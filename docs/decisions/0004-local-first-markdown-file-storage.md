# 0004: Local-First Markdown Storage and Page Identity

## Context

Notes must remain usable offline, readable outside Noetec, and owned by the user.
File-based storage supports external editors and independent synchronization, but
requires explicit identity, source-preservation, and consistency rules.

## Decision

Store pages as local UTF-8 Markdown files, not an application-owned database or a
remote master copy. Synchronization is layered over local operation.

An initial `noetec:page` HTML comment contains JSON page metadata: a stable UUID
and optional properties. Block metadata follows the
[in-band metadata decision](0002-in-band-block-metadata.md).
YAML frontmatter, technical timestamps, and a page-wide hash are not required.
Foreign frontmatter is preserved as unsupported source, not inferred as Noetec
page metadata.

Use own-state checks on blocks to detect accidental inconsistency without making
every descendant edit change its ancestors' checks. Checks are not authentication,
unique content identities, or authority to recover IDs. Save conflict detection
verifies the source revision independently of those checks.

The [page-file contract](../contracts/page-file-format-v3.md) defines representation
and check inputs. The [editing and saving specification](../specs/02-page-editing-and-saving.spec)
defines adoption, external-change handling, saving, and recovery.

## Status

Accepted. Implementation coverage is separate from this decision.

## Consequences

- Pages remain readable and editable with external tools, without a network.
- JSON comments carry metadata without a visible frontmatter section in ordinary
  Markdown rendering.
- Own-state checks localize inconsistency to a block's content, properties, or
  immediate-child structure; they do not authenticate external edits.
- Queries and relationships require indexes that can be rebuilt from files.
- External editing and cross-file operations require explicit preservation,
  conflict detection, and recovery rather than database-provided transactions.

## Alternatives considered

- **Database as the primary page store** — does not provide directly editable,
  human-readable files as the source of page content.
- **Cloud-first page storage** — makes offline operation depend on a cache of
  remotely authoritative content.
- **YAML frontmatter and mandatory page-wide hashes** — not needed for the chosen
  JSON metadata and localized own-state checks.
- **Metadata-free Markdown** — cannot carry persistent page and block identities.
