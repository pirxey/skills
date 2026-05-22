# BIMI — Brand Indicators for Message Identification

BIMI displays the sender's logo next to authenticated mail in supporting inboxes (Gmail, Yahoo, Apple Mail since iOS 16). It is the most user-visible payoff for setting up SPF/DKIM/DMARC properly — and the strictest in its requirements.

BIMI is only relevant once **DMARC is at `quarantine` or `reject` with `pct=100`** (see [DMARC policy ladder](./dmarc.md#the-policy-ladder)). Otherwise mark the BIMI verdict `n/a`.

## Lookup

```bash
dig +short TXT default._bimi.example.com @1.1.1.1
```

Selectors other than `default` are allowed (set via `BIMI-Selector:` header on outbound mail), but `default` is what 99% of senders use.

## Record anatomy

```
v=BIMI1; l=https://example.com/logo.svg; a=https://example.com/vmc.pem
└─────┘ └────────── SVG URL ──────────┘ └──────── auth cert URL ─────┘
```

| Tag | Meaning |
|---|---|
| `v=BIMI1` | Required. Must be first. |
| `l=` | HTTPS URL to the SVG logo. Required. |
| `a=` | HTTPS URL to the **VMC** or **CMC** PEM file. Required by Gmail and Apple Mail. Yahoo currently allows BIMI without it for trademarked brands. |

A record with `l=` but no `a=` is sometimes called **"BIMI lite"** — only Yahoo will render it.

## The four things that must all be true

### 1. DMARC must be enforced

- `p=quarantine` or `p=reject`
- `pct=100`
- The organizational domain must publish DMARC — `_dmarc.example.com` when BIMI is published at `example.com`

Some receivers also require **`sp=`** be enforced when BIMI is published at the apex but mail is sent from subdomains.

### 2. The SVG must conform to SVG Tiny 1.2 + PS profile

Validate with:

```bash
curl -sL "$SVG_URL" -o /tmp/logo.svg
# Check size
wc -c /tmp/logo.svg   # must be < 32KB
# Check XML structure
xmllint --noout /tmp/logo.svg
```

**Required:**

- `<svg>` root element with `version="1.2"` and `baseProfile="tiny-ps"`
- `xmlns="http://www.w3.org/2000/svg"`
- Square `viewBox` (width and height equal, e.g. `0 0 64 64`)
- `<title>` element with the brand/logo name
- File size **strictly less than 32 KB**

**Forbidden:**

- `<script>` (any)
- External references: `<image href="https://...">`, `<use href="https://...">`
- Animation: `<animate>`, `<animateMotion>`, `<animateTransform>`, `<set>`
- Interactivity: `onclick`, `onload`, `<a href>`
- Foreign content: `<foreignObject>`
- Embedded raster: `data:image/png` inside `<image>`
- XML processing instructions other than the XML declaration
- Comments referencing external entities, DOCTYPEs with external DTDs
- CSS `@import`, `url(...)` pointing off-domain
- Filters that reference external resources

**Tooling:**

- [BIMI Group SVG Checker](https://bimigroup.org/bimi-generator/) — official
- [EasyDMARC SVG Validator](https://easydmarc.com/tools/bimi-record-check) — visual
- `svgcheck` (Python) for CI

A common conversion path from PNG: Inkscape → File → Save As → "Optimized SVG" → manual strip of unsupported attrs → set `baseProfile="tiny-ps"`.

### 3. The VMC / CMC certificate

The `a=` URL serves a PEM file containing the certificate chain. There are two acceptable types:

- **VMC (Verified Mark Certificate)** — requires a **registered trademark** of the logo in a participating jurisdiction (USPTO, EUIPO, JPO, CIPO, IPA, IP Australia, etc.). ~$1,500–$2,000/year. Issued by DigiCert or Entrust.
- **CMC (Common Mark Certificate)** — for logos used in commerce for 5+ years, no trademark required. Cheaper. Recognized by Gmail since 2024.

Validate the PEM:

```bash
curl -sL "$PEM_URL" -o /tmp/cert.pem
openssl crl2pkcs7 -nocrl -certfile /tmp/cert.pem | openssl pkcs7 -print_certs -text -noout > /tmp/cert.txt
```

Then check each of these in `/tmp/cert.txt`:

#### Issuer

Must be one of:

- DigiCert Verified Mark Issuing CA (VMC)
- Entrust Verified Mark CA (VMC)
- DigiCert Common Mark Issuing CA (CMC)
- SSL.com BIMI Authority (VMC/CMC)
- GlobalSign GCC Trusted Root CA for BIMI

#### Validity

```bash
openssl x509 -in /tmp/cert.pem -noout -dates
```

`notBefore` ≤ today ≤ `notAfter`. Renewal cycle is 1 year.

#### Extended Key Usage (EKU)

The certificate must carry the BIMI EKU OID:

```
1.3.6.1.5.5.7.3.31
```

Look in `cert.txt` for `X509v3 Extended Key Usage:` — it should contain `BIMI` or the raw OID.

#### LogotypeExtension

The certificate must carry the logo embedded as an X.509 `LogotypeExtension` (OID `1.3.6.1.5.5.7.1.12`). Look for `id-pe-logotype` or `1.3.6.1.5.5.7.1.12` in `cert.txt`.

#### Logo hash binding

The `LogotypeExtension` includes a **SHA-256 hash of the SVG**. The SVG served at `l=` must hash to that exact value, byte-for-byte. Any difference — extra whitespace, BOM, trailing newline — invalidates BIMI.

```bash
# Hash the served SVG
shasum -a 256 /tmp/logo.svg

# Extract the hash from the cert (requires asn1parse + manual inspection,
# or use a tool like `bimi-checker`)
```

Quickest non-manual check: [bimichecker.com](https://bimichecker.com/) or [redsift.com/bimi-inspector](https://redsift.com/bimi-inspector).

#### Chain

The PEM must include the full chain to a root trusted by the receiver. DigiCert and Entrust roots are in the major receivers' trust stores by default — but a missing intermediate kills validation. Always include intermediates in the PEM.

### 4. The logo URL and PEM URL must be HTTPS and reachable

- HTTP only: fail
- TLS errors (self-signed, expired): fail
- 4xx/5xx response: fail
- Redirect chain: most receivers follow up to one redirect, but don't rely on it
- CORS: not required, but the URL must be plain HTTP GET

## Inbox support matrix (2026)

| Inbox | BIMI w/ VMC | BIMI w/ CMC | BIMI without cert |
|---|---|---|---|
| Gmail | ✓ | ✓ | ✗ |
| Yahoo | ✓ | ✓ | ✓ (limited) |
| Apple Mail (iOS 16+, macOS 13+) | ✓ | ✓ | ✗ |
| Fastmail | ✓ | ✓ | ✗ |
| La Poste (FR) | ✓ | ✓ | ✗ |
| Microsoft 365 / Outlook.com | ✗ | ✗ | ✗ (still no support as of 2026) |
| ProtonMail | ✗ | ✗ | ✗ |

Microsoft's lack of BIMI support is a recurring complaint and the single biggest reason teams skip BIMI for B2B.

## Verdict logic for the audit

| Finding | Verdict |
|---|---|
| DMARC not enforced (`p=none` or `pct<100`) | **n/a** — fix DMARC first |
| No BIMI TXT | **n/a** if DMARC weak, otherwise **FAIL** |
| BIMI TXT exists but `l=` URL 404s | **FAIL** |
| SVG isn't Tiny PS / has scripts / >32KB | **FAIL** |
| BIMI TXT has `l=` but no `a=` | **WARN** (Yahoo only) |
| VMC/CMC expired | **FAIL** |
| Certificate is wrong type (e.g. an HTTPS server cert) | **FAIL** |
| Logo hash in cert ≠ hash of served SVG | **FAIL** |
| Issuer not on allowed list | **FAIL** |
| BIMI EKU OID missing | **FAIL** |
| Everything passes | **OK** |

## Common gotchas

- **Editing the SVG after the cert was issued.** The cert binds to a specific hash. Re-exporting the SVG (different optimizer, different XML formatting) changes the hash and breaks BIMI. Re-issue the cert.
- **CDN modifying the SVG.** Cloudflare / Vercel image optimization can mutate SVGs. Serve from a path that bypasses optimization, or set `Content-Type: image/svg+xml` + `Cache-Control: immutable`.
- **Embedded raster.** "It's still an SVG file" — yes, but raster-inside-SVG is rejected by every validator.
- **Animation snuck in via filter.** Some `<filter>` effects use `<animate>` children. Strip the whole filter.
- **Forgotten subdomain.** BIMI on `example.com` does not apply to mail from `news.example.com`. Each sending domain needs its own BIMI record (or alignment to apex via DMARC organizational domain, which works for relaxed alignment).
- **VMC requires the exact trademarked logo.** A "modernized" version that differs from the registered mark won't pass DigiCert review.
