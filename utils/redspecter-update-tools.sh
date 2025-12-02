#!/usr/bin/env bash
#
# Red Specter - Update Tools Helper
# Version: 1.0
# Updates common Kali / Red Specter dependencies in one go.
#

set -euo pipefail

RED="$(printf '\033[31m')"
GREEN="$(printf '\033[32m')"
YELLOW="$(printf '\033[33m')"
BLUE="$(printf '\033[34m')"
BOLD="$(printf '\033[1m')"
RESET="$(printf '\033[0m')"

banner() {
  echo -e "${RED}${BOLD}"
  echo "==============================================="
  echo "       RED SPECTER - TOOL UPDATE HELPER"
  echo "==============================================="
  echo -e "${RESET}"
}

# Decide whether to use sudo
SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  SUDO="sudo"
fi

banner

echo -e "${BLUE}[+] This will update system package lists and refresh common Red Specter tools.${RESET}"
echo
echo "Tools covered (via apt where available):"
echo "  - nmap, amass, subfinder, httpx, dnsx"
echo "  - ffuf, gobuster, whatweb, nuclei"
echo "  - theHarvester, jq, curl, wget"
echo
echo -e "${YELLOW}[!] This may take a while and will run apt update / upgrade.${RESET}"
echo -e "${YELLOW}[!] Make sure you are OK with updating Kali before proceeding.${RESET}"
echo
read -rp "Proceed with tool update? [y/N]: " CONFIRM

if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
  echo
  echo -e "${YELLOW}[!] Aborting tool update at user request.${RESET}"
  exit 0
fi

echo
echo -e "${BLUE}[+] Updating package lists (apt update)...${RESET}"
${SUDO} apt update -y || {
  echo -e "${RED}[!] apt update failed.${RESET}"
  exit 1
}

echo
echo -e "${BLUE}[+] Upgrading installed packages (apt full-upgrade)...${RESET}"
${SUDO} apt full-upgrade -y || {
  echo -e "${RED}[!] apt full-upgrade failed.${RESET}"
  exit 1
}

echo
echo -e "${BLUE}[+] Installing / refreshing core Red Specter tools...${RESET}"

${SUDO} apt install -y \
  nmap \
  amass \
  subfinder \
  httpx-toolkit \
  dnsx \
  ffuf \
  gobuster \
  whatweb \
  nuclei \
  theharvester \
  jq \
  curl \
  wget || {
    echo -e "${RED}[!] One or more tool installs failed (check output above).${RESET}"
  }

echo
echo -e "${GREEN}[+] Tool update routine complete.${RESET}"
echo -e "${GREEN}[+] You may want to reboot if a lot of packages were upgraded.${RESET}"
echo
