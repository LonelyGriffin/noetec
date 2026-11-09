# Page Editing and Saving

**Status: draft.**

This specification defines application behavior for editing and saving Noetec
Markdown pages. The [page-file contract](../contracts/page-file-format-v3.md)
defines their syntax and representation.

**MUST** and **MUST NOT** have their RFC 2119 and RFC 8174 meanings.
Implementation coverage is not assessed by this draft.

## Editing guarantees

Every operation MUST preserve content, identities, and properties except for
changes explicitly defined by that operation. This includes editing opaque text.
Operations requiring unknown semantics are not applicable without a defined mapping.

Unsupported source MUST remain available as editable text without requiring a
separate whole-page source mode or a repair confirmation before ordinary saving.
Metadata-free export MUST preserve document structure rather than merely delete
comments.

## Identity establishment

Reading a page does not rewrite it or establish missing identities. An explicit
identity-establishing operation (adoption) assigns identities to identity-less blocks and
materializes opaque wrappers for unsupported regions it adopts.

When identity is established for a page with missing or malformed initial page
metadata, the application creates a new page record. Any damaged record is
preserved as opaque body source; its meaning is not reconstructed.

Page-identity ambiguity MUST NOT be resolved by choosing a file or renumbering
it. Retired identities MUST NOT be reused.

An unrelated edit MUST NOT establish an opaque identity by rewriting an unwrapped
unsupported region.

## Block operations

| Operation | Identity | Properties |
|---|---|---|
| Move or one-to-one conversion | Preserve | Preserve |
| Wrap | New container ID; preserve children | Children retain theirs; no automatic inheritance |
| Split | First result retains ID; others new | First retains; others empty unless specified |
| Merge | First in document order survives; others retire | Survivor retains; retired owners require resolution |
| Unwrap | Container retires; children survive | Children retain; container requires resolution |
| Copy | All copied block IDs new | Copy |
| Clear text | Preserve | Preserve |
| Delete | Retire | Explicit deletion |

Container merging does not implicitly merge child paragraphs. Moved children
retain IDs. Converting a paragraph to a list wraps the existing paragraph in new
list/item containers rather than assigning its ID to either container.
Clearing an item's first paragraph retains `first`; deleting that paragraph
removes it.

Copying opaque creates a new outer block ID and matching boundary records, while
preserving the payload and not inventing descendant identities or replacing
URI-looking strings. Operations requiring interpretation of unknown internal
references or structure are not applicable without an explicit supported mapping.

An operation MUST define treatment of properties on retired owners. Conflicting
unknown properties MUST NOT be silently discarded or merged by invented rules.
An operation without a defined lossless or explicit property-resolution outcome
is not applicable.

Text edits retain the opaque block's ID and properties. Changing or deleting its
identity-bearing wrapper records requires a defined identity operation.
Conversion to supported structure is explicit and MUST define the identity and
property result, even when a newer reader supports the payload's syntax.

## References during operations

Known merges retarget absorbed targets to the survivor. Unwrap or delete alone
does not retarget a container to its first child. Explicit target replacement
and cross-page moves update affected semantic references throughout the vault,
including unopened pages. Destination ID collisions block a move without silent
renumbering. Copy-internal references target the copies; references to outside
content and incoming references outside the copy remain unchanged.

Reference updates MUST NOT change non-reference text by string replacement.

## Save and recovery

An operation and its induced cross-file reference updates form one logical
transaction. Completed saving and crash recovery MUST leave either its prior
state or its complete result, not an arbitrary subset. A successful save MUST
durably preserve the complete result. Unavailable pages, unsafe writes, or
conflicts MUST NOT be reported as successful completion.

All saves verify the source revision being replaced, including metadata-only
and byte-level changes. Before overwriting externally supplied source with a
normalized representation, preserve its original bytes in recoverable history
or backup. The entry survives restart under a defined retention policy. Failure
to preserve it blocks overwrite, not ordinary inspection of the document.

Resource limits and invalid encodings MUST NOT result in truncated or lossy
documents being saved as complete. These requirements do not specify transaction
or history storage or independent file-sync delivery.

## Acceptance scenarios

### Read without adoption

| Step | Detail |
|---|---|
| **Given** | a page with missing identities and unwrapped unsupported source |
| **When** | the page is opened for reading |
| **Then** | the file is not rewritten and no persistent identities are established |

### Adopt damaged page metadata

| Step | Detail |
|---|---|
| **Given** | a page with malformed initial page metadata |
| **When** | the user establishes its identity |
| **Then** | a new page record is created and the damaged record is preserved as opaque body source |

### Edit unsupported source

| Step | Detail |
|---|---|
| **Given** | an opaque block with properties |
| **When** | the user edits its text, saves, and reopens the page |
| **Then** | the edited payload, block ID, and properties are preserved |
| **And** | saving requires neither whole-page source mode nor repair confirmation |

### Clear or delete the first paragraph

| Step | Detail |
|---|---|
| **Given** | an item with a first paragraph |
| **When** | the user clears its text |
| **Then** | `first` and the paragraph's identity and properties remain |
| **When** | the user deletes that paragraph |
| **Then** | `first` is removed and the paragraph identity retires |

### Move a referenced block between pages

| Step | Detail |
|---|---|
| **Given** | a block referenced by an unopened page and no destination ID collision |
| **When** | the user moves the block to another page and saving succeeds |
| **Then** | its block ID and properties survive and all affected semantic references target its new address |
| **And** | URI-looking non-reference text remains unchanged |

### External change before save

| Step | Detail |
|---|---|
| **Given** | the source revision has changed externally since it was read |
| **When** | the application attempts to save over that revision |
| **Then** | the conflict is detected and the stale overwrite is not reported as successful |

### Recovery of a cross-file operation

| Step | Detail |
|---|---|
| **Given** | an operation changes a page and references in other pages |
| **When** | saving is interrupted and crash recovery completes |
| **Then** | either the prior state or the complete operation result remains, never a partial result |

## Verification

Acceptance requires reproducible read → model → write → reopen fixtures,
check vectors using the implementation's fixed per-type state representations,
and operation/save/recovery cases covering the normative rules of this
specification and the page-file contract, including invalid and boundary inputs.
