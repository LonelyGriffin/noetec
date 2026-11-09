# Noetec Markdown page file format

**Contract revision: 3. Status: accepted.**

This contract defines Noetec Markdown syntax, represented data, metadata,
identities, checks, references, and read/write preservation requirements.
Editing operations and save/recovery behavior are defined in the
[page editing and saving specification](../specs/02-page-editing-and-saving.spec).
Sync protocols and transaction/OpLog storage are outside its scope.

Files have no required `format_version`. **MUST**, **MUST NOT**, **SHOULD**, and
**MAY** have their RFC 2119 and RFC 8174 meanings.

Examples use short IDs and may omit checks; they are not conformance vectors.

## 1. Terminology

Noetec Markdown stores content using the syntax in §2 and metadata in HTML comments.

A **block** is a semantic unit of the Noetec document model with its own identity,
including blocks without textual content, such as thematic breaks. Source may
lack valid block metadata or IDs (§6). Syntax tokens, fences, list markers,
separator lines, and inter-block whitespace have no independent identities.

**Opaque** stores unsupported source as one block (§8).

Readers interpret current source without reconstructing external editing history,
matching identities by similarity, or inferring replacement link targets.

## 2. Encoding and syntax

Pages are UTF-8 `.md` files. Writers emit LF without BOM. Readers accept a leading
UTF-8 BOM and normalize CRLF/CR to LF for interpretation. Invalid UTF-8 MUST NOT
be silently replaced and overwritten.

The syntax is based on CommonMark 0.31.2 with the GFM tables, task list items,
and strikethrough extensions, subject to the changes below and Noetec metadata.
Other GFM extensions are not part of this syntax.

The following rules override CommonMark:

- A paragraph occupies one source line, from its beginning to the newline or EOF.
  Consecutive paragraph-text lines are separate paragraphs without requiring a
  blank separator. Container markers identify structure, not paragraph text; pipe
  cells have their own boundaries. Blank separators and empty paragraphs follow
  §5.1. Other blocks and metadata retain their structural representations.
- Soft breaks and hard breaks are not supported. A newline is not an inline
  element and is never converted to a space. A trailing backslash or spaces MUST
  NOT be interpreted as a hard-break marker or consumed on that basis.
- Inline constructs do not continue across paragraph boundaries. Unmatched inline
  delimiters remain text; cross-line constructs MUST NOT trigger automatic opaque
  wrapping or recovery of a multiline inline structure.
- Reference-style links and reference definitions are not supported. Their
  reference syntax remains paragraph text, not a resolved link, a definition,
  or a source dependency.

Only the mappings in §3 are editable as structured content. Unmapped source follows
§8. Visual wrapping does not create paragraphs.
Smart punctuation, automatic resource fetching, filters, includes, and executable
content MUST NOT run as part of interpreting or saving a page.

## 3. Block and inline model

Lists, items, and their child paragraphs are independent blocks, including the
first paragraph of an item. Quotes and items contain
child blocks; the paragraph rule in §2 applies within them. Headings do not
implicitly parent following content.

The following table defines the block model and each type's own `state`
for §7. Children are represented by ordered IDs, not their content or checks.

| Type | Own state |
|---|---|
| Paragraph | Single-line inline content |
| Heading | Inline content and level 1–6 |
| Code | CommonMark text content and complete info string |
| Opaque | Exact source payload; no interpreted children |
| Item | Ordinary/unchecked/checked state and direct child IDs |
| List | Ordered/unordered kind, starting number if ordered, and item IDs |
| Quote | Direct child IDs |
| Table | Row/column counts, header/body roles, alignments, and ordered content IDs per cell |
| Thematic break | No content or children |

Tables and cell-content blocks have IDs; rows, columns, and cells do not. Editable
tables are rectangular pipe tables with a header, body rows, column alignment,
and at most one inline-content block per cell. Other tables MUST be preserved
without lossy conversion. Empty cells and empty content blocks differ (§5.1).
Table state includes empty positions and cell boundaries, not a flattened ID list.

Task state comes only from standard source markers `[ ]` and `[x]`; `[X]` is
accepted on read. It MUST NOT be duplicated in metadata. Literal checkbox
characters do not establish task syntax.

List-marker spelling, ordered delimiter, and tight/loose layout are formatting,
not state.

Fenced and indented code follow CommonMark 0.31.2. Code state contains the
CommonMark text content, including trailing LFs, subject to §2 line-ending
normalization. Indented code has an empty info string; fenced code retains the
complete processed info string. Fence character and length are formatting, not state.

The inline model contains text, emphasis, strong emphasis, strikethrough,
inline code, links, and images. Images contain a destination, an
optional title, and flat alt text, edited without nested inline parsing.
Inline HTML has no editable mapping; its containing text block follows §8.

A link uses `[label](destination)` with an optional title. It is inline content,
even when occupying an entire paragraph or appearing in an item's first paragraph.
It has no independent ID, metadata, or check; its label, destination, and title
contribute to the containing block's state. Absent and empty titles are distinct.

## 4. Metadata comments and values

The reserved syntax is:

```markdown
<!-- noetec:<type> <JSON object> -->
```

The type declares the expected owner; it does not override content structure.
Names are `page`, `paragraph`, `heading`, `list`, `item`, `quote`, `code`, `table`,
`thematic-break`, and `opaque`. Empty blocks and opaque use the explicit
representations below. `end-opaque` is a boundary record, not a block type.

Metadata and live links are recognized only in the structural and inline positions
defined by this contract. Code payloads are literal. Opaque interpretation follows
§8.1. Ordinary HTML comments are not Noetec metadata.

Block records contain:

| Field | Meaning |
|---|---|
| `id` | Block identity |
| `check` | Six-character own-state check (§7) |
| `props` | Optional JSON object of block properties |
| `first` | Item-only metadata record for its first paragraph |

`first` contains the metadata of the item's first child when that child is a
paragraph: independent `id`, `check`, and optional `props`, with implicit type
`paragraph`. It MUST NOT contain `first` or coexist with a separate metadata
record for that paragraph. Empty first paragraphs follow §5.1.

Values use the JCS-compatible JSON model (RFC 8785): Unicode scalar strings without
normalization, booleans, null, arrays, string-keyed objects, and finite binary64
numbers. Exact integers are limited to ±(2^53−1); larger integers and exact decimals
use strings. Readers MUST NOT round out-of-range integers into the safe range or
accept numeric overflow. Duplicate keys, unpaired surrogates, comments, and
trailing commas are unsupported.

Unknown `props` keys and technical fields MUST be preserved on their owner without
invented semantics or reclassification.

Writers emit block and boundary records on one physical line. Page records use
formatted multiline JSON (§6). In addition to JSON string escaping,
they encode `<`, `>`, `&`, and `|` as `\u003c`, `\u003e`, `\u0026`, and `\u007c`.
Every hyphen in a run of two or more is encoded as `\u002d`. These rules apply to
keys and string values.

## 5. Canonical placement and ownership

Suffix comments are the primary form. Prefix comments are used only for the
explicit cases below, not as a fallback search for a suitable owner.

| Owner | Canonical placement |
|---|---|
| Nonempty paragraph | Suffix at the end of its inline content |
| Heading | Suffix at the end of heading content |
| Text block in a pipe cell | Paragraph suffix within that cell |
| Item beginning with a nonempty paragraph | Item suffix at the end of that paragraph; `first` identifies the paragraph |
| Item without initial paragraph text | On the item-marker line, after any task marker |
| List, quote, table, code, thematic break | Separate prefix comment before the block |
| Empty paragraph | Standalone paragraph record; not a prefix for another block |
| Opaque | Opening and closing boundary records around its payload (§8) |

```markdown
Text. <!-- noetec:paragraph {"id":"A"} -->

<!-- noetec:list {"id":"L"} -->
- [ ] Task. <!-- noetec:item {"id":"I","first":{"id":"B"}} -->

  Details. <!-- noetec:paragraph {"id":"C"} -->
```

An inline record with one unambiguous owner MAY normalize to a suffix on the same
source line without changing content or assigning it to another owner.

Canonical suffixes are outside formatting/link/code spans. Writers use one
metadata-separator space before a suffix; that separator is not user content.
Extraction removes the comment and exactly its one ASCII-space separator, not
all preceding whitespace. Any additional spaces remain content. Noncanonical
inline extraction MUST NOT consume user content. Canonical headings use
ATX syntax without closing hashes.

A prefix occupies its own line immediately before its block; readers also accept
intervening blank lines. It MUST NOT skip content, cross container boundaries,
or share its line with user content. Nested records use their container's Markdown
markers and indentation; they MUST NOT be placed outside that container.

Later item paragraphs have their own suffix records.

### 5.1. Empty states

A standalone `noetec:paragraph` record is an empty paragraph, not a prefix. Blank
lines create none; multiple records preserve multiple empty paragraphs. Records
inside containers use the same container markers and indentation as their blocks.

On an item-marker line with no user text, an item record with `first` represents
an empty first paragraph; without `first` it represents no initial paragraph.

An empty pipe cell contains no content block. A cell containing only a paragraph
record contains an empty paragraph with its own identity. Whitespace used to
separate table syntax or metadata is not paragraph text.

Writers MUST NOT emit competing owner records. Readers MUST distinguish missing,
malformed, misplaced, and competing records without merging their properties or
guessing a winner. Their source MUST remain preserved. Type mismatch is reported
as such, not used as an instruction to convert the content.

## 6. Page metadata and identity

A `noetec:page` comment begins on the first source line, after an optional BOM.
Its object contains required `id` and optional `props`, using the same JSON codec
as blocks. Writers emit formatted JSON with two-space indentation and one blank
separator line after the closing `} -->`, then the body. Readers accept compact
or multiline JSON in this initial record. The formatting and separator do not
create blocks. The body starts after the record and its one framing separator.

```markdown
<!-- noetec:page {
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "props": {"title": "Page title"}
} -->
```

No technical timestamps or page-wide hash are required.
Property meanings, including a title, MUST NOT be inferred from a body heading.

A later page record does not replace the initial record. Missing, malformed,
competing, and ambiguous page metadata MUST NOT be treated as a valid unique
identity. Foreign frontmatter follows §8.

Reading alone does not rewrite the file or establish missing identities.

Pages have stable UUID identities. The complete address of a block is
`(page_id, block_id)`. New block IDs are UUIDs. Existing valid unique block IDs
are retained literally: no trimming, case folding, or Unicode normalization.
A valid block ID is nonempty, not entirely Unicode whitespace, and contains no
Unicode `Cc` control characters.

Owner recognition precedes identity validation. Missing or invalid IDs MUST NOT be
reconstructed from content. Multiple files claiming the same page ID constitute
a page-identity conflict, not a rule for selecting one file.

## 7. Own-state checks

Every block record carries `check`, an accidental-inconsistency detector. Its input
has exactly `domain`, `type`, `id`, `props`, and `state`. The domain is
`noetec.block-state.1`.
Absent `props` equals `{}`; `state` is defined by the model in §3.

The input excludes the check itself, descendant content/checks, parent identity,
sibling position, metadata-comment formatting, and technical save timestamps.
No Unicode normalization is performed on content or IDs.

Markdown escapes and character references decode under the selected inline grammar.
Marker spelling does not enter state when it represents the same model value.
Adjacent text nodes combine and empty text nodes disappear. Visually equivalent
formatting trees are not otherwise normalized. Code-text and opaque-payload
whitespace and newlines are content.

Serialize this object using JSON Canonicalization Scheme (JCS, RFC 8785), then
compute SHA-256 over its UTF-8 bytes. Encode the digest as Base64url (RFC 4648)
and take its first six characters, equivalently its first 36 bits encoded without
padding. Comment escaping is a file codec, not an additional step applied to JCS
bytes. Array order remains significant. The implementation defines the concrete
per-type `state` JSON representation consistently with §3 and fixes it in tests.
Reproducing a check requires that representation as well as this algorithm.

Changing a descendant's content does not change ancestors' checks unless their
own state or immediate-child structure changes. For a composed item record,
the item and first paragraph checks are independent; `first` is not hashed as a
second copy of the paragraph's contents in the item.

Readers MUST distinguish ownership/identity errors from check mismatch and MUST
NOT report absent, invalid, or uncomputable checks as matching. A match does not
resolve conflicts or exclude collisions and identical-state reassignment. A mismatch
establishes inconsistency, not its cause. Checks are neither authentication nor
unique content IDs and MUST NOT authorize identity recovery or retargeting.
Mismatch resolution is outside this contract.
Writers compute current checks for blocks whose resulting state they serialize.
Page records have no check.

## 8. Source preservation and unsupported content

Unmapped source, including foreign frontmatter and source omitted by a semantic
parser, MUST be preserved. Unsupported payloads retain their exact text, subject
only to §2 encoding rules.

Writers MUST preserve source outside the operation's scope. Changed supported
blocks MAY use canonical serialization without changing their resulting content,
identities, or properties. Rewriting an enclosing container MUST NOT alter other
blocks' content, identities, or properties or remove source dependencies.
Code text, including tabs, spaces, and trailing LFs, MUST survive serialization
and reopening.

### 8.1. Addressable opaque source

Opaque uses paired comments:

```markdown
<!-- noetec:opaque {"id":"O","check":"abc123","boundary":"unique-token"} -->

Source payload.

<!-- noetec:end-opaque {"boundary":"unique-token"} -->
```

The closing record contains only the matching `boundary`, not a second block ID or
check. This framing token is excluded from the check. Writers choose or replace it
to avoid payload conflicts without modifying the payload.

Boundaries occupy separate structural lines in the same container. A wrapper MUST
enclose complete syntax constructs without changing the structure of surrounding
content. Its scope expands to an enclosing block/container when needed to satisfy
these constraints, up to the body but not the page record.
Nested wrappers are unsupported; missing, competing, or ambiguous closures MUST
NOT be resolved by guessing.

An unwrapped unsupported region has no persistent opaque identity. Wrapper records
are structural metadata, not payload text. Payload contents are not interpreted
as blocks, metadata, or live references, even if a reader supports their syntax.

## 9. Block references

Block addresses use `[label](noetec://<page-id>/<block-id>)`. Updating a link
destination updates its containing block's state and check. Page UUIDs are
canonical lowercase; block IDs are UTF-8 percent-encoded as one path component.
Readers decode once without path normalization. Dot-only IDs have encoded dots.
Userinfo, ports, queries, fragments, extra components, or invalid escapes/IDs are
not valid addresses and MUST NOT be guessed into valid ones.

Only recognized semantic link destinations are live references. URI-looking text
in comments, arbitrary properties, code, and opaque source is not a live reference.

## References

- [CommonMark 0.31.2](https://spec.commonmark.org/0.31.2/)
- [GFM specification](https://github.github.com/gfm/)
- [RFC 2119](https://www.rfc-editor.org/rfc/rfc2119) and
  [RFC 8174](https://www.rfc-editor.org/rfc/rfc8174)
- [RFC 4648](https://www.rfc-editor.org/rfc/rfc4648)
- [RFC 8785: JSON Canonicalization Scheme](https://www.rfc-editor.org/rfc/rfc8785)
