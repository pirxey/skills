# SPF — Sender Policy Framework

SPF tells receiving mail servers which IPs are authorized to send mail "from" the audited domain. It is a single DNS TXT record on the apex domain (or on each sending subdomain).

## Lookup

```bash
dig +short TXT example.com @1.1.1.1
```

Look for one line starting with `v=spf1`. Two SPF records on the same name = hard fail at most receivers — they must be merged into one.

Alignment between the SPF envelope-from domain and the visible `From:` header is what DMARC actually grades — see [DMARC](./dmarc.md#alignment-the-part-that-actually-matters) for how the two interact.

## Record anatomy

```
v=spf1 include:_spf.google.com include:sendgrid.net ip4:198.51.100.0/24 ~all
└────┘ └─────────── mechanisms (left-to-right evaluation) ──────────────┘ └─┘
version                                                                qualifier
```

| Token | Meaning |
|---|---|
| `v=spf1` | Required version tag. Must be first. |
| `include:domain` | Authorize all senders permitted by `domain`'s SPF. Counts as 1 DNS lookup. |
| `a` / `a:domain` | Authorize the A/AAAA record of the domain. |
| `mx` / `mx:domain` | Authorize the MX hosts of the domain. |
| `ip4:cidr` / `ip6:cidr` | Authorize a literal IP or range. No DNS lookup. |
| `exists:domain` | Match if the domain resolves. Used by some big senders for dynamic SPF. |
| `redirect=domain` | Replace this SPF with another domain's SPF entirely. |
| `~all` | **SoftFail** — preferred. Message is accepted but marked. |
| `-all` | **Fail** — receivers should reject unauthorized senders. Strict. |
| `?all` | Neutral — equivalent to no policy. Avoid. |
| `+all` | Pass everything. **Never use this** — anyone can spoof the domain. |

## The 10-lookup limit (RFC 7208)

SPF allows **at most 10 DNS lookups** during evaluation. Exceeding it returns `PermError` and receivers treat the domain as if SPF were absent. Lookups count for: `include`, `a`, `mx`, `exists`, `redirect`, and any `ptr` (deprecated).

`ip4` / `ip6` do **not** count. Use them to flatten an `include` to bare IPs when possible.

### Counting lookups

Each `include:` counts as 1 itself, plus all lookups its SPF triggers. Example:

```
v=spf1 include:_spf.google.com include:mailgun.org include:sendgrid.net ~all
        └──── 4 lookups ────┘ └── 2 lookups ──┘ └── 1 lookup ──┘
                                                          = 8 total
```

Add `mx` (1) + a subdomain `include` and the record hits the ceiling.

### Tools to count

- Online: [mxtoolbox.com/SuperTool.aspx?action=spf](https://mxtoolbox.com/SuperTool.aspx?action=spf)
- CLI: `spfquery` (libspf2), `pyspf-milter`, `checkdmarc` (Python)

### When the record exceeds 10 lookups

1. **Flatten** — replace `include:` with bare `ip4:` ranges. Use a tool that auto-updates them (Cloudflare, EasyDMARC SPF Flattener), since IPs change.
2. **Move** senders off the apex onto subdomains with their own SPF (e.g. `marketing.example.com` for the ESP).
3. **Drop** unused ESPs. Audit every `include:`.

## ESP include strings

| ESP | Include |
|---|---|
| Google Workspace | `include:_spf.google.com` |
| Microsoft 365 | `include:spf.protection.outlook.com` |
| Amazon SES | `include:amazonses.com` |
| SendGrid | `include:sendgrid.net` |
| Mailgun | `include:mailgun.org` |
| Postmark | `include:spf.mtasv.net` |
| Mailchimp / Mandrill | `include:servers.mcsv.net` |
| HubSpot | `include:_spf.hubspotemail.net` |
| Brevo (Sendinblue) | `include:spf.brevo.com` |
| Klaviyo | `include:_spf.klaviyo.com` |
| ConvertKit | `include:_spf.mcsv.net` (Mandrill) |
| ActiveCampaign | `include:spf.activehosted.com` |
| Zendesk | `include:mail.zendesk.com` |
| Intercom | `include:_spf.intercom.io` |
| Salesforce Marketing Cloud | `include:_spf.salesforce.com` (varies by tenant) |

If the user's sender is not listed, check the ESP's docs for the current include string — they change.

## Verdict logic for the audit

| Finding | Verdict | Action |
|---|---|---|
| No `v=spf1` record | **FAIL** | Add one. |
| Multiple `v=spf1` records | **FAIL** | Merge into one. |
| Qualifier is `+all` or `?all` | **FAIL** | Switch to `~all` (or `-all` once stable). |
| Lookups > 10 | **FAIL** | Flatten or drop unused includes. |
| Qualifier is `~all`, all expected ESPs present | **OK** | None. |
| Qualifier is `-all`, all expected ESPs present | **OK** | None. Strict mode. |
| Missing an expected ESP include | **WARN** | Add the include from the ESP. |

## Common gotchas

- **`v=spf1` not first.** The version tag must be the first token. Some receivers accept it, most don't.
- **Trailing whitespace / line splitting.** A long SPF split across multiple quoted strings in the TXT record is fine (DNS concatenates), but stray spaces inside the joins break it.
- **Two records.** Especially common after migrating ESPs — leftover record from the old provider stays. Delete it.
- **SPF on subdomains.** SPF is per-domain. `mail.example.com` needs its own SPF — `example.com`'s SPF doesn't cover it.
- **Bare `ptr`.** Deprecated. Slow. Some receivers ignore it. Remove.
- **SPF doesn't survive forwarding.** A receiver forwarding the message rewrites the envelope sender, breaking SPF. This is why DKIM + DMARC matter — they survive forwards.
