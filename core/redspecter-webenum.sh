#!/bin/bash

# ============================================
# Red Specter Web Enumeration Script
# Name: redspecter-webenum.sh
# Author: Richard (Red Specter) + Vigil
# Version: 1.0
# ============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}"
echo "==========================================="
echo "       RED SPECTER - WEB ENUM V1"
echo "==========================================="
echo -e "${NC}"
echo -e "${YELLOW}[!] Use only against web assets you are explicitly authorised to test.${NC}"
echo

TARGET=""
DOMAIN=""
WORDLIST=""
TARGET_DIR=""

# -------------------------
# Core helpers
# -------------------------

create_directories() {
    if [ -z "$TARGET" ]; then
        read -p "Enter target name (folder label): " TARGET
    fi

    TARGET_DIR="$TARGET"

    mkdir -p "$TARGET_DIR"/{webenum,subdomains,web,reports}
    echo -e "${GREEN}[+] Using target directory: $TARGET_DIR/${NC}"
}

check_dependencies() {
    echo -e "${GREEN}[+] Checking core dependencies for web enumeration...${NC}"

    # httpx is our main engine here
    required_tools=("curl" "httpx")

    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            echo -e "${RED}[!] Required tool '$tool' is not installed.${NC}"
            echo -e "${YELLOW}    Please install it (e.g. 'sudo apt install httpx' or via Go) and re-run.${NC}"
            exit 1
        else
            echo -e "${GREEN}[✓] $tool is installed${NC}"
        fi
    done

    echo -e "${YELLOW}[*] Optional tools (enhanced results): whatweb, wafw00f, ffuf, gobuster${NC}"
}

# Prepare list of hosts/URLs to probe
prepare_host_list() {
    cd "$TARGET_DIR" || exit
    cd webenum || exit

    HOST_INPUT_FILE="hosts_input.txt"

    # If a domain was provided, try to use subdomains from previous recon if present
    if [ -n "$DOMAIN" ]; then
        if [ -f "../subdomains/all_subdomains.txt" ]; then
            echo -e "${GREEN}[+] Found existing subdomains list from recon, using that.${NC}"
            cp ../subdomains/all_subdomains.txt "$HOST_INPUT_FILE"
        else
            echo -e "${YELLOW}[*] No subdomains file found, starting with the main domain only.${NC}"
            echo "$DOMAIN" > "$HOST_INPUT_FILE"
        fi
    else
        # No domain provided – ask the user
        if [ -f "../subdomains/all_subdomains.txt" ]; then
            echo -e "${YELLOW}[*] No domain specified, but subdomains list found from recon.${NC}"
            read -p "Use ../subdomains/all_subdomains.txt as input? (y/N): " USE_SUBS
            if [[ "$USE_SUBS" =~ ^[Yy]$ ]]; then
                cp ../subdomains/all_subdomains.txt "$HOST_INPUT_FILE"
            else
                read -p "Enter a single domain or hostname: " DOMAIN
                echo "$DOMAIN" > "$HOST_INPUT_FILE"
            fi
        else
            read -p "Enter a single domain or hostname: " DOMAIN
            echo "$DOMAIN" > "$HOST_INPUT_FILE"
        fi
    fi

    echo -e "${GREEN}[+] Host input prepared: $(wc -l < "$HOST_INPUT_FILE") entries${NC}"
    cd ..  # back to target dir
}

# Probe for alive web hosts using httpx
probe_alive_hosts() {
    cd "$TARGET_DIR/webenum" || exit

    HOST_INPUT_FILE="hosts_input.txt"
    ALIVE_OUTPUT_FILE="alive_httpx.txt"

    if [ ! -f "$HOST_INPUT_FILE" ]; then
        echo -e "${RED}[!] Host input file not found: $HOST_INPUT_FILE${NC}"
        echo -e "${YELLOW}    Run prepare_host_list first.${NC}"
        return
    fi

    echo -e "${GREEN}[+] Probing for alive web hosts with httpx...${NC}"
    echo -e "${YELLOW}    This will include title, status code, tech and IP where possible.${NC}"

    httpx -silent -follow-redirects \
        -l "$HOST_INPUT_FILE" \
        -status-code -title -tech-detect -ip -cname -web-server \
        -o "$ALIVE_OUTPUT_FILE"

    ALIVE_COUNT=$(wc -l < "$ALIVE_OUTPUT_FILE" 2>/dev/null | tr -d ' ')
    echo -e "${GREEN}[✓] Alive web endpoints discovered: $ALIVE_COUNT${NC}"

    cd ../..
}

# Simple tech fingerprinting (extra pass if whatweb / wafw00f exist)
tech_fingerprint() {
    cd "$TARGET_DIR/webenum" || exit

    ALIVE_OUTPUT_FILE="alive_httpx.txt"
    URLS_ONLY_FILE="alive_urls.txt"

    if [ ! -f "$ALIVE_OUTPUT_FILE" ]; then
        echo -e "${RED}[!] Alive hosts file not found: $ALIVE_OUTPUT_FILE${NC}"
        echo -e "${YELLOW}    Run the alive probing step first.${NC}"
        cd ../..
        return
    fi

    # Extract just URLs from httpx output (first field)
    awk '{print $1}' "$ALIVE_OUTPUT_FILE" | sort -u > "$URLS_ONLY_FILE"

    if command -v whatweb &> /dev/null; then
        echo -e "${GREEN}[+] Running whatweb against alive URLs...${NC}"
        whatweb -i "$URLS_ONLY_FILE" --log-brief=whatweb_brief.log --log-verbose=whatweb_verbose.log
    else
        echo -e "${YELLOW}[*] whatweb not installed, skipping whatweb fingerprinting.${NC}"
    fi

    if command -v wafw00f &> /dev/null; then
        echo -e "${GREEN}[+] Running wafw00f to detect WAF on alive URLs...${NC}"
        : > wafw00f_results.txt
        while read -r url; do
            echo -e "${YELLOW}[*] Checking WAF for: $url${NC}"
            wafw00f "$url" >> wafw00f_results.txt
            echo "" >> wafw00f_results.txt
        done < "$URLS_ONLY_FILE"
    else
        echo -e "${YELLOW}[*] wafw00f not installed, skipping WAF detection.${NC}"
    fi

    echo -e "${GREEN}[✓] Tech fingerprinting step completed.${NC}"
    cd ../..
}

# Directory brute forcing (single target URL)
dir_bruteforce() {
    cd "$TARGET_DIR/webenum" || exit

    read -p "Enter base URL for directory fuzzing (e.g. https://example.com/): " BASE_URL
    if [ -z "$BASE_URL" ]; then
        echo -e "${RED}[!] No URL provided, skipping dir fuzzing.${NC}"
        cd ../..
        return
    fi

    if [ -z "$WORDLIST" ]; then
        read -p "Enter wordlist path (default: /usr/share/wordlists/dirb/common.txt): " WORDLIST
        [ -z "$WORDLIST" ] && WORDLIST="/usr/share/wordlists/dirb/common.txt"
    fi

    if [ ! -f "$WORDLIST" ]; then
        echo -e "${RED}[!] Wordlist not found: $WORDLIST${NC}"
        cd ../..
        return
    fi

    # Prefer ffuf if present, fall back to gobuster
    if command -v ffuf &> /dev/null; then
        echo -e "${GREEN}[+] Running dir fuzzing with ffuf...${NC}"
        ffuf -w "$WORDLIST" -u "${BASE_URL}FUZZ" -mc 200,204,301,302,307,401,403 -o ffuf_dirs.json -of json
    elif command -v gobuster &> /dev/null; then
        echo -e "${GREEN}[+] Running dir fuzzing with gobuster...${NC}"
        gobuster dir -u "$BASE_URL" -w "$WORDLIST" -o gobuster_dirs.txt -t 50
    else
        echo -e "${RED}[!] Neither ffuf nor gobuster is installed; cannot perform directory brute forcing.${NC}"
        cd ../..
        return
    fi

    echo -e "${GREEN}[✓] Directory fuzzing step completed.${NC}"
    cd ../..
}

# Generate Markdown web enumeration report
generate_webenum_report() {
    cd "$TARGET_DIR/reports" || exit

    REPORT="webenum_report_$(date +%Y%m%d_%H%M%S).md"

    echo "# Red Specter Web Enumeration Report" > "$REPORT"
    echo "" >> "$REPORT"
    echo "## Target: ${DOMAIN:-Unknown}" >> "$REPORT"
    echo "### Date: $(date)" >> "$REPORT"
    echo "" >> "$REPORT"

    echo "## Scope & Method" >> "$REPORT"
    echo "" >> "$REPORT"
    echo "- Alive host probing with **httpx** (status, title, tech, IP)." >> "$REPORT"
    echo "- Optional fingerprinting with **whatweb** and **wafw00f**." >> "$REPORT"
    echo "- Optional directory fuzzing with **ffuf** or **gobuster**." >> "$REPORT"
    echo "" >> "$REPORT"

    # Alive hosts summary
    if [ -f "../webenum/alive_httpx.txt" ]; then
        ALIVE_COUNT=$(wc -l < "../webenum/alive_httpx.txt" 2>/dev/null | tr -d ' ')
        echo "## Alive Web Endpoints" >> "$REPORT"
        echo "" >> "$REPORT"
        echo "- **Count:** $ALIVE_COUNT" >> "$REPORT"
        echo "" >> "$REPORT"
        echo '```' >> "$REPORT"
        cat ../webenum/alive_httpx.txt >> "$REPORT"
        echo '```' >> "$REPORT"
        echo "" >> "$REPORT"
    fi

    # WhatWeb summary
    if [ -f "../webenum/whatweb_brief.log" ]; then
        echo "## Technology Fingerprinting (WhatWeb - Brief)" >> "$REPORT"
        echo "" >> "$REPORT"
        echo '```' >> "$REPORT"
        cat ../webenum/whatweb_brief.log >> "$REPORT"
        echo '```' >> "$REPORT"
        echo "" >> "$REPORT"
    fi

    # WAF detection
    if [ -f "../webenum/wafw00f_results.txt" ]; then
        echo "## WAF Detection (wafw00f)" >> "$REPORT"
        echo "" >> "$REPORT"
        echo '```' >> "$REPORT"
        cat ../webenum/wafw00f_results.txt >> "$REPORT"
        echo '```' >> "$REPORT"
        echo "" >> "$REPORT"
    fi

    # Directory fuzzing notes
    if [ -f "../webenum/ffuf_dirs.json" ] || [ -f "../webenum/gobuster_dirs.txt" ]; then
        echo "## Directory Enumeration" >> "$REPORT"
        echo "" >> "$REPORT"
        if [ -f "../webenum/ffuf_dirs.json" ]; then
            echo "- Results from **ffuf** stored in \`webenum/ffuf_dirs.json\`." >> "$REPORT"
        fi
        if [ -f "../webenum/gobuster_dirs.txt" ]; then
            echo "- Results from **gobuster** stored in \`webenum/gobuster_dirs.txt\`." >> "$REPORT"
        fi
        echo "" >> "$REPORT"
    fi

    echo "## High-Level Web Security Recommendations" >> "$REPORT"
    echo "" >> "$REPORT"
    echo "1. Minimise exposed endpoints; disable or restrict unused paths." >> "$REPORT"
    echo "2. Harden identified tech stacks (frameworks, CMS, plugins) and keep them patched." >> "$REPORT"
    echo "3. Implement strict access controls and rate limiting on sensitive or high-value endpoints." >> "$REPORT"
    echo "4. Use strong security headers (HSTS, CSP, X-Frame-Options, X-Content-Type-Options, etc.)." >> "$REPORT"
    echo "5. Regularly re-run web enumeration after major releases or infrastructure changes." >> "$REPORT"

    echo -e "${GREEN}[✓] Web enumeration report generated: reports/$REPORT${NC}"
    cd ..
}

# -------------------------
# Menu / Control flow
# -------------------------

main_menu() {
    echo -e "${BLUE}"
    echo "==========================================="
    echo "     RED SPECTER WEB ENUM - MAIN MENU"
    echo "==========================================="
    echo -e "${NC}"
    echo "1. Full Web Enumeration (recommended)"
    echo "2. Probe Alive Web Hosts Only"
    echo "3. Tech Fingerprinting Only (whatweb / wafw00f)"
    echo "4. Directory Fuzzing Only"
    echo "5. Generate Web Enumeration Report"
    echo "0. Exit"
    echo ""

    read -p "Select option (0-5): " OPTION

    case $OPTION in
        1)
            create_directories
            check_dependencies
            read -p "Enter main domain (e.g. example.com): " DOMAIN
            prepare_host_list
            probe_alive_hosts
            tech_fingerprint
            read -p "Run directory fuzzing as part of full enum? (y/N): " DO_FUZZ
            if [[ "$DO_FUZZ" =~ ^[Yy]$ ]]; then
                dir_bruteforce
            fi
            generate_webenum_report
            ;;
        2)
            create_directories
            check_dependencies
            read -p "Enter main domain (e.g. example.com): " DOMAIN
            prepare_host_list
            probe_alive_hosts
            ;;
        3)
            create_directories
            check_dependencies
            read -p "Enter main domain (e.g. example.com): " DOMAIN
            prepare_host_list
            probe_alive_hosts
            tech_fingerprint
            ;;
        4)
            create_directories
            check_dependencies
            dir_bruteforce
            ;;
        5)
            create_directories
            generate_webenum_report
            ;;
        0)
            echo -e "${YELLOW}[*] Exiting Red Specter Web Enum...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}[!] Invalid option${NC}"
            main_menu
            ;;
    esac
}

# Simple CLI mode
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Red Specter Web Enumeration v1"
    echo ""
    echo "Options:"
    echo "  -t, --target NAME     Target folder name (label for reports)"
    echo "  -d, --domain DOMAIN   Main domain to enumerate (optional, menu will ask if omitted)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "If no options are provided, the interactive menu will be shown."
}

if [ $# -gt 0 ]; then
    while [[ $# -gt 0 ]]; do
        key="$1"
        case $key in
            -t|--target)
                TARGET="$2"
                shift; shift
                ;;
            -d|--domain)
                DOMAIN="$2"
                shift; shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo -e "${RED}[!] Unknown option: $1${NC}"
                usage
                exit 1
                ;;
        esac
    done

    # If options were provided, just run full enum with those
    create_directories
    check_dependencies
    prepare_host_list
    probe_alive_hosts
    tech_fingerprint
    generate_webenum_report
else
    main_menu
fi
