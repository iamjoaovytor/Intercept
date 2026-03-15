import Foundation
import SwiftUI
import NIO

@MainActor
@Observable
final class ProxyViewModel {

    private(set) var events: [TrafficEvent] = []
    private(set) var isRunning = false
    private(set) var error: String?

    var selectedEventID: TrafficEvent.ID?

    var selectedEvent: TrafficEvent? {
        guard let id = selectedEventID else { return nil }
        return events.first { $0.id == id }
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

    // MARK: - Private

    private func handleEvent(_ event: TrafficEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id }) {
            events[index] = event
        } else {
            events.append(event)
        }
    }
}
