# Roadmap

A date-free, development phases and the state of
each piece. This is a "living" document: the structure, statuses, and level of detail change during the development process.

## Status

- ✅ Done
- 🔨 Now — in progress
- 🔜 Soon — up next
- ⏳ Later — planned for the future

## 🔨 Prototype (alpha version)

Getting the app to a usable prototype for windows and android. Plan to test and use only yourself

- ✅ Foundation 
  - ✅ Vault management — create/open vaults on plain local Markdown files
  - ✅ Block-based page model with stable block IDs
  - ✅ Operation log (OpLog) with WAL persistence and crash recovery
  - ✅ Local-first, offline-first operation
- 🔨 Basic editor functionality 
  - ✅ Basic page/block editor — create, edit, and rename pages
  - ✅ Text editing — selection, clipboard, IME/keyboard/pointer input
  - 🔨 Markdown round-trip — basic text blocks only
    - ✅ Text paragraph 
    - 🔨 Link
    - 🔜 Header
- 🔨 Basic sync & user system 
  - 🔨 Device and user identity
  - 🔨 File-based sync engine — Аuto conflict resolution, external-edit handling
  - 🔜 Manual conflict resolution
  - 🔜 End-to-end sync hardening and verification
- ⏳ QoL & UI/UX 
  - ⏳ Rework the prototype UI into a polished, friendly interface
  - ⏳ Quality-of-life improvements — smoother editing, shortcuts, visual feedback
  - ⏳ User scope settings
  - ⏳ Onboarding and empty states for new users
- ⏳ Android adaptation 
  - ⏳ Аdapt the app for Android (phones and tablets)
  - ⏳ Adnroid e2e tests
- ⏳ Polishing and release
  - ⏳ Expand the integration test suite for the prototype scope
  - ⏳ Refactoring and polish app architecture
  - ⏳ Polish and stabilize the prototype behavior

## ⏳ Expansion (beta version)

An app with rich functionality and full features. I'm planning to test it out with a small, close circle of people.

- ⏳ Full markdown editor 
  - ⏳ Extend the editor to full markdown block coverage
    - ⏳ lists
    - ⏳ tasks (simple checkboxes)
    - ⏳ code
    - ⏳ quotes
    - ⏳ tables
    - ⏳ callouts
  - ⏳ Tags system
  - ⏳ Slash-comands 
  - ⏳ Embeds
  - ⏳ Mathematics formulas
- ⏳ Indexing and cache systems
- ⏳ Meta-properties — status, start/end dates, custom properties
- ⏳ Search
- ⏳ Block references and backlinks
- ⏳ Templates — note and block
- ⏳ Native task blocks
- ⏳ Event handling
- ⏳ Built-in calendar
- ⏳ Agenda views
- ⏳ Board canvas
- ⏳ Query blocks   
  - ⏳ Outliner
  - ⏳ Table
  - ⏳ Kanban
  - ⏳ Timeline
- ⏳ Pages history navigation

## ⏳ Sync & collaboration (release candidate)

To create an app that fits a wide audience and different use cases.

- ⏳ Server-based sync — self-hosted or hosted master copy
- ⏳ Teams, roles, and access control (requires server sync)
- ⏳ Peer-to-peer sync — devices synchronize directly
- ⏳ Real-time co-editing via CRDT
- ⏳ Plugins ecosystem

## ⏳ Public Documentation
  - ⏳ Marketing website with feature showcases, setup variants and release notes
  - ⏳ Comprehensive user manual and comprehensive video/visual guides
  - ⏳ Interactive templates gallery and community-driven showcase
  - ⏳ Self-hosting deployment guides and API/developer documentation

## ⏳ Cross platform adaptation

- ⏳ IOS
- ⏳ Linux
- ⏳ MacOS
