# CheckNet — development roadmap

Goal: **the best network-diagnostics app on Apple platforms** — native on iPhone, iPad and Mac,
honest in its explanations, with checks the competition lacks (Speedtest, Network Analyzer, iNetTools).

Tasks live in [Issues](https://github.com/AuthFailed/CheckNet/issues) and are grouped by milestone.
This file is about **order and dependencies**: why M2 comes before M3, and M4 before M6.

---

## Where we are now

Updated 2026-07-23. **M1–M4 and M6 are closed; M5 (platform integrations) remains.** Below is the
actual state; the milestone tables further down mark each task separately in a "Status" column.

- **27 tools** implemented; **no "coming soon" placeholders left**. Two Wi-Fi tools
  work on macOS only (CoreWLAN); on iOS they show a "available on Mac" placeholder.
  Added in this milestone: bufferbloat (#46), IP geolocation and World Ping (#47), Wi-Fi on macOS (#48).
- **Core** `Packages/NetworkKit` — **207 XCTest tests** against real hosts and parsers
  (DNS/X.509/MMDB parsers and geolocation covered deterministically). In CI: deterministic ones
  as a blocking gate, network ones informationally (see "How the tests run in CI").
- **App + Shared** — ~11,000 lines; a **`CheckNetTests` target (119 tests)** now covers
  App/Shared logic (M4 #37). Pure pieces (`HostSharing`, `IPAddress`, `LaunchArguments`,
  `ScheduleRule`, `HistoryCSV`, the `CheckRecord` and `ToolRunModel` factories) were moved to `Shared/`.
- **Localization** — string catalog, 13 languages. The second category remains: engine strings
  looked up through `LocalizedStringKey(variable)` that stay in the source language in every locale
  (issue #60).
- **iPad/macOS** — the adaptive layout is in place: `NavigationSplitView` + `.sidebarAdaptable`,
  a single `ToolScaffold` with a width constraint, `MenuBarExtra` / commands / a Settings scene on Mac,
  landscape on iPhone (M2 #14–#19 closed).
- **Haptics** are in (`App/Common/Haptics.swift` + a toggle in settings); accessibility improved —
  status is conveyed by shape and word, not color alone, and icons got labels (#20, #21);
  Dynamic Type, reduce-motion and `numericText` are polished (M3 closed).
- The Home Screen widget was **deliberately removed**: the extension publishes the Live Activity and
  user-added controls (#41), but nothing goes into the Home Screen gallery; after install the
  app imposes nothing.

---

## The order logic

```
M1 Stabilization ─┬─→ M2 Adaptive UI ──→ M3 UX polish
                  │            │                 │
                  └─→ M4 Architecture and tests ─┘
                               │
                               ├─→ M5 Platform integrations
                               ├─→ M6 New tools
                               └─→ M7 VPN tools ──→ M8 App Store release
                                                            ▲
   Release quality (cross-cutting, feed into M8):  M9 Design redesign ····┤
                                                   M10 Translations and tone ·┘

   After M8, forward-looking:  M11 Competitive edge and design leadership
```

**Milestone status:** M1 ✅ · M2 ✅ · M3 ✅ · M4 ✅ · M5 almost closed (#39–#44 ✅, P3 #45 remains) · M6 ✅ (tools done; #49 is a living idea backlog) · **M7 ✅** (the section for VPN operators is complete: #70–#79) · **M8 📋 planned** (App Store preparation and release) · **M9 📋** (design redesign: macOS + VPN + unified language) · **M10 📋** (translations and tone) · **M11 📋** (competitive edge and design leadership).

- **M1 first** — it holds the release blockers (privacy manifest), a data-loss bug (a race in the
  history) and a broken CI. Building new things on an unstable foundation costs more.
- **M2 before M3** — `ToolScaffold` and `NavigationSplitView` rewrite the frame of all 22 screens.
  Polishing empty states and animations before that means redoing the work twice.
- **M4 in parallel with M2/M3** — `ToolRunModel` and `ToolScaffold` are two halves of one refactor;
  moving logic into NetworkKit makes it testable.
- **M5 and M6 after M4** — new tools and background flows sit on `CheckRunner`,
  unified error handling and `ToolScaffold`, otherwise every new screen again copies 200 lines.

---

## M1 · Stabilization and release ✅

Without this the app cannot ship: App Store blockers, data loss, an unlocalized UI.

**Status: complete ✅** (all tasks closed).

| # | Task | Priority | Status |
|---|---|---|---|
| [#5](https://github.com/AuthFailed/CheckNet/issues/5) | `PrivacyInfo.xcprivacy` — App Store review blocker | P0 | ✅ |
| [#6](https://github.com/AuthFailed/CheckNet/issues/6) | CI: run `swift test` and build macOS | P0 | ✅ |
| [#7](https://github.com/AuthFailed/CheckNet/issues/7) | Fix the macOS target build | P0 | ✅ |
| [#8](https://github.com/AuthFailed/CheckNet/issues/8) | History: CSV/JSON export runs in `body` | P0 | ✅ |
| [#9](https://github.com/AuthFailed/CheckNet/issues/9) | History: hardcoded `ru_RU` locale | P0 | ✅ |
| [#10](https://github.com/AuthFailed/CheckNet/issues/10) | 46 untranslated keys in the string catalog | P0 | ✅ |
| [#11](https://github.com/AuthFailed/CheckNet/issues/11) | `SharedStore`: race when writing history | P0 | ✅ |
| [#13](https://github.com/AuthFailed/CheckNet/issues/13) | Network profiles don't work without the Wi-Fi entitlement | P1 | ✅ |

**Order within the milestone:** #7 → #6 (CI can't build a broken target) → the rest in parallel.

---

## M2 · Adaptive UI (iPad + macOS) ✅

The biggest visual debt. Right now it's a "stretched iPhone" on every wide screen.

**Status: complete ✅** (all tasks closed).

| # | Task | Priority | Status |
|---|---|---|---|
| [#14](https://github.com/AuthFailed/CheckNet/issues/14) | `NavigationSplitView` + `.tabViewStyle(.sidebarAdaptable)` | P1 | ✅ |
| [#15](https://github.com/AuthFailed/CheckNet/issues/15) | `ToolScaffold` — a single container with a width constraint | P1 | ✅ |
| [#16](https://github.com/AuthFailed/CheckNet/issues/16) | Fixed widths/heights that break Dynamic Type | P1 | ✅ |
| [#17](https://github.com/AuthFailed/CheckNet/issues/17) | Sheets without `presentationDetents` | P2 | ✅ |
| [#18](https://github.com/AuthFailed/CheckNet/issues/18) | macOS: `MenuBarExtra`, `.commands`, `Settings` scene | P1 | ✅ |
| [#19](https://github.com/AuthFailed/CheckNet/issues/19) | Landscape on iPhone | P2 | ✅ |

**Order:** #15 (the frame) → #14 (navigation on top of it) → #16 → #17/#19 → #18 (depends on #7).

---

## M3 · UX polish ✅

What separates "it works" from "it's pleasant to use".

**Status: complete ✅** (all tasks closed). Most were closed by early PRs; the last one done was
Dynamic Type (#22) — the only remaining hardcoded font size.

| # | Task | Priority | Status |
|---|---|---|---|
| [#20](https://github.com/AuthFailed/CheckNet/issues/20) | Haptics — currently 0 calls in the whole project | P1 | ✅ |
| [#21](https://github.com/AuthFailed/CheckNet/issues/21) | Accessibility: status by color only, icons without labels | P1 | ✅ |
| [#22](https://github.com/AuthFailed/CheckNet/issues/22) | Dynamic Type: 39 hardcoded `.font(.system(size:))` | P1 | ✅ |
| [#23](https://github.com/AuthFailed/CheckNet/issues/23) | Unified error handling + "Retry" | P1 | ✅ |
| [#24](https://github.com/AuthFailed/CheckNet/issues/24) | Idle states on 12 screens | P2 | ✅ |
| [#25](https://github.com/AuthFailed/CheckNet/issues/25) | Search: synonyms in the catalog, search in history | P2 | ✅ |
| [#26](https://github.com/AuthFailed/CheckNet/issues/26) | Reduce motion and `numericText` | P2 | ✅ |
| [#27](https://github.com/AuthFailed/CheckNet/issues/27) | Pull-to-refresh on lists | P3 | ✅ |
| [#28](https://github.com/AuthFailed/CheckNet/issues/28) | Screens without ⓘ and asymmetry in Blocking | P2 | ✅ |
| [#29](https://github.com/AuthFailed/CheckNet/issues/29) | The placeholder doesn't explain why a tool is unavailable | P2 | ✅ |
| [#30](https://github.com/AuthFailed/CheckNet/issues/30) | Onboarding and pre-permission for the local network | P2 | ✅ |
| [#31](https://github.com/AuthFailed/CheckNet/issues/31) | `onTapGesture` instead of `NavigationLink` | P2 | ✅ |

**Order:** #23 (unified phase/error) → #20 and #24 sit on it → #21/#22 → the rest.

---

## M4 · Architecture and tests ✅

Removes duplication and closes the riskiest uncovered code.

**Status: complete ✅** (6 of 7 closed; for #32 the building block is in place, the migration is a
separate step, see below).

| # | Task | Priority | Status |
|---|---|---|---|
| [#35](https://github.com/AuthFailed/CheckNet/issues/35) | Tests for `X509Parser` (hand-written DER) | P1 | ✅ |
| [#36](https://github.com/AuthFailed/CheckNet/issues/36) | Tests for `DNSMessage`, including the pointer loop | P1 | ✅ |
| [#37](https://github.com/AuthFailed/CheckNet/issues/37) | `CheckNetTests` target for `App/` and `Shared/` | P1 | ✅ |
| [#33](https://github.com/AuthFailed/CheckNet/issues/33) | Move `BlockingCheck.run` into NetworkKit | P1 | ✅ |
| [#34](https://github.com/AuthFailed/CheckNet/issues/34) | Duplication: `CheckRecord`, `PingConfig`, persistence | P2 | ✅ |
| [#38](https://github.com/AuthFailed/CheckNet/issues/38) | Uncovered NetworkKit engines | P2 | ✅ |
| [#32](https://github.com/AuthFailed/CheckNet/issues/32) | `ToolRunModel<T>` — collapse ~15 models | P2 | 🔨 partial |

**What's done (in `main`):**
- #36 — `DNSMessage.readName` rejects compression pointers that don't point "strictly backward"
  (loops/forward/at itself), caps the name at 255 bytes, forbids reserved label lengths; +15 tests.
- #35 — string parsing by tag (BMPString/Teletex), UTCTime by the RFC 5280 century rule, SAN parsing
  (shown on a leaf certificate); +17 tests with real RSA/EC fixtures and fuzzing.
- #37 — App's pure logic was moved to `Shared/` and covered by the `CheckNetTests` target (51 tests);
  CSV escaping is now RFC 4180 across all columns.
- #33 — check dispatch in `CensorshipCheckKind` (NetworkKit); Intents/scheduler no longer depend on
  the UI.
- #34 — `PingConfig` presets, `CheckRecord` factories, `UserDefaults.json/setJSON`.
- #38 — the ICMP checksum (RFC 1071 vector) and packet parsing; +19 tests.
- #32 — the **building block** `RunPhase` + `ToolRunModel<Value>` in `Shared/` (with tests).

**Remaining on #32:** migrating ~15 models onto `ToolRunModel`. It was meant to go together with #15
(`ToolScaffold`), but #15 is already closed, so this is a separate mechanical step: the screens
already use `ToolScaffold`, and the migration comes down to swapping the internals of each model. The
models are heterogeneous — ~8 one-shot (`run() async throws`) and ~7 streaming (`start()/stop()` with
progress).

**Order (as done):** #35/#36 (security and hang risk) → #37 → #33 → #34 → #38 → #32.

---

## M5 · Platform integrations — in progress

This is where the app stops being "a utility you open by hand".

| # | Task | Priority | Status |
|---|---|---|---|
| [#39](https://github.com/AuthFailed/CheckNet/issues/39) | Background monitoring via `BGTask` | P1 | ✅ |
| [#40](https://github.com/AuthFailed/CheckNet/issues/40) | Notifications: actions, time-sensitive, foreground | P2 | ✅ |
| [#41](https://github.com/AuthFailed/CheckNet/issues/41) | Control Center + Lock Screen widgets | P2 | ✅ |
| [#42](https://github.com/AuthFailed/CheckNet/issues/42) | Siri: donating intents, host `AppEntity` | P2 | ✅ |
| [#43](https://github.com/AuthFailed/CheckNet/issues/43) | iCloud sync, Handoff, Spotlight | P2 | ✅ |
| [#44](https://github.com/AuthFailed/CheckNet/issues/44) | Focus filters, interactive Live Activity | P3 | ✅ |
| [#45](https://github.com/AuthFailed/CheckNet/issues/45) | watchOS and visionOS — investigation | P3 | |

**Order:** #39 → #40 (notifications only make sense with a working background) → #41/#42 → #43 → #44/#45.
The order is soft: #42 was taken before the background tasks as pure code that is unit-testable — it
needs no on-device check, unlike `BGTask`/notifications.

**#42 done:** saved hosts became `SavedHostEntity` (`EntityStringQuery`) — in Shortcuts and Siri the
user picks their favorites by name, and any address can be entered manually; a manual ping donates
`PingHostIntent` to `IntentDonationManager` so the system suggests it on the Lock Screen and in
Spotlight. Matching and the codec were moved to `Shared/SavedHostsPersistence.swift` (a single
storage key for the store and the query) and covered by unit tests in `CheckNetTests`.

**#44 done:** the **interactive Live Activity** — the ping activity (Lock Screen + expanded Dynamic
Island) gained a "Stop" button (`StopPingLiveActivityIntent: LiveActivityIntent`, `#if os(iOS)`) that,
through a shared generation counter (`LiveActivitySignal`, app group), signals the ping loop to
finish; a baseline is captured on start, so an old tap doesn't kill a new run. The **Focus filter** —
`MonitorFocusFilter: SetFocusFilterIntent` (cross-platform) mutes monitoring alerts in the chosen
focus, persisting the choice in `FocusMonitorState`, which `HostNotifier.post` reads (both foreground
and background). Both flags are pure and covered by tests; real focus switching is verified only on
device.

**Live Activity generalized (beyond #44).** There used to be only the ping activity; now a single
`CheckActivityAttributes` (status + title + subtitle + up to three chips, `kind` → icon and button)
serves any long-running check. The controller and widget were renamed to `CheckActivityController` /
`CheckLiveActivityWidget`, and formatting was moved into pure `PingActivityContent` /
`MonitorActivityContent` (unit tests). **Monitoring** now shows a live activity (an "N/M online"
aggregate, worst status → color, Online/Not responding/Hosts chips), updated from the foreground loop
and from `BackgroundMonitor` (by enumerating activities). At the same time `MonitoringManager` was
raised to the app level (`@Environment`) — monitoring used to die when you left the screen; now it
runs the whole session, and orphaned activities are killed on start.

**Live Activity extended to every runnable tool — 22 of them.**
- *Long-running* (live Dynamic Island): ping, monitoring, speed test (Mbit/s + phase),
  bufferbloat (phase/RTT → an A–F grade with color), MTR (target latency/loss/round), traceroute,
  port and IP scan (an "X/Y" progress + found), World Ping and network overview (progress), Bonjour
  (service count), MTU (probe size → path MTU).
- *One-shot* (result held for 90s on the Lock Screen): host→IP, reverse DNS, DNS lookup/compare/
  tamper, whois, TLS, blacklists, CGNAT, IP geolocation.

Scalability: the activity is wired into `ToolRunModel` itself (a seam for ~10 one-shot tools — they
set a short `ActivityDescriptor` + a phase→view mapper; `LookupActivityContent` renders "running /
result / error", and a per-result status paints an expired cert / a listing / a spoof red).
Progress scans share `ScanActivityContent`. Content was moved into pure builders in `Shared/` and
covered by unit tests; `kind` → an icon in the widget. A race was found and fixed: a model's `start()`
first calls `stop()`, and the async end from `stop()` was killing the just-created activity — we moved
to **a separate controller per run**. Deliberately without an activity: Wake-on-LAN (a synchronous,
instant send — nothing to show), the interface list, and the iOS Wi-Fi placeholders. Verified on the
simulator: the MTR activity in Dynamic Island (compact "30 hops" + expanded view), and the creation of
a lookup activity confirmed in the log.

**#39 + #40 done:** **background** — `BackgroundMonitor` (`BGAppRefreshTask`, id
`com.chrsnv.checknet.monitor.refresh` in `BGTaskSchedulerPermittedIdentifiers`, `UIBackgroundModes:
fetch`) re-runs the same checks as the foreground monitoring while the app is unloaded; it registers
in `init`, schedules on going to background and when monitoring is enabled. **Notifications** —
`HostNotifier` provides a `HOST_STATUS` category with "Open" / "Check again" actions,
foreground banner display (delegate) and a time-sensitive level for outages (gracefully degrading to
`.active` without the paid entitlement). The decision "whether to send and what" was moved into pure
`Shared/MonitorNotification.swift` (a transition matrix: the first measurement is silent, ok↔degraded
flapping is silent, only down/recovery alerts), and host records into a shared `Shared/MonitorStore.swift`;
all covered by unit tests. iOS-only (`BGTaskScheduler` isn't on macOS — the foreground loop stays
there). Real wake-up by the system and delivery are verified only on device; here — the build,
logic tests and a clean start with the task registered on the simulator.

**#43 done:** **Handoff** — the open tool is advertised as an `NSUserActivity`
(`com.chrsnv.checknet.tool`, `Shared/ToolActivity.swift`, declared in `NSUserActivityTypes`) with the
host; the receiving side resolves through the same `navigator.open` as Spotlight and the controls.
**iCloud host sync** is written (`App/Store/CloudHostSync.swift`, `NSUbiquitousKeyValueStore`
+ a pure `SavedHostMerge.union` merge, covered by tests) but **dormant**: `isAvailable = false`,
because the `ubiquity-kvstore-identifier` entitlement is only signed by a paid account — the same
barrier as Wi-Fi (`CurrentNetwork.isSSIDReadable`); settings honestly show "Unavailable" with an
explanation. The flag and the entitlement are enabled in a single commit. **Spotlight** was closed
earlier (`acc7a6f`). Cross-device Handoff/iCloud are verified only on a pair of devices; here — the
build, codec/merge unit tests and the settings render on the simulator.

**#41 done:** two `ControlWidget`s in the extension (`Widgets/CheckNetControls.swift`) — "Ping a host"
(shows the last result from the app-group snapshot and, on tap, re-opens the check) and
"Check blocking" (opens the tab). Both are **user-added only** (Control Center, Lock Screen, the Action
button) — still nothing is published to the Home Screen gallery. A tap fires a deep link
`checknet://tool/<raw>?host=&run=1` / `checknet://tab/<name>`, resolved by `onOpenURL`; the link
grammar and the control value format were moved into `Shared/ControlSupport.swift` and covered by unit
tests. Routing verified on the simulator (Ping with auto-run, the "Blocking" tab).

> The widgets in #41 are **only the ones the user adds themselves** (Control Center, Lock Screen).
> A Home Screen widget does not appear after install and must not.

---

## M6 · New tools ✅

| # | Task | Priority | Status |
|---|---|---|---|
| [#46](https://github.com/AuthFailed/CheckNet/issues/46) | Bufferbloat — latency under load | P1 | ✅ |
| [#47](https://github.com/AuthFailed/CheckNet/issues/47) | IP geolocation and World Ping — pick a source | P2 | ✅ |
| [#48](https://github.com/AuthFailed/CheckNet/issues/48) | Wi-Fi analysis on macOS via CoreWLAN | P2 | ✅ |
| [#49](https://github.com/AuthFailed/CheckNet/issues/49) | Idea pool for a competitive edge | P3 | 📋 backlog |

**#46 done first** — the load engine already existed (`IperfClient`, `CloudflareSpeedTest`), and the
check itself is more in demand than the rest: bufferbloat is exactly what explains "the internet is
fast, but calls drop". `BufferbloatTest` (idle → down → up RTT, an A–F grade, phases capped by time) +
`BufferbloatView` (the grade, a latency-by-phase chart, three numbers); verified on a real network.

From [#49](https://github.com/AuthFailed/CheckNet/issues/49) the most promising are:
**IPv6 readiness**, **QUIC/HTTP-3 availability**, a **network-quality journal** and
an **auto-report for the ISP** — the last one is a potential killer feature.

---

## M7 · Tools for VPN operators — complete ✅

A new section not for the end user but for the **VPN operator** (the Xray / Reality /
mihomo / sing-box / Happ ecosystem). Today the app looks at the network through a client's eyes;
operators need a different set — check a domain for Reality, confirm the inbound is alive, parse
geosite/geoip and routing rules, parse a subscription. In the App Store this niche is nearly empty — a
potential edge.

**The boundary.** The section stays diagnostics and config management: check, parse, display,
build a config. The app **does not perform DPI bypass** and does not become a circumvention tool — the
same principle as in the "Blocking" tab (detect, don't bypass). We don't embed SNI fragmentation, a
fake ClientHello, and the like; we help the operator set up and check **their own** server.

| # | Task | Priority | Status |
|---|---|---|---|
| [#69](https://github.com/AuthFailed/CheckNet/issues/69) | Epic: the "VPN" section — umbrella task | P2 | 📋 |
| [#70](https://github.com/AuthFailed/CheckNet/issues/70) | Domain suitability as SNI/dest for Reality | P2 | ✅ |
| [#71](https://github.com/AuthFailed/CheckNet/issues/71) | Xray inbound reachability (VLESS/Trojan) — a real handshake | P2 | ✅ |
| [#72](https://github.com/AuthFailed/CheckNet/issues/72) | Subscription parsing — hosts, routing, quick actions | P2 | ✅ |
| [#73](https://github.com/AuthFailed/CheckNet/issues/73) | geosite/geoip viewer — download, parse, tag search, filters | P3 | ✅ |
| [#74](https://github.com/AuthFailed/CheckNet/issues/74) | mihomo rule-set (`.mrs`) viewer | P3 | ✅ |
| [#75](https://github.com/AuthFailed/CheckNet/issues/75) | Subscription server response to different clients' headers | P3 | ✅ |
| [#76](https://github.com/AuthFailed/CheckNet/issues/76) | Happ routing-rule configurator + parsing | P3 | ✅ |
| [#77](https://github.com/AuthFailed/CheckNet/issues/77) | Happ Decrypt — decrypting Happ configs/subscriptions | P3 | ✅ |
| [#78](https://github.com/AuthFailed/CheckNet/issues/78) | Incy deep link — parse and generate `incy://crypt1` (+ QR) | P3 | ✅ |
| [#79](https://github.com/AuthFailed/CheckNet/issues/79) | Domain scanner for Reality — sweep an IP/subnet in search of a TLS 1.3 dest | P2 | ✅ |

**Order:** first the parsers and clients in `NetworkKit` (engine → test → screen), which the rest
depends on: subscription parsing (#72) and the VLESS/Trojan client (#71) are the foundation; the SNI
check (#70) reuses the TLS inspector/`X509Parser`; the viewers (#73/#74) are independent; the routing
configurator (#76) and Happ Decrypt (#77) wait on the format specs (see the open questions in the issue).

**#70 done:** `RealitySNICheck` renders a verdict on a domain's suitability as a `dest`/SNI by the same
criteria the reference `XTLS/RealiTLScanner` and the REALITY README stand on. Mandatory (a failure
sinks the verdict): **TLS 1.3**, **ALPN `h2`**, a real leaf certificate with subject and issuer —
that is RealiTLScanner's acceptance rule. Soft (a remark only): **X25519 support**, the absence of an
external redirect from the home page (`example.com` → `www` is allowed), a trusted non-expired
certificate, the domain being covered by the SAN. TLS facts come from the existing
`TLSInspector`/`X509Parser`; the redirect from a live `GET /` over `TLSStream`. X25519 can't be
constrained through Network.framework (no API for key-exchange groups), so `TLS13GroupProbe` hand-sends
a minimal TLS 1.3 ClientHello with a single X25519 group and reads the ServerHello — the same way
RealiTLScanner captures `CurvePreferences`. Everything runs over `NWConnection` (raw BSD sockets are
blocked in the sandbox, which is why `TLSInspector` always lived on Network.framework). The engine is
covered by unit tests (the deterministic verdict/cert-matching/redirect logic) and verified on live
domains: microsoft/google/apple/cloudflare/github → "suitable", `dl.google.com` → "with a remark"
(a cross-subdomain redirect to `www.google.com`). On device the verdict for www.microsoft.com was
confirmed. The `RealitySNIView` screen — enter a domain, `ToolRunModel<RealitySNIReport>`, a verdict
card + a criteria list with status by shape and word + a details card. The boundary is respected: only
diagnostics, no bypass. **Done in M7:** #70, #72, #76, #77, #78; **remaining:** #71 (Xray inbound),
#73/#74 (geosite/`.mrs` viewers), #75 (client headers), #79 (scanner, in progress).

**#79 — the domain scanner for Reality (done).** #70 checks a single domain; the scanner solves the
inverse problem — "give me an IP/subnet near my server, find hosts in it fit for `dest`". It sweeps an
IPv4 range (CIDR / `a.b.c.d-e` / `a.b.c` / a single IP; a domain resolves to an IP, optionally the
neighboring /24), does a TLS 1.3 handshake **without SNI** to each IP, and collects hits: TLS 1.3 + a
certificate, from the leaf it takes the domain (CN/SAN) and issuer, and flags h2 support. The result
streams (progress + a list of finds IP → domain → issuer), as in the port/IP scan. It reuses
`IPv4Range.hosts` (range parsing) and the streaming `withTaskGroup` from `IPRangeScanner`, with TLS
facts modeled on `TLSInspector`. A range scan is network-intrusive → a consent gate (`.confirmationDialog`,
as with the port/IP scan). The M7 boundary is respected: we find camouflage domains, we don't bypass DPI.

**#75 — server response by client (done).** `ClientHeaderProbe` (NetworkKit/VPN) requests the
subscription URL on behalf of each client (`SubscriptionUserAgents`: v2rayNG, Happ, Clash Meta, sing-box,
Hiddify, Streisand, Shadowrocket, NekoBox, V2Box, Karing) and streams a per-client result: status,
node count, format (via `SubscriptionParser`) and the panel headers — `subscription-userinfo`
(upload/download/total/expire; `expire=0` = no expiry, not 1970), `content-disposition` (filename,
including RFC 5987), `profile-title` (plain/`base64:`), `profile-update-interval`, support-url. The
`ClientHeadersView` screen — a streaming list with a colored status (served/no nodes/refused) and
expanded details; the URL field is wired to the shared `SavedSubscriptionsStore` (the same subscription
list as in "Subscription parsing", #72) — you can drop in a saved one or bookmark the current one. The
**client editor** (`ClientEditorView` + `EditableClient`): the user edits the app and version
themselves (a UA "App/Version" is assembled), enables/disables and adds their own; for open-source
clients `ClientReleaseIndex` pulls the real versions from GitHub Releases (a client→repository map:
2dust/v2rayNG, SagerNet/sing-box, clash-verge-rev, hiddify-app, NekoBox, Karing, mihomo, FlClash) —
a "pull latest" button + a per-row version picker menu; closed-source ones (Happ, Streisand,
Shadowrocket, V2Box) stay manual. **HWID:** a "send HWID" toggle + a custom value (or generation) —
it goes out as an `X-HWID` header for panels with device binding; the whole thing can be turned off.
**Raw response headers** are saved and shown per-client (an expandable "Response headers (N)" list).
The client/HWID set persists in UserDefaults. 11 + 6 unit tests (header and GitHub-release parsing) +
live smokes against cloudflare-trace and the GitHub API; verified on a real subscription (Happ →
200/20 nodes, traffic/title/support parsed) and on device (version pull: v2rayNG 1.9.5→2.2.6,
clash-verge→2.5.2, sing-box→1.14.0-beta.2). **Remaining in M7:** #71 (Xray inbound, through-proxy on
macOS only), #73/#74 (geosite/`.mrs` viewers).

**#73 — geosite/geoip viewer (done).** `GeoData` (NetworkKit/VPN) — manual parsing of the v2fly
wire-format protobuf (a custom `ProtoReader`: varint/length-delimited/skip, like the hand-written
DER/MMDB parsers). `GeoDataDocument.load` auto-detects geosite vs geoip (by the type of the first field
inside the inner message: varint=domain → geosite, bytes=IP → geoip), builds a category index
(`country_code` + a counter, a byte range), and decodes rules on demand — a file with ~0.5 million
rules is never fully materialized into objects. geosite: domain type (full/domain/keyword/regexp) +
value + `@ads` attributes; geoip: CIDR (v4 and v6). Search: `categoriesContaining(domain:)` (exact/
subdomain/keyword/regex) and `categoriesContaining(ip:)` (IPv4 membership by mask). The `GeoDataView`
screen — open your own `.dat` (`fileImporter`) or download the Loyalsoldier build, a header
(type/categories/rules), a domain/IP search across categories, a `.searchable` category list → a rule
detail screen with type badges. 10 unit tests on hand-made protobuf fixtures + live parsing of real
geosite.dat/geoip.dat (GOOGLE/NETFLIX/CN, CN >1000 domains, IP 1.2.4.8→CN). Verified on device:
geosite.dat = 1527 categories / 498,682 rules; geoip renders CIDRs.

**#71 — Xray inbound reachability (done).** It checks that the operator's VLESS/Trojan inbound really
accepts connections: it brings up **the Xray core right inside the app process** (not via a downloaded
binary — on iOS you can neither download nor run one) and makes a probe request through it.
The core is a vendored `LibXray.xcframework` (XTLS/libXray, a static Go core `libXray.a`; fetched by
`Scripts/fetch-libxray.sh`, not committed to git — linked, not embedded; Go resolves DNS through
`libresolv`). The `XrayCore` bridge (App/VPN) wraps the single C entry point `CGoInvoke(json)->json`
(core version, `runXrayFromJson`, `stopXray`). `XrayProxyRunner.startInProcess` builds a config from
the node (`XrayTestConfig`: one local SOCKS inbound + the node's real outbound — for Xray JSON it's
taken verbatim, otherwise reconstructed from the link fields), brings up the core and returns a live
SOCKS port.

**Egress IP through the proxy.** Instead of a single "works/doesn't", the tool queries ~19 independent
resources through the proxy and shows **which egress IP each one sees** — so the operator confirms the
exit address, catches split routing (different resources see different IPs) and reads the geo/ASN the
server presents outward. The `EgressIPProbe` engine (NetworkKit/VPN) pins the whole `URLSession`
to the SOCKS proxy via `ProxyConfiguration(socksv5Proxy:)` (Network, iOS 17+) — TLS, redirects and
JSON all go through the tunnel, so the set even includes an HTTPS look at Cloudflare itself. The
catalog is diversified (`EgressResource.catalog`): IP echo (ipify, ifconfig.me, icanhazip, Amazon AWS,
ident.me, ip.sb, SeeIP, myexternalip, WTFIsMyIP), Cloudflare `/cdn-cgi/trace` (IP + country + colo) and
geo/ASN (ip-api, ipinfo, ipwho.is, ipapi.co, ip.sb geoip, GeoJS, myip.com, FreeIPAPI). Results stream
(`AsyncStream`, concurrently), and the `XrayCheckView` screen gives a verdict ("inbound works / N of M
responded"), a large egress IP with a country flag and a warning when IPs diverge, and below — a list
grouped (resource → IP → flag/country/ASN/provider/colo, latency, a red reason on failure). Response
parsing (plain/trace/JSON, nested keys, an `AS` prefix for numeric ASNs) is covered by unit tests.

`XrayTestConfig`/`SubscriptionParser`/`EgressIPProbe` are covered by unit tests (building a config
from a reality link and from full Xray JSON, parsing every echo format — deterministically). **Verified
live** on an iPhone 17 Pro (simulator) against a real VLESS+Vision server (France): the core came up,
connected, 17 of 19 resources returned the same egress IP `50.7.33.242`, Cloudflare — 🇫🇷 FR/colo VIE,
ip-api — FDCservers.net; two resources fell out on timeout and are honestly shown in red. This also
confirmed the positive end-to-end handshake that previously required a live server. The M7 boundary is
respected: we diagnose our own inbound and its exit, we don't bypass DPI.

**#74 — mihomo `.mrs` viewer (done, M7 closed).** It unpacks a compiled Clash.Meta/mihomo rule-set
back into a list of domains or subnets. The format was decoded from the mihomo sources: a zstd frame →
an `MRS\x01` container + a behavior byte (0 = domains, 1 = ipcidr) + a count + reserve → the payload.
Domains are stored as a **succinct trie (LOUDS)** in reverse order (`com.example`) — `SuccinctDomainSet`
reproduces mihomo's reader and `keys()` traversal, but with rank/select over popcount instead of
precomputed indices (we only need to enumerate once for display). ipcidr is a list of merged ranges
[from,to] of 16 bytes each; `IPRangeCIDR` expands each range into minimal CIDRs (on byte arithmetic,
without a 128-bit type — keeping the iOS 17 bar): IPv4-mapped renders as IPv4, the rest as IPv6. Apple's
`Compression` doesn't do zstd, so we vendor a decompress-only `zstddeclib.c` (facebook/zstd 1.6.0, BSD)
as a separate C target `CZstd` and wrap it in `Zstd.decompress` (size from the frame, or streaming). The
`MRSView` screen — open a `.mrs` (`fileImporter`) or by URL, a header (type, rule count, "source →
after merge"), a search and a list export. Parsing is covered by unit tests on real fixtures from
MetaCubeX/meta-rules-dat (domains and ipcidr, IPv4+IPv6), and the domain enumeration is checked against
an independent LOUDS decoder (youtube.mrs → exactly 355 domains; telegram.mrs → 12 CIDRs, including
IPv6). The boundary is respected: only unpacking and viewing lists, no routing. **M7 closed** — the
entire section for VPN operators (#70–#79) is ready.

Sources of the idea (behavioral references for the scanner, not a dependency):
- `XTLS/RealiTLScanner` — https://github.com/XTLS/RealiTLScanner (the reference: `-addr <IP/CIDR/domain>`,
  the acceptance rule `version==TLS1.3 && alpn=="h2" && has CN && has issuer`, output `IP  domain  issuer`,
  flags `-port/-thread/-timeout/-showFail`).
- Web implementation: https://ru.inettools.net/tools/reality-tls-scanner
- Guide to setting up Xray+Reality (choosing `dest`, using the scanner):
  https://pikabu.ru/story/nastraivaem_server_i_klient_xray_s_xtlsreality_12073187

**Formats decoded (specs in the issue):** Happ crypt/crypt5 (RSA PKCS#1 + ChaCha20-Poly1305,
public key material) — #77; Happ routing (`happ://routing/add/<base64 JSON>`, exact fields) —
#76; mihomo `.mrs` (zstd + magic `MRS\x01`, LOUDS domain-set / ipcidr) — #74; geosite/geoip `.dat`
(v2fly protobuf, manual wire-format) — #73. Among the dependencies: `.mrs` needs zstd on iOS/macOS
(Apple's `Compression` doesn't provide it).

**Client versions — automatically.** The headers for #75 substitute the current version, pulling it
from GitHub Releases via a `client → repository` map (Happ, Incy, mihomo, sing-box, v2rayNG, Clash Verge
Rev, Hiddify, Karing, FlClash), with a cache and a bundle fallback; the actual UAs come from observed
subscription traffic. The exact Incy/koala-clash/v2raytun/Happ formats are confirmed.

**Official format references connected:** `Happ-proxy/routing_generator` (the routing generator, the
source of truth for #76) and `INCY-DEV/incy-link-encoder` (the `incy://crypt1` format, AES-256-GCM —
for #78 and #72).

**Additional ideas (issue candidates, from epic #69):** a validator/generator for
`vless://`/`trojan://`/`ss://` links with QR; a Reality-config integrity check (SNI/dest, pbk/sid, flow,
ALPN); a config's "detectability" (uTLS fingerprint/ALPN vs a browser, steal-oneself); external
uptime/latency of inbounds; checking the server's IP against blacklists/ASN (reusing DNSBL).

---

## M8 · App Store preparation and release — planned

Until now "release" in the plan was only about the tech (M1: privacy manifest, CI, data races).
M8 is the **actual App Store launch**: the account and legal layer, encryption export control,
passing App Review, metadata and the store page, a TestFlight beta and rollout automation. It's the
last milestone not because it's easy, but because submitting a moving target is pointless: the tool set
must be frozen.

The app is **atypical for the store** and that's the main risk: network scanners (ports, IP range,
the Reality domain scanner), a whole section **for VPN operators** and crypto tools (Happ Decrypt,
Incy `crypt1`). So a lot here is not about "uploading a binary" but about **how to explain to Apple
that this is diagnostics and managing your own server, not a bypass/hacking tool** — the same boundary
principle as in the "Blocking" tab.

> **The two biggest review risks — we budget time for them in advance.**
> 1. **Guideline 5.4 (VPN).** The app has a "VPN" section, but it **is not** a VPN provider
>    and does not route traffic — these are diagnostics and config-prep tools. A reviewer could
>    decide otherwise over the single word "VPN". We mitigate with wording in the description and UI
>    (if at risk — rename the section to "Operator Tools"), detailed reviewer notes and demo data.
> 2. **Network scanners and crypto.** Scanners are allowed on Apple (Fing is an example), but only with
>    explicit consent and a clear purpose — consent is already a gate for us (`SensitiveConsentModifier`).
>    Happ/Incy decrypt the operator's **own** configs by published algorithms — this must be spelled out
>    in the notes, otherwise it looks suspicious.

**Export control (don't miss it — it's a submission blocker).** Beyond standard TLS the app uses
its own crypto for interoperability: ChaCha20-Poly1305, AES-256-GCM, RSA (Happ, Incy). This most
likely falls under the mass-market exemption 740.17(b) (standard published algorithms), but requires
proper handling of `ITSAppUsesNonExemptEncryption`, an **annual self-classification report** to
BIS/ENC, and, when distributing in France, an ANSSI declaration. This needs an explicit task with a
final determination, not "set false and forget".

### A. Account, legal layer, export control

| # | Task | Priority | Status |
|---|---|---|---|
| [#80](https://github.com/AuthFailed/CheckNet/issues/80) | Enrollment in the Apple Developer Program (individual/organization; for an organization — D-U-N-S) | P0 | ⬜ |
| [#81](https://github.com/AuthFailed/CheckNet/issues/81) | Agreements in App Store Connect (Free Apps Agreement), fill in Tax & Banking | P0 | ⬜ |
| [#82](https://github.com/AuthFailed/CheckNet/issues/82) | Privacy Policy + Support URL — lay out and host (candidate: GitHub Pages) | P0 | ⬜ |
| [#83](https://github.com/AuthFailed/CheckNet/issues/83) | Export control: determine the status, `ITSAppUsesNonExemptEncryption`, annual self-classification to BIS/ENC, ANSSI declaration | P0 | ⬜ |
| [#84](https://github.com/AuthFailed/CheckNet/issues/84) | Vet the name "CheckNet" (trademark/store collisions), reserve the bundle ID and App ID with the needed capabilities | P0 | ⬜ |

### B. Compliance with the App Review Guidelines

| # | Task | Priority | Status |
|---|---|---|---|
| [#85](https://github.com/AuthFailed/CheckNet/issues/85) | Review audit of sensitive tools: scanners, the VPN section, Happ/Incy crypto — a legitimate statement of purpose | P0 | ⬜ |
| [#86](https://github.com/AuthFailed/CheckNet/issues/86) | Reviewer notes (App Review Information): what each sensitive tool does + demo data (a test subscription, test hosts) so the reviewer can run the VPN section | P0 | ⬜ |
| [#87](https://github.com/AuthFailed/CheckNet/issues/87) | 5.4 VPN boundaries: explicitly show the app does NOT route traffic (wording in the description/UI, rename the section if at risk) | P1 | ⬜ |
| [#88](https://github.com/AuthFailed/CheckNet/issues/88) | 2.5.1 private APIs: audit for the absence of non-public frameworks/symbols (raw sockets, `rt_msghdr2`, CoreWLAN) in the iOS build | P1 | ⬜ |
| [#89](https://github.com/AuthFailed/CheckNet/issues/89) | App Privacy ("nutrition labels") in ASC: honestly declare "Data Not Collected", no tracking | P0 | ⬜ |
| [#90](https://github.com/AuthFailed/CheckNet/issues/90) | Age rating (age rating questionnaire) | P1 | ⬜ |
| [#91](https://github.com/AuthFailed/CheckNet/issues/91) | Legal cleanliness of data: attributions for third-party sources (v2fly geosite/geoip, iperf server list, GitHub Releases), checking their terms on bundling | P2 | ⬜ |

### C. The technical release build

| # | Task | Priority | Status |
|---|---|---|---|
| [#92](https://github.com/AuthFailed/CheckNet/issues/92) | Distribution certificate + App Store provisioning profile; the Release archive actually builds (`xcodebuild archive`) | P0 | ⬜ |
| [#93](https://github.com/AuthFailed/CheckNet/issues/93) | Entitlements audit: turn off the unobtained ones (iCloud KV — dormant, Wi-Fi) so signing passes; reconcile the App ID capabilities | P0 | ⬜ |
| [#94](https://github.com/AuthFailed/CheckNet/issues/94) | `PrivacyInfo.xcprivacy`: declare the required-reason APIs (UserDefaults, file timestamp, boot time, disk space) — an Apple requirement | P0 | ⬜ |
| [#95](https://github.com/AuthFailed/CheckNet/issues/95) | Bump the version/build, disable debug logs and test hosts, upload dSYM for symbolication | P1 | ⬜ |
| [#96](https://github.com/AuthFailed/CheckNet/issues/96) | macOS decision: a separate Mac App Store submission (its own profile/screenshots) or iOS only for now; notarization if outside the store | P1 | ⬜ |
| [#97](https://github.com/AuthFailed/CheckNet/issues/97) | `Info.plist` sanity: usage strings (Local Network etc.), orientations, background-modes justification, launch screen, min deployment target | P1 | ⬜ |

### D. Metadata and the store page

| # | Task | Priority | Status |
|---|---|---|---|
| [#98](https://github.com/AuthFailed/CheckNet/issues/98) | Store copy: name, subtitle, description, keywords, promo text, category (Utilities / Developer Tools), What's New | P1 | ⬜ |
| [#99](https://github.com/AuthFailed/CheckNet/issues/99) | Screenshots for all required sizes (iPhone 6.9″/6.5″, iPad 13″, + Mac on submission) + optional app preview | P1 | ⬜ |
| [#100](https://github.com/AuthFailed/CheckNet/issues/100) | 1024 icon with no alpha/rounding; check icons of all sizes in the asset catalog | P1 | ⬜ |
| [#101](https://github.com/AuthFailed/CheckNet/issues/101) | Metadata localization: at minimum the primary language fully; top store languages as feasible (13 languages already in the app) | P2 | ⬜ |

### E. QA on real devices

Nearly all the "device-only" features from `CLAUDE.md` (Local Network Privacy, `BGTask`, notifications,
Handoff, Live Activity) had only been verified on the simulator or in logic tests — here they are
finally run on live devices.

| # | Task | Priority | Status |
|---|---|---|---|
| [#102](https://github.com/AuthFailed/CheckNet/issues/102) | Run on real iPhone/iPad: Local Network Privacy, `BGTask` wake-up, notification delivery, Handoff, Live Activity/Dynamic Island, controls | P0 | ⬜ |
| [#103](https://github.com/AuthFailed/CheckNet/issues/103) | Stability: no crashes on cold start and any screen, no memory leaks, correct operation without a network | P0 | ⬜ |
| [#104](https://github.com/AuthFailed/CheckNet/issues/104) | Accessibility: a VoiceOver pass over key screens, Dynamic Type up to accessibility sizes, tap targets ≥44 pt | P1 | ⬜ |
| [#105](https://github.com/AuthFailed/CheckNet/issues/105) | Check on a "clean" device without paid entitlements: dormant features (iCloud/Wi-Fi) honestly show "unavailable", don't crash | P1 | ⬜ |

### F. TestFlight and beta

| # | Task | Priority | Status |
|---|---|---|---|
| [#106](https://github.com/AuthFailed/CheckNet/issues/106) | Internal TestFlight testing (own devices) | P1 | ⬜ |
| [#107](https://github.com/AuthFailed/CheckNet/issues/107) | External beta (Beta App Review) + collecting feedback before release | P2 | ⬜ |

### G. Rollout automation

"It may be possible to automate some processes" — yes, and it pays off from the second submission.
A manual path for the first release is acceptable, but everything below is worth setting up so that
updates aren't a manual ritual.

| # | Task | Priority | Status |
|---|---|---|---|
| [#108](https://github.com/AuthFailed/CheckNet/issues/108) | App Store Connect API key + fastlane (`gym` — archive, `deliver` — metadata/screenshots/binary, `match` — signing) | P2 | ⬜ |
| [#109](https://github.com/AuthFailed/CheckNet/issues/109) | Auto-generate screenshots (fastlane `snapshot` / a UI test) for all sizes and languages | P2 | ⬜ |
| [#110](https://github.com/AuthFailed/CheckNet/issues/110) | CI: on a git tag build the archive and upload to TestFlight (extending the existing GitHub Actions) | P3 | ⬜ |
| [#111](https://github.com/AuthFailed/CheckNet/issues/111) | Auto-publish the Privacy Policy/Support as static pages (GitHub Pages) from the repository | P3 | ⬜ |

**Order.** First the submission blockers — the whole of group A plus M8.13–M8.15 and M8.10: without an
account, an export status, a distribution signature, a privacy manifest and App Privacy labels the
binary simply won't be accepted. In parallel the legal layer is prepared (policy, support). Then B
(review risks and reviewer notes) — the very thing that could get our app in particular turned away.
After that D (the store page) and E (on-device QA) go together. F (beta) is the dress rehearsal before
release. G (automation) is P2/P3, as needed.

**Dependency on M7.** A submission makes sense once the tool set is frozen — otherwise every new
screen drags in new screenshots, strings and reviewer notes. M8 starts when M7 is closed (or its
sensitive tools are deliberately hidden from the release build). The local hygiene from
`CLAUDE.md` (zero toolchain traces in the repository, commits, store metadata) applies here too.

The tasks are filed as GitHub Issues [#80–#111](https://github.com/AuthFailed/CheckNet/milestone/8) and
hung off milestone M8, like the rest.

---

## M9 · Design redesign — macOS, VPN section, unified visual language — planned

M2 made the layout **adaptive** (it doesn't break), but not **beautiful**. On macOS this is especially
visible: content is displayed crookedly, stretches wrong, fields and alignment drift, and the "VPN"
section from M7 is missing on Mac altogether. M9 is the move from "works on a wide screen" to "looks
like a native Mac app", with a unified visual language for the catalog, the tool screen and the result
card.

**Design is produced as a spec first, then implemented — not sketched ad-hoc in SwiftUI** — that's a
project rule (otherwise we again get 22 near-identical screens). So the milestone has an explicit
"brief → spec → implementation" step, not "nudge the margins by eye".

| # | Task | Priority | Status |
|---|---|---|---|
| [#113](https://github.com/AuthFailed/CheckNet/issues/113) | Audit of macOS layout defects: screenshots of every screen in windows of different sizes, a catalog of problems | P1 | ⬜ |
| [#114](https://github.com/AuthFailed/CheckNet/issues/114) | Bring back/adapt the "VPN" section on macOS (conditional compilation/hidden tab) | P1 | ⬜ |
| [#115](https://github.com/AuthFailed/CheckNet/issues/115) | Window width and behavior on Mac: width constraint, margins, resize, minimum size | P1 | ⬜ |
| [#116](https://github.com/AuthFailed/CheckNet/issues/116) | Design brief: a unified language for catalog/tool/result under macOS 26 + an iOS revision | P1 | ⬜ |
| [#117](https://github.com/AuthFailed/CheckNet/issues/117) | Implement the redesign from the spec | P1 | ⬜ |
| [#118](https://github.com/AuthFailed/CheckNet/issues/118) | Native toolbars, menus, keyboard shortcuts and window behavior on Mac | P2 | ⬜ |
| [#119](https://github.com/AuthFailed/CheckNet/issues/119) | Revise empty states and result cards under the new language | P2 | ⬜ |
| [#120](https://github.com/AuthFailed/CheckNet/issues/120) | Accept the redesign on the matrix: iPhone/iPad/Mac, light/dark, Dynamic Type, RTL | P2 | ⬜ |

**Order:** #113 (collect the defects) + #114/#115 (fix the roughest on Mac) → #116 (the brief) →
#117 (implementation from the spec) → #118/#119 → #120 (acceptance). Acceptance is convenient to run
with the design-QA tooling from M11 (#132/#133).

---

## M10 · Localization and tone — full translation, business voice, release gate — planned

Two different debts under one roof: the **completeness** of the translation and the **quality** of the
text. Right now the catalog covers 13 languages, but some engine strings stay in the source language in
a foreign locale (the category from the closed #60, which the state-of-fact still counts as open), and
the tone is machine-like in places. M10 brings the translation to 100% across all languages, brings all
text to a **polished, formal business voice**, and puts in an **automatic gate** that, before each
release, checks that translations are in place and correct.

The tone is codified "in the guidelines": a voice guide + a glossary in `docs/STYLE.md` and a new
principle #6 at the end of this file.

| # | Task | Priority | Status |
|---|---|---|---|
| [#121](https://github.com/AuthFailed/CheckNet/issues/121) | Tone-of-voice guide (formal business voice) + a unified glossary → `docs/STYLE.md` | P1 | ⬜ |
| [#122](https://github.com/AuthFailed/CheckNet/issues/122) | Audit the source strings for tone: remove officialese/machine feel, unify terms | P1 | ⬜ |
| [#123](https://github.com/AuthFailed/CheckNet/issues/123) | Verbatim engine strings (`LocalizedStringKey(variable)`, `Text(model.string)`, `%lld`) — continue #60 | P1 | ⬜ |
| [#124](https://github.com/AuthFailed/CheckNet/issues/124) | Translation-completeness inventory: a coverage report for each of the 13 languages | P1 | ⬜ |
| [#125](https://github.com/AuthFailed/CheckNet/issues/125) | Bring the translation to 100% across all languages + a glossary proofread | P1 | ⬜ |
| [#126](https://github.com/AuthFailed/CheckNet/issues/126) | Localization release gate: before deploy, fail if there are untranslated/empty/verbatim strings | P1 | ⬜ |
| [#127](https://github.com/AuthFailed/CheckNet/issues/127) | Long translations and RTL: the layout doesn't clip, mirrors correctly | P2 | ⬜ |
| [#128](https://github.com/AuthFailed/CheckNet/issues/128) | Proofread the key languages with native speakers/a quality source | P2 | ⬜ |

**Order:** #121 (sets the tone and terms) → #122/#123 (fix the source and verbatim) →
#124 (inventory) → #125 (finish translating) → #126 (the gate, so it doesn't degrade) → #127/#128.
The #126 release gate is built into the pre-release run alongside the M8 rollout automation.

---

## M11 · Competitive edge and design leadership — planned

A forward-looking milestone: not "get to release", but "stay better than the competition after
release". Three threads.

- **Product.** Find and adopt what we're missing from the competition (Speedtest, Network Analyzer,
  iNetTools, Fing, He.net) — not copy everything, but take what's meaningful for our niche.
- **Design.** Use the "latest word" in Apple design (new APIs, patterns, Liquid Glass) — so the app
  always looks natively modern, not an OS version behind.
- **Automatic design QA.** Tooling that **finds layout flaws on its own**: it runs every screen on a
  matrix of devices/themes/font sizes and reports defects. A candidate for an agent/workflow — the run
  over screens parallelizes.

| # | Task | Priority | Status |
|---|---|---|---|
| [#129](https://github.com/AuthFailed/CheckNet/issues/129) | Competitive audit: a "they have it — we don't" matrix (Speedtest, Network Analyzer, iNetTools, Fing, He.net) | P2 | ⬜ |
| [#130](https://github.com/AuthFailed/CheckNet/issues/130) | File issues for the chosen new tools (add to backlog #49) | P2 | ⬜ |
| [#131](https://github.com/AuthFailed/CheckNet/issues/131) | Adopt the latest word in Apple design: track new APIs/patterns, an adoption plan | P3 | ⬜ |
| [#132](https://github.com/AuthFailed/CheckNet/issues/132) | Screenshot harness: via deep link, capture every tool on the matrix (iPhone/iPad/Mac, light/dark, Dynamic Type) | P2 | ⬜ |
| [#133](https://github.com/AuthFailed/CheckNet/issues/133) | Design-review agent/workflow: look in the screenshots for clipping, overflow, contrast, drifted alignment | P2 | ⬜ |
| [#134](https://github.com/AuthFailed/CheckNet/issues/134) | Layout snapshot regression: baselines + a failure on unintended visual changes | P3 | ⬜ |
| [#135](https://github.com/AuthFailed/CheckNet/issues/135) | Design QA in the pre-release pipeline: a defect report before deploy | P3 | ⬜ |
| [#136](https://github.com/AuthFailed/CheckNet/issues/136) | Killer features from #49: pick 1–2 (IPv6 readiness, QUIC/HTTP-3, a quality journal, an ISP auto-report) | P3 | ⬜ |

**Order:** #129 → #130 (product: audit → tasks) run independently of the design thread. In the design
thread #132 (the harness) is the foundation: #133 (the agent), #134 (regression) and #135 (pipeline
integration) sit on it. #131 (tracking Apple) and #136 (a killer feature) are background, pulled
continuously. Design QA (#132/#133) is reused to accept the redesign in M9 (#120).

**Why forward-looking, not a release blocker.** The first release (M8) does without this — the tool set
is already competitive. But to "stay ahead" beyond that, we need a steady influx of features and an
automatic eye on the layout, otherwise design debt piles up again, as it did with the 22 near-identical
screens.

---

## How the tests run in CI

Most of the 96 tests reach live hosts — this is deliberate: a check is considered working only after
confirmation on a real host. But the GitHub runner isn't a reliable network: ICMP there is usually
filtered, and DNS and TLS to third-party hosts flake. Running that as a blocking gate means reddening
every PR over someone else's outage.

The decision made is to split the run in two:

- **`unit-tests` — blocking.** Runs with `CHECKNET_SKIP_NETWORK_TESTS=1`; network tests are
  marked with a `try requiresInternet()` call and skipped. What remains is deterministic:
  parsers, encoders, catalogs, webhook delivery to a local server. This job must not
  flake — a red cross here always means a regression.
- **`network-tests` — informational** (`continue-on-error: true`). Runs the whole set against
  real hosts. A failure is a reason to look, not a reason to block the PR.

Locally the variable isn't set, so `swift test` still runs everything. The real gate
for network checks is a local run before enabling a tool.

---

## Principles that are not up for revision

1. **Test before screen.** An engine in `NetworkKit` + a test against a real host → only then the UI and
   `Tool.isImplemented = true`. There are no half-working checks in the build.
2. **Detect only, don't bypass.** Blocks are diagnosed; SNI fragmentation, a fake ClientHello,
   record-splitting and other DPI bypass are not added to the app — that's outside diagnostics.
3. **Impose nothing.** No widgets, permissions or notifications "by default" —
   the user enables everything, and every check explains itself through ⓘ.
4. **Privacy.** Diagnostics run from the device; only what the user
   requested goes out. External APIs are wired in only with an explicit explanation in ⓘ.
5. **HIG.** System components over homegrown ones, Dynamic Type and VoiceOver — not optional.
6. **A unified voice and full localization.** Text is a polished, formal business voice, free of
   officialese and clichés, with a unified glossary of terms (`docs/STYLE.md`). The app is translated
   into all declared languages 100%; before each release the completeness and correctness of the
   translations are checked by an automatic gate — there must be no source-language strings in a
   foreign locale.
