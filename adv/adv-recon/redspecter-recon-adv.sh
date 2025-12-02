#!/usr/bin/env bash
#
# Red Specter – ADV Recon v1.1
# File: adv/adv-recon/redspecter-recon-adv.sh
#
# Advanced reconnaissance wrapper:
# - Passive subdomain enumeration
# - DNS resolution
# - HTTP probing & tech fingerprinting (if httpx installed)
# - Basic WHOIS + DNS records
# - Markdown summary report
#
# SAFE-BY-DEFAULT: Passive OSINT + light probing only.
#

set -euo pipefail

VERSION="1.1"

# ---------- Colours ----------
RED="$(tput setaf 1 2>/dev/null || true)"
GREEN="$(tput setaf 2 2>/dev/null || true)"
YELLOW="$(tput setaf 3 2>/dev/null || true)"
BLUE="$(tput setaf 4 2>/dev/null || true)"
BOLD="$(tput bold 2>/dev/null || true)"
RESET="$(tput sgr0 2>/dev/null || true)"

# ---------- Paths ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPORT_DIR="${BASE_DIR}/reports"

# ---------- Helpers ----------
usage() {
  cat <<EOF

===========================================
      RED SPECTER - ADV RECON v${VERSION}
===========================================

Advanced reconnaissance wrapper (passive-first).

Usage:
  $(basename "$0") -d <domain> [-t <tag>]

Options:
  -d, --domain DOMAIN   Target domain (required)
  -t, --tag TAG         Optional label for this run (e.g. client name)
  -h, --help            Show this help message

Examples:
  $(basename "$0") -d example.com
  $(basename "$0") -d example.com -t ClientA

If no options are provided, interactive mode will prompt for a domain and tag.

EOF
}

check_binary() {
  local bin="$1"
  if command -v "$bin" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

authorization_prompt() {
  echo
  echo "${YELLOW}${BOLD}ROE / AUTHORIZATION CHECK (ADV RECON)${RESET}"
  echo "${YELLOW}Only use this tool on domains where you have explicit, written permission.${RESET}"
  echo
  read -r -p "Do you confirm you are authorised to recon this domain? (yes/no): " ans
  case "$ans" in
    yes|y|Y)
      echo "${GREEN}[+] Authorization confirmed. Continuing...${RESET}"
      ;;
    *)
      echo "${RED}[!] Authorization not confirmed. Aborting.${RESET}"
      exit 1
      ;;
  esac
}

banner() {
  echo
  echo "${RED}${BOLD}===========================================${RESET}"
  echo "${RED}${BOLD}         RED SPECTER - ADV RECON v${VERSION}${RESET}"
  echo "${RED}${BOLD}===========================================${RESET}"
  echo
  echo "${YELLOW}Advanced reconnaissance module.${RESET}"
  echo "${YELLOW}Passive-first OSINT, DNS and HTTP probing only.${RESET}"
  echo
}

# ---------- Main ----------
main() {
  local DOMAIN=""
  local TAG=""

  # If no args at all → interactive mode
  if [[ $# -eq 0 ]]; then
    banner
    echo "${BLUE}[i] No arguments supplied — entering interactive mode.${RESET}"
    echo
    read -rp "Enter target domain: " DOMAIN
    if [[ -z "$DOMAIN" ]]; then
      echo "${RED}[!] A domain is required.${RESET}"
      exit 1
    fi
    read -rp "Enter optional tag (or press Enter to skip): " TAG
  else
    # Parse args
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -d|--domain)
          DOMAIN="${2:-}"
          shift 2
          ;;
        -t|--tag)
          TAG="${2:-}"
          shift 2
          ;;
        -h|--help)
          usage
          exit 0
          ;;
        *)
          echo "${RED}[!] Unknown argument: $1${RESET}"
          usage
          exit 1
          ;;
      esac
    done
  fi

  if [[ -z "$DOMAIN" ]]; then
    echo "${RED}[!] Domain is required (-d / --domain).${RESET}"
    usage
    exit 1
  fi

  banner
  authorization_prompt

  # Dependency info
  echo "${BLUE}[i] Checking optional recon tools...${RESET}"
  local HAVE_SUBFINDER="false"
  local HAVE_AMASS="false"
  local HAVE_ASSETFINDER="false"
  local HAVE_DNSX="false"
  local HAVE_HTTPX="false"
  local HAVE_WHOIS="false"
  local HAVE_DIG="false"

  if check_binary subfinder; then
    HAVE_SUBFINDER="true"; echo "${GREEN}[+] subfinder found.${RESET}"
  else
    echo "${YELLOW}[-] subfinder not found. Skipping subfinder stage.${RESET}"
  fi

  if check_binary amass; then
    HAVE_AMASS="true"; echo "${GREEN}[+] amass found.${RESET}"
  else
    echo "${YELLOW}[-] amass not found. Skipping amass stage.${RESET}"
  fi

  if check_binary assetfinder; then
    HAVE_ASSETFINDER="true"; echo "${GREEN}[+] assetfinder found.${RESET}"
  else
    echo "${YELLOW}[-] assetfinder not found. Skipping assetfinder stage.${RESET}"
  fi

  if check_binary dnsx; then
    HAVE_DNSX="true"; echo "${GREEN}[+] dnsx found.${RESET}"
  else
    echo "${YELLOW}[-] dnsx not found. DNS resolution will be basic only.${RESET}"
  fi

  if check_binary httpx; then
    HAVE_HTTPX="true"; echo "${GREEN}[+] httpx found.${RESET}"
  else
    echo "${YELLOW}[-] httpx not found. HTTP probing / tech detection will be skipped.${RESET}"
  fi

  if check_binary whois; then
    HAVE_WHOIS="true"; echo "${GREEN}[+] whois found.${RESET}"
  else
    echo "${YELLOW}[-] whois not found. WHOIS info will be skipped.${RESET}"
  fi

  if check_binary dig; then
    HAVE_DIG="true"; echo "${GREEN}[+] dig found.${RESET}"
  else
    echo "${YELLOW}[-] dig not found. DNS record enumeration will be limited.${RESET}"
  fi

  # Prepare directories
  mkdir -p "${REPORT_DIR}"
  local ts
  ts="$(date +'%Y%m%d_%H%M%S')"

  local safe_domain
  safe_domain="$(echo "$DOMAIN" | sed 's/[^A-Za-z0-9._-]/_/g')"
  local label="${safe_domain}"
  if [[ -n "$TAG" ]]; then
    local safe_tag
    safe_tag="$(echo "$TAG" | sed 's/[^A-Za-z0-9._-]/_/g')"
    label="${safe_tag}_${safe_domain}"
  fi

  local RUN_DIR="${REPORT_DIR}/adv-recon_${label}_${ts}"
  mkdir -p "${RUN_DIR}"/{raw,lists,summary}

  echo
  echo "${GREEN}[+] Run directory: ${RUN_DIR}${RESET}"
  echo

  local SUBS_ALL="${RUN_DIR}/lists/subdomains_all.txt"
  local SUBS_UNIQUE="${RUN_DIR}/lists/subdomains_unique.txt"
  local RESOLVED_HOSTS="${RUN_DIR}/lists/resolved_hosts.txt"
  local HTTPX_OUT="${RUN_DIR}/raw/httpx.txt"
  local WHOIS_OUT="${RUN_DIR}/raw/whois.txt"
  local DNS_RECORDS_OUT="${RUN_DIR}/raw/dns_records.txt"
  local SUMMARY_MD="${RUN_DIR}/summary/ADV_Recon_Summary_${safe_domain}.md"

  touch "$SUBS_ALL" "$SUBS_UNIQUE"

  # ---------- Stage 1: WHOIS / DNS baseline ----------
  echo "${BLUE}[i] Stage 1: WHOIS and DNS baseline for ${DOMAIN}${RESET}"

  if [[ "$HAVE_WHOIS" == "true" ]]; then
    echo "${BLUE}[i] Running whois...${RESET}"
    whois "$DOMAIN" > "$WHOIS_OUT" 2>/dev/null || true
  else
    echo "${YELLOW}[-] Skipping whois (not installed).${RESET}"
  fi

  if [[ "$HAVE_DIG" == "true" ]]; then
    {
      echo ";; A records"
      dig +short A "$DOMAIN"
      echo
      echo ";; AAAA records"
      dig +short AAAA "$DOMAIN"
      echo
      echo ";; MX records"
      dig +short MX "$DOMAIN"
      echo
      echo ";; NS records"
      dig +short NS "$DOMAIN"
      echo
      echo ";; TXT records"
      dig +short TXT "$DOMAIN"
    } > "$DNS_RECORDS_OUT" 2>/dev/null || true
  else
    echo "${YELLOW}[-] Skipping detailed DNS records (dig not installed).${RESET}"
  fi

  # ---------- Stage 2: Passive subdomain enumeration ----------
  echo
  echo "${BLUE}[i] Stage 2: Passive subdomain enumeration for ${DOMAIN}${RESET}"

  if [[ "$HAVE_SUBFINDER" == "true" ]]; then
    echo "${BLUE}[i] Running subfinder...${RESET}"
    subfinder -silent -d "$DOMAIN" >> "$SUBS_ALL" 2>/dev/null || true
  fi

  if [[ "$HAVE_AMASS" == "true" ]]; then
    echo "${BLUE}[i] Running amass (passive)...${RESET}"
    amass enum -passive -d "$DOMAIN" >> "$SUBS_ALL" 2>/dev/null || true
  fi

  if [[ "$HAVE_ASSETFINDER" == "true" ]]; then
    echo "${BLUE}[i] Running assetfinder...${RESET}"
    assetfinder --subs-only "$DOMAIN" >> "$SUBS_ALL" 2>/dev/null || true
  fi

  if [[ ! -s "$SUBS_ALL" ]]; then
    echo "${YELLOW}[-] No subdomains discovered by available tools.${RESET}"
  else
    sort -u "$SUBS_ALL" > "$SUBS_UNIQUE"
    echo "${GREEN}[+] Unique subdomains written to: ${SUBS_UNIQUE}${RESET}"
    echo "${BLUE}[i] Total unique subdomains: $(wc -l < "$SUBS_UNIQUE" | xargs)${RESET}"
  fi

  # ---------- Stage 3: DNS resolution ----------
  echo
  echo "${BLUE}[i] Stage 3: DNS resolution of discovered subdomains${RESET}"
  if [[ -s "$SUBS_UNIQUE" ]]; then
    if [[ "$HAVE_DNSX" == "true" ]]; then
      echo "${BLUE}[i] Using dnsx to resolve...${RESET}"
      dnsx -silent -resp -l "$SUBS_UNIQUE" > "$RESOLVED_HOSTS" 2>/dev/null || true
      echo "${GREEN}[+] Resolved hosts written to: ${RESOLVED_HOSTS}${RESET}"
    else
      echo "${YELLOW}[-] dnsx not available, using basic ping-based check (slower, less accurate).${RESET}"
      > "$RESOLVED_HOSTS"
      while IFS= read -r sub; do
        [[ -z "$sub" ]] && continue
        if ping -c 1 -W 1 "$sub" >/dev/null 2>&1; then
          echo "$sub" >> "$RESOLVED_HOSTS"
        fi
      done < "$SUBS_UNIQUE"
      echo "${GREEN}[+] Basic resolved hosts written to: ${RESOLVED_HOSTS}${RESET}"
    fi
  else
    echo "${YELLOW}[-] No subdomains to resolve.${RESET}"
  fi

  # ---------- Stage 4: HTTP probing & tech detection ----------
  echo
  echo "${BLUE}[i] Stage 4: HTTP probing & tech detection${RESET}"
  if [[ "$HAVE_HTTPX" == "true" && -s "$RESOLVED_HOSTS" ]]; then
    echo "${BLUE}[i] Running httpx on resolved hosts...${RESET}"
    httpx -l "$RESOLVED_HOSTS" -status-code -title -tech-detect -silent > "$HTTPX_OUT" 2>/dev/null || true
    echo "${GREEN}[+] httpx output written to: ${HTTPX_OUT}${RESET}"
  else
    if [[ "$HAVE_HTTPX" != "true" ]]; then
      echo "${YELLOW}[-] httpx not found. Skipping HTTP probing.${RESET}"
    fi
    if [[ ! -s "$RESOLVED_HOSTS" ]]; then
      echo "${YELLOW}[-] No resolved hosts found. Skipping HTTP probing.${RESET}"
    fi
  fi

  # ---------- Stage 5: Markdown summary ----------
  echo
  echo "${BLUE}[i] Stage 5: Generating Markdown summary${RESET}"

  {
    echo "# Red Specter – ADV Recon Summary"
    echo
    echo "- **Date:** $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "- **Domain:** \`${DOMAIN}\`"
    if [[ -n "$TAG" ]]; then
      echo "- **Tag/Client:** \`${TAG}\`"
    fi
    echo "- **Module:** ADV Recon v${VERSION}"
    echo
    echo "## Overview"
    echo
    echo "This report summarises advanced reconnaissance against the authorised domain."
    echo "The module emphasises passive OSINT and light probing only."
    echo
    echo "## Data Files"
    echo
    echo "- WHOIS: \`$(basename "$WHOIS_OUT")\`"
    echo "- DNS records: \`$(basename "$DNS_RECORDS_OUT")\`"
    echo "- All subdomains (raw): \`$(basename "$SUBS_ALL")\`"
    echo "- Unique subdomains: \`$(basename "$SUBS_UNIQUE")\`"
    echo "- Resolved hosts: \`$(basename "$RESOLVED_HOSTS")\`"
    if [[ -s "$HTTPX_OUT" ]]; then
      echo "- httpx HTTP probing: \`$(basename "$HTTPX_OUT")\`"
    fi
    echo
    echo "## Quick Stats"
    echo
    if [[ -s "$SUBS_UNIQUE" ]]; then
      echo "- **Unique subdomains:** $(wc -l < "$SUBS_UNIQUE" | xargs)"
    else
      echo "- **Unique subdomains:** 0"
    fi
    if [[ -s "$RESOLVED_HOSTS" ]]; then
      echo "- **Resolved hosts:** $(wc -l < "$RESOLVED_HOSTS" | xargs)"
    else
      echo "- **Resolved hosts:** 0"
    fi
    if [[ -s "$HTTPX_OUT" ]]; then
      echo "- **HTTP services identified:** $(wc -l < "$HTTPX_OUT" | xargs)"
    else
      echo "- **HTTP services identified:** 0"
    fi
    echo
    echo "## Next Steps (Suggested)"
    echo
    echo "- Feed resolved hosts and active HTTP services into:"
    echo "  - Core Web Enumeration"
    echo "  - Core / ADV Vulnerability Scanner"
    echo "- Use subdomain lists for:"
    echo "  - Scope confirmation with the client"
    echo "  - Target selection for deeper testing"
    echo
    echo "> All findings are indicative. Confirm scope and verify manually before reporting."
  } > "$SUMMARY_MD"

  echo
  echo "${GREEN}[+] ADV Recon completed.${RESET}"
  echo "${GREEN}[+] Summary report: ${SUMMARY_MD}${RESET}"
  echo
}

main "$@"

