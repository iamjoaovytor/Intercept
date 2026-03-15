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
- **Dependencies** (via Xcode SPM): swift-nio (NIO, NIOHTTP1), swift-nio-ssl (NIOSSL), swift-certificates (X509)
- **App Sandbox**: disabled — proxy needs unrestricted network access

## Architecture

Three decoupled layers — see `docs/ARCHITECTURE.md` for full details including data flow and certificate flow diagrams.

1. **ProxyCore** (`Intercept/Intercept/ProxyCore/`) — SwiftNIO proxy server, TLS handlers, certificate generation, system proxy config. Zero UI dependencies. Key types: `ProxyServer` (lifecycle + `SequenceGenerator`), `HTTPProxyHandler` with `.httpProxy`/`.httpsRelay` modes + `ResponseCollector` (Handlers/), `RootCAManager` + `CertificateStore` (Certificate/), `SystemProxyManager` (SystemProxy/), `TrafficEvent` (Models/).
2. **TrafficStore** (`Intercept/Intercept/TrafficStore/`) — not yet implemented. Currently `ProxyViewModel` holds events in-memory directly.
3. **InterceptUI** (`Intercept/Intercept/Views/` + `ViewModels/`) — SwiftUI app target. `ProxyViewModel` (`@Observable`, `@MainActor`) owns `ProxyServer`, `SystemProxyManager`, event list, and filter state. `ContentView` has NavigationSplitView with toolbar. `RequestListView` shows captured traffic with inline filter bar (text search, method/status dropdowns). `RequestDetailView` shows headers/body with JSON formatting.

Data flows one direction: `ProxyServer` → `TrafficEvent` (value type, `@Sendable` closure) → `ProxyViewModel` (`@MainActor`) → SwiftUI Views.

## Concurrency Notes

- `ProxyServer` is `@unchecked Sendable` — uses `NSLock` for channel storage (not `NIOLockedValueBox`, unavailable in current NIO version)
- `HTTPProxyHandler` is `@unchecked Sendable` — NIO handlers are single-threaded per event loop
- `NSLock.withLock {}` instead of `lock()`/`unlock()` in async contexts
- Events cross from NIO threads to MainActor via `@Sendable` closure + `Task { @MainActor in }`
- `ChannelHandlerContext.write` still uses `wrapOutboundOut` (NIOAny deprecation warnings are expected)
- `UnsafeSendable<T>` wrapper used for `ChannelHandlerContext` captures in `@Sendable` closures (safe when accessed only from the event loop)
- CONNECT pipeline upgrade: `removeHandler(name:)` returns futures — must `whenAllComplete` before adding handlers with same names
- CONNECT 200 response must include `Content-Length: 0` to prevent chunked encoding from corrupting TLS handshake

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
