# Intercept — Project Guidelines

## What is this

Native macOS HTTP/HTTPS debugging proxy built in Swift. Portfolio project + daily driver for iOS development.

## Tech Stack

- **Proxy Engine**: SwiftNIO
- **TLS/Certs**: Security.framework + CryptoKit
- **UI**: SwiftUI with AppKit (NSTableView) for performance-critical lists
- **Persistence**: SwiftData
- **Target**: macOS 14+, Swift 6.0, Xcode 16+

## Architecture

Three decoupled layers:
1. **ProxyCore** (Swift Package) — proxy server, TLS, certificates
2. **TrafficStore** (Swift Package) — in-memory + persisted traffic data
3. **InterceptUI** — SwiftUI app target

See `docs/ARCHITECTURE.md` for details.

## Code Guidelines

- ProxyCore must have zero UI dependencies
- All proxy events flow through `TrafficEvent` value types
- Use `@Observable` for view models, not `ObservableObject`
- Prefer `async/await` over callbacks
- Strict concurrency: `Sendable` compliance, no data races
- Test proxy logic independently from UI

## Git Conventions

- Conventional commits: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`
- Do not include "Claude Code" in commit messages
- Branch naming: `feat/description`, `fix/description`

## Dependencies

- [swift-nio](https://github.com/apple/swift-nio) — async networking
- [swift-nio-ssl](https://github.com/apple/swift-nio-ssl) — TLS support
- [swift-certificates](https://github.com/apple/swift-certificates) — X.509 certificate handling
