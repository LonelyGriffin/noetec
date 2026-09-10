# Noetec

**Local-first, block-based notes that live in plain files you own.**

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](LICENSE)
[![Status: pre-alpha](https://img.shields.io/badge/status-pre--alpha-red.svg)](#status)
[![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-0175C2?logo=dart&logoColor=white)](https://dart.dev)

## What is Noetec?

Noetec is a cross-platform note-taking app that pairs the openness of plain files with the comfort of a modern block editor. Your notes live in readable Markdown files on your own disk — the Obsidian approach — while the editor hides the formatting markers behind a friendly, Notion-like interface.

Every note is a tree of typed blocks (paragraphs, headings, lists, tasks, and more), each with a globally unique ID. That block-level structure is what makes precise references, synchronization, and conflict resolution possible — and it means your data is never locked into a proprietary format.

Noetec is **local-first**: it works fully offline, and the network is an enhancement, never a requirement. When you do want to sync, you choose how — file-based (Git, Dropbox, …), server-based (self-hosted or hosted), or peer-to-peer.

## Who is it for?

- **You want to own your data.** Your notes stay in plain, readable files you control — no account, no proprietary storage, no lock-in.
- **You love Markdown and self-hosting.** A file-first design that plays well with Git, Dropbox, and your own tooling, plus a server sync you can host yourself.
- **Developers and early adopters.** An open-source (AGPLv3) Flutter app with a clean, documented architecture you can read, learn from, and extend.

## Status

Noetec is in **pre-alpha**: under active development, and not yet ready for daily, critical use. APIs and file formats may change without notice. Follow along via the [roadmap](ROADMAP.md), and see [CONTRIBUTING.md](CONTRIBUTING.md) if you'd like to help.

Hi! I'm a frontend developer, and Noetec is my experimental project — a personal note-taking app. Anyone will be welcome to join once the project matures. I'm also open to AI assistance where it's used sensibly, since I rely on AI heavily myself.

## Quick start

```bash
flutter pub get
dart run build_runner build
flutter run
```

Requires a recent Flutter SDK (Dart 3.10+). Full setup — including git hooks — is covered in [CONTRIBUTING.md](CONTRIBUTING.md).

## Documentation

- [ROADMAP.md](ROADMAP.md) — what's done and what's planned
- [CONTRIBUTING.md](CONTRIBUTING.md) — set up, report bugs, and contribute
- [SECURITY.md](SECURITY.md) — report a security issue privately
- [SUPPORT.md](SUPPORT.md) — where to ask questions
- [docs/architecture.md](docs/architecture.md) — high-level code map (where each concern lives)
- [docs/](docs/) — product vision, architecture decisions, and specs

## License

Noetec is free and open-source software licensed under the [GNU Affero General Public License v3.0](LICENSE).
