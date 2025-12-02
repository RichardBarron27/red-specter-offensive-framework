#!/usr/bin/env bash
#
# Red Specter Offensive Framework Launcher
# Version: 1.4 (Email OSINT + Tool Updater)
# Author: Richard + Vigil
#

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED="$(printf '\033[31m')"
GREEN="$(printf '\033[32m')"
YELLOW="$(printf '\033[33m')"
BLUE="$(printf '\033[34m')"
BOLD="$(printf '\033[1m')"
RESET="$(printf '\033[0m')"

banner() {
  echo -e "${RED}${BOLD}"
  echo "==============================================="
  echo "              R E D   S P E C T E R"
  echo "      Offensive Framework Launcher v1.4"
  echo "==============================================="
  echo -e "${RESET}"
}

press_enter() {
  echo
  read -rp "Press Enter to continue..." _
}

run_module() {
  # Safely run a module if it exists and is executable.
  # Usage: run_module "Description" "relative/path/to/script.sh"
  local desc="$1"
  local rel_path="$2"
  local full_path="${SCRIPT_DIR}/${rel_path}"

  echo
  echo -e "${BLUE}[+] ${desc}${RESET}"
  if [[ ! -f "${full_path}" ]]; then
    echo -e "${RED}[!] Module not found: ${full_path}${RESET}"
    press_enter
    return 1
  fi

  if [[ ! -x "${full_path}" ]]; then
    echo -e "${YELLOW}[!] Module is not executable. Fixing permissions...${RESET}"
    chmod +x "${full_path}" || {
      echo -e "${RED}[!] Failed to chmod +x ${full_path}${RESET}"
      press_enter
      return 1
    }
  fi

  "${full_path}"
  press_enter
}

#######################
# Core Module Menu    #
#######################

core_menu() {
  while true; do
    clear
    banner
    echo "=============== CORE MODULES ==============="
    echo "1) Core Recon"
    echo "2) Core Web Enumeration"
    echo "3) Core Vulnerability Scanning"
    echo "0) Back to main menu"
    echo "==========================================="
    echo
    read -rp "Select an option: " core_choice

    case "${core_choice}" in
      1)
        run_module "Core Recon" "core/redspecter-recon.sh"
        ;;
      2)
        run_module "Core Web Enumeration" "core/redspecter-webenum.sh"
        ;;
      3)
        run_module "Core Vulnerability Scanning" "core/redspecter-vulnscan.sh"
        ;;
      0)
        break
        ;;
      *)
        echo -e "${YELLOW}[!] Invalid option${RESET}"
        press_enter
        ;;
    esac
  done
}

########################
# Advanced Module Menu #
########################

adv_menu() {
  while true; do
    clear
    banner
    echo "============= ADVANCED MODULES ============="
    echo "1) Advanced Recon"
    echo "2) Advanced Web Enumeration"
    echo "3) Advanced Vulnerability Scanning"
    echo "4) Advanced Exploitation"
    echo "5) Advanced PrivEsc / Post-Exploitation"
    echo "0) Back to main menu"
    echo "============================================"
    echo
    read -rp "Select an option: " adv_choice

    case "${adv_choice}" in
      1)
        run_module "Advanced Recon" "adv/adv-recon/redspecter-recon-adv.sh"
        ;;
      2)
        run_module "Advanced Web Enumeration" "adv/adv-webenum/redspecter-webenum-adv.sh"
        ;;
      3)
        run_module "Advanced Vulnerability Scanning" "adv/adv-vulnscan/redspecter-vulnscan-adv.sh"
        ;;
      4)
        run_module "Advanced Exploitation" "adv/adv-exploitation/redspecter-exploit-adv.sh"
        ;;
      5)
        run_module "Advanced PrivEsc / Post-Exploitation" "adv/adv-privesc/redspecter-post-adv.sh"
        ;;
      0)
        break
        ;;
      *)
        echo -e "${YELLOW}[!] Invalid option${RESET}"
        press_enter
        ;;
    esac
  done
}

#########################
# OSINT / Email Menu    #
#########################

osint_menu() {
  while true; do
    clear
    banner
    echo "============== OSINT MODULES ==============="
    echo "1) Email OSINT (Harvester-style v1.1)"
    echo "0) Back to main menu"
    echo "============================================"
    echo
    read -rp "Select an option: " osint_choice

    case "${osint_choice}" in
      1)
        read -rp "Enter target domain (e.g. example.com): " rs_osint_domain
        if [[ -n "${rs_osint_domain}" ]]; then
          echo
          echo -e "${YELLOW}[!] Ensure you have authorization for OSINT on: ${rs_osint_domain}${RESET}"
          read -rp "Press Enter to proceed or Ctrl+C to abort..." _
          # Call the module directly so we can pass the domain as arg
          "${SCRIPT_DIR}/redspecter-osint-email.sh" "${rs_osint_domain}"
          press_enter
        else
          echo -e "${YELLOW}[!] No domain provided. Returning to OSINT menu.${RESET}"
          press_enter
        fi
        ;;
      0)
        break
        ;;
      *)
        echo -e "${YELLOW}[!] Invalid option${RESET}"
        press_enter
        ;;
    esac
  done
}

#########################
# WiFi Menu (paths TBD) #
#########################

wifi_menu() {
  while true; do
    clear
    banner
    echo "================ WIFI TOOLS ================"
    echo "1) WiFi Core Module"
    echo "2) WiFi Advanced Module"
    echo "0) Back to main menu"
    echo "============================================"
    echo
    read -rp "Select an option: " wifi_choice

    case "${wifi_choice}" in
      1)
        # TODO: adjust to your real WiFi core path
        run_module "WiFi Core Module" "utils/redspecter-wifi-core.sh"
        ;;
      2)
        # TODO: adjust to your real WiFi advanced path
        run_module "WiFi Advanced Module" "utils/redspecter-wifi-adv.sh"
        ;;
      0)
        break
        ;;
      *)
        echo -e "${YELLOW}[!] Invalid option${RESET}"
        press_enter
        ;;
    esac
  done
}

#####################
# Utilities / Setup #
#####################

utils_menu() {
  while true; do
    clear
    banner
    echo "================= UTILITIES ================="
    echo "1) Red Specter Kali Setup Script"
    echo "2) Update Red Specter Tools (Kali apt)"
    echo "0) Back to main menu"
    echo "============================================="
    echo
    read -rp "Select an option: " util_choice

    case "${util_choice}" in
      1)
        run_module "Red Specter Kali Setup" "red_specter_kali_setup.sh"
        ;;
      2)
        run_module "Red Specter Tools Update" "utils/redspecter-update-tools.sh"
        ;;
      0)
        break
        ;;
      *)
        echo -e "${YELLOW}[!] Invalid option${RESET}"
        press_enter
        ;;
    esac
  done
}

###############
# Main Menu   #
###############

main_menu() {
  while true; do
    clear
    banner
    echo "=============== MAIN MENU ==================="
    echo "1) Core Modules"
    echo "2) Advanced Modules"
    echo "3) OSINT / Email Intelligence"
    echo "4) WiFi Tools"
    echo "5) Utilities / Setup"
    echo "0) Exit"
    echo "============================================="
    echo
    read -rp "Select an option: " main_choice

    case "${main_choice}" in
      1)
        core_menu
        ;;
      2)
        adv_menu
        ;;
      3)
        osint_menu
        ;;
      4)
        wifi_menu
        ;;
      5)
        utils_menu
        ;;
      0)
        echo
        echo -e "${GREEN}Goodbye from Red Specter.${RESET}"
        echo
        exit 0
        ;;
      *)
        echo -e "${YELLOW}[!] Invalid option${RESET}"
        press_enter
        ;;
    esac
  done
}

main_menu
