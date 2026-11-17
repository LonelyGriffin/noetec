# Noetec

Project instructions for coding agents, independent of the tool or platform.

- Follow the GitHub contribution workflow and project conventions in
  [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).
- Preserve existing work. Do not discard unrelated changes or switch branches in
  a workspace used by another task. Use separate worktrees or clones for parallel
  changes when needed; an already isolated workspace is sufficient.
- Commit, push, open PRs, or publish releases only when requested. Do not merge
  PRs or push directly to `main`; the repository owner merges.
- Never edit generated files (`*.g.dart`, `*.freezed.dart`); regenerate with
  `dart run build_runner build`.
- Use `package:logging`, not `print()`, in production code. Use the project's
  reactive systems and notifiers rather than introducing a ViewModel layer.
- Run the checks applicable to the change, as described in CONTRIBUTING. Report
  what changed, what was checked, and anything that could not be verified.

## Where to look

- [Documentation index](docs/README.md): requirements, contracts, decisions, and
  product direction. Accepted requirements govern their scope; drafts and code
  disagreements require review, not silently rewriting requirements to match code.
- [Architecture](docs/architecture.md): map of the current code.
- [Contributing](docs/CONTRIBUTING.md): setup, commands, tests, and GitHub workflow.
- [Release process](docs/release-process.md): versions, changelog, tags, and releases.
