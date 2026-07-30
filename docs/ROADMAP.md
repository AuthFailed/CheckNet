# CheckNet — development plan

Goal: **the best network-diagnostics app on Apple platforms** — native on iPhone, iPad and Mac,
honest in its explanations, with checks the competition lacks (Speedtest, Network Analyzer, iNetTools).

Work items live in [Issues](https://github.com/AuthFailed/CheckNet/issues) and are grouped by milestone.
This file is about **order and dependencies**: why M2 comes before M3, and M4 before M6.

---

## Where we are now

Updated 2026-07-23. **M1–M4 and M6 are closed; M5 (platform integrations) remains.** Below is the
actual state; the milestone tables further down mark each task individually in a "Status" column.

- **27 tools** implemented; **no "coming soon" placeholders left**. Two Wi-Fi tools work only on
  macOS (CoreWLAN); on iOS they show an "available on Mac" placeholder.
  Added in this milestone: bufferbloat (#46), IP geolocation and World Ping (#47), Wi-Fi on macOS (#48).
- **Core** `Packages/NetworkKit` — **207 XCTest tests** against real hosts and parsers
  (the DNS/X.509/MMDB parsers and geolocation are covered deterministically). In CI: deterministic
  tests are a blocking gate, network tests are informational (see "How tests run in CI").
- **App + Shared** — ~11,000 lines; a **`CheckNetTests` target (119 tests)** was added for App/Shared
  logic (M4 #37). Pure pieces (`HostSharing`, `IPAddress`, `LaunchArguments`,
  `ScheduleRule`, `HistoryCSV`, the `CheckRecord` and `ToolRunModel` factories) were extracted into `Shared/`.
- **Localization** — string catalog, 13 languages. The second category remains: engine strings that
  are looked up via `LocalizedStringKey(variable)` and stay in English (the source language) in every
  locale (issue #60).
- **iPad/macOS** — adaptive layout is in place: `NavigationSplitView` + `.sidebarAdaptable`,
  a single `ToolScaffold` with a width limit, `MenuBarExtra` / commands / a Settings scene on Mac,
  landscape on iPhone (M2 #14–#19 closed).
- **Haptics** are in (`App/Common/Haptics.swift` + a toggle in Settings); accessibility improved —
  status is conveyed by shape and word, not just color, and icons have labels (#20, #21);
  Dynamic Type, reduce-motion and `numericText` are finished (M3 closed).
- The Home Screen widget was **removed on purpose**: the extension publishes the Live Activity and
  user-added controls (#41), but nothing goes into the Home Screen gallery; after install the app
  imposes nothing.

---

## Ordering logic

```
M1 Stabilization ──┬─→ M2 Adaptive UI ──→ M3 UX polish
                   │            │                 │
                   └─→ M4 Architecture & tests ───┘
                                │
                                ├─→ M5 Platform integrations
                                └─→ M6 New tools
```

**Milestone status:** M1 ✅ · M2 ✅ · M3 ✅ · M4 ✅ · M5 nearly closed (#39–#44 ✅, P3 #45 remains) · M6 ✅ (tools done; #49 is a living backlog of ideas) · **M7 📋 planned** (a section for VPN operators, #69–#77).

- **M1 first** — that's where the release blockers live (privacy manifest), data loss (a race in
  history) and a broken CI. Building new things on an unstable foundation costs more.
- **M2 before M3** — `ToolScaffold` and `NavigationSplitView` rewrite the shell of all 22 screens.
  Polishing empty states and animations before that means redoing it twice.
- **M4 in parallel with M2/M3** — `ToolRunModel` and `ToolScaffold` are two halves of one refactor;
  moving logic into NetworkKit makes it testable.
- **M5 and M6 after M4** — new tools and background scenarios sit on `CheckRunner`, unified error
  handling and `ToolScaffold`, otherwise every new screen copies 200 lines again.

---

## M1 · Stabilization & release ✅

Without this the app can't ship: App Store blockers, data loss, an unlocalized UI.

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

The main visual debt. Right now it's a "stretched iPhone" on every wide screen.

**Status: complete ✅** (all tasks closed).

| # | Task | Priority | Status |
|---|---|---|---|
| [#14](https://github.com/AuthFailed/CheckNet/issues/14) | `NavigationSplitView` + `.tabViewStyle(.sidebarAdaptable)` | P1 | ✅ |
| [#15](https://github.com/AuthFailed/CheckNet/issues/15) | `ToolScaffold` — a single container with a width limit | P1 | ✅ |
| [#16](https://github.com/AuthFailed/CheckNet/issues/16) | Fixed widths/heights that break Dynamic Type | P1 | ✅ |
| [#17](https://github.com/AuthFailed/CheckNet/issues/17) | Sheets without `presentationDetents` | P2 | ✅ |
| [#18](https://github.com/AuthFailed/CheckNet/issues/18) | macOS: `MenuBarExtra`, `.commands`, a `Settings` scene | P1 | ✅ |
| [#19](https://github.com/AuthFailed/CheckNet/issues/19) | Landscape on iPhone | P2 | ✅ |

**Order:** #15 (the shell) → #14 (navigation on top of it) → #16 → #17/#19 → #18 (depends on #7).

---

## M3 · UX polish ✅

What separates "it works" from "it's pleasant to use".

**Status: complete ✅** (all tasks closed). Most were closed by early PRs; Dynamic Type (#22) was the
last one finished — the only remaining hardcoded font size.

| # | Task | Priority | Status |
|---|---|---|---|
| [#20](https://github.com/AuthFailed/CheckNet/issues/20) | Haptics — currently 0 calls across the whole project | P1 | ✅ |
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

## M4 · Architecture & tests ✅

Removes duplication and closes the riskiest uncovered code.

**Status: complete ✅** (6 of 7 closed; for #32 the building block landed, the migration is a separate
step, see below).

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
  (loops/forward/self), caps the name at 255 bytes, forbids reserved label lengths; +15 tests.
- #35 — string parsing by tag (BMPString/Teletex), UTCTime by the RFC 5280 century rule, SAN parsing
  (shown on a leaf certificate); +17 tests with real RSA/EC fixtures and fuzzing.
- #37 — pure App logic extracted into `Shared/` and covered by the `CheckNetTests` target (51 tests);
  CSV escaping is now RFC 4180 across all columns.
- #33 — check dispatch in `CensorshipCheckKind` (NetworkKit); Intents/scheduler no longer depend on the UI.
- #34 — `PingConfig` presets, `CheckRecord` factories, `UserDefaults.json/setJSON`.
- #38 — the ICMP checksum (RFC 1071 vector) and packet parsing; +19 tests.
- #32 — the **building block** `RunPhase` + `ToolRunModel<Value>` in `Shared/` (with tests).

**Remaining for #32:** migrating ~15 models to `ToolRunModel`. It was meant to be done together with
#15 (`ToolScaffold`), but #15 is already closed, so this is a separate mechanical step: the screens
already use `ToolScaffold`, and the migration comes down to swapping out the internals of each model.
The models are heterogeneous — ~8 one-shot (`run() async throws`) and ~7 streaming (`start()/stop()`
with progress).

**Order (as done):** #35/#36 (security and hang risk) → #37 → #33 → #34 → #38 → #32.

---

## M5 · Platform integrations — in progress

Here the app stops being "a utility you open by hand".

| # | Task | Priority | Status |
|---|---|---|---|
| [#39](https://github.com/AuthFailed/CheckNet/issues/39) | Background monitoring via `BGTask` | P1 | ✅ |
| [#40](https://github.com/AuthFailed/CheckNet/issues/40) | Notifications: actions, time-sensitive, foreground | P2 | ✅ |
| [#41](https://github.com/AuthFailed/CheckNet/issues/41) | Control Center + Lock Screen widgets | P2 | ✅ |
| [#42](https://github.com/AuthFailed/CheckNet/issues/42) | Siri: intent donation, host `AppEntity` | P2 | ✅ |
| [#43](https://github.com/AuthFailed/CheckNet/issues/43) | iCloud sync, Handoff, Spotlight | P2 | ✅ |
| [#44](https://github.com/AuthFailed/CheckNet/issues/44) | Focus filters, interactive Live Activity | P3 | ✅ |
| [#45](https://github.com/AuthFailed/CheckNet/issues/45) | watchOS and visionOS — research | P3 | |

**Order:** #39 → #40 (notifications only make sense once the background works) → #41/#42 → #43 → #44/#45.
The order is soft: #42 was taken before the background tasks as pure, unit-testable code — it doesn't
require on-device verification, unlike `BGTask`/notifications.

**#42 done:** saved hosts became `SavedHostEntity` (`EntityStringQuery`) — in Shortcuts and Siri the
user picks their favorites by name, and any address can be entered manually; a manual ping donates
`PingHostIntent` to `IntentDonationManager` so the system offers it on the lock screen and in Spotlight.
Matching and the codec were extracted into `Shared/SavedHostsPersistence.swift` (a single store key for
both the store and the query) and covered by unit tests in `CheckNetTests`.

**#44 done:** an **interactive Live Activity** — the ping activity (Lock Screen + expanded Dynamic
Island) gained a "Stop" button (`StopPingLiveActivityIntent: LiveActivityIntent`, `#if os(iOS)`) that,
via a shared generation counter (`LiveActivitySignal`, app-group), signals the ping loop to finish; a
baseline is captured at start, so an old tap doesn't kill a new run. The **Focus filter** —
`MonitorFocusFilter: SetFocusFilterIntent` (cross-platform) mutes monitoring alerts in the chosen focus,
persisting the choice in `FocusMonitorState`, which `HostNotifier.post` reads (both foreground and
background). Both flags are pure and covered by tests; actual focus switching is only verified on device.

**Live Activity generalized (beyond #44).** There was only the ping activity; now a single
`CheckActivityAttributes` (status + title + subtitle + up to three chips, `kind` → icon and button)
serves any ongoing check. The controller and widget were renamed to `CheckActivityController` /
`CheckLiveActivityWidget`, and formatting was moved into pure `PingActivityContent` /
`MonitorActivityContent` (unit tests). **Monitoring** now shows a Live Activity (an "N/M online"
aggregate, worst status as the color, Online/Not responding/Hosts chips), updated from the foreground
loop and from `BackgroundMonitor` (by enumerating activities). At the same time `MonitoringManager` was
lifted to app level (`@Environment`) — monitoring used to die when leaving the screen; now it runs for
the whole session, and orphaned activities are killed at start.

**Live Activity brought to all runnable tools — 22 of them.**
- *Ongoing* (a live Dynamic Island): ping, monitoring, speed test (Mbit/s + phase),
  bufferbloat (phase/RTT → an A–F grade with color), MTR (target latency/loss/round), traceroute,
  port and IP scan (an "X/Y" progress + found count), World Ping and network overview (progress), Bonjour
  (service counter), MTU (probe size → path MTU).
- *One-shot* (the result holds for 90s on the lock screen): host→IP, reverse DNS, DNS lookup/compare/
  tamper, whois, TLS, blacklists, CGNAT, IP geolocation.

Scalability: the activity is wired to `ToolRunModel` itself (a seam for the ~10 one-shot tools — they
supply a short `ActivityDescriptor` + a phase→view mapper; `LookupActivityContent` renders
"running / result / error", and a per-result status colors an expired cert / a listing / a tamper red).
Progress scans share `ScanActivityContent`. The content was moved into pure builders in `Shared/` and
covered by unit tests; `kind` → icon in the widget. A race was found and fixed: the models' `start()`
calls `stop()` first, and the async end from `stop()` was killing the just-created activity — so we
moved to a **separate controller per run**. Deliberately without an activity: Wake-on-LAN (a synchronous
instant send — nothing to show), the interface list and the iOS Wi-Fi placeholders. Verified on the
simulator: the MTR activity in the Dynamic Island (compact "30 hops" + expanded view), and lookup
activity creation confirmed by log.

**#39 + #40 done:** **background** — `BackgroundMonitor` (`BGAppRefreshTask`, id
`com.chrsnv.checknet.monitor.refresh` in `BGTaskSchedulerPermittedIdentifiers`, `UIBackgroundModes:
fetch`) reruns the same checks as foreground monitoring while the app is unloaded; it registers in
`init`, and is scheduled on going to background and when monitoring is enabled. **Notifications** —
`HostNotifier` provides a `HOST_STATUS` category with "Open" / "Check again" actions, a foreground
banner (delegate) and a time-sensitive level for outages (degrades gracefully to `.active` without the
paid entitlement). The "whether and what to send" decision was moved into a pure
`Shared/MonitorNotification.swift` (a transition matrix: the first measurement is silent, ok↔degraded
flapping is silent, only down/recovery alert), and host records into a shared `Shared/MonitorStore.swift`;
all covered by unit tests. iOS-only (`BGTaskScheduler` isn't on macOS — a foreground loop stays there).
Real wake-up by the system and delivery are only verified on device; here it's the build, the logic
tests, and a clean start with the task registered on the simulator.

**#43 done:** **Handoff** — the open tool is advertised as an `NSUserActivity`
(`com.chrsnv.checknet.tool`, `Shared/ToolActivity.swift`, declared in `NSUserActivityTypes`) with the
host; on the receiving side it resolves in the root scene through the same `navigator.open` as Spotlight
and controls. **iCloud host sync** is written (`App/Store/CloudHostSync.swift`,
`NSUbiquitousKeyValueStore` + a pure `SavedHostMerge.union` merge, covered by tests), but **dormant**:
`isAvailable = false`, since the `ubiquity-kvstore-identifier` entitlement is only signed by a paid
account — the same barrier as Wi-Fi (`CurrentNetwork.isSSIDReadable`); Settings honestly shows
"Unavailable" with an explanation. The flag and the entitlement flip in a single commit. **Spotlight**
was closed earlier (`acc7a6f`). Cross-device Handoff/iCloud are only verified on a pair of devices; here
it's the build, the codec/merge unit tests, and the Settings render on the simulator.

**#41 done:** two `ControlWidget`s in the extension (`Widgets/CheckNetControls.swift`) — "Ping host"
(shows the last result from an app-group snapshot and, on tap, reopens the check) and "Check blocks"
(opens the tab). Both are **user-added only** (Control Center, lock screen, the Action button) — still
nothing is published to the Home Screen gallery. A tap sends the deep link
`checknet://tool/<raw>?host=&run=1` / `checknet://tab/<name>`, which `onOpenURL` resolves; the link
grammar and the control's value format were moved into `Shared/ControlSupport.swift` and covered by unit
tests. Routing verified on the simulator (Ping with auto-run, the Blocking tab).

> The widgets in #41 are **only those the user adds themselves** (Control Center, lock screen).
> The Home Screen widget doesn't appear after install and must not.

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
fast, but calls drop". `BufferbloatTest` (idle → down → up RTT, an A–F grade, per-phase time limits) +
`BufferbloatView` (the grade, a latency chart by phase, three numbers); verified on a real network.

The most promising from [#49](https://github.com/AuthFailed/CheckNet/issues/49):
**IPv6 readiness**, **QUIC/HTTP-3 availability**, a **network-quality journal** and an
**auto-report for the ISP** — the last a potential killer feature.

---

## M7 · Tools for VPN operators — planned

A new section not for the end user but for the **VPN operator** (the Xray / Reality / mihomo / sing-box /
Happ ecosystem). Right now the app looks at the network through a client's eyes; operators need a
different set — check a domain for Reality, confirm an inbound is alive, parse geosite/geoip and routing
rules, parse a subscription. This niche is nearly empty on the App Store — a potential edge.

**The boundary.** The section stays diagnostics and config management: check, parse, show, assemble a
config. The app **does not perform DPI bypass** and doesn't become a circumvention tool — the same
principle as the Blocking tab (detect, not bypass). We don't build in SNI fragmentation, a fake
ClientHello and the like; we help the operator set up and verify **their own** server.

| # | Task | Priority | Status |
|---|---|---|---|
| [#69](https://github.com/AuthFailed/CheckNet/issues/69) | Epic: the "VPN" section — umbrella task | P2 | 📋 |
| [#70](https://github.com/AuthFailed/CheckNet/issues/70) | Domain suitability as an SNI/dest for Reality | P2 | 📋 |
| [#71](https://github.com/AuthFailed/CheckNet/issues/71) | Xray inbound availability (VLESS/Trojan) — a real handshake | P2 | 📋 |
| [#72](https://github.com/AuthFailed/CheckNet/issues/72) | Subscription parsing — hosts, routing, quick actions | P2 | 📋 |
| [#73](https://github.com/AuthFailed/CheckNet/issues/73) | geosite/geoip viewer — download, parse, tag search, filters | P3 | 📋 |
| [#74](https://github.com/AuthFailed/CheckNet/issues/74) | mihomo rule-set viewer (`.mrs`) | P3 | 📋 |
| [#75](https://github.com/AuthFailed/CheckNet/issues/75) | Subscription server's response to different clients' headers | P3 | 📋 |
| [#76](https://github.com/AuthFailed/CheckNet/issues/76) | Happ routing-rule configurator + parsing | P3 | 📋 |
| [#77](https://github.com/AuthFailed/CheckNet/issues/77) | Happ Decrypt — decrypting Happ configs/subscriptions | P3 | 📋 |
| [#78](https://github.com/AuthFailed/CheckNet/issues/78) | Incy deep link — parse and generate `incy://crypt1` (+ QR) | P3 | 📋 |

**Order:** first the parsers and clients in `NetworkKit` (engine → test → screen), on which the rest
depends: subscription parsing (#72) and the VLESS/Trojan client (#71) are the foundation; the SNI check
(#70) reuses the TLS inspector/`X509Parser`; the viewers (#73/#74) are independent; the routing
configurator (#76) and Happ Decrypt (#77) wait on format specs (see the open questions in the issue).

**Formats reverse-engineered (specs in the issue):** Happ crypt/crypt5 (RSA PKCS#1 + ChaCha20-Poly1305,
public key material) — #77; Happ routing (`happ://routing/add/<base64 JSON>`, exact fields) — #76;
mihomo `.mrs` (zstd + magic `MRS\x01`, LOUDS domain-set / ipcidr) — #74; geosite/geoip `.dat` (protobuf
v2fly, hand-rolled wire format) — #73. Of the dependencies: `.mrs` requires zstd on iOS/macOS (Apple's
`Compression` doesn't provide it).

**Client versions — automatically.** The headers for #75 fill in the current version, pulling it from
GitHub Releases via a `client → repository` map (Happ, Incy, mihomo, sing-box, v2rayNG, Clash Verge Rev,
Hiddify, Karing, FlClash), with a cache and a bundle fallback; the actual UAs come from observed
subscription traffic. The exact Incy/koala-clash/v2raytun/Happ formats are confirmed.

**Official format references wired in:** `Happ-proxy/routing_generator` (the routing generator, the
source of truth for #76) and `INCY-DEV/incy-link-encoder` (the `incy://crypt1` format, AES-256-GCM — for
#78 and #72).

**Additional ideas (issue candidates, from epic #69):** a validator/generator for
`vless://`/`trojan://`/`ss://` links with QR; a Reality config integrity check (SNI/dest, pbk/sid, flow,
ALPN); config "detectability" (uTLS fingerprint/ALPN vs a browser, steal-oneself); external
uptime/latency of inbounds; checking the server IP against blacklists/ASN (reusing DNSBL).

---

## How tests run in CI

Most of the 96 tests hit live hosts — that's deliberate: a check is considered working only after it's
confirmed against a real host. But the GitHub runner isn't a reliable network: ICMP there is usually
filtered, and DNS and TLS to third-party hosts flake. Running that as a blocking gate means reddening
every PR over someone else's failure.

The decision taken is to split the run in two:

- **`unit-tests` — blocking.** Runs with `CHECKNET_SKIP_NETWORK_TESTS=1`; network tests are marked with
  a `try requiresInternet()` call and skipped. What remains is deterministic: parsers, encoders,
  catalogs, webhook delivery to a local server. This job has no right to flake — a red cross here always
  means a regression.
- **`network-tests` — informational** (`continue-on-error: true`). Runs the full set against real hosts.
  A failure is a reason to look, not a reason to block the PR.

Locally the variable isn't set, so `swift test` still runs everything. The real gate for network checks
is a local run before wiring up a tool.

---

## Principles we don't revisit

1. **Test before screen.** An engine in `NetworkKit` + a test against a real host → only then the UI and
   `Tool.isImplemented = true`. Half-working checks never make it into a build.
2. **Detect only, don't bypass.** Blocks are diagnosed; SNI fragmentation, a fake ClientHello,
   record-splitting and other DPI bypass are not added to the app — that's outside the scope of diagnostics.
3. **We impose nothing.** No widgets, permissions or notifications "by default" — the user enables
   everything, and each check explains itself via ⓘ.
4. **Privacy.** Diagnostics run from the device; only what the user explicitly requested leaves it.
   External APIs are wired in only with an explicit explanation in ⓘ.
5. **HIG.** System components over homemade ones; Dynamic Type and VoiceOver aren't optional.
