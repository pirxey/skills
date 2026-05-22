#!/usr/bin/env bash
# bimi-validate.sh — deep BIMI validation for the email-auth-audit skill.
#
# 1. Resolves default._bimi.<domain> TXT
# 2. Fetches the SVG and checks: size < 32KB, XML well-formed, baseProfile=tiny-ps,
#    no <script>, no animation, no external refs.
# 3. Fetches the VMC/CMC PEM and checks: issuer allow-list, validity window,
#    BIMI EKU OID 1.3.6.1.5.5.7.3.31, LogotypeExtension (OID 1.3.6.1.5.5.7.1.12),
#    SHA-256 hash binding (SVG hash vs hash embedded in the cert).
#
# Usage:
#   ./bimi-validate.sh <domain> [selector]
#
# Selector defaults to "default".
#
# Dependencies: dig, curl, openssl, shasum (or sha256sum), grep, sed.
#               xmllint optional (used for SVG well-formedness when present).

set -euo pipefail

readonly RESOLVER="@1.1.1.1"
readonly MAX_SVG_BYTES=32768
readonly BIMI_EKU_OID="1.3.6.1.5.5.7.3.31"
readonly LOGOTYPE_OID="1.3.6.1.5.5.7.1.12"

if [[ $# -lt 1 ]]; then
  printf 'usage: %s <domain> [selector]\n' "$(basename "$0")" >&2
  exit 64
fi

readonly DOMAIN="$1"
readonly SELECTOR="${2:-default}"

WORKDIR="$(mktemp -d -t bimi-validate.XXXXXX)"
trap 'rm -rf "$WORKDIR"' EXIT

declare -a RESULTS=()

ok()   { RESULTS+=("$(printf '\033[32mOK  \033[0m %s' "$1")"); }
warn() { RESULTS+=("$(printf '\033[33mWARN\033[0m %s' "$1")"); }
fail() { RESULTS+=("$(printf '\033[31mFAIL\033[0m %s' "$1")"); }
info() { RESULTS+=("$(printf '\033[90m·   \033[0m %s' "$1")"); }

hash_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

###############################################################################
# Step 1 — Resolve BIMI TXT
###############################################################################
record="$(dig +short TXT "${SELECTOR}._bimi.${DOMAIN}" "$RESOLVER" 2>/dev/null \
  | sed 's/" "//g; s/^"//; s/"$//' \
  | grep -E '^v=BIMI1' | head -1 || true)"

if [[ -z "$record" ]]; then
  fail "no ${SELECTOR}._bimi.${DOMAIN} TXT record"
  printf '\nBIMI validation for %s (selector=%s)\n\n' "$DOMAIN" "$SELECTOR"
  printf '  %b\n' "${RESULTS[@]}"
  exit 1
fi

info "TXT: $record"

l_url="$(sed -n 's/.*[; ]l=\([^;]*\).*/\1/p' <<<"$record" | tr -d ' ')"
a_url="$(sed -n 's/.*[; ]a=\([^;]*\).*/\1/p' <<<"$record" | tr -d ' ')"

[[ -n "$l_url" ]] && ok "l= $l_url" || fail "l= missing — no SVG URL"
if [[ -z "$a_url" ]]; then
  warn "a= missing — Yahoo will render but Gmail / Apple Mail will not"
fi

###############################################################################
# Step 2 — Fetch + validate SVG
###############################################################################
SVG_FILE="$WORKDIR/logo.svg"

if [[ -n "$l_url" ]]; then
  if curl -sSLf -o "$SVG_FILE" "$l_url"; then
    size=$(wc -c <"$SVG_FILE" | tr -d ' ')
    if [[ "$size" -lt "$MAX_SVG_BYTES" ]]; then
      ok "SVG size $size bytes (< 32KB)"
    else
      fail "SVG size $size bytes — exceeds 32KB limit"
    fi

    if command -v xmllint >/dev/null 2>&1; then
      if xmllint --noout "$SVG_FILE" 2>/dev/null; then
        ok "SVG is well-formed XML"
      else
        fail "SVG is not well-formed XML"
      fi
    else
      info "xmllint not installed — skipping XML structural check"
    fi

    if grep -qE 'baseProfile=("|'"'"')tiny-ps' "$SVG_FILE"; then
      ok "baseProfile=tiny-ps present"
    else
      fail "baseProfile=tiny-ps missing — required for BIMI SVG Tiny PS profile"
    fi

    if grep -qE 'version=("|'"'"')1\.2' "$SVG_FILE"; then
      ok "version=1.2 present"
    else
      warn "version=1.2 not asserted on <svg> root"
    fi

    if grep -qE 'viewBox=("|'"'"')[^"]+' "$SVG_FILE"; then
      vb="$(sed -n 's/.*viewBox=["'"'"']\([^"'"'"']*\).*/\1/p' "$SVG_FILE" | head -1)"
      read -r _ _ vw vh <<<"$vb"
      if [[ -n "$vw" && -n "$vh" && "$vw" == "$vh" ]]; then
        ok "viewBox is square ($vb)"
      else
        fail "viewBox is not square ($vb) — BIMI requires square aspect"
      fi
    else
      fail "viewBox missing"
    fi

    forbidden_hit=0
    for pattern in '<script' '<animate' '<animateMotion' '<animateTransform' '<foreignObject' 'onclick=' 'onload='; do
      if grep -q "$pattern" "$SVG_FILE"; then
        fail "forbidden element / attribute: $pattern"
        forbidden_hit=1
      fi
    done
    if grep -qE '<image[^>]*href=["'"'"']https?://' "$SVG_FILE"; then
      fail "external <image href=…> reference forbidden"
      forbidden_hit=1
    fi
    if grep -qE '<use[^>]*href=["'"'"']https?://' "$SVG_FILE"; then
      fail "external <use href=…> reference forbidden"
      forbidden_hit=1
    fi
    [[ "$forbidden_hit" -eq 0 ]] && ok "no forbidden elements / attributes found"

    svg_hash="$(hash_sha256 "$SVG_FILE")"
    info "SVG SHA-256: $svg_hash"
  else
    fail "SVG fetch failed: $l_url"
  fi
fi

###############################################################################
# Step 3 — Fetch + validate VMC/CMC certificate
###############################################################################
if [[ -n "$a_url" ]]; then
  PEM_FILE="$WORKDIR/cert.pem"
  if curl -sSLf -o "$PEM_FILE" "$a_url"; then
    ok "PEM fetched ($(wc -c <"$PEM_FILE" | tr -d ' ') bytes)"

    cert_text="$WORKDIR/cert.txt"
    if openssl crl2pkcs7 -nocrl -certfile "$PEM_FILE" 2>/dev/null \
        | openssl pkcs7 -print_certs -text -noout 2>/dev/null >"$cert_text"; then
      :
    else
      openssl x509 -in "$PEM_FILE" -text -noout >"$cert_text" 2>/dev/null || true
    fi

    # Issuer allow-list
    issuer_line="$(grep -m1 'Issuer:' "$cert_text" || true)"
    if grep -qiE 'DigiCert|Entrust|SSL\.com|GlobalSign' <<<"$issuer_line"; then
      ok "issuer recognized: ${issuer_line#*Issuer: }"
    else
      fail "issuer not on BIMI allow-list: ${issuer_line:-<none>}"
    fi

    # Validity
    if openssl x509 -in "$PEM_FILE" -noout -checkend 0 >/dev/null 2>&1; then
      dates="$(openssl x509 -in "$PEM_FILE" -noout -dates 2>/dev/null | tr '\n' ' ')"
      ok "certificate valid: $dates"
    else
      dates="$(openssl x509 -in "$PEM_FILE" -noout -dates 2>/dev/null | tr '\n' ' ')"
      fail "certificate expired or not yet valid: $dates"
    fi

    # EKU OID — openssl may show it as a long human name ("Brand Indicator for…")
    # or as the raw dotted OID, depending on version and OID database.
    if grep -qiE "${BIMI_EKU_OID}|BIMI|Brand Indicator for Message" "$cert_text"; then
      ok "BIMI EKU present (OID $BIMI_EKU_OID)"
    else
      fail "BIMI EKU OID $BIMI_EKU_OID missing"
    fi

    # LogotypeExtension
    if grep -qE "${LOGOTYPE_OID}|id-pe-logotype|Logotype" "$cert_text"; then
      ok "LogotypeExtension present ($LOGOTYPE_OID)"
    else
      fail "LogotypeExtension $LOGOTYPE_OID missing — logo not embedded in cert"
    fi

    # Hash binding — best-effort. The embedded hash sits inside the LogotypeExtension
    # as DER; surface it via asn1parse and look for the served SVG's SHA-256 hex.
    if [[ -n "${svg_hash:-}" ]]; then
      openssl x509 -in "$PEM_FILE" -outform DER 2>/dev/null \
        | openssl asn1parse -inform DER 2>/dev/null \
        | grep -i "$svg_hash" >/dev/null \
        && ok "logo hash binding matches served SVG ($svg_hash)" \
        || warn "could not confirm logo hash binding via asn1parse — verify via bimichecker.com"
    fi
  else
    fail "PEM fetch failed: $a_url"
  fi
fi

###############################################################################
# Report
###############################################################################
printf '\nBIMI validation for %s (selector=%s)\n\n' "$DOMAIN" "$SELECTOR"
for line in "${RESULTS[@]}"; do
  printf '  %b\n' "$line"
done

# Exit 1 when any FAIL was emitted.
if printf '%s\n' "${RESULTS[@]}" | grep -q '^FAIL'; then
  exit 1
fi
