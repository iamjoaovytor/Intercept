import Foundation

/// Exports captured traffic events as HAR 1.2 (HTTP Archive) JSON.
enum HARExporter {

    static func export(_ events: [TrafficEvent]) throws -> Data {
        let entries = events.compactMap { harEntry(from: $0) }

        let har: [String: Any] = [
            "log": [
                "version": "1.2",
                "creator": [
                    "name": "Intercept",
                    "version": "1.0"
                ],
                "entries": entries
            ]
        ]

        return try JSONSerialization.data(withJSONObject: har, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - Private

    private static func harEntry(from event: TrafficEvent) -> [String: Any]? {
        let request = harRequest(from: event.request)
        let response = harResponse(from: event.response)
        let timeMs = (event.duration ?? 0) * 1000

        var entry: [String: Any] = [
            "startedDateTime": iso8601(event.startedAt),
            "time": round(timeMs * 100) / 100,
            "request": request,
            "response": response,
            "cache": [:] as [String: Any],
            "timings": [
                "send": -1,
                "wait": round(timeMs * 100) / 100,
                "receive": -1
            ]
        ]

        if let tls = event.tlsInfo {
            entry["_tlsVersion"] = tls.protocolVersion ?? ""
            entry["_tlsCipher"] = tls.cipherSuite ?? ""
        }

        return entry
    }

    private static func harRequest(from request: TrafficEvent.Request) -> [String: Any] {
        var result: [String: Any] = [
            "method": request.method,
            "url": request.url.absoluteString,
            "httpVersion": "HTTP/1.1",
            "headers": harHeaders(request.headers),
            "queryString": harQueryString(from: request.url),
            "headersSize": -1,
            "bodySize": request.body?.count ?? 0
        ]

        if let body = request.body, !body.isEmpty {
            let mimeType = request.headers.first { $0.name.lowercased() == "content-type" }?.value ?? "application/octet-stream"
            result["postData"] = [
                "mimeType": mimeType,
                "text": String(data: body, encoding: .utf8) ?? "",
                "size": body.count
            ]
        }

        return result
    }

    private static func harResponse(from response: TrafficEvent.Response?) -> [String: Any] {
        guard let response else {
            return [
                "status": 0,
                "statusText": "",
                "httpVersion": "HTTP/1.1",
                "headers": [] as [[String: String]],
                "content": ["size": 0, "mimeType": ""],
                "headersSize": -1,
                "bodySize": 0,
                "redirectURL": ""
            ]
        }

        let mimeType = response.headers.first { $0.name.lowercased() == "content-type" }?.value ?? ""
        var content: [String: Any] = [
            "size": response.body?.count ?? 0,
            "mimeType": mimeType
        ]

        if let body = response.body {
            if let text = String(data: body, encoding: .utf8) {
                content["text"] = text
            } else {
                content["text"] = body.base64EncodedString()
                content["encoding"] = "base64"
            }
        }

        let redirectURL = response.headers.first { $0.name.lowercased() == "location" }?.value ?? ""

        return [
            "status": response.statusCode,
            "statusText": response.reasonPhrase,
            "httpVersion": "HTTP/1.1",
            "headers": harHeaders(response.headers),
            "content": content,
            "headersSize": -1,
            "bodySize": response.body?.count ?? 0,
            "redirectURL": redirectURL
        ]
    }

    private static func harHeaders(_ headers: [TrafficEvent.Header]) -> [[String: String]] {
        headers.map { ["name": $0.name, "value": $0.value] }
    }

    private static func harQueryString(from url: URL) -> [[String: String]] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return [] }
        return (components.queryItems ?? []).map {
            ["name": $0.name, "value": $0.value ?? ""]
        }
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
