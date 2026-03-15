# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is this

Native macOS HTTP/HTTPS debugging proxy built in Swift. Sits between apps and the network to inspect, filter, and modify HTTP/HTTPS traffic in real time. Works with browsers, iOS simulators, CLI tools, etc.

## Build & Test Commands

This is an Xcode project (not a standalone Swift Package). All commands use the `Intercept` scheme.

```bash
# Build
xcodebuild -project Intercept/Intercept.xcodeproj -scheme Intercept -destination 'platform=macOS' build

# Run all unit tests
xcodebuild -project Intercept/Intercept.xcodeproj -scheme Intercept -destination 'platform=macOS' test

# Run a single test (Swift Testing framework)
xcodebuild -project Intercept/Intercept.xcodeproj -scheme Intercept -destination 'platform=macOS' test -only-testing:InterceptTests/InterceptTests/example

# Run UI tests
xcodebuild -project Intercept/Intercept.xcodeproj -scheme Intercept -destination 'platform=macOS' test -only-testing:InterceptUITests
```

Tests use Swift Testing (`import Testing`, `@Test`) not XCTest.

## Tech Stack

- **Target**: macOS 14+, Swift 6.0, Xcode 16+
- **Proxy Engine**: SwiftNIO
- **TLS/Certs**: Security.framework + CryptoKit
- **UI**: SwiftUI with AppKit (NSTableView) for performance-critical lists
- **Persistence**: SwiftData
- **Dependencies** (via Xcode SPM): swift-nio-ssl (NIOSSL), swift-certificates (X509)

## Architecture

Three decoupled layers — see `docs/ARCHITECTURE.md` for full details including data flow and certificate flow diagrams.

1. **ProxyCore** (`Intercept/Intercept/ProxyCore/`) — SwiftNIO proxy server, TLS handlers, certificate generation. Zero UI dependencies. Key types: `ProxyServer`, `CertificateStore`, `RootCAManager`, `HTTPHandler`, `TLSHandler`, `TrafficEvent`.
2. **TrafficStore** (`Intercept/Intercept/TrafficStore/`) — in-memory + SwiftData persistence. Receives `TrafficEvent` from ProxyCore, provides `@Observable` collections. Key types: `TrafficSession`, `TrafficEntry`, `TrafficFilter`.
3. **InterceptUI** (`Intercept/Intercept/Views/` + `ViewModels/`) — SwiftUI app target with the main window, request list, detail panels, filters.

Data flows one direction: `ProxyServer` → `TrafficEvent` (value type) → `TrafficStore` (@Observable) → SwiftUI Views.

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
