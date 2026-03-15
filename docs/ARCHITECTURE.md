# Architecture

## Overview

Intercept is split into three layers that communicate through well-defined protocols. The proxy engine has zero dependencies on UI or persistence — it emits events that the other layers consume.

## Layers

### 1. ProxyCore

The network engine. Runs a local proxy server using SwiftNIO.

**Responsibilities:**
- Listen for incoming HTTP/HTTPS connections
- Handle CONNECT tunneling for HTTPS (planned)
- Generate per-domain TLS certificates signed by a local root CA (planned)
- Forward requests to the destination server
- Emit `TrafficEvent` objects for each request/response pair

**Key Types:**
- `ProxyServer` — starts/stops the listener, manages connections (`@unchecked Sendable`, uses `NSLock`)
- `SequenceGenerator` — thread-safe sequential ID generator
- `HTTPProxyHandler` — ChannelInboundHandler that receives client requests, connects to upstream via `ClientBootstrap`, and relays traffic
- `ResponseCollector` — ChannelInboundHandler that accumulates upstream response parts and fulfills a promise
- `TrafficEvent` — `Sendable` value type representing a request/response pair with state transitions (`.inProgress` → `.completed`/`.failed`)

**Not yet implemented:**
- `CertificateStore` — generates and caches TLS certificates
- `RootCAManager` — creates and installs the root CA in Keychain
- `TLSHandler` — ChannelHandler for CONNECT + TLS interception

### 2. TrafficStore (planned)

In-memory store of captured traffic with optional SwiftData persistence. Currently `ProxyViewModel` holds events directly.

**Planned types:**
- `TrafficSession` — a collection of events (one "capture session")
- `TrafficEntry` — enriched event with computed properties (duration, body size, etc.)
- `TrafficFilter` — predicate builder for filtering entries

### 3. InterceptUI (SwiftUI)

The macOS frontend.

**Current implementation:**
- `ProxyViewModel` — `@Observable`, `@MainActor` view model that owns `ProxyServer` and event list
- `ContentView` — NavigationSplitView with toolbar (start/stop, clear, status indicator)
- `RequestListView` — list of captured traffic with method, host, path, status code, duration
- `RequestDetailView` — tabbed view (Request/Response) showing headers and body with JSON auto-formatting

**Not yet implemented:**
- Filter bar (domain, method, status code, text search)
- NSTableView-backed list for performance at scale
- JSON viewer with collapsible tree

## Data Flow

```
ProxyServer (SwiftNIO event loop threads)
    │
    ▼
TrafficEvent (struct, Sendable)
    │  @Sendable closure + Task { @MainActor }
    ▼
ProxyViewModel (@Observable, @MainActor)
    │
    ▼
SwiftUI Views (reactive binding)
```

## Certificate Flow (HTTPS) — planned

```
1. Client sends CONNECT example.com:443
2. Intercept accepts the CONNECT, responds 200
3. RootCAManager provides root CA (created on first launch)
4. CertificateStore generates cert for example.com signed by root CA
5. TLS handshake with client using generated cert
6. TLS handshake with real server using system trust
7. Traffic flows through, decrypted on both sides
```

## Package Structure

```
Intercept/
├── Intercept.xcodeproj
├── Intercept/                  # Main app target
│   ├── InterceptApp.swift
│   ├── ContentView.swift
│   ├── Views/
│   │   ├── RequestListView.swift
│   │   └── RequestDetailView.swift
│   ├── ViewModels/
│   │   └── ProxyViewModel.swift
│   ├── ProxyCore/
│   │   ├── ProxyServer.swift
│   │   ├── Handlers/
│   │   │   └── HTTPHandler.swift
│   │   ├── Certificate/        # (empty, planned)
│   │   └── Models/
│   │       └── TrafficEvent.swift
│   ├── TrafficStore/           # (empty, planned)
│   └── Resources/
└── docs/
```
