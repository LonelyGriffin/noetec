// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

import 'package:flutter/foundation.dart';

@immutable
class VaultEntity {
  final String id;
  final String name;
  final String rootPath;

  const VaultEntity({
    required this.id,
    required this.name,
    required this.rootPath,
  });

  VaultEntity rename(String newName) =>
      VaultEntity(id: id, name: newName, rootPath: rootPath);

  VaultEntity relocate(String newRootPath) =>
      VaultEntity(id: id, name: name, rootPath: newRootPath);

  VaultEntity withUpdate({String? name, String? rootPath}) => VaultEntity(
    id: id,
    name: name ?? this.name,
    rootPath: rootPath ?? this.rootPath,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaultEntity &&
          id == other.id &&
          name == other.name &&
          rootPath == other.rootPath;

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ rootPath.hashCode;
}
