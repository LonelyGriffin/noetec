# Contributing

[**English**](CONTRIBUTING.md) · [Русский](CONTRIBUTING_RU.md)

Thanks for looking at Noetec! We welcome contributions of any size — a well-described
bug report is just as valuable as a polished feature. If you find something that
doesn't work as expected, the fastest way to help is to open an issue, even if you
never write a line of code.

By participating in this project, you agree to uphold our
[Code of Conduct](CODE_OF_CONDUCT.md). Please report unacceptable behavior to the
contact listed there.

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

Use the usual GitHub flow:

1. Check existing issues; discuss substantial changes before implementing them.
   Small fixes can go straight to a PR.
2. Create a branch from `main`, in a fork if needed. Use a descriptive name;
   no issue ID or naming scheme is required.
3. Make a focused change and run the applicable checks below.
4. Open a PR against `main` describing what changed, why, and how it was checked.
   Link related issues; use `Closes #42` when resolving a GitHub issue.
5. Address review feedback in the same branch. The repository owner reviews and
   merges PRs.

See [architecture.md](architecture.md) for the code map and
[docs/README.md](README.md) for requirements and decisions. The same contribution
workflow applies to human and AI-assisted changes.

## Project conventions

- The "why" behind each major decision lives in
  [decisions/](decisions/README.md). Keep these current; archive a replaced
  decision instead of keeping competing versions in the live catalog.
- Add appropriate tests for new or changed behavior. Unit/widget tests mirror
  `lib/` under `test/lib/`; integration scenarios live in `integration_test/`.
- Never edit generated files (`*.g.dart`, `*.freezed.dart`) — regenerate them with
  `dart run build_runner build` instead.
- No `print()` in production code — use `package:logging`.
- Update affected documentation when behavior, formats, or architectural decisions change.

## Checks

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
