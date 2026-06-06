// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

abstract interface class IIdService {
  String generateId();
}

// TODO improve service make id uniq in any situation
class IdService implements IIdService {
  @override
  String generateId() => _uuid.v4();
}
