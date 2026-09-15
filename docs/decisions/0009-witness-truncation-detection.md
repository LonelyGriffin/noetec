# 0008: Witness References and Truncation Detection (Phase 3)

## Context

Phase 1 (per-entry Ed25519 signatures, ADR-0006) and Phase 2 (user/device
registries, ADR-0007) are implemented. Together they close entry forgery and
unauthorized participation, but they leave **history truncation** open
(threat 3 in `sync-security.md` §10, still ⚠️): every device appends only to its
own `<deviceId>.oplog.jsonl`, and a reader only ever sees the entries that are
present. Deleting the tail of *another* device's file leaves a valid signed
prefix, so a rollback is indistinguishable from "that device simply wrote
nothing more" — and the rolled-back state wins the merge.

`sync-security.md` §4 already defines the Phase-3 remedy normatively: an entry
**MAY**/**SHOULD** carry `seen` — `{deviceId: lastSeenHlcKey}`, the latest entry
its author observed from every other device. Because a reference lives in a
*different* device's file, truncating the referenced file becomes observable:
the reference outlives the entry it points at.

The field format is fixed by the spec. What the spec deliberately leaves to a
decision record is the **implementation policy**, and that policy decides
whether threat 3 is merely *detected* or actually *defeated*:

- where the observed heads come from on the write path, and how the
  non-decreasing rule (§4.2) is guaranteed;
- whether a dangling reference is evaluated against signature-verified or
  authorized entries, and where in the §7 pipeline the check belongs;
- what a dangling reference *does* — §4.3 says "SHOULD treat that file's
  entries as untrusted", so reject-by-default and warn-only are both
  conformant;
- the real overhead at the target scale (a family/team vault: ~2–10 devices).

Constraints: file-based sync only (ADR-0004), no server and no trusted third
party, offline-first, append-only JSONL, and full backward compatibility (§8).

## Decision

### 1. Field and wire form

- `seen` is a JSON object `{deviceUuid: hlcKey}`. The **key** is the
  referenced device's full `deviceUuid` (the same id used in `device`, in HLC
  *ordering*, and as the oplog file name). The **value** is an HLC key in the
  exact `hlc`/`parent` string form `<physicalMs>-<counterHex≥4>-<nodeId>`,
  where `nodeId` is the device's **hyphen-free 8-hex** id
  (`DeviceIdentity.truncatedDeviceId`) — **not** the full UUID. The full-UUID
  example in `sync-security.md` §4.1 does not parse as an HLC key and is a spec
  error (corrected there by this decision).
- `seen` is part of the wire object (`OpLogEntry.toWireMap`) and therefore of
  the signing input (§2.2). The key is **omitted** when there are no
  references — never emitted as `"seen": null` — so that the signing input
  re-derived from an existing signed entry stays byte-identical to the bytes
  that were signed.
- No `version` bump; a reader that does not know the key ignores it and
  preserves it on round-trip (§8.5).

### 2. Population (write path)

- `OpLogSystem` keeps a per-document observed-head cache:
  `relativePath -> {deviceUuid -> Hlc}` = the highest HLC observed from each
  **other** device. It is fed by every whole-document read
  (`OpLogReader.readAllLogs`, which the sync cycle already performs per page);
  when a document is first written in a session without having been read, the
  cache is seeded by one read pass over that document's device files — the
  same read the write path already does for the local file when resolving its
  parent.
- While composing an entry, each reference is
  `seen[d] = max(cache[d], previousEntryOfThisDevice.seen[d])`, compared
  component-wise by HLC — so §4.2's non-decreasing rule holds **by
  construction**, not by convention.
- A device never lists itself (§4.2); when no other device has been observed
  for the document, the field is omitted entirely.
- No change to when entries are written: population is pure derivation from
  state the write path already owns.
- Legacy/Phase-1/Phase-2 devices keep writing entries without `seen`; nothing
  forces migration.

### 3. Verification (read path)

- A dedicated checker runs inside `OpLogSystem.buildDag`, **after** the
  verification gate (signature §2.4 → TOFU → certificate → registry filter,
  §7 steps 2–5) and **before** `OpLogDag.fromEntries` — i.e. at §7 step 7.
  §7 step 6 (HLC drift) is not adopted yet; when it lands it runs before this
  check and does not change it.
- The checker consumes two inputs at deliberately different trust levels:
  - **references** — `seen` from entries that passed the *full* chain
    (accepted). A rejected entry's references never count: an entry we refuse
    to merge must not be able to condemn another file (§2.4 rule 6).
  - **evidence** — for each referenced device, whether its file holds an entry
    HLC-ordered at or after the referenced key, evaluated over the
    **signature-verified** entries read from that file (§2.4) *before* the
    authorization filter. Existence is what matters here: a genuine-but-
    revoked device's file must not be reported as truncated, and its own
    truncation must still be detected.
  - **presence** — the referenced device's file exists on disk. A missing file
    is **not** dangling (§4.3): the device may legitimately be gone.
- Classification:
  - `dangling-witness-ref` — **actionable**. File exists ∧ no verified entry
    HLC-ordered at or after the reference (a file that exists but yields no
    verified entries — emptied or fully truncated — counts as containing
    none).
  - `malformed-witness-ref` — **report-only**. A reference that does not parse
    as an HLC key, whose `nodeId` is not the referenced device's, or that names
    the entry's own device (§4.2 MUST NOT). The entry is signature-valid and is
    **not** rejected: a defective witness is a defect, not an attack signal.
  - No timestamp-plausibility bound is applied to references. It would be
    trivially bypassed — a device that fabricates a reference also writes its
    own `hlc` — while costing detection between clock-skewed peers, and the
    future-dating dimension belongs to §6 (Phase 4b).
- Violations are reported through `package:logging` and through a
  `lastWitnessViolations` accessor on `OpLogSystem` (mirroring
  `lastRejections`); the affected document is marked `suspicious` in
  `SyncSystem`.

### 4. Policy: a dangling reference makes the referenced file untrusted

- Report the dangling reference(s) — referenced file, key, referencing entry —
  and **exclude the referenced device's entries from that document's DAG**, so
  the rolled-back state cannot contribute to merge decisions.
- The **referencing** device is never punished: its entries stay in the DAG.
- **Exception — the local device's own file is never excluded.** Excluding it
  would destroy the user's own local state with no way to arbitrate; the
  violation is reported and the document flagged instead.
- Rationale for dropping rather than warning: a *consistent* rollback of the
  whole `.sync/` tree produces **no** dangling references (every file, and
  every reference in it, moves back together), so dangling references only
  appear when files disagree — i.e. selective truncation, partial restore, or
  whole-file replacement. Dropping the disagreeing file is therefore precise,
  and it is the difference between detecting the attack and stopping it.

### 5. Reporting surface

- Minimum: `package:logging` (§9 item 5) plus the `OpLogSystem` accessor and
  the `SyncSystem` document state above.
- A user-facing sync-status surface is **out of scope** for this decision:
  `SyncSystem.status` / `documentStateOf` currently have no consumer in the UI
  at all, so exposing truncation to the user is a separate, UI-scoped task.

## Status

Accepted.

## Consequences

- Positive: threat 3 moves from detected-on-paper to **defeated in practice**
  for any entry a Phase-3 device has already witnessed — a selective rollback
  now costs the attacker that file's contribution to the merge instead of
  silently rewriting history.
- Positive: the realistic file-sync failure mode — an *inconsistent* (partial)
  folder restore — surfaces as dangling references. A *consistent* whole-folder
  rollback produces none and stays invisible: that is an unchanged limitation
  of file-based sync with no external anchor.
- Positive: cheap. Size: ≈75 bytes per other device per entry (36-byte UUID +
  ~34-byte HLC key + syntax) → with a ≈700-byte signed entry, ≈+10% for 2
  devices, ≈+35% for 4, ≈+85% for 10 — and only for devices that actually
  contributed to that document, since the map carries observed devices, not
  registered ones. CPU: one extra O(entries) pass per file to derive per-device
  heads, plus O(references) comparisons per document — single-digit
  milliseconds at 10⁴ entries per page.
- Positive: no new on-disk format, no version bump, no wire break for older
  readers (§8.5).
- Negative: detection depends on observation. An entry becomes detectable only
  after another Phase-3 device has read it, so a tail truncated before any peer
  saw it is invisible, and a single-device vault has no coverage at all by
  construction.
- Negative: the observed-head cache is in-memory in v1. After a restart, the
  first write to a document may carry no or partial references until the
  document is read again. Accepted because §4.2 is SHOULD-level and a persisted
  cache would add a local format and a lifecycle for a marginal gain; a device
  that has just read the document (the common case before an edit) is fully
  covered.
- Negative: an **authorized member** device can fabricate references and cause
  another device's entries to be excluded from a page. This is an accepted
  limit, not an oversight: fabricating a reference grants no power the member
  does not already have — the threat model (§1.3) gives every participant
  read/write access to the shared folder, so the same member can truncate that
  file directly and produce the identical outcome. No guard is added for it,
  and the fingerprint of the exclusion (report + suspicious state) is what the
  user sees.
- Negative: exclusion can make a document appear to lose recent changes. The
  user sees the suspicious state and the report; resolution is manual (restore
  the file, or accept the rollback by re-adopting the device).
- Negative: new code paths (cache, checker, policy) whose destructive branch
  needs false-positive tests — missing file, legacy/`seen`-less entries,
  unauthorized-but-genuine file.

## Alternatives considered

- **Warn-only** (report dangling references, merge the truncated file anyway) —
  rejected: it detects but does not defeat the attack; the rolled-back state
  still wins the merge, so threat 3 stays ⚠️ and Phase 3 buys little.
- **Exclude every file involved in an inconsistency** (referencing and
  referenced) — rejected: it amplifies one truncated file into a wipe of the
  page and punishes the witnesses that make detection possible.
- **Also exclude the local device's own file** — rejected: unrecoverable local
  data loss for the user, with nothing to arbitrate it.
- **Make `seen` mandatory / reject entries without it** — rejected: breaks
  backward compatibility (§8.1, §8.3) and rejects every Phase-2 device and
  every legacy entry.
- **Hash-chained entries (`prevHash`)** — rejected as a substitute: a chain
  catches *middle* tampering, but a truncated tail is still a valid chain, so
  tail truncation still needs an external witness to be visible. Complementary,
  not alternative; deferred — it would add a field, a verification pass and a
  migration for a benefit `seen` already delivers across devices.
- **Per-device monotonic counter replicated in every entry** — equivalent
  detection power, but it duplicates what HLC keys in `seen` already carry and
  needs agreement on the counter's authority; rejected as more machinery for
  the same result.
- **Persist observed heads in `.sync/`** — rejected: the shared area is
  attacker-writable and attacker-readable (§1.3); publishing local observation
  state there adds a tamper target and leaks device activity for no gain.
  `.noetec/` is the right home if persistence is ever added.
- **Bound reference timestamps against the referencing entry's own `hlc`**
  (report references dated more than `maxDrift` ahead) — rejected: it stops
  nothing, because the device fabricating the reference writes its own
  timestamp as well, while it would suppress detection coming from honest
  peers whose clocks run ahead. Future-dating is §6's dimension.
- **External anchoring (timestamping / transparency service)** — rejected:
  contradicts local-first file-based sync (ADR-0004) and reintroduces the
  trusted third party the identity model deliberately avoids (ADR-0007).
- **Block sync for the whole document on detection** — rejected: one truncated
  file would stop the page's sync entirely instead of letting healthy devices
  converge.
- **Per-file check at read time (before authorization) instead of a
  DAG-level pass** — rejected: references must come from entries that passed
  the full chain while evidence must come from signature-verified entries
  regardless of authorization, and only the post-gate stage sees all device
  files of the document at once.
