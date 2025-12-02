#!/usr/bin/env bash
set -euo pipefail
sudo apt update && sudo apt full-upgrade -y
# Kali defaults
sudo apt install -y kali-linux-default kali-tools-top10
# Common extras
sudo apt install -y git vim tmux htop jq python3-pip ruby-full golang-go
# Useful scanners / recon
sudo apt install -y nmap masscan amass dnsenum subfinder assetfinder gobuster
# Web testing
sudo apt install -y nikto sqlmap wfuzz dirsearch
# Burp deps (Burp is commercial, but community Burp or use ZAP)
sudo apt install -y zaproxy
# Cleanup
sudo apt autoremove -y && sudo apt autoclean -y
echo "Done. Reboot recommended."
