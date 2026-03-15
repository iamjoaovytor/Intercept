import Foundation
import NIO
import NIOHTTP1

// MARK: - ProxyServer

final class ProxyServer: @unchecked Sendable {

    struct Configuration: Sendable {
        let host: String
        let port: Int

        init(host: String = "127.0.0.1", port: Int = 8080) {
            self.host = host
            self.port = port
        }
    }

    let configuration: Configuration
    private let group: MultiThreadedEventLoopGroup
    private var _serverChannel: Channel?
    private let lock = NSLock()
    private let sequenceGenerator = SequenceGenerator()
    private let eventHandler: @Sendable (TrafficEvent) -> Void

    init(
        configuration: Configuration = .init(),
        onEvent: @escaping @Sendable (TrafficEvent) -> Void
    ) {
        self.configuration = configuration
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        self.eventHandler = onEvent
    }

    func start() async throws {
        let seqGen = sequenceGenerator
        let onEvent = eventHandler

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(.backlog, value: 256)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(
                        HTTPProxyHandler(sequenceGenerator: seqGen, onEvent: onEvent)
                    )
                }
            }
            .childChannelOption(.socketOption(.so_reuseaddr), value: 1)

        let channel = try await bootstrap.bind(
            host: configuration.host,
            port: configuration.port
        ).get()

        lock.withLock { _serverChannel = channel }
    }

    func stop() async throws {
        let channel = lock.withLock {
            let current = _serverChannel
            _serverChannel = nil
            return current
        }

        if let channel {
            try await channel.close()
        }
        try await group.shutdownGracefully()
    }

    var localAddress: SocketAddress? {
        lock.withLock { _serverChannel?.localAddress }
    }
}

// MARK: - SequenceGenerator

final class SequenceGenerator: @unchecked Sendable {
    private var counter = 0
    private let lock = NSLock()

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        counter += 1
        return counter
    }
}
