# Changelog

All notable changes to Elite Recon are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [7.0.0] — 2025-06-01

### Added
- **Ctrl+C Phase-Skip System** — 1st press saves partial data and skips to next phase; 2nd press aborts with checkpoint saved
- `--resume <dir>` flag — resumes scan from exact last checkpoint
- **5-Layer False Positive Filter** — Response → HTTP Code → Content Size → Reproducibility → Body content check
- **WAF Auto-Detection** — detects WAF before injection tests; switches to bypass payload variants automatically
- **Rate-Limit Backoff** — detects 429/503 responses and backs off automatically
- Phase 4: Technology fingerprint + WAF detection phase (new, standalone)
- Phase 12: Advanced JS analysis — Prototype Pollution, DOM sinks, 12 API key patterns
- **UUID/GUID IDOR detection** (Phase 5)
- **NoSQL Injection** testing (Phase 7)
- **SSTI** (Server-Side Template Injection) testing with 5 engine probes (Phase 7)
- **XXE** (XML External Entity) testing (Phase 7)
- **OAuth redirect_uri bypass** testing (Phase 8)
- **JWT weak secret** brute-force against common secrets (Phase 8)
- **Mass Assignment** detection (Phase 9)
- **Business logic boundary value** testing (Phase 9)
- **Race condition candidate** detection with manual test template (Phase 9)
- **Prototype Pollution** parameter scanning (Phase 12)
- **DOM sink analysis** in JS files (Phase 12)
- **API key pattern matching** — 12 services (AWS, Stripe, Slack, GitHub, GitLab, SendGrid, Facebook, Square, Mailchimp) (Phase 12)
- **Source map detection** with source file extraction (Phase 3)
- **Non-Cloudflare IP detection** — identifies potential WAF bypass IPs (Phase 2)
- **OOB SSRF** via interactsh-client (`--oob` flag) (Phase 11)
- **ASN/IP range discovery** via BGPView API (`--asn` flag)
- **GitHub secret/subdomain search** (`--github` flag, requires GITHUB_TOKEN)
- **Tech-specific Nuclei scans** — WordPress, Jenkins, PHP, Spring, Grafana, Kubernetes, Elasticsearch, Drupal (Phase 14)
- **GF-pattern targeted Nuclei** — sqli, xss, ssrf, lfi, redirect patterns (Phase 14)
- **Brute-force lockout testing** — 12 rapid attempts to verify rate limiting (Phase 15)
- **Exception/stack trace leak** detection with 18 boundary values (Phase 15)
- **JSON report export** — full machine-readable summary (Phase 16)
- Verified PoC blocks with curl commands, impact, and steps to reproduce
- `write_poc()` function — structured PoC generation for all confirmed findings
- gospider integration for additional crawl coverage (Phase 3)
- Security headers audit — 6 expected headers + clickjacking detection (Phase 6)
- TLS/SSL analysis — weak versions, expired certs, self-signed (Phase 10)
- Parallel background job management with Ctrl+C kill support (Phase 1)
- 10+ passive subdomain sources: crt.sh, OTX, RapidDNS, BufferOver, ThreatCrowd, waybackurls, gauplus, amass, subfinder, assetfinder, hackertarget (Phase 1)
- `--out <dir>` flag for custom output directory
- `--h1 <url>` flag placeholder for HackerOne program URL
- Comprehensive `install.sh` for automated dependency installation
- `config.example.yaml` for configuration management
- `setup.py` for Python module installation

### Changed
- All tool invocations wrapped in `timeout` with `|| true` — no more crashes on tool failure
- `check_skip()` integrated into every loop — Ctrl+C respected everywhere
- Checkpoint saved after every `end_phase()` call — no data loss on interrupt
- Phase numbering restructured: 16 phases total (was 10)
- CORS testing expanded to 5 origin variants (was 2)
- SQLi payloads split into WAF-bypass and standard sets
- XSS payloads split into WAF-bypass and standard sets with content-type check
- IDOR testing now tests 5 offsets (+1, -1, +2, +100, +9999)
- DNS resolution uses dnsx with configurable resolvers file (fallback to dig)
- Cloud bucket names now include 12 variants per domain
- Subdomain takeover checks 14 service fingerprints (was 6)
- Report generation writes Markdown + JSON (was Markdown only)

### Fixed
- False positives from generic 404 pages now filtered at L5
- XSS false positives filtered by Content-Type: text/html check
- IDOR false positives filtered by response size and body content checks
- Stale output from failed tool runs no longer pollutes master files
- Heredoc encoding issues in banner resolved via Python-written header
- Duplicate function definitions from header/body concatenation removed

### Security
- All external API calls use `curl -sk` with explicit timeouts
- No credentials stored in output directories
- GITHUB_TOKEN read from environment variable only

---

## [6.0.0] — 2024-11-15

### Added
- OWASP 2021 coverage (A01–A10)
- 10 scan phases
- Nuclei integration
- Basic IDOR detection (integer IDs only)
- CORS testing (2 origins)
- SQLi error-based detection
- Reflected XSS detection
- JWT alg:none bypass
- Open redirect testing
- Subdomain takeover (6 service fingerprints)
- Markdown report generation
- Basic checkpoint system
- amass, subfinder, assetfinder, httpx, katana integration

### Known Issues (fixed in v7.0)
- Ctrl+C kills entire scan with no data preservation
- No WAF detection or bypass
- High false positive rate on IDOR
- No NoSQL, SSTI, XXE, or prototype pollution testing
- No JWT weak secret testing
- No OAuth testing
- No race condition detection
- Single passive subdomain source (no multi-source)

---

## [5.0.0] — 2024-06-01

### Added
- Initial public release
- Basic subdomain enumeration (amass + subfinder)
- HTTP probing (httpx)
- Simple endpoint crawl (katana)
- Basic SQLi and XSS probing
- Markdown report

