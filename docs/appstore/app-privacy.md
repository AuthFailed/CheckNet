# App Privacy — "nutrition labels" (#89)

Exact answers for App Store Connect → your app → **App Privacy**. Based on a code audit: the app
**collects nothing** — there are no servers/accounts/analytics/tracking (see
`../legal/privacy-policy.md` and `PrivacyInfo.xcprivacy`).

## What to click in ASC

1. **Data Collection**: "Do you or your third-party partners collect data from this app?"
   → **No, we do not collect data from this app.**
   - Rationale: diagnostics run on-device; results don't leave the device, except the requests the
     user themselves initiates to the hosts/services they specify, and an optional webhook to
     **their own** server. We (the publisher) receive and store nothing.
2. A confirmation appears that the label will be "**Data Not Collected**" — confirm it.
3. **Tracking** (ATT): there is no tracking, `NSPrivacyTracking=false`, no tracking domains declared.
   No advertising/analytics SDKs. → nothing additional needs to be enabled.

## Why "Not Collected" even though there are network requests

Apple distinguishes "data collection" (transmission to the publisher/partners for storage/analysis)
from requests the user initiates to third parties:

- IP geolocation, world ping, speed-test server lists, DoH resolvers, version checks on GitHub —
  these are **tool actions on the user's command**, to services the user chooses to run; we don't
  receive the response and don't attach any identifier.
- Webhook — the user themselves specifies their own server's URL; the data goes to them, not to us.
- Settings/history/saved hosts — on-device only (and in the user's personal iCloud, if enabled).

This fits Apple's "data not collected" exception: the data doesn't go to the publisher and isn't
used for tracking. If we add third-party analytics/a crash reporter, the label would have to change.

> ⚠️ Keep in mind for future changes: any third-party SDK with telemetry (even a "harmless" crash
> reporter) breaks "Data Not Collected". There are none right now.
