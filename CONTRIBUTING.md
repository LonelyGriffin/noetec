# Setup dev environment
1. As usual, clone the repository, set up Flutter, and install dependencies.
2. Run `dart ./scripts/setup_project.dart` to configure git hooks

## Understanding the codebase

Before making changes, read [`docs/architecture.md`](docs/architecture.md) — a
high-level map of where each concern lives (systems, DI, the data-flow loop), with
pointers to the ADRs and specs that define the why and the contract.

## Releasing

Noetec versions follow the process in
[`docs/release-process.md`](docs/release-process.md): the changelog
(`CHANGELOG.md`, Keep a Changelog) is updated in every user-visible PR, and a
release is a version bump + tag + GitHub Release cut from the changelog.
