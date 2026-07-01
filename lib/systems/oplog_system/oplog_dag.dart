// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import 'dart:collection';

import 'package:noetec/systems/oplog_system/oplog_models.dart';

enum DagTopology { empty, single, linear, diverged }

class OpLogDag {
  OpLogDag._(this._entriesByHlc, this._childrenByHlc, this._heads);

  final Map<String, OpLogEntry> _entriesByHlc;
  final Map<String, List<OpLogEntry>> _childrenByHlc;
  final Map<String, OpLogEntry> _heads;

  factory OpLogDag.fromEntries(Map<String, List<OpLogEntry>> entriesByDevice) {
    final entriesByHlc = <String, OpLogEntry>{};
    for (final list in entriesByDevice.values) {
      for (final entry in list) {
        entriesByHlc[entry.hlcKey] = entry;
      }
    }

    final childrenByHlc = <String, List<OpLogEntry>>{};
    void addChild(String parentKey, OpLogEntry child) {
      childrenByHlc.putIfAbsent(parentKey, () => []).add(child);
    }

    for (final entry in entriesByHlc.values) {
      if (entry.parent != null) {
        addChild(entry.parent!.toKey(), entry);
      }
      if (entry.parentB != null) {
        addChild(entry.parentB!.toKey(), entry);
      }
    }

    final heads = <String, OpLogEntry>{};
    for (final entry in entriesByHlc.values) {
      final children = childrenByHlc[entry.hlcKey];
      if (children == null || children.isEmpty) {
        final existing = heads[entry.deviceId];
        if (existing == null || entry.hlc > existing.hlc) {
          heads[entry.deviceId] = entry;
        }
      }
    }

    return OpLogDag._(entriesByHlc, childrenByHlc, heads);
  }

  Map<String, OpLogEntry> get entriesByHlc =>
      UnmodifiableMapView(_entriesByHlc);

  Map<String, OpLogEntry> get heads => UnmodifiableMapView(_heads);

  List<OpLogEntry> get sortedEntries {
    final list = _entriesByHlc.values.toList()
      ..sort((a, b) => a.hlc.compareTo(b.hlc));
    return list;
  }

  List<OpLogEntry> childrenOf(OpLogEntry entry) =>
      List.unmodifiable(_childrenByHlc[entry.hlcKey] ?? const []);

  DagTopology get topology {
    if (_entriesByHlc.isEmpty) return DagTopology.empty;
    final headList = _heads.values.toList();
    if (headList.length <= 1) return DagTopology.single;

    for (var i = 0; i < headList.length; i++) {
      for (var j = i + 1; j < headList.length; j++) {
        final a = headList[i];
        final b = headList[j];
        if (!_isAncestor(a, b) && !_isAncestor(b, a)) {
          return DagTopology.diverged;
        }
      }
    }
    return DagTopology.linear;
  }

  OpLogEntry? lca(OpLogEntry a, OpLogEntry b) {
    if (a.hlcKey == b.hlcKey) return a;

    final visitedA = <String>{a.hlcKey};
    final visitedB = <String>{b.hlcKey};
    final queueA = Queue<OpLogEntry>()..add(a);
    final queueB = Queue<OpLogEntry>()..add(b);

    while (queueA.isNotEmpty || queueB.isNotEmpty) {
      if (queueA.isNotEmpty) {
        final node = queueA.removeFirst();
        for (final parent in _parentsOf(node)) {
          final key = parent.hlcKey;
          if (visitedB.contains(key)) return parent;
          if (visitedA.add(key)) queueA.add(parent);
        }
      }
      if (queueB.isNotEmpty) {
        final node = queueB.removeFirst();
        for (final parent in _parentsOf(node)) {
          final key = parent.hlcKey;
          if (visitedA.contains(key)) return parent;
          if (visitedB.add(key)) queueB.add(parent);
        }
      }
    }

    return null;
  }

  List<OpLogEntry> pathFrom(OpLogEntry ancestor, OpLogEntry head) {
    final ancestorKey = ancestor.hlcKey;
    final collected = <String, OpLogEntry>{};
    final stack = <OpLogEntry>[head];
    var reached = false;

    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (node.hlcKey == ancestorKey) {
        reached = true;
        continue;
      }
      if (collected.containsKey(node.hlcKey)) continue;
      collected[node.hlcKey] = node;
      for (final parent in _parentsOf(node)) {
        stack.add(parent);
      }
    }

    if (!reached && head.hlcKey != ancestorKey) {
      return const [];
    }

    final result = collected.values.toList()
      ..sort((a, b) => a.hlc.compareTo(b.hlc));
    return result;
  }

  List<OpLogEntry> _parentsOf(OpLogEntry entry) {
    final parents = <OpLogEntry>[];
    if (entry.parent != null) {
      final p = _entriesByHlc[entry.parent!.toKey()];
      if (p != null) parents.add(p);
    }
    if (entry.parentB != null) {
      final pb = _entriesByHlc[entry.parentB!.toKey()];
      if (pb != null) parents.add(pb);
    }
    return parents;
  }

  bool _isAncestor(OpLogEntry ancestor, OpLogEntry descendant) {
    if (ancestor.hlcKey == descendant.hlcKey) return true;
    final visited = <String>{};
    final stack = <OpLogEntry>[descendant];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      for (final parent in _parentsOf(node)) {
        if (parent.hlcKey == ancestor.hlcKey) return true;
        if (visited.add(parent.hlcKey)) stack.add(parent);
      }
    }
    return false;
  }
}
