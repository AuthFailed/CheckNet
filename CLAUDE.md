# CheckNet — project guide

Native **iOS + macOS** network-diagnostics app ("сетевой комбайн"). SwiftUI, Russian UI, iOS-26 system look (light + dark). Design reference: *NetTool iOS* — a clean system-list tool catalog with per-tool screens.

## Golden rule
**Test each check before shipping it.** Networking logic lives in a UI-free package and is unit-tested against real hosts on macOS. Only after an engine's tests pass do we wire it to a screen and flip `Tool.isImplemented`. Keep the app polished and bug-free; unimplemented tools show a "скоро" placeholder, never a half-working check.

## Environment
- `xcode-select` points at CommandLineTools (no `xcodebuild`/simulators). **Xcode 26.6 is at `/Applications/Xcode.app`.** Prefix build/test/sim commands with:
  ```sh
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  ```
  (no sudo). `swift build` works without it; `swift test` needs it (XCTest).
- Network egress works in this sandbox (ICMP, DNS, TCP, TLS all reachable) — real hosts are testable.
- iPhone 17 Pro simulator UDID: `195ED81D-E86E-4CAF-8C83-B326C657B68D`.

## Layout
```
Packages/NetworkKit/    # UI-free engines + XCTest suite (the tested core)
  Sources/NetworkKit/{Support,Ping,DNS,TLS,Port,Info}/
  Tests/NetworkKitTests/
App/                    # SwiftUI app, imports NetworkKit
  Catalog/  Ping/  DNS/  Port/  TLS/  Info/  Common/  Store/
project.yml             # XcodeGen source of truth (the .xcodeproj is generated & gitignored)
```

## Commands
```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# Core engine tests (run these after any NetworkKit change)
cd Packages/NetworkKit && swift test

# (Re)generate the Xcode project — REQUIRED after adding files/folders under App/
xcodegen generate

# Build for simulator
xcodebuild -project CheckNet.xcodeproj -scheme CheckNet \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build build

# Install / launch / screenshot
SIM=195ED81D-E86E-4CAF-8C83-B326C657B68D
xcrun simctl install "$SIM" build/Build/Products/Debug-iphonesimulator/CheckNet.app
xcrun simctl launch "$SIM" com.checknet.app -openTool ping -host 1.1.1.1 -run 1
xcrun simctl io "$SIM" screenshot screens/out.png
```
Deep-link launch args (also the Shortcuts groundwork): `-openTool <toolRawValue> [-host <h>] [-run]`, parsed in `App/Catalog/CatalogView.swift` → `LaunchOptions`.

## Adding a tool
1. Add engine + models under `Packages/NetworkKit/Sources/NetworkKit/<Area>/`; keep it `Sendable`, async/await, no UIKit/SwiftUI.
2. Add a test in `Tests/NetworkKitTests/` hitting a real host; `swift test` must pass.
3. Add a screen under `App/<Area>/` using shared UI in `App/Common/` (`HostInputBar`, `RunButton`, `.card()`, `InfoRow`, `Palette`, `Sparkline`, `PulseRing`).
4. Route it in `ToolDestinationView` and add the case to `Tool.isImplemented`.
5. `xcodegen generate`, build, screenshot, verify.

## Conventions
- Swift 6 language mode, `@Observable` view models (`@MainActor`), structured concurrency.
- Low-level sockets: `SOCK_DGRAM` ICMP (unprivileged, works on iOS). Reusable primitives in `Support/` (`TCPTransport`, `UDPExchange`, `SocketFactory`, `ResolvedEndpoint`, `MonoClock`).
- iOS lacks `SecCertificateCopyValues`/`kSecOID*` → cert fields come from the hand-written `X509` DER parser.
- Commits: **Conventional Commits**, clear scope, no AI/tooling attribution.

## Status
Done (tested + wired): Ping, DNS lookup, Port scan, TLS inspector, Host→IP, Reverse DNS, Interfaces.
Engine tested, screen pending: DNS resolver-compare, DNS tamper detect.
Next (self-contained, no third-party API): traceroute, MTR, whois (TCP 43), DNSBL blacklist (DNS), MTU discovery, CGNAT/double-NAT (traceroute + STUN), IP-range scanner, network browser + mDNS/Bonjour + MAC-vendor OUI, Wake-on-LAN, history + CSV/JSON export, App Intents/Shortcuts, Widgets, Live Activities/Dynamic Island, background monitoring + local notifications.
Needs external API or restricted on iOS (deferred): IP geolocation, World Ping, deep Wi-Fi RSSI/channel (iOS-restricted; more on macOS), server-based speed test.
