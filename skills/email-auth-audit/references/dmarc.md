# DMARC — Domain-based Message Authentication, Reporting & Conformance

DMARC ties SPF and DKIM together with two things: an **alignment** check (the authenticated domain must match the visible `From:` domain) and a **policy** (what receivers do when alignment fails). It also defines the **reporting** channel that surfaces spoofing attempts back to the domain owner.

DMARC depends on at least one of [SPF](./spf.md) or [DKIM](./dkim.md) passing *and* aligning — without working DKIM alignment, ESP traffic typically fails DMARC even when SPF and DKIM both pass technically.

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

DMARC is rolled out, not switched on. Receivers expect a gradual ramp:

| Stage | Record | Rollout time |
|---|---|---|
| **1. Monitor** | `p=none; rua=mailto:reports@example.com` | 2–4 weeks. Read aggregate reports. Identify and fix all legitimate senders failing alignment. |
| **2. Quarantine 10%** | `p=quarantine; pct=10; rua=...` | 1 week. Watch for legitimate mail landing in spam. |
| **3. Quarantine 100%** | `p=quarantine; pct=100; rua=...` | 1–2 weeks. |
| **4. Reject 10%** | `p=reject; pct=10; rua=...` | Optional intermediate. Some teams skip this. |
| **5. Reject 100%** | `p=reject; rua=...` | Terminal. Spoofers blocked at receiver. |

Reaching `p=reject` unlocks BIMI eligibility (see [BIMI](./bimi.md)). Stopping at `p=none` permanently provides no protection — only reporting.

## Alignment, the part that actually matters

DMARC passes only if SPF **or** DKIM passes **and** the passing one is **aligned** with the `From:` header. "Aligned" means the authentication domain shares the organizational domain with `From:`.

| `From:` | DKIM `d=` | Mode | Aligned? |
|---|---|---|---|
| `news@example.com` | `example.com` | relaxed or strict | ✓ |
| `news@example.com` | `mail.example.com` | relaxed | ✓ |
| `news@example.com` | `mail.example.com` | strict | ✗ |
| `news@example.com` | `sendgrid.net` | any | ✗ (DKIM passes, DMARC fails) |

The `sendgrid.net` row is the most common cause of DMARC failures: the ESP signs with its own domain (`d=sendgrid.net`) instead of the sender's domain. The fix is to set up **DKIM on a CNAME** so the ESP signs with `d=example.com` (or `d=em.example.com` when the ESP CNAMEs a subdomain). This is also why setting up DKIM with the ESP is non-optional for DMARC. See [DKIM selector probing](./dkim.md#selector-probing-per-esp) for the per-ESP CNAME path.

SPF alignment works the same way, comparing the envelope-from (Return-Path) domain to the `From:` domain. Most ESPs use their own envelope-from, so **SPF alignment usually fails** through an ESP — relying on DKIM alignment is the norm.

## Reporting

`rua=` is where the real value of DMARC lives. Each receiver (Google, Yahoo, Microsoft, etc.) emits one XML report per day listing every IP that sent mail claiming to be the audited domain and whether it passed/failed alignment.

Skip reading raw XML — recommend an aggregator:

- **Cloudflare DMARC Management** — free, native when DNS is on Cloudflare. Auto-creates the record.
- **Postmark DMARC Monitoring** — free up to a point, clean UI.
- **dmarcian** — comprehensive, paid above small volume.
- **EasyDMARC** — paid, includes guided remediation.
- **Valimail** — enterprise.
- **Self-hosted:** parse with [parsedmarc](https://github.com/domainaware/parsedmarc).

`ruf=` (forensic / per-failure samples) is mostly deprecated for privacy reasons — Gmail and Microsoft stopped sending them. Don't bother setting it.

## Subdomain policy (`sp=`)

When `sp=` is absent, subdomains inherit `p=`. Set `sp=reject` explicitly when the domain does not send from subdomains — it shuts down the most common spoofing vector (`account.example.com`, `support.example.com`).

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
| `rua=` points to an external domain | **WARN** (DMARC reporting authorization) | The receiving domain must publish `<sender-domain>._report._dmarc.<external-domain>` — most aggregators handle this automatically. |

## Common gotchas

- **`p=none` forever.** Reporting-only mode protects nothing. Plan a ramp.
- **`pct=` only applies to quarantine and reject.** It does nothing in `p=none`.
- **Alignment requires DKIM on the sender's domain.** When the ESP signs with `d=esp.com`, DMARC fails even though DKIM and SPF both pass.
- **`mailto:` in `rua=` must accept mail.** A typo or full mailbox = silently no reports.
- **External destination authorization.** If `rua=mailto:x@otherdomain.com`, `otherdomain.com` must publish a TXT at `example.com._report._dmarc.otherdomain.com` saying "v=DMARC1" to opt in. All aggregators (Cloudflare, Postmark, dmarcian, etc.) handle this automatically.
- **Mailing lists break DMARC.** Lists rewrite `From:`, breaking alignment. Solutions: ARC, From-rewriting at the list (`example@list.example.com via list`), or just accept it. Discord, Mailman 3, and Google Groups support ARC.
- **`ruf=` is dead.** Skip it — Gmail and Microsoft no longer emit forensic reports.
