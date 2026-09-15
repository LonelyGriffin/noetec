# 0008: HLC Drift Validation — Rejecting Future-Dated OpLog Entries

## Context

Noetec's OpLog orders entries by Hybrid Logical Clock, compared **component-wise
— `physicalMs`, then `counter`, then `deviceId`** (ADR-0006, `docs/specs/sync-security.md` §4.1,
`lib/entity/hlc.dart`). `physicalMs` is the wall clock of the *authoring* device
(`Hlc.now` = `max(wallMs, last.physicalMs)`), and `deviceId` is only the last
tie-breaker. A writer that stamps `physicalMs` far into the future therefore
outranks every honest entry — this is threat #5 (HLC spoofing) of the sync
security threat model (§10), and it is the only threat in the matrix left
uncovered by Phases 1–3.

The threat model (§1.3) grants the adversary read/write access to the shared
sync folder but **no** private keys. Such an adversary cannot forge signatures
(Phase 1), cannot join without a certificate (Phase 2), and cannot truncate
another device's file undetected (Phase 3) — but they *can* append to their own
file or replace another device's file with a copy that carries a future-dated
`hlc` and a valid signature of their own. Whenever such an entry is concurrent
with honest work, `MergeEngine` resolves in the attacker's favour:

- `MergeEngine.merge` takes the **fast-forward** path whenever the DAG topology
  is `linear` and rewrites the page from the HLC-**latest** head — the future
  head. With a `diverged` topology the same ordering decides which head is
  "latest" for the merge entry that is appended afterwards, so the future stamp
  keeps winning on the next cycle too.

§6 of the spec already states a bound — `entry.hlc.physicalMs <= localTime +
maxDrift`, default `maxDrift = 60 000 ms`, other devices only — but leaves four
mechanics open, which are exactly the design questions this phase had to settle:
reject vs flag, the default bound and its configurability, the effect on merge,
and the reporting surface.

Two properties of the existing implementation shape the answer:

1. **The violation is always a suffix of a device file.** `physicalMs` is
   non-decreasing across a device's own file (`Hlc.now` takes
   `max(wallMs, last.physicalMs)`), so the first entry above the bound implies
   every later entry in that same file is above it too.
2. **A device's file is the unit of read, verify, and gate.** `OpLogReader`
   reads one device file at a time, `OpLogVerifier` already applies
   chain rejection to a device file's tail (§2.4.3), and `OpLogAuthorizer`
   accepts or rejects whole device files. Rejecting a *suffix* is therefore the
   natural grain of the existing pipeline, while rejecting a *single mid-chain
   entry* is not: its descendants would keep a `parent` absent from the DAG,
   `OpLogDag._parentsOf` would silently treat them as roots, `OpLogDag.lca`
   would return `null`, and `MergeEngine.merge` would return `MergeNoop` — a
   silent non-merge that swallows a legitimate sibling branch.

## Decision

**Reject the drifted suffix of every other device's file, before the DAG is
built. Default `maxDrift` is 60 000 ms, configurable only larger, and every
rejection is reported.**

1. **Policy — reject, not flag-only.** `OpLogAuthorizer` gains a sixth check
   (§7 step 6) running after the registry filter: for each device file that is
   **not** the local device, the first entry with
   `physicalMs > localTime + maxDrift` and every entry after it in that file are
   dropped from `AuthorizationOutcome.accepted` and reported with a new reason
   token `hlc-drift`. `localTime` is `DateTime.now().millisecondsSinceEpoch` at
   read time.
2. **Suffix, not single entry** — required by point 2 above; it mirrors the
   §2.4.3 signature chain rejection and keeps the accepted prefix's ancestry
   intact, so a rejected future entry can never block a legitimate sibling
   branch.
3. **Non-destructive and self-healing.** The rejected entries stay in the
   authoring device's own file; nothing is rewritten, truncated, or deleted.
   The check is re-evaluated on every read, so the entries are accepted again as
   soon as the rejecting device's clock advances past the bound (§8.4:
   adopting drift validation **MUST NOT** invalidate already-merged entries).
4. **No HLC inheritance from a rejected entry.** A drifted entry **MUST NOT**
   be fed to `Hlc.receive`, so it cannot raise the local clock and thereby make
   this device's own future entries look drifted to its peers. (Today the OpLog
   path never adopts a remote `physicalMs`; the rule is stated so a later change
   cannot silently reintroduce the cascade.)
5. **Local device exempt.** A device never applies the check to its own file:
   it cannot be its own drift reference, and the local clock is trusted by
   construction.
6. **Bound and configurability.** `maxDrift` defaults to `60 000` ms and is
   vault-scoped local state (`ISettingsService`, key `sync.maxClockDriftMs`)
   that **MUST NOT** be synced. Only values **larger** than the default are
   accepted, clamped to `[60_000, 86_400_000]`; a tighter bound would only
   manufacture false positives — it cannot strengthen the guarantee, because the
   adversary picks a timestamp arbitrarily far in the future. The value is read
   once per sync cycle.
7. **Reporting.** The gate aggregates `hlc-drift` into the existing
   `EntryRejectionReport` chain (reason, affected device UUIDs, rejected entry
   count) extended with the observed drift in milliseconds, so the message can
   state *how far* ahead the device is. Rejections are logged via
   `package:logging` (§6, §9) and accumulated per sync cycle on
   `OpLogSystem.lastRejections` for the sync-status surface.
8. **Backward compatibility.** The check is additive and read-time only; it
   changes no wire format, no signature input, and no stored state, so adopting
   it does not invalidate existing data (§8.4).

## Status

Proposed — the normative wording of this decision is
`docs/specs/sync-security.md` §6 (with §7 step 6, §8.4, §9 and §10 updated);
implementation tasks are tracked as sub-issues of NOET-35.

## Consequences

- Positive: threat #5 is closed deterministically. A future-dated head can no
  longer enter the DAG, so it cannot win last-write-wins, cannot be picked as
  the fast-forward head, and cannot become the parent of a merge entry. The
  closed set is what makes the guarantee deterministic: the drift check only
  *removes* entries, so a device that rejects more than a peer cannot compute a
  different merge outcome from a smaller input — it converges as soon as the
  clocks do.
- Positive: no data loss and no permanent fork. A legitimately skewed device
  keeps writing locally; its peers merely postpone applying the drifted tail,
  and re-read it automatically once their clocks advance. The worst case is
  bounded by the drift window, not by the size of the file.
- Positive: no new state, no new file, no wire-format change; the check is an
  integer comparison on data already in memory, so the cost is negligible
  against signature verification.
- Negative: a device with a badly wrong clock (or one that intentionally keeps
  its clock ahead) is effectively muted for the duration of the skew — its
  newest edits do not reach its peers until the clocks converge. The default of
  60 s tolerates ordinary NTP-level skew; a manual clock error of hours is
  merely diagnosable, not self-correcting.
- Negative: the decision is clock-dependent, so two devices can momentarily
  disagree about which entries are visible and therefore diverge for up to the
  drift window before converging. This is inherent to any `localTime`-anchored
  bound (§6) and is why the check gates *acceptance* only and never rewrites the
  stored entries.
- Negative: the rejection is per device file, so a device whose whole tail is
  drifted loses its whole tail from the reader's DAG, not just the offending
  entry. That is the intended grain (point 2), and the rejected entries remain
  intact on disk.
- Negative (flagged risk, out of scope): the registry `revision` is also an HLC
  key and the local device *does* adopt it (`IRegistryService` → `Hlc.receive`).
  A future-dated registry revision — signed by an authorized identity key — would
  push the local clock forward and cascade into this device's own OpLog entries
  being rejected by its peers. Registries are signature-protected but not
  drift-checked; hardening that path is a separate follow-up.
- Negative: `localTime` is read from the device clock, which the user can
  change; a device whose clock is set *backwards* rejects less, and one set
  forwards rejects more. The bound is a spoofing deterrent, not a
  certified-time guarantee.

## Alternatives considered

- **Flag-only (accept the entry, report it).** Rejected: it does not close
  threat #5. The suspicious entry still enters the DAG, so it still wins
  last-write-wins and can still be chosen as the fast-forward head — the report
  is the only thing that changed. It would also contradict §6's norm that a
  suspicious entry **MUST NOT** be applied as a merge result without user
  awareness.
- **Flag-only, and let the merge engine prefer non-drifted heads.** Rejected:
  it makes content resolution depend on each device's clock, so two devices
  compute different merge outcomes from the same input and stop converging — the
  one property this architecture cannot give up. It also only delays the attack
  until the user confirms a prompt.
- **Reject the single offending entry only.** Rejected: it corrupts the DAG
  rather than protecting it. The rejected entry's descendants keep it as
  `parent`; `OpLogDag` cannot resolve that parent, so those descendants are
  treated as roots, the LCA with the other branch becomes `null`, and the merge
  degrades to `MergeNoop` — the sibling branch's content is silently never
  applied. A suffix rejection removes that whole class of failure.
- **Reject the whole device file rather than its drifted suffix.** Rejected:
  over-broad. The device's entire history — already merged, signed, and possibly
  the only copy of a page — would be discarded over a tail problem, turning a
  bounded availability cost into a data-visibility loss.
- **Rewrite or clamp the drifted timestamp** (e.g. treat the effective time as
  `localTime + maxDrift`). Rejected: `hlc` is part of the signed wire form
  (§2.2), so any rewrite invalidates the signature; and a per-device computed
  clamp is non-deterministic, so peers would merge the same entry at different
  positions in the total order.
- **Anchor the bound to the newest `physicalMs` observed from any device**
  rather than to `localTime`. Rejected: the adversary can drift every device
  they control by the same amount, so the reference becomes attacker-chosen and
  the bound stops being a bound. A wall-clock anchor is the only one the
  adversary in §1.3 cannot move.
- **Make `maxDrift` smaller to catch more attacks (or configurable in both
  directions).** Rejected: exposure is unbounded above, so tightening the bound
  rejects honest slow/skewed devices long before it rejects a determined
  attacker. Only loosening is offered, so the setting can buy availability but
  never silently weaken the default.
