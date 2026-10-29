# Architecture decision records

ADRs record why an architectural approach was chosen: context, decision,
consequences, and rejected alternatives. This directory is the single ADR layer;
it does not duplicate behavior specifications or technical contracts.

## Find a decision

### Application architecture

| ADR | Topic |
|---|---|
| [0001](0001-flux-unidirectional-data-flow.md) | Flux-inspired unidirectional data flow |
| [0005](0005-get-it-di-ecosystem.md) | Dependency injection and the get_it/watch_it/listen_it/command_it ecosystem |

### Storage and document identity

| ADR | Topic |
|---|---|
| [0002](0002-block-ids-via-fenced-directives.md) | Stable block IDs via fenced directives in Markdown |
| [0004](0004-local-first-markdown-file-storage.md) | Local-first Markdown storage with YAML frontmatter |

### Synchronization, identity, and security

| ADR | Topic |
|---|---|
| [0003](0003-no-device-identity-until-sync.md) | Deferring device identity until synchronization exists |
| [0006](0006-sync-crypto-signatures.md) | Ed25519 signatures for OpLog security |
| [0007](0007-user-device-identity-and-registry.md) | User/device identity and sync registries |
| [0008](0008-hlc-drift-validation.md) | Rejecting future-dated OpLog entries |
| [0009](0009-witness-truncation-detection.md) | Witness references and history-truncation detection |

## Reading and adding ADRs

- Read the record's status and context; inclusion in this index does not mean
  every decision is implemented or applies unconditionally to current behavior.
- Existing ADRs are immutable. If a decision changes, add a new numbered ADR
  identifying which earlier decision it supersedes and why; do not rewrite history.
- Follow the existing `NNNN-descriptive-title.md` naming and sections: Context,
  Decision, Status, Consequences, and Alternatives considered.
- Keep acceptance scenarios in [specs/](../specs/README.md) and format/protocol
  rules in [contracts/](../contracts/README.md). Link to them instead of copying
  their requirements into a second source of truth.
- Update this index when adding a record. It is navigation, not an ADR itself.
- Historical document paths inside ADRs are preserved. Consult the
  [documentation index](../README.md#historical-paths) for moved contracts.
