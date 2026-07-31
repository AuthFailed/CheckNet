# Stage 4 — expanding the "Blocking" section

The plan is based on measurement sources (net4people/bbs, IMC'21/'22 TSPU, OONI spec, DEF CON 33). Every check is **detection only**: the app records what the network restricts, and does not help circumvent it. This rule applies to all the new checks below as well.

Platform: iOS and macOS. The Mac target builds and runs; Live Activities are disabled there,
and the adaptive layout is a separate task.

---

## 0. Common rules, without which every check lies

This is the foundation — to be done before the checks themselves.

### 0.1 Captive portal pre-check (blocks everything else)
A request to `http://captive.apple.com/hotspot-detect.html`, with the expected body being exactly `<HTML><HEAD><TITLE>Success</TITLE></HEAD><BODY>Success</BODY></HTML>`. Any other response → portal. **On a positive result the remaining checks do not run**, and an explanation is shown. Otherwise hotel Wi-Fi lights up the whole panel with false blocks.

### 0.2 A fresh source port for every probe
TSPU keeps conntrack-like state on the 5-tuple. Residual blocking after a trigger fires: SNI-I **75 s**, SNI-II **420 s**, SNI-IV **40 s**, QUIC **420 s**. A retry inside that window will fail regardless of the actual network state. A new socket gives a new port — that is already the case, but retries must be spaced out deliberately, and a failure inside the window must not be treated as proof.

### 0.3 MTU as a disqualifier
A low path MTU produces the same "small passes, large freezes" picture as `l4-25`. The existing MTU discovery runs **before** the packet checks; when the MTU is abnormally low, no `l4-25` verdict is issued.

### 0.4 CGNAT lowers the weight of concurrency-based checks
CGNAT (a local address in `100.64.0.0/10`, or local ≠ public) itself causes port exhaustion under concurrency. When it is detected, the verdict of the "Siberian" check is marked as unreliable. We already have a CGNAT tool — reuse it.

### 0.5 Verdict vocabulary — following the OONI model
- **confirmed** — only on a match with a fingerprint (block page, known censorship IP).
- **anomaly** — there are signs of interference, corroboration is needed. This is the default for almost everything.
- **ok** / **inconclusive**.

A single measurement is not a verdict. Wording must reflect the observation ("the TLS connection dropped after ClientHello"), not the motive.

### 0.6 Failure classification by errno
A single parser for all checks; this is the main discriminator of the mechanism:

| errno | Meaning | Interpretation |
|---|---|---|
| `ECONNRESET` | reset | RST injection (on-path) |
| timeout with no bytes | drop | silent drop (in-path) |
| clean EOF | cut | cut in the middle |
| TLS alert | — | **not censorship**, server side |

---

## 1. Checks — in implementation order

Order = usefulness × detection reliability from an unprivileged iOS client.

### 1.1 The "16–20 KB" check ⭐ first

The name is user-facing and stays, but the check runs **three variants**, because the mechanism turned out not to be byte-based: the real trigger is **~25 packets** in either direction (~16 KB on average, observed spread 14–34 KB), and the connection **silently freezes, with no RST arriving**. It works on TCP and UDP, is port-independent, and is symmetric across directions. The targets are foreign ASNs (Cloudflare, Hetzner, OVH, DigitalOcean, AWS).

The variants give different answers to "what exactly is the censor counting", and together they distinguish a byte threshold, a packet threshold, and no filter at all.

**Variant A — byte accumulation** (matches the original "16–20 KB" wording).
A single keep-alive TLS connection to IP:443. Request `i = 0` with no padding — this is the liveness control. Requests `i = 1…15` with **4 KB** of padding (cumulatively 4→60 KB). Read timeout `max(RTT × 3, 1.5 s)`, cap **12 s**. Positive if `i = 0` passed and some `i ≥ 1` froze. **We report the exact byte offset** — that is the number the user expects to see.

**Variant B — packet counter** (decisive).
TCP → target:443, `TCP_NODELAY`, TLS. Send ~**64 bytes** in **2-byte** chunks with a **50 ms** pause → ~32 packets. Wait up to **5 s**.

**Variant C — segmentation control** (paired with B).
The same 64 bytes in **a single segment** to the same IP:port.

A freeze in B while C succeeds is a packet counter and nothing else: 64 bytes of traffic, no harmless explanation. If A fires but B does not, the threshold really is byte-based, and that is a separate finding.

**Target pairing:** foreign ASN + Russian control (Selectel, Yandex Cloud). "The foreign one freezes, the Russian one holds" is far stronger than any single result.

**False positives:** very low for B+C, moderate for A — congestion produces timeouts at an arbitrary point, so for A require reproduction across **≥3 different ASNs**. Everywhere require the control to succeed. Warn that with circumvention tools enabled the result is meaningless.

### 1.2 Whitelist SNI+CIDR ⭐ second

A refinement of the existing check. The censor keeps a list by **SNI** *and* by **destination CIDR**, and since 2026 checks them together.

**Test A — SNI sensitivity at a fixed IP:** two TLS connections to **the same** foreign IP:443, differing only in SNI: neutral (`example.com`) versus whitelisted (`vk.com`, `yandex.ru`). A difference = SNI whitelist. Six bytes of plaintext change in the ClientHello — an almost ideal pair.

**Test B — CIDR sensitivity:** fix a whitelisted SNI, vary the destination (whitelisted ASN versus a foreign one).

Together they give three states: no whitelist / SNI only / SNI+CIDR.

`sec_protocol_options_set_tls_server_name` lets you set the SNI independently of the endpoint. **Browser-based checkers cannot do this** — a native app is objectively stronger here than any web test.

**False positives:** low. A server-side cause differs by the *mode* of failure: the server responds with an alert or a 4xx quickly, whereas a whitelist gives a timeout with no alert. Use targets that serve a default certificate for an arbitrary SNI.

### 1.3 TLS truncation — RST versus timeout classification

The existing SNI-RST check, taken to a diagnostic level.

**Mechanisms (IMC'22):** SNI-I — rewriting the server packet into **RST/ACK** (not injecting an extra one, so TTL/seq are not anomalous and the classic TTL test will not work); SNI-II — 5–8 more packets pass, then a symmetric drop; SNI-IV — dropping everything including the ClientHello, as a fallback filter.

**Recipe:**
1. TCP connect. **If TCP passed but TLS failed, an IP block is ruled out**, which is a useful narrowing in itself.
2. ClientHello with the target SNI → classify by errno (see 0.6).
3. **Control A:** same IP, neutral SNI. Success here + a failure above = a name-based trigger, and it rules out an IP block, routing, and a server crash all at once.
4. **Control B:** same SNI, a different IP.
5. Show **the distribution of failure modes across targets**. All timeouts versus all RSTs are different DPI deployments by different operators, and that is information a user genuinely finds interesting.

### 1.4 Unreachability / IP block

**Behavior:** a drop regardless of port and payload, **ICMP to blocked IPs is dropped too**. Residual blocking lives for months.

**Recipe:** ICMP (4 probes) + TCP on **443**, **80** and an arbitrary high port (7777) + **a control to a neighboring IP in the same AS**. Positive when ICMP is silent, all three ports time out (not refused), and the control passes. The combination of "port independence + ICMP loss" distinguishes this from `l4-25` (which needs an established connection) and from an SNI block (which needs a successful TCP).

Plus a traceroute to the target and to the control: TSPU is in the first **~5 hops** (the GFW, for comparison, is at ~14), and a divergence at hop 2–3 is strong corroboration. We have MTR.

**False positives:** ICMP is dropped en masse for harmless reasons — **never issue a verdict on a single ICMP result**. A control in the same AS is mandatory.

### 1.5 "Siberian" blocking — policing by connection count

A refinement of the existing check. It fires **much earlier** than commonly assumed: a measurement (Novosibirsk, MTS, November 2025) — around **12** TLS connections in a short window, and **even to Russian servers and from an ordinary browser**. Recovery ~60 s.

**Recipe:** a single sequential handshake (control) → **16** connections at **~100 ms** intervals → record where the timeouts began → **check recovery**: a sequential handshake after 60–120 s.

**The recovery timer is the diagnostic.** Server-side limits give an immediate refusal or RST; here it is a freeze that releases on a clock. "Connections were frozen for 118 s" is far more convincing to a user than "some handshakes didn't go through".

**False positives: moderate, the highest in the list.** CGNAT port exhaustion, radio state transitions, server-side rate limits. Mandatory: the recovery timer, a successful control beforehand, two targets in different ASes, weight reduction under CGNAT. **A consent gate is needed** (`SensitiveConsentModifier`) — the check itself degrades connectivity for a minute.

### 1.6 DNS — interception and tampering

Two decisive subtests that are missing today:

- **A response from a non-resolver.** The same query to a public resolver and to an IP where there is no DNS server at all. **A correct response from a non-resolver is proof of transparent on-path interception.** There is no harmless explanation. Cheap and almost free of false positives.
- **Injection race.** Do not close the UDP socket after the first response; wait ~2 s. **Two different responses to one query are proof of injection.**

Plus: NXDOMAIN hijacking (a random nonexistent label — any A response = tampering); block-page fingerprint (collect the operator's stub IPs beforehand by resolving known-blocked domains); DoH/DoT availability across transports (53 / 443 / **853**) with errno classification; an SNI control for DoH (a neutral SNI to the provider's IP — separates "DoH is blocked" from "the IP is unreachable").

**Important:** compare responses **by AS, not by IP** — a CDN legitimately serves different IPs. And architecturally: DNS manipulation is done by **the operator's resolver** (hops 5–8), not by TSPU (hops 1–3) — these are different layers, and the UI should keep them apart.

**Freshness caveat:** my knowledge of DoH/DoT mechanics is from 2021. Verify, don't assert.

### 1.7 IPv4 versus IPv6

Filtering is often deployed on IPv4 only. Identical probes over A and AAAA, then compare. Cheap, and the existing tools (`dpi-ch`) do not cover it at all.

**False positives:** broken or tunneled IPv6 on consumer networks is common, so an IPv6 baseline against a known-reachable target is needed.

### 1.8 TLS MITM / certificate substitution

Compare the SPKI hash and issuer against those expected for a pinned host. **Show the issuer** — almost every trigger is corporate MDM or antivirus, and the issuer name lets the user recognize it instantly. Word it neutrally.

### 1.9 Outbound port filtering

TCP on 25, 445, 853, 1194, 5060, 51820 + a control high port. Distinguish `ECONNREFUSED` (reached) from a timeout (filtered). **Present it under "network policy", not "blocking"** — this is almost always ordinary operator policy.

---

## 2. What we deliberately do not do

- **QUIC/UDP:443** — data only from March 2022 (version v1, payload ≥1001 bytes, port 443). The current status is unknown, and UDP:443 breaks on many networks for harmless reasons. Silence is weak evidence. If done at all, only as a differential probe with three controls, and presented as information, not a verdict.
- **ECH** — data from November 2024: the trigger is the conjunction "ECH extension + SNI `cloudflare-ech.com`". The design is clean (three arms, firing only on the conjunction), but the intel is 20 months old and requires hand-building three ClientHellos differing by exactly one field. An encoding error looks identical to blocking. Verify on a real network before enabling.
- **Detecting VPN-protocol blocking** — a high false-positive risk and legally sensitive wording. Silence of a UDP handshake is the most overdetermined item in the list. If done, **only as neutral connectivity diagnostics** ("UDP 51820: no response; UDP 23456: response"), without a "your VPN is blocked" label. Separately: the documented Russian rule fires **after** the handshake (>15 P_DATA for OpenVPN, >2 data packets for WireGuard), so checking handshake success is useless here — it will report success on a network where the tunnel is unusable.
- **TSPU fingerprint by IP fragmentation** (a limit of 45 fragments versus 64 on Linux; 0.7% of hosts worldwide behave this way) — an ideal marker, but it requires `SOCK_RAW`, i.e. root. **Not available on iOS.**
- **Throttling by record-and-replay** — the best methodology in its class, but it needs our own server. Without it, it can't be done honestly.
- **CDN degradation versus congestion** — cannot be separated without controlled infrastructure. Either do it for real or don't do it.

---

## 3. UI

The request was for "several sections with switching via a bottom menu". **The bottom menu is already taken by the root `TabView`** (Tests / Blocking / Settings), and a second row of tabs at the bottom is against HIG and would look alien on iOS 26.

Instead I propose sections in a single `List` inside "Blocking", plus a `Picker(.segmented)` in the toolbar as a filter:

- **Blocking** — DNS tampering, IP block, SNI-RST, HTTP block page, whitelist
- **Unreachability** — IP block, ports, IPv4/IPv6
- **Degradation** — `l4-25`, Siberian, throttling
- **DNS** — interception, injection, DoH/DoT
- **Integrity** — TLS MITM, transparent proxy

Checks run **one at a time only**. There is no "Run all" button: some checks deliberately degrade connectivity for a minute (see 1.5), and a mass volley against someone else's network is exactly the behavior that `SensitiveConsentModifier` guards against.

---

## 4. Work order

1. Common rules 0.1–0.6 (captive-portal gate, errno classifier, verdict vocabulary) — the foundation.
2. `l4-25` — engine in `NetworkKit/Censorship`, a test against a real host, then the screen.
3. Whitelist SNI+CIDR — refining the existing one.
4. TLS truncation classification — refining the existing one.
5. Unreachability / IP block.
6. Siberian — recovery timer + consent gate.
7. DNS interception (two decisive subtests).
8. IPv4/IPv6, TLS MITM, ports.
9. Restructuring the UI into sections.

Every engine follows the project's golden rule: first a test in `Packages/NetworkKit/Tests/`, a green `swift test`, and only then the screen and `isImplemented`.

---

## Sources

- net4people/bbs [#490](https://github.com/net4people/bbs/issues/490) (`l4-25`), [#546](https://github.com/net4people/bbs/issues/546) (Siberian), [#516](https://github.com/net4people/bbs/issues/516) (whitelist), [#274](https://github.com/net4people/bbs/issues/274) (VPN protocols), [#363](https://github.com/net4people/bbs/issues/363) (fully-encrypted)
- [hyperion-cs/dpi-checkers](https://github.com/hyperion-cs/dpi-checkers) — `utils/l4-25_prober.py`
- Xue et al., [TSPU: Russia's Decentralized Censorship System, IMC 2022](https://ensa.fi/papers/tspu-imc22.pdf); [Throttling Twitter, IMC 2021](https://censoredplanet.org/assets/throttling-imc-paper.pdf)
- [OONI spec](https://github.com/ooni/spec/tree/master/nettests) — especially `sni_blocking` (ts-024), `tlsmiddlebox` (ts-037), `echcheck` (ts-039), [df-007-errors](https://github.com/ooni/spec/blob/master/data-formats/df-007-errors.md)
- [OONI Russia report 2024](https://ooni.org/post/2024-russia-report/), [Interpreting OONI data](https://ooni.org/support/interpreting-ooni-data/)
- DEF CON 33, Mixon-Baca, [TSPU: Russia's Firewall](https://www.youtube.com/watch?v=zcdEX1ZgXzY)
