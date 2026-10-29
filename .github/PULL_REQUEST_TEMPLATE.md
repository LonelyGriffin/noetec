## What changed

<!-- A clear, concise description of the change and its scope. -->

## Why

<!-- The problem this solves or the motivation behind the change. Link the issue it closes, e.g. `Closes #123`. -->

## How tested

<!-- What you ran to verify the change: lint, format, tests, manual checks. -->

<!-- For documentation-only changes, code checks, tests, and code generation are not required. Mark non-applicable items as N/A and explain anything you could not verify. -->

## Checklist

- [ ] I followed the project conventions in [CONTRIBUTING.md](https://github.com/LonelyGriffin/noetec/blob/main/docs/CONTRIBUTING.md)
- [ ] For code changes, I ran `dart run scripts/lint.dart` and it passes
- [ ] For code changes, I ran `flutter test` and all tests pass
- [ ] I ran relevant integration tests when the change affects user-facing workflows
- [ ] I regenerated code with `dart run build_runner build` when required
- [ ] I did not edit generated files (`*.g.dart`, `*.freezed.dart`)
- [ ] I updated affected behavior specs, technical contracts, or ADRs when requirements or architecture changed (existing ADRs are immutable)
- [ ] For documentation changes, I checked accuracy, links, paths, command examples, Markdown rendering, and `git diff --check`
- [ ] I updated existing translations
- [ ] I updated `CHANGELOG.md` for user-visible changes
