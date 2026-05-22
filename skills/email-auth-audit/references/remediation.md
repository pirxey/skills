# Phase 2 — Interactive Remediation

Once the audit (Phase 1) ends, you have a verdict table and a list of broken records. Phase 2 is where you walk the user through fixing them — **one DNS change at a time**.

The aim is "hand-holding without lecturing." Give them exact values, wait for them to apply, verify with `dig`, move on.

## Core rules

1. **One record at a time.** Never dump three TXT changes at once. The user will mis-paste at least one.
2. **Exact values.** Always give Type / Name / Value formatted for their DNS panel. No "something like…".
3. **Ask for the provider first** if you don't know it. Cloudflare / GoDaddy / Route53 / Azure have very different UIs and conventions ([dns-providers.md](./dns-providers.md)).
4. **Verify each change before moving on.** Re-run `dig` against `@1.1.1.1` and `@8.8.8.8`. If the user's NS hasn't propagated, query their authoritative NS directly: `dig +short TXT _dmarc.example.com @ns1.theirprovider.com`.
5. **Don't say "now wait 24–48 hours for propagation."** That's outdated advice. Most public resolvers see the change within minutes if TTL is sensible. If propagation is genuinely slow, query the authoritative NS, not the resolver.

## Order of operations

Always do this order — each step depends on the previous:

1. **SPF** — receivers won't accept mail at all without a working SPF.
2. **DKIM** — required for DMARC alignment.
3. **DMARC** — set `p=none; rua=...` first, watch reports, ramp up.
4. **BIMI** — only after DMARC is at `quarantine`/`reject` with `pct=100`.

If multiple records are broken, fix in this order even if BIMI was the user's stated goal. There's no point in BIMI without DMARC enforced.

## Per-step pattern

### SPF

```
Type:  TXT
Name:  @            (or example.com — see provider notes)
Value: v=spf1 include:_spf.google.com include:sendgrid.net ~all
TTL:   3600         (1 hour — short for now, raise after stable)
```

After they confirm:

```bash
dig +short TXT example.com @1.1.1.1
```

Confirm exactly one `v=spf1` line, the includes you expect, and `~all`.

### DKIM

Most ESPs publish DKIM as **CNAMEs**. The user copies them from the ESP's "Domain authentication" page into DNS:

```
Type:  CNAME
Name:  s1._domainkey
Value: s1.domainkey.u12345678.wl001.sendgrid.net.
TTL:   3600
```

Some ESPs (Postmark, custom setups) publish DKIM as TXT directly:

```
Type:  TXT
Name:  pm._domainkey
Value: v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...
```

Verify with:

```bash
dig +short TXT s1._domainkey.example.com @1.1.1.1
```

You should see the public key. If it's still the CNAME without resolution, the user pasted the value wrong.

### DMARC (start at none)

```
Type:  TXT
Name:  _dmarc
Value: v=DMARC1; p=none; rua=mailto:dmarc-reports@example.com; sp=none; adkim=r; aspf=r
TTL:   3600
```

Tell the user to:

1. Set up an inbox or use a free aggregator (Cloudflare, Postmark) for the `rua=` address.
2. Wait 1–2 weeks. Read reports. Identify legitimate senders failing alignment.
3. Fix any unaligned senders (usually by setting up DKIM on a CNAME with that sender).
4. Then ramp policy.

### DMARC ramp

Subsequent updates to the same TXT — they replace the previous value:

```
v=DMARC1; p=quarantine; pct=10; rua=mailto:dmarc-reports@example.com; sp=quarantine; adkim=r; aspf=r
```

Then `pct=100`, then `p=reject; pct=100`, with a week+ between each.

### BIMI

```
Type:  TXT
Name:  default._bimi
Value: v=BIMI1; l=https://example.com/bimi/logo.svg; a=https://example.com/bimi/vmc.pem
TTL:   3600
```

Then upload the SVG and the VMC PEM at those URLs over HTTPS. Verify with [bimichecker.com](https://bimichecker.com/) — manual `dig` won't catch SVG / certificate problems.

## Provider-specific quirks

### Cloudflare DMARC shortcut

If their DNS is on Cloudflare, **don't ask them to add a DMARC TXT manually**. Tell them:

> Cloudflare has a free native DMARC tool. In your Cloudflare dashboard, go to **Email → DMARC Management** and click **Enable DMARC Management**. This auto-creates the `_dmarc` record at `p=none` and sets `rua=` to Cloudflare's free analytics ingestion. You can view reports in the same panel.

Then verify the record appeared. To ramp policy later, edit it in the same panel — Cloudflare lets them flip `none → quarantine → reject` from a dropdown.

### Provider value-field conventions

| Provider | Apex name field | Subdomain name field |
|---|---|---|
| Cloudflare | `@` (auto-fills) | `s1._domainkey` |
| GoDaddy | `@` | `s1._domainkey` |
| Route53 | Empty (leave the name blank) | `s1._domainkey.example.com.` (FQDN) |
| Azure DNS | `@` | `s1._domainkey` |
| Google Domains / Squarespace | `@` | `s1._domainkey` |
| Namecheap | `@` | `s1._domainkey` |

See [dns-providers.md](./dns-providers.md) for the full per-provider walkthrough.

## Verification commands cheat sheet

```bash
# SPF
dig +short TXT example.com @1.1.1.1

# DKIM (replace selector)
dig +short TXT s1._domainkey.example.com @1.1.1.1
dig +short CNAME s1._domainkey.example.com @1.1.1.1

# DMARC
dig +short TXT _dmarc.example.com @1.1.1.1

# BIMI
dig +short TXT default._bimi.example.com @1.1.1.1

# Force fresh lookup (skip resolver cache, query authoritative NS)
NS=$(dig +short NS example.com @1.1.1.1 | head -1)
dig +short TXT _dmarc.example.com @${NS}
```

## When the user gets stuck

- **"It's been an hour, dig still shows the old record."** Their resolver may be caching. Query a different one: `@9.9.9.9`. Or query authoritative: `dig +short TXT _dmarc.example.com @ns1.cloudflare.com`. If the authoritative NS has it, propagation is fine.
- **"My provider doesn't have a `TXT` type."** They probably do, look under "Advanced DNS" or "Custom Records". Some really old registrar UIs hide it — at that point, recommend moving DNS to Cloudflare (free).
- **"The value is too long, my provider truncates it."** This happens with 2048-bit DKIM keys. Most providers handle it transparently by splitting into multiple quoted strings — but a few break. Workaround: use a 1024-bit key for that selector, or move DNS hosting.
- **"My DMARC report inbox is overflowing."** They set `rua=` to a real human inbox. Move to an aggregator (Cloudflare, Postmark — both free at low volume).
