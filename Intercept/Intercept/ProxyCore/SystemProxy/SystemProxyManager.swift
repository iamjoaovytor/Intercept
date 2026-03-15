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
    /// Uses AppleScript to request admin privileges (shows macOS password dialog).
    func enable(host: String, port: Int) throws {
        let services = try activeNetworkServices()

        lock.withLock {
            for service in services {
                if let state = try? currentProxyState(for: service) {
                    savedSettings[service] = state
                }
            }
        }

        var commands: [String] = []
        for service in services {
            let escaped = service.replacingOccurrences(of: "'", with: "'\\''")
            commands.append("networksetup -setwebproxy '\\(escaped)' \\(host) \\(port)")
            commands.append("networksetup -setsecurewebproxy '\\(escaped)' \\(host) \\(port)")
            commands.append("networksetup -setwebproxystate '\\(escaped)' on")
            commands.append("networksetup -setsecurewebproxystate '\\(escaped)' on")
        }

        try runWithAdmin(commands.joined(separator: " && "))
    }

    /// Restores the original proxy settings saved during `enable()`.
    func disable() {
        let saved = lock.withLock {
            let copy = savedSettings
            savedSettings.removeAll()
            return copy
        }

        guard !saved.isEmpty else { return }

        var commands: [String] = []
        for (service, state) in saved {
            let escaped = service.replacingOccurrences(of: "'", with: "'\\''")

            if state.httpEnabled {
                commands.append("networksetup -setwebproxy '\\(escaped)' \\(state.httpHost) \\(state.httpPort)")
                commands.append("networksetup -setwebproxystate '\\(escaped)' on")
            } else {
                commands.append("networksetup -setwebproxystate '\\(escaped)' off")
            }

            if state.httpsEnabled {
                commands.append("networksetup -setsecurewebproxy '\\(escaped)' \\(state.httpsHost) \\(state.httpsPort)")
                commands.append("networksetup -setsecurewebproxystate '\\(escaped)' on")
            } else {
                commands.append("networksetup -setsecurewebproxystate '\\(escaped)' off")
            }
        }

        _ = try? runWithAdmin(commands.joined(separator: " && "))
    }

    // MARK: - Network Services

    private func activeNetworkServices() throws -> [String] {
        let output = try runCapture("-listallnetworkservices")
        return output
            .components(separatedBy: "\n")
            .dropFirst() // First line is a header
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") } // * = disabled
    }

    private func currentProxyState(for service: String) throws -> ServiceProxyState {
        let http = try parseProxyOutput(runCapture("-getwebproxy", service))
        let https = try parseProxyOutput(runCapture("-getsecurewebproxy", service))

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

    /// Runs a shell command with admin privileges via AppleScript.
    /// Shows the native macOS authentication dialog.
    @discardableResult
    private func runWithAdmin(_ command: String) throws -> String {
        let script = "do shell script \"\(command)\" with administrator privileges"
        guard let appleScript = NSAppleScript(source: script) else {
            throw SystemProxyError.scriptCreationFailed
        }

        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)

        if let error {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw SystemProxyError.adminCommandFailed(message)
        }

        return result.stringValue ?? ""
    }

    /// Runs networksetup without admin (for read-only queries).
    private func runCapture(_ args: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SystemProxyError.commandFailed(
                "networksetup \(args.joined(separator: " "))",
                process.terminationStatus
            )
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// MARK: - Errors

enum SystemProxyError: Error, LocalizedError {
    case commandFailed(String, Int32)
    case scriptCreationFailed
    case adminCommandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let cmd, let status):
            "Command failed (status \(status)): \(cmd)"
        case .scriptCreationFailed:
            "Failed to create AppleScript"
        case .adminCommandFailed(let message):
            "Admin command failed: \(message)"
        }
    }
}
