import SwiftUI

struct RequestDetailView: View {
    let event: TrafficEvent

    @State private var selectedTab: Tab = .request

    enum Tab: String, CaseIterable {
        case request = "Request"
        case response = "Response"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Summary bar
            summaryBar

            Divider()

            // Tab picker
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)

            Divider()

            // Content
            ScrollView {
                switch selectedTab {
                case .request:
                    requestContent
                case .response:
                    responseContent
                }
            }
        }
    }

    // MARK: - Summary Bar

    private var summaryBar: some View {
        HStack(spacing: 12) {
            Text(event.request.method)
                .font(.system(.headline, design: .monospaced))

            if let statusCode = event.response?.statusCode {
                Text("\(statusCode)")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(statusColor(statusCode))
            }

            Text(event.request.url.absoluteString)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            if let duration = event.duration {
                Text(formatDuration(duration))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            stateIndicator
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch event.state {
        case .inProgress:
            ProgressView().controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    // MARK: - Request Tab

    private var requestContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            headersSection(title: "Request Headers", headers: event.request.headers)

            if let body = event.request.body, !body.isEmpty {
                bodySection(title: "Request Body", data: body, truncated: event.request.bodyTruncated)
            }
        }
        .padding()
    }

    // MARK: - Response Tab

    @ViewBuilder
    private var responseContent: some View {
        if let response = event.response {
            VStack(alignment: .leading, spacing: 16) {
                headersSection(title: "Response Headers", headers: response.headers)

                if let body = response.body, !body.isEmpty {
                    bodySection(title: "Response Body", data: body, truncated: response.bodyTruncated)
                }
            }
            .padding()
        } else if event.state == .failed {
            ContentUnavailableView(
                "Request Failed",
                systemImage: "exclamationmark.triangle",
                description: Text(event.error ?? "Unknown error")
            )
        } else {
            ContentUnavailableView(
                "Waiting for response",
                systemImage: "hourglass",
                description: Text("The request is still in progress")
            )
        }
    }

    // MARK: - Shared Components

    private func headersSection(title: String, headers: [TrafficEvent.Header]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    HStack(alignment: .top, spacing: 8) {
                        Text(header.name)
                            .font(.system(.caption, design: .monospaced, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(header.value)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func bodySection(title: String, data: Data, truncated: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Text(formatSize(data.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if truncated {
                    Text("(truncated)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Text(bodyString(from: data))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Helpers

    private func bodyString(from data: Data) -> String {
        // Try to pretty-print JSON
        if let json = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: pretty, encoding: .utf8) {
            return string
        }
        return String(data: data, encoding: .utf8) ?? "\(data.count) bytes (binary)"
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

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
