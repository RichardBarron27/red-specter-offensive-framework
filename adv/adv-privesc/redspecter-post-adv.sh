#!/usr/bin/env bash
#
# Red Specter – ADV PrivEsc / Post-Ex Helper v1.0
# File: adv/adv-privesc/redspecter-post-adv.sh
#
# Privilege escalation & post-exploitation PLANNING helper:
# - Does NOT run exploits
# - Helps structure local enumeration & privesc notes
# - Suggests commands (linpeas, winpeas, pspy, manual checks)
#
# ROE: Only for use on lab systems or targets with explicit written permission
#      for post-exploitation / privilege escalation attempts.
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
 RED SPECTER - ADV PRIVESC / POST-EX v${VERSION}
===========================================

Privilege escalation & post-exploitation PLANNING helper.

Usage:
  $(basename "$0") -t <tag> -H <host> -o <os> -u <user> [-a <access>]

Options:
  -t, --tag TAG        Run label (e.g. CLIENT-LINUX-01, LAB-WIN-BOX)
  -H, --host HOST      Target host/IP or hostname
  -o, --os OS          Target OS (linux/windows/other)
  -u, --user USER      Current user (e.g. www-data, lowpriv, user1)
  -a, --access TYPE    Access type (shell, RDP, SSH, webshell, etc.)
  -h, --help           Show this help

If no options are provided, interactive mode will prompt for details.

EOF
}

authorization_prompt() {
  echo
  echo "${YELLOW}${BOLD}ROE / AUTHORIZATION CHECK (ADV PRIVESC / POST-EX)${RESET}"
  echo "${YELLOW}This helper is for planning local enumeration and privilege escalation on:${RESET}"
  echo "${YELLOW}  • Lab systems you fully control, OR${RESET}"
  echo "${YELLOW}  • Client systems with explicit written permission for post-exploitation.${RESET}"
  echo
  read -r -p "Do you confirm you are authorised to plan privesc/post-ex for this target? (yes/no): " ans
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

planning_ack_prompt() {
  echo
  echo "${BLUE}[i] Reminder: This helper will NOT run exploits or privesc tools.${RESET}"
  echo "${BLUE}[i] It only suggests commands and structures notes for manual use.${RESET}"
  echo
  local phrase="PRIVESC PLANNING ONLY"
  echo "To continue, type the following phrase exactly:"
  echo "  ${BOLD}${phrase}${RESET}"
  echo
  read -r -p "> " typed
  if [[ "$typed" != "$phrase" ]]; then
    echo
    echo "${RED}[!] Phrase mismatch. Aborting.${RESET}"
    exit 1
  fi
  echo
  echo "${GREEN}[+] Acknowledged. Continuing with PrivEsc planning.${RESET}"
  echo
}

banner() {
  echo
  echo "${RED}${BOLD}===========================================${RESET}"
  echo "${RED}${BOLD}  RED SPECTER - ADV PRIVESC / POST-EX v${VERSION}${RESET}"
  echo "${RED}${BOLD}===========================================${RESET}"
  echo
  echo "${YELLOW}Privilege escalation & post-exploitation planning helper.${RESET}"
  echo "${YELLOW}Use only under proper ROE or in your lab.${RESET}"
  echo
}

# ---------- Main ----------
main() {
  local TAG=""
  local HOST=""
  local OS=""
  local USER=""
  local ACCESS_TYPE=""

  # Interactive mode if no args
  if [[ $# -eq 0 ]]; then
    banner
    echo "${BLUE}[i] No arguments supplied — entering interactive mode.${RESET}"
    echo
    read -rp "Enter run tag/label (e.g. CLIENT-LINUX-01, LAB-WIN-BOX): " TAG
    read -rp "Enter target host/IP or hostname: " HOST
    read -rp "Enter OS (linux/windows/other): " OS
    read -rp "Enter current user (e.g. www-data, user, lowpriv): " USER
    read -rp "Enter access type (shell, SSH, RDP, webshell, etc.): " ACCESS_TYPE
  else
    # Parse args
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -t|--tag)
          TAG="${2:-}"
          shift 2
          ;;
        -H|--host)
          HOST="${2:-}"
          shift 2
          ;;
        -o|--os)
          OS="${2:-}"
          shift 2
          ;;
        -u|--user)
          USER="${2:-}"
          shift 2
          ;;
        -a|--access)
          ACCESS_TYPE="${2:-}"
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

  # Basic validation
  if [[ -z "$TAG" || -z "$HOST" || -z "$OS" || -z "$USER" ]]; then
    echo "${RED}[!] Tag, host, OS, and user are all required fields.${RESET}"
    usage
    exit 1
  fi

  banner
  authorization_prompt
  planning_ack_prompt

  # Prepare report directory
  mkdir -p "${REPORT_DIR}"
  local ts
  ts="$(date +'%Y%m%d_%H%M%S')"

  local safe_tag
  safe_tag="$(echo "$TAG" | sed 's/[^A-Za-z0-9._-]/_/g')"
  local safe_host
  safe_host="$(echo "$HOST" | sed 's/[^A-Za-z0-9._-]/_/g')"

  local RUN_DIR="${REPORT_DIR}/adv-privesc_${safe_tag}_${safe_host}_${ts}"
  mkdir -p "${RUN_DIR}"/summary

  echo
  echo "${GREEN}[+] Run directory: ${RUN_DIR}${RESET}"
  echo

  local SUMMARY_MD="${RUN_DIR}/PrivEsc_Plan_${safe_host}_${USER}.md"

  # Normalise OS string
  local OS_LOWER
  OS_LOWER="$(echo "$OS" | tr '[:upper:]' '[:lower:]')"

  # Suggested commands (planning only)
  local base_linux_enum='whoami; id; uname -a; cat /etc/os-release; sudo -l'
  local base_windows_enum='whoami && whoami /priv && systeminfo && net user && net localgroup administrators'

  local linpeas_cmd="wget -O linpeas.sh https://github.com/carlospolop/PEASS-ng/releases/latest/download/linpeas.sh && chmod +x linpeas.sh && ./linpeas.sh"
  local winpeas_cmd="powershell -c \"Invoke-WebRequest -Uri https://github.com/carlospolop/PEASS-ng/releases/latest/download/winPEASx64.exe -OutFile winpeas.exe\""

  local pspy_cmd="./pspy64"

  # Ask for suspected weakness / notes
  echo "${BLUE}[i] Optional: short description of suspected PrivEsc angle (e.g. weak sudoers, kernel, misconfig).${RESET}"
  read -rp "Suspected PrivEsc angle: " SUSPECTED_ANGLE
  echo "${BLUE}[i] Optional: any known vulnerabilities / CVEs / references.${RESET}"
  read -rp "Known issues (or press Enter if none): " KNOWN_ISSUES

  {
    echo "# Red Specter – PrivEsc / Post-Ex Planning Note"
    echo
    echo "- **Date:** $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "- **Tag/Engagement:** \`${TAG}\`"
    echo "- **Host:** \`${HOST}\`"
    echo "- **OS:** \`${OS}\`"
    echo "- **Current User:** \`${USER}\`"
    if [[ -n "$ACCESS_TYPE" ]]; then
      echo "- **Access Type:** \`${ACCESS_TYPE}\`"
    fi
    echo "- **Module:** ADV PrivEsc / Post-Ex Helper v${VERSION}"
    echo
    echo "## ROE / Scope Reminder"
    echo
    echo "> This note is for planning local enumeration and privilege escalation ONLY."
    echo "> Actual execution of privesc techniques must be within explicit ROE or lab scope."
    echo
    echo "## Suspected PrivEsc Angle"
    echo
    if [[ -n "$SUSPECTED_ANGLE" ]]; then
      echo "- ${SUSPECTED_ANGLE}"
    else
      echo "- (Not specified yet)"
    fi
    echo
    echo "## Known Issues / References"
    echo
    if [[ -n "$KNOWN_ISSUES" ]]; then
      echo "- ${KNOWN_ISSUES}"
    else
      echo "- None documented yet."
    fi
    echo
    echo "## Baseline Local Enumeration"
    echo
    if [[ "$OS_LOWER" == "linux" ]]; then
      echo "Run a basic Linux enumeration set:"
      echo
      echo "\`\`\`bash"
      echo "${base_linux_enum}"
      echo "\`\`\`"
    elif [[ "$OS_LOWER" == "windows" ]]; then
      echo "Run a basic Windows enumeration set:"
      echo
      echo "\`\`\`powershell"
      echo "${base_windows_enum}"
      echo "\`\`\`"
    else
      echo "OS marked as 'other'. Adapt commands as appropriate (e.g., network devices, appliances)."
    fi
    echo
    echo "## Advanced Enumeration Tools (Manual Use)"
    echo
    if [[ "$OS_LOWER" == "linux" ]]; then
      echo "### linPEAS (Linux PrivEsc Audit)"
      echo
      echo "\`\`\`bash"
      echo "${linpeas_cmd}"
      echo "\`\`\`"
      echo
      echo "### pspy (Process Monitor)"
      echo
      echo "\`\`\`bash"
      echo "${pspy_cmd}"
      echo "\`\`\`"
    elif [[ "$OS_LOWER" == "windows" ]]; then
      echo "### winPEAS (Windows PrivEsc Audit)"
      echo
      echo "\`\`\`powershell"
      echo "${winpeas_cmd}"
      echo "\`\`\`"
    else
      echo "- Consider vendor-specific or OS-specific tools for deeper enumeration."
    fi
    echo
    echo "## PrivEsc Hypotheses"
    echo
    echo "- **Potential vector #1:**"
    echo "  - (e.g. misconfigured sudoers, weak service permissions, SUID binaries, unquoted service paths)"
    echo "- **Potential vector #2:**"
    echo "  - (e.g. outdated kernel, writable config files, credential reuse)"
    echo
    echo "## Evidence & Notes"
    echo
    echo "- Paste outputs of key enumeration commands here."
    echo "- Highlight any misconfigurations, interesting files, or credentials."
    echo
    echo "## Reporting Reminders"
    echo
    echo "- Clearly separate *verified* privilege escalation from **potential** paths."
    echo "- Document:"
    echo "  - Steps to reproduce (minimise impact)"
    echo "  - Resulting privilege level"
    echo "  - Impact on confidentiality/integrity/availability"
    echo "  - Recommended mitigations (patches, config changes, hardening)"
    echo
    echo "> This note was generated by Red Specter ADV PrivEsc / Post-Ex Helper v${VERSION}."
  } > "$SUMMARY_MD"

  echo
  echo "${GREEN}[+] PrivEsc / Post-Ex planning note created.${RESET}"
  echo "${GREEN}[+] File: ${SUMMARY_MD}${RESET}"
  echo
  echo "${YELLOW}Reminder:${RESET} This tool does NOT run privesc exploits or tools. Use suggested commands manually and lawfully."
  echo
}

main "$@"
