# Contributing

[**English**](CONTRIBUTING.md) · [Русский](CONTRIBUTING_RU.md)

Thanks for looking at Noetec! We welcome contributions of any size — a well-described
bug report is just as valuable as a polished feature. If you find something that
doesn't work as expected, the fastest way to help is to open an issue, even if you
never write a line of code.

By participating in this project, you agree to uphold our
[Code of Conduct](CODE_OF_CONDUCT.md). Please report unacceptable behavior to the
contact listed there.

## How this project is built

Noetec is a personal project developed in part with help from AI agents. All contributions
are reviewed before merging; the repository owner makes the final decision.

## Report a bug

Open a GitHub issue with the
[bug report template](https://github.com/LonelyGriffin/noetec/issues/new?template=bug_report.yml).
The template asks for:

- **Steps to reproduce** — the shortest sequence that triggers the bug.
- **Expected vs. actual behavior.**
- **Environment** — OS and app version or commit, if known. Include Flutter/Dart
  SDK versions when running from source.

The more specific the report, the easier it is to fix. If the bug is a security
issue (the app handles cryptography and sync), do **not** open a public issue —
follow [SECURITY.md](SECURITY.md) instead.

## Contribute a change

### 1. Discuss the change

Check existing issues before starting. If a relevant issue exists, read the
discussion and leave a comment saying you would like to work on it; check whether
someone is already doing so.

For substantial changes, open an issue using the bug or feature-request template
if needed, and agree on the approach with the repository owner before implementation.
Small fixes, such as typos or minor documentation corrections, can go straight to a PR.

### 2. Fork and branch

1. Fork the repository to your GitHub account (contributors with write access can
   create a branch in this repository).
2. Create a branch from `main` with a descriptive name, for example
   `42-fix-page-rename` for issue #42. No particular naming format is required.

### 3. Understand the codebase

Before making changes, read [`architecture.md`](architecture.md) — a
high-level map of the codebase. Follow [docs/README.md](README.md) to find
relevant requirements and architecture decisions.

### 4. Make the change

- The "why" behind each major decision lives in
  [decisions/](decisions/) (immutable ADRs — a change to an ADR is a new
  ADR, not an edit).
- Add appropriate tests for new or changed behavior. Unit/widget tests mirror
  `lib/` under `test/lib/`; integration scenarios live in `integration_test/`.
- Never edit generated files (`*.g.dart`, `*.freezed.dart`) — regenerate them with
  `dart run build_runner build` instead.
- No `print()` in production code — use `package:logging`.
- Update affected documentation when behavior, formats, or architectural decisions change.

### 5. Verify the change

For code changes:

- Regenerate code when required, then run `dart run scripts/lint.dart` and `flutter test`.
- Run relevant integration tests when the change affects user-facing workflows.
- Describe any manual checks and anything you could not verify in the PR.

For documentation-only changes, code checks, tests, and code generation are not
required. Instead:

- Check accuracy, links, paths, and command examples. Do not run destructive or
  state-changing commands just to validate an example.
- Check the rendered Markdown, especially tables and code blocks.
- Update existing translations.
- Run `git diff --check` and describe your checks in the PR.

### 6. Open a PR

Push your branch and open a pull request against `main`, filling in the PR
template (what changed, why, and how it was verified). Link the related issue,
if any; use `Closes #42` when the PR resolves it.

### 7. Review and merge

- The repository owner reviews the PR and makes the final decision on accepting changes.
- Address the feedback by pushing to the same branch — do not open a new PR.
- The repository owner merges PRs into `main`.

## Releasing

For user-visible changes, update `CHANGELOG.md` in the same PR.
Release mechanics are described in [release-process.md](release-process.md).

## Translations

Translations live next to the source document, with a language suffix added to
the filename, for example `README_RU.md`.

- When changing a document, update its existing translations in the same PR.
- At the start of each document, link to the available language versions,
  with the current language in bold.
- In translations, link to documents in the same language when available;
  otherwise, link to the source document.

## Set up the dev environment

Install a Flutter SDK whose bundled Dart version satisfies `environment.sdk` in
[pubspec.yaml](../pubspec.yaml).

```bash
git clone https://github.com/LonelyGriffin/noetec.git   # or your fork
cd noetec
flutter pub get
dart run build_runner build
dart run scripts/setup_project.dart   # installs the git pre-commit hook
```

The pre-commit hook automatically runs project checks before a commit.

### Day-to-day commands

All commands run from the repo root.

| Command | Purpose |
|---|---|
| `dart run scripts/format.dart` | Apply the project's code formatting |
| `dart run scripts/lint.dart` | Run code quality checks |
| `flutter test` | Run the unit/widget test suite (`test/`) |
| `dart run scripts/run_integration_tests.dart` | Run integration tests (`integration_test/`) |
| `dart run build_runner build` | Code generation (json_serializable, etc.) — run after changing serializable classes |

### Where to look

| You want to… | Read |
|---|---|
| Know what Noetec is and where it stands | [README.md](../README.md), [ROADMAP.md](product/ROADMAP.md) |
| Find where a piece of the system lives | [architecture.md](architecture.md) |
| Find documentation, requirements, and architecture decisions | [docs/README.md](README.md) |
| Releasing, versioning, and `CHANGELOG.md` | [release-process.md](release-process.md) |
