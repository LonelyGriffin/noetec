// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:get_it/get_it.dart';
import 'package:noetec/service/crypto_service.dart';
import 'package:noetec/service/device_service.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/service/hlc_service.dart';
import 'package:noetec/service/id_service.dart';
import 'package:noetec/service/secure_key_store.dart';
import 'package:noetec/service/settings_service.dart';
import 'package:noetec/service/vault_file_service.dart';
import 'package:noetec/systems/layout/layout_ui_system.dart';
import 'package:noetec/systems/markdown_system/markdown_system.dart';
import 'package:noetec/systems/oplog_system/oplog_system.dart';
import 'package:noetec/systems/page_system/page_system.dart';
import 'package:noetec/systems/persistence_system/crash_recovery_service.dart';
import 'package:noetec/systems/persistence_system/persistence_system.dart';
import 'package:noetec/systems/persistence_system/wal_service.dart';
import 'package:noetec/systems/sync_system/sync_system.dart';
import 'package:noetec/systems/user_input_system/user_input_service.dart';
import 'package:noetec/systems/vault/vault_repository.dart';
import 'package:noetec/systems/vault/vault_system.dart';

Future<void> configureDI({
  IFileSystemService? fileSystem,
  ISettingsService? settings,
  ISecureKeyStore? secureKeyStore,
}) async {
  final getIt = GetIt.instance;

  getIt.debugEventsEnabled = true;

  getIt.registerSingleton<IIdService>(IdService());
  getIt.registerSingleton<IFileSystemService>(
    fileSystem ?? FileSystemServiceImpl(),
  );
  getIt.registerSingleton<ISettingsService>(settings ?? SettingsServiceImpl());
  getIt.registerSingleton<ISecureKeyStore>(
    secureKeyStore ?? SecureKeyStoreImpl(),
  );
  getIt.registerSingleton<ICryptoService>(CryptoServiceImpl());
  getIt.registerSingleton<IDeviceService>(
    DeviceServiceImpl(
      getIt<IFileSystemService>(),
      getIt<IIdService>(),
      getIt<ICryptoService>(),
      getIt<ISecureKeyStore>(),
    ),
  );
  getIt.registerSingleton<IVaultRepository>(
    VaultRepositoryImpl(getIt<ISettingsService>()),
  );
  getIt.registerSingleton<VaultSystem>(
    VaultSystem(
      getIt<IFileSystemService>(),
      getIt<IVaultRepository>(),
      getIt<IIdService>(),
      getIt<IDeviceService>(),
    ),
  );

  getIt.registerSingleton<LayoutUISystem>(LayoutUISystem());

  getIt.registerSingleton<MarkdownSystem>(MarkdownSystem(getIt<IIdService>()));

  getIt.registerSingleton<PageSystem>(
    PageSystem(
      getIt<IIdService>(),
      getIt<MarkdownSystem>(),
      getIt<IFileSystemService>(),
      getIt<VaultSystem>(),
    ),
  );

  getIt.registerSingleton<VaultFileService>(
    VaultFileService(getIt<IFileSystemService>(), getIt<VaultSystem>()),
  );

  getIt.registerSingleton<UserInputService>(
    UserInputService(getIt<PageSystem>()),
  );

  getIt.registerSingleton<HlcService>(
    HlcService(getIt<VaultSystem>(), getIt<IDeviceService>()),
  );

  getIt.registerSingleton<WalService>(
    WalService(getIt<IFileSystemService>(), getIt<VaultSystem>()),
  );

  getIt.registerSingleton<PersistenceSystem>(
    PersistenceSystem(
      wal: getIt<WalService>(),
      pageSystem: getIt<PageSystem>(),
      vaultSystem: getIt<VaultSystem>(),
    ),
  );

  getIt.registerSingleton<CrashRecoveryService>(
    CrashRecoveryService(getIt<WalService>()),
  );

  getIt.registerSingleton<OpLogSystem>(
    OpLogSystem(
      fileSystem: getIt<IFileSystemService>(),
      hlcService: getIt<HlcService>(),
      vaultSystem: getIt<VaultSystem>(),
      deviceService: getIt<IDeviceService>(),
    ),
  );

  getIt.registerSingleton<SyncSystem>(
    SyncSystem(
      oplogSystem: getIt<OpLogSystem>(),
      fileSystem: getIt<IFileSystemService>(),
      markdownSystem: getIt<MarkdownSystem>(),
      vaultSystem: getIt<VaultSystem>(),
      deviceService: getIt<IDeviceService>(),
    ),
  );
}
