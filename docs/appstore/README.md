# App Store: submission preparation

Working index for milestone M8. There are two layers here:

- **What is already done in code/config** — verifiable in the repository.
- **What you do by hand** — in Apple Developer / App Store Connect (ASC) / on GitHub Pages.
  Each such item below has its own draft file and a step-by-step "what to click" list.

The drafts intentionally live in the repository as ordinary project documents. Only `docs/legal/*`
(policy and support) become public — those we publish via GitHub Pages.

## Surfaced blockers (important)

- **CI was broken.** Since libXray was added, the iOS/macOS/CodeQL builds had been failing in CI (the
  framework wasn't being fetched). Fixed on branch `feat/m7-vpn-operator-tools` (the `Fetch libXray
  core` step). After a green run, PR #112 is merged into `main` (the localization job stays red → M10,
  by decision).
- **There is no app icon at all** (#100). No asset catalog, no `AppIcon`, no 1024 — a hard submission
  blocker. This is a design task → the design brief is in `store-metadata.md`. Once we have the
  icon, I create the asset catalog and wire it into `project.yml`.
- **`ITSAppUsesNonExemptEncryption=false`** may be incorrect given the Happ/Incy crypto — the decision
  is in `export-compliance.md`.

## What I need from you to clear the remaining blockers

| Needed | Why | Where to get it |
|---|---|---|
| ~~Apple Team ID~~ **`A63H349525`** ✅ obtained | Signing the release archive, App ID capabilities | — |
| Confirm bundle ID | Already set to `com.chrsnv.checknet` (widgets `.widgets`, group `group.com.chrsnv.checknet`) | — |
| Apple ID in Xcode (Settings → Accounts) **or** ASC API key | Automatic signing itself registers capabilities on the App ID at archive time (no manual portal work needed) — see `audit-findings.md` #92 | Xcode / App Store Connect → Users and Access → Integrations |
| Allow local builds | `xcodebuild archive` / `nm` audit of the iOS binary (#88, #92) | confirm in the session |

## M8 task status

### A — code/config (me)
| # | What | Status |
|---|---|---|
| 1 · iCloud sync | flag `CloudHostSync.isAvailable`, tests `SavedHostMerge.union` | code half done, tests present; **waiting on entitlement (Team ID + capability)** |
| 1 · Wi-Fi SSID | flag `CurrentNetwork.isSSIDReadable`, iOS path | code half done; **waiting on entitlement** |
| 1 · Time-sensitive | `HostNotifier` already sets `.timeSensitive` | code ready; **waiting on entitlement** |
| #94 privacy manifest | required-reason API | Swift code is clean (only UserDefaults `CA92.1`, already declared). **libXray is open** — needs an `nm` pass over the binary |
| #93 entitlements audit | bring capabilities in line with the App ID | current files build; dormant ones — I add them together with the Team ID |
| #97 Info.plist sanity | usage strings, orientations, background modes | fine; see `audit-findings.md` |
| #88 private APIs | raw sockets, `rt_msghdr2`, CoreWLAN | statically clean (all under `#if os(macOS)` / `canImport(CoreWLAN)`); **`nm` pass over the iOS binary pending** |
| #95 version/logs/dSYM | debug logs, test hosts | clean: no `#if DEBUG`, no debug `print`, hosts are UI placeholders. Version 1.0/build 1 is fine for the first submission. dSYM — at the archive stage |
| #92 release archive | signing with Team ID, `xcodebuild archive` | **waiting on Team ID** |

### B — your actions (I prepare the drafts)
| # | What | Draft file |
|---|---|---|
| #82 | Privacy Policy + Support | `../legal/privacy-policy.md`, `../legal/support.md` |
| #83 | Encryption export compliance | `export-compliance.md` |
| #85/#86/#87 | Reviewer notes, the 5.4 VPN boundary, crypto/scanners, demo data | `review-notes.md` |
| #89 | App Privacy ("Data Not Collected") | `app-privacy.md` |
| #90 | Age rating | `age-rating.md` |
| #98–#101 | Store metadata, screenshots, icon | `store-metadata.md` |
| #102–#105 | On-device QA | `device-qa-checklist.md` |

## Order

1. **Submission blockers (group A + a technical build):** account/agreements (#80/#81, you), export
   status (#83), distribution signing (#92/#93), privacy manifest (#94), App Privacy labels (#89).
2. **Legal layer in parallel:** policy + support on Pages (#82/#111).
3. **Review risks (B):** reviewer notes and the 5.4 boundary (#85/#86/#87) — the exact reasons our
   app could get rejected.
4. **Storefront + QA:** metadata/screenshots (#98–#101) and an on-device run (#102–#105).
5. **Beta:** TestFlight (#106/#107). **Automation:** fastlane/CI (#108–#111), as needed.
