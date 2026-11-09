# Noetec page file format

**Contract revision: 2. Status: rejected.**

This contract defines page files, block identity, serialization, and handling of
external edits. It does not define editor controls, synchronization protocols, or
the storage layout of history, transactions, or OpLogs.

The revision is documentation-only; page files have no required `format_version`
field. Compatibility with or migration from the
[version-1 format](page-file-format.md) is outside this contract.

**MUST**, **MUST NOT**, **SHOULD**, and **MAY** express requirement levels as defined
by RFC 2119 and RFC 8174. Requirements remain proposals until this draft is accepted.

## 1. Guarantees

All editing inside Noetec MUST preserve content and properties except for changes
explicitly made by the operation, and MUST obey the identity and transaction rules
in §6 and §7. This includes editing raw-text blocks.

External editors may change page files. Noetec preserves valid, correctly placed
unique IDs, but does not guarantee identity preservation after arbitrary external
changes. It MUST NOT infer split/merge history or retarget links by text similarity.

Noetec is not a lossless visual editor for every Pandoc construct or malformed
input. Source that cannot be represented safely by ordinary blocks MUST remain
editable as raw text (§8), not be silently discarded.

## 2. Encoding and envelope

A page is a UTF-8 `.md` file with leading YAML metadata and a Pandoc Markdown body.

- Writers MUST emit UTF-8 without BOM and LF line endings.
- Readers accept a leading UTF-8 BOM and normalize CRLF and CR to LF.
- An exact first line `---` starts metadata. The next exact `---` line closes it,
  independently of YAML validity. A closing line at EOF needs no final LF.
- Writers put one empty separator line after metadata. Readers remove at most
  one immediately following empty line; further blank lines belong to the body.
- Without the opening delimiter, the whole normalized source is body.
- Without a closing delimiter, preserve the whole normalized source in one
  raw-text block and synthesize metadata; do not guess where metadata ends.
- A file without metadata must use `***` or `___` for a leading horizontal rule.

An empty separator line contains no characters. Delimiter prefixes, such as
`---unexpected`, are not delimiters. Invalid UTF-8 MUST NOT be silently replaced
and overwritten. If original bytes cannot be represented safely as text, saving
MUST fail rather than overwrite them with a lossy interpretation.

## 3. Page metadata

Metadata is one YAML document with a mapping at the top level.

| Key | Value | On write |
|---|---|---|
| `id` | Stable page UUID, lowercase hyphenated form | Required |
| `content_hash` | `sha256:` plus 64 lowercase hexadecimal characters | Required |
| `modified` | Save time, UTC RFC 3339 date-time ending in `Z` | Required |
| `modified_by` | UUID of the saving device | Omitted if unknown |

In supported metadata, known fields MUST be validated independently. A missing or
invalid page ID receives a new UUID; it does not restore the previous identity or
retarget links. Missing/invalid dates receive current UTC time; valid
offset-bearing dates are normalized to UTC. Invalid hashes provide no baseline.
Generated identities MUST remain stable in the loaded document until persistence.
Reading alone MUST NOT continually change timestamps or trigger saves.

Unknown values in ordinary YAML 1.2 Core mappings and sequences MUST be preserved
semantically. Comments, key order, quoting, and formatting need not survive.
Identifiers and hashes are strings, not Markdown content. Duplicate keys,
non-string keys, aliases, custom tags, and values that cannot be represented
without loss need not be supported; their source follows §8 instead of being
silently coerced or discarded.

Missing metadata is synthesized. If metadata cannot be safely represented,
preserve the complete delimited metadata source in a raw-text block before the
body and synthesize replacement metadata. Its payload is inactive source, not
page metadata. Saving requires no repair confirmation.

Multiple files with the same valid page ID make the address ambiguous. Readers
MUST NOT choose a winner or silently renumber files. Inspection and editing remain
available, but address-dependent operations are blocked until explicit resolution.

## 4. Markdown profile and elements

Body syntax follows a pinned Pandoc Markdown profile, not installed defaults.
Before acceptance, the contract MUST name the reference release, AST version,
enabled/disabled extensions, and reader settings, including tab preservation and
automatic text transformations. Implementations need not run the Pandoc binary.

The profile MUST enable `fenced_divs`, `bracketed_spans`, `task_lists`, heading
attributes, and fenced code with attributes; disable `four_space_rule`, `smart`,
and body-level metadata parsing; and preserve literal tabs in code/raw text.
The envelope and YAML values are handled separately from Markdown. Writers use
spaces for structural indentation, aligning list continuations with the content
column after the list marker.

The initial editable set consists of paragraphs, headings, ordered/unordered/task
lists, nested lists, block quotes, fenced code blocks, pipe/grid tables, links,
basic inline formatting, raw-text blocks, and standard Div/Span attributes.
Horizontal rules are retained without generated IDs; nonsemantic separating
whitespace may be normalized. The set is extensible through explicit mapping
rules, not changed parser defaults.

A **block** is a semantically meaningful addressable unit. Paragraphs, headings,
lists, items, quotes, tables, code blocks, and raw-text blocks receive IDs. Every
paragraph inside an item, including the first, has its own ID. Semantic blocks
inside items, quotes, or cells follow the same rules as elsewhere. Empty cells
and editor placeholders require no synthetic text blocks.

Rows, cells, inline fragments, and user Divs are structural elements, not
automatically addressable blocks. There is no generic Noetec group block.
Hierarchy follows Markdown structure; headings do not automatically parent the
following content. Simple cell text maps to one text block whether Pandoc uses
`Plain` or `Para`; item paragraphs use the same equivalence. Clearing an existing
paragraph preserves its ID and writes an empty Span, `[]{noet-id="A"}`. Explicit
block deletion, not empty text alone, removes its identity.

Pipe tables may be written only when they can represent the content and table
properties without loss. Block-containing cells use a capable representation,
normally grid syntax. Unrepresentable configurations follow §8 rather than being
flattened. Images, figures, footnotes, and other unmapped elements follow the
unsupported-content policy until their editable mapping is defined.

## 5. Block metadata and canonical carriers

The attribute prefix `noet-` is reserved. `noet-id` is block identity, independent
of user anchors such as `#installation`. `noet-raw="true"` marks a raw-text code
block (§8); no type or carrier-role attribute is required for ordinary blocks.
Other `noet-*` attributes are properties. Attribute values are strings; property
types require separate definitions. Unknown keys MUST be preserved on their owner
without invented semantics.

New IDs are UUIDs. Existing valid unique IDs MUST be retained literally. A valid
ID is nonempty, is not entirely Unicode whitespace, and has no Unicode control
characters (category `Cc`). IDs are compared without trimming, case folding, or
Unicode normalization.

Readers and writers use the canonical carriers below. Structural variants are
allowed only by explicit, mutually exclusive rules, not by carrier preferences.

| Block | Carrier |
|---|---|
| Heading | Native heading attributes |
| Code or raw-text block | Native fenced-code attributes |
| Paragraph or cell text | Outermost Span covering all inline content |
| List | Div directly enclosing the list |
| Simple list item | Outer Span enclosing the paragraph's own complete Span |
| Other list item | Div enclosing all item content |
| Quote or table | Div directly enclosing that semantic block |

```markdown
[Paragraph.]{noet-id="B"}

## Heading {#user-anchor noet-id="H"}

::: {noet-id="L"}

- ::: {noet-id="I"}

  [First paragraph.]{noet-id="A"}

  [Additional paragraph.]{noet-id="P"}

  :::

:::
```

### List items and tasks

A **simple item** contains exactly one nonempty paragraph, no explicit line
breaks, and no other child blocks. Its outer Span identifies the item; the inner
complete Span identifies the paragraph. Writers emit it on one physical line,
with the outer attributes at line end:

```markdown
- [[Ordinary item.]{noet-id="A"}]{noet-id="I"}
- [ ] [[Task text.]{noet-id="B"}]{noet-id="J"}
```

Soft source wrapping does not change item structure or carrier ownership. Empty
items, empty paragraphs, explicit line breaks, and additional blocks require Div
form. An ordinary Div item has the carrier as its sole immediate block. A task
Div item has a standard task marker alone before the Div, separated by a blank
line:

```markdown
- [x]

  ::: {noet-id="I"}

  [Task text.]{noet-id="A"}

  [Details.]{noet-id="B"}

  :::
```

The marker-only prefix is task state, not an addressable paragraph. Task state
comes only from standard `[ ]` / `[x]` syntax (`[X]` is accepted on read), outside
the carriers; it MUST NOT be duplicated in a Noetec property. Literal checkbox
characters are not sufficient evidence of task syntax.

The item carrier owns only item identity and properties. Every child paragraph
has its own carrier; a nested list needs a separate Div inside the item Div.
Only the complete outer Span enclosing the paragraph's complete Span is an item
Span carrier. A lone paragraph Span does not also identify the item. Recognizable
item carriers outside their permitted structural form follow the raw policy
rather than supplying a fallback identity. Known Noetec edits switch forms as
needed while preserving item/child IDs and properties, without retargeting links.
User inline attributes remain attached to their inline content when a carrier
changes; writers retain an inner user Span if necessary instead of converting
those attributes into block-level attributes.

### Ownership and attributes

Only the canonical carrier supplies active identity and block properties.
Establish item ownership first, then paragraph ownership inside its carrier.
Outside the item rule, `Text {noet-id="A"}` is not a paragraph carrier, a Div
around a paragraph does not transfer identity, and an inner Span does not compete
with the complete outer Span. A Div around multiple sibling blocks
does not distribute metadata or create a Noetec group. Readers MUST NOT transfer
IDs between carriers, merge their metadata, or infer replacement reference targets.

Noncanonical `noet-id` attributes are inactive and MUST be preserved as attributes
when safe; otherwise preserve the containing source as raw text. User Spans,
Divs, anchors, classes, and attributes MUST survive supported editing. A partial
user Span is not expanded into a carrier. A known type conversion transfers the
block's identity and properties to its new canonical carrier and MUST retain user
attributes in a representable form rather than silently discard them.

## 6. Identity and operations

Block IDs are unique within a page; the full address is `(page_id, block_id)`.
Readers establish carrier ownership before resolving duplicates. For distinct
blocks with equal IDs, the first in depth-first document order keeps the ID;
later blocks receive new UUIDs. Missing or invalid canonical IDs also receive new
UUIDs. These are new identities, not recovered ones, and MUST NOT trigger link
updates. Tables are traversed head, bodies, foot; rows and actual cells are visited
in order, spanning cells once. IDs inside raw payloads are inactive.

| Known Noetec operation | Result |
|---|---|
| Move or one-to-one type conversion | Preserve block identity |
| Copy | New IDs for the copy and addressable descendants |
| New semantic container | New ID |
| Split | First part keeps its ID; later parts receive new IDs |
| Insert an empty block before content | Existing content keeps its ID |
| Merge | First block in document order keeps its ID; retarget absorbed blocks' links |

Converting paragraph `A` into a list keeps `A` on the paragraph; the new list and
item containers receive new IDs. Wrapping content is not identity replacement.

Moved descendants keep their IDs. Retired IDs MUST NOT be reused. Cross-page
moves MUST check destination collisions before changing files; a collision blocks
the move without silent renumbering or partial mutation.

Links inside a copied subtree to its own blocks MUST target the copies. Links
to outside content and incoming links from outside the copy remain unchanged.
External deletion or replacement of IDs may leave unresolved links; reading or
normalizing a file MUST NOT repair those targets by inference.

## 7. Block links

```markdown
[Label](noetec://<page-id>/<block-id>)
```

The authority is the page UUID and the single path component is the block ID.
Writers use lowercase `noetec` and canonical page UUIDs, percent-encoding block
IDs as UTF-8 path data. Readers accept scheme case differences and decode once,
without path normalization. Dot-only IDs MUST have their dots encoded.
Userinfo, ports, query strings, fragments, extra path components, invalid escapes,
or invalid decoded IDs are invalid addresses; preserve rather than
guess repairs. User anchors and ordinary URLs are separate addresses.

Only semantic link destinations are references. URI text in code, raw source,
or arbitrary metadata is not automatically a live link.

Known merges, cross-page moves, and explicit target-replacement operations MUST
update affected semantic references throughout the vault, including unopened
pages, without changing labels. External edits, ID assignment, and ordinary
normalization MUST NOT trigger reference retargeting.

An operation and all its induced cross-file reference changes form one logical
transaction. Completed saving and crash recovery MUST leave either the state
before the transaction or its complete result, not an arbitrary subset of changes;
a save reported as successful MUST durably preserve the complete result.
Unavailable pages or unsafe writes MUST NOT be treated as successful completion.

Transaction storage and cross-file OpLog layout are implementation concerns.
Guarantees for independent file-sync delivery belong to sync contracts. External
documents and obsolete links reintroduced by later external edits are outside
the transaction.

## 8. External edits, unsupported content, and safe saving

External input is interpreted as its current state, not as a history to recover.
Supported structure opens as ordinary blocks with the mechanical ID rules in §6.
Noetec MUST NOT reconstruct previous identities, split/merge history, properties,
or reference targets.

Source that cannot be represented safely becomes a special editable raw-text
block with its own ID. This applies equally to unsupported valid constructs and
uninterpretable source; a valid unsupported construct is not malformed. Markdown
that the selected reader treats as ordinary text remains ordinary text.

Recovery MUST use reliable source boundaries without changing the interpretation
of neighboring content. If local boundaries are unsafe, expand to a reliable
enclosing region, up to the whole body, displayed as a normal raw-text block.
Readers MUST retain the original source and a reliable mapping to its regions;
reserializing an unsupported AST node is not preservation of its source. When
constructs depend on definitions elsewhere, the recovery boundary MUST include
the dependencies needed to avoid losing source or changing neighboring content.

Raw blocks are serialized as fenced code blocks with `noet-raw="true"` and a
canonical `noet-id`. For example:

````markdown
```{noet-id="R" noet-raw="true"}
source not represented by ordinary blocks
```
````

The payload is editable text, not active Markdown, metadata, or references. It
MUST remain a raw block on save/reopen, including after payload edits; ordinary
saving MUST NOT automatically reinterpret it. Its exact text value follows the
fenced-code rules in §9. Original line-ending/BOM distinctions are covered by
the byte backup, not the text payload.

Saving persists the interpreted document without asking for repair or conversion
confirmation. Automatically generated IDs and metadata are persisted normally.

Before the first normalized write of an externally changed or repaired file,
Noetec MUST retain its original bytes in a recoverable backup or history entry.
That entry MUST contain the external file, not merely an older Noetec save, survive
restart, and remain retrievable under the history/backup retention policy; save
completion alone MUST NOT delete it. Preservation is automatic. If it fails,
overwrite MUST fail rather than be reported as successful.

All saves MUST verify that the source revision being replaced is still current;
external changes require rereading/reconciliation. Reading or previewing MUST NOT
execute scripts, filters, raw content, or includes, or fetch external resources.
Resource-limit failures MUST be explicit, not truncated documents saved as complete.

## 9. Hashing and serialization

On read, compute SHA-256 over the UTF-8 bytes of the extracted LF-normalized body
before parsing repairs, ID generation, or reserialization. Compare with a safely
parsed valid `content_hash`; missing/invalid metadata provides no stored baseline.
An unterminated metadata candidate has no extracted body hash.

On write, serialize the final body and hash exactly its UTF-8 bytes, including
actual trailing LFs and attributes. Write that body with the matching metadata.
The hash excludes metadata and is not authentication or proof of an external edit.
Source-revision checks MUST also account for metadata-only and byte-level changes.

Supported content, raw-text values, semantic nesting, properties, user attributes,
and identities MUST survive normal round trips. Nonsemantic wrapping, delimiters,
and YAML formatting need not be byte-identical. Code whitespace and explicit line
breaks are content. Each writer MUST be stable for an unchanged normalized
document; repeated cycles MUST NOT mint IDs or alternate carrier forms.

For both code and raw-text blocks, writers MUST emit an opening fence followed
by LF; for an empty text value, immediately emit the closing fence. Otherwise
emit the entire text value unchanged, then one additional LF, then the closing
fence. That additional LF terminates the source line and is not part of the text
value. Existing trailing LFs MUST NOT be removed or used in place of it.

Fences MUST be longer than any potentially closing run of their delimiter in the
text. Structural list/quote prefixes are added to payload lines separately from
the text value, without trimming, tab expansion, or removal of blank lines.
Readers MUST reverse only those structural prefixes and retain the text value,
including tabs and trailing LFs. A generic Pandoc writer is not sufficient evidence
of compliance; its code-block output may omit a required trailing LF.

## 10. Acceptance evidence

Examples are illustrative, not validated fixtures. Acceptance requires a pinned
Pandoc profile and fixtures proving:

- Span/Div item boundaries, identity-preserving switches, independent paragraph
  IDs, soft wrapping versus explicit line breaks, and empty paragraphs/items;
- standard task markers with Span and Div items, including empty tasks and
  literal checkbox text that is not task syntax;
- table text identity across pipe/grid syntax and supported block-containing cells;
- supported-content round trips and stable identities;
- split/merge/move/copy results and internal-copy links;
- complete cross-file transactions after saving and crash recovery, including
  vault-wide link updates and concurrent external writes;
- missing/duplicate/misplaced IDs, malformed metadata, and unresolved links;
- raw recovery boundaries, malformed/unsupported metadata, ordinary saving
  without repair confirmation, and durable original-byte backups;
- raw payload stability for tabs, container indentation, fence-like text, empty
  payloads, and trailing LFs, without automatic reinterpretation;
- encoding, envelope boundaries, and independently verified body hashes.

The editable table subset, source boundaries, and exact code/raw serialization
MUST be validated, not assumed from Pandoc AST capabilities. Pipe/grid conversion
MUST preserve semantic table properties, not adopt incidental source widths as new
user settings. Version-1 tests do not prove conformance.

## References

- [Pandoc User's Guide](https://pandoc.org/MANUAL.html)
- [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and
  [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174)
- [RFC 3339](https://www.rfc-editor.org/rfc/rfc3339)
- [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986)
