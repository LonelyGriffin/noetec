// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

class VaultEntity {
  final String id;
  final String name;
  final String rootPath;
  final DateTime createdAt;

  const VaultEntity({
    required this.id,
    required this.name,
    required this.rootPath,
    required this.createdAt,
  });

  factory VaultEntity.fromMap(Map<String, dynamic> map) {
    return VaultEntity(
      id: map['id'] as String,
      name: map['name'] as String,
      rootPath: map['rootPath'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'rootPath': rootPath,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  VaultEntity rename(String newName) => VaultEntity(
    id: id,
    name: newName,
    rootPath: rootPath,
    createdAt: createdAt,
  );

  VaultEntity relocate(String newRootPath) => VaultEntity(
    id: id,
    name: name,
    rootPath: newRootPath,
    createdAt: createdAt,
  );

  VaultEntity withUpdate({String? name, String? rootPath}) => VaultEntity(
    id: id,
    name: name ?? this.name,
    rootPath: rootPath ?? this.rootPath,
    createdAt: createdAt,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VaultEntity &&
          id == other.id &&
          name == other.name &&
          rootPath == other.rootPath &&
          createdAt == other.createdAt;

  @override
  int get hashCode =>
      id.hashCode ^ name.hashCode ^ rootPath.hashCode ^ createdAt.hashCode;
}
