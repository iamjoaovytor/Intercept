import Foundation
import SwiftUI
import NIO

@MainActor
@Observable
final class ProxyViewModel {

    // MARK: - Filter Types

    enum MethodFilter: String, CaseIterable, Identifiable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case delete = "DELETE"
        case patch = "PATCH"

        var id: String { rawValue }
    }

    enum StatusFilter: String, CaseIterable, Identifiable {
        case success = "2xx"
        case redirect = "3xx"
        case clientError = "4xx"
        case serverError = "5xx"
        case failed = "Failed"

        var id: String { rawValue }

        func matches(_ event: TrafficEvent) -> Bool {
            switch self {
            case .success: event.response.map { (200..<300).contains($0.statusCode) } ?? false
            case .redirect: event.response.map { (300..<400).contains($0.statusCode) } ?? false
            case .clientError: event.response.map { (400..<500).contains($0.statusCode) } ?? false
            case .serverError: event.response.map { $0.statusCode >= 500 } ?? false
            case .failed: event.state == .failed
            }
        }
    }

    // MARK: - State

    private(set) var events: [TrafficEvent] = []
    private(set) var isRunning = false
    private(set) var error: String?

    var selectedEventID: TrafficEvent.ID?
    var searchText = ""
    var methodFilter: MethodFilter?
    var statusFilter: StatusFilter?

    var selectedEvent: TrafficEvent? {
        guard let id = selectedEventID else { return nil }
        return events.first { $0.id == id }
    }

    var filteredEvents: [TrafficEvent] {
        var result = events

        if let methodFilter {
            result = result.filter { $0.request.method == methodFilter.rawValue }
        }

        if let statusFilter {
            result = result.filter { statusFilter.matches($0) }
        }

        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.host.lowercased().contains(query)
                    || $0.path.lowercased().contains(query)
                    || $0.request.method.lowercased().contains(query)
            }
        }

        return result
    }

    var hasActiveFilters: Bool {
        methodFilter != nil || statusFilter != nil || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var server: ProxyServer?

    var port: Int = 8080

    func start() {
        guard !isRunning else { return }
        error = nil

        let config = ProxyServer.Configuration(port: port)
        let handler: @Sendable (TrafficEvent) -> Void = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleEvent(event)
            }
        }
        let server = ProxyServer(configuration: config, onEvent: handler)
        self.server = server

        Task {
            do {
                try await server.start()
                isRunning = true
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func stop() {
        guard isRunning else { return }

        Task {
            do {
                try await server?.stop()
            } catch {
                self.error = error.localizedDescription
            }
            server = nil
            isRunning = false
        }
    }

    func clear() {
        events.removeAll()
        selectedEventID = nil
    }

    func clearFilters() {
        searchText = ""
        methodFilter = nil
        statusFilter = nil
    }

    // MARK: - Private

    private func handleEvent(_ event: TrafficEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
        } else {
            events.append(event)
        }
    }
}
