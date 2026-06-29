// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html
import '../../entity/page/page_edit_action.dart';
import 'wal_service.dart';

class RecoveryCandidate {
  const RecoveryCandidate({
    required this.relativePath,
    required this.pendingActions,
  });

  final String relativePath;
  final List<PageEditAction> pendingActions;
}

class CrashRecoveryService {
  CrashRecoveryService(WalService walService) : _wal = walService;

  final WalService _wal;

  Future<List<RecoveryCandidate>> findCandidates() async {
    final walEntries = await _wal.getPendingWals();
    if (walEntries.isEmpty) return const [];

    final candidates = <RecoveryCandidate>[];
    for (final entry in walEntries) {
      try {
        final actions = await _wal.readWal(entry.walFilePath);
        if (actions.isNotEmpty) {
          candidates.add(
            RecoveryCandidate(
              relativePath: entry.relativePath,
              pendingActions: actions,
            ),
          );
        }
      } catch (_) {}
    }
    return candidates;
  }

  Future<void> discardAll() async {
    await _wal.clearAll();
  }
}
