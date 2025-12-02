#!/usr/bin/env bash
#
# Red Specter – ADV Vulnerability Scanner (AGGRESSIVE) v1.0
# File: adv/adv-vulnscan/redspecter-vulnscan-adv.sh
#
# AGGRESSIVE vulnerability scanning wrapper:
# - Nmap full-port vuln scan
# - Nuclei (medium/high/critical) against HTTP targets
# - Optional Nikto on HTTP targets
#
# WARNING:
#   This module is AGGRESSIVE and should ONLY be used:
#     • In your own lab, OR
#     • With explicit written Rules of Engagement (ROE) from the client
#

set -euo pipefail

VERSION="1.0"

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
 RED SPECTER - ADV VULN SCAN (AGGRESSIVE)
===========================================

AGGRESSIVE vulnerability scanning wrapper.

Usage:
  $(basename "$0") -t <tag> (-f <targets_file> | -i <ip/host> | -u <url>)

Options:
  -t, --tag TAG         Run label (e.g. client name, LAB-TEST-01) [required]
  -f, --file FILE       File with targets (IP/host/URL, one per line)
  -i, --ip HOST         Single IP/host target
  -u, --url URL         Single URL target (http/https)
  --nmap-only           Run only Nmap vuln scanning (skip nuclei/nikto)
  --safe                Use toned-down Nmap profile (NOT recommended here)
  -h, --help            Show this help

Examples:
  $(basename "$0") -t LAB-NMAP -i 192.168.56.10
  $(basename "$0") -t CLIENT-ROE -f scope_hosts.txt
  $(basename "$0") -t LAB-WEB -u https://lab.target.local

If no options are provided, interactive mode will prompt for tag and targets.

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
  echo "${YELLOW}${BOLD}ROE / AUTHORIZATION CHECK (ADV VULN SCAN – AGGRESSIVE)${RESET}"
  echo "${YELLOW}Only use this tool where you have:${RESET}"
  echo "${YELLOW}  • Full control (your own lab), OR${RESET}"
  echo "${YELLOW}  • Explicit written ROE from the client covering aggressive scanning.${RESET}"
  echo
  read -r -p "Do you confirm you are authorised to perform AGGRESSIVE scanning? (yes/no): " ans
  case "$ans" in
    yes|y|Y)
      echo "${GREEN}[+] Authorization confirmed.${RESET}"
      ;;
    *)
      echo "${RED}[!] Authorization not confirmed. Aborting.${RESET}"
      exit 1
      ;;
  esac
}

aggressive_ack_prompt() {
  echo
  echo "${RED}${BOLD}!!! AGGRESSIVE SCANNING WARNING !!!${RESET}"
  echo "${RED}This module can:${RESET}"
  echo "${RED}  • Trigger IDS/IPS/WAF alerts${RESET}"
  echo "${RED}  • Generate significant traffic${RESET}"
  echo "${RED}  • Hit many ports and endpoints${RESET}"
  echo
  echo "${YELLOW}If this is NOT your own lab or NOT explicitly authorised, STOP NOW.${RESET}"
  echo
  local phrase="I UNDERSTAND THIS IS AGGRESSIVE"
  echo "To continue, type the following phrase exactly:"
  echo "  ${BOLD}${phrase}${RESET}"
  echo
  read -r -p "> " typed
  if [[ "$typed" != "$phrase" ]]; then
    echo
    echo "${RED}[!] Phrase mismatch. Aborting aggressive scan.${RESET}"
    exit 1
  fi
  echo
  echo "${GREEN}[+] Aggressive scanning acknowledged. Proceeding...${RESET}"
  echo
}

banner() {
  echo
  echo "${RED}${BOLD}===========================================${RESET}"
  echo "${RED}${BOLD}  RED SPECTER - ADV VULN SCAN (AGGR) v${VERSION}${RESET}"
  echo "${RED}${BOLD}===========================================${RESET}"
  echo
  echo "${YELLOW}AGGRESSIVE vulnerability scanning module.${RESET}"
  echo "${YELLOW}Use ONLY in lab or with explicit written ROE.${RESET}"
  echo
}

# ---------- Nmap Profiles ----------
build_nmap_cmd() {
  local target_file="$1"
  local out_dir="$2"
  local mode="$3"   # aggressive | safe

  case "$mode" in
    aggressive)
      # Heavy profile: full TCP ports, default+safety+vuln scripts
      echo "nmap -Pn -sV -sC --script=vuln,default,safe -p- --reason --open -iL \"$target_file\" -oN \"$out_dir/nmap_aggressive.txt\""
      ;;
    safe)
      # Toned-down profile: top ports + vuln scripts
      echo "nmap -Pn -sV --top-ports 2000 --script=vuln,default,safe -iL \"$target_file\" -oN \"$out_dir/nmap_safe.txt\""
      ;;
    *)
      echo "nmap -Pn -sV -sC --script=vuln,default,safe -p- --reason --open -iL \"$target_file\" -oN \"$out_dir/nmap_aggressive.txt\""
      ;;
  esac
}

build_nuclei_cmd() {
  local http_targets="$1"
  local out_file="$2"
  # Aggressive nuclei profile: medium+ severity, decent concurrency
  echo "nuclei -l \"$http_targets\" -severity medium,high,critical -c 50 -o \"$out_file\""
}

build_nikto_cmd() {
  local url="$1"
  local out_file="$2"
  echo "nikto -host \"$url\" -output \"$out_file\""
}

# ---------- Main ----------
main() {
  local TAG=""
  local TARGET_FILE=""
  local SINGLE_IP=""
  local SINGLE_URL=""
  local NMAP_ONLY="false"
  local PROFILE="aggressive"   # aggressive | safe

  # If no args → interactive mode
  if [[ $# -eq 0 ]]; then
    banner
    echo "${BLUE}[i] No arguments supplied — entering interactive mode.${RESET}"
    echo
    read -rp "Enter run tag/label (e.g. LAB-TEST-01 or CLIENT-ROE): " TAG
    if [[ -z "$TAG" ]]; then
      echo "${RED}[!] Tag/label is required.${RESET}"
      exit 1
    fi
    echo
    echo "Choose target input method:"
    echo "  1) Single IP/host"
    echo "  2) Single URL (http/https)"
    echo "  3) File with targets"
    echo
    read -rp "Selection: " choice
    case "$choice" in
      1)
        read -rp "Enter IP/host: " SINGLE_IP
        ;;
      2)
        read -rp "Enter URL: " SINGLE_URL
        ;;
      3)
        read -rp "Enter path to targets file: " TARGET_FILE
        ;;
      *)
        echo "${RED}[!] Invalid selection.${RESET}"
        exit 1
        ;;
    esac
  else
    # Parse args
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -t|--tag)
          TAG="${2:-}"
          shift 2
          ;;
        -f|--file)
          TARGET_FILE="${2:-}"
          shift 2
          ;;
        -i|--ip)
          SINGLE_IP="${2:-}"
          shift 2
          ;;
        -u|--url)
          SINGLE_URL="${2:-}"
          shift 2
          ;;
        --nmap-only)
          NMAP_ONLY="true"
          shift
          ;;
        --safe)
          PROFILE="safe"
          shift
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

  if [[ -z "$TAG" ]]; then
    echo "${RED}[!] Tag/label is required (-t / --tag).${RESET}"
    usage
    exit 1
  fi

  # Validate target input
  local TARGETS_TMP
  TARGETS_TMP="$(mktemp)"
  if [[ -n "$TARGET_FILE" ]]; then
    if [[ ! -f "$TARGET_FILE" ]]; then
      echo "${RED}[!] Target file not found: $TARGET_FILE${RESET}"
      exit 1
    fi
    while IFS= read -r line; do
      line="$(echo "$line" | xargs || true)"
      [[ -z "$line" ]] && continue
      echo "$line" >> "$TARGETS_TMP"
    done < "$TARGET_FILE"
  fi

  if [[ -n "$SINGLE_IP" ]]; then
    echo "$SINGLE_IP" >> "$TARGETS_TMP"
  fi

  if [[ -n "$SINGLE_URL" ]]; then
    echo "$SINGLE_URL" >> "$TARGETS_TMP"
  fi

  if [[ ! -s "$TARGETS_TMP" ]]; then
    echo "${RED}[!] No valid targets provided.${RESET}"
    rm -f "$TARGETS_TMP"
    usage
    exit 1
  fi

  # Normalise & dedupe targets
  sort -u "$TARGETS_TMP" -o "$TARGETS_TMP"

  banner
  authorization_prompt
  aggressive_ack_prompt

  # Dependency checks
  echo "${BLUE}[i] Checking tools for aggressive vuln scanning...${RESET}"
  local HAVE_NMAP="false"
  local HAVE_NUCLEI="false"
  local HAVE_NIKTO="false"

  if check_binary nmap; then
    HAVE_NMAP="true"; echo "${GREEN}[+] nmap found.${RESET}"
  else
    echo "${RED}[!] nmap is required for this module.${RESET}"
    exit 1
  fi

  if check_binary nuclei; then
    HAVE_NUCLEI="true"; echo "${GREEN}[+] nuclei found.${RESET}"
  else
    echo "${YELLOW}[-] nuclei not found. HTTP template scanning will be skipped.${RESET}"
  fi

  if check_binary nikto; then
    HAVE_NIKTO="true"; echo "${GREEN}[+] nikto found.${RESET}"
  else
    echo "${YELLOW}[-] nikto not found. Deep HTTP vulnerability checks (Nikto) will be skipped.${RESET}"
  fi

  # Prepare directories
  mkdir -p "${REPORT_DIR}"
  local ts
  ts="$(date +'%Y%m%d_%H%M%S')"

  local safe_tag
  safe_tag="$(echo "$TAG" | sed 's/[^A-Za-z0-9._-]/_/g')"

  local RUN_DIR="${REPORT_DIR}/adv-vulnscan_${safe_tag}_${PROFILE}_${ts}"
  mkdir -p "${RUN_DIR}"/{raw,lists,summary}

  echo
  echo "${GREEN}[+] Run directory: ${RUN_DIR}${RESET}"
  echo

  local HOSTS_FILE="${RUN_DIR}/lists/targets_all.txt"
  local HOSTS_ONLY="${RUN_DIR}/lists/targets_hosts.txt"
  local HTTP_TARGETS="${RUN_DIR}/lists/targets_http.txt"
  local NMAP_OUT_DIR="${RUN_DIR}/raw/nmap"
  local NUCLEI_OUT="${RUN_DIR}/raw/nuclei.txt"
  local NIKTO_DIR="${RUN_DIR}/raw/nikto"
  local SUMMARY_MD="${RUN_DIR}/summary/ADV_VulnScan_Summary_${safe_tag}.md"

  mkdir -p "$NMAP_OUT_DIR" "$NIKTO_DIR"
  cp "$TARGETS_TMP" "$HOSTS_FILE"

  # Split targets into hosts vs URLs for different scanners
  > "$HOSTS_ONLY"
  > "$HTTP_TARGETS"
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    if [[ "$t" =~ ^https?:// ]]; then
      echo "$t" >> "$HTTP_TARGETS"
      # Also extract host portion for Nmap
      host_part="$(echo "$t" | sed -E 's#https?://([^/]+)/?.*#\1#')"
      echo "$host_part" >> "$HOSTS_ONLY"
    else
      echo "$t" >> "$HOSTS_ONLY"
      # we can also synthesise http/https URLs for nuclei/Nikto
      echo "http://$t" >> "$HTTP_TARGETS"
      echo "https://$t" >> "$HTTP_TARGETS"
    fi
  done < "$HOSTS_FILE"

  sort -u "$HOSTS_ONLY" -o "$HOSTS_ONLY"
  sort -u "$HTTP_TARGETS" -o "$HTTP_TARGETS"

  echo "${BLUE}[i] Hosts for Nmap: $(wc -l < "$HOSTS_ONLY" | xargs)${RESET}"
  echo "${BLUE}[i] HTTP targets for nuclei/Nikto: $(wc -l < "$HTTP_TARGETS" | xargs)${RESET}"

  # ---------- Stage 1: Nmap aggressive vuln scanning ----------
  echo
  echo "${BLUE}[i] Stage 1: Nmap vulnerability scanning (${PROFILE} profile)${RESET}"

  if [[ -s "$HOSTS_ONLY" ]]; then
    local nmap_cmd
    nmap_cmd="$(build_nmap_cmd "$HOSTS_ONLY" "$NMAP_OUT_DIR" "$PROFILE")"
    echo "${BLUE}[i] Running Nmap with command:${RESET}"
    echo "    $nmap_cmd"
    echo
    eval "$nmap_cmd" || true
  else
    echo "${YELLOW}[-] No host targets for Nmap.${RESET}"
  fi

  # ---------- Stage 2: Nuclei scanning (if available and not nmap-only) ----------
  echo
  echo "${BLUE}[i] Stage 2: Nuclei HTTP template scanning${RESET}"

  if [[ "$NMAP_ONLY" == "true" ]]; then
    echo "${YELLOW}[-] Nmap-only mode enabled. Skipping nuclei and Nikto.${RESET}"
  else
    if [[ "$HAVE_NUCLEI" == "true" && -s "$HTTP_TARGETS" ]]; then
      local nuclei_cmd
      nuclei_cmd="$(build_nuclei_cmd "$HTTP_TARGETS" "$NUCLEI_OUT")"
      echo "${BLUE}[i] Running nuclei with command:${RESET}"
      echo "    $nuclei_cmd"
      echo
      eval "$nuclei_cmd" || true
    else
      if [[ "$HAVE_NUCLEI" != "true" ]]; then
        echo "${YELLOW}[-] nuclei not found. Skipping nuclei stage.${RESET}"
      fi
      if [[ ! -s "$HTTP_TARGETS" ]]; then
        echo "${YELLOW}[-] No HTTP targets available for nuclei.${RESET}"
      fi
    fi

    # ---------- Stage 3: Nikto scanning (optional) ----------
    echo
    echo "${BLUE}[i] Stage 3: Nikto deep HTTP checks (if available)${RESET}"

    if [[ "$HAVE_NIKTO" == "true" && -s "$HTTP_TARGETS" ]]; then
      while IFS= read -r url; do
        [[ -z "$url" ]] && continue
        local safe_url
        safe_url="$(echo "$url" | sed 's#[^A-Za-z0-9._-]#_#g')"
        local out_file="${NIKTO_DIR}/${safe_url}_nikto.txt"
        local nikto_cmd
        nikto_cmd="$(build_nikto_cmd "$url" "$out_file")"
        echo "${BLUE}[i] Running Nikto against: ${url}${RESET}"
        eval "$nikto_cmd" || true
      done < "$HTTP_TARGETS"
    else
      if [[ "$HAVE_NIKTO" != "true" ]]; then
        echo "${YELLOW}[-] Nikto not found. Skipping Nikto stage.${RESET}"
      fi
      if [[ ! -s "$HTTP_TARGETS" ]]; then
        echo "${YELLOW}[-] No HTTP targets available for Nikto.${RESET}"
      fi
    fi
  fi

  # ---------- Stage 4: Markdown summary ----------
  echo
  echo "${BLUE}[i] Stage 4: Generating Markdown summary${RESET}"

  # Simple stats
  local nmap_files=0
  local nuclei_findings=0
  local nikto_files=0

  if [[ -d "$NMAP_OUT_DIR" ]]; then
    nmap_files="$(find "$NMAP_OUT_DIR" -type f -name '*.txt' | wc -l | xargs || echo 0)"
  fi

  if [[ -s "$NUCLEI_OUT" ]]; then
    nuclei_findings="$(wc -l < "$NUCLEI_OUT" | xargs || echo 0)"
  fi

  if [[ -d "$NIKTO_DIR" ]]; then
    nikto_files="$(find "$NIKTO_DIR" -type f -name '*.txt' | wc -l | xargs || echo 0)"
  fi

  {
    echo "# Red Specter – ADV Vulnerability Scan (AGGRESSIVE) Summary"
    echo
    echo "- **Date:** $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "- **Tag/Run:** \`${TAG}\`"
    echo "- **Profile:** \`${PROFILE}\` (this module is AGGRESSIVE by design)"
    echo "- **Module:** ADV Vulnerability Scanner v${VERSION}"
    echo
    echo "## Targets"
    echo
    echo "- Total input targets: $(wc -l < "$HOSTS_FILE" | xargs)"
    echo "- Host targets (Nmap): $(wc -l < "$HOSTS_ONLY" | xargs)"
    echo "- HTTP targets (Nuclei/Nikto): $(wc -l < "$HTTP_TARGETS" | xargs)"
    echo
    echo "## Scanner Outputs"
    echo
    echo "- Nmap output directory: \`$(basename "$NMAP_OUT_DIR")\` (files: ${nmap_files})"
    if [[ "$NMAP_ONLY" != "true" ]]; then
      if [[ -s "$NUCLEI_OUT" ]]; then
        echo "- Nuclei findings: ${nuclei_findings} lines in \`$(basename "$NUCLEI_OUT")\`"
      else
        echo "- Nuclei findings: 0 (file empty or not created)"
      fi
      echo "- Nikto output directory: \`$(basename "$NIKTO_DIR")\` (files: ${nikto_files})"
    else
      echo "- Nuclei/Nikto: Skipped (nmap-only mode)"
    fi
    echo
    echo "## Important Notes"
    echo
    echo "- This module is AGGRESSIVE and likely to appear in logs and alerts."
    echo "- All findings are *potential* until manually verified."
    echo "- Wherever possible, corroborate:"
    echo "  - Nmap vuln scripts vs. manual checks"
    echo "  - Nuclei findings vs. direct HTTP interaction"
    echo "  - Nikto findings vs. actual business impact"
    echo
    echo "## Suggested Next Steps"
    echo
    echo "- Prioritise critical/remote findings for manual validation."
    echo "- Use output to populate your Genesis workbook / Red Specter reports."
    echo "- For client work, ensure findings align with the agreed ROE and scope."
    echo
    echo "> Generated by Red Specter ADV Vulnerability Scanner (AGGRESSIVE) v${VERSION}."
  } > "$SUMMARY_MD"

  rm -f "$TARGETS_TMP"

  echo
  echo "${GREEN}[+] ADV Vulnerability Scan completed.${RESET}"
  echo "${GREEN}[+] Summary report: ${SUMMARY_MD}${RESET}"
  echo
}

main "$@"
