# Setup dev environment
1. As usual, clone the repository, set up Flutter, and install dependencies.
2. Run `dart ./scripts/setup_project.dart` to configure git hooks

## Understanding the codebase

Before making changes, read [`docs/architecture.md`](docs/architecture.md) — a
high-level map of where each concern lives (systems, DI, the data-flow loop), with
pointers to the ADRs and specs that define the why and the contract.
