import Foundation
@preconcurrency import NIO
@preconcurrency import NIOHTTP1
@preconcurrency import NIOSSL

// MARK: - Sendable Wrapper

/// Wraps a non-Sendable value for use in @Sendable closures.
/// Safe when the value is only accessed from a single NIO event loop.
private struct UnsafeSendable<T>: @unchecked Sendable {
    let value: T
}

// MARK: - HTTPProxyHandler

final class HTTPProxyHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    enum Mode {
        case httpProxy
        case httpsRelay(host: String, port: Int)
    }

    private let mode: Mode
    private let sequenceGenerator: SequenceGenerator
    private let certificateStore: CertificateStore
    private let onEvent: @Sendable (TrafficEvent) -> Void

    private var requestHead: HTTPRequestHead?
    private var requestBody: ByteBuffer?

    init(
        mode: Mode = .httpProxy,
        sequenceGenerator: SequenceGenerator,
        certificateStore: CertificateStore,
        onEvent: @escaping @Sendable (TrafficEvent) -> Void
    ) {
        self.mode = mode
        self.sequenceGenerator = sequenceGenerator
        self.certificateStore = certificateStore
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
            if head.method == .CONNECT {
                handleConnect(head: head, context: context)
            } else {
                forwardRequest(head: head, body: requestBody, context: context)
            }
            requestHead = nil
            requestBody = nil
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("[Intercept] errorCaught (\(mode)): \(error)")
        context.close(promise: nil)
    }

    // MARK: - CONNECT (HTTPS Tunneling)

    private func handleConnect(head: HTTPRequestHead, context: ChannelHandlerContext) {
        let parts = head.uri.split(separator: ":")
        guard let hostPart = parts.first else {
            writeError(.badRequest, message: "Invalid CONNECT target", context: context)
            return
        }
        let host = String(hostPart)
        let port = parts.count > 1 ? Int(parts[1]) ?? 443 : 443

        // Send 200 Connection Established, then upgrade pipeline after flush completes.
        // Content-Length: 0 prevents HTTPResponseEncoder from using chunked encoding,
        // which would add a "0\r\n\r\n" terminator that corrupts the TLS handshake.
        var response = HTTPResponseHead(version: .http1_1, status: .ok)
        response.headers.add(name: "Content-Length", value: "0")
        context.write(wrapOutboundOut(.head(response)), promise: nil)

        let flushPromise = context.eventLoop.makePromise(of: Void.self)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: flushPromise)

        print("[Intercept] CONNECT \(host):\(port) — sending 200, will upgrade pipeline")
        let wrappedCtx = UnsafeSendable(value: context)
        flushPromise.futureResult.whenComplete { [weak self] _ in
            guard let self else { return }
            print("[Intercept] 200 flushed, upgrading pipeline for \(host)")
            self.upgradePipelineForTLS(host: host, port: port, context: wrappedCtx.value)
        }
    }

    private func upgradePipelineForTLS(host: String, port: Int, context: ChannelHandlerContext) {
        let pipeline = context.pipeline
        let channel = context.channel
        let certStore = self.certificateStore
        let seqGen = self.sequenceGenerator
        let onEvent = self.onEvent

        // removeHandler(name:) is async — must wait for all removals before adding
        // handlers with the same names, otherwise the add fails with a name conflict
        EventLoopFuture.whenAllComplete([
            pipeline.removeHandler(name: "http-proxy-handler"),
            pipeline.removeHandler(name: "http-response-encoder"),
            pipeline.removeHandler(name: "http-request-decoder"),
        ], on: context.eventLoop).whenSuccess { _ in
            do {
                print("[Intercept] handlers removed, building TLS context for \(host)")
                let tlsConfig = try certStore.tlsConfiguration(forHost: host)
                let sslContext = try NIOSSLContext(configuration: tlsConfig)

                try pipeline.syncOperations.addHandler(
                    NIOSSLServerHandler(context: sslContext), name: "tls-server"
                )
                try pipeline.syncOperations.addHandler(
                    ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes)),
                    name: "http-request-decoder"
                )
                try pipeline.syncOperations.addHandler(
                    HTTPResponseEncoder(), name: "http-response-encoder"
                )
                try pipeline.syncOperations.addHandler(
                    HTTPProxyHandler(
                        mode: .httpsRelay(host: host, port: port),
                        sequenceGenerator: seqGen,
                        certificateStore: certStore,
                        onEvent: onEvent
                    ),
                    name: "http-proxy-handler"
                )
                print("[Intercept] TLS pipeline ready for \(host)")
            } catch {
                print("[Intercept] TLS pipeline upgrade FAILED for \(host): \(error)")
                channel.close(promise: nil)
            }
        }
    }

    // MARK: - Request Forwarding

    private func forwardRequest(
        head: HTTPRequestHead,
        body: ByteBuffer?,
        context: ChannelHandlerContext
    ) {
        let resolved: (host: String, port: Int, url: URL)

        switch mode {
        case .httpProxy:
            guard let url = URL(string: head.uri), let host = url.host() else {
                writeError(.badRequest, message: "Invalid proxy request URL", context: context)
                return
            }
            resolved = (host, url.port ?? 80, url)

        case .httpsRelay(let host, let port):
            let portSuffix = port == 443 ? "" : ":\(port)"
            guard let url = URL(string: "https://\(host)\(portSuffix)\(head.uri)") else {
                writeError(.badRequest, message: "Invalid request URL", context: context)
                return
            }
            resolved = (host, port, url)
        }

        // Build TrafficEvent
        let seq = sequenceGenerator.next()
        let requestHeaders = head.headers.map { TrafficEvent.Header(name: $0.name, value: $0.value) }
        let bodyData = extractBody(from: body)

        let trafficRequest = TrafficEvent.Request(
            method: head.method.rawValue,
            url: resolved.url,
            headers: requestHeaders,
            body: bodyData.data,
            bodyTruncated: bodyData.truncated
        )
        let event = TrafficEvent(sequenceNumber: seq, request: trafficRequest)

        // Rewrite request for upstream
        var forwardHead = head
        if case .httpProxy = mode {
            forwardHead.uri = relativePath(from: resolved.url)
        }
        if !forwardHead.headers.contains(name: "Host") {
            forwardHead.headers.add(name: "Host", value: resolved.host)
        }
        forwardHead.headers.remove(name: "Proxy-Connection")
        forwardHead.headers.remove(name: "Proxy-Authorization")

        // Connect to upstream server
        let onEvent = self.onEvent
        let wrappedContext = UnsafeSendable(value: context)

        connectToUpstream(host: resolved.host, port: resolved.port, eventLoop: context.eventLoop)
            .whenComplete { [weak self] result in
                let ctx = wrappedContext.value
                guard let self, ctx.channel.isActive else { return }

                switch result {
                case .success(let upstream):
                    self.relay(
                        upstream: upstream,
                        head: forwardHead,
                        body: body,
                        event: event,
                        onEvent: onEvent,
                        context: ctx
                    )
                case .failure(let error):
                    var event = event
                    event.fail(with: "Connection failed: \(error.localizedDescription)")
                    onEvent(event)
                    self.writeError(.badGateway, message: "Connection failed", context: ctx)
                }
            }
    }

    private func connectToUpstream(
        host: String,
        port: Int,
        eventLoop: any EventLoop
    ) -> EventLoopFuture<Channel> {
        let bootstrap = ClientBootstrap(group: eventLoop)

        switch mode {
        case .httpProxy:
            return bootstrap
                .channelInitializer { channel in
                    do {
                        try channel.pipeline.syncOperations.addHandler(HTTPRequestEncoder())
                        try channel.pipeline.syncOperations.addHandler(ByteToMessageHandler(HTTPResponseDecoder()))
                        return channel.eventLoop.makeSucceededVoidFuture()
                    } catch {
                        return channel.eventLoop.makeFailedFuture(error)
                    }
                }
                .connect(host: host, port: port)

        case .httpsRelay:
            return bootstrap
                .channelInitializer { channel in
                    do {
                        let tlsConfig = TLSConfiguration.makeClientConfiguration()
                        let sslContext = try NIOSSLContext(configuration: tlsConfig)
                        let sslHandler = try NIOSSLClientHandler(context: sslContext, serverHostname: host)
                        try channel.pipeline.syncOperations.addHandler(sslHandler)
                        try channel.pipeline.syncOperations.addHandler(HTTPRequestEncoder())
                        try channel.pipeline.syncOperations.addHandler(ByteToMessageHandler(HTTPResponseDecoder()))
                        return channel.eventLoop.makeSucceededVoidFuture()
                    } catch {
                        return channel.eventLoop.makeFailedFuture(error)
                    }
                }
                .connect(host: host, port: port)
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

        do {
            try upstream.pipeline.syncOperations.addHandler(ResponseCollector(promise: responsePromise))
            upstream.write(HTTPClientRequestPart.head(head), promise: nil)
            if let body, body.readableBytes > 0 {
                upstream.write(HTTPClientRequestPart.body(.byteBuffer(body)), promise: nil)
            }
            upstream.writeAndFlush(HTTPClientRequestPart.end(nil), promise: nil)
        } catch {
            responsePromise.fail(error)
        }

        var event = event
        let wrappedContext = UnsafeSendable(value: context)

        responsePromise.futureResult.whenComplete { [weak self] result in
            let ctx = wrappedContext.value
            guard let self, ctx.channel.isActive else { return }

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
                ctx.write(self.wrapOutboundOut(.head(response.head)), promise: nil)
                if let body = response.body, body.readableBytes > 0 {
                    ctx.write(self.wrapOutboundOut(.body(.byteBuffer(body))), promise: nil)
                }
                ctx.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)

            case .failure(let error):
                event.fail(with: error.localizedDescription)
                onEvent(event)
                self.writeError(.badGateway, message: "Upstream error", context: ctx)
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

        let wrappedCtx = UnsafeSendable(value: context)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            wrappedCtx.value.close(promise: nil)
        }
    }
}

// MARK: - Response Collector

private struct UpstreamResponse: Sendable {
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
