# Reviewer notes and App Review boundaries (#85 / #86 / #87)

The goal is to remove the two main review risks: **5.4 (VPN)** and **sensitive tools** (network
scanners, crypto decoders). The app is diagnostics and config preparation; it does **not** route
traffic and does **not** circumvent restrictions.

---

## A. Text for App Review Information (App Store Connect → "Notes")

> Paste into the Review Notes field. English — the reviewer reads it in English. Keep it short and
> direct.

```
CheckNet is a network-diagnostics utility (like Fing/iNet) with an extra section of read-only
tools for people who run their own VPN servers. It does NOT provide a VPN tunnel, does NOT route
or proxy the user's traffic, and does NOT circumvent any network restriction. Every tool is
diagnostic: it measures or inspects, it does not change how the device connects.

Guideline 5.4: The app installs no VPN configuration and contains no NEVPNManager / Network
Extension packet-tunnel. The "VPN" section is a set of checks an operator runs AGAINST a server
they already control (is the inbound reachable, does the TLS/Reality handshake look right, what
egress IP does the proxy show). Nothing tunnels the user's own traffic.

Sensitive tools and why they are safe/legitimate:
- Port scan / IP-range scan / Reality dest scanner: standard diagnostics. They run only after an
  explicit in-app consent dialog that explains what will happen. Intended for the user's own hosts
  and networks (same category as Fing, which is approved).
- "Blocking" (Censorship checks): transparency/diagnostics only — they DETECT what the local
  network blocks by comparing a probe to a control. They contain NO circumvention (no DPI bypass,
  no SNI fragmentation, no domain fronting).
- Happ Decrypt / Incy link (crypt1): these decode the operator's OWN subscription links using
  PUBLIC keys that ship inside the corresponding open-source clients. Standard algorithms
  (RSA, AES-GCM, ChaCha20-Poly1305) via Apple frameworks. It is a convenience decoder, not an
  attack tool — it only reads data the user already possesses.

Privacy: the app collects nothing. All results stay on device; the only outbound traffic is the
checks the user starts and, if the user configures one, a webhook to a server the user owns.

Demo: no login required. See the "How to try the VPN section" steps below and the demo data.
```

## B. How the reviewer runs the VPN section (demo data)

The reviewer must be able to tap and see a result without our infrastructure. Prepare:

1. **A demo host / subscription** that lives for the duration of the review (can be stood up on a
   cheap VPS or a reused test one). State it directly in the notes:
   - `Tests` → `Ping` / `TLS inspector`: `1.1.1.1`, `cloudflare.com` — work without our infra.
   - `VPN` → inbound/Reality check: demo address `<DEMO_HOST:PORT>`, SNI `<DEMO_SNI>`.
   - `VPN` → Happ/Incy: attach an **example link** `incy://crypt1/<...>` and `happ://<...>` — the
     reviewer pastes it and sees that it decoded into a plain subscription URL.
2. **A deep-link for a quick demo** (already in the app): `checknet://` +
   `-openTool <tool> -host <h> -run` — you can give the reviewer a couple of ready links.
3. Explicitly write "no account needed", so they don't apply 5.1.1 (login).

> TODO for you: decide whether we stand up a separate demo host for the review or give public targets
> (1.1.1.1, etc.) + static example links. Public targets + example links are the minimum sufficient;
> a demo host improves the chance of passing on the first try.

## C. The 5.4 boundary — what the code guarantees (for #87)

Verifiable facts (can be shown to the reviewer and kept as a self-check before submission):

- **No** `NEVPNManager`, `NETunnelProvider*`, `NEPacketTunnelProvider`, no Network Extension target.
- **No** `com.apple.developer.networking.networkextension` / `packet-tunnel-provider` entitlement.
- libXray is used **in-process** only to spin up a local inbound/egress check and immediately tear it
  down — not as a system tunnel.
- The proxy runner listens on `127.0.0.1` for a local SOCKS test, it doesn't intercept system traffic.

Self-check (keep it green):

```sh
# Should be empty:
grep -rn "NEVPNManager\|NETunnelProvider\|NEPacketTunnel\|packet-tunnel" App Shared Packages Widgets \
  | grep -v "\.build/"
```

**Mitigation if at risk:** if the reviewer takes issue with the word "VPN", rename the section to
"Operator Tools" (the tab-title string) — the content doesn't change. Keep this as a fallback, don't
do it preemptively (the section is honestly about VPN servers).

## D. Wording in the store description (see `store-metadata.md`)

- Don't write "VPN" as a category/feature without the word "diagnostics/tools".
- An explicit line in the description: "CheckNet is not a VPN, it does not route traffic and does not
  circumvent restrictions — it's diagnostics and config preparation."
- Don't promise circumvention of blocks anywhere in the metadata (otherwise 5.4 + a likely reject).
