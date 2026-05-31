# Contributing to Elite Recon v7.0

Thank you for your interest in contributing. This project is for authorized security research only.

## Code of Conduct

All contributions must align with responsible disclosure principles:
- Only submit code intended for authorized use on bug bounty programs
- Do not submit exploits targeting specific production systems
- Follow ethical security research standards

## How to Contribute

### Reporting Bugs

Open a GitHub Issue with:
1. Description of the bug
2. Steps to reproduce
3. Expected vs actual behaviour
4. Your OS, bash version, and tool versions (`bash --version`, `nuclei -version`)

### Submitting Pull Requests

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-improvement`
3. Make your changes with clear comments
4. Test on at least one authorized target (your own lab or a bug bounty program)
5. Submit a PR with a clear description of what changed and why

### Areas Where Contributions Are Welcome

- Additional passive subdomain sources
- More WAF bypass payload variants
- Additional OWASP vulnerability patterns
- Performance improvements
- Better false positive filtering logic
- Report formatting improvements
- Additional cloud provider metadata endpoints
- WebSocket testing module
- HTTP request smuggling detection
- GraphQL introspection and mutation testing
- Additional tech-specific Nuclei scan mappings

### Code Standards

- All bash code must pass `bash -n script.sh` (syntax check)
- Use `t_run <seconds> <command>` for all external tool calls
- Use `check_skip || break` inside loops to respect Ctrl+C
- Every new finding type must go through `fp_validate()` or equivalent filtering
- New findings must call `write_poc()` if exploitability is confirmed
- Add `end_phase N` and `save_checkpoint` at the end of new phases
- Follow existing variable naming conventions (UPPER_CASE globals, lower_case locals)

### Testing

Before submitting, verify:
```bash
# Syntax check
bash -n elite_recon_v7.sh

# Run phase 1 only against your own domain
bash elite_recon_v7.sh yourdomain.com --phase 1 --no-brute

# Test Ctrl+C skip works
bash elite_recon_v7.sh yourdomain.com
# Press Ctrl+C during Phase 1 — verify it skips to Phase 2
# Press Ctrl+C again — verify it saves checkpoint and exits
```

## Security Disclosure

If you find a security issue in this tool itself (e.g., command injection in argument parsing), open a GitHub Issue marked **[SECURITY]**. Do not publicly disclose critical issues without allowing time to fix.
