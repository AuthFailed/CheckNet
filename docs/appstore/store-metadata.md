# Store metadata, screenshots, icon (#98–#101)

Draft storefront copy + the screenshot/icon plan. The primary language is Russian; English is
attached. The tone is measured — no "circumventing blocks" and no use of the word "VPN" without
"diagnostics/tools" (see `review-notes.md`, the 5.4 boundary).

## #98 · Texts

**Name (30):** `CheckNet — Network Diagnostics`
**Subtitle (30):** `Ping, DNS, TLS, ports & more`
**Category:** Utilities (Primary). Secondary — Developer Tools.

**Promotional text (170):**
`A network multitool for iPhone, iPad, and Mac: ping, traceroute, DNS, TLS, port scanners, censorship checks, and tools for VPN-server owners. All on-device, no data collection.`

**Description:**
```
CheckNet is a set of network checks in a single app, with a native iOS and Mac look.

Diagnostics:
• Ping, traceroute, MTR, MTU
• DNS: lookups, resolver comparison, tamper detection
• TLS certificate inspector, Reality-SNI check
• Port and IP-range scanner (with explicit consent before running)
• Bonjour/mDNS, network browser, interfaces, whois, DNSBL, Wake-on-LAN
• Speed test (iperf3) and IP geolocation

Censorship checks (detection only):
• See exactly what your network restricts — DNS spoofing, IP blocking, SNI-based resets,
  block pages. This is transparency, not circumvention: CheckNet circumvents nothing.

Tools for VPN-server owners:
• Inbound reachability, client-header checks, subscription-link parsing, viewing
  geosite/geoip and mihomo rules. Diagnostics for your own server.

Privacy:
• We collect nothing. Results stay on your device. No accounts, no ads, no tracking.

CheckNet is not a VPN, it does not route traffic and does not circumvent blocks — it's diagnostics.
```

**Keywords (100, comma-separated, no spaces):**
`ping,traceroute,dns,tls,ssl,port,scanner,network,diagnostics,mtr,whois,ip,bonjour,iperf,speed,dnsbl`

**What's New (for 1.0):**
`First release of CheckNet.`

## #99 · Screenshots

Required sizes (Apple's current requirements):
- **iPhone 6.9″** (iPhone 16 Pro Max, 1320×2868) — mandatory.
- **iPad 13″** (2064×2752) — mandatory, since we support iPad.
- 6.5″ — optional (can be reused from 6.9″ via scaling, but better to shoot separately).
- Mac — not needed (the first submission is iOS-only, see #96).

**Harness via deep-link** (already built in: `-openTool <tool> [-host <h>] [-run]`). The plan is to
shoot deterministic screens on the simulator:
```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
SIM=<UDID iPhone 16 Pro Max>   # boot in advance: xcrun simctl boot "$SIM"
xcrun simctl install "$SIM" <path>/CheckNet.app
shoot() { xcrun simctl launch "$SIM" com.chrsnv.checknet -openTool "$1" -host "$2" -run 1; sleep 3; \
          xcrun simctl io "$SIM" screenshot "screens/$1.png"; }
shoot ping 1.1.1.1
shoot dns  cloudflare.com
shoot tls  cloudflare.com
shoot portscan 1.1.1.1
shoot traceroute 8.8.8.8
```
Pick the 5–8 most illustrative (ping with the chart, TLS cert, DNS comparison, port scanner with
consent, the Censorship section, VPN tools). The text on the screenshots — in the language of the
storefront locale.

> Automation (#109, P2): fastlane `snapshot` on top of the same deep-link mechanism — for the future.

## #100 · 1024 icon — ✅ DONE (the "Echo" concept)

The icon is in place: `App/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png` (1024×1024, no
alpha, PNG), the vector source — `docs/appstore/appicon-echo.svg`. The "Echo" concept — concentric
waves + a node (a ping metaphor), the blue from the app's system `.blue`. Verified with `sips`
(`hasAlpha: no`, 1024×1024). Below is the original task context (how it was chosen).



**Fact (verified):** the repository has **neither an icon nor an asset catalog** — no `*.xcassets`,
no `AppIcon.appiconset`, no reference to an icon in `project.yml`/`Info.plist`, no images in git.
Right now the app builds with an empty system icon. For the App Store this is a hard blocker (a 1024 +
the set are required).

The icon is a **design task** (icons aren't drawn ad-hoc in code — it's separate design work). Order:

1. Give the brief below to a design tool, get back a 1024×1024 (ideally with a source/vector).
2. I'll create `App/Resources/Assets.xcassets/AppIcon.appiconset` (single-size 1024, iOS/macOS),
   set `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon` in `project.yml`, regenerate and build.
3. I'll verify: no alpha, no rounding, 1024×1024:
   ```sh
   sips -g hasAlpha -g pixelWidth -g pixelHeight <path>/1024.png   # hasAlpha: no; 1024×1024
   ```

**Ready design brief (paste as-is):**
```
Draw an app icon for CheckNet — a native network-diagnostics app for
iOS 26 / iPadOS 26 / macOS 26 (the same system visual language as Apple's icons: Liquid Glass,
soft depth, legibility at a small size).

What the app is: a "network multitool" — ping, DNS, TLS, port scanners, censorship checks,
tools for VPN-server owners. The audience is technically literate users. The tone is
calm, engineering-minded, not "hacker" — no skulls or lightning bolts.

It needs a network/diagnostics metaphor recognizable at 40 pt: e.g. a pulse/signal, a graph node,
a radar, concentric waves — your choice, but one clear idea, not a collage. Minimal planes, a
legible silhouette. Works on a light and a dark icon-grid background.

Format: a 1024×1024 square with no alpha channel and no rounded corners (the system rounds them
itself), no text and no sticker-style outline. Deliver a final 1024×1024 PNG and, if possible, a
vector source and a preview on the home-screen grid (light and dark themes).
```

## #101 · Metadata localization

- Fully — the primary language (ru). English — from the blocks above.
- Top store languages (de/es/fr/ja/zh-Hans/…): as capacity allows; the app already has 13 languages,
  the metadata can be translated later (P2). Not a blocker for the first submission.
