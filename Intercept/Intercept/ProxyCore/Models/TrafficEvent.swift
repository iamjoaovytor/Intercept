import Foundation

// MARK: - TrafficEvent

/// A captured HTTP request/response pair flowing through the proxy.
/// This is the core data contract between ProxyCore, TrafficStore, and UI.
struct TrafficEvent: Sendable, Identifiable, Equatable {

    let id: UUID
    let sequenceNumber: Int
    let startedAt: Date
    var completedAt: Date?

    let request: Request
    var response: Response?
    var state: State
    var error: String?
    var tlsInfo: TLSInfo?

    var duration: TimeInterval? {
        guard let completedAt else { return nil }
        return completedAt.timeIntervalSince(startedAt)
    }

    var host: String {
        request.url.host() ?? request.url.absoluteString
    }

    var path: String {
        request.url.path()
    }

    init(
        id: UUID = UUID(),
        sequenceNumber: Int,
        startedAt: Date = .now,
        request: Request
    ) {
        self.id = id
        self.sequenceNumber = sequenceNumber
        self.startedAt = startedAt
        self.completedAt = nil
        self.request = request
        self.response = nil
        self.state = .inProgress
        self.error = nil
        self.tlsInfo = nil
    }
}

// MARK: - Nested Types

extension TrafficEvent {

    enum State: Sendable, Equatable {
        case inProgress
        case completed
        case failed
    }

    struct Request: Sendable, Equatable {
        let method: String
        let url: URL
        let headers: [Header]
        let body: Data?
        let bodyTruncated: Bool

        init(method: String, url: URL, headers: [Header], body: Data? = nil, bodyTruncated: Bool = false) {
            self.method = method
            self.url = url
            self.headers = headers
            self.body = body
            self.bodyTruncated = bodyTruncated
        }
    }

    struct Response: Sendable, Equatable {
        let statusCode: Int
        let reasonPhrase: String
        let headers: [Header]
        let body: Data?
        let bodyTruncated: Bool

        init(statusCode: Int, reasonPhrase: String, headers: [Header], body: Data? = nil, bodyTruncated: Bool = false) {
            self.statusCode = statusCode
            self.reasonPhrase = reasonPhrase
            self.headers = headers
            self.body = body
            self.bodyTruncated = bodyTruncated
        }
    }

    struct Header: Sendable, Equatable {
        let name: String
        let value: String
    }

    struct TLSInfo: Sendable, Equatable {
        let protocolVersion: String?
        let cipherSuite: String?
    }
}

// MARK: - Constants

extension TrafficEvent {
    /// Maximum body size stored in memory (10 MB). Bodies exceeding this are truncated.
    static let maxBodySize = 10 * 1024 * 1024
}

// MARK: - Mutations

extension TrafficEvent {

    mutating func complete(with response: Response, at date: Date = .now) {
        self.response = response
        self.completedAt = date
        self.state = .completed
    }

    mutating func fail(with error: String, at date: Date = .now) {
        self.error = error
        self.completedAt = date
        self.state = .failed
    }
}
