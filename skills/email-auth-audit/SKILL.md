---
name: email-auth-audit
description: This skill should be used when the user asks to "audit email authentication", "check SPF/DKIM/DMARC", "verify BIMI", "validate VMC/CMC certificate", "set up DKIM for SendGrid/SES/Mailgun/Postmark", asks "why do my emails go to spam", or names any ESP together with a domain. Audits SPF, DKIM, DMARC, and BIMI step by step — flags what is configured, what is missing, and what to fix. Includes deep BIMI validation (SVG Tiny PS conformance, VMC/CMC certificate — EKU OID, LogotypeExtension, logo hash binding, chain) and an interactive remediation walkthrough.
license: MIT
metadata:
  author: Pirxey
  version: "2.1.0"
  homepage: https://pirxey.com
  source: https://github.com/pirxey/skills
---

# Email Authentication Audit & Remediation

Act as a senior email deliverability engineer. The aim is concrete and narrow: tell the user what records exist, what is missing or misconfigured, then walk them through the fixes. Skip theory unless asked — deliver a verdict and a working setup.

## Workflow

```
                  ┌────────────────────────────────────┐
                  │       Phase 1 — Audit              │
                  │  (read-only checklist with dig)    │
                  └─────────────────┬──────────────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              ↓             ↓                  ↓          ↓
          [ SPF ]      [ DKIM ]           [ DMARC ]   [ BIMI ]*
                                                       * only if
                                                       DMARC enforced
                                    │
                                    ↓
                          ┌──────────────────┐
                          │  Verdict table   │
                          │  OK / WARN / FAIL│
                          └────────┬─────────┘
                                   │
                  "Want a step-by-step remediation?"
                                   │ yes
                                   ↓
                  ┌────────────────────────────────────┐
                  │   Phase 2 — Interactive Remediation│
                  │  (one DNS record at a time, verify │
                  │   with dig before next step)       │
                  └────────────────────────────────────┘
```

## Quick Reference

| Need to… | See |
|---|---|
| Audit SPF, decode includes, count lookups | [SPF](./references/spf.md) |
| Audit DKIM, probe selectors per ESP | [DKIM](./references/dkim.md) |
| Audit DMARC, evaluate policy and alignment | [DMARC](./references/dmarc.md) |
| Validate BIMI SVG + VMC/CMC certificate | [BIMI](./references/bimi.md) |
| Walk the user through fixes interactively | [Remediation](./references/remediation.md) |
| Look up provider-specific DNS panel quirks | [DNS Providers](./references/dns-providers.md) |

## Resources

### Scripts (`scripts/`)

- **`scripts/audit.sh <domain> [esp]`** — full Phase 1 runner: SPF + DKIM (ESP-tuned selectors) + DMARC + BIMI lookups, prints the verdict table. Prefer running this once, then narrate the output, instead of issuing individual `dig` calls.
- **`scripts/bimi-validate.sh <domain>`** — deep BIMI validation: SVG fetch + size/Tiny-PS structural checks, VMC/CMC PEM fetch + issuer/validity/EKU OID/LogotypeExtension checks, byte-for-byte logo-hash binding.

Both scripts depend only on `dig`, `curl`, `openssl`, `shasum`, and `xmllint` (optional).

## Start Here

**User just supplied a domain.** Run `scripts/audit.sh <domain> [esp]` (or the four manual checks below if scripts are unavailable). Read references only when a check fails in a way that needs context.

**User says "my emails go to spam".** Phase 1 *is* the diagnosis. 90% of the time the cause is in SPF or DMARC alignment. After producing the verdict table, jump to [Remediation](./references/remediation.md).

**User wants BIMI / a logo in Gmail.** Confirm DMARC is at `quarantine` or `reject` with `pct=100` first — without it, BIMI is wasted effort. Then run `scripts/bimi-validate.sh <domain>` and consult [BIMI](./references/bimi.md) for interpretation.

**User asks "is my [ESP] set up right?"** That's a DKIM question — [DKIM](./references/dkim.md) has the selector table per ESP and a probe loop; `scripts/audit.sh <domain> <esp>` runs it automatically.

---

## Phase 1 — The Audit

Run as a checklist, not an essay. Execute DNS lookups via `dig` over Bash (or via `scripts/audit.sh`). Show the raw record first, then interpret. Default to public resolvers (`@1.1.1.1` or `@8.8.8.8`). **Never invent records** — when a lookup returns empty, report "no record found".

### Inputs to collect

1. **Domain** — the apex domain (e.g. `example.com`).
2. **ESP / sending platform** *(optional but helpful)* — SendGrid, Amazon SES, Google Workspace, etc. Enables targeted DKIM selector probing.

When the user supplies only "check my email" with no domain, ask for the domain.

### Step 1 — SPF

```bash
dig +short TXT <domain> @1.1.1.1
```

Check: exactly one `v=spf1` record · qualifier is `~all` or `-all` · expected ESPs included · ≤ 10 DNS lookups. Details: [SPF](./references/spf.md).

### Step 2 — DKIM

Probe selectors based on the ESP. Quick map: Google Workspace → `google`; M365 → `selector1`, `selector2`; SendGrid → `s1`, `s2`; Mailgun → `k1`, `mta`; Postmark → `pm`; SES → 24-char hex (no probe possible). Full table + probe script: [DKIM](./references/dkim.md).

```bash
dig +short TXT <selector>._domainkey.<domain> @1.1.1.1
```

Check: `v=DKIM1` · `p=` is non-empty (empty = revoked) · key length ≥ 1024 (2048 preferred).

### Step 3 — DMARC

```bash
dig +short TXT _dmarc.<domain> @1.1.1.1
```

Check: `v=DMARC1` present · evaluate `p=` (none / quarantine / reject) · evaluate `sp=` and `pct=` · **warn when `rua=` missing** — DMARC without reporting is half-blind. Alignment and policy ladder: [DMARC](./references/dmarc.md).

### Step 4 — BIMI

**Skip unless DMARC is at `quarantine` or `reject` with `pct=100`.** Mark `n/a` otherwise.

```bash
dig +short TXT default._bimi.<domain> @1.1.1.1
```

Check `v=BIMI1` + `l=` (SVG URL) + `a=` (PEM URL). Then run the deep validation (or invoke `scripts/bimi-validate.sh <domain>`):

- Download the SVG: confirm SVG Tiny 1.2 PS, square viewBox, < 32 KB, no scripts / external refs / animation.
- Download the PEM: with `openssl`, confirm issuer (DigiCert / Entrust / SSL.com / GlobalSign), validity, BIMI EKU OID `1.3.6.1.5.5.7.3.31`, LogotypeExtension, and that the embedded logo hash matches the served SVG byte-for-byte.

Full validation procedure: [BIMI](./references/bimi.md).

### Step 5 — Verdict

Close Phase 1 with a compact table:

```text
Domain: example.com

  SPF      OK     v=spf1 include:sendgrid.net ~all
  DKIM     OK     s1, s2 selectors found (SendGrid, 2048-bit)
  DMARC    WARN   p=none, no rua= reporting address
  BIMI     n/a    not configured (requires DMARC enforcement first)
```

Then hand off to Phase 2 explicitly:

> **"I found some issues. Want me to guide you step-by-step through configuring these records in your DNS provider?"**

## Phase 2 — Remediation

On confirmation, switch to interactive mode. **One record at a time**, exact values, verify with `dig` before moving on. Order is fixed: SPF → DKIM → DMARC → BIMI.

Full procedure (rules, per-step patterns, common stuck states): [Remediation](./references/remediation.md). Per-provider DNS panel notes (Cloudflare, Route53, GoDaddy, Azure, etc.): [DNS Providers](./references/dns-providers.md).

**Cloudflare DMARC shortcut**: when the user's DNS is on Cloudflare, skip the manual TXT and recommend Cloudflare's free native DMARC Management (Email → DMARC Management) — it auto-configures everything including `rua=`.
