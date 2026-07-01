import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/hlc.dart';
import 'package:noetec/systems/oplog_system/oplog_dag.dart';
import 'package:noetec/systems/oplog_system/oplog_models.dart';

OpLogEntry _entry({
  required String hlcKey,
  String? parentKey,
  String? parentBKey,
  String deviceId = 'device-a',
  OpEntryType type = OpEntryType.edit,
}) {
  return OpLogEntry(
    version: 1,
    hlc: Hlc.fromKey(hlcKey),
    parent: parentKey != null ? Hlc.fromKey(parentKey) : null,
    parentB: parentBKey != null ? Hlc.fromKey(parentBKey) : null,
    type: type,
    blockOps: const [],
    fileOp: null,
    fileHash: null,
    deviceId: deviceId,
  );
}

void main() {
  group('OpLogDag', () {
    group('topology', () {
      test('empty when no entries', () {
        final dag = OpLogDag.fromEntries({});
        expect(dag.topology, DagTopology.empty);
      });

      test('single when one head', () {
        final e1 = _entry(hlcKey: '100-0000-dev1');
        final e2 = _entry(hlcKey: '200-0000-dev1', parentKey: '100-0000-dev1');
        final dag = OpLogDag.fromEntries({
          'dev1': [e1, e2],
        });
        expect(dag.topology, DagTopology.single);
        expect(dag.heads.length, 1);
      });

      test('single when multi-device linear chain', () {
        final e1 = _entry(hlcKey: '100-0000-dev1', deviceId: 'dev1');
        final e2 = _entry(
          hlcKey: '200-0000-dev1',
          parentKey: '100-0000-dev1',
          deviceId: 'dev1',
        );
        final e3 = _entry(
          hlcKey: '300-0000-dev2',
          parentKey: '200-0000-dev1',
          deviceId: 'dev2',
        );
        final dag = OpLogDag.fromEntries({
          'dev1': [e1, e2],
          'dev2': [e3],
        });
        expect(dag.topology, DagTopology.single);
      });

      test('diverged when heads are not ancestor of each other', () {
        final e1 = _entry(hlcKey: '100-0000-dev1', deviceId: 'dev1');
        final e2 = _entry(
          hlcKey: '200-0000-dev1',
          parentKey: '100-0000-dev1',
          deviceId: 'dev1',
        );
        final e3 = _entry(
          hlcKey: '200-0000-dev2',
          parentKey: '100-0000-dev1',
          deviceId: 'dev2',
        );
        final dag = OpLogDag.fromEntries({
          'dev1': [e1, e2],
          'dev2': [e3],
        });
        expect(dag.topology, DagTopology.diverged);
      });
    });

    group('entries and heads', () {
      test('entriesByHlc contains all entries', () {
        final e1 = _entry(hlcKey: '100-0000-dev1');
        final e2 = _entry(hlcKey: '200-0000-dev1', parentKey: '100-0000-dev1');
        final dag = OpLogDag.fromEntries({
          'dev1': [e1, e2],
        });

        expect(dag.entriesByHlc.length, 2);
        expect(dag.entriesByHlc['100-0000-dev1'], e1);
        expect(dag.entriesByHlc['200-0000-dev1'], e2);
      });

      test('sortedEntries returns entries in HLC order', () {
        final e1 = _entry(hlcKey: '100-0000-dev1');
        final e2 = _entry(hlcKey: '200-0000-dev1', parentKey: '100-0000-dev1');
        final e3 = _entry(hlcKey: '300-0000-dev1', parentKey: '200-0000-dev1');
        final dag = OpLogDag.fromEntries({
          'dev1': [e3, e1, e2],
        });

        final sorted = dag.sortedEntries;
        expect(sorted[0].hlc, e1.hlc);
        expect(sorted[1].hlc, e2.hlc);
        expect(sorted[2].hlc, e3.hlc);
      });

      test('heads are entries with no children', () {
        final e1 = _entry(hlcKey: '100-0000-dev1', deviceId: 'dev1');
        final e2 = _entry(
          hlcKey: '200-0000-dev1',
          parentKey: '100-0000-dev1',
          deviceId: 'dev1',
        );
        final dag = OpLogDag.fromEntries({
          'dev1': [e1, e2],
        });

        expect(dag.heads.length, 1);
        expect(dag.heads['dev1'], e2);
      });

      test('duplicate hlcKey entries are deduplicated', () {
        final e1 = _entry(hlcKey: '100-0000-dev1');
        final dag = OpLogDag.fromEntries({
          'dev1': [e1, e1],
        });
        expect(dag.entriesByHlc.length, 1);
      });
    });

    group('childrenOf', () {
      test('returns children via parent', () {
        final e1 = _entry(hlcKey: '100-0000-dev1');
        final e2 = _entry(hlcKey: '200-0000-dev1', parentKey: '100-0000-dev1');
        final dag = OpLogDag.fromEntries({
          'dev1': [e1, e2],
        });

        final children = dag.childrenOf(e1);
        expect(children, hasLength(1));
        expect(children.first, e2);
      });

      test('returns children via parentB', () {
        final e1 = _entry(hlcKey: '100-0000-dev1');
        final e2 = _entry(hlcKey: '100-0000-dev2', deviceId: 'dev2');
        final e3 = _entry(
          hlcKey: '300-0000-dev1',
          parentKey: '100-0000-dev1',
          parentBKey: '100-0000-dev2',
        );
        final dag = OpLogDag.fromEntries({
          'dev1': [e1, e3],
          'dev2': [e2],
        });

        expect(dag.childrenOf(e1), contains(e3));
        expect(dag.childrenOf(e2), contains(e3));
      });

      test('returns empty for head', () {
        final e1 = _entry(hlcKey: '100-0000-dev1');
        final dag = OpLogDag.fromEntries({
          'dev1': [e1],
        });
        expect(dag.childrenOf(e1), isEmpty);
      });
    });

    group('lca', () {
      test('same entry returns itself', () {
        final e1 = _entry(hlcKey: '100-0000-dev1');
        final dag = OpLogDag.fromEntries({
          'dev1': [e1],
        });
        expect(dag.lca(e1, e1), e1);
      });

      test('simple linear chain', () {
        final e1 = _entry(hlcKey: '100-0000-dev1');
        final e2 = _entry(hlcKey: '200-0000-dev1', parentKey: '100-0000-dev1');
        final e3 = _entry(hlcKey: '300-0000-dev1', parentKey: '200-0000-dev1');
        final dag = OpLogDag.fromEntries({
          'dev1': [e1, e2, e3],
        });

        final result = dag.lca(e2, e3);
        expect(result, e2);
      });

      test('diverged with common ancestor', () {
        final e1 = _entry(hlcKey: '100-0000-dev1');
        final e2 = _entry(
          hlcKey: '200-0000-dev1',
          parentKey: '100-0000-dev1',
          deviceId: 'dev1',
        );
        final e3 = _entry(
          hlcKey: '200-0000-dev2',
          parentKey: '100-0000-dev1',
          deviceId: 'dev2',
        );
        final dag = OpLogDag.fromEntries({
          'dev1': [e1, e2],
          'dev2': [e3],
        });

        final result = dag.lca(e2, e3);
        expect(result, e1);
      });

      test('merge node has lca through parentB', () {
        final e1 = _entry(hlcKey: '100-0000-dev1', deviceId: 'dev1');
        final e2 = _entry(
          hlcKey: '200-0000-dev1',
          parentKey: '100-0000-dev1',
          deviceId: 'dev1',
        );
        final e3 = _entry(
          hlcKey: '200-0000-dev2',
          parentKey: '100-0000-dev1',
          deviceId: 'dev2',
        );
        final e4 = _entry(
          hlcKey: '300-0000-dev1',
          parentKey: '200-0000-dev1',
          parentBKey: '200-0000-dev2',
          deviceId: 'dev1',
        );
        final dag = OpLogDag.fromEntries({
          'dev1': [e1, e2, e4],
          'dev2': [e3],
        });

        expect(dag.lca(e4, e3), e3);
      });
    });

    group('pathFrom', () {
      test('returns entries from ancestor to head', () {
        final e1 = _entry(hlcKey: '100-0000-dev1');
        final e2 = _entry(hlcKey: '200-0000-dev1', parentKey: '100-0000-dev1');
        final e3 = _entry(hlcKey: '300-0000-dev1', parentKey: '200-0000-dev1');
        final dag = OpLogDag.fromEntries({
          'dev1': [e1, e2, e3],
        });

        final path = dag.pathFrom(e1, e3);
        expect(path, hasLength(2));
        expect(path[0], e2);
        expect(path[1], e3);
      });

      test('returns empty when ancestor not reachable', () {
        final e1 = _entry(hlcKey: '100-0000-dev1');
        final e2 = _entry(hlcKey: '200-0000-dev2', deviceId: 'dev2');
        final dag = OpLogDag.fromEntries({
          'dev1': [e1],
          'dev2': [e2],
        });

        final path = dag.pathFrom(e1, e2);
        expect(path, isEmpty);
      });

      test('same entry returns empty path', () {
        final e1 = _entry(hlcKey: '100-0000-dev1');
        final dag = OpLogDag.fromEntries({
          'dev1': [e1],
        });

        final path = dag.pathFrom(e1, e1);
        expect(path, isEmpty);
      });
    });
  });
}
