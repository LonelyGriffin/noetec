// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'package:logging/logging.dart';

import 'package:noetec/service/trust_store.dart';
import 'package:noetec/systems/oplog_system/hlc_drift_gate.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';
import 'package:noetec/systems/sync_system/registry/registry_models.dart';
import 'package:noetec/systems/sync_system/registry/registry_service.dart';

/// The outcome of the verification chain for a single OpLog entry
/// (sync-security.md §3.5, §7).
///
/// Signature verification (§7 steps 1–2, NOET-28) is performed by
/// [OpLogVerifier] at read time, *before* the entries reach this gate. This
/// gate enforces the steps that follow: **TOFU** (§5.2), **certificate**
/// (§3.3) and **registry filter** (§3.5).
sealed class EntryAuthorization {
  const EntryAuthorization();
}

/// The entry passed the full attribution chain and may contribute to the DAG.
final class EntryAuthorized extends EntryAuthorization {
  const EntryAuthorized();
}

/// The entry was rejected: the device's observed key differs from the
/// TOFU-pinned key (key substitution, §5.2 rule 3).
final class EntryKeySubstituted extends EntryAuthorization {
  const EntryKeySubstituted({required this.storedKey, required this.observedKey});

  final String storedKey;
  final String observedKey;
}

/// The entry was rejected: the TOFU trust store could not be read for the
/// device (malformed `trusted_keys.json`, §8.4). Distinct from key
/// substitution — a store failure must not prompt the user to "confirm a new
/// key". The device is conservatively rejected; the failure is logged.
final class EntryTrustStoreError extends EntryAuthorization {
  const EntryTrustStoreError();
}

/// The entry was rejected: the device is not bound to a user by a valid
/// certificate in any `devices/<userId>.json` (§3.3, §3.5.1).
final class EntryUnboundDevice extends EntryAuthorization {
  const EntryUnboundDevice();
}

/// The entry was rejected: the device's user is absent from `users.json` or
/// revoked (`removedAt`), or the device certificate is a tombstone (§3.5.2).
final class EntryUnauthorizedUser extends EntryAuthorization {
  const EntryUnauthorizedUser();
}

/// One line of the per-sync-cycle rejection report surfaced in the sync status
/// and the logs (sync-security.md §9: rejections MUST be reported, never
/// silently dropped).
final class EntryRejectionReport {
  const EntryRejectionReport({required this.reason, required this.devices, required this.entryCount, this.observedDriftMs});

  /// A short reason token (`key-substitution`, `trust-store-error`,
  /// `unbound-device`, `unauthorized-user`, `hlc-drift`) for grouping and
  /// matching.
  final String reason;

  /// The affected device UUIDs, sorted for stable output.
  final List<String> devices;

  /// The number of rejected entries.
  final int entryCount;

  /// How far ahead of the reader's clock the rejected entries are, in
  /// milliseconds (sync-security.md §6: the report names the *observed
  /// drift*). `null` for reasons that carry no clock information; present
  /// (and positive) for `hlc-drift`, where it is the per-device maximum of
  /// `physicalMs - localTime` over the rejected suffix — drift reports are
  /// kept one-per-device-file, so this is unambiguous.
  final int? observedDriftMs;

  @override
  String toString() {
    final noun = entryCount == 1 ? 'entry' : 'entries';
    final drift = observedDriftMs == null ? '' : ' (observed drift: $observedDriftMs ms)';
    return '$reason: $entryCount $noun from device(s) ${devices.join(', ')} rejected$drift';
  }
}

/// The result of the verification chain over the entries of one document.
final class AuthorizationOutcome {
  const AuthorizationOutcome({required this.accepted, required this.rejections});

  /// The entries that passed the full chain, keyed by device — ready for
  /// [OpLogDag.fromEntries].
  final Map<String, List<OpLogEntry>> accepted;

  /// The aggregated rejection reports, one per rejection reason.
  final List<EntryRejectionReport> rejections;

  bool get hasRejections => rejections.isNotEmpty;
}

/// The registry input of the attribution gate: the canonical `users.json`
/// plus every user's canonical `devices/<userId>.json`.
///
/// A [RegistrySnapshot] is the result of one full load+verify pass over the
/// registry area ([loadSnapshot]). The sync pipeline loads it **once per sync
/// cycle** ([OpLogSystem.prepareVerification]) and threads it through every
/// [OpLogAuthorizer.authorize] call of that cycle, so the expensive
/// read-parse-verify work (O(users), with whole-file and per-record
/// signature checks) is not repeated for every `.oplog.jsonl` file.
///
/// A snapshot is a point-in-time read of the registry, and the gate is
/// stateless with respect to it: it does not observe or mutate the registry,
/// so a snapshot loaded at the start of a cycle remains valid for the whole
/// cycle.
final class RegistrySnapshot {
  const RegistrySnapshot({required this.users, required this.deviceFiles});

  /// The canonical user registry, or `null` when absent/unreadable (the vault
  /// is public, §8.2).
  final UserRegistry? users;

  /// The canonical device registries, keyed by `userId` — loaded for every
  /// user listed in [users] (including revoked users, so a device bound to a
  /// revoked user resolves to that user and is rejected as
  /// `unauthorized-user` rather than merely unbound).
  final Map<String, DeviceRegistry> deviceFiles;
}

/// Runs the attribution/authorization portion of the verification chain
/// (sync-security.md §7) that [OpLogVerifier] does not: **TOFU** (§5.2),
/// **certificate** (§3.3), **registry filter** (§3.5) and, for every device
/// file that is **not** the local device's, the **HLC drift** check (§6).
///
/// [OpLogVerifier] already runs the §7 steps 1–2 (parse + signature + chain
/// rejection) using the same `canonical_json` signing input as NOET-28; the
/// entries handed to this gate have therefore already been signature-checked.
/// This gate then ensures that every entry is *attributable to an authorized
/// user's device*:
///
/// 1. its device key passes TOFU (pinned / verified, not substituted);
/// 2. the device is bound to a user by a valid certificate in
///    `devices/<userId>.json` whose `devicePublicKey` matches the key the
///    entry verified under;
/// 3. that user is authorized in `users.json` (listed and not revoked);
/// 4. and, if the device is not the local device, its entries are not
///    future-dated beyond `localNowMs + maxClockDriftMs` (§6) — the drifted
///    **suffix** of the file is dropped from [AuthorizationOutcome.accepted]
///    and reported as `hlc-drift`.
///
/// When `users.json` is absent or invalid the vault is **public** (§8.2):
/// devices whose key passes TOFU are accepted; a key-substituted device is
/// still rejected and reported. A broken registry never locks out devices.
///
/// Rejections are reported via `package:logging` and aggregated into
/// [EntryRejectionReport]s for the sync status (§9) — never silently dropped.
class OpLogAuthorizer {
  OpLogAuthorizer({required IRegistryService registry, required ITrustStore trustStore, this.nowMs = _realNowMs}) : _registry = registry, _trustStore = trustStore;

  final IRegistryService _registry;
  final ITrustStore _trustStore;

  /// The reader's wall clock in ms since the Unix epoch (sync-security.md §6:
  /// `localTime` is `DateTime.now().millisecondsSinceEpoch` at read time).
  /// Injected so tests can drive it deterministically; defaults to the real
  /// clock. [OpLogSystem] supplies a per-cycle value (captured once at the
  /// start of the cycle) rather than a fresh read per file.
  final int Function() nowMs;

  static int _realNowMs() => DateTime.now().millisecondsSinceEpoch;

  static final Logger _log = Logger('OpLogAuthorizer');

  /// Loads the registry input of the attribution gate exactly once: the
  /// canonical `users.json` and, for every user listed in it, the canonical
  /// `devices/<userId>.json`.
  ///
  /// This is the expensive step (a disk read + JSON parse + whole-file and
  /// per-record signature verification per file, via
  /// [IRegistryService.loadUserRegistry] / [IRegistryService.loadDeviceRegistry]).
  /// The sync pipeline calls it **once per sync cycle**
  /// ([OpLogSystem.prepareVerification]) and passes the result to every
  /// [authorize] call of that cycle — not once per `.oplog.jsonl` file.
  ///
  /// Any load failure degrades to "absent" (public vault semantics, §8.2)
  /// rather than locking out devices; a registry cycle is treated as absent
  /// (§11).
  Future<RegistrySnapshot> loadSnapshot() async {
    UserRegistry? users;
    try {
      users = await _registry.loadUserRegistry();
    } on Exception catch (e) {
      _log.warning('user registry could not be loaded — treating the vault as public (§8.2): $e');
    }
    final deviceFiles = <String, DeviceRegistry>{};
    if (users != null) {
      for (final user in users.users) {
        try {
          final file = await _registry.loadDeviceRegistry(user.userId);
          if (file != null) deviceFiles[user.userId] = file;
        } on Exception catch (e) {
          _log.warning('device registry for user ${user.userId} could not be loaded: $e');
        }
      }
    }
    return RegistrySnapshot(users: users, deviceFiles: deviceFiles);
  }

  /// Runs TOFU, certificate, registry-filter and HLC drift (§7 steps 3–6)
  /// over [entriesByDevice] (one device file's entries per device, as produced
  /// by the read path after §7 steps 1–2) for the page at [relativePath].
  ///
  /// [vaultRootPath] is the active vault root (scoping the TOFU store).
  /// [localDeviceId] is the local device's UUID (the [entriesByDevice] key of
  /// its own file) — the §6 drift check applies to every device file **except**
  /// this one: a device never applies the bound to its own file (§6: "a device
  /// MUST NOT apply it to its own file"). Pass `null` to disable the drift
  /// check entirely (low-level use; the sync pipeline always supplies it).
  /// [localNowMs] is the reader's wall clock in ms since the epoch
  /// (`DateTime.now().millisecondsSinceEpoch` at read time, §6) — pass the
  /// cycle's value captured once at the start of the sync cycle
  /// ([OpLogSystem.prepareVerification]) so the whole cycle shares one
  /// reference point. When `null`, this gate's own [nowMs] is used (read once
  /// for this call).
  /// [maxClockDriftMs] is the tolerated future drift (default
  /// [kDefaultMaxClockDriftMs]; a larger value MAY be configured — NOET-57).
  /// [snapshot] is the cycle's registry input, as produced by
  /// [loadSnapshot] / [OpLogSystem.prepareVerification]; when omitted it is
  /// loaded on demand (low-level use — the sync pipeline always supplies it).
  ///
  /// The §6 drift check runs **per device, after that device passed steps 3–5**
  /// (TOFU → certificate → registry filter): a device already rejected by the
  /// registry filter is never double-counted as `hlc-drift`. For each other
  /// device that passed, the **drifted suffix** of its file — the first entry
  /// with `physicalMs > localNowMs + maxClockDriftMs` and every entry after
  /// it (§6: the violating set is always a suffix) — is dropped from
  /// [AuthorizationOutcome.accepted] and reported **once per device file** as
  /// `hlc-drift` with the rejected entry count and the observed drift in ms.
  /// Rejected entries never reach [AuthorizationOutcome.accepted], so they
  /// cannot contribute to the DAG, merge decisions, or witness state, and they
  /// are never fed to `Hlc.receive` (§6: drift MUST NOT propagate). Nothing on
  /// disk is rewritten or deleted (§8.4: the check is re-evaluated on every
  /// read, so once the reader's clock advances past the bound the entries are
  /// accepted again).
  Future<AuthorizationOutcome> authorize({
    required String vaultRootPath,
    required String relativePath,
    required Map<String, List<OpLogEntry>> entriesByDevice,
    String? localDeviceId,
    int? localNowMs,
    int maxClockDriftMs = kDefaultMaxClockDriftMs,
    RegistrySnapshot? snapshot,
  }) async {
    final accepted = <String, List<OpLogEntry>>{};
    final countsByReason = <String, int>{};
    final devicesByReason = <String, Set<String>>{};
    // hlc-drift is reported once per device file (the observed drift is
    // per-file, §9.4), so its reports are accumulated separately and appended
    // after the per-reason aggregates rather than merged into them.
    final driftReports = <EntryRejectionReport>[];

    final snap = snapshot ?? await loadSnapshot();
    final users = snap.users;
    final deviceFiles = snap.deviceFiles;
    // The §6 drift check is active when a local device is named (so we know
    // which file is exempt). The reference clock is the cycle's value when
    // supplied, else this gate's own [nowMs] — OpLogSystem supplies the
    // cycle's value so the whole cycle shares one reference point.
    final driftEnabled = localDeviceId != null;
    final localNowMsRef = localNowMs ?? nowMs();

    for (final device in entriesByDevice.keys) {
      final entries = entriesByDevice[device]!;
      if (entries.isEmpty) continue;

      final result = await _authorizeDevice(device: device, entries: entries, vaultRootPath: vaultRootPath, users: users, deviceFiles: deviceFiles);

      if (result.authorization is EntryAuthorized) {
        if (!driftEnabled || device == localDeviceId) {
          // No drift check for the local device's own file (§6) or when the
          // check is disabled (no local device named — low-level use) — accept
          // as-is.
          accepted[device] = entries;
          continue;
        }

        // §7 step 6 — HLC drift: the device passed steps 3–5, so it is the
        // only remaining gate. Reject the drifted suffix and report it once
        // for this device file.
        final drift = HlcDriftGate.check(entries, localNowMsRef, maxDriftMs: maxClockDriftMs);
        if (drift.rejectedCount == 0) {
          accepted[device] = drift.accepted;
          continue;
        }
        final firstRejectedHlc = entries[entries.length - drift.rejectedCount].hlcKey;
        if (drift.accepted.isNotEmpty) {
          accepted[device] = drift.accepted;
        }
        driftReports.add(EntryRejectionReport(reason: 'hlc-drift', devices: [device], entryCount: drift.rejectedCount, observedDriftMs: drift.observedDriftMs));
        _logDriftRejection(device: device, entryCount: drift.rejectedCount, observedDriftMs: drift.observedDriftMs, firstRejectedHlc: firstRejectedHlc, relativePath: relativePath);
      } else {
        final reason = _reasonOf(result.authorization);
        countsByReason[reason] = (countsByReason[reason] ?? 0) + entries.length;
        final firstLogged = devicesByReason.putIfAbsent(reason, () => {}).add(device);
        if (firstLogged) {
          _logRejection(
            reason: reason,
            device: device,
            entryCount: entries.length,
            firstHlc: entries.first.hlcKey,
            relativePath: relativePath,
            authorization: result.authorization,
          );
        }
      }
    }

    final rejections = [
      for (final reason in countsByReason.keys) EntryRejectionReport(reason: reason, devices: devicesByReason[reason]!.toList()..sort(), entryCount: countsByReason[reason]!),
      ...driftReports,
    ];
    return AuthorizationOutcome(accepted: accepted, rejections: rejections);
  }

  Future<({EntryAuthorization authorization})> _authorizeDevice({
    required String device,
    required List<OpLogEntry> entries,
    required String vaultRootPath,
    required UserRegistry? users,
    required Map<String, DeviceRegistry> deviceFiles,
  }) async {
    // The key the entry verified under: the file's first-entry `pubKey` (the
    // key [OpLogVerifier] checked the signature against). `null` only when the
    // file is all-legacy (no entry carries a key) — §8.1: accepted during
    // migration.
    final observedKey = _observedKey(entries);
    if (observedKey == null) {
      return (authorization: const EntryAuthorized());
    }

    // §7 step 3 — TOFU. Pin or reject the device key before any registry
    // check, so a new device's key is pinned before its authorization is judged.
    TrustDecision tofu;
    try {
      tofu = await _trustStore.observeKey(vaultRootPath, device, observedKey);
    } on Exception catch (e) {
      // A store failure (e.g. a malformed trusted_keys.json, §8.4) is NOT key
      // substitution: reject the device and report the distinct reason.
      _log.warning('TOFU store could not be read for device $device — entry rejected (trust-store-error): $e');
      return (authorization: const EntryTrustStoreError());
    }
    if (tofu is TrustSubstituted) {
      // §5.2 rule 3 / §3.5: a substituted key is NOT trusted and the file's
      // entries MUST NOT be merged (applies even in a public vault).
      return (authorization: EntryKeySubstituted(storedKey: tofu.storedKey, observedKey: observedKey));
    }

    // §7 step 4 — certificate. Resolve the device to its user by a live
    // certificate whose devicePublicKey matches the observed key (§3.5.1).
    String? boundUser;
    for (final file in deviceFiles.values) {
      final cert = file.devicesById[device];
      if (cert == null || cert.isRemoved) continue;
      if (cert.devicePublicKey != observedKey) continue;
      boundUser = file.userId;
      break;
    }

    // §7 step 5 — registry filter.
    if (boundUser == null) {
      // No live certificate binds this device to an authorized user.
      // Public vault (§8.2): no users.json ⇒ no registry ⇒ any device with a
      // valid (TOFU-cleared) key may contribute.
      return users == null ? (authorization: const EntryAuthorized()) : (authorization: const EntryUnboundDevice());
    }
    final userRecord = users?.usersById[boundUser];
    if (userRecord == null || userRecord.isRemoved) {
      return (authorization: const EntryUnauthorizedUser());
    }
    return (authorization: const EntryAuthorized());
  }

  /// The key the entries verified under: the first non-null `pubKey` in file
  /// order. `null` when the file is all-legacy (no entry carries a key).
  static String? _observedKey(List<OpLogEntry> entries) {
    for (final entry in entries) {
      if (entry.pubKey != null) return entry.pubKey;
    }
    return null;
  }

  static String _reasonOf(EntryAuthorization authorization) {
    if (authorization is EntryKeySubstituted) return 'key-substitution';
    if (authorization is EntryTrustStoreError) return 'trust-store-error';
    if (authorization is EntryUnboundDevice) return 'unbound-device';
    if (authorization is EntryUnauthorizedUser) return 'unauthorized-user';
    return 'authorized';
  }

  void _logRejection({
    required String reason,
    required String device,
    required int entryCount,
    required String firstHlc,
    required String relativePath,
    required EntryAuthorization authorization,
  }) {
    final noun = entryCount == 1 ? 'entry' : 'entries';
    final base = 'Rejected $entryCount $noun for device $device at $relativePath (first entry $firstHlc)';
    final detail = switch (authorization) {
      EntryKeySubstituted(:final storedKey, :final observedKey) =>
        ': key substitution detected (TOFU §5.2) — stored=$storedKey observed=$observedKey. Confirm the new key to adopt it.',
      EntryTrustStoreError() => ': the TOFU trust store could not be read (trust-store-error, §8.4) — the device was not trusted.',
      EntryUnboundDevice() => ': device is not bound to any user by a valid certificate (registry §3.5).',
      EntryUnauthorizedUser() => ': the device\'s user is not authorized in users.json (absent or revoked, registry §3.5).',
      _ => '.',
    };
    _log.warning(base + detail);
  }

  /// Logs a §6 HLC drift rejection for one device file. The rejected entries
  /// stay in the authoring device's own file (§6: non-destructive, self-
  /// healing) — the message makes clear they will be applied once the clocks
  /// converge (§9.4), and names the device, the entry count, and the observed
  /// drift in ms.
  void _logDriftRejection({required String device, required int entryCount, required int observedDriftMs, required String firstRejectedHlc, required String relativePath}) {
    final noun = entryCount == 1 ? 'entry' : 'entries';
    _log.warning(
      'Rejected $entryCount $noun for device $device at $relativePath '
      '(first drifted entry $firstRejectedHlc): hlc-drift (physicalMs ahead of '
      'local clock by $observedDriftMs ms, beyond the $kDefaultMaxClockDriftMs ms '
      'bound, §6). The entries stay in the authoring device\'s file and will be '
      'applied once the reader\'s clock advances past the bound.',
    );
  }
}
