import Foundation
import SystemConfiguration

final class SystemProxyManager: @unchecked Sendable {

    private var savedSettings: [String: ServiceProxyState] = [:]
    private let lock = NSLock()

    struct ServiceProxyState {
        let httpEnabled: Bool
        let httpHost: String
        let httpPort: Int
        let httpsEnabled: Bool
        let httpsHost: String
        let httpsPort: Int
    }

    // MARK: - Public

    /// Configures all active network services to use the given proxy.
    /// Saves current settings for later restoration.
    func enable(host: String, port: Int) throws {
        let services = try activeNetworkServices()

        lock.withLock {
            for service in services {
                if let state = try? currentProxyState(for: service) {
                    savedSettings[service] = state
                }
            }
        }

        for service in services {
            try run("networksetup", "-setwebproxy", service, host, String(port))
            try run("networksetup", "-setsecurewebproxy", service, host, String(port))
            try run("networksetup", "-setwebproxystate", service, "on")
            try run("networksetup", "-setsecurewebproxystate", service, "on")
        }

        print("[Intercept] System proxy enabled on \(services.joined(separator: ", "))")
    }

    /// Restores the original proxy settings saved during `enable()`.
    func disable() {
        let saved = lock.withLock {
            let copy = savedSettings
            savedSettings.removeAll()
            return copy
        }

        for (service, state) in saved {
            // Restore HTTP proxy
            if state.httpEnabled {
                _ = try? run("networksetup", "-setwebproxy", service, state.httpHost, String(state.httpPort))
                _ = try? run("networksetup", "-setwebproxystate", service, "on")
            } else {
                _ = try? run("networksetup", "-setwebproxystate", service, "off")
            }

            // Restore HTTPS proxy
            if state.httpsEnabled {
                _ = try? run("networksetup", "-setsecurewebproxy", service, state.httpsHost, String(state.httpsPort))
                _ = try? run("networksetup", "-setsecurewebproxystate", service, "on")
            } else {
                _ = try? run("networksetup", "-setsecurewebproxystate", service, "off")
            }
        }

        if !saved.isEmpty {
            print("[Intercept] System proxy restored for \(saved.keys.joined(separator: ", "))")
        }
    }

    // MARK: - Network Services

    private func activeNetworkServices() throws -> [String] {
        let output = try runCapture("networksetup", "-listallnetworkservices")
        return output
            .components(separatedBy: "\n")
            .dropFirst() // First line is a header
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") } // * = disabled
    }

    private func currentProxyState(for service: String) throws -> ServiceProxyState {
        let http = try parseProxyOutput(runCapture("networksetup", "-getwebproxy", service))
        let https = try parseProxyOutput(runCapture("networksetup", "-getsecurewebproxy", service))

        return ServiceProxyState(
            httpEnabled: http.enabled,
            httpHost: http.host,
            httpPort: http.port,
            httpsEnabled: https.enabled,
            httpsHost: https.host,
            httpsPort: https.port
        )
    }

    private func parseProxyOutput(_ output: String) throws -> (enabled: Bool, host: String, port: Int) {
        var enabled = false
        var host = ""
        var port = 0

        for line in output.components(separatedBy: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }

            switch parts[0].lowercased() {
            case "enabled": enabled = parts[1].lowercased() == "yes"
            case "server": host = parts[1]
            case "port": port = Int(parts[1]) ?? 0
            default: break
            }
        }

        return (enabled, host, port)
    }

    // MARK: - Shell

    @discardableResult
    private func run(_ args: String...) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = Array(args.dropFirst()) // first arg is "networksetup", skip it
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        // Actually, args includes "networksetup" as first element but we set executableURL directly
        process.arguments = Array(args.dropFirst())
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SystemProxyError.commandFailed(args.joined(separator: " "), process.terminationStatus)
        }
        return process
    }

    private func runCapture(_ args: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = Array(args.dropFirst())

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SystemProxyError.commandFailed(args.joined(separator: " "), process.terminationStatus)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Errors

enum SystemProxyError: Error, LocalizedError {
    case commandFailed(String, Int32)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let cmd, let status):
            "Command failed (status \(status)): \(cmd)"
        }
    }
}
