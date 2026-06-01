// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

/// Generates unique identifiers.
///
/// In production, backed by `uuid.v4()`.
/// In tests, can be replaced with a predictable generator (e.g. counter).
class IdService {
  final String Function() _generate;

  IdService(this._generate);

  String generateId() => _generate();
}
