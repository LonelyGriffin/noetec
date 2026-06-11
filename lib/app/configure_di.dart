// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:get_it/get_it.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/service/id_service.dart';
import 'package:noetec/service/settings_service.dart';
import 'package:noetec/systems/vault/vault_repository.dart';
import 'package:noetec/systems/vault/vault_system.dart';

Future<void> configureDI() async {
  final getIt = GetIt.instance;

  getIt.debugEventsEnabled = true;

  getIt.registerSingleton<IIdService>(IdService());
  getIt.registerSingleton<IFileSystemService>(FileSystemServiceImpl());
  getIt.registerSingleton<ISettingsService>(SettingsServiceImpl());
  getIt.registerSingleton<IVaultRepository>(
    VaultRepositoryImpl(getIt<ISettingsService>()),
  );
  getIt.registerSingleton<VaultSystem>(
    VaultSystem(
      getIt<IFileSystemService>(),
      getIt<IVaultRepository>(),
      getIt<IIdService>(),
    ),
  );

  await getIt<VaultSystem>().init();
}
