import SwiftUI
import UniformTypeIdentifiers

struct HARDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let events: [TrafficEvent]

    init(events: [TrafficEvent]) {
        self.events = events
    }

    init(configuration: ReadConfiguration) throws {
        self.events = []
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try HARExporter.export(events)
        return FileWrapper(regularFileWithContents: data)
    }
}
