import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            List {
                Text("No requests yet")
                    .foregroundStyle(.secondary)
            }
            .navigationSplitViewColumnWidth(min: 250, ideal: 350)
        } detail: {
            Text("Select a request")
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Intercept")
    }
}

#Preview {
    ContentView()
}
