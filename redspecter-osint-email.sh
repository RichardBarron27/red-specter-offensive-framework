#!/usr/bin/env bash
#
# Red Specter - Email OSINT Module
# Version: 1.1 (with crawl tuning)
# Author: Richard + Vigil
#
# Usage:
#   ./redspecter-osint-email.sh example.com
#

set -euo pipefail

VERSION="1.1"

######################
# Colours & Banner   #
######################

RED="$(printf '\033[31m')"
GREEN="$(printf '\033[32m')"
YELLOW="$(printf '\033[33m')"
BLUE="$(printf '\033[34m')"
BOLD="$(printf '\033[1m')"
RESET="$(printf '\033[0m')"

show_banner() {
  echo -e "${RED}${BOLD}"
  echo "==============================================="
  echo "        RED SPECTER - EMAIL OSINT v${VERSION}"
  echo "==============================================="
  echo -e "${RESET}"
}

usage() {
  cat <<EOF
Usage: $0 <domain>

Example:
  $0 example.com

This module will:
  - Crawl the target website and extract emails
  - Query crt.sh for Certificate Transparency data and extract emails
  - Optionally call theHarvester if installed
  - Output a Markdown report under reports/osint-email/
EOF
}

check_dep() {
  local bin="$1"
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo -e "${YELLOW}[!] Missing dependency: ${bin}${RESET}"
    MISSING_DEPS=1
  fi
}

# Deduplicate helper
dedupe() {
  sort -u | sed '/^$/d'
}

######################
# Main               #
######################

show_banner

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

TARGET_DOMAIN="$1"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

BASE_DIR="$(pwd)"
REPORT_BASE_DIR="${BASE_DIR}/reports/osint-email"
RAW_DIR="${REPORT_BASE_DIR}/raw/${TARGET_DOMAIN}_${TIMESTAMP}"
REPORT_MD="${REPORT_BASE_DIR}/${TARGET_DOMAIN}_email_osint_${TIMESTAMP}.md"

mkdir -p "${REPORT_BASE_DIR}" "${RAW_DIR}"

echo -e "${BLUE}[+] Target domain: ${TARGET_DOMAIN}${RESET}"
echo -e "${BLUE}[+] Output directory: ${REPORT_BASE_DIR}${RESET}"
echo

######################
# Dependency checks  #
######################

MISSING_DEPS=0
check_dep "curl"
check_dep "grep"
check_dep "sed"
check_dep "awk"
check_dep "wget"

HAS_THEHARVESTER=0
if command -v theHarvester >/dev/null 2>&1; then
  HAS_THEHARVESTER=1
fi

if [[ "${MISSING_DEPS}" -eq 1 ]]; then
  echo -e "${RED}[!] One or more required dependencies are missing. Please install them and retry.${RESET}"
  exit 1
fi

#########################
# Legal / scope reminder
#########################

echo -e "${YELLOW}[!] Ensure you have proper authorization for OSINT on this target."
echo -e "    Even passive recon can raise alarms if abused.${RESET}"
echo

######################
# Email regex        #
######################

EMAIL_REGEX='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,10}'

############################################
# 1) Website crawl + email extraction      #
############################################

echo -e "${BLUE}[+] Step 1/3: Website crawl and email extraction${RESET}"

CRAWL_DIR="${RAW_DIR}/site_crawl"
mkdir -p "${CRAWL_DIR}"

# Default to HTTPS; you can later add a toggle to switch to HTTP if needed
TARGET_URL="https://${TARGET_DOMAIN}"

echo
echo -e "${BLUE}[+] Select crawl mode for ${TARGET_URL}${RESET}"
echo "  1) Safe       (depth 1, 2s delay per request)"
echo "  2) Normal     (depth 2, 1s delay per request) [default]"
echo "  3) Aggressive (depth 3, 0.2s delay per request – lab only)"
echo
read -rp "Choose crawl mode [1-3, default 2]: " CRAWL_MODE

CRAWL_DEPTH=2
CRAWL_WAIT=1

case "${CRAWL_MODE:-2}" in
  1)
    CRAWL_DEPTH=1
    CRAWL_WAIT=2
    ;;
  3)
    CRAWL_DEPTH=3
    CRAWL_WAIT=0.2
    ;;
  *)
    CRAWL_DEPTH=2
    CRAWL_WAIT=1
    ;;
esac

echo
echo -e "${YELLOW}[!] Crawl configuration:${RESET}"
echo "    - Depth: ${CRAWL_DEPTH}"
echo "    - Wait between requests: ${CRAWL_WAIT}s"
echo "    - Target: ${TARGET_URL}"
echo
echo -e "${YELLOW}[!] Ensure you are allowed to crawl this target at this intensity.${RESET}"
echo -e "    Press Enter to continue or Ctrl+C to abort."
read -r _

wget \
  --quiet \
  --recursive \
  --level="${CRAWL_DEPTH}" \
  --wait="${CRAWL_WAIT}" \
  --timeout=10 \
  --no-parent \
  --user-agent="RedSpecter-EmailOSINT/${VERSION}" \
  --directory-prefix="${CRAWL_DIR}" \
  "${TARGET_URL}" || true

SITE_EMAILS_FILE="${RAW_DIR}/site_emails.txt"

if find "${CRAWL_DIR}" -type f 2>/dev/null | grep -q "."; then
  find "${CRAWL_DIR}" -type f -print0 \
    | xargs -0 grep -Eoi "${EMAIL_REGEX}" 2>/dev/null \
    | sed 's/["'\'']//g' \
    | dedupe > "${SITE_EMAILS_FILE}" || true
fi

SITE_EMAIL_COUNT=0
if [[ -f "${SITE_EMAILS_FILE}" ]]; then
  SITE_EMAIL_COUNT="$(wc -l < "${SITE_EMAILS_FILE}" | tr -d ' ')"
fi

echo -e "${GREEN}[+] Website crawl complete. Emails found: ${SITE_EMAIL_COUNT}${RESET}"
echo

############################################
# 2) crt.sh Certificate Transparency emails #
############################################

echo -e "${BLUE}[+] Step 2/3: crt.sh Certificate Transparency lookup${RESET}"

CRT_RAW_JSON="${RAW_DIR}/crtsh_${TARGET_DOMAIN}.json"
CRT_EMAILS_FILE="${RAW_DIR}/crtsh_emails.txt"

CRT_URL="https://crt.sh/?q=%25.${TARGET_DOMAIN}&output=json"

echo -e "${BLUE}[+] Querying: ${CRT_URL}${RESET}"
curl -s "${CRT_URL}" > "${CRT_RAW_JSON}" || true

if [[ -s "${CRT_RAW_JSON}" ]]; then
  grep -Eoi "${EMAIL_REGEX}" "${CRT_RAW_JSON}" 2>/dev/null \
    | dedupe > "${CRT_EMAILS_FILE}" || true
fi

CRT_EMAIL_COUNT=0
if [[ -f "${CRT_EMAILS_FILE}" ]]; then
  CRT_EMAIL_COUNT="$(wc -l < "${CRT_EMAILS_FILE}" | tr -d ' ')"
fi

echo -e "${GREEN}[+] crt.sh processing complete. Emails found: ${CRT_EMAIL_COUNT}${RESET}"
echo

############################################
# 3) Optional: theHarvester integration    #
############################################

HARVESTER_EMAILS_FILE="${RAW_DIR}/theharvester_emails.txt"
HARVESTER_RAW_FILE="${RAW_DIR}/theharvester_raw.txt"
HARVESTER_EMAIL_COUNT=0

if [[ "${HAS_THEHARVESTER}" -eq 1 ]]; then
  echo -e "${BLUE}[+] Step 3/3: theHarvester integration (optional)${RESET}"
  echo -e "${YELLOW}[!] theHarvester detected. Do you want to run it as an extra source? [y/N]${RESET}"
  read -r RUN_HARVESTER
  if [[ "${RUN_HARVESTER}" =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}[+] Running: theHarvester -d ${TARGET_DOMAIN} -b all${RESET}"
    theHarvester -d "${TARGET_DOMAIN}" -b all 2>/dev/null | tee "${HARVESTER_RAW_FILE}" || true

    if [[ -s "${HARVESTER_RAW_FILE}" ]]; then
      grep -Eoi "${EMAIL_REGEX}" "${HARVESTER_RAW_FILE}" 2>/dev/null \
        | dedupe > "${HARVESTER_EMAILS_FILE}" || true
    fi

    if [[ -f "${HARVESTER_EMAILS_FILE}" ]]; then
      HARVESTER_EMAIL_COUNT="$(wc -l < "${HARVESTER_EMAILS_FILE}" | tr -d ' ')"
    fi

    echo -e "${GREEN}[+] theHarvester emails found: ${HARVESTER_EMAIL_COUNT}${RESET}"
  else
    echo -e "${YELLOW}[!] Skipping theHarvester step.${RESET}"
  fi
  echo
else
  echo -e "${YELLOW}[!] theHarvester not installed. Skipping Step 3.${RESET}"
  echo
fi

############################################
# Combine & dedupe all sources             #
############################################

ALL_EMAILS_FILE="${RAW_DIR}/all_emails_combined.txt"

: > "${ALL_EMAILS_FILE}"
[[ -f "${SITE_EMAILS_FILE}" ]] && cat "${SITE_EMAILS_FILE}" >> "${ALL_EMAILS_FILE}"
[[ -f "${CRT_EMAILS_FILE}" ]] && cat "${CRT_EMAILS_FILE}" >> "${ALL_EMAILS_FILE}"
[[ -f "${HARVESTER_EMAILS_FILE}" ]] && cat "${HARVESTER_EMAILS_FILE}" >> "${ALL_EMAILS_FILE}"

ALL_EMAIL_COUNT=0
if [[ -s "${ALL_EMAILS_FILE}" ]]; then
  dedupe < "${ALL_EMAILS_FILE}" > "${ALL_EMAILS_FILE}.tmp"
  mv "${ALL_EMAILS_FILE}.tmp" "${ALL_EMAILS_FILE}"
  ALL_EMAIL_COUNT="$(wc -l < "${ALL_EMAILS_FILE}" | tr -d ' ')"
fi

echo -e "${GREEN}[+] Total unique emails across all sources: ${ALL_EMAIL_COUNT}${RESET}"
echo

############################################
# Categorise first-party vs third-party    #
############################################

FIRST_PARTY_FILE="${RAW_DIR}/first_party_emails.txt"
THIRD_PARTY_FILE="${RAW_DIR}/third_party_emails.txt"

: > "${FIRST_PARTY_FILE}"
: > "${THIRD_PARTY_FILE}"

if [[ -s "${ALL_EMAILS_FILE}" ]]; then
  TARGET_DOMAIN_LOWER="$(printf '%s\n' "${TARGET_DOMAIN}" | tr 'A-Z' 'a-z')"

  while IFS= read -r email; do
    clean_email="$(printf '%s\n' "${email}" | tr -d '[:space:]')"
    [[ -z "${clean_email}" ]] && continue

    email_domain="$(printf '%s\n' "${clean_email}" | awk -F'@' '{print tolower($2)}')"

    # First-party if the email domain is exactly the target domain or a subdomain of it
    if [[ "${email_domain}" == "${TARGET_DOMAIN_LOWER}" || "${email_domain}" == *".${TARGET_DOMAIN_LOWER}" ]]; then
      echo "${clean_email}" >> "${FIRST_PARTY_FILE}"
    else
      echo "${clean_email}" >> "${THIRD_PARTY_FILE}"
    fi
  done < "${ALL_EMAILS_FILE}"

  [[ -s "${FIRST_PARTY_FILE}" ]] && dedupe < "${FIRST_PARTY_FILE}" > "${FIRST_PARTY_FILE}.tmp" && mv "${FIRST_PARTY_FILE}.tmp" "${FIRST_PARTY_FILE}"
  [[ -s "${THIRD_PARTY_FILE}" ]] && dedupe < "${THIRD_PARTY_FILE}" > "${THIRD_PARTY_FILE}.tmp" && mv "${THIRD_PARTY_FILE}.tmp" "${THIRD_PARTY_FILE}"
fi

FIRST_PARTY_COUNT=0
THIRD_PARTY_COUNT=0
[[ -f "${FIRST_PARTY_FILE}" ]] && FIRST_PARTY_COUNT="$(wc -l < "${FIRST_PARTY_FILE}" | tr -d ' ')"
[[ -f "${THIRD_PARTY_FILE}" ]] && THIRD_PARTY_COUNT="$(wc -l < "${THIRD_PARTY_FILE}" | tr -d ' ')"

############################################
# Write Markdown report                    #
############################################

echo -e "${BLUE}[+] Writing Markdown report: ${REPORT_MD}${RESET}"

{
  echo "# Red Specter Email OSINT Report"
  echo
  echo "- Target domain: \`${TARGET_DOMAIN}\`"
  echo "- Timestamp: \`${TIMESTAMP}\`"
  echo "- Module version: \`${VERSION}\`"
  echo
  echo "## Summary"
  echo
  echo "- Total unique emails: **${ALL_EMAIL_COUNT}**"
  echo "- First-party emails (matching ${TARGET_DOMAIN}): **${FIRST_PARTY_COUNT}**"
  echo "- Third-party emails: **${THIRD_PARTY_COUNT}**"
  echo
  echo "## First-party Emails"
  echo
  if [[ "${FIRST_PARTY_COUNT}" -gt 0 ]]; then
    echo '```text'
    cat "${FIRST_PARTY_FILE}"
    echo '```'
  else
    echo "_None found._"
  fi
  echo
  echo "## Third-party Emails"
  echo
  if [[ "${THIRD_PARTY_COUNT}" -gt 0 ]]; then
    echo '```text'
    cat "${THIRD_PARTY_FILE}"
    echo '```'
  else
    echo "_None found._"
  fi
  echo
  echo "## Source Breakdown"
  echo
  echo "- Website crawl emails: **${SITE_EMAIL_COUNT}** (raw: \`${SITE_EMAILS_FILE}\`)"
  echo "- crt.sh emails: **${CRT_EMAIL_COUNT}** (raw: \`${CRT_EMAILS_FILE}\`)"
  if [[ "${HAS_THEHARVESTER}" -eq 1 ]]; then
    echo "- theHarvester emails: **${HARVESTER_EMAIL_COUNT}** (raw: \`${HARVESTER_EMAILS_FILE}\`)"
  else
    echo "- theHarvester: _not installed or not run_"
  fi
  echo
  echo "## Notes"
  echo
  echo "- This data is gathered from public sources only (website content, Certificate Transparency logs, optional theHarvester)."
  echo "- Treat all findings as unverified until manually confirmed."
  echo "- Use responsibly under your defined Rules of Engagement (ROE)."
} > "${REPORT_MD}"

echo
echo -e "${GREEN}[+] Done. Report written to: ${REPORT_MD}${RESET}"
echo -e "${GREEN}[+] Raw artefacts in: ${RAW_DIR}${RESET}"
echo
