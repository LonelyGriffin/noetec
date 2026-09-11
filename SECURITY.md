# Security

Noetec is a local-first notes app that handles cryptography and synchronization
(Ed25519 signatures, device identity, registries — see
[docs/specs/sync-security.md](docs/specs/sync-security.md)). If you believe you
have found a security vulnerability, please report it privately rather than
opening a public issue.

## Reporting a vulnerability

- **Preferred:** use GitHub's private vulnerability reporting — open the
  **Security** tab of this repository and choose **"Report a vulnerability"**.
  This keeps the report confidential and gives us a private channel to
  coordinate a fix.
- Alternatively, contact the maintainer directly (see [AUTHORS](AUTHORS)).

Please do not report security issues in public issues, pull requests, or
discussions. Include as much detail as you can: the affected component and
version, steps to reproduce, and (if possible) a proof of concept.

## Scope

**In scope:**

- The app code in this repository (`lib/`, `test/`, `integration_test/`),
  including the sync security implementation: Ed25519 OpLog signatures,
  device/user registries, witness fields, and TOFU key pinning.
- The local storage of secrets and keys (`flutter_secure_storage`-based
  storage) and the vault/persistence layer.
- The on-disk Markdown and block-format parsers — a maliciously crafted note
  file or synced payload that triggers parser behavior is a valid report.
- The sync merge and conflict-resolution logic.

**Out of scope:**

- Third-party dependencies (the Flutter SDK and pub packages). Please report
  vulnerabilities in those to their upstream maintainers.
- Your own sync infrastructure: self-hosted sync servers, Git hosts, Dropbox
  or other file-sync services, and network paths outside the app.
- Features of the GitHub platform itself (repositories, CI) beyond the code in
  this repository.

If a report is out of scope, we will say so and, where possible, point you to
the right place.

## What to expect

- **Acknowledgement:** we aim to acknowledge your report within **3 business
  days**. Noetec is a personal project maintained by a solo developer, so
  triage may take longer — any response we send, even a short one, confirms
  the report was received.
- **Disclosure timeline:** we follow coordinated disclosure. A vulnerability
  will **not** be discussed or published publicly before a fix is released.
  Once the fix ships, you will be notified, and we will acknowledge your
  contribution in the release notes (anonymously if you prefer).
- **If a fix is not feasible in time:** before any public disclosure, we will
  notify you so you can take your own precautions.

## Policy

- Do **not** publish, disclose, or discuss an unpatched vulnerability publicly
  before a fix is released.
- We will keep you informed as we triage, fix, and release.
- We do not offer monetary bounties; credit is given in the release notes and
  this file's acknowledgements at your discretion.
