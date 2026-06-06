// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:get_it/get_it.dart';
import 'package:noetec/service/id_service.dart';

Future<void> configureDI() async {
  GetIt.instance.debugEventsEnabled = true;
  GetIt.instance.registerSingleton<IIdService>(IdService());
}
