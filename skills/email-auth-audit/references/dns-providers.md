# DNS Provider Cheat Sheet

The records are the same everywhere; the panels are not. This is per-provider guidance for the remediation walk-through.

Ask the user *"What service manages your DNS?"* before reciting any of this. If they don't know, run `dig +short NS example.com @1.1.1.1` — the answer tells you (`ns1.cloudflare.com`, `ns-XXX.awsdns-XX.com` = Route53, `ns1.domaincontrol.com` = GoDaddy, etc.).

## Cloudflare

**Strengths:** fastest UI, free DMARC management, free analytics, instant propagation, supports long DKIM TXTs natively.

**Path:** Dashboard → select domain → DNS → Records → Add record.

**Conventions:**

- Apex name: type `@` (Cloudflare auto-fills to the domain).
- Subdomain: type just `s1._domainkey` — Cloudflare appends `.example.com`.
- Proxy status: **must be DNS-only (grey cloud)** for all email-related records. Orange-cloud will break them since Cloudflare doesn't proxy TXT/MX.
- TTL: leave on "Auto" (5 min effective).

**DMARC shortcut:** Dashboard → Email → DMARC Management → Enable. Auto-creates `_dmarc` at `p=none` and points `rua=` at Cloudflare's free analytics. Reports show in the same panel. The policy can be ramped (`none → quarantine → reject`) from a dropdown without editing DNS by hand.

**Email Routing for inbound:** If they use Cloudflare Email Routing, MX and SPF are managed for them under Email → Email Routing → Settings → Email Configuration. Don't touch SPF directly — let Cloudflare manage it and add `include:_spf.mx.cloudflare.net` only via the Routing UI.

## AWS Route 53

**Strengths:** programmable (Terraform / CLI), integrates with SES.

**Path:** Console → Route 53 → Hosted Zones → select zone → Create record.

**Conventions:**

- Record name: **leave blank for apex** (don't type `@`).
- Subdomain: type `s1._domainkey` — Route 53 appends the zone.
- Value field: TXT values **must be wrapped in double quotes**: `"v=spf1 include:amazonses.com ~all"`. Multiple strings for long TXTs: `"v=DKIM1; k=rsa; " "p=MIIBIjA..."`.
- TTL: 300 is the safe default during setup. Raise to 3600 once stable.

**SES quirk:** SES generates DKIM as 3 CNAMEs (`<random>._domainkey.example.com` → `<random>.dkim.amazonses.com`). All three must be added or DKIM fails intermittently. Console > SES > Verified Identities > <domain> > "Publish DNS records" gives the exact values.

**Programmatic:**

```bash
aws route53 change-resource-record-sets --hosted-zone-id Z123 --change-batch file://changes.json
```

## GoDaddy

**Strengths:** ubiquitous (many small business domains).

**Path:** My Products → Domains → DNS → Manage Zones → select domain.

**Conventions:**

- Apex name: `@`.
- Subdomain: `s1._domainkey`.
- Type dropdown: explicit (`A`, `CNAME`, `TXT`, `MX`).
- Value field: paste raw, no quotes.
- TTL: defaults to 1 hour, leave it.

**Quirks:**

- Long TXT (2048-bit DKIM): GoDaddy's UI accepts the full string but their backend used to split it incorrectly. As of 2024 this is fixed, but if a DKIM lookup returns garbled output, recreate the record.
- **Cannot add two records with the same name and type** through the UI — for SPF this is right (you should have one anyway), but for some legacy migration scenarios this trips people up.
- DMARC reporting: works, but no native dashboard. Use an external aggregator for `rua=`.

## Azure DNS

**Path:** Azure Portal → DNS Zones → select zone → Recordsets → +Record set.

**Conventions:**

- Name field: `@` for apex, `s1._domainkey` for subdomain.
- Type: TXT or CNAME from dropdown.
- "Value" is split across multiple lines for multi-string TXT — paste one per line.
- TTL: minutes, not seconds. 60 = 1 hour.

**Quirks:**

- Azure terminology: "Recordsets" instead of "records". Same thing.
- For Microsoft 365 mail, all the SPF/DKIM/DMARC records live in this zone — but the actual DKIM keys are managed via Microsoft 365 admin center → Exchange → Email authentication. The Azure DNS side is just CNAMEs to `selector1-example-com._domainkey.example.onmicrosoft.com`.

## Google Domains (now Squarespace Domains)

**Path:** Squarespace Domains → select domain → DNS → Custom records.

**Conventions:**

- Host field: `@` for apex, `s1._domainkey` for subdomain.
- Type: dropdown.
- Data: paste raw.
- TTL: in seconds.

**Quirks:**

- Migrated from Google Domains in 2023 — UI was rebuilt. Some old screenshots in tutorials are wrong.
- No native DMARC dashboard. Use an aggregator.
- For Google Workspace email, the DKIM key is generated from the Workspace admin console (Apps → Google Workspace → Gmail → Authenticate email) and then pasted into a TXT record here.

## Namecheap

**Path:** Domain List → Manage → Advanced DNS → Add New Record.

**Conventions:**

- Type: dropdown.
- Host: `@` for apex, `s1._domainkey` for subdomain.
- Value: paste raw.
- TTL: 30 min default.

**Quirks:**

- The default DNS is "Namecheap Web Hosting DNS" which has a different UI — make sure they're on "Namecheap BasicDNS" or "PremiumDNS".
- Free DNS works fine for all email auth records.

## DNSimple

**Path:** Account → select domain → DNS → Records → Add Record.

**Conventions:** clean and explicit. Apex is empty Name field. TTL in seconds.

**Strength:** TXT handling is robust, no string-split bugs.

## OVH

**Path:** Web Cloud → Domains → select domain → DNS Zone → Add an entry.

**Conventions:**

- Apex: leave subdomain field blank.
- Subdomain: just the prefix (`s1._domainkey`).
- Quotes on TXT values: OVH adds them automatically — **don't paste them** or you'll get double-quoted values.

## Hover / Tucows

**Path:** Hover → select domain → DNS.

**Conventions:** standard. Apex is `@`.

**Quirks:** TXT lookup can take 10–30 min to propagate on first add (slow NS refresh). Subsequent edits are faster.

## When their provider isn't here

- Look for **"DNS"**, **"Zone editor"**, **"Custom records"**, **"Advanced DNS"** in their dashboard.
- If they truly can't find TXT support: recommend pointing the domain's NS to Cloudflare (free, takes ~5 min, and gives them the DMARC dashboard for free).
- If the registrar refuses to delegate NS: that's rare and probably a "domain forwarding" plan, not a full registration. They'd need to upgrade.

## Verifying after any provider

```bash
# Public resolver
dig +short TXT _dmarc.example.com @1.1.1.1

# Authoritative — bypasses public resolver cache
NS=$(dig +short NS example.com @1.1.1.1 | head -1)
dig +short TXT _dmarc.example.com @${NS}
```

If the authoritative NS has the new record but a public resolver still serves the old one, that's resolver caching — the user is done, the world just hasn't caught up. Tell them so, don't ask them to "do it again".
