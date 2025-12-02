#!/bin/bash

# ============================================
# Red Specter Reconnaissance Script
# Author: Richard (Red Specter) + Vigil
# Version: 1.0
# ============================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Banner
echo -e "${BLUE}"
echo "==========================================="
echo "          RED SPECTER - RECON V1"
echo "==========================================="
echo -e "${NC}"
echo -e "${YELLOW}[!] Use only on systems and domains you are explicitly authorised to test.${NC}"
echo -e "${YELLOW}[!] Red Specter & Vigil assume all activity is logged for evidence and compliance.${NC}"
echo

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[!] This script must be run as root (sudo)${NC}"
   exit 1
fi

# Create directory structure
create_directories() {
    echo -e "${GREEN}[+] Creating directory structure...${NC}"
    
    if [ -z "$1" ]; then
        read -p "Enter target name: " TARGET
    else
        TARGET=$1
    fi
    
    # Create main directory in current path
    mkdir -p "$TARGET"/{nmap,subdomains,web,network,reports}
    
    echo -e "${GREEN}[+] Directory created: $TARGET/${NC}"
    cd "$TARGET" || exit
}

# Check dependencies
check_dependencies() {
    echo -e "${GREEN}[+] Checking core dependencies...${NC}"
    
    # Added jq here (was missing but used later)
    required_tools=("nmap" "dig" "whois" "curl" "python3" "git" "jq")
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            echo -e "${RED}[!] $tool is not installed${NC}"
            exit 1
        else
            echo -e "${GREEN}[✓] $tool is installed${NC}"
        fi
    done
}

# Initial target information gathering
initial_recon() {
    echo -e "${GREEN}[+] Starting initial reconnaissance...${NC}"
    
    if [ -z "$DOMAIN" ] && [ -z "$IP" ]; then
        read -p "Enter target (domain/IP): " TARGET_INPUT
        
        # Check if input is IP or domain
        if [[ $TARGET_INPUT =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            IP=$TARGET_INPUT
            echo -e "${YELLOW}[*] Target identified as IP: $IP${NC}"
            DOMAIN=$(dig +short -x "$IP" 2>/dev/null | head -1)
        else
            DOMAIN=$TARGET_INPUT
            echo -e "${YELLOW}[*] Target identified as domain: $DOMAIN${NC}"
            IP=$(dig +short "$DOMAIN" | head -1)
        fi
    fi
    
    # Save target info
    echo "Target: $DOMAIN" > target_info.txt
    echo "IP: $IP" >> target_info.txt
    echo "Date: $(date)" >> target_info.txt
    
    # WHOIS lookup
    echo -e "${GREEN}[+] Performing WHOIS lookup...${NC}"
    whois "$DOMAIN" > whois.txt 2>/dev/null || whois "$IP" > whois.txt 2>/dev/null
    
    # DNS enumeration
    echo -e "${GREEN}[+] Enumerating DNS records...${NC}"
    echo "=== DNS Records for $DOMAIN ===" > dns_records.txt
    echo "" >> dns_records.txt
    
    # Check different record types
    record_types=("A" "AAAA" "MX" "NS" "TXT" "SOA" "CNAME")
    
    for record in "${record_types[@]}"; do
        echo "[$record Records]" >> dns_records.txt
        dig "$DOMAIN" "$record" +short >> dns_records.txt
        echo "" >> dns_records.txt
    done
    
    echo -e "${GREEN}[✓] Initial reconnaissance completed${NC}"
}

# Subdomain enumeration
subdomain_enum() {
    echo -e "${GREEN}[+] Starting subdomain enumeration...${NC}"
    
    if [ -z "$DOMAIN" ]; then
        read -p "Enter domain: " DOMAIN
    fi
    
    cd subdomains || exit
    
    # Using different tools/methods for subdomain discovery
    echo -e "${YELLOW}[*] Method 1: crt.sh (Certificate Transparency)...${NC}"
    if command -v jq &> /dev/null; then
        curl -s "https://crt.sh/?q=%25.$DOMAIN&output=json" \
        | jq -r '.[].name_value' \
        | sed 's/\*\.//g' \
        | sort -u > crt_sh.txt
    else
        echo -e "${RED}[!] jq not installed, skipping crt.sh JSON parsing...${NC}"
    fi
    
    echo -e "${YELLOW}[*] Method 2: Subfinder...${NC}"
    if command -v subfinder &> /dev/null; then
        subfinder -d "$DOMAIN" -o subfinder.txt
    else
        echo -e "${RED}[!] Subfinder not installed, skipping...${NC}"
    fi
    
    echo -e "${YELLOW}[*] Method 3: Assetfinder...${NC}"
    if command -v assetfinder &> /dev/null; then
        assetfinder --subs-only "$DOMAIN" > assetfinder.txt
    else
        echo -e "${RED}[!] Assetfinder not installed, skipping...${NC}"
    fi
    
    # Combine all results
    cat *.txt 2>/dev/null | sort -u > all_subdomains.txt
    COUNT=$(wc -l < all_subdomains.txt 2>/dev/null | tr -d ' ')
    
    echo -e "${GREEN}[✓] Found $COUNT unique subdomains${NC}"
    cd ..
}

# Port scanning with nmap
port_scanning() {
    echo -e "${GREEN}[+] Starting port scanning...${NC}"
    
    if [ -z "$IP" ]; then
        read -p "Enter target IP: " IP
    fi
    
    cd nmap || exit
    
    echo -e "${YELLOW}[*] Quick scan (top 1000 TCP ports)...${NC}"
    nmap -sV -sC -oN quick_scan.nmap "$IP"
    
    echo -e "${YELLOW}[*] Full TCP port scan...${NC}"
    nmap -p- -oN full_ports.nmap "$IP"
    
    # Get open ports for service detection
    OPEN_PORTS=$(grep -E '^[0-9]+/tcp.*open' full_ports.nmap 2>/dev/null | cut -d'/' -f1 | tr '\n' ',' | sed 's/,$//')
    
    if [ -n "$OPEN_PORTS" ]; then
        echo -e "${YELLOW}[*] Detailed service scan on open ports: $OPEN_PORTS${NC}"
        nmap -sV -sC -p "$OPEN_PORTS" -oN detailed_scan.nmap "$IP"
    fi
    
    echo -e "${YELLOW}[*] UDP scan (top 100)...${NC}"
    nmap -sU --top-ports 100 -oN udp_scan.nmap "$IP"
    
    echo -e "${GREEN}[✓] Port scanning completed${NC}"
    cd ..
}

# Web reconnaissance
web_recon() {
    echo -e "${GREEN}[+] Starting web reconnaissance...${NC}"
    
    cd web || exit
    
    if [ -z "$DOMAIN" ]; then
        read -p "Enter domain: " DOMAIN
    fi
    
    # Check if web server is running
    echo -e "${YELLOW}[*] Checking HTTP/HTTPS...${NC}"
    curl -I "http://$DOMAIN" -m 5 > http_headers.txt 2>/dev/null
    curl -I "https://$DOMAIN" -k -m 5 >> http_headers.txt 2>/dev/null
    
    # Take screenshot (if eyewitness is installed)
    if command -v eyewitness &> /dev/null; then
        echo -e "${YELLOW}[*] Taking screenshot with EyeWitness...${NC}"
        eyewitness --web --single "http://$DOMAIN" --no-prompt
    fi
    
    # Directory brute force (if gobuster is installed)
    if command -v gobuster &> /dev/null; then
        echo -e "${YELLOW}[*] Directory brute forcing with Gobuster...${NC}"
        gobuster dir -u "http://$DOMAIN" -w /usr/share/wordlists/dirb/common.txt -o directory_scan.txt -t 50
    fi
    
    # Check for common security headers
    echo -e "${YELLOW}[*] Checking for common security headers...${NC}"
    echo "=== Security Headers for https://$DOMAIN ===" > security_checks.txt
    curl -I "https://$DOMAIN" -k -m 5 2>/dev/null \
        | grep -i -E "(strict-transport-security|x-frame-options|x-content-type|x-xss-protection|content-security-policy)" \
        >> security_checks.txt
    
    echo -e "${GREEN}[✓] Web reconnaissance completed${NC}"
    cd ..
}

# Network reconnaissance
network_recon() {
    echo -e "${GREEN}[+] Starting network reconnaissance...${NC}"
    
    cd network || exit
    
    if [ -z "$IP_RANGE" ]; then
        read -p "Enter IP range (e.g., 192.168.1.0/24) or press enter to skip: " IP_RANGE
        if [ -z "$IP_RANGE" ]; then
            echo -e "${YELLOW}[*] Skipping network reconnaissance${NC}"
            cd ..
            return
        fi
    fi
    
    echo -e "${YELLOW}[*] Network discovery (ping sweep)...${NC}"
    nmap -sn "$IP_RANGE" -oN network_discovery.nmap
    
    echo -e "${YELLOW}[*] OS detection on IP range (may be slow/noisy)...${NC}"
    nmap -O --osscan-guess "$IP_RANGE" -oN os_detection.nmap
    
    echo -e "${GREEN}[✓] Network reconnaissance completed${NC}"
    cd ..
}

# Vulnerability scanning (basic)
vuln_scanning() {
    echo -e "${GREEN}[+] Starting vulnerability scanning (NSE)...${NC}"
    
    cd nmap || exit
    
    if [ -z "$IP" ]; then
        read -p "Enter target IP: " IP
    fi
    
    echo -e "${YELLOW}[*] Running NSE vulnerability scripts (--script vuln)...${NC}"
    nmap --script vuln -oN vulnerability_scan.nmap "$IP"
    
    echo -e "${YELLOW}[*] Checking versions with safe scripts...${NC}"
    # Fixed: use a valid Nmap script expression
    nmap -sV --script "safe" -oN service_versions.nmap "$IP"
    
    echo -e "${GREEN}[✓] Vulnerability scanning completed${NC}"
    cd ..
}

# Generate report
generate_report() {
    echo -e "${GREEN}[+] Generating Markdown report...${NC}"
    
    cd reports || exit
    
    REPORT="recon_report_$(date +%Y%m%d_%H%M%S).md"
    
    echo "# Red Specter Reconnaissance Report" > "$REPORT"
    echo "" >> "$REPORT"
    echo "## Target: ${DOMAIN:-Unknown} (${IP:-Unknown})" >> "$REPORT"
    echo "### Date: $(date)" >> "$REPORT"
    echo "" >> "$REPORT"
    
    # Summary
    echo "## Executive Summary" >> "$REPORT"
    echo "" >> "$REPORT"
    echo "- Automated reconnaissance performed with Red Specter Recon v1." >> "$REPORT"
    echo "- All tests conducted under authorised conditions." >> "$REPORT"
    echo "" >> "$REPORT"
    
    # Subdomains count
    if [ -f "../subdomains/all_subdomains.txt" ]; then
        SUBS_COUNT=$(wc -l < "../subdomains/all_subdomains.txt" 2>/dev/null | tr -d ' ')
        echo "## Subdomain Enumeration" >> "$REPORT"
        echo "" >> "$REPORT"
        echo "- **Subdomains Found:** $SUBS_COUNT" >> "$REPORT"
        echo "" >> "$REPORT"
    fi
    
    # Open ports
    if [ -f "../nmap/quick_scan.nmap" ]; then
        echo "## Open TCP Ports (Quick Scan)" >> "$REPORT"
        echo "" >> "$REPORT"
        echo '```' >> "$REPORT"
        grep -E '^[0-9]+/tcp.*open' ../nmap/quick_scan.nmap >> "$REPORT"
        echo '```' >> "$REPORT"
        echo "" >> "$REPORT"
    fi
    
    # Recommendations
    echo "## High-Level Security Recommendations" >> "$REPORT"
    echo "1. Ensure all exposed services are updated to the latest secure versions." >> "$REPORT"
    echo "2. Review and close unnecessary open ports and services." >> "$REPORT"
    echo "3. Implement and verify strong security headers (HSTS, CSP, X-Frame-Options, etc.)." >> "$REPORT"
    echo "4. Perform regular vulnerability assessments and remediation cycles." >> "$REPORT"
    echo "5. Consider adding Web Application Firewall (WAF) and rate limiting where appropriate." >> "$REPORT"
    
    echo -e "${GREEN}[✓] Report generated: reports/$REPORT${NC}"
    cd ..
}

# Install additional tools
install_tools() {
    echo -e "${GREEN}[+] Installing additional tools (Kali / Debian-based)...${NC}"
    
    # Update system
    apt-get update
    
    # Install recommended tools
    RECOMMENDED_TOOLS=("gobuster" "subfinder" "assetfinder" "jq" "eyewitness" "amass" "masscan")
    
    for tool in "${RECOMMENDED_TOOLS[@]}"; do
        echo -e "${YELLOW}[*] Installing $tool...${NC}"
        apt-get install -y "$tool" 2>/dev/null || echo -e "${RED}[!] Failed to install $tool (check package name or install manually)${NC}"
    done
    
    # Install findomain from GitHub if not present
    echo -e "${YELLOW}[*] Installing findomain (from GitHub release) if missing...${NC}"
    if ! command -v findomain &> /dev/null; then
        wget https://github.com/findomain/findomain/releases/latest/download/findomain-linux -O /usr/local/bin/findomain
        chmod +x /usr/local/bin/findomain
    fi
    
    echo -e "${GREEN}[✓] Tool installation phase completed${NC}"
}

# Clean up function
cleanup() {
    echo -e "${YELLOW}[*] Cleaning up (end of run)...${NC}"
    # Placeholder for future cleanup (temp files, etc.)
    echo -e "${GREEN}[✓] Cleanup completed${NC}"
}

# Trap Ctrl+C and normal exit
trap cleanup EXIT

# Main menu
main_menu() {
    echo -e "${BLUE}"
    echo "==========================================="
    echo "        RED SPECTER RECON - MAIN MENU"
    echo "==========================================="
    echo -e "${NC}"
    
    echo "1. Full Automated Reconnaissance"
    echo "2. Initial Information Gathering"
    echo "3. Subdomain Enumeration"
    echo "4. Port Scanning"
    echo "5. Web Reconnaissance"
    echo "6. Network Reconnaissance"
    echo "7. Vulnerability Scanning"
    echo "8. Generate Report (from existing data)"
    echo "9. Install Recommended Tools"
    echo "0. Exit"
    echo ""
    
    read -p "Select option (0-9): " OPTION
    
    case $OPTION in
        1)
            create_directories
            check_dependencies
            initial_recon
            subdomain_enum
            port_scanning
            web_recon
            network_recon
            vuln_scanning
            generate_report
            ;;
        2)
            create_directories
            check_dependencies
            initial_recon
            ;;
        3)
            create_directories
            check_dependencies
            subdomain_enum
            ;;
        4)
            create_directories
            check_dependencies
            port_scanning
            ;;
        5)
            create_directories
            check_dependencies
            web_recon
            ;;
        6)
            create_directories
            check_dependencies
            network_recon
            ;;
        7)
            create_directories
            check_dependencies
            vuln_scanning
            ;;
        8)
            generate_report
            ;;
        9)
            install_tools
            ;;
        0)
            echo -e "${YELLOW}[*] Exiting Red Specter Recon...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}[!] Invalid option${NC}"
            main_menu
            ;;
    esac
}

# Argument handling (CLI mode)
if [ $# -gt 0 ]; then
    case $1 in
        -d|--domain)
            DOMAIN=$2
            create_directories "$DOMAIN"
            check_dependencies
            initial_recon
            ;;
        -i|--ip)
            IP=$2
            create_directories "$IP"
            check_dependencies
            initial_recon
            ;;
        -f|--full)
            DOMAIN=$2
            create_directories "$DOMAIN"
            check_dependencies
            initial_recon
            subdomain_enum
            port_scanning
            web_recon
            vuln_scanning
            generate_report
            ;;
        -h|--help)
            echo "Usage: $0 [OPTION]"
            echo ""
            echo "Red Specter Recon v1 - authorised reconnaissance wrapper"
            echo ""
            echo "Options:"
            echo "  -d, --domain DOMAIN   Target domain (initial recon only)"
            echo "  -i, --ip IP           Target IP address (initial recon only)"
            echo "  -f, --full DOMAIN     Full reconnaissance workflow on domain"
            echo "  -h, --help            Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}[!] Invalid argument${NC}"
            echo "Use -h for help"
            exit 1
            ;;
    esac
else
    # Start with main menu (interactive)
    main_menu
fi

echo -e "${BLUE}"
echo "==========================================="
echo "       RED SPECTER RECON COMPLETED"
echo "==========================================="
echo -e "${NC}"
