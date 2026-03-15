# Architecture

## Overview

Intercept is split into three layers that communicate through well-defined protocols. The proxy engine has zero dependencies on UI or persistence — it emits events that the other layers consume.

## Layers

### 1. ProxyCore (Swift Package)

The network engine. Runs a local proxy server using SwiftNIO.

**Responsibilities:**
- Listen for incoming HTTP/HTTPS connections
- Handle CONNECT tunneling for HTTPS
- Generate per-domain TLS certificates signed by a local root CA
- Forward requests to the destination server
- Emit `TrafficEvent` objects for each request/response pair

**Key Types:**
- `ProxyServer` — starts/stops the listener, manages connections
- `CertificateStore` — generates and caches TLS certificates
- `RootCAManager` — creates and installs the root CA in Keychain
- `HTTPHandler` — ChannelHandler for HTTP traffic
- `TLSHandler` — ChannelHandler for CONNECT + TLS interception
- `TrafficEvent` — value type representing a complete request/response

### 2. TrafficStore

In-memory store of captured traffic with optional SwiftData persistence.

**Responsibilities:**
- Receive `TrafficEvent` from ProxyCore
- Index for fast filtering (domain, method, status, content type)
- Provide `@Observable` collections for the UI
- Persist sessions to disk via SwiftData

**Key Types:**
- `TrafficSession` — a collection of events (one "capture session")
- `TrafficEntry` — enriched event with computed properties (duration, body size, etc.)
- `TrafficFilter` — predicate builder for filtering entries

### 3. InterceptUI (SwiftUI + AppKit)

The macOS frontend.

**Responsibilities:**
- Request list with virtual scrolling (NSTableView backed)
- Detail panel: headers, body viewer, timing
- JSON viewer with syntax highlighting
- Filter bar (domain, method, status code, text search)
- Toolbar controls: start/stop proxy, clear, export

## Data Flow

```
ProxyServer (SwiftNIO)
    │
    ▼
TrafficEvent (struct)
    │
    ▼
TrafficStore (@Observable)
    │
    ▼
SwiftUI Views (reactive binding)
```

## Certificate Flow (HTTPS)

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
│   ├── Views/
│   │   ├── ContentView.swift
│   │   ├── RequestListView.swift
│   │   ├── RequestDetailView.swift
│   │   ├── JSONViewer.swift
│   │   └── FilterBar.swift
│   ├── ViewModels/
│   │   ├── ProxyViewModel.swift
│   │   └── TrafficViewModel.swift
│   └── Resources/
├── ProxyCore/                  # Swift Package
│   ├── Sources/
│   │   ├── ProxyServer.swift
│   │   ├── Handlers/
│   │   │   ├── HTTPHandler.swift
│   │   │   └── TLSHandler.swift
│   │   ├── Certificate/
│   │   │   ├── RootCAManager.swift
│   │   │   └── CertificateStore.swift
│   │   └── Models/
│   │       └── TrafficEvent.swift
│   └── Tests/
├── TrafficStore/               # Swift Package
│   ├── Sources/
│   │   ├── TrafficStore.swift
│   │   ├── TrafficEntry.swift
│   │   ├── TrafficFilter.swift
│   │   └── TrafficSession.swift
│   └── Tests/
└── docs/
```
