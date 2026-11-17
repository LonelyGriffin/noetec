# 0009: Witness References and History Inconsistency Detection

## Context

Entry signatures do not prove that a stream contains all of its history. Removing
a signed suffix leaves a valid prefix. Observations recorded in other streams can
make some inconsistent truncation visible without a server or trusted third party.

## Decision

Entries may witness the latest observed heads of other per-page streams, identified
by `(userId, deviceId)`. Writers should include those observations and keep each
reference non-decreasing across their stream; a stream does not witness itself.
Only entries passing signature, trust, authorization, and drift checks supply
references. Evidence of the referenced head is evaluated over signature-verified
entries, even when authorization or drift excludes them from applicable history.
Presence of genuine history and permission to apply it are distinct questions.

When a referenced file exists but has no verified entry at or after the witnessed
HLC, report the dangling reference and exclude that remote stream from the page
DAG and merge decisions. Keep the referencing stream eligible. Never exclude the
local stream for a dangling witness; report the inconsistency and flag the page.
Malformed references are reported and ignored. Missing referenced files may be
ignored.

The [sync security contract](../contracts/sync-security-v2.md) defines wire
representation, ordering, and verification. The
[drift decision](0008-hlc-drift-validation.md) defines the separate applicability
gate for future-dated entries.

## Status

Accepted as part of the sync architecture. The detailed sync contract remains
draft; this is not a claim of implementation completion.

## Consequences

- Some inconsistent truncation or replacement becomes observable across streams.
- Remote-stream exclusion prevents its suspect history from contributing to merge.
  Retaining local history avoids discarding the user's own state based on remote
  allegations.
- Existence-based evidence does not prove exact historical content, freshness, or
  completeness. Consistent whole-folder rollback and unwitnessed truncation can
  remain undetected.
- An authorized participant can fabricate references and cause remote-stream
  exclusion. This policy does not protect availability against malicious users.
- Readers can temporarily differ because transport delivery and local-stream
  exceptions differ; witness detection is not a consensus mechanism.

## Alternatives considered

- **Signatures alone** — cannot distinguish an intact stream from its valid prefix.
- **Warn without excluding remote history** — still permits the suspect stream to
  influence merge decisions.
- **Exclude the referencing stream** — punishes the observer rather than the stream
  whose supplied history contradicts the observation.
- **Exclude the local stream too** — can hide local state without a trusted way to
  arbitrate the allegation.
- **Require exact referenced entries** — chooses stronger historical evidence than
  the selected at-or-after inconsistency policy.
- **Trusted server or collective consensus** — adds infrastructure or coordination
  not required for this limited detection mechanism.
