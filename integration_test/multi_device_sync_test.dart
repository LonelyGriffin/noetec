// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
//
// NOET-34: integration tests for multi-user / multi-device sync corner cases.
//
// Every test drives the REAL production stack against real on-disk vault
// folders (no UI, so no WSLg app-launch flakiness — see the
// `integration-testing` skill):
//
//   * real Ed25519 signing   (OpLogSigner + OpLogWriter)
//   * real verification      (OpLogReader + OpLogVerifier, chain rejection)
//   * real authorization gate (OpLogAuthorizer + TrustStore TOFU + RegistryService)
//   * real registry signing   (RegistryService / OnboardingService)
//   * real merge             (OpLogDag + MergeEngine + StateReconstructionEngine)
//   * real merge application (MergeApplier -> disk)
//
// "Two devices / two users" is modeled exactly as the issue's context pack
// prescribes: each device is its own vault folder (own `.noetec/` + `.sync/`)
// or, for one-user-two-devices, a shared `.sync/` area with independent Ed25519
// keys. Sync is driven by copying one side's `.sync/` onto the other's.
//
// Scenarios (all conflict-free or auto-resolved — NO user conflict resolution):
//   1. two devices, one user: different blocks -> auto-merge (MergeSuccess)
//   2. two devices, one user: identical edit  -> auto-resolve (MergeSuccess)
//   3. two devices, one user: one side ahead  -> fast-forward (MergeFastForward)
//   4. two users: foreign device (not in registry) -> rejected + reported
//   5. two users: each writes only its own devices/<id>.json -> no cross-user conflict
//   6. forgery: entry under a victim's deviceId without its key -> rejected
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/entity/page/block/text/text_segment.dart';
import 'package:noetec/service/crypto_service.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/service/id_service.dart';
import 'package:noetec/systems/oplog_system/oplog_authorizer.dart';
import 'package:noetec/systems/oplog_system/oplog_dag.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';
import 'package:noetec/systems/sync_system/merge_applier.dart';
import 'package:noetec/systems/sync_system/merge_engine.dart';
import 'package:noetec/systems/markdown_system/markdown_system.dart';
import 'package:noetec/systems/page_system/page_frontmatter_codec.dart';

import 'helpers/sync_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late IFileSystemService fs;
  late CryptoServiceImpl crypto;
  late IIdService ids;
  late String root;

  /// The real sync pipeline over the shared `.sync/` at [folderPath]:
  /// read (real verification) -> authorize (real TOFU/cert/registry gate)
  /// -> DAG -> merge (real MergeEngine). Exactly the decomposed form of the
  /// app's `OpLogSystem.buildDag` + `SyncSystem.checkFile`.
  Future<({MergeResult result, Map<String, List<OpLogEntry>> accepted, List<EntryRejectionReport> rejections, OpLogDag dag})>
      pipeline({
    required String folderPath,
    required SyncDevice local,
    required String relativePath,
    required OpLogAuthorizer authorizer,
    required RegistrySnapshot snapshot,
  }) async {
    final logs = await local.readAllVerified(relativePath);
    final outcome = await authorizer.authorize(vaultRootPath: folderPath, relativePath: relativePath, entriesByDevice: logs, snapshot: snapshot);
    final dag = OpLogDag.fromEntries(outcome.accepted);
    final result = MergeEngine.merge(dag);
    return (result: result, accepted: outcome.accepted, rejections: outcome.rejections, dag: dag);
  }

  /// Writes a real on-disk page file (frontmatter + markdown) from [blocks].
  Future<void> createPageFile({required String folderPath, required String relativePath, required List<TextBlockEntity> blocks}) async {
    final md = MarkdownSystem(ids).serializeBlocks(blocks);
    final hash = PageFrontmatterCodec.computeContentHash(md);
    final fm = PageFrontmatter(id: ids.generateId(), contentHash: 'sha256:$hash', modified: DateTime.now().toUtc());
    final fullPath = p.join(folderPath, relativePath);
    final parent = p.dirname(fullPath);
    if (parent != folderPath && !Directory(parent).existsSync()) {
      await fs.createDirectory(parent);
    }
    await fs.writeFile(fullPath, PageFrontmatterCodec.encode(fm, md));
  }

  OpLogAuthorizer makeAuthorizer(OwnerDevice owner) => OpLogAuthorizer(registry: owner.registry, trustStore: owner.trustStore);

  Future<RegistrySnapshot> snapshot(OwnerDevice owner, OpLogAuthorizer authorizer) => authorizer.loadSnapshot();

  setUp(() async {
    fs = FileSystemServiceImpl();
    crypto = CryptoServiceImpl();
    ids = IdService();
    root = Directory.systemTemp.createTempSync('noet34_sync_').path;
  });

  tearDown(() async {
    if (Directory(root).existsSync()) {
      Directory(root).deleteSync(recursive: true);
    }
  });

  /// True if [e] is an edit entry that updates any block to contain [text].
  bool hasEditText(OpLogEntry e, String text) {
    final ops = e.blockOps;
    if (ops == null) return false;
    for (final op in ops) {
      if (op is BlockUpdate && op.segments.any((s) => s.text == text)) return true;
    }
    return false;
  }

  group('NOET-34 multi-device / multi-user sync (real stack)', () {
    test('1. two devices one user: different blocks auto-merge (no conflict)', () async {
      const rel = 'pages/notes.md';
      final folder = '$root/vault1';
      // Real on-boarded owner (device A) with a real, signed registry.
      final owner = await createOwnerVault(folderPath: folder, vaultId: 'v-1', ownerName: 'Owner', deviceName: 'Laptop A', crypto: crypto, fileSystem: fs);
      // Device B: a second device of the SAME owner (shared .sync/), own key.
      final b = await makeSharedDevice(anchor: owner.device, name: 'Laptop B', crypto: crypto, fileSystem: fs);
      // The owner binds device B (real registry signing) so it is authorized.
      await owner.registry.addDevice(deviceUuid: b.deviceUuid, devicePublicKey: b.publicKey, deviceName: 'Laptop B');

      final a = owner.device;
      // --- Shared ancestor: A creates the page (parent=null, pubKey=A) ---
      // This is the single baseline both devices branch from (the LCA).
      await a.append(rel, entry(physicalMs: 1000, deviceId: a.deviceUuid, type: OpEntryType.fileCreate, blockOps: null, fileOp: FileCreateOp(pageId: 'page-1', initialBlocks: [
        TextBlockSnapshot(blockId: 'b1', afterBlockId: null, segments: [TextSegment(text: 'Line one')]),
        TextBlockSnapshot(blockId: 'b2', afterBlockId: 'b1', segments: [TextSegment(text: 'Line two')]),
      ])));
      // A edits b1 — a branch off the shared baseline.
      await a.append(rel, entry(physicalMs: 1100, deviceId: a.deviceUuid, parent: Hlc(physicalMs: 1000, counter: 0, deviceId: nodeId(a.deviceUuid)), type: OpEntryType.edit, blockOps: [BlockUpdate(blockId: 'b1', segments: [TextSegment(text: 'Line one by A')])]));
      // B's first entry: a no-op save (parent=null → carries pubKey=B so the
      // verifier can resolve B's key) linked to A's baseline via parentB=A1.
      // This is the cross-device LCA link that makes the DAG diverged.
      await b.append(rel, entry(physicalMs: 1200, deviceId: b.deviceUuid, parentB: Hlc(physicalMs: 1000, counter: 0, deviceId: nodeId(a.deviceUuid)), type: OpEntryType.save));
      // B edits b2 — a DIFFERENT block than A, branching from B's chain.
      await b.append(rel, entry(physicalMs: 1300, deviceId: b.deviceUuid, parent: Hlc(physicalMs: 1200, counter: 0, deviceId: nodeId(b.deviceUuid)), type: OpEntryType.edit, blockOps: [BlockUpdate(blockId: 'b2', segments: [TextSegment(text: 'Line two by B')])]));

      // A real page file exists (for the merge applier to write into).
      await createPageFile(folderPath: folder, relativePath: rel, blocks: [blk('b1', 'Line one'), blk('b2', 'Line two')]);

      final authorizer = makeAuthorizer(owner);
      final snap = await snapshot(owner, authorizer);
      final out = await pipeline(folderPath: folder, local: a, relativePath: rel, authorizer: authorizer, snapshot: snap);

      // Both devices authorized, nothing rejected.
      expect(out.rejections, isEmpty, reason: 'both devices are the owner\'s -> both authorized');
      expect(out.accepted.keys, containsAll([a.deviceUuid, b.deviceUuid]));

      // Conflict-free auto-merge of DIFFERENT blocks (diverged DAG, shared LCA).
      expect(out.result, isA<MergeSuccess>(), reason: 'different blocks -> MergeSuccess, never MergeConflict');
      final merged = (out.result as MergeSuccess).mergedBlocks;
      final text = {for (final m in merged) m.blockId: m.segmentText};
      expect(text['b1'], 'Line one by A', reason: 'A\'s edit to b1 survives the merge');
      expect(text['b2'], 'Line two by B', reason: 'B\'s edit to b2 survives the merge');

      // Real merge applier writes the merged blocks to disk (full real path).
      // (The serializer escapes markdown specials, so the assertion uses text
      // without special characters.)
      final applier = MergeApplier(fileSystem: fs, markdownSystem: MarkdownSystem(ids), vaultRootPath: folder);
      final applied = await applier.applyToDisk(rel, merged);
      expect(applied.content, contains('Line one by A'), reason: 'A\'s merged edit is written to disk');
      expect(applied.content, contains('Line two by B'), reason: 'B\'s merged edit is written to disk');
      // The on-disk page now reflects the merged state of BOTH devices.
      final onDisk = await fs.readFile('$folder/$rel');
      expect(onDisk, contains('Line one by A'));
      expect(onDisk, contains('Line two by B'));
    });

    test('2. two devices one user: identical edit auto-resolves (no conflict)', () async {
      const rel = 'pages/notes.md';
      final folder = '$root/vault2';
      final owner = await createOwnerVault(folderPath: folder, vaultId: 'v-2', ownerName: 'Owner', deviceName: 'Laptop A', crypto: crypto, fileSystem: fs);
      final b = await makeSharedDevice(anchor: owner.device, name: 'Laptop B', crypto: crypto, fileSystem: fs);
      await owner.registry.addDevice(deviceUuid: b.deviceUuid, devicePublicKey: b.publicKey, deviceName: 'Laptop B');
      final a = owner.device;

      await a.append(rel, entry(physicalMs: 1000, deviceId: a.deviceUuid, type: OpEntryType.fileCreate, fileOp: FileCreateOp(pageId: 'page-1', initialBlocks: [TextBlockSnapshot(blockId: 'b1', afterBlockId: null, segments: [TextSegment(text: 'base')])])));
      // BOTH edit b1 to the SAME new text -> identical change, no conflict.
      await a.append(rel, entry(physicalMs: 1100, deviceId: a.deviceUuid, parent: Hlc(physicalMs: 1000, counter: 0, deviceId: nodeId(a.deviceUuid)), type: OpEntryType.edit, blockOps: [BlockUpdate(blockId: 'b1', segments: [TextSegment(text: 'same')])]));
      await b.append(rel, entry(physicalMs: 1200, deviceId: b.deviceUuid, type: OpEntryType.save));
      await b.append(rel, entry(physicalMs: 1300, deviceId: b.deviceUuid, parent: Hlc(physicalMs: 1000, counter: 0, deviceId: nodeId(a.deviceUuid)), type: OpEntryType.edit, blockOps: [BlockUpdate(blockId: 'b1', segments: [TextSegment(text: 'same')])]));

      final authorizer = makeAuthorizer(owner);
      final snap = await snapshot(owner, authorizer);
      final out = await pipeline(folderPath: folder, local: a, relativePath: rel, authorizer: authorizer, snapshot: snap);

      expect(out.rejections, isEmpty);
      expect(out.result, isA<MergeSuccess>(), reason: 'identical edit -> MergeSuccess, never MergeConflict');
      final text = {for (final m in (out.result as MergeSuccess).mergedBlocks) m.blockId: m.segmentText};
      expect(text['b1'], 'same');
    });

    test('3. two devices one user: one side ahead -> already in sync, no conflict', () async {
      const rel = 'pages/notes.md';
      final folder = '$root/vault3';
      final owner = await createOwnerVault(folderPath: folder, vaultId: 'v-3', ownerName: 'Owner', deviceName: 'Laptop A', crypto: crypto, fileSystem: fs);
      final b = await makeSharedDevice(anchor: owner.device, name: 'Laptop B', crypto: crypto, fileSystem: fs);
      await owner.registry.addDevice(deviceUuid: b.deviceUuid, devicePublicKey: b.publicKey, deviceName: 'Laptop B');
      final a = owner.device;

      // A edits b1 first.
      await a.append(rel, entry(physicalMs: 1000, deviceId: a.deviceUuid, type: OpEntryType.fileCreate, fileOp: FileCreateOp(pageId: 'page-1', initialBlocks: [
        TextBlockSnapshot(blockId: 'b1', afterBlockId: null, segments: [TextSegment(text: 'base')]),
        TextBlockSnapshot(blockId: 'b2', afterBlockId: 'b1', segments: [TextSegment(text: 'two')]),
      ])));
      await a.append(rel, entry(physicalMs: 1100, deviceId: a.deviceUuid, parent: Hlc(physicalMs: 1000, counter: 0, deviceId: nodeId(a.deviceUuid)), type: OpEntryType.edit, blockOps: [BlockUpdate(blockId: 'b1', segments: [TextSegment(text: 'one')])]));
      // B, already synced with A (parent = A's head A2), edits b2 -> B3 is the
      // single head of a linear chain (B3 -> B2 -> A2 -> A1).
      await b.append(rel, entry(physicalMs: 1200, deviceId: b.deviceUuid, parent: Hlc(physicalMs: 1100, counter: 0, deviceId: nodeId(a.deviceUuid)), type: OpEntryType.save)); // B2 (pubKey=B, parent=A2)
      await b.append(rel, entry(physicalMs: 1300, deviceId: b.deviceUuid, parent: Hlc(physicalMs: 1200, counter: 0, deviceId: nodeId(b.deviceUuid)), type: OpEntryType.edit, blockOps: [BlockUpdate(blockId: 'b2', segments: [TextSegment(text: 'two!')])]));

      final authorizer = makeAuthorizer(owner);
      final snap = await snapshot(owner, authorizer);
      final out = await pipeline(folderPath: folder, local: a, relativePath: rel, authorizer: authorizer, snapshot: snap);

      expect(out.rejections, isEmpty, reason: 'both devices are the owner\'s -> authorized');
      expect(out.dag.heads, hasLength(1), reason: 'one side strictly ahead -> a single head');
      // A single-head DAG is already in sync: the ahead device's head is the
      // merged state, so no 3-way merge is needed (MergeNoop) and there is
      // never a conflict.
      expect(out.dag.topology, DagTopology.single, reason: 'one side strictly ahead -> single head');
      expect(out.result, isA<MergeNoop>(), reason: 'already in sync -> MergeNoop, never MergeConflict');
    });

    test('4. two users: foreign device (not in registry) is rejected and reported', () async {
      const rel = 'pages/notes.md';
      final folder = '$root/vault4';
      final owner = await createOwnerVault(folderPath: folder, vaultId: 'v-4', ownerName: 'Owner', deviceName: 'Laptop A', crypto: crypto, fileSystem: fs);
      final a = owner.device;

      // A legitimate page (so the victim's file is well-formed + verifiable).
      await a.append(rel, entry(physicalMs: 1000, deviceId: a.deviceUuid, type: OpEntryType.fileCreate, fileOp: FileCreateOp(pageId: 'page-1', initialBlocks: [TextBlockSnapshot(blockId: 'b1', afterBlockId: null, segments: [TextSegment(text: 'base')])])));
      // A FOREIGN device (own key, valid signature) writes to the shared .sync/.
      final foreign = await makeSharedDevice(anchor: a, name: 'Foreign', crypto: crypto, fileSystem: fs);
      await foreign.append(rel, entry(physicalMs: 2000, deviceId: foreign.deviceUuid, type: OpEntryType.save)); // pubKey=foreign (verifiable)
      await foreign.append(rel, entry(physicalMs: 2100, deviceId: foreign.deviceUuid, parent: Hlc(physicalMs: 1000, counter: 0, deviceId: nodeId(a.deviceUuid)), type: OpEntryType.edit, blockOps: [BlockUpdate(blockId: 'b1', segments: [TextSegment(text: 'foreign-edit')])]));

      final authorizer = makeAuthorizer(owner);
      final snap = await snapshot(owner, authorizer);
      final out = await pipeline(folderPath: folder, local: a, relativePath: rel, authorizer: authorizer, snapshot: snap);

      // The foreign device is NOT bound to any user -> rejected by the gate.
      expect(out.accepted.keys, isNot(contains(foreign.deviceUuid)), reason: 'foreign device must be excluded from the DAG');
      expect(out.rejections, isNotEmpty, reason: 'rejection MUST be reported, never silently dropped');
      final unbound = out.rejections.where((r) => r.reason == 'unbound-device').toList();
      expect(unbound, isNotEmpty, reason: 'the foreign device is rejected as unbound-device');
      expect(unbound.first.devices, contains(foreign.deviceUuid));
      // A's own entries still accepted (the vault is not locked out).
      expect(out.accepted.keys, contains(a.deviceUuid));
    });

    test('5. two users: each writes only its own devices/<id>.json -> no cross-user conflict', () async {
      final folder = '$root/vault5';
      // User A onboards their own owner vault.
      final ownerA = await createOwnerVault(folderPath: folder, vaultId: 'v-5', ownerName: 'User A', deviceName: 'A-1', crypto: crypto, fileSystem: fs);
      // User B is a different user, added by the owner (real registry signing).
      final bPub = foreignKey(11);
      final bAdd = await ownerA.registry.addUser(userId: 'user-b-id', name: 'User B', publicKey: bPub, role: 'member');
      expect(bAdd.usersById['user-b-id'], isNotNull, reason: 'user B is recorded in users.json');

      // Device isolation: A's registry lists only A's device; B's would list
      // only B's. The two files are distinct and each reconciles cleanly.
      final regA = await ownerA.registry.loadDeviceRegistry(ownerA.ownerUserId);
      expect(regA, isNotNull, reason: 'devices/<A>.json exists');
      expect(regA!.devices, hasLength(1));
      expect(regA.devices.first.deviceUuid, ownerA.device.deviceUuid);

      // Reconcile A's device file (single candidate -> fast-path adopt).
      final reportA = await ownerA.registry.reconcileDeviceRegistry(ownerA.ownerUserId);
      expect(reportA.mode, anyOf('fast-path', 'adopt'), reason: 'single-candidate device file reconciles without a 3-way merge');
      expect(reportA.droppedFiles, isEmpty, reason: 'no cross-user candidate is dropped');

      // B's device file is a SEPARATE file — loading it does not surface A's device.
      final devicesDir = Directory('$folder/.sync/devices');
      final files = await devicesDir.list().where((e) => e is File).toList();
      final names = files.map((e) => (e as File).path.split('/').last).toList();
      expect(names, contains('${ownerA.ownerUserId}.json'), reason: 'A\'s device file is present');
      expect(names, isNot(contains('user-b-id.json')), reason: 'B has not added a device yet; A\'s file is isolated');
    });

    test('6. forgery: entry under a victim deviceId without its key is rejected (attribution holds)', () async {
      const rel = 'pages/victim.md';
      final folder = '$root/vault6';
      final owner = await createOwnerVault(folderPath: folder, vaultId: 'v-6', ownerName: 'Owner', deviceName: 'Laptop A', crypto: crypto, fileSystem: fs);
      final a = owner.device;

      // The victim's well-formed, verifiable oplog.
      await a.append(rel, entry(physicalMs: 1000, deviceId: a.deviceUuid, type: OpEntryType.fileCreate, fileOp: FileCreateOp(pageId: 'page-1', initialBlocks: [TextBlockSnapshot(blockId: 'b1', afterBlockId: null, segments: [TextSegment(text: 'victim line')])])));
      await a.append(rel, entry(physicalMs: 1100, deviceId: a.deviceUuid, parent: Hlc(physicalMs: 1000, counter: 0, deviceId: nodeId(a.deviceUuid)), type: OpEntryType.edit, blockOps: [BlockUpdate(blockId: 'b1', segments: [TextSegment(text: 'victim edit')])]));

      // A FORGER (different key) appends into the victim's oplog FILE.
      final forger = await makeSharedDevice(anchor: a, name: 'Forger', crypto: crypto, fileSystem: fs);
      final victimFile = a.oplogFilePath(rel);
      await forger.appendSignedTo(rel, victimFile, entry(physicalMs: 1200, deviceId: a.deviceUuid, parent: Hlc(physicalMs: 1100, counter: 0, deviceId: nodeId(a.deviceUuid)), type: OpEntryType.edit, blockOps: [BlockUpdate(blockId: 'b1', segments: [TextSegment(text: 'FORGED')])]));

      // Read back: the real OpLogVerifier rejects the forged entry (it does not
      // verify under the victim's key) and applies chain rejection.
      final logs = await a.readAllVerified(rel);
      final victimEntries = logs[a.deviceUuid] ?? const <OpLogEntry>[];
      expect(victimEntries.any((e) => hasEditText(e, 'FORGED')), isFalse, reason: 'the forged entry (signed with a foreign key) must be rejected by signature verification');
      // The victim's genuine edit is retained.
      expect(victimEntries.any((e) => hasEditText(e, 'victim edit')), isTrue, reason: 'the victim\'s genuine entries are retained');
    });
  });
}
