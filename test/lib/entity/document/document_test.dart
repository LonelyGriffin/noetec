// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/page/block/block.dart';
import 'package:noetec/entity/page/page.dart';

class MutableBlock extends BlockEntity {
  MutableBlock({required super.id, super.parentId, List<BlockEntity>? children})
    : super(children: children ?? []);
}

void main() {
  group('DocumentEntity.addBlock', () {
    test('adds root block at beginning when afterBlockId is null', () {
      final doc = PageEntity(id: 'doc');
      final block = MutableBlock(id: 'b1');

      doc.addBlock(block, null);

      expect(doc.rootBlocks, [block]);
      expect(doc.blocks['b1'], block);
    });

    test('adds root block after specified block', () {
      final doc = PageEntity(id: 'doc');
      final b1 = MutableBlock(id: 'b1');
      final b2 = MutableBlock(id: 'b2');

      doc.addBlock(b1, null);
      doc.addBlock(b2, 'b1');

      expect(doc.rootBlocks, [b1, b2]);
    });

    test('adds root block at end when afterBlockId not found in root', () {
      final doc = PageEntity(id: 'doc');
      final b1 = MutableBlock(id: 'b1');

      doc.addBlock(b1, 'nonexistent');

      expect(doc.rootBlocks, [b1]);
    });

    test('adds child block at beginning when afterBlockId is null', () {
      final doc = PageEntity(id: 'doc');
      final parent = MutableBlock(id: 'parent');
      final child = MutableBlock(id: 'child', parentId: 'parent');

      doc.addBlock(parent, null);
      doc.addBlock(child, null);

      expect(parent.children, [child]);
      expect(doc.blocks['child'], child);
    });

    test('adds child block after specified sibling', () {
      final doc = PageEntity(id: 'doc');
      final parent = MutableBlock(id: 'parent');
      final c1 = MutableBlock(id: 'c1', parentId: 'parent');
      final c2 = MutableBlock(id: 'c2', parentId: 'parent');

      doc.addBlock(parent, null);
      doc.addBlock(c1, null);
      doc.addBlock(c2, 'c1');

      expect(parent.children, [c1, c2]);
    });

    test('adds child at end when afterBlockId not found in siblings', () {
      final doc = PageEntity(id: 'doc');
      final parent = MutableBlock(id: 'parent');
      final child = MutableBlock(id: 'child', parentId: 'parent');

      doc.addBlock(parent, null);
      doc.addBlock(child, 'nonexistent');

      expect(parent.children, [child]);
    });

    test('throws when parent block does not exist', () {
      final doc = PageEntity(id: 'doc');
      final child = MutableBlock(id: 'child', parentId: 'missing');

      expect(() => doc.addBlock(child, null), throwsA(isA<ArgumentError>()));
      expect(doc.blocks, isEmpty);
    });

    test('adds first root block then inserts before it', () {
      final doc = PageEntity(id: 'doc');
      final b1 = MutableBlock(id: 'b1');
      final b2 = MutableBlock(id: 'b2');

      doc.addBlock(b1, null);
      doc.addBlock(b2, null);

      expect(doc.rootBlocks, [b2, b1]);
    });
  });

  group('DocumentEntity.removeBlock', () {
    test('removes root block from document', () {
      final doc = PageEntity(id: 'doc');
      final block = MutableBlock(id: 'b1');

      doc.addBlock(block, null);
      doc.removeBlock('b1');

      expect(doc.rootBlocks, isEmpty);
      expect(doc.blocks, isEmpty);
    });

    test('does nothing when block id does not exist', () {
      final doc = PageEntity(id: 'doc');

      doc.removeBlock('nonexistent');

      expect(doc.rootBlocks, isEmpty);
      expect(doc.blocks, isEmpty);
    });

    test('removes child block from parent', () {
      final doc = PageEntity(id: 'doc');
      final parent = MutableBlock(id: 'parent');
      final child = MutableBlock(id: 'child', parentId: 'parent');

      doc.addBlock(parent, null);
      doc.addBlock(child, null);
      doc.removeBlock('child');

      expect(parent.children, isEmpty);
      expect(doc.blocks['child'], isNull);
      expect(doc.blocks['parent'], isNotNull);
    });

    test('recursively removes block and all descendants', () {
      final doc = PageEntity(id: 'doc');
      final parent = MutableBlock(id: 'parent');
      final child1 = MutableBlock(id: 'c1', parentId: 'parent');
      final child2 = MutableBlock(id: 'c2', parentId: 'parent');
      final grandchild = MutableBlock(id: 'gc', parentId: 'parent');

      doc.addBlock(parent, null);
      doc.addBlock(child1, null);
      doc.addBlock(child2, null);
      (parent.children as List).add(grandchild);
      doc.blocks['gc'] = grandchild;

      doc.removeBlock('parent');

      expect(doc.rootBlocks, isEmpty);
      expect(doc.blocks, isEmpty);
    });

    test('removes only target block and its children, not siblings', () {
      final doc = PageEntity(id: 'doc');
      final parent = MutableBlock(id: 'parent');
      final c1 = MutableBlock(id: 'c1', parentId: 'parent');
      final c2 = MutableBlock(id: 'c2', parentId: 'parent');

      doc.addBlock(parent, null);
      doc.addBlock(c1, null);
      doc.addBlock(c2, null);
      doc.removeBlock('c1');

      expect(parent.children, [c2]);
      expect(doc.blocks['c1'], isNull);
      expect(doc.blocks['c2'], isNotNull);
    });

    test('removes nested grandchild correctly', () {
      final doc = PageEntity(id: 'doc');
      final parent = MutableBlock(id: 'parent');
      final child = MutableBlock(id: 'child', parentId: 'parent');
      final grandchild = MutableBlock(id: 'gc', parentId: 'parent');

      doc.addBlock(parent, null);
      doc.addBlock(child, null);
      (child.children as List).add(grandchild);
      doc.blocks['gc'] = grandchild;

      doc.removeBlock('child');

      expect(doc.blocks['child'], isNull);
      expect(doc.blocks['gc'], isNull);
      expect(doc.blocks['parent'], isNotNull);
      expect(parent.children, isEmpty);
    });
  });

  group('DocumentEntity.flatBlockIds', () {
    test('returns empty list for empty document', () {
      final doc = PageEntity(id: 'doc');

      final ids = doc.flatBlockIds();

      expect(ids, isEmpty);
    });

    test('returns ids of root blocks in order', () {
      final doc = PageEntity(id: 'doc');
      final b1 = MutableBlock(id: 'b1');
      final b2 = MutableBlock(id: 'b2');
      final b3 = MutableBlock(id: 'b3');

      doc.addBlock(b1, null);
      doc.addBlock(b2, 'b1');
      doc.addBlock(b3, 'b2');

      final ids = doc.flatBlockIds();

      expect(ids, ['b1', 'b2', 'b3']);
    });

    test('returns depth-first order with children', () {
      final doc = PageEntity(id: 'doc');
      final parent = MutableBlock(id: 'parent');
      final c1 = MutableBlock(id: 'c1', parentId: 'parent');
      final c2 = MutableBlock(id: 'c2', parentId: 'parent');

      doc.addBlock(parent, null);
      doc.addBlock(c1, null);
      doc.addBlock(c2, 'c1');

      final ids = doc.flatBlockIds();

      expect(ids, ['parent', 'c1', 'c2']);
    });

    test('handles deeply nested tree in depth-first order', () {
      final doc = PageEntity(id: 'doc');
      final root = MutableBlock(id: 'root');
      final child = MutableBlock(id: 'child', parentId: 'root');
      final grandchild = MutableBlock(id: 'gc', parentId: 'root');

      doc.addBlock(root, null);
      doc.addBlock(child, null);
      (child.children as List).add(grandchild);
      doc.blocks['gc'] = grandchild;

      final ids = doc.flatBlockIds();

      expect(ids, ['root', 'child', 'gc']);
    });

    test('returns correct order for multiple root blocks with children', () {
      final doc = PageEntity(id: 'doc');
      final p1 = MutableBlock(id: 'p1');
      final p2 = MutableBlock(id: 'p2');
      final c1 = MutableBlock(id: 'c1', parentId: 'p1');
      final c2 = MutableBlock(id: 'c2', parentId: 'p2');

      doc.addBlock(p1, null);
      doc.addBlock(p2, 'p1');
      doc.addBlock(c1, null);
      doc.addBlock(c2, null);

      final ids = doc.flatBlockIds();

      expect(ids, ['p1', 'c1', 'p2', 'c2']);
    });
  });
}
