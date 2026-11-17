# 0008: HLC Drift Validation for Remote OpLog Entries

## Context

A signed entry can still carry an excessively future-dated clock. Allowing it
into applicable history can distort ordering and propagate the timestamp into
local clocks. Honest clock skew must remain recoverable without rewriting logs.

## Decision

Before building applicable history, exclude the first remote-stream entry above
the reader's wall-clock drift bound and the stream's remaining suffix. Excluding
the suffix prevents dependent entries from surviving without their predecessor.

The default allowance is 60 seconds. It is vault-scoped local configuration,
not shared authorization state, and may be increased but not reduced below the
default. The local user's own device stream is exempt.

Excluded entries do not advance the local HLC or supply witness references.
Report the affected stream and reason without rewriting or deleting its source.
Re-evaluate on reads: clearing the drift exclusion does not bypass other checks.
Registry timestamps are outside this gate.

The [sync security contract](../contracts/sync-security-v2.md) defines the bound
and verification rules. The [witness decision](0009-witness-truncation-detection.md)
distinguishes applicable references from signature-verified evidence.

## Status

Accepted as part of the sync architecture. The detailed sync contract remains
draft; this is not a claim of implementation completion.

## Consequences

- Excessively future-dated remote entries cannot influence current merge decisions
  or raise the local HLC through those entries.
- Legitimately skewed entries remain available and can become eligible later.
- Readers with different clocks can temporarily disagree about applicable history.
  The gate is not certified time or a general guarantee of convergence.
- Large clock errors can delay visibility for much longer than the default allowance.
- Registry timestamps and other authorization checks need their own rules.

## Alternatives considered

- **Warn only** — leaves the future-dated entry in merge decisions.
- **Exclude only one entry** — leaves descendants dependent on excluded history.
- **Exclude the whole stream** — unnecessarily hides its eligible prefix.
- **Clamp or rewrite timestamps** — changes signed data and introduces reader-local
  ordering values.
- **Use remote observed time as the bound** — lets remote writers choose the clock
  against which their entries are checked.
