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
description: This skill should be used when the user asks to "{trigger phrase 1}", "{trigger phrase 2}", or {scenario}. {One sentence on what the skill does and what it produces.}
license: MIT
metadata:
  author: Pirxey
  version: "1.0.0"
  homepage: https://pirxey.com
  source: https://github.com/pirxey/skills
---

# {Skill Title}

{Short intro in imperative form: what to do, how to behave, what to produce. No second-person — write "Act as X" not "You are X".}

## Workflow / Architecture

{Optional ASCII diagram showing the flow.}

## Quick Reference

| Need to… | See |
|---|---|
| {use case} | [{topic}](./references/{topic}.md) |

## Resources

{When the skill bundles `scripts/`, list them here with one-line summaries and the exact invocation. Reference `references/` files implicitly via the Quick Reference table.}

## Start Here

{Per-use-case routing — "User says X → do Y".}

---

## {Phase 1 / Procedure}

{Main inline content in imperative form. Push depth into references/.}
```

### Description Guidance

The `description` is what skills.sh, the CLI search, and agents see at discovery time. It must:

- **Open with "This skill should be used when…"** in third person, followed by quoted trigger phrases (`"check SPF/DKIM"`, `"audit X"`)
- **Mention what the skill produces** after the triggers, so the agent can rank it
- **Stay under ~700 chars** — anything longer gets truncated in some UIs

Good example:
> This skill should be used when the user asks to "audit email authentication", "check SPF/DKIM/DMARC", "verify BIMI", "validate VMC/CMC certificate", "set up DKIM for SendGrid/SES/Mailgun/Postmark", asks "why do my emails go to spam", or names any ESP together with a domain. Audits SPF, DKIM, DMARC, and BIMI step by step and produces a verdict table plus an interactive remediation walkthrough.

Bad examples:
> Email skill for various deliverability tasks.

> Use this skill when you want to audit email — checks SPF, DKIM, DMARC.  (wrong person, no quoted triggers)

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

This repo follows Anthropic's [skill-development](https://github.com/anthropics/claude-code/tree/main/plugins/plugin-dev/skills/skill-development) conventions:

- **Description in third person**, starting with `This skill should be used when…` and listing quoted trigger phrases.
- **Body in imperative form** — write `Run dig`, `Check the record`, `Probe selectors`. Never `You should run dig` or `You'll see…`. The only place second person is allowed is verbatim quotes the agent says to the user.
- **No marketing-speak in SKILL.md.** It runs at agent-discovery time and the agent ranks it against other skills — exaggeration costs activation accuracy.
- **Marketing belongs in README.md**, where humans read.
- **Each reference file is one topic.** Don't make `everything-else.md`.
- **Bundle scripts for repeated commands.** When the SKILL.md procedure would have the agent re-issue the same `dig` / `curl` / `openssl` loop on every run, factor it into `scripts/<name>.sh` and reference the invocation from SKILL.md. Scripts run without consuming context.
- **Code blocks are tested.** If you include a `dig` / `openssl` / `curl` snippet, it should run as-is.

## Need help building a skill?

Open an issue, or reach out: [pirxey.com](https://pirxey.com).
