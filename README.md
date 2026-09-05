# Noetec

A cross-platform Flutter block-based note-taking application with file-based storage, local-first operation, and multi-device synchronization.

> **Status:** Early development

## Overview

Noetec combines the file-based approach of Obsidian (all data stored as readable `.md` files) with the user-friendly interface of Notion. The application is fully functional offline, with flexible sync options: file-based (Dropbox, Git), server-based, or P2P.

All notes are structured as trees of blocks (paragraphs, lists, headings, etc.), each with a unique identifier. This enables block-level references, precise sync, and conflict resolution.

## Documentation

- [Architecture decisions](docs/decisions/) — ADRs capturing key design choices
- [Product Vision](docs/product/vision.md) — features, sync strategies, future plans
- [Specs](docs/specs/) — normative file-format and workflow specs

## Tech Stack

- **Flutter** (Dart 3.10.7) — cross-platform (desktop + mobile)
- **State management**: get_it + watch_it + listen_it + command_it
- **Storage**: File-based (Markdown with YAML frontmatter)

## Getting Started

```bash
flutter pub get
dart run build_runner build
flutter run
```

## License

See [LICENSE](LICENSE)
