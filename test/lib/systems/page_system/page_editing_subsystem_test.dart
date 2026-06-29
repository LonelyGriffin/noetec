// ignore: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/entity/page/block/text/text.dart';
import 'package:noetec/entity/page/block/text/text_segment.dart';
import 'package:noetec/entity/page/selection.dart';
import 'package:noetec/service/file_system_service.dart';
import 'package:noetec/service/id_service.dart';
import 'package:noetec/systems/markdown_system/markdown_system.dart';
import 'package:noetec/systems/page_system/page_system.dart';
import 'package:noetec/systems/vault/vault_system.dart';

import '../../../helpers/test_fakes.dart';

class _FakeIdService implements IIdService {
  int _counter = 0;
  @override
  String generateId() => 'gen-${_counter++}';
}

class _FakeFileSystemService implements IFileSystemService {
  @override
  Future<bool> directoryExists(String path) async => false;
  @override
  Future<void> createDirectory(String path) async {}
  @override
  Future<String> readFile(String path) async => '';
  @override
  Future<void> writeFile(String path, String content) async {}
  @override
  Future<bool> fileExists(String path) async => false;
  @override
  Future<String?> pickDirectory() async => null;
  @override
  Future<List<FileEntry>> listDirectory(String path) async => [];
  @override
  Future<void> deleteFile(String path) async {}
  @override
  Future<void> renameFileOrDirectory(String oldPath, String newPath) async {}
  @override
  Stream<FileEntry> watchDirectory(
    String path, {
    Duration pollInterval = const Duration(seconds: 5),
  }) => const Stream.empty();
  @override
  Future<void> appendToFile(String path, String content) async {}
}

void main() {
  late PageSystem pageSystem;
  late VaultSystem vaultSystem;

  setUp(() {
    vaultSystem = createTestVaultSystem();
    pageSystem = PageSystem(
      _FakeIdService(),
      MarkdownSystem(_FakeIdService()),
      _FakeFileSystemService(),
      vaultSystem,
    );
    pageSystem.openPage('page-1');
  });

  tearDown(() {
    pageSystem.dispose();
    vaultSystem.dispose();
  });

  void addTextBlock(String id, String text) {
    final block = TextBlockEntity(
      id: id,
      segments: [TextSegment(text: text)],
    );
    final page = pageSystem.getActivePage()!;
    page.addBlock(
      block,
      page.rootBlocks.isNotEmpty ? page.rootBlocks.last.id : null,
    );
    page.blocks[id] = block;
  }

  void setCursor(String blockId, int segmentIndex, int offset) {
    pageSystem.getActivePage()!.selection.value = SingleCursorSelectionEntity(
      cursorPos: CursorPositionInTextBlock(
        blockId: blockId,
        segmentIndex: segmentIndex,
        offset: offset,
      ),
    );
  }

  group('PageEditingSubsystem —', () {
    group('insertText —', () {
      test('inserts text at cursor position', () {
        addTextBlock('b1', 'hello');
        setCursor('b1', 0, 5);

        pageSystem.editing.insertText(5, ' world');

        final block =
            pageSystem.getActivePage()!.getBlockById('b1') as TextBlockEntity;
        expect(block.computeAllSegmentsText(), 'hello world');
      });

      test('updates cursor after insertion', () {
        addTextBlock('b1', 'ab');
        setCursor('b1', 0, 1);

        pageSystem.editing.insertText(1, 'X');

        final selection = pageSystem.getActivePage()!.selection.value;
        expect(selection, isA<SingleCursorSelectionEntity>());
        final cursor =
            (selection as SingleCursorSelectionEntity).cursorPos
                as CursorPositionInTextBlock;
        expect(cursor.offset, 2);
      });

      test('does nothing without active page', () {
        pageSystem.closePage('page-1');
        pageSystem.editing.insertText(0, 'x');
      });
    });

    group('deleteTextBack —', () {
      test('deletes character before cursor', () {
        addTextBlock('b1', 'abc');
        setCursor('b1', 0, 2);

        pageSystem.editing.deleteTextBack(2);

        final block =
            pageSystem.getActivePage()!.getBlockById('b1') as TextBlockEntity;
        expect(block.computeAllSegmentsText(), 'ac');
      });

      test('does nothing at start of first block', () {
        addTextBlock('b1', 'abc');
        setCursor('b1', 0, 0);

        pageSystem.editing.deleteTextBack(0);

        final block =
            pageSystem.getActivePage()!.getBlockById('b1') as TextBlockEntity;
        expect(block.computeAllSegmentsText(), 'abc');
      });
    });

    group('deleteTextForward —', () {
      test('deletes character after cursor', () {
        addTextBlock('b1', 'abc');
        setCursor('b1', 0, 1);

        pageSystem.editing.deleteTextForward(1);

        final block =
            pageSystem.getActivePage()!.getBlockById('b1') as TextBlockEntity;
        expect(block.computeAllSegmentsText(), 'ac');
      });

      test('does nothing at end of last block', () {
        addTextBlock('b1', 'abc');
        setCursor('b1', 0, 3);

        pageSystem.editing.deleteTextForward(3);

        final block =
            pageSystem.getActivePage()!.getBlockById('b1') as TextBlockEntity;
        expect(block.computeAllSegmentsText(), 'abc');
      });
    });

    group('splitBlock —', () {
      test('splits block at offset creating new block', () {
        addTextBlock('b1', 'abcdef');
        setCursor('b1', 0, 3);

        pageSystem.editing.splitBlock(3);

        final page = pageSystem.getActivePage()!;
        expect(page.rootBlocks.length, 2);

        final first = page.getBlockById('b1') as TextBlockEntity;
        expect(first.computeAllSegmentsText(), 'abc');

        final newBlockId = page.rootBlocks.last.id;
        final second = page.getBlockById(newBlockId) as TextBlockEntity;
        expect(second.computeAllSegmentsText(), 'def');
      });

      test('moves cursor to start of new block', () {
        addTextBlock('b1', 'abcdef');
        setCursor('b1', 0, 3);

        pageSystem.editing.splitBlock(3);

        final selection = pageSystem.getActivePage()!.selection.value;
        final cursor =
            (selection as SingleCursorSelectionEntity).cursorPos
                as CursorPositionInTextBlock;
        expect(cursor.blockId, isNot('b1'));
        expect(cursor.offset, 0);
      });
    });

    group('replaceText —', () {
      test('replaces range with new text', () {
        addTextBlock('b1', 'hello world');
        setCursor('b1', 0, 5);

        pageSystem.editing.replaceText(5, 11, ' Dart');

        final block =
            pageSystem.getActivePage()!.getBlockById('b1') as TextBlockEntity;
        expect(block.computeAllSegmentsText(), 'hello Dart');
      });
    });

    group('deleteSelection —', () {
      test('deletes selected range within single block', () {
        addTextBlock('b1', 'hello world');
        final page = pageSystem.getActivePage()!;
        page.selection.value = const RangeSelectionEntity(
          anchor: CursorPositionInTextBlock(
            blockId: 'b1',
            segmentIndex: 0,
            offset: 5,
          ),
          extent: CursorPositionInTextBlock(
            blockId: 'b1',
            segmentIndex: 0,
            offset: 11,
          ),
        );

        pageSystem.editing.deleteSelection();

        final block = page.getBlockById('b1') as TextBlockEntity;
        expect(block.computeAllSegmentsText(), 'hello');
      });

      test('does nothing for single cursor selection', () {
        addTextBlock('b1', 'hello');
        setCursor('b1', 0, 3);

        pageSystem.editing.deleteSelection();

        final block =
            pageSystem.getActivePage()!.getBlockById('b1') as TextBlockEntity;
        expect(block.computeAllSegmentsText(), 'hello');
      });
    });
  });
}
