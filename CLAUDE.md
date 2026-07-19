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
xcrun simctl launch "$SIM" com.chrsnv.checknet -openTool ping -host 1.1.1.1 -run 1
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

## Apple Human Interface Guidelines (HIG)
Follow Apple's HIG (https://developer.apple.com/design/human-interface-guidelines) — the app must feel native on iOS 26/macOS 26. Practical rules we hold to:
- **System components first.** Use `List`/`Form`/`NavigationStack`/`TabView`, standard `Toolbar` placements, `.confirmationDialog`/`.alert`, `.sheet` with `presentationDetents`. Don't rebuild what the system provides.
- **Respect Dynamic Type & accessibility.** Use semantic fonts (`.body`, `.caption`…), never hard-coded sizes for body text; give every icon-only control an `accessibilityLabel`; keep tap targets ≥44 pt; support light + dark via semantic colors (`Palette`).
- **Clear, reversible, consent-driven actions.** Destructive/ambiguous or network-intrusive actions (port/IP scanning) get a `.confirmationDialog` with a plain-language explanation and a cancel; never surprise the user. See `SensitiveConsentModifier`.
- **Explain, don't assume.** Every tool/check exposes an ⓘ description (`InfoButton`/`InfoSheet`) in its row and its screen toolbar so users know what will run before they run it.
- **Feedback & state.** Show progress (`ProgressView`), empty states (`ContentUnavailableView`), and errors inline; avoid janky custom animations (we removed the buggy pin "copy" animation in favor of a star badge).
- **Localization-ready.** Prefer `Text("…")` string literals (auto-localized) over `Text(verbatimString)`; wrap model strings with `LocalizedStringKey` at the call site. Right-to-left and long-translation layouts must not clip.

## Censorship checks policy — detection only
The **Блокировки** tab and `CensorshipChecks` are **transparency/diagnostics only**: they detect what the local network restricts (probe-vs-control). **Do NOT add any circumvention/DPI-bypass functionality** (SNI fragmentation, fake ClientHello, record-splitting, domain fronting, etc.) — checking a block is fine, defeating it is out of scope for this app.

## App structure
Root is a Liquid Glass `TabView` (`App/RootTabView.swift`): **Тесты** (tool catalog), **Блокировки** (censorship checks), **Настройки** (`AppSettings`: theme/language/saved-hosts/toggles). `AppSettings` + `SavedHostsStore` (IP vs domain split) are `@Observable` env objects.

## Device gotchas (simulator hides these)
- The sim skips **Local Network Privacy** + swallowed errors made tests look dead on device. Engines now emit terminal `.failed(reason)`; `HostResolver.resolve` has a hard timeout; `LocalNetworkPermission` triggers the prompt on launch; **all** browsed Bonjour types are in `NSBonjourServices` (explicit `App/Info.plist` via XcodeGen, `GENERATE_INFOPLIST_FILE: NO`).

## Status
**22 tools done (engine-tested + wired):** ping, traceroute, MTR, DNS lookup, DNS compare, DNS tamper, port scan, TLS inspector, host→IP, reverse DNS, interfaces, whois, DNSBL blacklist, Wake-on-LAN, MTU discovery, IP-range scanner, Bonjour/mDNS, CGNAT/NAT, monitoring, network browser, **speed test (iperf3)**, plus the **Блокировки** censorship suite (DNS spoof / IP / SNI-RST / HTTP block-page / whitelist / Siberian throttle — `CensorshipChecks` + `DoHClient`, probe-vs-control).
**Speed test:** pure-Swift iperf3 protocol client (`IperfClient`) + auto server list (`IperfServerList`, export.iperf3serverlist.net) + ping preview + Cloudflare HTTP fallback (`CloudflareSpeedTest`). iperf3 handshake verified against real servers (ACCESS_DENIED parsed); full runs need a free server + unthrottled net.
**Platform features:** App Intents/Shortcuts, Widget, Live Activity + Dynamic Island, history + CSV/JSON export, app-group store.
**UX layer:** every tool/check has an ⓘ description sheet (`InfoButton`) in its row and screen toolbar; pinned tools show a star (buggy copy-animation removed); saved hosts/domains bookmark menu (`SavedHostsMenu`) is available in every host-input tool; scanning tools (port/IP scan) gate behind a consent `.confirmationDialog` (`SensitiveConsentModifier`, toggle in Settings). DNS-tamper is hidden from the main catalog (it lives in **Блокировки**).
**Speed test geo:** `IperfServerList` merges curated ErTelecom (Дом.ру) `st.<city>.ertelecom.ru` endpoints into the auto-updated public index; picker groups by geography (user's country first, then continent), shows link bandwidth (`bandwidthLabel`), and auto-selects the nearest reachable server in the user's region.
**MTR:** rewritten WinMTR-style — each cycle fires all TTL probes and collects replies in one shared window (fast cycles), stable hop count, per-hop Sent/Recv/Loss/Best/Avg/Worst/Last (`MTRSession`). *Needs on-device ICMP verification.*
**Not built — third-party API or iOS-restricted:** IP geolocation, World Ping (need external API); Wi-Fi RSSI/channel (iOS-restricted; CoreWLAN on macOS); network-browser MAC/vendor on iOS (`rt_msghdr2` macOS-only); bufferbloat (needs a load server — could layer on the speed test).
**Localization:** `AppLanguage` offers system + the popular App Store languages; UI uses `.environment(\.locale)`. Strings are Russian literals acting as `Localizable.xcstrings` keys — English + other languages are translated in the String Catalog. Point of care: `Text(model.string)` is verbatim (not localized) — wrap model strings in `LocalizedStringKey` at the call site. Full per-language coverage needs an Xcode build to compile the catalog and audit remaining literals.
