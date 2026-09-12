// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'package:logging/logging.dart';
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/service/crypto_service.dart';
import 'package:noetec/service/device_service.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/service/hlc_service.dart';
import 'package:noetec/service/secure_key_store.dart';
import 'package:noetec/systems/oplog_system/block_diff_engine.dart';
import 'package:noetec/systems/oplog_system/oplog_authorizer.dart';
import 'package:noetec/systems/oplog_system/oplog_dag.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';
import 'package:noetec/systems/oplog_system/oplog_reader.dart';
import 'package:noetec/systems/oplog_system/oplog_serializer.dart';
import 'package:noetec/systems/oplog_system/oplog_signer.dart';
import 'package:noetec/systems/oplog_system/oplog_verifier.dart';
import 'package:noetec/systems/oplog_system/oplog_writer.dart';
import 'package:noetec/systems/vault/vault_system.dart';

class OpLogSystem {
  OpLogSystem({
    required IFileSystemService fileSystem,
    required HlcService hlcService,
    required VaultSystem vaultSystem,
    required IDeviceService deviceService,
    required ICryptoService crypto,
    required ISecureKeyStore secureKeyStore,
    OpLogAuthorizer? authorizer,
  }) : _fileSystem = fileSystem,
       _hlcService = hlcService,
       _vaultSystem = vaultSystem,
       _deviceService = deviceService,
       _crypto = crypto,
       _secureKeyStore = secureKeyStore,
       _authorizer = authorizer {
    _serializer = const OpLogSerializer();
    _signer = OpLogSigner(crypto: _crypto, secureKeyStore: _secureKeyStore, serializer: _serializer);
    // The key resolver supplies the authoring device's public key for a device
    // file that carries no `pubKey` on any entry (a mixed legacy/signed file).
    // In Phase 1 the only trusted source is `device.json` for the *local*
    // device; remote-device key trust arrives with the Phase-4 TOFU store
    // (NOET-30). A signed entry whose key cannot be resolved is rejected.
    _verifier = OpLogVerifier(crypto: _crypto, serializer: _serializer, keyResolver: _resolveDeviceKey);
    _vaultSystem.currentVault.addListener(_onVaultChanged);
  }

  final IFileSystemService _fileSystem;
  final HlcService _hlcService;
  final VaultSystem _vaultSystem;
  final IDeviceService _deviceService;
  final ICryptoService _crypto;
  final ISecureKeyStore _secureKeyStore;

  /// Runs the attribution/authorization chain (sync-security.md §7 steps 3–5:
  /// TOFU → certificate → registry filter) over the entries read by
  /// [buildDag]. When `null` (e.g. low-level tests) the DAG is built from every
  /// signature-verified entry, preserving the pre-gate behavior.
  final OpLogAuthorizer? _authorizer;
  static final Logger _log = Logger('OpLogSystem');

  /// The rejection reports from the most recent [buildDag] that ran the gate
  /// (sync-security.md §9 — rejections are surfaced, never silently dropped).
  /// Exposed for the sync-status UI (NOET-33); empty when no gate ran or
  /// nothing was rejected.
  final List<EntryRejectionReport> _lastRejections = [];
  List<EntryRejectionReport> get lastRejections => List.unmodifiable(_lastRejections);

  String? _vaultRootPath;
  String? _vaultId;
  String? _deviceId;
  late final OpLogSerializer _serializer;
  late final OpLogSigner _signer;
  late final OpLogVerifier _verifier;
  OpLogWriter? _writer;
  OpLogReader? _reader;

  final Map<String, List<TextBlockEntity>> _lastKnownState = {};
  final Map<String, Hlc> _lastHlcByFile = {};

  /// Phase-1 key resolution for a device file with no `pubKey`: returns the
  /// local device's base64url public key (from `device.json`) when [deviceId]
  /// is this device, else `null`.
  Future<String?> _resolveDeviceKey(String deviceId) async {
    final device = _deviceService.currentDevice;
    if (device == null || device.uuid != deviceId) return null;
    final pubKey = device.publicKey;
    if (pubKey == null || pubKey.isEmpty) return null;
    return normalizeToBase64Url(pubKey);
  }

  void _onVaultChanged() {
    final vault = _vaultSystem.currentVault.value;
    if (vault != null) {
      final device = _deviceService.currentDevice;
      if (device == null) return;
      _vaultRootPath = vault.rootPath;
      _vaultId = vault.id;
      _deviceId = device.uuid;
      // A Phase-1 device that cannot publish its key (no publicKey) degrades
      // to writing legacy (unsigned) entries rather than emit un-verifiable
      // ones.
      final pubKey = device.publicKey;
      final signer = (pubKey == null || pubKey.isEmpty) ? null : _signer;
      _writer = OpLogWriter(_fileSystem, _vaultRootPath!, _serializer, signer: signer, vaultId: _vaultId, devicePublicKeyBase64Url: pubKey);
      _reader = OpLogReader(_fileSystem, _vaultRootPath!, _serializer, verifier: _verifier);
    } else {
      _vaultRootPath = null;
      _vaultId = null;
      _deviceId = null;
      _writer = null;
      _reader = null;
      _lastKnownState.clear();
      _lastHlcByFile.clear();
    }
  }

  bool get _isActive => _vaultRootPath != null && _deviceId != null;

  Future<void> recordSave(String relativePath, String pageId, List<TextBlockEntity> currentBlocks, String fileHash) async {
    if (!_isActive) return;
    final previous = _lastKnownState[pageId] ?? const [];
    final diff = BlockDiffEngine.compute(previous, currentBlocks);

    var parentHlc = await _resolveParent(relativePath);

    if (diff.isNotEmpty) {
      final editHlc = _hlcService.now();
      await _writer!.append(
        relativePath,
        OpLogEntry(version: 1, hlc: editHlc, parent: parentHlc, parentB: null, type: OpEntryType.edit, blockOps: diff, fileOp: null, fileHash: null, deviceId: _deviceId!),
      );
      parentHlc = editHlc;
      _lastHlcByFile[relativePath] = editHlc;
    }

    final saveHlc = _hlcService.now();
    await _writer!.append(
      relativePath,
      OpLogEntry(
        version: 1,
        hlc: saveHlc,
        parent: parentHlc,
        parentB: null,
        type: OpEntryType.save,
        blockOps: null,
        fileOp: null,
        fileHash: _withPrefix(fileHash),
        deviceId: _deviceId!,
      ),
    );
    _lastHlcByFile[relativePath] = saveHlc;
    _lastKnownState[pageId] = _snapshotBlocks(currentBlocks);
  }

  Future<void> recordFileCreate(String relativePath, String pageId, List<TextBlockEntity> initialBlocks) async {
    if (!_isActive) return;
    final snapshots = <TextBlockSnapshot>[];
    String? afterId;
    for (final block in initialBlocks) {
      snapshots.add(TextBlockSnapshot(blockId: block.id, afterBlockId: afterId, segments: List.of(block.segments)));
      afterId = block.id;
    }

    final hlc = _hlcService.now();
    await _writer!.append(
      relativePath,
      OpLogEntry(
        version: 1,
        hlc: hlc,
        parent: null,
        parentB: null,
        type: OpEntryType.fileCreate,
        blockOps: null,
        fileOp: FileCreateOp(pageId: pageId, initialBlocks: snapshots),
        fileHash: null,
        deviceId: _deviceId!,
      ),
    );
    _lastHlcByFile[relativePath] = hlc;
  }

  Future<void> recordFileDelete(String relativePath) async {
    if (!_isActive) return;
    final parentHlc = await _resolveParent(relativePath);
    final hlc = _hlcService.now();
    await _writer!.append(
      relativePath,
      OpLogEntry(
        version: 1,
        hlc: hlc,
        parent: parentHlc,
        parentB: null,
        type: OpEntryType.fileDelete,
        blockOps: null,
        fileOp: const FileDeleteOp(),
        fileHash: null,
        deviceId: _deviceId!,
      ),
    );
    _lastHlcByFile[relativePath] = hlc;
  }

  Future<void> recordFileRename(String oldPath, String newPath) async {
    if (!_isActive) return;
    final parentHlc = await _resolveParent(oldPath, fallbackPath: newPath);
    final hlc = _hlcService.now();
    await _writer!.append(
      newPath,
      OpLogEntry(
        version: 1,
        hlc: hlc,
        parent: parentHlc,
        parentB: null,
        type: OpEntryType.fileRename,
        blockOps: null,
        fileOp: FileRenameOp(oldPath: oldPath, newPath: newPath),
        fileHash: null,
        deviceId: _deviceId!,
      ),
    );
    _lastHlcByFile.remove(oldPath);
    _lastHlcByFile[newPath] = hlc;
  }

  Future<void> recordExternalEdit(String relativePath, List<TextBlockEntity> currentBlocks, String fileHash, {String? pageId}) async {
    if (!_isActive) return;
    final previous = (pageId != null ? _lastKnownState[pageId] : null) ?? const [];
    final ops = BlockDiffEngine.compute(previous, currentBlocks);

    final parentHlc = await _resolveParent(relativePath);
    final hlc = _hlcService.now();
    await _writer!.append(
      relativePath,
      OpLogEntry(
        version: 1,
        hlc: hlc,
        parent: parentHlc,
        parentB: null,
        type: OpEntryType.externalEdit,
        blockOps: ops,
        fileOp: null,
        fileHash: _withPrefix(fileHash),
        deviceId: _deviceId!,
      ),
    );
    _lastHlcByFile[relativePath] = hlc;
    if (pageId != null) {
      _lastKnownState[pageId] = _snapshotBlocks(currentBlocks);
    }
  }

  Future<void> recordMerge(String relativePath, Hlc parentA, Hlc parentB, String fileHash) async {
    if (!_isActive) return;
    final hlc = _hlcService.now();
    await _writer!.append(
      relativePath,
      OpLogEntry(
        version: 1,
        hlc: hlc,
        parent: parentA,
        parentB: parentB,
        type: OpEntryType.merge,
        blockOps: null,
        fileOp: null,
        fileHash: _withPrefix(fileHash),
        deviceId: _deviceId!,
      ),
    );
    _lastHlcByFile[relativePath] = hlc;
  }

  /// Loads the registry snapshot **once per sync cycle** for the
  /// attribution/authorization gate (sync-security.md §7 steps 3–5).
  ///
  /// [SyncSystem] calls this at the start of a `checkAll` cycle and threads the
  /// result through every [buildDag] of the cycle, so the expensive
  /// registry read+verify pass is performed once per cycle rather than once
  /// per `.oplog.jsonl` file. Returns `null` when no gate is installed (the
  /// pre-gate behavior is preserved) or no vault is active.
  Future<RegistrySnapshot?> prepareVerification() async {
    final authorizer = _authorizer;
    if (authorizer == null || _vaultRootPath == null || _deviceId == null || _reader == null) return null;
    return authorizer.loadSnapshot();
  }

  Future<OpLogDag> buildDag(String relativePath, {RegistrySnapshot? verification}) async {
    final root = _vaultRootPath;
    if (root == null || _deviceId == null || _reader == null) return OpLogDag.fromEntries(const {});
    final logs = await _reader!.readAllLogs(relativePath);
    final authorizer = _authorizer;
    if (authorizer == null) {
      _lastRejections.clear();
      return OpLogDag.fromEntries(logs);
    }
    // Verification gate (sync-security.md §7, §2.4 rule 6): entries are
    // filtered through the attribution/authorization chain (TOFU →
    // certificate → registry filter) *before* they contribute to the DAG,
    // merge decisions, or witness state. Rejected entries never enter the DAG
    // and are reported via [OpLogAuthorizer] (never silently dropped).
    //
    // [verification] is the cycle's registry snapshot (see
    // [prepareVerification]); when omitted it is loaded on demand.
    final outcome = await authorizer.authorize(vaultRootPath: root, relativePath: relativePath, entriesByDevice: logs, snapshot: verification);
    _lastRejections
      ..clear()
      ..addAll(outcome.rejections);
    if (outcome.rejections.isNotEmpty) {
      _log.warning('Verification gate for $relativePath rejected: ${outcome.rejections.map((r) => r.toString()).join('; ')}');
    }
    return OpLogDag.fromEntries(outcome.accepted);
  }

  void initLastKnownState(String pageId, List<TextBlockEntity> blocks) {
    _lastKnownState[pageId] = _snapshotBlocks(blocks);
  }

  void clearLastKnownState(String pageId) {
    _lastKnownState.remove(pageId);
  }

  bool hasLastKnownState(String pageId) => _lastKnownState.containsKey(pageId);

  Future<Hlc?> _resolveParent(String relativePath, {String? fallbackPath}) async {
    final cached = _lastHlcByFile[relativePath] ?? (fallbackPath != null ? _lastHlcByFile[fallbackPath] : null);
    if (cached != null) return cached;

    final last = await _lastHlcFromDisk(relativePath) ?? (fallbackPath != null ? await _lastHlcFromDisk(fallbackPath) : null);
    if (last != null) {
      _lastHlcByFile[relativePath] = last;
    }
    return last;
  }

  Future<Hlc?> _lastHlcFromDisk(String relativePath) async {
    if (_reader == null || _deviceId == null) return null;
    final entries = await _reader!.readDeviceLog(relativePath, _deviceId!);
    if (entries.isEmpty) return null;
    var last = entries.first.hlc;
    for (final entry in entries) {
      if (entry.hlc > last) last = entry.hlc;
    }
    return last;
  }

  static String _withPrefix(String hash) => hash.startsWith('sha256:') ? hash : 'sha256:$hash';

  static List<TextBlockEntity> _snapshotBlocks(List<TextBlockEntity> blocks) {
    return blocks.map((b) => TextBlockEntity(id: b.id, segments: List.of(b.segments))).toList();
  }

  void dispose() {
    _vaultSystem.currentVault.removeListener(_onVaultChanged);
    _lastKnownState.clear();
    _lastHlcByFile.clear();
  }
}
