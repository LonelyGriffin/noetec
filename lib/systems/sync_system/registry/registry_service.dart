// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/entity/user/user_identity.dart';
import 'package:noetec/service/crypto_service.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/service/hlc_service.dart';
import 'package:noetec/service/secure_key_store.dart';
import 'package:noetec/systems/vault/vault_system.dart';

import 'registry_models.dart';
import 'registry_reconciler.dart';
import 'registry_signing.dart';

/// The outcome of reconciling one registry area (users, or one user's devices).
///
/// Every rejection and every dropped candidate is reported here (spec §3.7
/// "MUST report the dropped side rather than silently discarding it", §9).
final class RegistryReconcileReport {
  const RegistryReconcileReport({
    required this.mode,
    required this.merged,
    required this.newRevision,
    this.rejectedFiles = const [],
    this.droppedFiles = const [],
    this.removedFiles = const [],
    this.decisions = const [],
    this.note,
  });

  /// How the reconcile resolved:
  /// - `'noop'` — no valid candidate found;
  /// - `'fast-path'` — exactly one valid candidate; adopted;
  /// - `'three-way'` — per-record LWW merge from a common ancestor / cache;
  /// - `'lww-fallback'` — no common ancestor; file-level LWW (larger revision).
  final String mode;

  /// Whether the canonical file was (re)written.
  final bool merged;

  /// The new canonical file's `revision` HLC key, when [merged].
  final String? newRevision;

  /// Candidate files rejected (parse/structural error or failed signature) —
  /// treated as absent (§8.2).
  final List<String> rejectedFiles;

  /// Candidate files dropped by the file-level LWW fallback (reported, §3.7).
  final List<String> droppedFiles;

  /// Conflicted copies deleted after a successful commit.
  final List<String> removedFiles;

  /// The per-record decisions that explain each cross-side conflict.
  final List<RecordMergeDecision> decisions;

  /// A human-readable outcome note.
  final String? note;
}

/// Supplies the local [UserIdentity] (and, for verification, the last verified
/// `users.json` used to resolve other users' keys). In production this reads
/// `.noetec/identity.json` and the known-good cache; tests may override it.
abstract interface class IIdentitySource {
  Future<({UserIdentity identity, UserRegistry? lastVerified})> resolve(String vaultRootPath);
}

/// Resolves the identity public keys used to verify the registry files
/// (sync-security.md §3.4 "Key resolution").
///
/// Resolution order for a [userId]:
/// 1. the local identity (the operator), when it is that user;
/// 2. the user's record in [fromFile] — the file being verified (its
///    whole-file signature, under the authority key, vouches for the keys it
///    lists, so this is sound);
/// 3. the last verified `users.json` (the known-good cache);
/// 4. an explicit [pinned] override (NOET-30 TOFU will supply this).
final class LocalRegistryKeyProvider implements IRegistryKeyProvider {
  LocalRegistryKeyProvider({required UserIdentity? localIdentity, required UserRegistry? lastVerifiedUserRegistry, UserRegistry? fromFile, Map<String, String> pinned = const {}})
    : _local = localIdentity,
      _lastVerified = lastVerifiedUserRegistry,
      _fromFile = fromFile,
      _pinned = pinned;

  final UserIdentity? _local;
  final UserRegistry? _lastVerified;
  final UserRegistry? _fromFile;
  final Map<String, String> _pinned;

  @override
  Future<String?> identityKeyFor(String userId) async {
    final local = _local;
    if (local != null && local.userId == userId) return local.publicKey;
    final file = _fromFile;
    if (file != null) {
      for (final user in file.users) {
        if (user.userId == userId) return user.publicKey;
      }
    }
    final registry = _lastVerified;
    if (registry != null) {
      for (final user in registry.users) {
        if (user.userId == userId) return user.publicKey;
      }
    }
    return _pinned[userId];
  }
}

/// A single registry file's last-known-good state (spec §3.7 "last known-good
/// `revision` cache").
///
/// The cache lives in `.noetec/` (outside the synced `.sync/` area, §5.3) and
/// stores the full *signed* wire map. Cached data is untrusted input: it is
/// re-verified before being used as a merge base.
final class KnownGoodEntry {
  const KnownGoodEntry({required this.wire, required this.revision});

  /// The full wire map (top-level `signature` included).
  final Map<String, dynamic> wire;

  /// The cached file's `revision` HLC key.
  final String revision;

  Map<String, dynamic> toJson() => {'revision': revision, 'wire': wire};

  factory KnownGoodEntry.fromJson(Map<String, dynamic> json) {
    final wire = json['wire'];
    if (wire is! Map) {
      throw const FormatException('known-good entry is missing its "wire" map');
    }
    return KnownGoodEntry(revision: json['revision'] as String, wire: Map<String, dynamic>.from(wire));
  }
}

/// The last-known-good cache for both registry areas.
final class RegistryKnownGoodCache {
  RegistryKnownGoodCache(this._fileSystem, this._log) : _entries = {};

  final IFileSystemService _fileSystem;
  final Logger _log;
  final Map<String, KnownGoodEntry> _entries;

  static const _fileName = 'registry_known_good.json';

  static String path(String vaultRootPath) => '$vaultRootPath/.noetec/$_fileName';

  Future<void> load(String vaultRootPath) async {
    _entries.clear();
    final path = RegistryKnownGoodCache.path(vaultRootPath);
    if (!await _fileSystem.fileExists(path)) return;
    try {
      final content = await _fileSystem.readFile(path);
      final data = jsonDecode(content) as Map<String, dynamic>;
      final files = data['files'];
      if (files is! Map) return;
      for (final entry in files.entries) {
        try {
          _entries[entry.key] = KnownGoodEntry.fromJson((entry.value as Map).cast<String, dynamic>());
        } on FormatException catch (e) {
          _log.warning('Known-good entry for ${entry.key} is corrupt, ignoring: $e');
        }
      }
    } on FormatException catch (e) {
      _log.warning('Known-good cache is corrupt, starting empty: $e');
    }
  }

  Future<void> save(String vaultRootPath) async {
    final data = {
      'files': {for (final e in _entries.entries) e.key: e.value.toJson()},
    };
    await _fileSystem.writeFile(RegistryKnownGoodCache.path(vaultRootPath), jsonEncode(data));
  }

  void put(String name, Map<String, dynamic> wire, String revision) => _entries[name] = KnownGoodEntry(wire: wire, revision: revision);

  KnownGoodEntry? get(String name) => _entries[name];

  void clear() => _entries.clear();
}

/// The user & device registry service (sync-security.md §3, ADR-0007).
///
/// Responsibilities:
/// - Discover registry candidate files in `.sync/` (the canonical file plus
///   conflicted copies produced by the sync backend).
/// - Verify whole-file and per-record signatures; reject and report invalid
///   candidates (§3.4, §8.2).
/// - Reconcile candidates: 3-way per-record LWW merge from a common ancestor
///   (`parent`) or the last-known-good cache, with the file-level LWW
///   fallback when no common ancestor exists (§3.7).
/// - Write the merged file atomically, remove the conflicted copies, and
///   refresh the known-good cache.
/// - Expose the registry operations: addUser, revokeUser, addDevice,
///   revokeDevice (§3.6).
abstract interface class IRegistryService {
  /// Reconciles the `users.json` candidates into a single canonical file.
  Future<RegistryReconcileReport> reconcileUserRegistry();

  /// Reconciles one user's `devices/<userId>.json` candidates.
  Future<RegistryReconcileReport> reconcileDeviceRegistry(String userId);

  /// The current (canonical) user registry, or `null` when absent/unreadable.
  Future<UserRegistry?> loadUserRegistry();

  /// The current (canonical) device registry for [userId], or `null`.
  Future<DeviceRegistry?> loadDeviceRegistry(String userId);

  /// Adds [name] to `users.json` (bootstrap owner record, or a new member, or
  /// a re-add after revoke) and re-signs the file (§3.6).
  Future<UserRegistry> addUser({required String userId, required String name, required String publicKey, String role = 'member'});

  /// Tombstones [userId] in `users.json` and re-signs the file (§3.6).
  Future<UserRegistry> revokeUser(String userId);

  /// Adds a device certificate to the operator's `devices/<userId>.json` and
  /// re-signs the file (§3.6).
  Future<DeviceRegistry> addDevice({required String deviceUuid, required String devicePublicKey, required String deviceName});

  /// Revokes [deviceUuid] in the operator's `devices/<userId>.json` and
  /// re-signs the file (§3.6).
  Future<DeviceRegistry> revokeDevice(String deviceUuid);
}

class RegistryServiceImpl implements IRegistryService {
  RegistryServiceImpl({
    required IFileSystemService fileSystem,
    required HlcService hlcService,
    required ICryptoService crypto,
    required ISecureKeyStore secureKeyStore,
    required VaultSystem vaultSystem,
    IIdentitySource? identitySource,
    Logger? log,
  }) : _fileSystem = fileSystem,
       _hlcService = hlcService,
       _secureKeyStore = secureKeyStore,
       _vaultSystem = vaultSystem,
       _identitySource = identitySource,
       _log = log ?? Logger('RegistryService'),
       _reconciler = RegistryReconciler(),
       _signing = RegistrySigning(crypto) {
    _cache = RegistryKnownGoodCache(_fileSystem, _log);
    _vaultSystem.currentVault.addListener(_onVaultChanged);
  }

  final IFileSystemService _fileSystem;
  final HlcService _hlcService;
  final ISecureKeyStore _secureKeyStore;
  final VaultSystem _vaultSystem;
  final IIdentitySource? _identitySource;
  final Logger _log;
  final RegistryReconciler _reconciler;
  final RegistrySigning _signing;
  late final RegistryKnownGoodCache _cache;

  String? _vaultRootPath;
  String? _vaultId;
  UserIdentity? _identity;
  UserRegistry? _lastVerifiedUserRegistry;
  bool _cacheLoaded = false;

  bool get _isActive => _vaultRootPath != null;

  void _requireActive() {
    if (!_isActive) {
      throw StateError('RegistryService is not active (no vault open)');
    }
  }

  void _onVaultChanged() {
    final vault = _vaultSystem.currentVault.value;
    if (vault == null) {
      _vaultRootPath = null;
      _vaultId = null;
      _identity = null;
      _lastVerifiedUserRegistry = null;
      _cacheLoaded = false;
      _cache.clear();
      return;
    }
    _vaultRootPath = vault.rootPath;
    _vaultId = vault.id;
    _identity = null;
    _lastVerifiedUserRegistry = null;
    _cacheLoaded = false;
  }

  Future<void> _ensureCacheLoaded() async {
    if (_cacheLoaded) return;
    await _cache.load(_vaultRootPath!);
    _cacheLoaded = true;
  }

  // --- Paths ---------------------------------------------------------------

  String _syncDir(String root) => '$root/.sync';

  String _devicesDir(String root) => '$root/.sync/devices';

  String _usersCanonicalPath(String root) => '${_syncDir(root)}/users.json';

  String _deviceCanonicalPath(String root, String userId) => '${_devicesDir(root)}/$userId.json';

  bool _isUsersFile(String name) => name == 'users.json' || (name.startsWith('users (') && name.endsWith('.json'));

  String? _userIdFromDeviceFileName(String name) {
    if (!name.endsWith('.json')) return null;
    var stem = name.substring(0, name.length - 5); // strip ".json"
    final spaceIdx = stem.indexOf(' ');
    if (spaceIdx != -1) stem = stem.substring(0, spaceIdx);
    return stem.isEmpty ? null : stem;
  }

  String _nameOf(String path) => path.split('/').last;

  // --- Identity / key resolution ------------------------------------------

  Future<({UserIdentity? identity, UserRegistry? lastVerified})> _resolveIdentity() async {
    final root = _vaultRootPath!;
    final source = _identitySource;
    if (source != null) {
      try {
        final r = await source.resolve(root);
        return (identity: r.identity, lastVerified: r.lastVerified);
      } on Exception catch (e) {
        _log.warning('identity source failed: $e');
        return (identity: null, lastVerified: null);
      }
    }
    // Default source: read identity.json and the known-good users registry.
    UserIdentity? identity;
    final identityPath = '$root/.noetec/identity.json';
    if (await _fileSystem.fileExists(identityPath)) {
      try {
        identity = UserIdentity.fromJson((jsonDecode(await _fileSystem.readFile(identityPath)) as Map).cast<String, dynamic>());
      } on Exception catch (e) {
        _log.warning('identity.json unreadable: $e');
      }
    }
    UserRegistry? lastVerified;
    await _ensureCacheLoaded();
    final entry = _cache.get('users.json');
    if (entry != null) {
      try {
        lastVerified = UserRegistry.fromWireMap(entry.wire);
      } on Exception catch (e) {
        _log.warning('known-good users.json unreadable: $e');
      }
    }
    return (identity: identity, lastVerified: lastVerified);
  }

  Future<void> _refreshIdentity() async {
    final resolved = await _resolveIdentity();
    _identity = resolved.identity;
    _lastVerifiedUserRegistry = resolved.lastVerified;
  }

  IRegistryKeyProvider _keyProvider({UserIdentity? identity, UserRegistry? lastVerified, UserRegistry? fromFile}) =>
      LocalRegistryKeyProvider(localIdentity: identity, lastVerifiedUserRegistry: lastVerified, fromFile: fromFile);

  /// The base64url identity **private** key for [userId], resolvable only when
  /// the local identity is that user (a user signs only their own authority
  /// scope: the owner signs `users.json`, a user signs their device file).
  Future<String> _authorityIdentityPrivateKey(String userId) async {
    final identity = _identity;
    if (identity == null || identity.userId != userId) {
      throw StateError('local identity is not the authority ($userId) for this registry file');
    }
    final vaultId = _vaultId;
    if (vaultId == null) {
      throw StateError('no vault id for the active vault');
    }
    final key = await _secureKeyStore.readIdentityPrivateKey(vaultId);
    if (key == null) {
      throw StateError('no identity private key in secure storage for user $userId');
    }
    return key;
  }

  // --- Reconcile -----------------------------------------------------------

  @override
  Future<RegistryReconcileReport> reconcileUserRegistry() async {
    _requireActive();
    final root = _vaultRootPath!;
    await _ensureCacheLoaded();
    await _refreshIdentity();

    final candidates = await _discoverUserFiles(root);
    final verified = await _verifyUserCandidates(candidates);
    final plan = _reconcileUsers(root, verified.valid, verified.rejected);
    final report = await _commitUsers(root, plan);
    await _refreshUserCache(root);
    await _cache.save(root);
    _logReport('users.json', report);
    return report;
  }

  @override
  Future<RegistryReconcileReport> reconcileDeviceRegistry(String userId) async {
    _requireActive();
    final root = _vaultRootPath!;
    await _ensureCacheLoaded();
    await _refreshIdentity();

    final candidates = await _discoverDeviceFiles(root, userId);
    final verified = await _verifyDeviceCandidates(candidates, userId);
    final plan = _reconcileDevices(root, userId, verified.valid, verified.rejected);
    final report = await _commitDevices(root, userId, plan);
    await _refreshDeviceCache(root, userId);
    await _cache.save(root);
    _logReport('devices/$userId.json', report);
    return report;
  }

  // --- Discovery -----------------------------------------------------------

  Future<List<String>> _discoverUserFiles(String root) async {
    final syncDir = _syncDir(root);
    if (!await _fileSystem.directoryExists(syncDir)) return const [];
    final entries = await _fileSystem.listDirectory(syncDir);
    return [
      for (final e in entries)
        if (!e.isDirectory && _isUsersFile(e.name)) e.path,
    ];
  }

  Future<List<String>> _discoverDeviceFiles(String root, String userId) async {
    final devicesDir = _devicesDir(root);
    if (!await _fileSystem.directoryExists(devicesDir)) return const [];
    final entries = await _fileSystem.listDirectory(devicesDir);
    final files = <String>[];
    for (final e in entries) {
      if (e.isDirectory) continue;
      final owner = _userIdFromDeviceFileName(e.name);
      if (owner != userId) continue;
      files.add(e.path);
    }
    return files;
  }

  // --- Verification --------------------------------------------------------

  Future<({List<(String, UserRegistry)> valid, List<String> rejected})> _verifyUserCandidates(List<String> paths) async {
    final valid = <(String, UserRegistry)>[];
    final rejected = <String>[];
    for (final path in paths) {
      final r = await _loadUserCandidate(path);
      if (r.registry == null) {
        rejected.add(path);
        _log.warning('rejected ${_nameOf(path)}: ${r.reason}');
      } else {
        valid.add((path, r.registry!));
      }
    }
    return (valid: valid, rejected: rejected);
  }

  Future<({List<(String, DeviceRegistry)> valid, List<String> rejected})> _verifyDeviceCandidates(List<String> paths, String userId) async {
    final valid = <(String, DeviceRegistry)>[];
    final rejected = <String>[];
    for (final path in paths) {
      final r = await _loadDeviceCandidate(path, userId);
      if (r.registry == null) {
        rejected.add(path);
        _log.warning('rejected ${_nameOf(path)}: ${r.reason}');
      } else {
        valid.add((path, r.registry!));
      }
    }
    return (valid: valid, rejected: rejected);
  }

  /// Parses, structurally validates, and fully verifies (whole-file and
  /// per-record signatures) one users.json candidate.
  ///
  /// Key resolution (§3.4): the owner's key resolves from the local identity
  /// (when the operator is the owner), the last verified users.json (cache),
  /// or the file's own owner record; other users' keys resolve from the
  /// file's records (the whole-file signature under the owner key already
  /// vouches for every key the file lists).
  Future<({UserRegistry? registry, String? reason})> _loadUserCandidate(String path) async {
    UserRegistry reg;
    try {
      final content = await _fileSystem.readFile(path);
      final map = (jsonDecode(content) as Map).cast<String, dynamic>();
      reg = UserRegistry.fromWireMap(map);
      reg.validate();
    } on FormatException catch (e) {
      return (registry: null, reason: 'parse: $e');
    }
    final kp = _keyProvider(identity: _identity, lastVerified: _lastVerifiedUserRegistry, fromFile: reg);
    final result = await _signing.verifyUserRegistry(reg, kp);
    if (!result.valid) {
      return (registry: null, reason: 'signature: ${result.issues.map((i) => i.toString()).join('; ')}');
    }
    return (registry: reg, reason: null);
  }

  Future<({DeviceRegistry? registry, String? reason})> _loadDeviceCandidate(String path, String userId) async {
    DeviceRegistry reg;
    try {
      final content = await _fileSystem.readFile(path);
      final map = (jsonDecode(content) as Map).cast<String, dynamic>();
      reg = DeviceRegistry.fromWireMap(map);
      reg.validate();
    } on FormatException catch (e) {
      return (registry: null, reason: 'parse: $e');
    }
    if (reg.userId != userId) {
      return (registry: null, reason: 'file name user $userId != content userId ${reg.userId}');
    }
    final kp = _keyProvider(identity: _identity, lastVerified: _lastVerifiedUserRegistry);
    final result = await _signing.verifyDeviceRegistry(reg, kp);
    if (!result.valid) {
      return (registry: null, reason: 'signature: ${result.issues.map((i) => i.toString()).join('; ')}');
    }
    return (registry: reg, reason: null);
  }

  // --- Reconcile: users ----------------------------------------------------

  _UsersPlan _reconcileUsers(String root, List<(String, UserRegistry)> valid, List<String> rejected) {
    final canonical = _usersCanonicalPath(root);
    if (valid.isEmpty) {
      return _UsersPlan(mode: 'noop', rejectedFiles: rejected, note: 'no valid users.json candidate');
    }
    if (valid.length == 1) {
      final (path, reg) = valid.single;
      return _UsersPlan(
        mode: 'adopt',
        reportMode: 'fast-path',
        registry: reg,
        sourcePath: path,
        toDelete: [
          for (final v in valid)
            if (v.$1 != canonical) v.$1,
        ],
        rejectedFiles: rejected,
      );
    }
    final owners = valid.map((v) => v.$2.ownerUserId).toSet();
    if (owners.length > 1) {
      // No common owner ⇒ no common ancestor ⇒ file-level LWW fallback.
      final sorted = [...valid]..sort((a, b) => a.$2.revision.compareTo(b.$2.revision));
      final winner = sorted.last;
      final losers = sorted.sublist(0, sorted.length - 1);
      final toDelete = [
        for (final l in losers)
          if (l.$1 != canonical) l.$1,
      ];
      return _UsersPlan(
        mode: 'adopt',
        reportMode: 'lww-fallback',
        registry: winner.$2,
        sourcePath: winner.$1,
        toDelete: toDelete,
        rejectedFiles: rejected,
        droppedFiles: [for (final l in losers) l.$1],
        note: 'file-level LWW: kept ${_nameOf(winner.$1)}, dropped ${[for (final l in losers) _nameOf(l.$1)].join(', ')}',
      );
    }
    return _perRecordMergeUsers(root, valid, rejected);
  }

  _UsersPlan _perRecordMergeUsers(String root, List<(String, UserRegistry)> valid, List<String> rejected) {
    final canonical = _usersCanonicalPath(root);
    final baseEntry = _cache.get('users.json');
    List<UserRecord> baseRecords;
    Hlc baseRevision;
    if (baseEntry != null) {
      final baseFile = UserRegistry.fromWireMap(baseEntry.wire);
      baseRecords = baseFile.users;
      baseRevision = baseFile.revision;
    } else {
      final sorted = [...valid]..sort((a, b) => a.$2.revision.compareTo(b.$2.revision));
      final smallest = sorted.first;
      baseRecords = smallest.$2.users;
      baseRevision = smallest.$2.revision;
    }
    final sides = <RegistryMergeSide<UserRecord>>[
      RegistryMergeSide(label: RegistryReconciler.baseLabel, records: baseRecords),
      for (final (path, reg) in valid) RegistryMergeSide(label: _nameOf(path), records: reg.users),
    ];
    final merge = _reconciler.merge(sides: sides);

    // The merge result keeps the authors' per-record signatures; only the
    // whole-file signature is re-stamped under the owner's key (§3.2). The
    // owner_user_id and version are carried from the winning (latest) file.
    final sorted = [...valid]..sort((a, b) => a.$2.revision.compareTo(b.$2.revision));
    final winner = sorted.last.$2;
    final unsigned = UserRegistry(version: winner.version, revision: baseRevision, parent: baseRevision, ownerUserId: winner.ownerUserId, users: merge.merged, signature: '');
    final toDelete = [
      for (final (path, _) in valid)
        if (path != canonical) path,
    ];
    final maxInput = _maxRevision(valid.map((v) => v.$2.revision));
    return _UsersPlan(mode: 'merge', registry: unsigned, decisions: merge.decisions, toDelete: toDelete, rejectedFiles: rejected, newParent: baseRevision, maxInput: maxInput);
  }

  // --- Reconcile: devices --------------------------------------------------

  _DevicesPlan _reconcileDevices(String root, String userId, List<(String, DeviceRegistry)> valid, List<String> rejected) {
    final canonical = _deviceCanonicalPath(root, userId);
    if (valid.isEmpty) {
      return _DevicesPlan(mode: 'noop', rejectedFiles: rejected, note: 'no valid devices/$userId.json candidate');
    }
    if (valid.length == 1) {
      final (path, reg) = valid.single;
      return _DevicesPlan(
        mode: 'adopt',
        reportMode: 'fast-path',
        registry: reg,
        sourcePath: path,
        toDelete: [
          for (final v in valid)
            if (v.$1 != canonical) v.$1,
        ],
        rejectedFiles: rejected,
      );
    }
    // (Different users' device files never collide — unique file names, §3.3
    // — so every multi-candidate case here is same-user and mergeable.)
    final baseEntry = _cache.get('devices/$userId.json');
    List<DeviceRecord> baseRecords;
    Hlc baseRevision;
    if (baseEntry != null) {
      final baseFile = DeviceRegistry.fromWireMap(baseEntry.wire);
      baseRecords = baseFile.devices;
      baseRevision = baseFile.revision;
    } else {
      final sorted = [...valid]..sort((a, b) => a.$2.revision.compareTo(b.$2.revision));
      final smallest = sorted.first;
      baseRecords = smallest.$2.devices;
      baseRevision = smallest.$2.revision;
    }
    final sides = <RegistryMergeSide<DeviceRecord>>[
      RegistryMergeSide(label: RegistryReconciler.baseLabel, records: baseRecords),
      for (final (path, reg) in valid) RegistryMergeSide(label: _nameOf(path), records: reg.devices),
    ];
    final merge = _reconciler.merge(sides: sides);

    final sorted = [...valid]..sort((a, b) => a.$2.revision.compareTo(b.$2.revision));
    final winner = sorted.last.$2;
    final unsigned = DeviceRegistry(version: winner.version, revision: baseRevision, parent: baseRevision, userId: winner.userId, devices: merge.merged, signature: '');
    final toDelete = [
      for (final (path, _) in valid)
        if (path != canonical) path,
    ];
    final maxInput = _maxRevision(valid.map((v) => v.$2.revision));
    return _DevicesPlan(mode: 'merge', registry: unsigned, decisions: merge.decisions, toDelete: toDelete, rejectedFiles: rejected, newParent: baseRevision, maxInput: maxInput);
  }

  // --- Commit --------------------------------------------------------------

  Future<RegistryReconcileReport> _commitUsers(String root, _UsersPlan plan) async {
    final canonical = _usersCanonicalPath(root);
    switch (plan.mode) {
      case 'noop':
        return RegistryReconcileReport(mode: 'noop', merged: false, newRevision: null, rejectedFiles: plan.rejectedFiles, note: plan.note);
      case 'adopt':
        return _commitAdoptedUsers(root, canonical, plan);
      case 'merge':
        return _commitMergedUsers(canonical, plan);
      default:
        throw StateError('unknown users plan mode: ${plan.mode}');
    }
  }

  Future<RegistryReconcileReport> _commitDevices(String root, String userId, _DevicesPlan plan) async {
    final canonical = _deviceCanonicalPath(root, userId);
    switch (plan.mode) {
      case 'noop':
        return RegistryReconcileReport(mode: 'noop', merged: false, newRevision: null, rejectedFiles: plan.rejectedFiles, note: plan.note);
      case 'adopt':
        return _commitAdoptedDevices(userId, canonical, plan);
      case 'merge':
        return _commitMergedDevices(canonical, plan);
      default:
        throw StateError('unknown devices plan mode: ${plan.mode}');
    }
  }

  /// Moves a verified file (single candidate or LWW-fallback winner) to the
  /// canonical name. A rename is atomic and preserves the file's own
  /// signatures — no re-signing required.
  Future<RegistryReconcileReport> _commitAdoptedUsers(String root, String canonical, _UsersPlan plan) async {
    final reg = plan.registry!;
    final src = plan.sourcePath!;
    final reportMode = plan.reportMode ?? 'fast-path';
    if (src != canonical) {
      await _fileSystem.renameFileOrDirectory(src, canonical);
    }
    final removed = await _deleteAll(plan.toDelete);
    return RegistryReconcileReport(
      mode: reportMode,
      merged: src != canonical,
      newRevision: reg.revision.toKey(),
      rejectedFiles: plan.rejectedFiles,
      droppedFiles: plan.droppedFiles,
      removedFiles: removed,
      note: plan.note,
    );
  }

  Future<RegistryReconcileReport> _commitAdoptedDevices(String userId, String canonical, _DevicesPlan plan) async {
    final reg = plan.registry!;
    final src = plan.sourcePath!;
    if (src != canonical) {
      await _fileSystem.renameFileOrDirectory(src, canonical);
    }
    final removed = await _deleteAll(plan.toDelete);
    return RegistryReconcileReport(
      mode: 'fast-path',
      merged: src != canonical,
      newRevision: reg.revision.toKey(),
      rejectedFiles: plan.rejectedFiles,
      removedFiles: removed,
      note: plan.note,
    );
  }

  /// Writes a freshly merged (newly signed) version of `users.json`.
  ///
  /// The merged records keep the authors' per-record signatures; only the
  /// whole-file signature is re-stamped under the owner's key (§3.2). If the
  /// local user is not the owner, the merge cannot be committed and is
  /// reported (no data is lost; the candidates are left in place).
  Future<RegistryReconcileReport> _commitMergedUsers(String canonical, _UsersPlan plan) async {
    final reg = plan.registry!;
    if (!_isAuthority(reg.ownerUserId)) {
      return RegistryReconcileReport(
        mode: 'three-way',
        merged: false,
        newRevision: null,
        rejectedFiles: plan.rejectedFiles,
        decisions: plan.decisions,
        note: 'cannot re-sign merged users.json: local user is not the owner (${reg.ownerUserId})',
      );
    }
    final newRevision = _hlcService.receive(plan.maxInput!);
    final toWrite = UserRegistry(version: reg.version, revision: newRevision, parent: plan.newParent, ownerUserId: reg.ownerUserId, users: reg.users, signature: '');
    final ownerKey = await _authorityIdentityPrivateKey(reg.ownerUserId);
    final signed = await _signing.signUserFileOnly(toWrite, ownerPrivateKey: ownerKey);
    await _atomicWrite(canonical, jsonEncode(signed.toWireMap()));
    final removed = await _deleteAll(plan.toDelete);
    return RegistryReconcileReport(
      mode: 'three-way',
      merged: true,
      newRevision: signed.revision.toKey(),
      rejectedFiles: plan.rejectedFiles,
      removedFiles: removed,
      decisions: plan.decisions,
    );
  }

  /// Writes a freshly merged (newly signed) version of `devices/<userId>.json`.
  ///
  /// The merged records keep the owner's per-record signatures; only the
  /// whole-file signature is re-stamped under the owning user's key (§3.3).
  /// If the local user is not the owning user, the merge cannot be committed
  /// and is reported (no data is lost; the candidates are left in place).
  Future<RegistryReconcileReport> _commitMergedDevices(String canonical, _DevicesPlan plan) async {
    final reg = plan.registry!;
    if (!_isAuthority(reg.userId)) {
      return RegistryReconcileReport(
        mode: 'three-way',
        merged: false,
        newRevision: null,
        rejectedFiles: plan.rejectedFiles,
        decisions: plan.decisions,
        note: 'cannot re-sign merged device registry: local user is not the owner (${reg.userId})',
      );
    }
    final newRevision = _hlcService.receive(plan.maxInput!);
    final toWrite = DeviceRegistry(version: reg.version, revision: newRevision, parent: plan.newParent, userId: reg.userId, devices: reg.devices, signature: '');
    final userKey = await _authorityIdentityPrivateKey(reg.userId);
    final signed = await _signing.signDeviceFileOnly(toWrite, userPrivateKey: userKey);
    await _atomicWrite(canonical, jsonEncode(signed.toWireMap()));
    final removed = await _deleteAll(plan.toDelete);
    return RegistryReconcileReport(
      mode: 'three-way',
      merged: true,
      newRevision: signed.revision.toKey(),
      rejectedFiles: plan.rejectedFiles,
      removedFiles: removed,
      decisions: plan.decisions,
    );
  }

  /// Whether the local identity is the signing authority for [userId].
  bool _isAuthority(String userId) => _identity?.userId == userId;

  /// Atomic replace: write to a sibling `.tmp` file, then rename over the
  /// target (the standard atomic file-replacement idiom; each registry update
  /// is "an atomic file replacement" — §3.6).
  Future<void> _atomicWrite(String target, String content) async {
    final tmp = '$target.tmp';
    await _fileSystem.writeFile(tmp, content);
    await _fileSystem.renameFileOrDirectory(tmp, target);
  }

  Future<List<String>> _deleteAll(List<String> paths) async {
    final removed = <String>[];
    for (final path in paths) {
      if (await _fileSystem.fileExists(path)) {
        await _fileSystem.deleteFile(path);
        removed.add(path);
      }
    }
    return removed;
  }

  Future<void> _refreshUserCache(String root) async {
    final reg = await _readUserRegistryOrNull(root);
    if (reg != null) {
      _cache.put('users.json', reg.toWireMap(), reg.revision.toKey());
      _lastVerifiedUserRegistry = reg;
    }
  }

  Future<void> _refreshDeviceCache(String root, String userId) async {
    final reg = await _readDeviceRegistryOrNull(root, userId);
    if (reg != null) {
      _cache.put('devices/$userId.json', reg.toWireMap(), reg.revision.toKey());
    }
  }

  // --- Load ----------------------------------------------------------------

  @override
  Future<UserRegistry?> loadUserRegistry() async {
    _requireActive();
    final root = _vaultRootPath!;
    await _ensureCacheLoaded();
    await _refreshIdentity();
    final path = _usersCanonicalPath(root);
    if (!await _fileSystem.fileExists(path)) return null;
    final r = await _loadUserCandidate(path);
    if (r.registry == null) {
      _log.warning('canonical users.json is invalid: ${r.reason}');
      return null;
    }
    return r.registry;
  }

  @override
  Future<DeviceRegistry?> loadDeviceRegistry(String userId) async {
    _requireActive();
    final root = _vaultRootPath!;
    await _ensureCacheLoaded();
    await _refreshIdentity();
    final r = await _loadDeviceCandidate(_deviceCanonicalPath(root, userId), userId);
    if (r.registry == null) {
      _log.warning('canonical devices/$userId.json is invalid: ${r.reason}');
      return null;
    }
    return r.registry;
  }

  // --- Operations (§3.6) ---------------------------------------------------

  @override
  Future<UserRegistry> addUser({required String userId, required String name, required String publicKey, String role = 'member'}) async {
    _requireActive();
    final root = _vaultRootPath!;
    await _ensureCacheLoaded();
    await _refreshIdentity();
    final operatorId = _identity?.userId;
    if (operatorId == null) throw StateError('no local identity; cannot sign users.json');

    final canonical = _usersCanonicalPath(root);
    UserRegistry? current;
    if (await _fileSystem.fileExists(canonical)) {
      current = await loadUserRegistry();
    }
    current ??= UserRegistry(version: 1, revision: _zeroHlc, parent: null, ownerUserId: operatorId, users: const [], signature: '');
    if (operatorId != current.ownerUserId) {
      throw StateError('only the owner (${current.ownerUserId}) administers users.json; local user is $operatorId');
    }

    final now = _hlcService.now();
    final existing = current.usersById[userId];
    // v1: the owner signs every users.json record (addedBy = owner, §3.2/§3.6).
    final unsignedRecord = UserRecord(userId: userId, name: name, publicKey: publicKey, role: role, addedBy: operatorId, updatedAt: now, removedAt: null, signature: '');
    final signedRecord = await _signing.signUserRecord(unsignedRecord, await _authorityIdentityPrivateKey(operatorId));
    final users = [
      for (final u in current.users)
        if (u.userId == userId) signedRecord else u,
      if (existing == null) signedRecord,
    ];
    final newRevision = _hlcService.receive(current.revision);
    final unsignedFile = UserRegistry(version: 1, revision: newRevision, parent: current.revision, ownerUserId: current.ownerUserId, users: users, signature: '');
    final signedFile = await _signing.signUserFileOnly(unsignedFile, ownerPrivateKey: await _authorityIdentityPrivateKey(operatorId));
    await _atomicWrite(canonical, jsonEncode(signedFile.toWireMap()));
    await _refreshUserCache(root);
    return signedFile;
  }

  @override
  Future<UserRegistry> revokeUser(String userId) async {
    _requireActive();
    final root = _vaultRootPath!;
    await _ensureCacheLoaded();
    await _refreshIdentity();
    final operatorId = _identity?.userId;
    if (operatorId == null) throw StateError('no local identity; cannot sign users.json');

    final canonical = _usersCanonicalPath(root);
    final current = await loadUserRegistry();
    if (current == null) throw StateError('users.json absent; nothing to revoke');
    if (operatorId != current.ownerUserId) {
      throw StateError('only the owner (${current.ownerUserId}) administers users.json; local user is $operatorId');
    }
    final target = current.usersById[userId];
    if (target == null) throw ArgumentError.value(userId, 'userId', 'not present in users.json');
    if (userId == current.ownerUserId) throw ArgumentError.value(userId, 'userId', 'cannot revoke the owner');

    final now = _hlcService.now();
    // The owner re-issues the record with removedAt set (tombstone, §3.6).
    final tombstone = UserRecord(
      userId: target.userId,
      name: target.name,
      publicKey: target.publicKey,
      role: target.role,
      addedBy: operatorId,
      updatedAt: now,
      removedAt: now,
      signature: '',
    );
    final signedTomb = await _signing.signUserRecord(tombstone, await _authorityIdentityPrivateKey(operatorId));
    final users = [
      for (final u in current.users)
        if (u.userId == userId) signedTomb else u,
    ];
    final newRevision = _hlcService.receive(current.revision);
    final unsignedFile = UserRegistry(version: 1, revision: newRevision, parent: current.revision, ownerUserId: current.ownerUserId, users: users, signature: '');
    final signedFile = await _signing.signUserFileOnly(unsignedFile, ownerPrivateKey: await _authorityIdentityPrivateKey(operatorId));
    await _atomicWrite(canonical, jsonEncode(signedFile.toWireMap()));
    await _refreshUserCache(root);
    return signedFile;
  }

  @override
  Future<DeviceRegistry> addDevice({required String deviceUuid, required String devicePublicKey, required String deviceName}) async {
    _requireActive();
    final root = _vaultRootPath!;
    await _ensureCacheLoaded();
    await _refreshIdentity();
    final operatorId = _identity?.userId;
    if (operatorId == null) throw StateError('no local identity; cannot sign the device registry');
    // Only the owning user manages their own device file (§3.3).

    final canonical = _deviceCanonicalPath(root, operatorId);
    DeviceRegistry? current;
    if (await _fileSystem.fileExists(canonical)) {
      current = await loadDeviceRegistry(operatorId);
    }
    current ??= DeviceRegistry(version: 1, revision: _zeroHlc, parent: null, userId: operatorId, devices: const [], signature: '');
    final now = _hlcService.now();
    final existing = current.devicesById[deviceUuid];
    final unsigned = existing == null
        ? DeviceRecord(
            deviceUuid: deviceUuid,
            devicePublicKey: devicePublicKey,
            userId: operatorId,
            deviceName: deviceName,
            issuedAt: now,
            updatedAt: now,
            removedAt: null,
            signature: '',
          )
        : DeviceRecord(
            deviceUuid: deviceUuid,
            devicePublicKey: devicePublicKey,
            userId: operatorId,
            deviceName: deviceName,
            issuedAt: existing.issuedAt,
            updatedAt: now,
            removedAt: null,
            signature: '',
          );
    final signed = await _signing.signDeviceRecord(unsigned, await _authorityIdentityPrivateKey(operatorId));
    final devices = [
      for (final d in current.devices)
        if (d.deviceUuid == deviceUuid) signed else d,
      if (existing == null) signed,
    ];
    final newRevision = _hlcService.receive(current.revision);
    final unsignedFile = DeviceRegistry(version: 1, revision: newRevision, parent: current.revision, userId: operatorId, devices: devices, signature: '');
    final signedFile = await _signing.signDeviceFileOnly(unsignedFile, userPrivateKey: await _authorityIdentityPrivateKey(operatorId));
    await _atomicWrite(canonical, jsonEncode(signedFile.toWireMap()));
    await _refreshDeviceCache(root, operatorId);
    return signedFile;
  }

  @override
  Future<DeviceRegistry> revokeDevice(String deviceUuid) async {
    _requireActive();
    final root = _vaultRootPath!;
    await _ensureCacheLoaded();
    await _refreshIdentity();
    final operatorId = _identity?.userId;
    if (operatorId == null) throw StateError('no local identity; cannot sign the device registry');

    final canonical = _deviceCanonicalPath(root, operatorId);
    final current = await loadDeviceRegistry(operatorId);
    if (current == null) throw StateError('devices/$operatorId.json absent; nothing to revoke');
    final target = current.devicesById[deviceUuid];
    if (target == null) throw ArgumentError.value(deviceUuid, 'deviceUuid', 'not present in the device registry');

    final now = _hlcService.now();
    final tombstone = DeviceRecord(
      deviceUuid: target.deviceUuid,
      devicePublicKey: target.devicePublicKey,
      userId: operatorId,
      deviceName: target.deviceName,
      issuedAt: target.issuedAt,
      updatedAt: now,
      removedAt: now,
      signature: '',
    );
    final signedTomb = await _signing.signDeviceRecord(tombstone, await _authorityIdentityPrivateKey(operatorId));
    final devices = [
      for (final d in current.devices)
        if (d.deviceUuid == deviceUuid) signedTomb else d,
    ];
    final newRevision = _hlcService.receive(current.revision);
    final unsignedFile = DeviceRegistry(version: 1, revision: newRevision, parent: current.revision, userId: operatorId, devices: devices, signature: '');
    final signedFile = await _signing.signDeviceFileOnly(unsignedFile, userPrivateKey: await _authorityIdentityPrivateKey(operatorId));
    await _atomicWrite(canonical, jsonEncode(signedFile.toWireMap()));
    await _refreshDeviceCache(root, operatorId);
    return signedFile;
  }

  // --- Small helpers -------------------------------------------------------

  static const Hlc _zeroHlc = Hlc(physicalMs: 0, counter: 0, deviceId: '00000000');

  Hlc _maxRevision(Iterable<Hlc> revisions) => revisions.reduce((a, b) => a > b ? a : b);

  void _logReport(String what, RegistryReconcileReport report) {
    if (report.decisions.isNotEmpty) {
      _log.info('$what merge: ${report.decisions.map((d) => d.toString()).join('; ')}');
    }
    if (report.droppedFiles.isNotEmpty) {
      _log.warning('$what file-level LWW dropped: ${report.droppedFiles.map(_nameOf).join(', ')}');
    }
    if (report.note != null) {
      _log.info('$what reconcile: ${report.mode} — ${report.note}');
    }
  }

  Future<UserRegistry?> _readUserRegistryOrNull(String root) async {
    final path = _usersCanonicalPath(root);
    if (!await _fileSystem.fileExists(path)) return null;
    try {
      final map = (jsonDecode(await _fileSystem.readFile(path)) as Map).cast<String, dynamic>();
      return UserRegistry.fromWireMap(map);
    } on Exception {
      return null;
    }
  }

  Future<DeviceRegistry?> _readDeviceRegistryOrNull(String root, String userId) async {
    final path = _deviceCanonicalPath(root, userId);
    if (!await _fileSystem.fileExists(path)) return null;
    try {
      final map = (jsonDecode(await _fileSystem.readFile(path)) as Map).cast<String, dynamic>();
      return DeviceRegistry.fromWireMap(map);
    } on Exception {
      return null;
    }
  }
}

/// A computed (not yet committed) user-registry plan.
final class _UsersPlan {
  const _UsersPlan({
    required this.mode,
    this.reportMode,
    this.registry,
    this.sourcePath,
    this.decisions = const [],
    this.toDelete = const [],
    this.rejectedFiles = const [],
    this.droppedFiles = const [],
    this.note,
    this.newParent,
    this.maxInput,
  });

  final String mode; // 'noop' | 'adopt' | 'merge'
  final String? reportMode; // 'fast-path' | 'lww-fallback'
  final UserRegistry? registry;
  final String? sourcePath; // for 'adopt': the file to move to canonical
  final List<RecordMergeDecision> decisions;
  final List<String> toDelete;
  final List<String> rejectedFiles;
  final List<String> droppedFiles;
  final String? note;
  final Hlc? newParent;
  final Hlc? maxInput;
}

/// A computed (not yet committed) device-registry plan.
final class _DevicesPlan {
  const _DevicesPlan({
    required this.mode,
    this.reportMode,
    this.registry,
    this.sourcePath,
    this.decisions = const [],
    this.toDelete = const [],
    this.rejectedFiles = const [],
    this.note,
    this.newParent,
    this.maxInput,
  });

  final String mode; // 'noop' | 'adopt' | 'merge'
  final String? reportMode; // 'fast-path' | 'lww-fallback'
  final DeviceRegistry? registry;
  final String? sourcePath; // for 'adopt': the file to move to canonical
  final List<RecordMergeDecision> decisions;
  final List<String> toDelete;
  final List<String> rejectedFiles;
  final String? note;
  final Hlc? newParent;
  final Hlc? maxInput;
}
