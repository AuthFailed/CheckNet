# Encryption export compliance (#83)

**Draft determination.** This is not legal advice — confirm the final decision on the flag and on
filing the report yourself. Below is a factual inventory of the crypto in the app and the standard
reading of the rules for this class of app (US EAR + French ANSSI).

> **DECIDED (2026-07-30): `ITSAppUsesNonExemptEncryption = false`.** All crypto uses standard,
> published algorithms via Apple's frameworks (see the inventory below), which falls under the export
> exemption, so the flag is `false`. We tried `true` — it blocks the upload at ingest
> (`Invalid Export Compliance Code`): it requires `ITSEncryptionExportComplianceCode`, which is only
> issued after export-compliance documents are filed in ASC. With `false` the build was accepted by
> App Store Connect. The annual mass-market self-classification with BIS/ENC (15 CFR 740.17) is a
> separate obligation, independent of the flag.

## 1. Cryptography inventory

Everything uses **standard, published algorithms** via Apple's stock frameworks (CryptoKit /
Security), with no in-house implementation of primitives:

| Where | Algorithm | Purpose | Keys |
|---|---|---|---|
| Network checks | TLS 1.2/1.3 (OS) | transport | system |
| `HappDecrypt` | RSA PKCS#1 v1.5 → ChaCha20-Poly1305; AES branch (OpenSSL-salted) | decrypting a Happ config link | **public** (baked into every Happ client; open-source decoders exist) |
| `IncyLink` (`incy://crypt1`) | AES-256-GCM | parsing/generating an INCY subscription link | **public** (constants from the client; open-source encoder) |
| `WebhookDispatcher` | HMAC-SHA256 | signing the webhook | user's secret |

Key facts for the classification:
- No **proprietary** cryptography — only RSA/AES/ChaCha20-Poly1305/SHA-256 via Apple.
- The Happ/Incy crypto is **interoperability and obfuscation, not secrecy**: the keys are public and
  open implementations exist. The user decrypts **their own** configs.
- The webhook HMAC is **message authentication** (one of the explicitly exempt categories).
- The app does **not** provide a VPN tunnel and does **not** encrypt anyone else's traffic (see
  `review-notes.md`).

## 2. US EAR classification

The app falls into Category 5, Part 2 (ECCN 5D002), but uses only standard, published algorithms and
is mass-market consumer software distributed through the App Store — this is the classic case of a
**mass-market exemption, 15 CFR 740.17(b)(1)**:

- **(b)(1)** — no classification request (CCATS) required; **self-classification** is sufficient.
- Obligation: an **annual self-classification report** to BIS and NSA/ENC — once a year, by **February
  1**, for the previous calendar year.
  - BIS: `crypt@bis.doc.gov`
  - ENC/NSA: `enc@nsa.gov`
  - Format — CSV per Supplement No. 8 to Part 742 (name, ECCN 5D002, type — "mass market", contact,
    link to the app). Keep a copy of the submission.
- CCATS/full classification is **not needed** as long as we stick to standard algorithms and
  mass-market.

## 3. France (ANSSI)

Distribution in the App Store in France formally requires a **declaration of import/supply of
cryptographic means** to ANSSI (régime de déclaration). For mass-market software on standard
algorithms this is a declaration, not an authorization. In practice, many small publishers file one
declaration per product.
- Portal: `https://www.ssi.gouv.fr/` → "Contrôle réglementaire de la cryptographie" → déclaration.
- This does **not** block the Apple submission, but it belongs to the M8 legal layer — note it as a
  separate step, don't forget it.

## 4. Decision on the `ITSAppUsesNonExemptEncryption` flag

Two options — pick one and I'll bring the config in line:

**A. Recommended (conservative, defensible): `true` + the exemption path.**
- In `App/Info.plist` → `ITSAppUsesNonExemptEncryption = true`.
- In App Store Connect, at the first build, ASC will ask Export Compliance questions:
  1. "Uses encryption?" → **Yes**.
  2. "Qualifies for exemptions?" → **Yes** (mass-market, standard algorithms, 740.17).
  3. ASC will indicate that an annual self-classification is required — file the BIS/ENC report
     (section 2).
- Pro: honest and audit-resilient. Con: you have to send a report once a year.

**B. Alternative: `false`.**
- Acceptable only if all the crypto is considered exempt (TLS + authentication + "standard algorithms
  via the OS for the user's own data"). Some publishers do this.
- Risk: decrypting configs is not "HTTPS only", the `false` reading is weaker. If Apple/an audit
  disputes it — you'd have to redo it.

→ **I recommend A.** It removes the risk and costs one letter a year.

## 5. What to click (after choosing A)

1. Tell me "we're going with true" — I'll change `App/Info.plist` (one field) and explain in the PR.
2. In ASC, at the first build upload, go through Export Compliance per section 4A's steps.
   (You can also do it in advance under App Information → no; the question appears at the build.)
3. Compose and send the annual self-classification report (CSV) to `crypt@bis.doc.gov` and
   `enc@nsa.gov` — I'll prepare the CSV draft from your contact details.
4. (France) file the ANSSI declaration — separately, doesn't block Apple.
