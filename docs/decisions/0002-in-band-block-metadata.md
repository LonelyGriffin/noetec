# 0002: In-Band Block Metadata in Markdown Comments

## Context

Block editing, references, and synchronization require stable identities attached
to semantic blocks. Metadata must stay with the content when files are moved or
edited outside Noetec, without making ordinary Markdown rendering display
technical wrappers around every block.

## Decision

Store block identities and properties in typed `noetec:*` HTML comments containing
JSON. Comment placement identifies the metadata owner; it does not override the
source structure. Lists, items, and child paragraphs have independent identities.
Unsupported source can have an explicit opaque wrapper without interpreting its
payload as supported content.

Reading alone does not invent missing identities. Existing valid unique block IDs
are retained literally; content similarity and checks do not recover identity.

Syntax, placement, identity validation, and preservation requirements are defined
by the [page-file contract](../contracts/page-file-format-v3.md). Identity changes
during editing are defined by the [editing specification](../specs/02-page-editing-and-saving.spec).

## Status

Accepted. Implementation coverage is separate from this decision.

## Consequences

- Metadata travels with its owner without a sidecar index.
- Ordinary Markdown renderers hide technical comments rather than displaying
  block fences. Noetec Markdown still has its own syntax profile.
- Nested ownership and empty blocks require explicit placement rules.
- External editors can damage metadata. Readers preserve and report ambiguity
  instead of guessing an owner or identity.

## Alternatives considered

- **Fenced directives for every block** — visible in ordinary Markdown rendering
  and more intrusive around supported content.
- **Positional or content-derived identity** — unstable under editing, moves, and
  concurrent changes.
- **Sidecar identity mapping** — can diverge from externally edited files and
  does not travel reliably with copied content.
