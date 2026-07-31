# CheckNet Privacy Policy

_Effective date: July 30, 2026. Contact: roman@chrsnv.ru._

CheckNet is a network-diagnostics app. It is designed to **collect no data about you
whatsoever**.

## What We Collect

**Nothing.** CheckNet has no servers, accounts, analytics, ads, or tracking. We do not collect,
store, or transmit your personal data. Check results stay on your device.

## On-Device Data

Settings, saved hosts, and check history are stored **locally** on your device (and, if you
enable iCloud sync, in your personal iCloud storage — which belongs to you, not to us).
You can clear the history in the app's settings at any time.

## Network Requests You Initiate

CheckNet is a diagnostic tool: on your command it contacts the hosts and services that
**you specify**. When you use certain checks, requests are sent to third-party services —
for example:

- IP geolocation (an external geo-service) — only the public IP you are checking is sent;
- "World Ping" and speed-test server lists — requests to third-party catalogs;
- tool version checks — public releases on GitHub;
- DNS-over-HTTPS resolvers — during DNS/censorship checks.

These requests are required for the corresponding check to work. We do not attach any
identifiers to them and do not receive their results — they go directly from your device.

If **you yourself** configure a webhook, CheckNet will send the check result to **your** server
at the address you specify. This is off by default.

## Permissions

- **Local Network** — to discover devices and Bonjour services on your network.
- **Location** (iOS only, if the corresponding feature is enabled) — needed solely so that
  iOS returns the name of the current Wi-Fi network; coordinates are not used and are not sent
  anywhere.
- **Camera** — only to scan a QR code containing your list of saved hosts; images are not sent
  anywhere.
- **Notifications** — for host-monitoring alerts, if you enable it.

## Children

The app is not intended to collect data about anyone, including children, and does not collect it.

## Changes

The current version of this policy is published on this page; the effective date is shown at the top.

## Contact

Privacy questions: roman@chrsnv.ru.
