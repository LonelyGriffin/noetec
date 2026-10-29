# Technical contracts

This directory defines data formats and protocol rules that implementations
must agree on. It does not contain user workflows, ADR rationale, rollout
plans, or guides to the current code.

## Catalog

| Contract | Scope | Document status |
|---|---|---|
| [Page file format](page-file-format.md) | Encoding, frontmatter, block directives, hashing, round-trip and version compatibility | Accepted, existing format version 1 |
| [Sync security](sync-security.md) | Signatures, registries, witness references, TOFU, verification, compatibility | Draft, format version 1; retained status, not newly approved |

Document status does not indicate implementation completeness. The base OpLog
format does not yet have a standalone contract here; the security document is
an extension, not a complete replacement for it. No new OpLog contract is
invented as part of this reorganization.

## Contract structure

Use this checklist for new contracts and substantive revisions. Existing section
numbers may be retained to preserve references; a wholesale rewrite is not required.

1. **Identity:** title, document status (`draft`, `accepted`, `deprecated`), and
   format/protocol version, if applicable. Approval status and format version
   are separate concepts; acceptance requires explicit project-owner approval.
2. **Scope:** what is governed, what is excluded, and prerequisite contracts.
3. **Definitions:** terminology and RFC 2119 requirement keywords.
4. **Contract:** schemas, encodings, invariants, algorithms, and error handling,
   with enough detail to test conformance independently of a particular codebase.
5. **Compatibility:** legacy input, version evolution, and migration behavior
   visible to readers or writers. Development rollout schedules do not belong here.
6. **Conformance evidence:** examples, fixtures, or test references. Label
   illustrative placeholders; examples do not override explicit requirements.
7. **References:** related contracts and existing ADRs, without copying their
   decision rationale.

Only accepted requirements take precedence over code within their declared
scope. Draft conflicts need review. Change accepted contracts explicitly rather
than adjusting prose solely to match implementation; follow their versioning
rules for format changes. Moving a document does not change a wire format or
approve a draft.

Implementation-dependent advice and rollout material extracted from sync security
are temporarily held in [the review notes](../sync-security-notes.tmp.md), outside
this contract layer.
