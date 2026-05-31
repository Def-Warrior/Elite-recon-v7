# Usage Examples — Elite Recon v7.0

All examples assume you have explicit written authorization to test the target.

---

## Quick Start

```bash
# Clone and install
git clone https://github.com/YOUR_USERNAME/elite-recon.git
cd elite-recon
sudo ./install.sh
source ~/.bashrc

# Run a full scan
bash elite_recon_v7.sh example.com
```

---

## Phase-Specific Runs

```bash
# Recon only (Phase 1–2)
bash elite_recon_v7.sh example.com --phase 1 --no-brute

# Start from endpoint discovery (skip recon)
bash elite_recon_v7.sh example.com --phase 3

# Injection testing only (Phase 7)
bash elite_recon_v7.sh example.com --phase 7

# Auth testing only (Phase 8)
bash elite_recon_v7.sh example.com --phase 8

# Nuclei only (Phase 14)
bash elite_recon_v7.sh example.com --phase 14 --nuclei-all
```

---

## Resume an Interrupted Scan

```bash
# After pressing Ctrl+C twice (scan aborted), resume from checkpoint
bash elite_recon_v7.sh --resume ./results_example.com_2025-06-01_10-30

# Checkpoint file shows which phase to resume from
cat ./results_example.com_2025-06-01_10-30/.checkpoint
```

---

## Bug Bounty Program Modes

```bash
# Conservative mode (low rate, no brute — for strict programs)
bash elite_recon_v7.sh example.com \
    --rate 20 \
    --threads 10 \
    --no-brute

# Full mode with cloud and OOB SSRF
bash elite_recon_v7.sh example.com \
    --deep \
    --cloud \
    --oob \
    --nuclei-all \
    --asn

# With GitHub token for source code recon
GITHUB_TOKEN="ghp_your_token" \
bash elite_recon_v7.sh example.com --github

# Custom output directory
bash elite_recon_v7.sh example.com \
    --out /tmp/bounty/example_$(date +%F)
```

---

## Reading Reports

```bash
# View verified findings immediately
cat results_*/09-reports/verified_findings.txt

# View Markdown report
cat results_*/09-reports/report_*.md

# Parse JSON summary with jq
jq '.findings' results_*/09-reports/summary_*.json
jq '.vulnerabilities.sqli' results_*/09-reports/summary_*.json
jq '.scope.subdomains_total' results_*/09-reports/summary_*.json

# Quick stats
jq '{critical:.findings.critical, high:.findings.high, medium:.findings.medium}' \
    results_*/09-reports/summary_*.json
```

---

## Ctrl+C Workflow

```
Scenario: Phase 2 is at 70% — you need to move on quickly

1. Press Ctrl+C once
   → "[CTRL+C] Phase 2 interrupted — partial data saved."
   → All hosts discovered SO FAR are written to master_alive.txt
   → Scan moves automatically to Phase 3

2. Phase 3 starts using whatever Phase 2 collected

3. If you need to stop completely:
   → Press Ctrl+C a second time during any phase
   → "[ABORT] Scan aborted by user."
   → Checkpoint saved showing current phase number
   → Resume later: bash elite_recon_v7.sh --resume <dir>
```

---

## Output Files Quick Reference

| File | Contents |
|---|---|
| `01-recon/master_subdomains.txt` | All unique subdomains found |
| `01-recon/master_web.txt` | Live HTTP/HTTPS hosts |
| `03-endpoints/master_endpoints.txt` | All discovered URLs |
| `06-js-analysis/api_keys_found.txt` | API keys found in JS |
| `05-owasp/a04-crypto/exposed_files.txt` | Exposed .git/.env/config files |
| `05-owasp/a01-access-control/idor_findings.txt` | IDOR findings |
| `05-owasp/a05-injection/sqli_findings.txt` | SQL injection findings |
| `09-reports/verified_findings.txt` | All confirmed findings with PoCs |
| `09-reports/report_*.md` | Full Markdown report |
| `09-reports/summary_*.json` | Machine-readable JSON summary |

---

## Environment Variables

```bash
# GitHub token for code search (Phase 1 --github mode)
export GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"

# Optional: custom nuclei templates directory
export NUCLEI_TEMPLATES="/path/to/custom/templates"
```
