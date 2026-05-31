#!/bin/bash
# ══════════════════════════════════════════════════════════════════════════════
# ELITE RECON v7.0 — AUTOMATED TOOL INSTALLER
# Supports: Ubuntu 20.04+, Debian 11+, Kali Linux, ParrotOS
# Run as root or with sudo
# ══════════════════════════════════════════════════════════════════════════════

set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log_info()    { printf "${CYAN}  [*]${NC} %s\n" "$1"; }
log_success() { printf "${GREEN}  [+]${NC} %s\n" "$1"; }
log_warn()    { printf "${YELLOW}  [!]${NC} %s\n" "$1"; }
log_skip()    { printf "${YELLOW}  [-]${NC} %s (already installed)\n" "$1"; }

need_root() { [ "$(id -u)" -eq 0 ] || { echo -e "${RED}[x] Run as root or with sudo${NC}"; exit 1; }; }
need_root

printf "\n${BOLD}  ELITE RECON v7.0 — INSTALLER${NC}\n\n"

# ── OS Detection ──────────────────────────────────────────────────────────────
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    OS="unknown"
fi

# ── Go version check ──────────────────────────────────────────────────────────
install_go() {
    command -v go &>/dev/null && {
        GO_VER=$(go version | grep -oP 'go\d+\.\d+' | head -1)
        log_skip "Go ($GO_VER)"
        return
    }
    log_info "Installing Go 1.22..."
    GO_URL="https://go.dev/dl/go1.22.3.linux-amd64.tar.gz"
    wget -q "$GO_URL" -O /tmp/go.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf /tmp/go.tar.gz
    rm /tmp/go.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    # Add to profile
    grep -q "go/bin" /etc/profile || echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile
    grep -q "go/bin" ~/.bashrc   || echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
    export GOPATH="$HOME/go"
    export PATH=$PATH:$GOPATH/bin
    log_success "Go installed"
}

setup_go_path() {
    export PATH=$PATH:/usr/local/go/bin
    export GOPATH="${GOPATH:-$HOME/go}"
    export PATH=$PATH:$GOPATH/bin
    mkdir -p "$GOPATH/bin"
}

# ── APT base packages ─────────────────────────────────────────────────────────
log_info "APT base packages..."
apt-get update -qq
apt-get install -y -qq \
    curl wget git nmap dnsutils python3 python3-pip \
    build-essential libssl-dev zip unzip jq \
    2>/dev/null
log_success "APT base packages"

# ── Go install ────────────────────────────────────────────────────────────────
install_go
setup_go_path

# ── Go-based tools ────────────────────────────────────────────────────────────
install_go_tool() {
    local name="$1" module="$2"
    if command -v "$name" &>/dev/null; then
        log_skip "$name"
    else
        log_info "Installing $name..."
        go install "${module}@latest" 2>/dev/null && \
            log_success "$name" || log_warn "$name install failed"
    fi
}

install_go_tool "subfinder"       "github.com/projectdiscovery/subfinder/v2/cmd/subfinder"
install_go_tool "assetfinder"     "github.com/tomnomnom/assetfinder"
install_go_tool "httpx"           "github.com/projectdiscovery/httpx/cmd/httpx"
install_go_tool "dnsx"            "github.com/projectdiscovery/dnsx/cmd/dnsx"
install_go_tool "katana"          "github.com/projectdiscovery/katana/cmd/katana"
install_go_tool "nuclei"          "github.com/projectdiscovery/nuclei/v3/cmd/nuclei"
install_go_tool "waybackurls"     "github.com/tomnomnom/waybackurls"
install_go_tool "gf"              "github.com/tomnomnom/gf"
install_go_tool "subjs"           "github.com/lc/subjs"
install_go_tool "ffuf"            "github.com/ffuf/ffuf/v2"
install_go_tool "gospider"        "github.com/jaeles-project/gospider"
install_go_tool "interactsh-client" "github.com/projectdiscovery/interactsh/cmd/interactsh-client"

# ── gauplus ───────────────────────────────────────────────────────────────────
if command -v gauplus &>/dev/null; then
    log_skip "gauplus"
else
    log_info "Installing gauplus..."
    go install github.com/bp0lr/gauplus@latest 2>/dev/null && \
        log_success "gauplus" || log_warn "gauplus install failed"
fi

# ── amass ─────────────────────────────────────────────────────────────────────
if command -v amass &>/dev/null; then
    log_skip "amass"
else
    log_info "Installing amass..."
    case "$OS" in
        kali|parrot)
            apt-get install -y -qq amass && log_success "amass" || \
            { go install github.com/owasp-amass/amass/v4/...@latest 2>/dev/null && log_success "amass (go)"; } || \
            log_warn "amass install failed"
            ;;
        *)
            go install github.com/owasp-amass/amass/v4/...@latest 2>/dev/null && \
                log_success "amass" || log_warn "amass install failed"
            ;;
    esac
fi

# ── arjun ─────────────────────────────────────────────────────────────────────
if command -v arjun &>/dev/null; then
    log_skip "arjun"
else
    log_info "Installing arjun..."
    pip3 install arjun -q && log_success "arjun" || log_warn "arjun install failed"
fi

# ── GF patterns ───────────────────────────────────────────────────────────────
GF_DIR="$HOME/.gf"
if [ -d "$GF_DIR" ] && [ "$(ls -A "$GF_DIR" 2>/dev/null | wc -l)" -gt 5 ]; then
    log_skip "gf patterns"
else
    log_info "Installing gf patterns..."
    mkdir -p "$GF_DIR"
    git clone --quiet https://github.com/tomnomnom/gf "$GF_DIR/gf-src" 2>/dev/null || true
    cp "$GF_DIR/gf-src/examples/"*.json "$GF_DIR/" 2>/dev/null || true
    git clone --quiet https://github.com/1ndianl33t/Gf-Patterns "$GF_DIR/gf-patterns-src" 2>/dev/null || true
    cp "$GF_DIR/gf-patterns-src/"*.json "$GF_DIR/" 2>/dev/null || true
    log_success "gf patterns"
fi

# ── Nuclei templates ─────────────────────────────────────────────────────────
NUCLEI_TPL="$HOME/nuclei-templates"
if [ -d "$NUCLEI_TPL" ] && [ "$(find "$NUCLEI_TPL" -name '*.yaml' | wc -l)" -gt 100 ]; then
    log_skip "nuclei-templates ($(find "$NUCLEI_TPL" -name '*.yaml' | wc -l) templates)"
else
    log_info "Downloading nuclei templates..."
    nuclei -update-templates -silent 2>/dev/null && log_success "nuclei-templates" || {
        git clone --quiet --depth 1 \
            https://github.com/projectdiscovery/nuclei-templates.git "$NUCLEI_TPL" \
            && log_success "nuclei-templates (git)"
    }
fi

# ── SecLists ──────────────────────────────────────────────────────────────────
SECLISTS_DIR="/usr/share/seclists"
if [ -d "$SECLISTS_DIR" ] && [ "$(ls -A "$SECLISTS_DIR" 2>/dev/null | wc -l)" -gt 10 ]; then
    log_skip "seclists"
else
    log_info "Installing seclists..."
    case "$OS" in
        kali|parrot)
            apt-get install -y -qq seclists 2>/dev/null && log_success "seclists" || \
            { git clone --quiet --depth 1 https://github.com/danielmiessler/SecLists "$SECLISTS_DIR" && log_success "seclists (git)"; }
            ;;
        *)
            git clone --quiet --depth 1 \
                https://github.com/danielmiessler/SecLists "$SECLISTS_DIR" \
                && log_success "seclists" || log_warn "seclists install failed"
            ;;
    esac
fi

# ── DNS resolvers ─────────────────────────────────────────────────────────────
RESOLVERS_FILE="/root/resolvers.txt"
if [ -f "$RESOLVERS_FILE" ] && [ "$(wc -l < "$RESOLVERS_FILE")" -gt 10 ]; then
    log_skip "resolvers.txt"
else
    log_info "Downloading trusted DNS resolvers..."
    curl -sL \
        "https://raw.githubusercontent.com/trickest/resolvers/main/resolvers.txt" \
        -o "$RESOLVERS_FILE" 2>/dev/null && \
        log_success "resolvers.txt ($(wc -l < "$RESOLVERS_FILE") resolvers)" || \
        log_warn "resolvers download failed"
fi

# ── PATH persistence ──────────────────────────────────────────────────────────
log_info "Updating PATH in shell configs..."
for rc in /root/.bashrc /root/.zshrc /home/*/.bashrc /home/*/.zshrc; do
    [ -f "$rc" ] || continue
    grep -q 'go/bin' "$rc" || \
        echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> "$rc"
done

# ── Summary ───────────────────────────────────────────────────────────────────
printf "\n${BOLD}  Installation complete! Verification:${NC}\n\n"
for tool in amass subfinder assetfinder httpx dnsx katana nuclei \
            waybackurls gf subjs ffuf gospider interactsh-client \
            arjun gauplus dig nmap curl python3; do
    command -v "$tool" &>/dev/null \
        && printf "  ${GREEN}[+]${NC} %-25s %s\n" "$tool" "$(command -v "$tool")" \
        || printf "  ${RED}[x]${NC} %-25s MISSING\n" "$tool"
done

printf "\n${YELLOW}  NOTE: Run 'source ~/.bashrc' or open a new terminal before using the tool.${NC}\n\n"
