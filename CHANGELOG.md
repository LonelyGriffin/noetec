# Changelog

All notable changes to the Noetec project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

This project keeps its changelog from the very first release: the first version
heading (`## [X.Y.Z] - YYYY-MM-DD`) is created when the first release is cut,
per [docs/release-process.md](docs/release-process.md). Everything below the
heading-less `Unreleased` section is not yet part of any tagged release.

## [Unreleased]

### Added

- Vault management: create and open vaults as plain local Markdown files.
- Block-based page model with stable block IDs.
- Operation log (OpLog) with WAL persistence and crash recovery.
- Basic page/block editor: create, edit, and rename pages.
- Text editing: selection, clipboard, and IME/keyboard/pointer input.
- Basic Markdown round-trip for text paragraphs and links.
- Open-source onboarding docs: README, roadmap, and community files
  (Code of Conduct, security policy, support), plus GitHub issue and PR
  templates.
- `CHANGELOG.md` and a documented release/tag process
  ([docs/release-process.md](docs/release-process.md)).
