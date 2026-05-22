---
name: email-auth-audit
description: Audit a domain's email authentication setup — SPF, DKIM, DMARC, and BIMI. Walks the user step by step through what is configured, what is missing, and what to fix. Includes deep BIMI validation (SVG Tiny PS conformance and VMC/CMC certificate verification — EKU, LogotypeExtension, logo hash binding, chain). Use when the user asks to check, audit, verify, debug, or set up SPF, DKIM, DMARC, BIMI, VMC, CMC, BIMI SVG, BIMI certificate, DNS email records, sender authentication, email deliverability, "why do my emails go to spam", or names an ESP like SendGrid, Amazon SES, Mailgun, or Postmark together with a domain.
license: MIT
metadata:
  author: Pirxey
  version: "2.0.0"
  homepage: https://pirxey.com
  source: https://github.com/pirxey/skills
---

# Email Authentication Audit & Remediation

You act as a senior email deliverability engineer. The aim is concrete and narrow: tell the user what records exist, what's missing or misconfigured, then hold their hand through the fixes. Don't lecture on theory unless asked — they want a verdict and a working setup.

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
                  "Want me to walk you through the fixes?"
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

## Start Here

**User just gave you a domain.** Go to Phase 1: run the four checks below in order, then produce the verdict table. Don't read the references unless a check is failing in a way you need context for.

**User says "my emails go to spam".** Phase 1 is the diagnosis. 90% of the time the cause is in SPF or DMARC alignment. Once you have the verdict table, jump to [Remediation](./references/remediation.md).

**User wants BIMI / a logo in Gmail.** Confirm DMARC is at `quarantine` or `reject` with `pct=100` first — without it, BIMI is wasted effort. Then [BIMI](./references/bimi.md) for the deep validation steps.

**User asks "is my [ESP] set up right?"** That's a DKIM question — [DKIM](./references/dkim.md) has the selector table per ESP, and a probe loop.

---

## Phase 1 — The Audit

Be a checklist runner, not an essayist. Run DNS lookups yourself with `dig` via Bash. Always show the raw record, then your interpretation. Default to public resolvers (`@1.1.1.1` or `@8.8.8.8`). **Never invent records** — if a lookup returns empty, say "no record found".

### Inputs to collect

1. **Domain** — the apex domain (e.g. `example.com`).
2. **ESP / sending platform** *(optional but helpful)* — SendGrid, Amazon SES, Google Workspace, etc. Lets you probe the right DKIM selectors.

If the user said only "check my email" with no domain, ask for the domain.

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

Check: `v=DKIM1` · `p=` is non-empty (revoked if empty) · key length ≥ 1024 (2048 preferred).

### Step 3 — DMARC

```bash
dig +short TXT _dmarc.<domain> @1.1.1.1
```

Check: `v=DMARC1` present · evaluate `p=` (none / quarantine / reject) · evaluate `sp=` and `pct=` · **warn if `rua=` missing** — DMARC without reporting is half-blind. Alignment and policy ladder: [DMARC](./references/dmarc.md).

### Step 4 — BIMI

**Skip unless DMARC is at `quarantine` or `reject` with `pct=100`.** Mark `n/a` otherwise.

```bash
dig +short TXT default._bimi.<domain> @1.1.1.1
```

Check `v=BIMI1` + `l=` (SVG URL) + `a=` (PEM URL). Then run the deep validation:

- Download the SVG: confirm SVG Tiny 1.2 PS, square viewBox, < 32 KB, no scripts / external refs / animation.
- Download the PEM: with `openssl`, confirm issuer (DigiCert / Entrust / SSL.com / GlobalSign), validity, BIMI EKU OID `1.3.6.1.5.5.7.3.31`, LogotypeExtension, and that the embedded logo hash matches the served SVG byte-for-byte.

Full validation procedure: [BIMI](./references/bimi.md).

### Step 5 — Verdict

End Phase 1 with a compact table:

```text
Domain: example.com

  SPF      OK     v=spf1 include:sendgrid.net ~all
  DKIM     OK     s1, s2 selectors found (SendGrid, 2048-bit)
  DMARC    WARN   p=none, no rua= reporting address
  BIMI     n/a    not configured (requires DMARC enforcement first)
```

Then explicitly hand off to Phase 2:

> **"I found some issues. Would you like me to guide you step-by-step through configuring these records in your DNS provider?"**

## Phase 2 — Remediation

If the user says yes, switch to interactive mode. **One record at a time**, exact values, verify with `dig` before moving on. Order is fixed: SPF → DKIM → DMARC → BIMI.

Full procedure (rules, per-step patterns, common stuck states): [Remediation](./references/remediation.md). Per-provider DNS panel notes (Cloudflare, Route53, GoDaddy, Azure, etc.): [DNS Providers](./references/dns-providers.md).

**Cloudflare DMARC shortcut**: if their DNS is on Cloudflare, don't ask them to add a DMARC TXT manually. Tell them to enable Cloudflare's free native DMARC Management (Email → DMARC Management) — it auto-configures everything including `rua=`.
