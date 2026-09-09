# Security

If you believe you have found a security vulnerability in Noetec, please report it privately rather than opening a public issue.

## Reporting a vulnerability

- **Preferred:** use GitHub's private vulnerability reporting — open the **Security** tab of the repository and choose **"Report a vulnerability"**. This keeps the report confidential and gives us a private channel to coordinate a fix.
- Alternatively, contact the maintainer directly (see [AUTHORS](AUTHORS)).

Please include as much detail as you can: the affected component, steps to reproduce, and (if possible) a proof of concept.

## Policy

- Do **not** publish or discuss an unpatched vulnerability publicly before a fix is released.
- We will acknowledge your report and keep you informed as we triage, fix, and release.

Noetec handles cryptography and synchronization (Ed25519 signatures, device identity, registries). The security model is described in [docs/specs/sync-security.md](docs/specs/sync-security.md).
