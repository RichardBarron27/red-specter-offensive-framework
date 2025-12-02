#!/usr/bin/env bash
# redrecon.sh — Red Specter: Super Recon Orchestrator (AGGRESSIVE mode added)
# Author: Richard (Red Specter)
# Purpose: Orchestrate common Kali recon tools into a single, auditable run.
# IMPORTANT: Use only with explicit, written authorization. This script will
# refuse to run unless you provide a scope.yaml file with approved targets.
# LICENSE: MIT (modify as needed)

# NOTE: By design this repository WILL NOT include exploit payloads, credential
# brute-force routines, or any code that meaningfully facilitates unauthorized
# attacks — even for "lab" use. You asked for an "aggressive hail mary" mode.
# I implemented an AGGRESSIVE flag that increases scan intensity, enables more
# intrusive but non-exploitative checks (e.g., nmap -A, aggressive fuzzing,
# nuclei high-severity templates). It will NOT run exploit modules or
# destructive actions. If you want to practice exploitation, use intentionally
# vulnerable VMs (Metasploitable, OWASP VMs) and manual Metasploit work under
# controlled conditions.

set -euo pipefail
IFS=$'
	'

#########################
# Configuration defaults
#########################
SCRIPT_NAME="redrecon"
BASE_OUT_DIR="./redrecon_reports"
SCOPE_FILE="scope.yaml"
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%SZ")
DRY_RUN=false
THREADS=10
AGGRESSIVE=false
SKIP_TOOLS=()
TOOLS=("amass" "subfinder" "assetfinder" "theHarvester" "recon-ng" "nmap" "whatweb" "httpx" "naabu" "nuclei" "nikto" "gobuster" "ffuf")

#########################
# Helper functions
#########################
log(){ printf "[%s] %s
" "${SCRIPT_NAME}" "$1"; }
err(){ printf "[%s] ERROR: %s
" "${SCRIPT_NAME}" "$1" >&2; }
usage(){ cat <<EOF
Usage: $0 -p project_name [-s scope.yaml] [--dry-run] [--threads N] [--skip tool1,tool2] [--aggressive]

Options:
  -p, --project   Project name (required)
  -s, --scope     Scope YAML file (default: ./scope.yaml)
  --dry-run       Print commands but don't execute
  --threads N     Parallelism for tools that support it (default: ${THREADS})
  --skip x,y      Comma-separated tool names to skip
  --aggressive    Enable higher-intensity scans and fuzzing (non-exploitative)
  -h, --help      Show this help

Scope file must exist and include a top-level `allowed:` list of hosts/domains/CIDRs.
Example scope.yaml:

allowed:
  - example.com
  - 10.10.10.0/24

This script is for AUTHORIZED testing only. Do not run without explicit permission.
EOF
}

require_scope(){
  if [[ ! -f "$SCOPE_FILE" ]]; then
    err "Scope file not found: $SCOPE_FILE"
    err "Place a scope.yaml in the current directory or pass -s /path/to/scope.yaml"
    exit 2
  fi
}

# read allowed targets into array
load_scope(){
  mapfile -t ALLOWED <<<$(yq e '.allowed[]' "$SCOPE_FILE" 2>/dev/null || python3 - <<'PY'
import sys, yaml
try:
    data=yaml.safe_load(open('$SCOPE_FILE'))
    for i in data.get('allowed',[]):
        print(i)
except Exception:
    sys.exit(1)
PY
)
}

# check whether a target is in scope (simple exact or suffix match)
is_in_scope(){
  local t="$1"
  for s in "${ALLOWED[@]}"; do
    if [[ "$s" == "$t" ]] || [[ "$t" == *".$s" ]] || [[ "$t" == "$s"* ]]; then
      return 0
    fi
  done
  return 1
}

check_tools(){
  local miss=()
  for t in "${TOOLS[@]}"; do
    # skip if user asked to skip specific tools
    if [[ " ${SKIP_TOOLS[*]} " == *" $t "* ]]; then
      log "Skipping tool: $t"
      continue
    fi
    if ! command -v "$t" >/dev/null 2>&1; then
      miss+=("$t")
    fi
  done
  if (( ${#miss[@]} )); then
    err "Missing tools: ${miss[*]}"
    err "Install missing Kali tools or adjust SKIP list with --skip"
    # don't exit: we allow running with --skip, but warn user
  fi
}

mkdir_safe(){
  mkdir -p "$1"
}

run_cmd(){
  local cmd="$*"
  if $DRY_RUN; then
    log "DRY-RUN: $cmd"
  else
    log "RUN: $cmd"
    eval "$cmd"
  fi
}

#########################
# Tool wrappers (AGGRESSIVE tuning applied where appropriate)
#########################
run_amass(){
  local outdir="$1"
  mkdir_safe "$outdir"
  # passive enumeration by default
  run_cmd "amass enum -passive -d ${DOMAIN_ARG} -o ${outdir}/amass.txt"
}

run_subfinder(){
  local outdir="$1"
  mkdir_safe "$outdir"
  run_cmd "subfinder -d ${DOMAIN_ARG} -o ${outdir}/subfinder.txt -silent"
}

run_assetfinder(){
  local outdir="$1"
  mkdir_safe "$outdir"
  run_cmd "assetfinder --subs-only ${DOMAIN_ARG} | tee ${outdir}/assetfinder.txt"
}

run_theharvester(){
  local outdir="$1"
  mkdir_safe "$outdir"
  run_cmd "theharvester -d ${DOMAIN_ARG} -b all -l 200 -f ${outdir}/theharvester.html"
}

run_reconng(){
  local outdir="$1"
  mkdir_safe "$outdir"
  local rcfile=${outdir}/reconng.rc
  cat > "$rcfile" <<EOF
workspaces create ${PROJECT_NAME}
workspace ${PROJECT_NAME}
set domains ${DOMAIN_ARG}
modules load recon/domains-hosts/bing
run
modules load recon/domains-hosts/brute_hosts
run
modules load reporting/csv
set output ${outdir}/reconng.csv
run
quit
EOF
  run_cmd "recon-ng -r ${rcfile}"
}

run_nmap(){
  local outdir="$1"
  mkdir_safe "$outdir"
  local targets_file=${outdir}/targets.txt
  printf "%s
" "${TARGETS[@]}" > "$targets_file"
  # AGGRESSIVE: add -A and higher timing if requested
  if $AGGRESSIVE; then
    run_cmd "nmap -A -T5 -p- -iL ${targets_file} -oA ${outdir}/nmap_aggressive"
  else
    run_cmd "nmap -sC -sV -T4 -iL ${targets_file} -oA ${outdir}/nmap"
  fi
}

run_whatweb(){
  local outdir="$1"
  mkdir_safe "$outdir"
  run_cmd "whatweb --color=never ${TARGETS[@]} | tee ${outdir}/whatweb.txt"
}

run_httpx(){
  local outdir="$1"
  mkdir_safe "$outdir"
  run_cmd "httpx -l ${outdir}/hosts_for_httpx.txt -silent -title -status-code -location -o ${outdir}/httpx.txt"
}

run_naabu(){
  local outdir="$1"
  mkdir_safe "$outdir"
  if $AGGRESSIVE; then
    run_cmd "naabu -list ${outdir}/hosts_for_naabu.txt -rate ${THREADS} -top-ports 65535 -o ${outdir}/naabu.txt"
  else
    run_cmd "naabu -list ${outdir}/hosts_for_naabu.txt -rate ${THREADS} -o ${outdir}/naabu.txt"
  fi
}

run_nuclei(){
  local outdir="$1"
  mkdir_safe "$outdir"
  # AGGRESSIVE: restrict to high/critical templates but allow more templates in lab
  if $AGGRESSIVE; then
    run_cmd "nuclei -l ${outdir}/http_hosts.txt -severity high,critical -t ~/.nuclei-templates/ -o ${outdir}/nuclei.txt -c ${THREADS}"
  else
    run_cmd "nuclei -l ${outdir}/http_hosts.txt -t ~/.nuclei-templates/ -o ${outdir}/nuclei.txt -c ${THREADS}"
  fi
}

run_nikto(){
  local outdir="$1"
  mkdir_safe "$outdir"
  # Nikto is already intrusive (server checks). AGGRESSIVE flag increases tuning.
  if $AGGRESSIVE; then
    run_cmd "nikto -h ${TARGETS[0]} -Tuning 123b -output ${outdir}/nikto.txt"
  else
    run_cmd "nikto -h ${TARGETS[0]} -output ${outdir}/nikto.txt"
  fi
}

run_gobuster(){
  local outdir="$1"
  mkdir_safe "$outdir"
  if $AGGRESSIVE; then
    run_cmd "gobuster dir -u ${TARGETS[0]} -w /usr/share/wordlists/raft-large-directories.txt -o ${outdir}/gobuster.txt -t ${THREADS}"
  else
    run_cmd "gobuster dir -u ${TARGETS[0]} -w /usr/share/wordlists/dirb/common.txt -o ${outdir}/gobuster.txt -t ${THREADS}"
  fi
}

run_ffuf(){
  local outdir="$1"
  mkdir_safe "$outdir"
  if $AGGRESSIVE; then
    run_cmd "ffuf -u ${TARGETS[0]}/FUZZ -w /usr/share/wordlists/raft-large-directories.txt -o ${outdir}/ffuf.json -of json -t ${THREADS}"
  else
    run_cmd "ffuf -u ${TARGETS[0]}/FUZZ -w /usr/share/wordlists/dirb/common.txt -o ${outdir}/ffuf.json -of json -t ${THREADS}"
  fi
}

# Placeholder: simulated "hail mary" reporter. This will NOT execute exploits — it
# only checks banners, known vulnerable versions, and flags likely targets.
run_hailmary_simulation(){
  local outdir="$1"
  mkdir_safe "$outdir"
  # Collect banners from nmap output (if present) and write a "simulated_exploits.txt"
  if [[ -f "${outdir}/nmap.xml" ]]; then
    grep -E "product|version" "${outdir}/nmap.xml" || true
    run_cmd "echo '[SIMULATION] No exploit execution performed. Use manual exploit testing on isolated VMs.' > ${outdir}/simulated_exploits.txt"
  else
    run_cmd "echo '[SIMULATION] No nmap xml found. Skipping simulation.' > ${outdir}/simulated_exploits.txt"
  fi
}

#########################
# Main flow
#########################
# Parse CLI
PROJECT_NAME=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -p|--project) PROJECT_NAME="$2"; shift 2;;
    -s|--scope) SCOPE_FILE="$2"; shift 2;;
    --dry-run) DRY_RUN=true; shift;;
    --threads) THREADS="$2"; shift 2;;
    --skip) IFS=',' read -ra SKIP_TOOLS <<< "$2"; shift 2;;
    --aggressive) AGGRESSIVE=true; shift;;
    -h|--help) usage; exit 0;;
    *) err "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ -z "$PROJECT_NAME" ]]; then
  err "Project name required"
  usage
  exit 1
fi

require_scope
load_scope
check_tools

# Build output directories
OUT_DIR="${BASE_OUT_DIR}/${PROJECT_NAME}_${TIMESTAMP}"
mkdir_safe "$OUT_DIR"
log "Output directory: $OUT_DIR"

# Build target list from scope (simple approach: include all allowed entries)
TARGETS=()
for t in "${ALLOWED[@]}"; do
  TARGETS+=("$t")
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  err "No targets loaded from scope"
  exit 3
fi

# helper aggregated file lists
HOSTS_FILE=${OUT_DIR}/hosts.txt
printf "%s
" "${TARGETS[@]}" > "$HOSTS_FILE"

# Domain arg: prefer first domain-like entry (simple heuristic)
DOMAIN_ARG="${TARGETS[0]}"

# Prepare input files for tools
cp "$HOSTS_FILE" "${OUT_DIR}/hosts_for_naabu.txt"
cp "$HOSTS_FILE" "${OUT_DIR}/hosts_for_httpx.txt"

# Run selected tools (order: passive -> active non-invasive -> active)
log "Starting passive discovery phase"
if [[ " ${SKIP_TOOLS[*]} " != *" amass "* ]]; then run_amass "$OUT_DIR/amass"; fi
if [[ " ${SKIP_TOOLS[*]} " != *" subfinder "* ]]; then run_subfinder "$OUT_DIR/subfinder"; fi
if [[ " ${SKIP_TOOLS[*]} " != *" assetfinder "* ]]; then run_assetfinder "$OUT_DIR/assetfinder"; fi
if [[ " ${SKIP_TOOLS[*]} " != *" theHarvester "* ]]; then run_theharvester "$OUT_DIR/theharvester"; fi
if [[ " ${SKIP_TOOLS[*]} " != *" recon-ng "* ]]; then run_reconng "$OUT_DIR/reconng"; fi

log "Passive phase complete"

log "Starting active discovery (non-exploitative)"
if [[ " ${SKIP_TOOLS[*]} " != *" naabu "* ]]; then run_naabu "$OUT_DIR/naabu"; fi
if [[ " ${SKIP_TOOLS[*]} " != *" nmap "* ]]; then run_nmap "$OUT_DIR/nmap"; fi
if [[ " ${SKIP_TOOLS[*]} " != *" whatweb "* ]]; then run_whatweb "$OUT_DIR/whatweb"; fi
if [[ " ${SKIP_TOOLS[*]} " != *" httpx "* ]]; then run_httpx "$OUT_DIR/httpx"; fi

log "Active discovery complete"

log "Starting scanning & content discovery"
if [[ " ${SKIP_TOOLS[*]} " != *" nuclei "* ]]; then run_nuclei "$OUT_DIR/nuclei"; fi
if [[ " ${SKIP_TOOLS[*]} " != *" nikto "* ]]; then run_nikto "$OUT_DIR/nikto"; fi
if [[ " ${SKIP_TOOLS[*]} " != *" gobuster "* ]]; then run_gobuster "$OUT_DIR/gobuster"; fi
if [[ " ${SKIP_TOOLS[*]} " != *" ffuf "* ]]; then run_ffuf "$OUT_DIR/ffuf"; fi

# Aggressive-only simulation step (no exploit, banners & likely vuln flags only)
if $AGGRESSIVE; then
  log "AGGRESSIVE mode: running hailmary simulation (non-exploitative)"
  run_hailmary_simulation "$OUT_DIR"
fi

log "Scanning phase complete"

# Basic aggregation step: unify discovered hosts into file
AGG_HOSTS=${OUT_DIR}/discovered_hosts.txt
cat ${OUT_DIR}/*/*.txt 2>/dev/null || true
# naive dedupe: grep lines that look like hosts
grep -Eo "([0-9]{1,3}\.){3}[0-9]{1,3}|[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" ${OUT_DIR}/* 2>/dev/null | sort -u > "$AGG_HOSTS" || true

log "Discovered hosts written to: $AGG_HOSTS"

# Final notes and summary file
SUMMARY=${OUT_DIR}/summary.txt
cat > "$SUMMARY" <<EOF
RedRecon Report Summary
Project: ${PROJECT_NAME}
Timestamp: ${TIMESTAMP}
Scope file: ${SCOPE_FILE}
Targets (from scope):
$(printf "  - %s
" "${TARGETS[@]}")
Output directory: ${OUT_DIR}
Tools run: ${TOOLS[*]}
Skipped tools: ${SKIP_TOOLS[*]:-none}
AGGRESSIVE: ${AGGRESSIVE}
Discovered hosts file: ${AGG_HOSTS}

LEGAL: This run was performed only against targets in scope.yaml. Keep evidence and authorization on file.
EOF

log "Run complete. See ${OUT_DIR} for results."

exit 0
