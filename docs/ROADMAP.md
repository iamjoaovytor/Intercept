# Roadmap

## Phase 1 — MVP (Core Proxy + Basic UI)

- [x] SwiftNIO proxy server listening on configurable port
- [x] HTTP request/response interception and forwarding
- [ ] HTTPS interception via CONNECT tunneling
- [ ] Root CA generation and Keychain installation
- [ ] Dynamic per-domain certificate generation
- [ ] System proxy auto-configuration (SystemConfiguration.framework)
- [x] Request list view with domain, method, status, duration
- [x] Request detail view with headers and body
- [x] JSON body viewer with syntax highlighting
- [ ] Basic filtering: domain, method, status code
- [x] Start/stop proxy toggle
- [x] Clear session

## Phase 2 — Power Features

- [ ] Breakpoints: pause and edit requests before forwarding
- [ ] Map Local: serve local files as responses
- [ ] Text search across all captured traffic
- [ ] Response body viewers: XML, HTML, image preview
- [ ] Request/response size and timing breakdown
- [ ] Session persistence with SwiftData
- [ ] Export session as HAR file

## Phase 3 — Polish

- [ ] HTTP/2 support
- [ ] WebSocket frame viewer
- [ ] Waterfall/timeline visualization
- [ ] Keyboard shortcuts for power users
- [ ] Appearance: light/dark theme support
- [ ] Menu bar quick access
- [ ] Diff between two responses
