# Elite Bug Bounty Framework v7.0 — OWASP 2025 Deep Edition

> **⚠️ LEGAL DISCLAIMER:** This tool is intended **exclusively** for authorized security testing on systems you have explicit written permission to test (e.g., HackerOne, Bugcrowd, Synack, or private engagements with written scope). Unauthorized use against any system is illegal under the Computer Fraud and Abuse Act (CFAA), UK Computer Misuse Act, and equivalent laws worldwide. The authors assume no liability for misuse.

---

## Overview

A fully automated, OWASP 2025–aligned bug bounty reconnaissance and vulnerability discovery framework. Designed for professional security researchers who test on authorized bug bounty programs.

```
  ELITE RECON v7.0 -- OWASP 2025 DEEP EDITION
  CTRL+C SKIP | 5-LAYER FP FILTER | WAF DETECT | FULL WORKFLOW
```

### Key Features

| Feature | Details |
|---|---|
| **Ctrl+C Phase-Skip** | 1st press saves partial data + skips to next phase. 2nd press aborts and saves checkpoint |
| **Resume Support** | `--resume <dir>` resumes from exact checkpoint |
| **5-Layer FP Filter** | Response → Code → Size → Reproducibility → Body content |
| **WAF Detection** | Auto-detects WAF and switches to bypass payload set |
| **16 Full Phases** | Recon → Fingerprint → Crawl → OWASP A01–A10 → Nuclei → Report |
| **Crash-Proof** | Every tool wrapped in `timeout` with graceful fallbacks |
| **Report Generation** | Markdown + JSON output with verified PoC blocks |

---

## OWASP 2025 Coverage

| ID | Category | Phase |
|---|---|---|
| A01 | Broken Access Control (IDOR, PrivEsc, UUID IDOR) | 5 |
| A02 | Security Misconfiguration (CORS, Headers, Cloud, Takeover) | 6, 13 |
| A03 | Supply Chain / Injection (SQLi, XSS, NoSQL, SSTI, LFI, XXE) | 7 |
| A04 | Cryptographic Failures (TLS, Exposed .git/.env) | 10 |
| A05 | Injection (CMDi, Prototype Pollution, DOM Sinks) | 7, 12 |
| A06 | Insecure Design (Race Conditions, Business Logic, Mass Assignment) | 9 |
| A07 | Authentication Failures (JWT, OAuth, Open Redirect) | 8 |
| A08 | Data Integrity Failures (JS API keys, Source Maps) | 12 |
| A09 | Logging & Alerting Failures (Brute-force protection) | 15 |
| A10 | Exceptional Conditions (Stack trace / exception leaks) | 15 |

---

## Installation

### Quick Install (Ubuntu/Debian/Kali)

```bash
git clone https://github.com/YOUR_USERNAME/elite-recon.git
cd elite-recon
chmod +x install.sh
sudo ./install.sh
```

### Manual Tool Installation

See [install.sh](install.sh) for the full automated install. Core dependencies:

**Required:**
```
curl wget python3 dig nmap nslookup
```

**Recommended (significantly improves results):**
```
amass subfinder assetfinder httpx dnsx
katana gospider nuclei gf arjun ffuf
waybackurls gauplus subjs jq interactsh-client
```

---

## Usage

### Basic Scan
```bash
bash elite_recon_v7.sh target.com
```

### Start From Specific Phase
```bash
bash elite_recon_v7.sh target.com --phase 5
```

### Resume Interrupted Scan
```bash
bash elite_recon_v7.sh --resume ./results_target.com_2025-06-01_10-30
```

### Full Deep Mode
```bash
bash elite_recon_v7.sh target.com --deep --cloud --oob --nuclei-all
```

### Rate-Limited (for strict programs)
```bash
bash elite_recon_v7.sh target.com --rate 30 --threads 15 --no-brute
```

### All Options

```
Options:
  --resume <dir>    Resume from last checkpoint
  --phase <N>       Start from phase N (1–16)
  --deep            Deep crawl + extended JS analysis (depth 7)
  --nuclei-all      Full nuclei template scan (slow, comprehensive)
  --no-brute        Skip DNS bruteforce
  --cloud           Cloud asset enumeration (S3, GCS, Azure)
  --asn             ASN/IP range discovery via BGPView
  --github          GitHub secret/subdomain search (requires GITHUB_TOKEN env var)
  --oob             Out-of-band SSRF via interactsh-client
  --rate <N>        Nuclei rate limit (default: 100 req/s)
  --threads <N>     HTTP probe threads (default: 50)
  --out <dir>       Custom output directory path
```

---

## Ctrl+C Behavior

```
1st Ctrl+C  →  Phase interrupted
              ├── All data collected SO FAR is written to output files
              ├── Checkpoint saved
              └── Scan continues from NEXT phase

2nd Ctrl+C  →  Scan aborted
              ├── Checkpoint saved with current phase number
              └── Resume later: bash elite_recon_v7.sh --resume <output_dir>
```

---

## Output Structure

```
results_TARGET_DATE/
├── .checkpoint                    ← Resume state
├── 01-recon/
│   ├── master_subdomains.txt      ← All unique subdomains
│   ├── master_alive.txt           ← DNS-resolved hosts
│   ├── master_web.txt             ← Live web targets
│   ├── master_urls.txt            ← Historical URLs
│   └── raw_sources/               ← Per-source subdomain lists
├── 02-fingerprint/
│   ├── httpx_full.txt             ← Full HTTP probe results
│   ├── tech_fingerprints.txt      ← Technology stack
│   └── waf_detected.txt           ← WAF-protected hosts
├── 03-endpoints/
│   ├── master_endpoints.txt       ← All discovered endpoints
│   ├── katana_crawl.txt
│   ├── js_internal_paths.txt
│   └── graphql_hints.txt
├── 04-parameters/
│   └── master_params.txt          ← All discovered parameters
├── 05-owasp/
│   ├── a01-access-control/        ← IDOR, PrivEsc findings
│   ├── a02-misconfig/             ← CORS, headers, takeover
│   ├── a04-crypto/                ← TLS, exposed files
│   ├── a05-injection/             ← SQLi, XSS, LFI, XXE, SSTI, NoSQL
│   ├── a06-design/                ← Race conditions, logic, mass assign
│   ├── a07-auth/                  ← JWT, OAuth, open redirects
│   ├── a09-logging/               ← Brute-force protection
│   └── a10-exceptions/            ← Exception leaks
├── 06-js-analysis/
│   ├── master_js.txt
│   ├── js_secrets.txt             ← Credentials in JS
│   ├── api_keys_found.txt         ← AWS/Stripe/Slack/GitHub keys
│   ├── sourcemaps_found.txt
│   ├── dom_sinks.txt
│   └── proto_pollution.txt
├── 07-cloud/
│   ├── all_ips.txt
│   ├── non_cf_ips.txt             ← Potential WAF bypass IPs
│   ├── bucket_findings.txt        ← S3/GCS misconfigs
│   ├── asn_ranges.txt
│   └── aws_metadata_hits.txt      ← SSRF → cloud metadata
├── 08-advanced/
│   └── gf_*.txt                   ← GF-pattern filtered endpoints
└── 09-reports/
    ├── verified_findings.txt      ← All PoC-confirmed vulnerabilities
    ├── all_findings.txt           ← Raw aggregated findings
    ├── report_TARGET_DATE.md      ← Full Markdown report
    └── summary_TARGET_DATE.json   ← Machine-readable JSON summary
```

---

## Phase Reference

| Phase | Name | Key Techniques |
|---|---|---|
| 1 | Passive Recon | amass, subfinder, assetfinder, crt.sh, OTX, RapidDNS, BufferOver, ThreatCrowd, wayback, gauplus |
| 2 | Live Host Detection | httpx probe, DNS resolution, Wayback/Gauplus URLs, non-CF IP detection |
| 3 | Endpoint Discovery | katana (JS rendering), gospider, JS extraction, source map detection, arjun params, ffuf |
| 4 | Fingerprint + WAF | Server headers, CMS detection, WAF probe, React/Angular/GraphQL detection |
| 5 | IDOR + Access Control | Integer ID enumeration, UUID/GUID IDOR, admin path access probing |
| 6 | Misconfiguration | CORS (5 origins), 6 security headers, clickjacking, S3/GCS buckets |
| 7 | Injection | SQLi (error + time-based), XSS, NoSQL, SSTI, LFI, XXE — WAF-bypass variants |
| 8 | Auth Failures | Open redirect, JWT (alg:none + weak secrets), OAuth redirect_uri bypass |
| 9 | Insecure Design | Race condition detection, boundary value testing, mass assignment |
| 10 | Crypto Failures | TLS version, cert expiry, self-signed, .git/.env/config exposure |
| 11 | SSRF | URL param injection, AWS/GCP/Azure metadata probing, OOB via interactsh |
| 12 | Advanced JS | Prototype pollution, DOM sinks, API key patterns (12 services) |
| 13 | Subdomain Takeover | 14-service fingerprint check + nuclei takeover templates |
| 14 | Nuclei | Critical/High + new templates + exposures + tech-specific + GF-targeted |
| 15 | Logging/Exceptions | Brute-force lockout, stack trace / exception leak detection |
| 16 | Report Generation | Markdown report, JSON summary, verified PoC file, severity buckets |

---

## Environment Variables

```bash
export GITHUB_TOKEN="ghp_..."        # GitHub recon (--github flag)
# interactsh is used directly when --oob is passed
```

---

## Wordlists

The tool uses SecLists for DNS brute-force and parameter discovery. Install:

```bash
# Kali Linux
sudo apt install seclists

# Manual install
sudo git clone https://github.com/danielmiessler/SecLists /usr/share/seclists
```

---

## False Positive Reduction

The 5-layer validation runs before any finding is written:

```
L1: Response received (not timeout / connection refused)
L2: HTTP status code matches expected
L3: Response body >= minimum bytes threshold
L4: Reproducible across two independent requests (0.4s gap)
L5: Body content is NOT a generic 404/error page
```

WAF-protected targets automatically switch to bypass payload variants, reducing both false positives and missed findings.

---

## Responsible Disclosure

When you find a valid vulnerability:

1. Do **not** access data beyond what is needed to prove the bug exists
2. Report through the program's disclosure channel (HackerOne, Bugcrowd, etc.)
3. Give the program reasonable time to fix before publishing
4. Follow the program's specific disclosure policy

---

## Contributing

Pull requests welcome. Areas that need improvement:

- Additional passive recon sources
- More WAF bypass payload variants
- GraphQL introspection / mutation testing module
- HTTP/2 request smuggling detection
- WebSocket endpoint testing
- Additional cloud provider metadata endpoints

---

## License

MIT License — see [LICENSE](LICENSE)

---

*For authorized security research only.*
