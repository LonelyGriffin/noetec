// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:noetec/entity/hlc.dart';

/// The common surface the registry reconciler needs from a record.
///
/// Implemented by `UserRecord` and `DeviceRecord` so the per-record LWW merge
/// (sync-security.md §3.7) is written once and applies identically to both
/// registries.
abstract interface class RegistryRecord {
  /// The record's merge key (a `userId` in `users.json`, a `deviceUuid` in
  /// `devices/<userId>.json`).
  String get recordId;

  /// The HLC that orders this record for LWW: a tombstone is ordered by
  /// `removedAt`, a live record by `updatedAt` (§3.7).
  Hlc get changeHlc;

  /// The full wire form (all spec keys, signature included).
  Map<String, dynamic> toWireMap();

  /// The wire form without `signature` — the per-record signing input.
  Map<String, dynamic> toUnsignedWireMap();
}
