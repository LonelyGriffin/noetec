# Noetec Page File Format

**Format version: 1**

This document is the normative specification of the on-disk format of a Noetec
page file. It is a contract: implementations (parsers, serializers, sync
engines, external tools) **MUST** conform to this document. If an
implementation diverges from this specification, that is a bug in the
implementation, not in this document.

The key words **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY**
in this document are to be interpreted as described in RFC 2119.

This specification is self-contained: a reader can implement a correct parser
and serializer for the page file format from this document alone.

---

## 1. Overview

A Noetec page is stored as a single UTF-8 encoded text file with the `.md`
extension. The file consists of two parts, in order:

1. An optional **frontmatter block** carrying page metadata.
2. The **content body**: GitHub-Flavored Markdown in which every top-level
   block is wrapped in a **fenced block directive** that carries the block's
   stable identifier.

```text
┌─────────────────────────────┐
│ ---                         │ ┐
│ id: <uuid>                  │ │
│ content_hash: sha256:<hex>  │ │  frontmatter block (optional on read,
│ modified: <iso8601>         │ │  mandatory on write)
│ ---                         │ ┘
│                             │
│ ::: {#block-id-1}           │ ┐
│ First block markdown.       │ │
│ :::                         │ │  content body
│                             │ │
│ ::: {#block-id-2}           │ │
│ Second block markdown.      │ │
│ :::                         │ ┘
└─────────────────────────────┘
```

---

## 2. Character encoding and line endings

- The file **MUST** be encoded as UTF-8 without a byte order mark (BOM). A
  parser **MAY** accept and silently strip a leading BOM.
- On **write**, all line endings in the file **MUST** be LF (`\n`, U+000A).
- On **read**, a parser **MUST** normalize CRLF (`\r\n`) and lone CR (`\r`)
  line endings to LF before any further processing (frontmatter detection,
  hashing, block parsing). Files originating on Windows are therefore valid
  input; normalizing them is part of parsing, not an error.

The normalized form (LF only) is the canonical form. Everywhere this
specification refers to "the content" (including the hash input in §5), it
means the **normalized** content.

---

## 3. Frontmatter block

### 3.1 Delimiters and placement

The frontmatter block, when present:

- **MUST** start at byte offset 0 of the file (after any stripped BOM).
- **MUST** begin with a line consisting of exactly three hyphen-minus
  characters `---`.
- **MUST** end with a subsequent line consisting of exactly `---`.
- The text between those two delimiter lines is the **frontmatter body** and
  **MUST** be a single YAML mapping (`key: value` pairs, one per line).

Everything after the closing delimiter line is the content body. If the line
immediately following the closing delimiter is blank, a parser **MUST**
consume that single blank line as a separator (i.e. it is not part of the
content body).

### 3.2 Schema

The frontmatter mapping defines the following keys:

| Key            | Type   | Required on write | Description                                                                 |
| -------------- | ------ | ----------------- | --------------------------------------------------------------------------- |
| `id`           | string | **MUST**          | Stable page identifier. A UUID (RFC 4122, version 4 recommended), lowercase hex with hyphens. Stable across renames and moves of the file. |
| `content_hash` | string | **MUST**          | `sha256:` followed by the 64-character lowercase hex SHA-256 digest of the content body, computed as specified in §5. Used to detect external edits. |
| `modified`     | string | **MUST**          | Timestamp of the last save, as an ISO 8601 date-time in UTC, e.g. `2026-01-15T10:30:00.000Z`. **MUST** be parseable by ISO 8601 parsers. |
| `modified_by`  | string | **SHOULD**        | UUID of the device that performed the last save. Omitted when unknown.      |

Additional keys **MAY** appear in the mapping. A parser **MUST** ignore keys
it does not recognize and **MUST NOT** fail because of them.

Key order in the mapping is not significant on read. On write, implementations
**SHOULD** emit the keys in the order shown above for deterministic diffs.

### 3.3 Serialization form

On write, the frontmatter block **MUST** be serialized exactly as:

```text
---\n
id: <uuid>\n
content_hash: sha256:<hex>\n
modified: <iso8601>\n
[modified_by: <device-uuid>\n]
---\n
\n
<content body>
```

That is: opening delimiter, one `key: value` line per key (single space after
the colon, values unquoted unless YAML requires quoting), closing delimiter,
one blank separator line, then the content body.

### 3.4 Missing, malformed, and edge-case input (normative)

A parser **MUST** handle the following inputs without error:

1. **Missing frontmatter.** If the file does not begin with a `---` delimiter
   line, the parser **MUST** treat the entire file as the content body and
   **MUST** synthesize a fresh frontmatter: a new random UUID for `id`,
   `content_hash` set per §5, `modified` set to the current UTC time.
2. **Malformed YAML.** If a frontmatter-looking block is present (file starts
   with `---`) but its body is not parseable YAML, or parses to something
   other than a YAML mapping, the parser **MUST** discard the frontmatter and
   behave as in case 1: the **entire file, including the malformed block**, is
   treated as content, and a fresh frontmatter with a fresh `id` is
   synthesized. The parser **MUST NOT** crash or reject the file.
3. **Missing keys.** If the YAML mapping parses but individual keys are
   absent: `id` **MUST** be regenerated as a fresh UUID; `modified` **MUST**
   default to the current UTC time; `content_hash` **MUST** be recomputed per
   §5; `modified_by` is treated as absent.
4. **Empty file.** A zero-byte file, or a file containing only whitespace,
   **MUST** parse to an empty content body plus a fresh frontmatter (fresh
   `id`, current `modified`).
5. **Windows line endings.** A file with CRLF (or lone CR) line endings is
   valid input and **MUST** be handled per §2 (normalize first, then apply
   cases 1–4 to the normalized text).
6. **Unterminated frontmatter.** If the file starts with `---` but no closing
   `---` line exists, the input is treated as malformed (case 2): the whole
   file is content, fresh frontmatter is synthesized.

In cases 1, 2, 4, and 6 the page's identity is newly minted on every fresh
parse of that file until the page is saved; on save the synthesized
frontmatter is written to disk and the `id` becomes stable from then on.

---

## 4. Block directives

### 4.1 Purpose

The content body is GitHub-Flavored Markdown. Every top-level block of the
document **MUST** be wrapped in a **fenced block directive** that binds the
block's markdown to a stable, unique **block id**. Block ids are the anchor
for editing, the operation log, and sync: they let the system address a block
independently of its position in the file.

### 4.2 Syntax

A block directive consists of an **opening fence**, zero or more lines of
block content, and a **closing fence**:

```text
::: {#<block-id>}
<block markdown, zero or more lines>
:::
```

- **Opening fence.** A line matching: three or more `:` characters, optional
  whitespace, an attribute block `{...}`, optional trailing whitespace, end of
  line. Formally: `^:{3,}\s*\{([^}]*)\}\s*$`.
- **Closing fence.** A line matching: three or more `:` characters, optional
  trailing whitespace, end of line. Formally: `^:{3,}\s*$`.
- **Attribute block.** The text between `{` and `}` of the opening fence, in
  pandoc-style attribute syntax. The following attributes are defined:
  - `#<id>` — the block id. **MUST** be present on write. The id is a
    non-empty string of word characters and hyphens (`[\w-]+`, i.e.
    `A–Z a–z 0–9 _ -`). It **MUST** be unique within the file.
  - `.<class>` — a class annotation. Currently reserved; parsers **MUST**
    accept and ignore it.
  - `key="value"` / `key='value'` / `key=value` — arbitrary key/value
    metadata. Parsers **MUST** accept unknown keys and **MUST** preserve them
    on round-trip whenever feasible.

On write, implementations **MUST** emit exactly three colons and a single
space before the attribute block: `::: {#<id>}` followed by any additional
attributes, then the closing fence as exactly `:::`.

### 4.3 Content of a directive

- The lines between the opening and closing fences are the block's markdown
  content. An empty block (opening fence immediately followed by the closing
  fence, or with only blank lines between) is valid and represents an empty
  text block.
- The block content is parsed as ordinary GitHub-Flavored Markdown. Within one
  directive, the content **MUST NOT** contain a line that matches the closing
  fence pattern `^:{3,}\s*$`; a serializer **MUST NOT** emit such a line
  inside a block, and a parser treats the first such line as the closing
  fence.
- Directives **MAY** be nested (a directive may appear inside another
  directive's content). This specification defines the flat top-level
  structure only; nested semantics are defined by the block model and are out
  of scope for this document.
- Top-level blocks **MUST** be separated from each other by exactly one blank
  line on write.

### 4.4 Bare markdown (normative)

Markdown outside any directive — e.g. a hand-written file, a file from an
external editor, or legacy content — is valid input. A parser **MUST** accept
it and **MUST** wrap each resulting top-level markdown block in a fresh
directive with a newly generated block id on the next save. A document with no
directives at all therefore still parses: its paragraphs become blocks.

### 4.5 Inline formatting

Inline formatting within block content uses standard Markdown, with the
following mapping to the block model:

- `**text**` — bold.
- `*text*` — italic.
- `***text***` — bold and italic.
- `[text](url)` — link.

On write, the following characters in plain text **MUST** be backslash-escaped
when they appear literally in content:

```text
\  *  _  [  ]  (  )  ~  `  >  #  +  -  =  |  {  }  .  !
```

On read, a backslash followed by any of those characters **MUST** be
interpreted as the literal character (standard CommonMark hard escaping).

---

## 5. Content hash algorithm

`content_hash` detects external modification: a change to the file outside the
application's own save path produces a different hash.

The hash **MUST** be computed as follows, in exactly this order:

1. Read the file as UTF-8 text.
2. **Normalize line endings** to LF per §2.
3. **Remove the frontmatter block**: the opening `---` line, the YAML body,
   the closing `---` line, and the single blank separator line immediately
   following it (if present). What remains is the content body. (If the
   frontmatter is missing or malformed, the entire normalized file is the
   content body per §3.4.)
4. Encode the content body as UTF-8 bytes.
5. Compute the SHA-256 digest of those bytes.
6. Format as `sha256:` followed by the 64-character lowercase hex digest.

The stored `content_hash` value in frontmatter **MUST** equal the result of
this algorithm applied to the file's own content body at the time of the last
save. A consumer that recomputes the hash of a file on disk and finds a
mismatch **MUST** treat the file as externally modified.

Note that the hash input is the content body only — never the frontmatter —
so updating `modified` or `modified_by` on save does not by itself change the
hash.

---

## 6. Round-trip requirements

An implementation that parses and re-serializes a conforming file **MUST**
satisfy:

- **Id stability**: page `id` and all block ids present on input are
  preserved unchanged on output.
- **Content stability**: reparsing the serialized output yields a block
  sequence equal to the input's (same ids, same text, same formatting,
  same links).
- **Hash consistency**: after any save in which the content changed, the
  written `content_hash` matches the algorithm in §5 applied to the written
  file.

Exact byte-level round-tripping of arbitrary hand-edited whitespace is not
required; semantic round-tripping of the block model is.

---

## 7. Example

A complete, conforming page file:

```markdown
---
id: 3f8a2c1e-9b7d-4e5f-a6c8-1d2e3f4a5b6c
content_hash: sha256:9b74c9897bac770ffc029102a200c5de
modified: 2026-08-26T17:45:12.310Z
modified_by: 7c1e2d3a-4b5f-4a6b-8c9d-0e1f2a3b4c5d
---

::: {#b-welcome}
Welcome to **Noetec**.
:::

::: {#b-todo}
- [ ] Read the [file format spec](https://example.com/spec)
:::
```

---

## 8. Versioning

- This document specifies **format version 1**. There is no version marker in
  the file itself for version 1; the format described here is the implicit
  baseline.
- Any future change to the rules in this document (frontmatter schema, fence
  syntax, hash algorithm, normalization rules) **MUST** be published as a new
  numbered version of this specification, and **MUST** introduce an explicit
  in-file version indicator if the change is not backward-readable by version
  1 parsers.
- Every spec version **MUST** ship with at least one new **golden fixture**: a
  checked-in example file plus its expected parse result, used by the
  round-trip tests to pin the contract. Golden fixtures for older versions
  **MUST** be kept and **MUST** continue to pass: new parsers remain able to
  read old files, or an explicit migration path is specified in the new
  version.
- Changes to the format and changes to this specification **MUST** land
  together: an implementation change without the corresponding spec-version
  bump and golden fixture is incomplete.
