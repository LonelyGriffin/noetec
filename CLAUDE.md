# Noetec

Entry point for AI coding agents. Keep this file lean: it is auto-injected into
every session, so it only holds always-true rules and pointers. Details live in
the docs referenced below — open them only when a task touches their area.

## Rules

- **Never run the app yourself** (`flutter run`, launch scripts, simulators). Use only e2e and unit tests.
- Never edit generated files (`*.g.dart`, `*.freezed.dart`) — regenerate via
  build_runner instead.
- No `print()` in production code — use `package:logging`.
- No `setState()` in view models — use the reactive `it` ecosystem
  (watch_it / listen_it / command_it).
- **Only Павел approves and merges.** Agents NEVER push to `main`, NEVER merge,
  NEVER approve, NEVER `git checkout main`. Branch protection on `main` enforces this.

## Commands

All commands run from the repo root.

| Command | Purpose |
|---|---|
| `dart run scripts/lint.dart` | Full lint: format check + `dart analyze` + copyright headers (changed files) |
| `dart run scripts/format.dart` | Format the project (page width 180 + trailing commas, from `formatter:` in `analysis_options.yaml`) |
| `dart analyze` | Static analysis (`analysis_options.yaml`, flutter_lints + extra rules) |
| `dart run scripts/setup_project.dart` | Install the git pre-commit hook (format + analyze + copyright on staged files) |
| `flutter test` | Run the unit/widget test suite (`test/`) |
| `dart run scripts/run_integration_tests.dart` | Run integration tests (`integration_test/`) — `--slow` / `--speed N` / `--hud-corner` add a human-watchable HUD; |
| `dart run build_runner build` | Code generation (json_serializable etc.) |
| `dart run build_runner watch` | Code generation in watch mode |

## Conventions

- DI: `get_it`, all registrations in `lib/app/configure_di.dart`.
- Services: `abstract interface class IXxxService` + `XxxServiceImpl` in one file.
- Tests mirror `lib/` under `test/lib/` (unit/widget — Developer, who runs the
  full `flutter test` suite before handoff); integration scenarios live in
  `integration_test/` (QA, for user-facing behavior) — QA commits and pushes its
  `integration_test/` changes to the branch it is testing. No tests for trivial
  logic; no duplicate coverage.
- Documentation lives in `docs/`; follow `docs/README.md` for its conventions.

## Where to look (progressive disclosure)

| When the task involves… | Read first |
|---|---|
| Finding the relevant part of the codebase | `docs/architecture.md` |
| User-facing behavior and acceptance scenarios | `docs/specs/` |
| Storage formats, protocols, and compatibility rules | `docs/contracts/` |
| Architectural choices and their rationale | `docs/decisions/` |
| Product goals, capabilities, and development direction | `docs/product/vision.md`, `docs/product/ROADMAP.md` |
| Releasing, versioning, tags, `CHANGELOG.md` entries | `docs/release-process.md` |
| Documentation boundaries, document status, where to put requirements | `docs/README.md` |

For directory entries, start with their README and follow relevant links.

If code disagrees with an accepted requirement, report the discrepancy rather than "fixing" the document to match code. Drafts, ambiguous status, or conflicts between documents require explicit review; directory placement is not approval.
