# AGENTS.md

Guidance for AI coding agents (Claude Code, Cursor, Copilot, etc.) working in this repository.

## Repository Overview

This repo hosts open-source [Agent Skills](https://agentskills.io) maintained by [Pirxey](https://pirxey.com). Each skill is a self-contained directory under `skills/` with a `SKILL.md` entry point and optional `references/`, `scripts/`, `lib/`, and `assets/` subdirectories.

## Adding a New Skill

### Directory Structure

```
skills/
  {skill-name}/                  # kebab-case directory name
    SKILL.md                     # Required — frontmatter + instructions
    README.md                    # Recommended — public-facing skill docs
    references/                  # Optional — progressive-disclosure deep dives
      {topic}.md
    scripts/                     # Optional — executable helpers
      {name}.sh
      {name}.mjs
    lib/                         # Optional — shared code for scripts
    assets/                      # Optional — templates, fixtures, sample data
```

### Naming Conventions

- **Skill directory**: `kebab-case` (e.g. `email-auth-audit`, `dmarc-monitoring`)
- **SKILL.md**: always uppercase, always exactly this filename
- **Scripts**: `kebab-case.{sh,mjs,py}`
- **References**: `kebab-case.md`, named by topic, not by section number

### SKILL.md Format

```markdown
---
name: {skill-name}
description: {One paragraph. Lead with what the skill does, then list trigger phrases the agent should activate on. Be specific — vague descriptions hurt discovery.}
license: MIT
metadata:
  author: Pirxey
  version: "1.0.0"
  homepage: https://pirxey.com
  source: https://github.com/pirxey/skills
---

# {Skill Title}

{Short intro: what you do, how you behave, what you produce.}

## Workflow / Architecture

{Optional ASCII diagram showing the flow.}

## Quick Reference

| Need to… | See |
|---|---|
| {use case} | [{topic}](./references/{topic}.md) |

## Start Here

{Per-use-case routing — "User says X → do Y".}

---

## {Phase 1 / Procedure}

{Main inline content. Push depth into references/.}
```

### Description Guidance

The `description` is what skills.sh, the CLI search, and agents see at discovery time. It must:

- **Lead with what the skill does** (not how)
- **List trigger phrases** — exact words the agent should activate on
- **Stay under ~700 chars** — anything longer gets truncated in some UIs

Good example:
> Audit a domain's email authentication setup — SPF, DKIM, DMARC, and BIMI. Use when the user asks to check, audit, verify, debug, or set up SPF/DKIM/DMARC/BIMI, asks "why do my emails go to spam", or names an ESP like SendGrid, Amazon SES, Mailgun, or Postmark together with a domain.

Bad example:
> Email skill for various deliverability tasks.

### Progressive Disclosure

Keep `SKILL.md` as a **router**, not a textbook. Push depth into `references/` files that the agent loads only when relevant. This keeps the agent's context window lean.

Pattern:

- `SKILL.md` (~150 lines): workflow, quick reference table, start-here per use case, short inline procedure
- `references/{topic}.md` (200–400 lines each): exhaustive treatment of one sub-topic

### Adding the Skill to `skills.sh.json`

After creating the skill directory, register it in `skills.sh.json` so it lands in the right group on the skills.sh listing:

```json
{
  "groupings": [
    {
      "title": "Email Authentication",
      "description": "...",
      "skills": ["email-auth-audit", "your-new-skill"]
    }
  ]
}
```

## Editing Existing Skills

- **Don't change `name:` in SKILL.md frontmatter** — it's the install-time identifier. Renaming breaks `npx skills add` for existing users.
- **Bump `metadata.version`** on any behavior change (semver: patch for fixes, minor for new capabilities, major for breaking workflow changes).
- **Keep the description forward-compatible.** Trigger phrases should be additive — don't remove ones that were once supported.

## Testing a Skill Locally

```bash
# Install from this local checkout
npx skills add ./skills/{skill-name} -g

# Or install from the live repo
npx skills add pirxey/skills --skill {skill-name} -g

# Verify the agent sees it
# (e.g. in Claude Code, ask for something that should trigger it)
```

## House Style

- **No marketing-speak in SKILL.md.** It runs at agent-discovery time and the agent ranks it against other skills — exaggeration costs activation accuracy.
- **Marketing belongs in README.md**, where humans read.
- **Each reference file is one topic.** Don't make `everything-else.md`.
- **Code blocks are tested.** If you include a `dig` / `openssl` / `curl` snippet, it should run as-is.

## Need help building a skill?

Open an issue, or reach out: [pirxey.com](https://pirxey.com).
