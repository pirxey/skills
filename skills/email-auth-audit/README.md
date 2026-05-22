# email-auth-audit

A universal agent skill that audits a domain's email authentication setup (SPF, DKIM, DMARC, BIMI), produces a verdict, and walks the user through fixing what's broken — one DNS record at a time, verified with `dig`.

Part of the **[pirxey/skills](https://github.com/pirxey/skills)** collection.

## What This Skill Covers

**Phase 1 — Audit (read-only)**

- **SPF** — record presence, qualifier strictness, 10-lookup limit, ESP include detection
- **DKIM** — selector probing tuned per ESP (SendGrid, SES, Mailgun, Google Workspace, M365, Postmark, Mailchimp, HubSpot, Brevo, Klaviyo, and more), key-length and revocation checks
- **DMARC** — policy ladder evaluation (`none` → `quarantine` → `reject`), `pct` rollout, alignment, missing-`rua` warnings
- **BIMI deep dive** — SVG Tiny PS conformance (viewBox, scripts, animation, external refs), VMC/CMC certificate validation (issuer, validity, BIMI EKU OID `1.3.6.1.5.5.7.3.31`, LogotypeExtension, **byte-for-byte logo-hash binding**, chain)

**Phase 2 — Interactive remediation**

- One DNS record at a time, exact values for the user's panel
- Provider-specific guidance: **Cloudflare** (uses native DMARC Management tool), Route53, GoDaddy, Azure, Squarespace Domains, Namecheap, OVH, DNSimple, Hover
- Verification with `dig` against `@1.1.1.1`/`@8.8.8.8` and authoritative NS
- Correct ordering: SPF → DKIM → DMARC → BIMI (never skip ahead)

## Structure

```
email-auth-audit/
├── SKILL.md                          # Start here — router with Quick Reference table
└── references/
    ├── spf.md                        # SPF anatomy, 10-lookup limit, ESP includes
    ├── dkim.md                       # DKIM, ESP selector table, probing, rotation
    ├── dmarc.md                      # Policy ladder, alignment, reporting
    ├── bimi.md                       # SVG Tiny PS rules, VMC/CMC validation, inbox matrix
    ├── remediation.md                # Phase 2 interactive flow, ordering, verification
    └── dns-providers.md              # Per-provider quirks (Cloudflare, Route53, etc.)
```

The skill uses [progressive disclosure](https://agentskills.io/specification#progressive-disclosure): your agent loads only `SKILL.md` at discovery, then pulls in a reference file on demand when a check or remediation step needs it.

## Quick Start

Once installed, ask your agent:

```text
Audit email authentication for example.com
```

The skill auto-activates on phrases like *"check SPF/DKIM/DMARC"*, *"why do my emails go to spam"*, *"verify BIMI"*, or naming an ESP (SendGrid, SES, Mailgun…) together with a domain.

## Installation

### As part of the full pirxey/skills repo

```bash
npx skills add pirxey/skills -g
```

### Just this skill

```bash
npx skills add pirxey/skills --skill email-auth-audit -g
```

### Manual install per agent

If you'd rather clone the repo yourself, drop the skill directory into your agent's global skills location:

| Agent | Path |
|---|---|
| Claude Code | `~/.claude/skills/email-auth-audit` |
| Cursor | `~/.cursor/skills/email-auth-audit` |
| Gemini CLI | `~/.gemini/skills/email-auth-audit` |
| GitHub Copilot | `~/.copilot/skills/email-auth-audit` |
| OpenCode | `~/.config/opencode/skills/email-auth-audit` |
| Codex | `~/.codex/skills/email-auth-audit` |

For a project-scoped install, most agents read from `./.agents/skills/` (or `./.claude/skills/` for Claude Code) — drop the folder there and commit alongside your repo.

### Web-based AI (ChatGPT, Claude.ai, Gemini Web)

No CLI? Use it as a system prompt:

1. Open [SKILL.md](./SKILL.md) and copy the full content.
2. Paste it into your chat with: *"Act as an Email Audit Expert based on these instructions. Audit the domain: yourdomain.com"*
3. For BIMI / certificate checks, also paste the relevant `references/*.md` file.

### Custom GPT (OpenAI)

Create a permanent "Email Auditor":

1. Create a **New GPT**.
2. Paste the content of [SKILL.md](./SKILL.md) into the **Instructions** field.
3. Upload the `references/*.md` files to the GPT's knowledge base.
4. Enable **Web Browsing** so it can fetch records without a terminal.

## Requirements (for CLI usage)

Standard tools found on most systems:

- `dig` — DNS lookups
- `openssl` — certificate validation
- `curl` — fetch SVG / PEM assets
- `shasum` / `sha256sum` — logo-hash binding verification
- `xmllint` *(optional)* — SVG structural validation

## Example Output

```text
Domain: example.com

  SPF      OK     v=spf1 include:sendgrid.net ~all
  DKIM     OK     s1, s2 selectors found (SendGrid, 2048-bit)
  DMARC    WARN   p=none, no rua= reporting address
  BIMI     FAIL   SVG OK, but VMC certificate expired (notAfter: 2025-11-12)

Recommended next actions:
  1. Add rua=mailto:dmarc@example.com to _dmarc record (or enable Cloudflare DMARC Management).
  2. Renew VMC certificate with DigiCert / Entrust for BIMI logo rendering.

Want me to walk you through these step-by-step?
```

## About the maintainer

This skill is built and maintained by **[Pirxey](https://pirxey.com)** — an AI-native software house (120+ engineers, banking / fintech / medtech / e-commerce / SaaS). We run 100% AI-assisted internally, and we open-source the skills we build for ourselves.

**AI is how we work, not what we sell.**

→ Need engineering capacity? **[pirxey.com](https://pirxey.com)**

## License

MIT — see [LICENSE](../../LICENSE).

---

*Built and maintained by [Pirxey](https://pirxey.com).*
