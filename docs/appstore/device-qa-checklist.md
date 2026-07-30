# On-device QA (#102–#105)

Checklist for a run on your iPhone/iPad. Almost everything below the simulator either hides or fakes —
so it's done on real hardware before submission. Mark ✅/❌ and note what broke.

## #102 · Platform features (device-only)

- [ ] **Local Network Privacy.** On the first tool that touches the LAN (Bonjour/network browse/scan),
      iOS shows the system prompt for local network access. Allow → devices/services are found. Deny
      → the tool honestly shows an error and doesn't "hang".
- [ ] **BGTask wake-up.** Enable host monitoring, background the app. After a while (can be forced
      from Xcode: Debug → Simulate Background Fetch) a check arrives. The identifier
      `com.chrsnv.checknet.monitor.refresh` is registered.
- [ ] **Notifications.** Monitoring catches the up→down and down→up transitions, a banner arrives; the
      "Open"/"Check again" actions work; a tap opens the right screen.
- [ ] **Time-sensitive (after the entitlement).** A host-down notification arrives as Time-Sensitive
      (breaks through Focus, if allowed). Before the entitlement — it arrives as a regular one (this
      is expected, not a bug).
- [ ] **Handoff.** Open a tool on one device → on the second (same Apple ID) a continuation icon
      appears in the dock; a tap opens the same tool.
- [ ] **Live Activity / Dynamic Island.** A long check (monitoring/speed) shows a Live Activity on the
      Lock Screen and in the Dynamic Island (iPhone 14 Pro+); it updates and finishes correctly.
- [ ] **Controls (Control Center / Lock Screen).** Added by the user, they launch the right tool via
      deep-link.
- [ ] **Deep links / Shortcuts.** `checknet://` + App Intents open a tool and start a check.

## #103 · Stability

- [ ] Cold start without a crash on iPhone and iPad.
- [ ] Go through **all** tool screens — no crash/hang on any of them.
- [ ] **No network** (airplane mode): checks give a clear error, don't crash and don't hang.
- [ ] No memory leaks on repeated runs of heavy tools (range scan, speed, monitoring) — check in
      Instruments/Xcode Memory graph.
- [ ] Rotation (iPhone landscape, iPad split view) doesn't break the layout.

## #104 · Accessibility

- [ ] **VoiceOver** goes through the key screens: catalog, tool screen (idle→running→result),
      Censorship checks, Settings. Every icon-only control has a label.
- [ ] **Dynamic Type** up to accessibility sizes: text isn't clipped, cards grow, nothing overlaps.
- [ ] Tap targets ≥44 pt.
- [ ] Status is readable **not by color alone** (shape + word) — check with a color-vision filter.

## #105 · A "clean" device without paid entitlements (dormant features)

Verify that before the paid capabilities are enabled the app behaves honestly rather than "pretending":

- [ ] **iCloud host sync** (`CloudHostSync.isAvailable=false`): in Settings it's either hidden or
      shown as "unavailable", the toggle doesn't pretend to work. Doesn't crash.
- [ ] **Wi-Fi SSID on iOS** (`CurrentNetwork.isSSIDReadable=false`): the "check current network" action
      is hidden/marked unavailable; the app does NOT ask for location for a lookup that wouldn't work
      anyway.
- [ ] **Wi-Fi tools on iOS**: show a "available on Mac" placeholder, not an empty/broken screen.
- [ ] After the entitlement is enabled (the next build): the same features become available and
      actually work on-device (SSID reads after location permission; iCloud picks up hosts from the
      second device; time-sensitive arrives as time-sensitive).

## How to install a build on a device

- Via Xcode (Run on a connected device) or a TestFlight build (#106).
- Automatic signing needs your Apple ID signed into Xcode and the Team ID in the project — see
  `README.md` (the Team ID section) and #92.
