# Selection Rendering — Implementation Notes

## Data flow

```
UserActionService
  └─ document.selection (ValueNotifier<SelectionState>)
       │
       ├─► document.selectedBlockIds (ValueListenable<Set<String>>)
       │     derived via combineLatest(selection, rootBlocks)
       │     recomputes on selection change OR tree structure change
       │
       └─► DocumentEditorBlockWidget (StatefulWidget)
             two subscriptions (see below)
               └─► TextBlockWidget (LeafRenderObjectWidget)
                     └─► RenderTextBlockContent (RenderBox)
```

## DocumentModel — derived notifier

`selectedBlockIds` is built with `combineLatest`:

```dart
late final ValueListenable<Set<String>> selectedBlockIds =
    selection.combineLatest<List<Block>, Set<String>>(
      rootBlocks,
      (selState, _) => _computeSelectedIds(selState),
    );
```

`_computeSelectedIds` does a depth-first walk of `rootBlocks` to find the
ordered flat list of all block IDs, then returns the slice from `from.blockId`
to `to.blockId` inclusive as a `Set<String>`.

## DocumentEditorBlockWidget — two subscriptions

| Listener | Source | When fires | Action |
|---|---|---|---|
| `_onSelectedBlockIdsChanged` | `selectedBlockIds` | Block enters or leaves selection | `setState` only if `_isSelected` flipped |
| `_onSelectionChanged` | `selection` | Every selection change | `setState` only if `_isSelected == true && stillSelected` |

The second subscription handles cursor movement **within the same block**: in
that case `selectedBlockIds` does not change, so only `_onSelectionChanged`
triggers the rebuild.

The guard `_isSelected && stillSelected` prevents redundant rebuilds for the
~10 000 unselected blocks when selection moves to a different block.

## BlockSelectionInfo — view-layer type

Lives in `DocumentView/`, not `DocumentSystem/`. Describes what to draw in a
specific block, computed in `_computeBlockSelectionInfo` during `build()`.

| Type | Condition |
|---|---|
| `BlockNotSelected` | block not in `selectedBlockIds` |
| `BlockWithCursor` | collapsed cursor in this block, or one range edge here |
| `BlockWithRange` | both `from` and `to` in this block |
| `BlockFullySelected` | block is between two cursors, neither endpoint here |

All subclasses implement `==` / `hashCode` so the setter on `RenderTextBlockContent`
can skip `markNeedsPaint()` when the value did not actually change.

## RenderTextBlockContent — paint and selectionInfo setter

`selectionInfo` is a getter/setter pair:

```dart
set selectionInfo(BlockSelectionInfo value) {
  if (_selectionInfo == value) return;   // equality via operator==
  _selectionInfo = value;
  _updateCursorBlink();
  markNeedsPaint();
}
```

`markNeedsLayout()` is never called from selection changes — only text segment
changes trigger re-layout. Selection only triggers `markNeedsPaint()`.

Paint order: text first, then selection overlay (highlight boxes, then cursor).

Cursor position uses `TextPainter.getOffsetForCaret` + `getFullHeightForCaret`
so height matches the line at the caret position, not the entire block height.

## Cursor blink animation

Active only for `BlockWithCursor` (collapsed). All other states: no timer,
cursor drawn solid or not drawn at all.

```
selectionInfo set to BlockWithCursor
  └─ _startBlink()
       _cursorVisible = true          ← immediately visible
       Timer.periodic(500ms)
         _cursorVisible = !_cursorVisible
         if (attached) markNeedsPaint()
```

`attached` guard prevents calling `markNeedsPaint()` after the render object
has been detached from the tree (e.g. block scrolled out of view).

On every click inside the same block `selectionInfo` changes (new
`BlockWithCursor` with different coords → `operator==` returns false) →
setter fires → `_startBlink()` restarts the timer → cursor appears immediately
and blink phase resets.

Transition to `BlockNotSelected` / `BlockFullySelected` / `BlockWithRange`:
`_stopBlink()` cancels the timer and sets `_cursorVisible = true` so the
cursor is visible immediately if it reappears.
