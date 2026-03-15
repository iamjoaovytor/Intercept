import Foundation
import NIO
import NIOHTTP1

// MARK: - HTTPProxyHandler

final class HTTPProxyHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let sequenceGenerator: SequenceGenerator
    private let onEvent: @Sendable (TrafficEvent) -> Void

    private var requestHead: HTTPRequestHead?
    private var requestBody: ByteBuffer?

    init(sequenceGenerator: SequenceGenerator, onEvent: @escaping @Sendable (TrafficEvent) -> Void) {
        self.sequenceGenerator = sequenceGenerator
        self.onEvent = onEvent
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            requestHead = head
            requestBody = context.channel.allocator.buffer(capacity: 0)
        case .body(var buffer):
            requestBody?.writeBuffer(&buffer)
        case .end:
            guard let head = requestHead else { return }
            forwardRequest(head: head, body: requestBody, context: context)
            requestHead = nil
            requestBody = nil
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }

    // MARK: - Request Forwarding

    private func forwardRequest(
        head: HTTPRequestHead,
        body: ByteBuffer?,
        context: ChannelHandlerContext
    ) {
        // CONNECT (HTTPS) is not supported yet
        if head.method == .CONNECT {
            writeError(.notImplemented, message: "HTTPS interception not yet supported", context: context)
            return
        }

        guard let url = URL(string: head.uri), let host = url.host() else {
            writeError(.badRequest, message: "Invalid proxy request URL", context: context)
            return
        }

        let port = url.port ?? 80

        // Build TrafficEvent
        let seq = sequenceGenerator.next()
        let requestHeaders = head.headers.map { TrafficEvent.Header(name: $0.name, value: $0.value) }
        let bodyData = extractBody(from: body)

        let trafficRequest = TrafficEvent.Request(
            method: head.method.rawValue,
            url: url,
            headers: requestHeaders,
            body: bodyData.data,
            bodyTruncated: bodyData.truncated
        )
        let event = TrafficEvent(sequenceNumber: seq, request: trafficRequest)

        // Rewrite request for upstream (relative URI, strip proxy headers)
        var forwardHead = head
        forwardHead.uri = relativePath(from: url)
        if !forwardHead.headers.contains(name: "Host") {
            forwardHead.headers.add(name: "Host", value: host)
        }
        forwardHead.headers.remove(name: "Proxy-Connection")
        forwardHead.headers.remove(name: "Proxy-Authorization")

        // Connect to upstream server
        let onEvent = self.onEvent

        ClientBootstrap(group: context.eventLoop)
            .channelInitializer { $0.pipeline.addHTTPClientHandlers() }
            .connect(host: host, port: port)
            .whenComplete { [weak self] result in
                guard let self, context.channel.isActive else { return }

                switch result {
                case .success(let upstream):
                    self.relay(
                        upstream: upstream,
                        head: forwardHead,
                        body: body,
                        event: event,
                        onEvent: onEvent,
                        context: context
                    )
                case .failure(let error):
                    var event = event
                    event.fail(with: "Connection failed: \(error.localizedDescription)")
                    onEvent(event)
                    self.writeError(.badGateway, message: "Connection failed", context: context)
                }
            }
    }

    private func relay(
        upstream: Channel,
        head: HTTPRequestHead,
        body: ByteBuffer?,
        event: TrafficEvent,
        onEvent: @escaping @Sendable (TrafficEvent) -> Void,
        context: ChannelHandlerContext
    ) {
        let responsePromise = context.eventLoop.makePromise(of: UpstreamResponse.self)

        upstream.pipeline.addHandler(ResponseCollector(promise: responsePromise)).whenSuccess {
            upstream.write(HTTPClientRequestPart.head(head), promise: nil)
            if let body, body.readableBytes > 0 {
                upstream.write(HTTPClientRequestPart.body(.byteBuffer(body)), promise: nil)
            }
            upstream.writeAndFlush(HTTPClientRequestPart.end(nil), promise: nil)
        }

        var event = event

        responsePromise.futureResult.whenComplete { [weak self] result in
            guard let self, context.channel.isActive else { return }

            switch result {
            case .success(let response):
                let respHeaders = response.head.headers.map {
                    TrafficEvent.Header(name: $0.name, value: $0.value)
                }
                let bodyData = self.extractBody(from: response.body)

                let trafficResponse = TrafficEvent.Response(
                    statusCode: Int(response.head.status.code),
                    reasonPhrase: response.head.status.reasonPhrase,
                    headers: respHeaders,
                    body: bodyData.data,
                    bodyTruncated: bodyData.truncated
                )
                event.complete(with: trafficResponse)
                onEvent(event)

                // Forward response to client
                context.write(self.wrapOutboundOut(.head(response.head)), promise: nil)
                if let body = response.body, body.readableBytes > 0 {
                    context.write(self.wrapOutboundOut(.body(.byteBuffer(body))), promise: nil)
                }
                context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)

            case .failure(let error):
                event.fail(with: error.localizedDescription)
                onEvent(event)
                self.writeError(.badGateway, message: "Upstream error", context: context)
            }
        }
    }

    // MARK: - Helpers

    private func relativePath(from url: URL) -> String {
        var path = url.path()
        if path.isEmpty { path = "/" }
        if let query = url.query {
            path += "?\(query)"
        }
        return path
    }

    private func extractBody(from buffer: ByteBuffer?) -> (data: Data?, truncated: Bool) {
        guard let buffer, buffer.readableBytes > 0 else {
            return (nil, false)
        }
        let data = Data(buffer.readableBytesView)
        if data.count > TrafficEvent.maxBodySize {
            return (data.prefix(TrafficEvent.maxBodySize), true)
        }
        return (data, false)
    }

    private func writeError(
        _ status: HTTPResponseStatus,
        message: String,
        context: ChannelHandlerContext
    ) {
        var headers = HTTPHeaders()
        let bodyBytes = Array(message.utf8)
        headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
        headers.add(name: "Content-Length", value: "\(bodyBytes.count)")
        headers.add(name: "Connection", value: "close")

        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        var buffer = context.channel.allocator.buffer(capacity: bodyBytes.count)
        buffer.writeBytes(bodyBytes)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)

        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            context.close(promise: nil)
        }
    }
}

// MARK: - Response Collector

private struct UpstreamResponse {
    let head: HTTPResponseHead
    let body: ByteBuffer?
}

private final class ResponseCollector: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart

    private let promise: EventLoopPromise<UpstreamResponse>
    private var head: HTTPResponseHead?
    private var body: ByteBuffer?

    init(promise: EventLoopPromise<UpstreamResponse>) {
        self.promise = promise
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let responseHead):
            head = responseHead
            body = context.channel.allocator.buffer(capacity: 0)
        case .body(var buffer):
            body?.writeBuffer(&buffer)
        case .end:
            guard let head else {
                promise.fail(ProxyError.noResponseHead)
                return
            }
            promise.succeed(UpstreamResponse(head: head, body: body))
            context.close(promise: nil)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        promise.fail(error)
        context.close(promise: nil)
    }
}

// MARK: - ProxyError

private enum ProxyError: Error, LocalizedError {
    case noResponseHead

    var errorDescription: String? {
        switch self {
        case .noResponseHead: "No response received from upstream server"
        }
    }
}
