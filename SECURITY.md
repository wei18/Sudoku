# Security Policy

This is a public repository and has been public since its first commit. No
secret, PII, or identifiable player data may appear in any commit.

## Supported versions

This is a portfolio monorepo for two apps (Sudoku and Minesweeper), not a
distributed library. Security fixes are applied to the latest `main` only;
there are no maintained release branches.

| Version | Supported |
|---|---|
| `main` (latest) | ✅ |
| Older tags / commits | ❌ |

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue for a
suspected vulnerability.

1. Go to the repository's **Security** tab.
2. Choose **Report a vulnerability** to open a private security advisory
   (GitHub Security Advisories).

This keeps the report private between you and the maintainer until a fix is
ready. You'll get a response as soon as the solo maintainer is able to triage
it.

## Existing security posture

The repo already runs defence-in-depth against secret leaks (see
[`docs/foundations.md §7`](docs/foundations.md)):

- **GitHub secret scanning + push protection** — enabled; Apple-issued secret
  patterns auto-revoke via GitHub's partner program.
- **Dependabot** — enabled for dependency vulnerability alerts.
- **`.gitignore` blocklist** — `secrets/**`, `*.pem`, `*.p8`, `*.p12`,
  `*.mobileprovision`, `.env*`, and the signing / AdMob xcconfigs are never
  committed.
- **Pre-commit gitleaks** — a lefthook pre-commit hook runs gitleaks (via mise)
  over staged files (`mise run scan:secrets`), plus a repo-hygiene scan
  (`mise run scan:hygiene`).
- **App-public-but-sensitive identifiers** (e.g. AdMob IDs) are injected at
  build time via gitignored xcconfigs rather than committed.

If a secret is ever exposed, it is treated as **already leaked**: it is rotated
first, then history is cleaned. Cleaning history is not the stop-bleed —
rotation is.
