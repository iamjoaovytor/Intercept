import SwiftUI

struct RequestListView: View {
    @Bindable var viewModel: ProxyViewModel

    var body: some View {
        Group {
            if viewModel.events.isEmpty {
                ContentUnavailableView(
                    viewModel.isRunning ? "Waiting for traffic" : "Proxy not running",
                    systemImage: viewModel.isRunning ? "antenna.radiowaves.left.and.right" : "play.circle",
                    description: Text(
                        viewModel.isRunning
                            ? "Configure your app to use localhost:\(viewModel.port)"
                            : "Press Start to begin capturing"
                    )
                )
            } else {
                List(viewModel.events, selection: $viewModel.selectedEventID) { event in
                    RequestRow(event: event)
                }
            }
        }
    }
}

// MARK: - RequestRow

struct RequestRow: View {
    let event: TrafficEvent

    var body: some View {
        HStack(spacing: 8) {
            Text("#\(event.sequenceNumber)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 30, alignment: .trailing)

            statusIndicator

            Text(event.request.method)
                .font(.system(.caption, design: .monospaced, weight: .semibold))
                .foregroundStyle(methodColor)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.host)
                    .font(.system(.body, design: .default, weight: .medium))
                    .lineLimit(1)
                Text(event.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let response = event.response {
                Text("\(response.statusCode)")
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(statusColor(response.statusCode))
            }

            if let duration = event.duration {
                Text(formatDuration(duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 55, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch event.state {
        case .inProgress:
            ProgressView()
                .controlSize(.small)
                .frame(width: 12, height: 12)
        case .completed:
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        }
    }

    private var methodColor: Color {
        switch event.request.method {
        case "GET": .blue
        case "POST": .orange
        case "PUT": .purple
        case "DELETE": .red
        case "PATCH": .teal
        default: .secondary
        }
    }

    private func statusColor(_ code: Int) -> Color {
        switch code {
        case 200..<300: .green
        case 300..<400: .blue
        case 400..<500: .orange
        case 500...: .red
        default: .secondary
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        if interval < 1 {
            return "\(Int(interval * 1000)) ms"
        }
        return String(format: "%.1f s", interval)
    }
}
