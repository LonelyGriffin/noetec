# Contributing

Thanks for looking at Noetec! We welcome contributions of any size — a well-described
bug report is just as valuable as a polished feature. If you find something that
doesn't work as expected, the fastest way to help is to open an issue, even if you
never write a line of code.

By participating in this project, you agree to uphold our
[Code of Conduct](CODE_OF_CONDUCT.md). Please report unacceptable behavior to the
contact listed there.

## How this project is built

Noetec is a personal project, and part of the day-to-day development is done by AI
agents working from the in-repo documentation. That changes nothing for you: human
contributions go through the exact same review. Every PR — written by a person or by
an agent — is reviewed on GitHub the same way before it can be merged.

## Report a bug

Open a GitHub issue with the
[bug report template](https://github.com/LonelyGriffin/noetec/issues/new?template=bug_report.yml).
The template asks for:

- **Steps to reproduce** — the shortest sequence that triggers the bug.
- **Expected vs. actual behavior.**
- **Environment** — OS, app version, and Flutter/Dart SDK versions.

The more specific the report, the easier it is to fix. If the bug is a security
issue (the app handles cryptography and sync), do **not** open a public issue —
follow [SECURITY.md](SECURITY.md) instead.

## Contribute a change

### 1. Open an issue first

Before writing code, open an issue describing the problem or the feature (use the
bug or feature-request template). This makes sure the direction is right and the
work is not duplicated. If an issue already exists, skip straight to step 2.

### 2. Fork and branch

1. Fork the repository to your GitHub account (contributors with write access can
   branch `main` directly).
2. Create a branch for the issue. The repo convention is one branch per issue,
   named after the issue key (e.g. `NOET-42`).

### 3. Understand the codebase

Before making changes, read [`docs/architecture.md`](docs/architecture.md) — a
high-level map of where each concern lives (systems, DI, the data-flow loop), with
pointers to the ADRs and specs that define the why and the contract.

### 4. Make the change

- The "why" behind each major decision lives in
  [docs/decisions/](docs/decisions/) (immutable ADRs — a change to an ADR is a new
  ADR, not an edit).
- Add unit/widget tests mirroring `lib/` under `test/` for new behavior.
- Never edit generated files (`*.g.dart`, `*.freezed.dart`) — regenerate them with
  `dart run build_runner build` instead.
- No `print()` in production code — use `package:logging`.

### 5. Open a PR

Push your branch and open a pull request against `main`, filling in the PR
template (what changed, why, and how it was tested).

### 6. Review and merge

- The project architect reviews the PR for architecture and approach; you will get
  inline comments and a verdict on the PR.
- Address the feedback by pushing to the same branch — do not open a new PR.
- Only the project owner merges to `main`; branch protection enforces this, so a
  PR is never self-merged, however small the change.

## Releasing

Noetec versions follow the process in
[`docs/release-process.md`](docs/release-process.md): the changelog
(`CHANGELOG.md`, Keep a Changelog) is updated in every user-visible PR, and a
release is a version bump + tag + GitHub Release cut from the changelog.

## Set up the dev environment

Prerequisite: a recent Flutter SDK (Dart 3.10 or later).

```bash
git clone https://github.com/LonelyGriffin/noetec.git   # or your fork
cd noetec
flutter pub get
dart run build_runner build
dart run scripts/setup_project.dart   # installs the git pre-commit hook
```

The pre-commit hook runs formatting, scoped static analysis, and a copyright-header
check on staged files, so most issues are caught before you ever commit.

### Day-to-day commands

All commands run from the repo root.

| Command | Purpose |
|---|---|
| `dart run scripts/format.dart` | Format the project (page width 180 + trailing commas, from `formatter:` in `analysis_options.yaml`) |
| `dart run scripts/lint.dart` | Full lint: format check + `dart analyze` + copyright headers |
| `flutter test` | Run the unit/widget test suite (`test/`) |
| `dart run build_runner build` | Code generation (json_serializable, etc.) — run after changing serializable classes |

### Where to look

| You want to… | Read |
|---|---|
| Know what Noetec is and where it stands | [README.md](README.md), [ROADMAP.md](ROADMAP.md) |
| Find where a piece of the system lives | [docs/architecture.md](docs/architecture.md) |
| Understand why the system is designed this way | [docs/decisions/](docs/decisions/) (immutable ADRs) |
| See the normative behavior specs | [docs/specs/](docs/specs/) |
| Releasing, versioning, and `CHANGELOG.md` | [docs/release-process.md](docs/release-process.md) |
| See project rules, stack, and all commands | [CLAUDE.md](CLAUDE.md) |
