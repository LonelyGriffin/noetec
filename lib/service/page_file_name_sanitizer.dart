// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

/// Thrown when a page name is invalid even after sanitization
/// (empty result, `.` or `..`).
class PageNameInvalidException implements Exception {
  const PageNameInvalidException(this.rawName);

  /// The user-supplied name that was rejected.
  final String rawName;

  @override
  String toString() => 'PageNameInvalidException: invalid page name "$rawName"';
}

/// Sanitizes user-supplied page names into a file-name-safe form.
class PageFileNameSanitizer {
  PageFileNameSanitizer._();

  static final RegExp _invalidChars = RegExp(r'[\\/:*?"<>|\x00-\x1f]');
  static final RegExp _dashRuns = RegExp(r'-{2,}');
  static final RegExp _edgeDashes = RegExp(r'^-+|-+$');

  /// Converts [raw] into a valid page file name.
  ///
  /// Steps, applied in order:
  /// 1. trim surrounding whitespace;
  /// 2. replace every character in `[\\/:*?"<>|\x00-\x1f]` with `-`;
  /// 3. collapse runs of `-` (`-{2,}`) into a single `-`;
  /// 4. strip leading and trailing `-`.
  ///
  /// Throws [PageNameInvalidException] if the result is empty, `.` or `..`.
  static String sanitize(String raw) {
    var name = raw.trim();
    name = name.replaceAll(_invalidChars, '-');
    name = name.replaceAll(_dashRuns, '-');
    name = name.replaceAll(_edgeDashes, '');
    if (name.isEmpty || name == '.' || name == '..') {
      throw PageNameInvalidException(raw);
    }
    return name;
  }
}
