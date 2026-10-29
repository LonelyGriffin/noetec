# Security

[**English**](SECURITY.md) · [Русский](SECURITY_RU.md)

If you believe you have found a security vulnerability in Noetec, please report
it privately using one of the channels below.

## Reporting a vulnerability

- Use GitHub's private vulnerability reporting, if available: open the
  **Security** tab of this repository and choose **"Report a vulnerability"**.
- Alternatively, or if that option is unavailable, email the repository owner
  at [lonelygriffin@gmail.com](mailto:lonelygriffin@gmail.com).

Please send the initial report through a private channel, not a public issue,
pull request, or discussion.

## What to include

- A description of the problem and its potential security impact.
- The affected component, app version or commit, and relevant environment details,
  if known.
- Steps to reproduce. A minimal example demonstrating the problem is helpful,
  but not required.

Do not include private keys, seed phrases, tokens, passwords, or personal notes.
Use synthetic data where possible. Do not test against other people's data or
systems without permission.

## Scope and supported versions

Reports should concern the security of Noetec, including issues that could expose
data, bypass security checks, allow unauthorized changes, or cause denial of
service when processing crafted content. Scope is not limited to particular
source directories or security mechanisms.

Vulnerabilities in third-party dependencies or services are generally fixed by
their upstream maintainers. If an issue affects Noetec or relates to how the
project uses or configures those components, please also report it here.
If you are unsure whether an issue belongs here, report it privately; we will
help identify the appropriate next steps where possible.

Security fixes are released in the current version; backports to older versions
are not guaranteed. If possible, check whether the issue still occurs in the
latest version or on `main`, but this is not a condition for reporting it.

## Handling and disclosure

The repository owner reviews reports as time permits. Assessment and remediation
times depend on the complexity of the issue; no response or fix deadline is
guaranteed. We will keep you informed about the assessment and any fix or release.

Please give us an opportunity to assess the issue before publishing technical
details. We aim to coordinate disclosure with you, taking into account user risk,
available mitigations, and the readiness of a fix. A released fix is not the only
possible basis for disclosure: users may need earlier warnings or protective
measures.

If a fix is delayed or not feasible, we will let you know and discuss possible
mitigations and next steps.

## Rewards and credit

We do not offer monetary bounties. With your consent, we may acknowledge your
contribution in the release notes using an agreed name or pseudonym. You may
also choose not to be mentioned publicly.
