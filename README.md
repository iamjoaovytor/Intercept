# Intercept

A native macOS HTTP/HTTPS debugging proxy built with Swift.

Intercept sits between your apps and the network, letting you inspect, filter, and modify every HTTP/HTTPS request and response in real time. Works with any application — browsers, iOS simulators, CLI tools, and more.

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-6.0-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **HTTP/HTTPS Interception** — MITM proxy with dynamic per-domain certificate generation
- **Real-time Traffic List** — Browse captured requests with filtering by text, method, and status code
- **Request Detail** — Headers and body with JSON auto-formatting
- **System Proxy** — Automatically configures/restores macOS proxy settings
- **HAR Export** — Export captured traffic as HAR 1.2 files

## Tech Stack

| Component | Technology |
|-----------|------------|
| Proxy Engine | SwiftNIO |
| TLS / Certificates | Security.framework + CryptoKit + swift-certificates |
| UI | SwiftUI |

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  Any App    │────▶│  Intercept   │────▶│   Server    │
│  (Browser,  │◀────│  Proxy Core  │◀────│  (API)      │
│  Simulator, │     └──────┬───────┘     └─────────────┘
│  CLI, etc.) │            │
└─────────────┘     ┌──────┴───────┐
                    │   SwiftUI    │
                    │   Frontend   │
                    └──────────────┘
```

### Modules

- **ProxyCore** — SwiftNIO-based proxy server, TLS handling, certificate generation
- **TrafficStore** — In-memory event storage (SwiftData persistence planned)
- **InterceptUI** — SwiftUI views, request list, detail panels, filters

## Requirements

- macOS 14+
- Xcode 16+
- Swift 6.0

## License

MIT
