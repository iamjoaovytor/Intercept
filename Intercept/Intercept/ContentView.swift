import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = ProxyViewModel()
    @State private var showingExporter = false

    var body: some View {
        NavigationSplitView {
            RequestListView(viewModel: viewModel)
                .navigationSplitViewColumnWidth(min: 300, ideal: 420)
        } detail: {
            if let event = viewModel.selectedEvent {
                RequestDetailView(event: event)
            } else {
                ContentUnavailableView(
                    "Select a request",
                    systemImage: "network",
                    description: Text("Choose a request from the sidebar to inspect it")
                )
            }
        }
        .navigationTitle("Intercept")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    if viewModel.isRunning {
                        viewModel.stop()
                    } else {
                        viewModel.start()
                    }
                } label: {
                    Image(systemName: viewModel.isRunning ? "stop.fill" : "play.fill")
                    Text(viewModel.isRunning ? "Stop" : "Start")
                }
                .tint(viewModel.isRunning ? .red : .green)

                Button {
                    showingExporter = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(viewModel.events.isEmpty)
                .help("Export as HAR")

                Button {
                    viewModel.clear()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(viewModel.events.isEmpty)
            }

            ToolbarItem(placement: .status) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isRunning ? .green : .secondary)
                        .frame(width: 8, height: 8)
                    Text(viewModel.isRunning ? "Port \(viewModel.port)" : "Stopped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if viewModel.hasActiveFilters {
                        Text("\(viewModel.filteredEvents.count)/\(viewModel.events.count) requests")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(viewModel.events.count) requests")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: HARDocument(events: viewModel.hasActiveFilters ? viewModel.filteredEvents : viewModel.events),
            contentType: .json,
            defaultFilename: "intercept-\(exportTimestamp).har"
        ) { _ in }
    }

    private var exportTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}

#Preview {
    ContentView()
}
