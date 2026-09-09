# Roadmap

A date-free, single-stream view of Noetec's development phases and the state of
each piece. Every phase and milestone carries a status, and every milestone is
decomposed into sub-items with their own status.

## Status

- ✅ Done
- 🔨 Now — in progress
- 🔜 Soon — up next
- ⏳ Later — planned for the future

## 1. Prototype 🔨

Getting the app to a usable prototype for windows and android.

### 1.1 Foundation ✅

- ✅ Vault management — create/open vaults on plain local Markdown files
- ✅ Block-based page model with stable block IDs
- ✅ Operation log (OpLog) with WAL persistence and crash recovery
- ✅ Local-first, offline-first operation

### 1.2 Basic editor functionality 🔨

- ✅ Basic page/block editor — create, edit, and rename pages
- ✅ Text editing — selection, clipboard, IME/keyboard/pointer input
- 🔨 Markdown round-trip — basic text blocks only - Text Paragraph, List, Header.

### 1.3 Basic sync & user system 🔨

- ✅ Device and user identity
- 🔨 File-based sync engine — OpLog merge, auto conflict resolution, external-edit handling
- 🔜 Manual conflict resolution
- 🔜 End-to-end sync hardening and verification

### 1.4 QoL & UI/UX 🔜

- 🔜 Rework the prototype UI into a polished, friendly interface
- 🔜 Quality-of-life improvements — smoother editing, shortcuts, visual feedback
- 🔜 User scope settings
- 🔜 Onboarding and empty states for new users

### 1.5 Android adaptation 🔜

- 🔜 Аdapt the app for Android (phones and tablets)
- 🔜 Adnroid e2e tests

### 1.6 Polishing 🔜

- 🔜 Expand the integration test suite for the prototype scope
- 🔜 Refactoring and polish app architecture
- 🔜 Polish and stabilize the prototype behavior

## 2. Expansion ⏳

### 2.1 Full markdown editor ⏳

- ⏳ Extend the editor to full markdown block coverage — headings, lists,
  tasks, code, quotes, tables

### 2.2 Block references, backlinks & templates ⏳

- ⏳ Block references and backlinks
- ⏳ Meta-properties — status, start/end dates, custom properties
- ⏳ Templates — note and block

### 2.3 Task & event system ⏳

- ⏳ Native task blocks and event handling

### 2.4 Calendar, agenda & specific pages ⏳

- ⏳ Built-in calendar and agenda views
- ⏳ Board mode — a spatial canvas view of the same content

### 2.5 Views & search ⏳

- ⏳ Views — outliner, table, kanban, timeline
- ⏳ Query blocks and smart search

## 3. Sync & collaboration ⏳

### 3.1 Server sync ⏳

- ⏳ Server-based sync — self-hosted or hosted master copy

### 3.2 Teams, roles & access control ⏳

- ⏳ Teams, roles, and access control (requires server sync)

### 3.3 P2P sync ⏳

- ⏳ Peer-to-peer sync — devices synchronize directly

### 3.4 Real-time collaboration ⏳

- ⏳ Real-time co-editing via CRDT

## 4. Cross platform adaptation ⏳

- ⏳ IOS
- ⏳ Linux
- ⏳ MacOS
