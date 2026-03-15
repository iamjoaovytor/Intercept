# Architecture

## Overview

Intercept is split into three layers that communicate through well-defined protocols. The proxy engine has zero dependencies on UI or persistence — it emits events that the other layers consume.

## Layers

### 1. ProxyCore

The network engine. Runs a local proxy server using SwiftNIO.

**Responsibilities:**
- Listen for incoming HTTP/HTTPS connections
- Handle CONNECT tunneling for HTTPS with TLS interception
- Generate per-domain TLS certificates signed by a local root CA
- Forward requests to the destination server
- Configure/restore macOS system proxy settings
- Emit `TrafficEvent` objects for each request/response pair

**Key Types:**
- `ProxyServer` — starts/stops the listener, manages connections (`@unchecked Sendable`, uses `NSLock`)
- `SequenceGenerator` — thread-safe sequential ID generator
- `HTTPProxyHandler` — ChannelInboundHandler with two modes: `.httpProxy` (plain HTTP) and `.httpsRelay` (decrypted HTTPS). Handles CONNECT by upgrading the channel pipeline to TLS.
- `ResponseCollector` — ChannelInboundHandler that accumulates upstream response parts and fulfills a promise
- `TrafficEvent` — `Sendable` value type representing a request/response pair with state transitions (`.inProgress` → `.completed`/`.failed`)
- `RootCAManager` — generates, persists, and installs the root CA in Keychain with trust settings
- `CertificateStore` — generates and caches per-host TLS certificates signed by the root CA
- `SystemProxyManager` — enables/disables macOS system HTTP/HTTPS proxy via `networksetup`, saves and restores original settings. `disable()` tries without admin first (macOS caches auth ~5 min), falls back to admin prompt only if needed.

### 2. TrafficStore (planned)

In-memory store of captured traffic with optional SwiftData persistence. Currently `ProxyViewModel` holds events directly.

**Planned types:**
- `TrafficSession` — a collection of events (one "capture session")
- `TrafficEntry` — enriched event with computed properties (duration, body size, etc.)
- `TrafficFilter` — predicate builder for filtering entries

### 3. InterceptUI (SwiftUI)

The macOS frontend.

**Current implementation:**
- `ProxyViewModel` — `@Observable`, `@MainActor` view model that owns `ProxyServer`, `SystemProxyManager`, event list, and filter state
- `ContentView` — NavigationSplitView with toolbar (start/stop, clear, status indicator with filtered count)
- `RequestListView` — list of captured traffic with inline filter bar (text search, method dropdown, status dropdown)
- `RequestDetailView` — tabbed view (Request/Response) showing headers and body with JSON auto-formatting

**Not yet implemented:**
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

## Certificate Flow (HTTPS)

```
1. Client sends CONNECT example.com:443
2. HTTPProxyHandler responds 200 (with Content-Length: 0 to avoid chunked framing)
3. Pipeline upgraded: HTTP codecs removed, NIOSSLServerHandler added
4. RootCAManager provides root CA (created + Keychain-installed on first launch)
5. CertificateStore generates P-256 ECDSA cert for example.com signed by root CA
6. TLS handshake with client using generated cert (TLS 1.2+)
7. New HTTPProxyHandler (.httpsRelay) added with fresh HTTP codecs after TLS
8. Upstream connection uses NIOSSLClientHandler with system trust
9. Traffic flows through, decrypted on both sides
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
│   │   ├── Certificate/
│   │   │   ├── RootCAManager.swift
│   │   │   └── CertificateStore.swift
│   │   ├── SystemProxy/
│   │   │   └── SystemProxyManager.swift
│   │   └── Models/
│   │       └── TrafficEvent.swift
│   ├── TrafficStore/           # (empty, planned)
│   └── Resources/
└── docs/
```
