# Architecture decision records

These are the current architectural decisions: context, chosen approach,
consequences, and important alternatives. Keep one current record per topic;
revise it when the decision changes. Move replaced decisions to the archive.
Contracts define formats and protocols; specifications define observable
behavior. ADRs explain the choices without duplicating those requirements.

## Find a decision

### Application architecture

| ADR | Topic |
|---|---|
| [0001](0001-flux-unidirectional-data-flow.md) | Flux-inspired unidirectional data flow |
| [0005](0005-get-it-di-ecosystem.md) | Dependency injection and the get_it/watch_it/listen_it/command_it ecosystem |

### Storage and document identity

| ADR | Topic |
|---|---|
| [0002](0002-in-band-block-metadata.md) | Block identities and metadata in Markdown comments |
| [0004](0004-local-first-markdown-file-storage.md) | Local-first Markdown storage, page identity, and own-state checks |

### Synchronization, identity, and security

| ADR | Topic |
|---|---|
| [0006](0006-sync-crypto-signatures.md) | Ed25519 signatures for OpLog security |
| [0008](0008-hlc-drift-validation.md) | Rejecting future-dated OpLog entries |
| [0009](0009-witness-truncation-detection.md) | Witness references and history-truncation detection |
| [0010](0010-vault-scoped-user-keys-and-device-registry.md) | Vault-scoped user keys, strict device registries, rotation, and witnesses |

## Reading and adding ADRs

- A decision's presence here does not mean it is fully implemented. Check its
  status and the linked contract or specification.
- Keep the current document self-contained. Do not add supersession chains or
  explanations of replaced decisions; Git retains revision history.
- Archive a replaced ADR under [the archive](../archive/README.md), preserving
  its filename and adding a brief notice. Do not keep competing decisions here.
- Follow the existing `NNNN-descriptive-title.md` naming and sections: Context,
  Decision, Status, Consequences, and Alternatives considered.
- Keep acceptance scenarios in [specs/](../specs/README.md) and format/protocol
  rules in [contracts/](../contracts/README.md). Link to them instead of copying
  their requirements into a second source of truth.
- Update this index when adding a record. It is navigation, not an ADR itself.
