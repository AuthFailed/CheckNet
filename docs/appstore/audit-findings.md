# Technical pre-submission audit (#88 / #93 / #94 / #95 / #97)

Actual findings from the code on the M8 branch. Where a built binary is needed, it's marked "pending
build".

## #94 · PrivacyInfo.xcprivacy (required-reason API)

The manifests exist: `App/Resources/PrivacyInfo.xcprivacy` and `Widgets/PrivacyInfo.xcprivacy`. Both:
`NSPrivacyTracking=false`, no collected types, only UserDefaults declared (`CA92.1`).

Audit of required-reason API usage in the **Swift code** (App/Shared/NetworkKit):

| Category | Found | Needs declaring? |
|---|---|---|
| UserDefaults | yes | **yes — already `CA92.1`** ✅ |
| File timestamp | no (`modificationDate/creationDate/getattrlist/stat` not present) | no |
| System boot time | `MonoClock` → `clock_gettime(CLOCK_MONOTONIC_RAW)` — **not on Apple's list** (that lists `systemUptime`/`mach_absolute_time`) | no |
| Disk space | only `.fileSizeKey` in `XrayCoreStore` — that's file size, **not** volume-capacity/`statfs` | no |
| Active keyboard | no | no |

**Conclusion:** for the Swift code the manifest is correct and complete. The assumption from the
ROADMAP (file timestamp / boot time / disk space) doesn't actually hold — those APIs aren't used.

**Open item — libXray (pending build).** `Frameworks/LibXray.xcframework` — a static Go core, **with
no privacy manifest of its own**. The Go runtime may call `stat`/`statfs`/`mach_absolute_time`. Apple
scans the binary's symbols (ITMS-91053). After building, run:
```sh
# over the app's iOS binary:
nm -u "$APP/CheckNet" | grep -E '\b(stat|fstat|lstat|statfs|fstatfs|mach_absolute_time|getattrlist)\b'
```
If the symbols are present — add reason codes to `App/Resources/PrivacyInfo.xcprivacy`:
- File timestamp → `DDA9.1` (files in the app container);
- Disk space → `E174.1` (checking space before writing the core file);
- System boot time → `35F9.1` (measuring intervals).
The reason codes are staged; I'll insert them based on the actual `nm` result.

## #88 · Private APIs (2.5.1)

Risky spots and their gating:

| API | File | Gate | In the iOS binary? |
|---|---|---|---|
| `rt_msghdr2`, `sysctl(NET_RT_FLAGS)` | `NetworkKit/Browser/ARPTable.swift` | `#if os(macOS)` | **no** ✅ |
| CoreWLAN (`CWWiFiClient`) | `NetworkKit/Info/WiFiInfo.swift` | `#if canImport(CoreWLAN)` (macOS-only) | **no** ✅ |
| `NEHotspotNetwork.fetchCurrent` | `App/Network/CurrentNetwork.swift` | public API (not private); behind the `isSSIDReadable` flag | yes, but it's a public API |
| ICMP `SOCK_DGRAM` | `NetworkKit/Support` | public, unprivileged | yes, fine |

**Conclusion:** statically clean — both macOS-only symbols compile out of the iOS build. Final
confirmation is pending build:
```sh
nm "$APP/CheckNet" | grep -iE 'rt_msghdr2|CWWiFiClient|CoreWLAN'   # expect empty
```

## #97 · Info.plist sanity

Checked in `App/Info.plist` / `project.yml`:
- Usage strings in place: `NSLocalNetworkUsageDescription`, `NSLocationWhenInUseUsageDescription`
  (explains it's only for SSID), `NSCameraUsageDescription`. ✅
- `NSBonjourServices` — the full list of types (otherwise mDNS silently fails). ✅
- Orientations: iPhone — portrait + both landscape; **iPad — all 4** (`UISupportedInterfaceOrientations~ipad`
  with `PortraitUpsideDown`). Originally only 3 → the App Store rejected it at ingest, "iPad
  multitasking requires all four". Fixed. `TARGETED_DEVICE_FAMILY=1,2`.
- Background: `UIBackgroundModes=[fetch]` + `BGTaskSchedulerPermittedIdentifiers` — justified (host
  monitoring). ✅ The review justification is in `review-notes.md`.
- Deep links (`checknet`), Live Activities, Handoff (`NSUserActivityTypes`) declared. ✅
- Min deployment iOS 26 / macOS 26. ✅
- ATS: the only exception is `ip-api.com` (an HTTP-only geo service), justified with a comment. ✅
- ✅ `ITSAppUsesNonExemptEncryption=true` (decided) — the Happ/Incy crypto is declared, exemption
  740.17 in ASC + an annual self-classification. Set in `project.yml` and `App/Info.plist`.
  See `export-compliance.md`.

## #95 · Version / debug logs / test hosts / dSYM

- **Debug logs:** no `#if DEBUG`, no debug `print()`. The only logger is the structured `os.Logger`
  in `SpotlightIndexer` (fine for release). ✅
- **Test hosts:** `example.com` / `8.8.8.8` are UI placeholders and input-field defaults,
  `127.0.0.1` is the local SOCKS bind of a test. Not artifacts, no need to remove. ✅
- **Version:** `MARKETING_VERSION=1.0`, `CURRENT_PROJECT_VERSION=1` — correct for a first submission.
- **dSYM (pending build):** for Release, `DEBUG_INFORMATION_FORMAT=dwarf-with-dsym` (the Release
  default) — the dSYM ends up in the archive and is uploaded with the binary. Verify after
  `xcodebuild archive`.

## #93 · Entitlements audit

- **iOS** (`App/CheckNet.entitlements`): currently only the app-group. Dormant ones (`wifi-info`,
  `ubiquity-kvstore-identifier`, `usernotifications.time-sensitive`) are intentionally absent — with
  them, the build won't sign without a Team ID/capabilities. I add them **together** with the Team ID
  and enabling the capability on the App ID (otherwise both the local and the CI build break).
- **macOS** (`App/CheckNet-macOS.entitlements`): sandbox + network client/server — correct, the
  ad-hoc build passes.
- **Widgets**: app-group — correct.
- **Conclusion:** the current set builds. Aligning with the App ID (enabling the dormant ones) is a
  step with the Team ID; Xcode's automatic signing creates the profile.

## #92 · Release archive — Team ID `A63H349525`

**On capabilities (from Apple's docs, Adding capabilities / Configuring iCloud services):** with
**automatic signing**, Xcode itself enables the capability on the App ID in the developer account.
We write entitlements via XcodeGen, so registration is done by automatic signing at archive time with
the `-allowProvisioningUpdates` flag. So **manually enabling these four in the portal is generally not
needed** — they auto-provision: App Groups (`group.com.chrsnv.checknet`), iCloud **Key-Value storage**
(a container is NOT needed — containers are only for Documents/CloudKit), **Access Wi-Fi Information**,
**Time Sensitive Notifications**.

**What's needed to authorize automatic signing (one of):**
- An Apple ID on team `A63H349525` added to Xcode (Settings → Accounts), **or**
- An App Store Connect API key (`-authenticationKeyPath *.p8 -authenticationKeyID <id>
  -authenticationKeyIssuerID <issuer>`).

**Order (one coordinated step):** I add 3 entitlements + flip 2 flags → `xcodebuild archive` with
automatic signing (registers capabilities on the App ID) → verify on-device that the features
actually work. I don't flip the flags before the archive: otherwise the signed build would show a
control that can't yet be signed (exactly what `isAvailable`/`isSSIDReadable` were built to prevent).

**Ready patch for the dormant features** (applied in one commit after enabling capabilities) —
in `App/CheckNet.entitlements`:
```xml
<key>com.apple.developer.networking.wifi-info</key><true/>
<key>com.apple.developer.usernotifications.time-sensitive</key><true/>
<key>com.apple.developer.ubiquity-kvstore-identifier</key>
<string>$(TeamIdentifierPrefix)$(CFBundleIdentifier)</string>
```
+ `CloudHostSync.isAvailable = true`, `CurrentNetwork.isSSIDReadable = true` (HostNotifier is ready).

**Archive command:**
```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild -project CheckNet.xcodeproj -scheme CheckNet \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/CheckNet.xcarchive \
  DEVELOPMENT_TEAM=A63H349525 CODE_SIGN_STYLE=Automatic \
  -allowProvisioningUpdates archive
```
What I need from you for the run: (1) an Apple ID on this team logged into Xcode **or** an ASC API key
in the environment; (2) capabilities enabled; (3) permission to build locally in the session. After
the archive — the `nm` audit (#88/#94-libXray) and a dSYM check (#95).

## ✅ Verified on the signed archive (Release, dev-signed, `-allowProvisioningUpdates`)

`ARCHIVE SUCCEEDED`. Automatic signing registered the App ID + capabilities with no manual portal work.

- **#93 — entitlements signed** (verified with `codesign -d --entitlements`): `wifi-info`,
  `usernotifications.time-sensitive`, `ubiquity-kvstore-identifier`
  (`A63H349525.com.chrsnv.checknet`), `application-groups`. The three dormant features are enabled.
- **#88 — clean**: `nm` over the iOS binary showed no `rt_msghdr2`/`CWWiFiClient`/CoreWLAN.
- **#94 — libXray**: the binary imports `_stat`/`_fstat`/`_lstat` (file-timestamp) and
  `_mach_absolute_time` (boot-time). Reason codes `DDA9.1` and `35F9.1` added to
  `App/Resources/PrivacyInfo.xcprivacy`. Disk-space (`statfs`) not found — not declared.
- **#100 — icon** compiles into the archive (`AppIcon60x60@2x.png`, `AppIcon76x76@2x~ipad.png`,
  `Assets.car`).

**Distribution `.ipa` built ✅.** `xcodebuild archive` (automatic) → `xcodebuild -exportArchive` with
`Scripts/ExportOptions-AppStore.plist` (`method: app-store-connect`, `signingStyle: automatic`,
`-allowProvisioningUpdates`). Result: `build/export-store/CheckNet.ipa` (~19 MB), signed with
**Cloud Managed Apple Distribution** (Team A63H349525), App Store profiles auto-created for
`com.chrsnv.checknet` and `.widgets`. #92 fully closed.

**✅ Build uploaded to App Store Connect (2026-07-30).** The app record — `com.chrsnv.checknet`,
SKU `checknet-ios`, app id 6796268067; uploaded via `xcodebuild -exportArchive destination: upload`
+ ASC API key. `Upload succeeded`. The build is processing (~5–15 min), then it appears in TestFlight.

Two ingest blockers along the way (both fixed and in the binary):
- iPad orientations (all 4 needed) — see #97 above.
- `ITSAppUsesNonExemptEncryption` → `false` (exemption; `true` requires a compliance code from ASC) — #83.

**Remaining:** wait for the build to finish processing → fill in the metadata (`store-metadata.md`),
App Privacy (`app-privacy.md`), Age Rating (`age-rating.md`), reviewer notes (`review-notes.md`),
screenshots (#99) → submit for review. The annual BIS self-classification (#83) — separately.
