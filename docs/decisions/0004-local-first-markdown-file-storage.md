# 0004: Local-First File-Based Storage as Markdown with YAML Frontmatter

## Context

Noetec needs a storage model for notes, tasks, and collaboration data. The product's core values are: fully functional offline, user ownership of data, human-readable content, and compatibility with existing tools (external editors, version control, file-sync services). A traditional approach — an app-owned database or a cloud-first service — conflicts with several of these values.

## Decision

Adopt local-first, file-based storage. All user data is stored as plain `.md` files on the user's filesystem, each beginning with a YAML frontmatter block carrying document metadata (a stable document `id`, a `content_hash` for integrity / external-edit detection, and modification timestamps — with `modified_by` deferred per ADR-0003). The files themselves are the source of truth; the application is fully functional without a network connection, and synchronization (file-based services such as Dropbox or Git, server-based, or P2P) is layered on top asynchronously as a later concern.

## Status

Accepted.

## Consequences

- Positive: true offline operation — all operations work locally with no network dependency.
- Positive: user owns the data in an open, human-readable, tool-compatible format; files can be read and edited outside Noetec and tracked by Git.
- Positive: sync via existing file-sync services becomes possible without building a server.
- Negative: the app must detect and tolerate external edits to its files (hence the `content_hash` integrity check), which a closed database would never face.
- Negative: querying, indexing, and relational operations are harder over loose files than over a database; integrity and consistency checks must be implemented explicitly.
- Negative: cross-device conflict handling becomes the app's problem rather than a database's — deferred to the sync phases.

## Alternatives considered

- **SQLite / embedded database as source of truth** — rejected: not human-readable, not directly editable by external tools, and locks user data inside an app-owned binary format; conflicts with the file-based ownership value.
- **Cloud-first storage (remote server as source of truth, local cache)** — rejected: violates local-first; offline becomes a degraded mode instead of the default, and user data ownership is weakened.
- **Plain markdown without frontmatter** — rejected: no place to carry a stable document ID or integrity hash, both of which are required for external-edit detection and later sync.
