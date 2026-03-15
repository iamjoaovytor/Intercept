# Intercept

A native macOS HTTP/HTTPS debugging proxy built with Swift.

Intercept sits between your app and the network, letting you inspect, filter, and modify every request and response in real time.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **HTTP/HTTPS Interception** — Man-in-the-middle proxy with dynamic certificate generation
- **Real-time Request List** — Browse all captured traffic with filtering by domain, method, and status code
- **JSON Viewer** — Syntax-highlighted, collapsible JSON body inspector
- **Request Detail** — Headers, body, timing, and TLS info at a glance
- **System Proxy** — Automatically configures macOS proxy settings
- **Breakpoints** — Pause, inspect, and modify requests before they hit the server
- **Map Local** — Serve local JSON files as API responses for testing

## Tech Stack

| Component | Technology |
|-----------|------------|
| Proxy Engine | SwiftNIO |
| TLS / Certificates | Security.framework + CryptoKit |
| UI | SwiftUI + AppKit (NSTableView for performance) |
| Persistence | SwiftData |

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  Client App  │────▶│  Intercept   │────▶│   Server    │
│  (iOS Sim)   │◀────│  Proxy Core  │◀────│  (API)      │
└─────────────┘     └──────┬───────┘     └─────────────┘
                           │
                    ┌──────┴───────┐
                    │   SwiftUI    │
                    │   Frontend   │
                    └──────────────┘
```

### Modules

- **ProxyCore** — SwiftNIO-based proxy server, TLS handling, certificate generation
- **TrafficStore** — In-memory + SwiftData persistence of captured requests
- **InterceptUI** — SwiftUI views, request list, detail panels, filters

## Requirements

- macOS 14+
- Xcode 16+
- Swift 6.0

## License

MIT
