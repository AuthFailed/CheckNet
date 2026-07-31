# App Store Connect: 1.0 submission checklist

Step by step, in the order of the ASC screens. Values are ready — copy them. **Blockers** are marked
⛔ (without them the Submit button won't unlock). Sources: the other files in this folder.

App: **CheckNet** · bundle `com.chrsnv.checknet` · SKU `checknet-ios` · app id 6796268067.

---

## A. App level (filled in once)

### A1. App Information (left menu → General → App Information)
- **Category**: Primary **Utilities**, Secondary **Developer Tools** (optional).
- **Content Rights**: "Does not contain, show, or access third-party content" → we run our own
  checks; but we show third-party sources (geosite/geoip, iperf-list, bgp.tools). Note that content
  rights exist / aren't required (these are our requests to public services). If in doubt — "Yes,
  contains third-party content" and explain in the notes (see #91).
- ⛔ **Privacy Policy URL**: a hosted URL is required (see the "What's on me" block below). The field
  is mandatory.
- **Localizations**: primary — Russian. English can be added (the metadata below is bilingual).

### A2. App Privacy (left menu → App Privacy) — see `app-privacy.md`
- "Do you or your third-party partners collect data from this app?" → **No, we do not collect data**.
- Confirm the **Data Not Collected** label. No tracking (nothing additional to enable).

### A3. Age Rating (in the version section / App Information → Age Rating) — see `age-rating.md`
- All categories → **None**. **Unrestricted Web Access → No**. Kids Category — don't claim it.
- Expected result: **4+**.

### A4. Pricing and Availability (left menu)
- **Price**: Free (0). Check that the **Free Apps Agreement** is accepted (otherwise the field is
  unavailable).
- **Availability**: all countries (or as desired). For France, the ANSSI crypto declaration is
  separate (see `export-compliance.md`) and does not block the Apple submission.

---

## B. Version 1.0 level (left menu → iOS App → 1.0 Prepare for Submission)

### B1. Texts — see `store-metadata.md`
- **Promotional Text (170)**:
  `A network multitool for iPhone, iPad, and Mac: ping, traceroute, DNS, TLS, port scanners, censorship checks, and tools for VPN-server owners. All on-device, no data collection.`
- **Description**: the block from `store-metadata.md` (#98).
- **Keywords (100)**:
  `ping,traceroute,dns,tls,ssl,port,scanner,network,diagnostics,mtr,whois,ip,bonjour,iperf,speed,dnsbl`
- **Subtitle (30)**: `Ping, DNS, TLS, ports & more`
- ⛔ **Support URL**: a hosted URL (see below). Mandatory.
- **Marketing URL**: optional (can be the same Pages site).
- **What's New in This Version**: not shown for 1.0; if the field exists — `First release of CheckNet.`

### B2. ⛔ Screenshots (#99)
- Required sizes: **iPhone 6.9″** (1320×2868) and **iPad 13″** (2064×2752).
- Not yet taken. I can generate them deterministically via the deep-link harness on the simulator
  (`-openTool <tool> -run`) — see the "What's on me" block.

### B3. ⛔ Build
- Select the processed 1.0 (1) build in the **Build** section (it appears once processing finishes).
- ASC pulls the 1024 icon from the build (single-size AppIcon in the asset catalog) — no separate
  upload needed.

### B4. App Review Information — see `review-notes.md`
- **Sign-in required?** → **No** (there is no account).
- **Contact**: first name, last name, phone, email (yours — ASC requires a reviewer contact).
- **Notes**: paste the English block from `review-notes.md` (section A) — about 5.4 (not a VPN, we
  don't route traffic), scanners (with consent, like Fing), Happ/Incy (public keys), privacy.
- **Demo / attachments**: public targets (1.1.1.1, cloudflare.com) + example links `incy://crypt1/…`,
  `happ://…` to test the decoders (see `review-notes.md` section B).

### B5. Export Compliance
- The build has `ITSAppUsesNonExemptEncryption = false` → ASC **won't ask** anything extra.
  If the question does appear — "uses standard/exempt encryption", exemption (see `export-compliance.md`).

### B6. Version Information
- **Copyright**: e.g. `2026 <your name/brand>`.
- **Routing App Coverage / Marketing**: not required.

---

## C. Submit for Review
- Click **Add for Review** → **Submit to App Review**.
- After submitting, the status: Waiting for Review → In Review. The first review usually takes 24–48 h.

---

## What's on me (I can do it myself)

1. **Screenshots (#99)** — I'll generate a set on the simulator via deep-link across several tools
   (ping/DNS/TLS/scanner/Censorship checks/VPN/Current Wi-Fi network) in the required sizes. Say the
   word — I'll start.
2. **GitHub Pages** for Privacy Policy + Support (#82/#111) — once you give me `<SUPPORT_EMAIL>` and
   a date, I'll fill in `docs/legal/*`, enable Pages, and hand you the ready URLs for fields A1 and B1.

## Yours only
- Reviewer contact (name/phone/email) in B4.
- Accepting the Free Apps Agreement (if not yet accepted) for A4.
- The final Submit (the button).
