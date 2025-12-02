#!/usr/bin/env bash
#
# Red Specter – Vulnerability Scanner v1.0
# File: redspecter-vulnscan.sh
#
# Safe-by-default vuln scanning wrapper around Nmap (+ optional Nikto, Nuclei).
# Author: Richard (Red Specter) + Vigil (AI Co-Intelligence)
#
# Usage:
#   ./redspecter-vulnscan.sh -t target.com
#   ./redspecter-vulnscan.sh -f targets.txt -o reports/
#

set -euo pipefail

VERSION="1.0"

# ---------- Colors ----------
RED="$(tput setaf 1 2>/dev/null || true)"
GREEN="$(tput setaf 2 2>/dev/null || true)"
YELLOW="$(tput setaf 3 2>/dev/null || true)"
BLUE="$(tput setaf 4 2>/devnull || true)"
BOLD="$(tput bold 2>/dev/null || true)"
RESET="$(tput sgr0 2>/dev/null || true)"

# ---------- Banner ----------
banner() {
  echo
  echo "${RED}${BOLD}==============================================${RESET}"
  echo "${RED}${BOLD}   Red Specter – Vulnerability Scanner v${VERSION}${RESET}"
  echo "${RED}${BOLD}==============================================${RESET}"
  echo "${YELLOW}Safe, RoE-compliant vulnerability enumeration wrapper.${RESET}"
  echo
}

# ---------- Usage ----------
usage() {
  cat <<EOF
Usage:
  $0 -t <target> | -f <targets_file> [options]

Required (choose one):
  -t, --target        Single target (IP/domain/URL)
  -f, --file          File with one target per line

Options:
  -o, --output DIR    Output directory (default: ./reports)
  -m, --notes TEXT    Freeform run notes to embed in report
  --quick             Faster, lighter scan profile
  --full              Deeper Nmap scan (still safe-only by default)
  --no-nikto          Disable Nikto (even if installed)
  --no-nuclei         Disable Nuclei (even if installed)
  --assume-authorized Skip authorization prompt (use in scripted/CI mode)
  -h, --help          Show this help

Examples:
  $0 -t 192.168.1.10
  $0 -f in-scope.txt -o ./clientA-reports
  $0 -t https://app.client.com --full --no-nikto

Notes:
  • This script is SAFE-BY-DEFAULT. It avoids exploit modules.
  • Nmap is required. Nikto and Nuclei are optional enhancements.
EOF
}

# ---------- Global defaults ----------
TARGET=""
TARGET_FILE=""
OUTPUT_DIR="./reports"
RUN_NOTES=""
PROFILE="quick"   # quick | full
ASSUME_AUTH="false"
ENABLE_NIKTO="true"
ENABLE_NUCLEI="true"

# ---------- Arg parsing ----------
if [[ $# -eq 0 ]]; then
  usage
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--target)
      TARGET="${2:-}"
      shift 2
      ;;
    -f|--file)
      TARGET_FILE="${2:-}"
      shift 2
      ;;
    -o|--output)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    -m|--notes)
      RUN_NOTES="${2:-}"
      shift 2
      ;;
    --quick)
      PROFILE="quick"
      shift
      ;;
    --full)
      PROFILE="full"
      shift
      ;;
    --no-nikto)
      ENABLE_NIKTO="false"
      shift
      ;;
    --no-nuclei)
      ENABLE_NUCLEI="false"
      shift
      ;;
    --assume-authorized)
      ASSUME_AUTH="true"
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

# ---------- Validate target input ----------
if [[ -z "$TARGET" && -z "$TARGET_FILE" ]]; then
  echo "${RED}[!] You must specify either -t <target> or -f <targets_file>.${RESET}"
  usage
  exit 1
fi

if [[ -n "$TARGET_FILE" && ! -f "$TARGET_FILE" ]]; then
  echo "${RED}[!] Target file not found: $TARGET_FILE${RESET}"
  exit 1
fi

# ---------- Authorization reminder ----------
authorization_prompt() {
  echo
  echo "${YELLOW}${BOLD}ROE / AUTHORIZATION CHECK${RESET}"
  echo "${YELLOW}Only use this tool on systems where you have explicit, written permission.${RESET}"
  echo
  read -r -p "Do you confirm you are authorized to scan ALL specified targets? (yes/no): " answer
  case "$answer" in
    yes|y|Y)
      echo "${GREEN}[+] Authorization confirmed. Continuing...${RESET}"
      ;;
    *)
      echo "${RED}[!] Authorization not confirmed. Aborting.${RESET}"
      exit 1
      ;;
  esac
}

# ---------- Dependency checks ----------
check_binary() {
  local bin="$1"
  if command -v "$bin" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

dependency_check() {
  echo
  echo "${BLUE}[i] Checking dependencies...${RESET}"

  if ! check_binary nmap; then
    echo "${RED}[!] nmap is required but not found in PATH.${RESET}"
    echo "    Install it (e.g. apt install nmap) and re-run."
    exit 1
  fi
  echo "${GREEN}[+] nmap found.${RESET}"

  if [[ "$ENABLE_NIKTO" == "true" ]]; then
    if check_binary nikto; then
      echo "${GREEN}[+] nikto found.${RESET}"
    else
      echo "${YELLOW}[-] nikto not found. Nikto scanning will be skipped.${RESET}"
      ENABLE_NIKTO="false"
    fi
  fi

  if [[ "$ENABLE_NUCLEI" == "true" ]]; then
    if check_binary nuclei; then
      echo "${GREEN}[+] nuclei found.${RESET}"
    else
      echo "${YELLOW}[-] nuclei not found. Nuclei scanning will be skipped.${RESET}"
      ENABLE_NUCLEI="false"
    fi
  fi
}

# ---------- Helper: determine HTTP-ish target ----------
is_http_like() {
  local t="$1"
  if [[ "$t" =~ ^https?:// ]]; then
    return 0
  fi
  if [[ "$t" =~ :80$ || "$t" =~ :443$ ]]; then
    return 0
  fi
  return 1
}

# ---------- Scan profiles ----------
build_nmap_cmd() {
  local target="$1"
  local profile="$2"
  local out_file="$3"

  # Safe-by-default profiles.
  #
  # quick:  version detection + default + safe scripts, limited ports
  # full:   more ports + vuln scripts (still not exploit modules)
  #
  case "$profile" in
    quick)
      echo "nmap -Pn -sV --top-ports 1000 --script=safe,default -oN \"$out_file\" \"$target\""
      ;;
    full)
      echo "nmap -Pn -sV -sC --script=safe,default,vuln -p- -oN \"$out_file\" \"$target\""
      ;;
    *)
      echo "nmap -Pn -sV --top-ports 1000 --script=safe,default -oN \"$out_file\" \"$target\""
      ;;
  esac
}

build_nikto_cmd() {
  local url="$1"
  local out_file="$2"
  echo "nikto -host \"$url\" -output \"$out_file\""
}

build_nuclei_cmd() {
  local target="$1"
  local out_file="$2"

  # Basic nuclei run. You can later tune with -severity or -tags.
  echo "nuclei -u \"$target\" -o \"$out_file\""
}

# ---------- Main work ----------
main() {
  banner

  if [[ "$ASSUME_AUTH" != "true" ]]; then
    authorization_prompt
  fi

  dependency_check

  local ts
  ts="$(date +'%Y%m%d_%H%M%S')"
  local run_dir="${OUTPUT_DIR}/redspecter-vulnscan_${ts}"
  mkdir -p "$run_dir"/{raw,nmap,nikto,nuclei}

  local summary_md="${run_dir}/RedSpecter_VulnScan_Report_${ts}.md"

  echo "${GREEN}[+] Output directory: ${run_dir}${RESET}"
  echo

  # Build target list
  local targets=()
  if [[ -n "$TARGET" ]]; then
    targets+=("$TARGET")
  fi
  if [[ -n "$TARGET_FILE" ]]; then
    while IFS= read -r line; do
      line="${line%%#*}"       # strip comments after #
      line="$(echo "$line" | xargs || true)" # trim
      [[ -z "$line" ]] && continue
      targets+=("$line")
    done < "$TARGET_FILE"
  fi

  if [[ ${#targets[@]} -eq 0 ]]; then
    echo "${RED}[!] No valid targets resolved after reading input.${RESET}"
    exit 1
  fi

  echo "${BLUE}[i] Targets to scan: ${#targets[@]}${RESET}"
  for t in "${targets[@]}"; do
    echo "  - $t"
  done
  echo

  # ---------- Initialize Markdown report ----------
  {
    echo "# Red Specter – Vulnerability Scan Report"
    echo
    echo "- **Date:** $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "- **Tool:** Red Specter Vulnerability Scanner v${VERSION}"
    echo "- **Profile:** ${PROFILE}"
    if [[ -n "$RUN_NOTES" ]]; then
      echo "- **Operator Notes:** ${RUN_NOTES}"
    fi
    echo
    echo "## Targets"
    echo
    for t in "${targets[@]}"; do
      echo "- \`$t\`"
    done
    echo
    echo "## Summary Table"
    echo
    echo "| Target | Scanner | Issues Summary | Raw Output |"
    echo "|--------|---------|----------------|------------|"
  } > "$summary_md"

  # ---------- Scan loop ----------
  for target in "${targets[@]}"; do
    echo "${BOLD}${BLUE}[*] Scanning target: ${target}${RESET}"

    # Sanitize filename
    local safe_name
    safe_name="$(echo "$target" | sed 's|[^A-Za-z0-9._-]|_|g')"

    # Nmap
    local nmap_out="${run_dir}/nmap/${safe_name}_nmap.txt"
    local nmap_cmd
    nmap_cmd="$(build_nmap_cmd "$target" "$PROFILE" "$nmap_out")"

    echo "${BLUE}[i] Running Nmap: ${nmap_cmd}${RESET}"
    eval "$nmap_cmd" || true

    # Grab a tiny summary from Nmap
    local nmap_summary="(see raw output)"
    if grep -q "VULNERABLE" "$nmap_out" 2>/dev/null; then
      local count
      count="$(grep -c "VULNERABLE" "$nmap_out" || echo 0)"
      nmap_summary="Potentially vulnerable services: ${count} (grep 'VULNERABLE')"
    fi

    # Append to summary table – Nmap
    {
      echo "| \`$target\` | Nmap | ${nmap_summary} | [link](./nmap/$(basename "$nmap_out")) |"
    } >> "$summary_md"

    # Web-specific tools (if target looks HTTP-ish)
    if is_http_like "$target"; then

      # Nikto
      if [[ "$ENABLE_NIKTO" == "true" ]]; then
        local nikto_out="${run_dir}/nikto/${safe_name}_nikto.txt"
        local nikto_cmd
        nikto_cmd="$(build_nikto_cmd "$target" "$nikto_out")"

        echo "${BLUE}[i] Running Nikto: ${nikto_cmd}${RESET}"
        eval "$nikto_cmd" || true

        local nikto_summary="(see raw output)"
        # Simple heuristic: count "OSVDB-" or "Server leaks" lines
        if grep -q "OSVDB-" "$nikto_out" 2>/dev/null; then
          local n
          n="$(grep -c "OSVDB-" "$nikto_out" || echo 0)"
          nikto_summary="Nikto findings: ${n} (OSVDB entries)"
        fi

        {
          echo "| \`$target\` | Nikto | ${nikto_summary} | [link](./nikto/$(basename "$nikto_out")) |"
        } >> "$summary_md"
      else
        echo "${YELLOW}[-] Nikto disabled or not installed. Skipping for ${target}.${RESET}"
      fi

      # Nuclei
      if [[ "$ENABLE_NUCLEI" == "true" ]]; then
        local nuclei_out="${run_dir}/nuclei/${safe_name}_nuclei.txt"
        local nuclei_cmd
        nuclei_cmd="$(build_nuclei_cmd "$target" "$nuclei_out")"

        echo "${BLUE}[i] Running Nuclei: ${nuclei_cmd}${RESET}"
        eval "$nuclei_cmd" || true

        local nuclei_summary="No findings (or see raw output)"
        if [[ -s "$nuclei_out" ]]; then
          local total
          total="$(wc -l < "$nuclei_out" | xargs)"
          nuclei_summary="Templates matched: ${total} (see raw output)"
        fi

        {
          echo "| \`$target\` | Nuclei | ${nuclei_summary} | [link](./nuclei/$(basename "$nuclei_out")) |"
        } >> "$summary_md"
      else
        echo "${YELLOW}[-] Nuclei disabled or not installed. Skipping for ${target}.${RESET}"
      fi

    else
      echo "${YELLOW}[i] Target does not look HTTP-like; skipping Nikto/Nuclei for ${target}.${RESET}"
    fi

    echo
  done

  # ---------- Closing notes in report ----------
  {
    echo
    echo "## Notes & Next Steps"
    echo
    echo "- Review Nmap outputs for services marked **VULNERABLE**."
    echo "- For HTTP targets, cross-check Nikto and Nuclei results."
    echo "- Treat all findings as *potential* until manually verified."
    echo
    echo "> This report was generated by Red Specter Vulnerability Scanner v${VERSION}."
  } >> "$summary_md"

  echo "${GREEN}[+] Scan complete.${RESET}"
  echo "${GREEN}[+] Markdown report: ${summary_md}${RESET}"
  echo
  echo "${YELLOW}Reminder:${RESET} All findings are *indicative* only. Verify manually before reporting to a client."
}

main "$@"
