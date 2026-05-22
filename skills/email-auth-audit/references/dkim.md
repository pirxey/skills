# DKIM — DomainKeys Identified Mail

DKIM cryptographically signs outbound messages. The receiver fetches the public key from DNS and verifies the signature. Unlike SPF, DKIM survives forwarding — the signature stays intact even when the message is relayed.

DKIM is published per **selector**. A domain can have many selectors (one per sender, one per rotation, etc.).

## Lookup

```bash
dig +short TXT <selector>._domainkey.<domain> @1.1.1.1
```

Example for SendGrid on `example.com`:

```bash
dig +short TXT s1._domainkey.example.com @1.1.1.1
```

Look for a TXT starting with `v=DKIM1`.

## Record anatomy

```
v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvX...
└─────┘ └────┘ └──────────────── public key ───────────────────┘
version  algo
```

| Tag | Meaning |
|---|---|
| `v=DKIM1` | Version. Required. |
| `k=rsa` | Key algorithm. `rsa` is universal; `ed25519` is newer and supported by Gmail/M365 but not everywhere. |
| `p=...` | Base64-encoded public key. **If empty (`p=;`), the key is revoked**, signatures auto-fail. |
| `t=y` | Test mode — receivers should not penalize failures. Remove in production. |
| `t=s` | Strict mode — subdomains can't use this key. |
| `h=sha256` | Allowed hash algorithm. SHA-256 is required by modern receivers; SHA-1 is broken, do not use. |
| `s=email` | Service type. Almost always `email`. |
| `n=...` | Notes (rarely used). |

## Key length

| Key size | Status |
|---|---|
| 512-bit | **Insecure.** Trivially crackable. Receivers reject. |
| 768-bit | Insecure. Avoid. |
| 1024-bit | **Minimum.** Widely supported, but consider 2048 for new deployments. |
| 2048-bit | **Recommended.** May need to be split across multiple quoted strings in TXT due to length. |

To roughly estimate key size from the `p=` length: a 1024-bit key's base64 is ~216 chars, a 2048-bit is ~392 chars.

## Selector probing per ESP

If the user doesn't know which selectors are in use, probe these by ESP:

| ESP | Selectors to probe |
|---|---|
| Google Workspace | `google` (default), or custom like `gmail`, `mail` |
| Microsoft 365 | `selector1`, `selector2` (both are CNAMEs to Microsoft) |
| Amazon SES | 24-char hex selector — get it from the SES console. No standard probe. |
| SendGrid | `s1`, `s2` (CNAMEs to `s1.domainkey.uXXXXXX.wlYYY.sendgrid.net`) |
| Mailgun | `k1` (CNAME), `mta` for transactional, `mailo` for some accounts |
| Postmark | `pm._domainkey` (TXT, not CNAME — Postmark publishes the key directly) |
| Mailchimp | `k1`, `k2`, `k3` (CNAMEs to `dkim.mcsv.net`) |
| HubSpot | `hs1-<hubID>._domainkey`, `hs2-<hubID>._domainkey` |
| Brevo (Sendinblue) | `mail` |
| Klaviyo | `klaviyo`, `klaviyo1`, `klaviyo2` |
| ActiveCampaign | `dk` |
| Zendesk | `zendesk1`, `zendesk2` |
| Intercom | `intercom-_domainkey` |
| Salesforce Marketing Cloud | tenant-specific selector, e.g. `s10`, varies |

### Probe script pattern

```bash
for sel in google selector1 selector2 s1 s2 k1 k2 k3 pm mail klaviyo; do
  out=$(dig +short TXT "${sel}._domainkey.${domain}" @1.1.1.1)
  [ -n "$out" ] && echo "FOUND: ${sel} → ${out:0:80}..."
done
```

When SendGrid / Mailchimp / etc. publish their DKIM as **CNAMEs**, `dig TXT` still resolves through and returns the TXT at the destination — but the user's DNS panel will show a CNAME row, not a TXT row. Don't tell them to "look for a TXT" if the ESP gave them CNAMEs.

## Verdict logic for the audit

| Finding | Verdict | Action |
|---|---|---|
| No DKIM record for any probed selector | **FAIL** | Set up DKIM with the ESP. |
| `p=` is empty | **FAIL** | Key revoked — regenerate. |
| Key is 1024-bit | **OK** (note) | Consider 2048-bit on next rotation. |
| Key is < 1024-bit | **FAIL** | Rotate immediately. |
| `t=y` (test mode) present | **WARN** | Remove once verified — receivers won't enforce. |
| `h=sha1` only | **FAIL** | Move to SHA-256. |
| Key is 2048-bit, `h=sha256` | **OK** | None. |

## How DKIM signing works (mental model)

1. Sending mail server hashes the message body + selected headers.
2. Signs the hash with the private key.
3. Adds a `DKIM-Signature:` header to the message with: domain (`d=`), selector (`s=`), hash algorithm (`a=`), signed headers list (`h=`), and the signature (`b=`).
4. Receiving server pulls the public key from `<selector>._domainkey.<d>` and verifies.

The `d=` domain in the signature is what DMARC alignment cares about — not the `From:` header's domain by default. If `d=` and `From:` don't share a parent domain, **DMARC fails** even though DKIM succeeded.

## Rotation

DKIM keys should be rotated periodically (recommended yearly, or after any suspected compromise):

1. Generate a new key pair.
2. Publish the new public key under a **new selector** (e.g. `s2` if `s1` is current).
3. Switch the sending platform to sign with the new key.
4. Wait 7+ days for in-flight mail to clear.
5. Either delete the old selector's TXT record, or zero the key (`p=;`) to revoke explicitly.

Never reuse a selector name with a new key — receivers may have it cached and fail signatures during propagation.

## Common gotchas

- **Forgetting subdomain DKIM.** If you send from `mail.example.com`, the selector lookup is `s1._domainkey.mail.example.com`, not `s1._domainkey.example.com`.
- **TXT length splitting.** 2048-bit keys exceed the 255-char TXT string limit. DNS allows concatenating multiple strings inside one TXT record — make sure your provider supports the syntax (most do; some require explicit quoting).
- **CNAME chains.** SendGrid / Mailchimp use CNAMEs so they can rotate keys without user action. Don't replace those CNAMEs with literal TXT — you'll freeze the key.
- **Selector visible in headers.** The selector name is in every email's `DKIM-Signature: s=...` header. Don't name selectors with anything sensitive.
