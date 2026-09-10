## What changed

<!-- A clear, concise description of the change and its scope. -->

## Why

<!-- The problem this solves or the motivation behind the change. Link the issue it closes, e.g. `Closes #123`. -->

## How tested

<!-- What you ran to verify the change: lint, format, tests, manual checks. -->

## Checklist

- [ ] I followed the project conventions in [CONTRIBUTING.md](CONTRIBUTING.md)
- [ ] I ran `dart run scripts/lint.dart` (format + analyze + copyright headers) and it passes
- [ ] I ran `flutter test` and all tests pass
- [ ] I regenerated code with `dart run build_runner build` when I touched models/interfaces
- [ ] I did not edit generated files (`*.g.dart`, `*.freezed.dart`)
- [ ] I updated the docs (specs/ADRs) when the contract or architecture changed
