#!/usr/bin/env bash
# audit.sh — Phase 1 runner for the email-auth-audit skill.
#
# Probes SPF, DKIM (ESP-tuned selectors), DMARC, and BIMI for a domain and
# prints a compact verdict table (OK / WARN / FAIL / n/a).
#
# Usage:
#   ./audit.sh <domain> [esp]
#
# ESP names: google, m365, ses, sendgrid, mailgun, postmark, mailchimp,
#            hubspot, brevo, klaviyo, activecampaign, zendesk, intercom
#
# Examples:
#   ./audit.sh example.com
#   ./audit.sh example.com sendgrid
#
# Dependencies: dig, awk, grep. Optional: openssl, curl for BIMI deep validation
# (delegated to bimi-validate.sh).

set -euo pipefail

readonly RESOLVER="@1.1.1.1"

if [[ $# -lt 1 ]]; then
  printf 'usage: %s <domain> [esp]\n' "$(basename "$0")" >&2
  exit 64
fi

readonly DOMAIN="$1"
readonly ESP="${2:-}"

# Output collectors
declare -a RAW_LINES=()
declare -a VERDICT_LINES=()

color() {
  case "${1:-}" in
    OK)   printf '\033[32m%-6s\033[0m' "$1" ;;
    WARN) printf '\033[33m%-6s\033[0m' "$1" ;;
    FAIL) printf '\033[31m%-6s\033[0m' "$1" ;;
    n/a)  printf '\033[90m%-6s\033[0m' "$1" ;;
    *)    printf '%-6s' "${1:-}" ;;
  esac
}

dig_txt() {
  # Args: <name>. Returns concatenated TXT data (no surrounding quotes), one record per line.
  dig +short TXT "$1" "$RESOLVER" 2>/dev/null | sed 's/" "//g; s/^"//; s/"$//'
}

dig_cname() {
  dig +short CNAME "$1" "$RESOLVER" 2>/dev/null
}

selectors_for_esp() {
  case "${1:-}" in
    google)         echo "google" ;;
    m365|microsoft) echo "selector1 selector2" ;;
    ses|amazonses)  echo "" ;; # SES uses random 24-char hex, no probe
    sendgrid)       echo "s1 s2 em sendgrid" ;;
    mailgun)        echo "k1 mta mailo" ;;
    postmark)       echo "pm 20150623 20240101" ;;
    mailchimp)      echo "k1 k2 k3" ;;
    hubspot)        echo "hs1 hs2" ;;
    brevo|sendinblue) echo "mail" ;;
    klaviyo)        echo "klaviyo klaviyo1 klaviyo2" ;;
    activecampaign) echo "dk" ;;
    zendesk)        echo "zendesk1 zendesk2" ;;
    intercom)       echo "intercom" ;;
    "" )            # No ESP given — probe a broad common set.
                    echo "google selector1 selector2 s1 s2 k1 k2 k3 pm mail dk klaviyo hs1 hs2" ;;
    *)              echo "" ;;
  esac
}

###############################################################################
# Step 1 — SPF
###############################################################################
spf_audit() {
  local raw spf_lines count
  raw="$(dig_txt "$DOMAIN" || true)"
  spf_lines="$(grep -E '^v=spf1' <<<"$raw" || true)"
  count="$(grep -cE '^v=spf1' <<<"$raw" || true)"

  RAW_LINES+=("SPF raw: ${spf_lines:-<none>}")

  if [[ -z "$spf_lines" ]]; then
    VERDICT_LINES+=("$(color FAIL)  SPF      no v=spf1 record found")
    return
  fi
  if [[ "$count" -gt 1 ]]; then
    VERDICT_LINES+=("$(color FAIL)  SPF      multiple v=spf1 records ($count) — merge into one")
    return
  fi

  local qualifier note=""
  if grep -qE -- '-all' <<<"$spf_lines"; then qualifier="-all"
  elif grep -qE -- '~all' <<<"$spf_lines"; then qualifier="~all"
  elif grep -qE -- '\?all' <<<"$spf_lines"; then qualifier="?all"; note=" — neutral qualifier, no protection"
  elif grep -qE -- '\+all' <<<"$spf_lines"; then qualifier="+all"; note=" — allows anyone to spoof"
  else qualifier="<missing>"; note=" — no all-mechanism qualifier"
  fi

  if [[ "$qualifier" == "+all" || "$qualifier" == "?all" || "$qualifier" == "<missing>" ]]; then
    VERDICT_LINES+=("$(color FAIL)  SPF      qualifier=$qualifier$note")
  else
    local trim="${spf_lines:0:70}"
    VERDICT_LINES+=("$(color OK)  SPF      $trim")
  fi
}

###############################################################################
# Step 2 — DKIM
###############################################################################
dkim_audit() {
  local sels found=()
  sels="$(selectors_for_esp "$ESP")"

  if [[ -z "$sels" ]]; then
    if [[ -n "$ESP" ]]; then
      VERDICT_LINES+=("$(color WARN)  DKIM     ESP '$ESP' uses non-probable selectors (check ESP console)")
      return
    fi
  fi

  for sel in $sels; do
    local name="${sel}._domainkey.${DOMAIN}"
    local txt cname
    txt="$(dig_txt "$name" || true)"
    cname="$(dig_cname "$name" || true)"
    if [[ -n "$txt" ]]; then
      found+=("$sel(TXT)")
      RAW_LINES+=("DKIM $sel TXT: ${txt:0:80}…")
    elif [[ -n "$cname" ]]; then
      found+=("$sel(CNAME→${cname%.})")
      RAW_LINES+=("DKIM $sel CNAME: $cname")
    fi
  done

  if [[ ${#found[@]} -eq 0 ]]; then
    VERDICT_LINES+=("$(color FAIL)  DKIM     no selectors found for probed set${ESP:+ (ESP=$ESP)}")
    return
  fi

  # Probe key length on the first TXT-resolving selector.
  local key_note=""
  for sel in $sels; do
    local txt
    txt="$(dig_txt "${sel}._domainkey.${DOMAIN}" || true)"
    if [[ -n "$txt" ]]; then
      local p_b64 p_len
      p_b64="$(sed -n 's/.*p=\([A-Za-z0-9+/=]*\).*/\1/p' <<<"$txt" | head -1)"
      p_len="${#p_b64}"
      if [[ -z "$p_b64" ]]; then
        key_note=" — p= empty (revoked)"
        break
      elif [[ "$p_len" -lt 200 ]]; then
        key_note=" — key ~1024-bit (consider 2048 on rotation)"
      else
        key_note=" — 2048-bit key"
      fi
      break
    fi
  done

  VERDICT_LINES+=("$(color OK)  DKIM     ${found[*]}${key_note}")
}

###############################################################################
# Step 3 — DMARC
###############################################################################
dmarc_audit() {
  local raw record p rua pct sp
  raw="$(dig_txt "_dmarc.${DOMAIN}" || true)"
  record="$(grep -E '^v=DMARC1' <<<"$raw" | head -1 || true)"
  RAW_LINES+=("DMARC raw: ${record:-<none>}")

  if [[ -z "$record" ]]; then
    VERDICT_LINES+=("$(color FAIL)  DMARC    no _dmarc record found")
    DMARC_ENFORCED=0
    return
  fi

  p="$(sed -n 's/.*[; ]p=\([a-z]*\).*/\1/p' <<<"$record")"
  rua="$(sed -n 's/.*[; ]rua=\([^;]*\).*/\1/p' <<<"$record" | tr -d ' ')"
  pct="$(sed -n 's/.*[; ]pct=\([0-9]*\).*/\1/p' <<<"$record")"
  sp="$(sed -n 's/.*[; ]sp=\([a-z]*\).*/\1/p' <<<"$record")"

  : "${p:=none}"
  : "${pct:=100}"

  local verdict status note=""
  case "$p" in
    reject)
      status=OK
      [[ "$pct" -lt 100 ]] && { status=WARN; note=" — pct=$pct, finish ramp"; }
      ;;
    quarantine)
      if [[ "$pct" -lt 100 ]]; then status=WARN; note=" — pct=$pct, finish ramp"
      else status=OK; note=" — consider p=reject"
      fi
      ;;
    none)
      status=WARN; note=" — reporting only, ramp policy"
      ;;
    *)
      status=FAIL; note=" — invalid p=$p"
      ;;
  esac

  if [[ -z "$rua" ]]; then
    [[ "$status" == "OK" ]] && status=WARN
    note="$note, no rua= (reporting blind)"
  fi

  verdict="p=$p pct=$pct${sp:+ sp=$sp}${rua:+ rua=set}${note}"
  VERDICT_LINES+=("$(color "$status")  DMARC    $verdict")

  if [[ "$p" =~ ^(quarantine|reject)$ ]] && [[ "$pct" -eq 100 ]]; then
    DMARC_ENFORCED=1
  else
    DMARC_ENFORCED=0
  fi
}

###############################################################################
# Step 4 — BIMI (only when DMARC enforced)
###############################################################################
bimi_audit() {
  if [[ "${DMARC_ENFORCED:-0}" -ne 1 ]]; then
    VERDICT_LINES+=("$(color n/a)  BIMI     skipped — requires DMARC at quarantine/reject pct=100")
    return
  fi

  local raw record l_url a_url
  raw="$(dig_txt "default._bimi.${DOMAIN}" || true)"
  record="$(grep -E '^v=BIMI1' <<<"$raw" | head -1 || true)"
  RAW_LINES+=("BIMI raw: ${record:-<none>}")

  if [[ -z "$record" ]]; then
    VERDICT_LINES+=("$(color FAIL)  BIMI     no default._bimi record found")
    return
  fi

  l_url="$(sed -n 's/.*[; ]l=\([^;]*\).*/\1/p' <<<"$record" | tr -d ' ')"
  a_url="$(sed -n 's/.*[; ]a=\([^;]*\).*/\1/p' <<<"$record" | tr -d ' ')"

  if [[ -z "$l_url" ]]; then
    VERDICT_LINES+=("$(color FAIL)  BIMI     record present but no l= (SVG URL)")
    return
  fi

  if [[ -z "$a_url" ]]; then
    VERDICT_LINES+=("$(color WARN)  BIMI     l= present, a= missing — Yahoo-only (no Gmail / Apple)")
    return
  fi

  VERDICT_LINES+=("$(color OK)  BIMI     l= and a= present — run scripts/bimi-validate.sh for deep check")
}

###############################################################################
# Run
###############################################################################
spf_audit
dkim_audit
dmarc_audit
bimi_audit

printf '\nDomain: %s%s\n\n' "$DOMAIN" "${ESP:+  (ESP hint: $ESP)}"
for line in "${VERDICT_LINES[@]}"; do
  printf '  %b\n' "$line"
done

printf '\nRaw records:\n'
for line in "${RAW_LINES[@]}"; do
  printf '  %s\n' "$line"
done
