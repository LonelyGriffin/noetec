// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:command_it/command_it.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/device/device_identity.dart';
import 'package:noetec/entity/vault.dart';
import 'package:noetec/service/device_service.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/service/id_service.dart';
import 'package:noetec/systems/vault/vault_repository.dart';
import 'package:noetec/systems/vault/vault_system.dart';

class FakeFileSystemService implements IFileSystemService {
  final Map<String, String> files = {};
  final Set<String> directories = {};

  String _normalize(String path) => path.replaceAll('\\', '/');

  @override
  Future<bool> directoryExists(String path) async =>
      directories.contains(_normalize(path));

  @override
  Future<void> createDirectory(String path) async {
    directories.add(_normalize(path));
  }

  @override
  Future<String> readFile(String path) async {
    final normalized = _normalize(path);
    if (!files.containsKey(normalized)) {
      throw Exception('File not found: $normalized');
    }
    return files[normalized]!;
  }

  @override
  Future<void> writeFile(String path, String content) async {
    files[_normalize(path)] = content;
  }

  @override
  Future<bool> fileExists(String path) async =>
      files.containsKey(_normalize(path));

  @override
  Future<String?> pickDirectory() async => null;

  @override
  Future<List<FileEntry>> listDirectory(String path) async {
    final normalized = _normalize(path);
    final entries = <FileEntry>[];
    final seen = <String>{};

    for (final dir in directories) {
      if (dir.startsWith('$normalized/')) {
        final relative = dir.substring(normalized.length + 1);
        final name = relative.split('/').first;
        if (seen.add(name)) {
          entries.add(
            FileEntry(name: name, path: '$normalized/$name', isDirectory: true),
          );
        }
      }
    }

    for (final file in files.keys) {
      if (file.startsWith('$normalized/')) {
        final relative = file.substring(normalized.length + 1);
        if (!relative.contains('/')) {
          entries.add(
            FileEntry(
              name: relative,
              path: file,
              isDirectory: false,
              lastModified: DateTime.now(),
            ),
          );
        }
      }
    }

    return entries;
  }

  @override
  Future<void> deleteFile(String path) async {
    files.remove(_normalize(path));
  }

  @override
  Future<void> renameFileOrDirectory(String oldPath, String newPath) async {}

  @override
  Stream<FileEntry> watchDirectory(
    String path, {
    Duration pollInterval = const Duration(seconds: 5),
  }) => const Stream.empty();

  @override
  Future<void> appendToFile(String path, String content) async {
    final normalized = _normalize(path);
    files[normalized] = (files[normalized] ?? '') + content;
  }
}

class FakeVaultRepository implements IVaultRepository {
  List<VaultEntity> _vaults = [];

  @override
  Future<List<VaultEntity>> loadRecentVaults() async => List.of(_vaults);

  @override
  Future<void> saveRecentVaults(List<VaultEntity> vaults) async {
    _vaults = List.of(vaults);
  }

  @override
  Future<void> addToRecent(VaultEntity vault) async {
    _vaults.removeWhere((existing) => existing.id == vault.id);
    _vaults.insert(0, vault);
  }

  @override
  Future<void> removeFromRecent(String vaultId) async {
    _vaults.removeWhere((existing) => existing.id == vaultId);
  }
}

class FakeIdService implements IIdService {
  int _counter = 0;

  @override
  String generateId() => 'test-id-${_counter++}';
}

class FakeDeviceService implements IDeviceService {
  DeviceIdentity? _device;

  @override
  DeviceIdentity? get currentDevice => _device;

  @override
  Future<DeviceIdentity> ensureDevice(
    String vaultRootPath,
    String vaultId,
  ) async {
    _device = DeviceIdentity(
      uuid: 'test-device-uuid',
      name: 'test',
      createdAt: DateTime.now(),
      lastHlc: null,
    );
    return _device!;
  }

  @override
  Future<void> updateLastHlc(String vaultRootPath, String hlcKey) async {}

  @override
  void clear() {
    _device = null;
  }
}

void main() {
  group('VaultSystem —', () {
    late FakeFileSystemService fakeFileSystem;
    late FakeVaultRepository fakeRepository;
    late FakeIdService fakeIdService;
    late FakeDeviceService fakeDeviceService;
    late VaultSystem vaultSystem;

    setUp(() {
      Command.globalExceptionHandler = (_, _) {};
      fakeFileSystem = FakeFileSystemService();
      fakeRepository = FakeVaultRepository();
      fakeIdService = FakeIdService();
      fakeDeviceService = FakeDeviceService();
      vaultSystem = VaultSystem(
        fakeFileSystem,
        fakeRepository,
        fakeIdService,
        fakeDeviceService,
      );
    });

    tearDown(() {
      vaultSystem.dispose();
      Command.globalExceptionHandler = null;
    });

    test('createVault — creates vault on disk and sets currentVault', () async {
      await vaultSystem.createVaultCommand.runAsync((
        parentPath: '/test',
        vaultName: 'my-vault',
      ));

      expect(vaultSystem.currentVault.value, isNotNull);
      expect(vaultSystem.currentVault.value!.name, equals('my-vault'));
      expect(
        vaultSystem.currentVault.value!.rootPath.endsWith('my-vault'),
        isTrue,
      );
      expect(
        fakeFileSystem.files.keys.any(
          (key) => key.endsWith('.noetec/vault.json'),
        ),
        isTrue,
      );
      expect(
        fakeFileSystem.directories.any((dir) => dir.endsWith('.noetec')),
        isTrue,
      );
    });

    test('createVault — adds vault to recentVaults', () async {
      await vaultSystem.createVaultCommand.runAsync((
        parentPath: '/test',
        vaultName: 'my-vault',
      ));

      expect(vaultSystem.recentVaults, hasLength(1));
      expect(
        vaultSystem.recentVaults.first.rootPath.endsWith('my-vault'),
        isTrue,
      );
    });

    test(
      'createVault — throws DirectoryAlreadyExistsException on existing dir',
      () async {
        fakeFileSystem.directories.add('/test/existing');

        await expectLater(
          vaultSystem.createVaultCommand.runAsync((
            parentPath: '/test',
            vaultName: 'existing',
          )),
          throwsA(isA<DirectoryAlreadyExistsException>()),
        );
      },
    );

    test('openVault — opens valid vault and sets currentVault', () async {
      fakeFileSystem.files['/existing/path/.noetec/vault.json'] =
          '{"id":"existing-id","name":"Existing",'
          '"rootPath":"/existing/path",'
          '"createdAt":"2026-01-01T00:00:00.000Z"}';

      await vaultSystem.openVaultCommand.runAsync('/existing/path');

      expect(vaultSystem.currentVault.value, isNotNull);
      expect(vaultSystem.currentVault.value!.id, equals('existing-id'));
    });

    test(
      'openVault — throws InvalidVaultException on non-vault path',
      () async {
        await expectLater(
          vaultSystem.openVaultCommand.runAsync('/non/vault'),
          throwsA(isA<InvalidVaultException>()),
        );
      },
    );

    test('closeVault — sets currentVault to null', () async {
      await vaultSystem.createVaultCommand.runAsync((
        parentPath: '/test',
        vaultName: 'my-vault',
      ));
      expect(vaultSystem.currentVault.value, isNotNull);

      await vaultSystem.closeVaultCommand.runAsync();
      expect(vaultSystem.currentVault.value, isNull);
    });

    test('init — loads recent vaults from repository', () async {
      final vault = VaultEntity(
        id: 'saved-id',
        name: 'Saved',
        rootPath: '/saved/path',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      await fakeRepository.addToRecent(vault);

      await vaultSystem.init();

      expect(vaultSystem.recentVaults, hasLength(1));
      expect(vaultSystem.recentVaults.first.id, equals('saved-id'));
    });
  });
}
