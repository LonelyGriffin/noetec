# 0002: Block IDs via Fenced Directives in Markdown

## Context

Noetec treats documents as trees of blocks (paragraphs, headers, tasks, lists, code blocks), and later phases require block-level operations, a block-level operation log, and block-level merge during sync. All of that depends on every block having a stable unique identifier. At the same time, Noetec's storage format is plain human-readable markdown that must remain editable in external editors and survive round-trips (parse → edit → serialize) without losing identity information.

Plain markdown has no native way to attach an identifier to a block, so an explicit in-band encoding is needed.

## Decision

Give every block a unique ID encoded directly in the markdown source using fenced container directives of the form `::: <type> <id> ...other attrs` … `:::`. Each block's opening fence carries its type and unique ID (plus optional attributes such as a task's status); nested blocks nest their fences. Block IDs are preserved across parse → serialize round-trips, so identity survives editing sessions.

## Status

Accepted.

## Consequences

- Positive: block identity is stored in-band, in the same file the user reads — no sidecar files or external index that can drift out of sync with the content.
- Positive: IDs survive round-trips and external edits, enabling stable block-level diffing, operation logs, and merges later.
- Positive: the file remains plain text and version-control friendly.
- Negative: the directive syntax is non-standard markdown; editors unaware of it will render the fences as visible text.
- Negative: the parser and serializer must handle directives (including nesting) correctly, and malformed fences from external edits must be tolerated gracefully.

## Alternatives considered

- **No explicit IDs (positional identity)** — rejected: block identity by position breaks under reordering and concurrent edits, making reliable block-level operations and merges impossible.
- **HTML comment markers (e.g. `<!-- id: xyz -->`)** — rejected: more visually intrusive in raw markdown, easier to accidentally delete, and awkward to associate with nested block structure compared with paired open/close fences.
- **Out-of-band ID mapping (separate index file)** — rejected: duplicates state, risks divergence between the index and the actual file content, and breaks when the file is edited externally without updating the index.
