# DMARC — Domain-based Message Authentication, Reporting & Conformance

DMARC ties SPF and DKIM together with two things: an **alignment** check (the authenticated domain must match the visible `From:` domain) and a **policy** (what receivers do when alignment fails). It also defines the **reporting** channel that tells you who's spoofing you.

A domain has at most one DMARC record, published at `_dmarc.<domain>`.

## Lookup

```bash
dig +short TXT _dmarc.example.com @1.1.1.1
```

## Record anatomy

```
v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com; pct=100; sp=reject; adkim=s; aspf=r
└──────┘ └───────────┘ └────────── reporting ──────┘ └─────┘ └────────┘ └────── alignment ──┘
version    policy                                  rollout  subdomain policy
```

| Tag | Meaning |
|---|---|
| `v=DMARC1` | Required. Must be first. |
| `p=` | Policy for the apex domain: `none`, `quarantine`, or `reject`. |
| `sp=` | Policy for **subdomains**. If absent, inherits `p`. |
| `pct=` | Percentage of failing mail to which `p` is applied. 0–100. Defaults to 100. |
| `rua=` | **Aggregate** reports — daily XML summaries. `mailto:` or `https:`. |
| `ruf=` | **Forensic** reports — per-failure samples. Very rare today (privacy). |
| `adkim=` | DKIM alignment: `r` (relaxed, organizational-domain match) or `s` (strict, exact). |
| `aspf=` | SPF alignment: `r` (default) or `s` (strict). |
| `fo=` | Forensic options: `0`, `1`, `d`, `s`. Mostly historical. |
| `rf=afrf` | Forensic report format. Default. |
| `ri=` | Reporting interval in seconds. Default 86400 (daily). Don't change it. |

## The policy ladder

DMARC is rolled out, not switched on. Receivers expect you to ramp up:

| Stage | Record | Rollout time |
|---|---|---|
| **1. Monitor** | `p=none; rua=mailto:reports@example.com` | 2–4 weeks. Read aggregate reports. Identify and fix all legitimate senders failing alignment. |
| **2. Quarantine 10%** | `p=quarantine; pct=10; rua=...` | 1 week. Watch for legitimate mail landing in spam. |
| **3. Quarantine 100%** | `p=quarantine; pct=100; rua=...` | 1–2 weeks. |
| **4. Reject 10%** | `p=reject; pct=10; rua=...` | Optional intermediate. Some teams skip this. |
| **5. Reject 100%** | `p=reject; rua=...` | Terminal. Spoofers blocked at receiver. |

Reach `p=reject` and you've earned BIMI eligibility. Stopping at `p=none` permanently gives you no protection — only reporting.

## Alignment, the part that actually matters

DMARC passes only if SPF **or** DKIM passes **and** the passing one is **aligned** with the `From:` header. "Aligned" means the authentication domain shares the organizational domain with `From:`.

| `From:` | DKIM `d=` | Mode | Aligned? |
|---|---|---|---|
| `news@example.com` | `example.com` | relaxed or strict | ✓ |
| `news@example.com` | `mail.example.com` | relaxed | ✓ |
| `news@example.com` | `mail.example.com` | strict | ✗ |
| `news@example.com` | `sendgrid.net` | any | ✗ (DKIM passes, DMARC fails) |

The `sendgrid.net` row is the most common cause of DMARC failures: the ESP signs with its own domain (`d=sendgrid.net`) instead of your domain. The fix is to set up **DKIM on a CNAME** so the ESP signs with `d=example.com` (or `d=em.example.com` if they CNAME a subdomain). This is also why setting up DKIM with your ESP is non-optional for DMARC.

SPF alignment works the same way, comparing the envelope-from (Return-Path) domain to the `From:` domain. Most ESPs use their own envelope-from, so **SPF alignment usually fails** through an ESP — relying on DKIM alignment is the norm.

## Reporting

`rua=` is where the real value of DMARC lives. You'll get one XML report per day per receiver (Google, Yahoo, Microsoft, etc.) listing every IP that sent mail claiming to be your domain and whether it passed/failed alignment.

Don't try to read raw XML. Use one of:

- **Cloudflare DMARC Management** — free, native if your DNS is on Cloudflare. Auto-creates the record.
- **Postmark DMARC Monitoring** — free up to a point, clean UI.
- **dmarcian** — comprehensive, paid above small volume.
- **EasyDMARC** — paid, includes guided remediation.
- **Valimail** — enterprise.
- **Roll your own:** parse with [parsedmarc](https://github.com/domainaware/parsedmarc).

`ruf=` (forensic / per-failure samples) is mostly deprecated for privacy reasons — Gmail and Microsoft stopped sending them. Don't bother setting it.

## Subdomain policy (`sp=`)

If you don't set `sp=`, subdomains inherit `p=`. Set `sp=reject` explicitly if you don't intend to send from subdomains — it shuts down the most common spoofing vector (`account.example.com`, `support.example.com`).

## Verdict logic for the audit

| Finding | Verdict | Action |
|---|---|---|
| No `_dmarc` record | **FAIL** | Add one starting at `p=none; rua=...`. |
| `p=none` with no `rua=` | **FAIL** | Useless without reporting. Add `rua=`. |
| `p=none` with `rua=` | **WARN** | Reporting only — move to `p=quarantine` after analyzing reports. |
| `p=quarantine`, `pct<100` | **WARN** | Mid-rollout. Continue to `pct=100`. |
| `p=quarantine`, `pct=100` | **OK** | Consider reject. |
| `p=reject` | **OK** (best) | BIMI is unlocked. |
| Multiple DMARC records | **FAIL** | Receivers ignore all of them. Keep one. |
| `sp=` absent and apex is `p=reject` | **WARN** | Set `sp=reject` explicitly. |
| `rua=` points to a domain not under your control | **WARN** (DMARC reporting authorization) | The receiving domain must publish `<your-domain>._report._dmarc.<their-domain>` — most aggregators do. |

## Common gotchas

- **`p=none` forever.** Reporting-only mode protects nothing. Plan a ramp.
- **`pct=` only applies to quarantine and reject.** It does nothing in `p=none`.
- **Alignment requires DKIM on your domain.** If your ESP signs with `d=esp.com`, DMARC fails even if DKIM and SPF both pass.
- **`mailto:` in `rua=` must accept mail.** A typo or full mailbox = silently no reports.
- **External destination authorization.** If `rua=mailto:x@otherdomain.com`, `otherdomain.com` must publish a TXT at `example.com._report._dmarc.otherdomain.com` saying "v=DMARC1" to opt in. All aggregators (Cloudflare, Postmark, dmarcian, etc.) handle this automatically.
- **Mailing lists break DMARC.** Lists rewrite `From:`, breaking alignment. Solutions: ARC, From-rewriting at the list (`example@list.example.com via list`), or just accept it. Discord, Mailman 3, and Google Groups support ARC.
- **`ruf=` is dead.** Don't set it; you'll get nothing.
