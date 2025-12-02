#!/bin/bash

# ============================================
# Red Specter Advanced Web Enumeration Script
# Name: redspecter-webenum-adv.sh
# Author: Richard (Red Specter) + Vigil
# Version: 1.0
#
# WARNING:
#   This is an AGGRESSIVE web enumeration tool.
#   It may generate significant traffic (ffuf, crawling,
#   archive scraping). Use ONLY with explicit ROE.
# ============================================

# -------- CONFIGURABLE DEFAULTS --------

OUTPUT_ROOT="$HOME/red_specter_adv_web"

# Wordlists (tune as needed)
DEFAULT_DIR_WORDLIST="/usr/share/wordlists/dirb/common.txt"
DEFAULT_EXT_LIST="php,asp,aspx,jsp,html,js"
FFUF_THREADS=50

# --------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "============================================"
echo "    RED SPECTER - WEB ENUM ADV V1"
echo "============================================"
echo -e "${NC}"
echo -e "${YELLOW}[!] This is an AGGRESSIVE web enumeration tool."
echo "[!] Use ONLY with full, explicit Rules of Engagement (ROE).${NC}"
echo

TARGET_LABEL=""
TARGET_DOMAIN=""
TARGET_DIR=""

# ------------- ROE CONFIRMATION -------------

roe_confirmation() {
    echo -e "${YELLOW}[!] Confirm ROE before proceeding.${NC}"
    echo "    Type: I_HAVE_ROE  (exactly) to continue."
    read -r CONFIRM
    if [ "$CONFIRM" != "I_HAVE_ROE" ]; then
        echo -e "${RED}[!] ROE confirmation failed. Exiting.${NC}"
        exit 1
    fi
    echo -e "${GREEN}[+] ROE confirmed.${NC}"
}

# ------------- DEPENDENCY CHECKS -------------

check_dependencies() {
    echo -e "${GREEN}[+] Checking core dependencies for ADV Web Enum...${NC}"

    # Hard requirements
    required_tools=("httpx" "ffuf" "curl")

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            echo -e "${RED}[!] Required tool missing: $tool${NC}"
            echo -e "${YELLOW}    Install it before using this script.${NC}"
            exit 1
        else
            echo -e "${GREEN}[✓] $tool is installed${NC}"
        fi
    done

    echo -e "${YELLOW}[*] Optional tools (enhanced coverage): gau, waybackurls, katana, whatweb, wafw00f${NC}"
}

# ------------- DIRECTORY SETUP -------------

create_directories() {
    if [ -z "$TARGET_LABEL" ]; then
        read -p "Enter target label (e.g. clientA-web): " TARGET_LABEL
    fi

    TARGET_DIR="$OUTPUT_ROOT/$TARGET_LABEL"

    mkdir -p "$TARGET_DIR"/{sources,alive,params,content_discovery,logs,reports}
    echo -e "${GREEN}[+] Using output directory: $TARGET_DIR${NC}"
}

# ------------- GET DOMAIN -------------

get_domain() {
    if [ -z "$TARGET_DOMAIN" ]; then
        read -p "Enter main domain (e.g. example.com): " TARGET_DOMAIN
    fi
    if [ -z "$TARGET_DOMAIN" ]; then
        echo -e "${RED}[!] No domain specified, cannot proceed.${NC}"
        exit 1
    fi
}

# ------------- URL COLLECTION -------------

collect_urls() {
    echo -e "${GREEN}[+] Collecting URLs for $TARGET_DOMAIN ...${NC}"
    cd "$TARGET_DIR/sources" || exit

    # Live crawl via httpx (simple)
    echo -e "${YELLOW}[*] Seeding with base domain URLs...${NC}"
    echo "https://$TARGET_DOMAIN" > base_seeds.txt
    echo "http://$TARGET_DOMAIN" >> base_seeds.txt

    # If katana exists, use it to crawl
    if command -v katana &> /dev/null; then
        echo -e "${GREEN}[+] Using katana for crawling...${NC}"
        katana -list base_seeds.txt -silent -o urls_katana.txt
    else
        echo -e "${YELLOW}[*] katana not installed, skipping active crawling.${NC}"
        touch urls_katana.txt
    fi

    # If gau exists, pull archived URLs
    if command -v gau &> /dev/null; then
        echo -e "${GREEN}[+] Using gau (archive URLs)...${NC}"
        gau "$TARGET_DOMAIN" > urls_gau.txt
    else
        echo -e "${YELLOW}[*] gau not installed, skipping archive collection.${NC}"
        touch urls_gau.txt
    fi

    # If waybackurls exists, hit Wayback Machine
    if command -v waybackurls &> /dev/null; then
        echo -e "${GREEN}[+] Using waybackurls...${NC}"
        echo "$TARGET_DOMAIN" | waybackurls > urls_wayback.txt
    else
        echo -e "${YELLOW}[*] waybackurls not installed, skipping Wayback URLs.${NC}"
        touch urls_wayback.txt
    fi

    # Merge & dedupe
    cat urls_katana.txt urls_gau.txt urls_wayback.txt base_seeds.txt \
        | sort -u > urls_all_raw.txt

    URL_COUNT=$(wc -l < urls_all_raw.txt 2>/dev/null | tr -d ' ')
    echo -e "${GREEN}[✓] Collected $URL_COUNT raw URLs (live + archive).${NC}"

    cd "$TARGET_DIR" || exit
}

# ------------- PROBE ALIVE ENDPOINTS -------------

probe_alive() {
    echo -e "${GREEN}[+] Probing alive URLs with httpx...${NC}"
    cd "$TARGET_DIR" || exit

    if [ ! -f "sources/urls_all_raw.txt" ]; then
        echo -e "${RED}[!] sources/urls_all_raw.txt not found. Run URL collection first.${NC}"
        return
    fi

    cd alive || exit

    echo -e "${YELLOW}[*] Running httpx with status, title, tech, IP...${NC}"

    httpx -silent -follow-redirects \
        -l ../sources/urls_all_raw.txt \
        -status-code -title -tech-detect -ip -web-server \
        -o httpx_full.txt

    # Extract just URLs with 'good' status codes (tune as needed)
    awk '$2 ~ /^(200|201|202|204|301|302|307|401|403)$/ {print $1}' httpx_full.txt \
        | sort -u > alive_urls.txt

    ALIVE_COUNT=$(wc -l < alive_urls.txt 2>/dev/null | tr -d ' ')
    echo -e "${GREEN}[✓] Alive endpoints detected: $ALIVE_COUNT${NC}"

    cd "$TARGET_DIR" || exit
}

# ------------- PARAMETER HARVESTING -------------

harvest_params() {
    echo -e "
