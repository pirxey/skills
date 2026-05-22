```
  ╔══════════════════════════════════════════════════╗
  ║          ____  ___ ____  __  ______  __          ║
  ║         / __ \/ _/ __ \ \ \/ / __/ \/ /          ║
  ║        / /_/ // // /_/ /  \  / _// /  /          ║
  ║       / .___/___/ _, _/   /_/___/_/__/           ║
  ║      /_/        /_/|_|                           ║
  ║                                                  ║
  ║                  Agent Skills                    ║
  ║         AI is how we work, not what we sell      ║
  ╚══════════════════════════════════════════════════╝
```

# Pirxey Skills

[![skills.sh](https://skills.sh/b/pirxey/skills)](https://skills.sh/pirxey/skills)

Open-source [Agent Skills](https://agentskills.io) from **[Pirxey](https://pirxey.com)** — procedures and playbooks we use in our own AI-assisted engineering work, packaged so any agent can run them.

Works with **Claude Code**, **Cursor**, **GitHub Copilot**, **Gemini CLI**, **OpenCode**, **Codex**, and 50+ other agents.

## Available Skills

### [email-auth-audit](./skills/email-auth-audit/)

Audits a domain's email authentication setup (SPF, DKIM, DMARC, BIMI), produces a verdict, and walks the user through fixing what's broken — one DNS record at a time, verified with `dig`.

**Use when:**

- "Audit email authentication for example.com"
- "Why do my emails go to spam?"
- "Check SPF / DKIM / DMARC for my domain"
- "Verify my BIMI logo and VMC certificate"
- "Set up DKIM for SendGrid / SES / Mailgun / Postmark…"

Includes deep BIMI validation: SVG Tiny PS conformance, VMC/CMC certificate verification (EKU, LogotypeExtension, byte-for-byte logo-hash binding, chain), and per-provider DNS panel walk-throughs (Cloudflare, Route53, GoDaddy, Azure, and more).

---

*More skills coming. Want one built? [Drop us a line.](https://pirxey.com)*

## Installation

### Install everything

```bash
# All skills, global
npx skills add pirxey/skills -g

# Or scoped to current project
npx skills add pirxey/skills
```

### Install a single skill

```bash
npx skills add pirxey/skills --skill email-auth-audit -g
```

### Target a specific agent

```bash
npx skills add pirxey/skills -a claude-code
npx skills add pirxey/skills -a cursor
npx skills add pirxey/skills -a gemini-cli
npx skills add pirxey/skills -a github-copilot
```

### List what's in the repo

```bash
npx skills add pirxey/skills --list
```

See all options: `npx skills add --help`.

## Structure

```
pirxey/skills/
├── README.md                                # This file
├── AGENTS.md                                # Cross-agent contributor notes
├── skills.sh.json                           # Groupings for skills.sh listing
└── skills/
    └── email-auth-audit/
        ├── SKILL.md                         # Skill entry point (router)
        ├── README.md                        # Skill-level docs
        └── references/                      # Progressive-disclosure deep dives
            ├── spf.md
            ├── dkim.md
            ├── dmarc.md
            ├── bimi.md
            ├── remediation.md
            └── dns-providers.md
```

Each skill follows [progressive disclosure](https://agentskills.io/specification#progressive-disclosure): your agent loads only the skill's `SKILL.md` at discovery, then pulls in a reference file on demand when a check or remediation step needs it.

## About Pirxey

**[Pirxey](https://pirxey.com)** is an AI-native software house — 120+ engineers shipping web, mobile, backend, cloud, and blockchain projects for banking, fintech, medtech, e-commerce, retail, government, EduTech, SaaS, and startups.

Our team runs 100% AI-assisted: Claude Code, Codex, Copilot, and friends are part of the daily workflow. We build the skills in this repo because we need them ourselves on client work — open-sourcing them is the cheapest way to make them better.

**AI is how we work, not what we sell.**

→ Need engineering capacity? **[pirxey.com](https://pirxey.com)**

## License

MIT — see [LICENSE](./LICENSE).

---

*Built and maintained by [Pirxey](https://pirxey.com).*
