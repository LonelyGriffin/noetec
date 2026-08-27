# Noetec

Entry point for AI coding agents. Keep this file lean: it is auto-injected into
every session, so it only holds always-true rules and pointers. Details live in
the docs referenced below — open them only when a task touches their area.

## Language rules

- **Chat responses: Russian.**
- **Code comments and documentation: English.**
- **Implementation plans: Russian.**

## Hard rules

- **Never run the app yourself** (`flutter run`, launch scripts, simulators).
  The user runs it manually to verify it starts.
- Never edit generated files (`*.g.dart`, `*.freezed.dart`) — regenerate via
  build_runner instead.
- No `print()` in production code — use `package:logging`.
- No `setState()` in view models — use the reactive `it` ecosystem
  (watch_it / listen_it / command_it).

## Commands

All commands run from the repo root.

| Command | Purpose |
|---|---|
| `dart run scripts/lint.dart` | Full lint: format check + `dart analyze` + copyright headers (changed files) |
| `dart run scripts/format.dart` | Format the project (page width 180, from `dart-format.yaml`) |
| `dart analyze` | Static analysis (`analysis_options.yaml`, flutter_lints + extra rules) |
| `flutter test` | Run the unit/widget test suite (`test/`) |
| `dart run build_runner build` | Code generation (json_serializable etc.) |
| `dart run build_runner watch` | Code generation in watch mode |

## Conventions

- DI: `get_it`, all registrations in `lib/app/configure_di.dart`.
- Services: `abstract interface class IXxxService` + `XxxServiceImpl` in one file.
- Tests mirror `lib/` under `test/lib/`; integration scenarios live in
  `integration_test/`. No tests for trivial logic; no duplicate coverage.
- Docs are the contract: specs under `docs/specs/` are normative (RFC 2119),
  decisions under `docs/decisions/` are immutable ADRs (supersede with a new
  ADR, never edit).

## Where to look (progressive disclosure)

| When the task involves… | Read first |
|---|---|
| Markdown parser/serializer, frontmatter, page file format, block IDs | `docs/specs/file-format.md` |
| Why unidirectional data flow / no setState / command pattern | `docs/decisions/0001-flux-unidirectional-data-flow.md` |
| Block ID syntax (`::: {#id}` directives) | `docs/decisions/0002-block-ids-via-fenced-directives.md` |
| Frontmatter fields, device identity, `modified_by` | `docs/decisions/0003-no-device-identity-until-sync.md` |
| Storage layout, why plain `.md` files, local-first | `docs/decisions/0004-local-first-markdown-file-storage.md` |
| DI container choice, get_it/watch_it/listen_it ecosystem | `docs/decisions/0005-get-it-di-ecosystem.md` |
| Product capabilities, roadmap, what/why of the project | `docs/product/vision.md` |
| Vault user workflow end-to-end | `docs/specs/01-vault-user-workflow.spec` |
| Sync encryption and security design | `docs/SYNC_SECURITY_STRATEGY.md` |

If a referenced doc and the code disagree, the spec is right and the code has a
bug — report it rather than "fixing" the doc.
