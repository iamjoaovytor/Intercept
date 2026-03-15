import SwiftUI

struct RequestListView: View {
    @Bindable var viewModel: ProxyViewModel

    var body: some View {
        VStack(spacing: 0) {
            filterBar
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

            Divider()

            let filtered = viewModel.filteredEvents
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
                .frame(maxHeight: .infinity)
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    "No matching requests",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Try adjusting your filters")
                )
                .frame(maxHeight: .infinity)
            } else {
                List(filtered, selection: $viewModel.selectedEventID) { event in
                    RequestRow(event: event)
                }
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 6) {
            // Search field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                TextField("Filter…", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            // Method picker
            Menu {
                Button("All Methods") { viewModel.methodFilter = nil }
                Divider()
                ForEach(ProxyViewModel.MethodFilter.allCases) { method in
                    Button {
                        viewModel.methodFilter = method
                    } label: {
                        if viewModel.methodFilter == method {
                            Label(method.rawValue, systemImage: "checkmark")
                        } else {
                            Text(method.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(viewModel.methodFilter?.rawValue ?? "Method")
                        .font(.caption)
                        .foregroundStyle(viewModel.methodFilter != nil ? .primary : .secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    viewModel.methodFilter != nil ? Color.accentColor.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Status picker
            Menu {
                Button("All Status") { viewModel.statusFilter = nil }
                Divider()
                ForEach(ProxyViewModel.StatusFilter.allCases) { status in
                    Button {
                        viewModel.statusFilter = status
                    } label: {
                        if viewModel.statusFilter == status {
                            Label(status.rawValue, systemImage: "checkmark")
                        } else {
                            Text(status.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(viewModel.statusFilter?.rawValue ?? "Status")
                        .font(.caption)
                        .foregroundStyle(viewModel.statusFilter != nil ? .primary : .secondary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    viewModel.statusFilter != nil ? Color.accentColor.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Clear all filters
            if viewModel.hasActiveFilters {
                Button {
                    viewModel.clearFilters()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear all filters")
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
