# Elite Recon v7.0 — Makefile
# Usage: make <target>

SCRIPT    := elite_recon_v7.sh
SHELL     := /bin/bash
.PHONY    : all lint install test clean help

help:
	@echo "Targets:"
	@echo "  lint     — bash -n syntax check + shellcheck"
	@echo "  install  — run install.sh (requires root)"
	@echo "  pyinstall— pip install Python requirements"
	@echo "  test     — run syntax check and file verification"
	@echo "  clean    — remove scan result directories"

lint:
	@echo "[*] Bash syntax check..."
	@bash -n $(SCRIPT) && echo "  [+] Syntax OK"
	@command -v shellcheck &>/dev/null && \
	    shellcheck -S warning $(SCRIPT) && echo "  [+] Shellcheck OK" || \
	    echo "  [~] shellcheck not installed (optional)"

install:
	@[ "$$EUID" -eq 0 ] || { echo "[x] Run: sudo make install"; exit 1; }
	@bash install.sh

pyinstall:
	@pip3 install -r requirements.txt

test: lint
	@echo "[*] File check..."
	@for f in $(SCRIPT) README.md install.sh requirements.txt \
	           setup.py LICENSE CHANGELOG.md CONTRIBUTING.md \
	           config.example.yaml .gitignore; do \
	    [ -f "$$f" ] && echo "  [+] $$f" || { echo "  [x] Missing: $$f"; exit 1; }; \
	done
	@echo "[+] All checks passed"

clean:
	@echo "[*] Removing result directories..."
	@find . -maxdepth 1 -type d -name "results_*" -exec rm -rf {} + 2>/dev/null || true
	@find . -maxdepth 1 -type d -name "output_*"  -exec rm -rf {} + 2>/dev/null || true
	@echo "[+] Clean done"
