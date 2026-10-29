# Documentation

| Layer | Purpose | Entry point |
|---|---|---|
| Behavior specifications | User-visible scenarios and acceptance criteria: what happens | [specs/](specs/README.md) |
| Technical contracts | Persistent formats, protocols, and compatibility rules | [contracts/](contracts/README.md) |
| Architecture decisions | Why an approach was chosen; immutable ADR history | [decisions/](decisions/) |
| Product direction | Product goals and future capabilities | [product/vision.md](product/vision.md), [roadmap](product/ROADMAP.md) |

[architecture.md](architecture.md) maps the current code; it is not a substitute
for a behavior specification or technical contract.
[release-process.md](release-process.md) describes the release workflow.

Accepted requirements take precedence over code within their stated scope.
Draft proposals, examples, temporary notes, and product plans do not become
accepted requirements merely by being placed in `docs/`. Report conflicts and
resolve them explicitly; do not silently rewrite a contract to match code.
Implementation coverage is separate from document approval.

No separate planning or technical-guide layer is introduced here.
[sync-security-notes.tmp.md](sync-security-notes.tmp.md) is temporary,
non-normative material awaiting manual processing, not a new documentation layer.

## Community

- [Contributing](CONTRIBUTING.md) — setup, contribution workflow, and checks.
- [Code of conduct](CODE_OF_CONDUCT.md) — community standards and reporting violations.
- [Security](SECURITY.md) — confidential vulnerability reports.
- [Support](SUPPORT.md) — questions and help.

Translations live next to these documents; use the language links at the top.
The project overview, license, authors, changelog, and agent instructions remain
in the repository root.

## Historical paths

The technical contracts were moved without changing the scenario specification:

| Old path | Current path |
|---|---|
| `docs/specs/file-format.md` | `docs/contracts/page-file-format.md` |
| `docs/specs/sync-security.md` | `docs/contracts/sync-security.md` |

Existing ADRs retain historical paths and phase names because ADRs are immutable.
Use this mapping when following their references. New references use current paths.
