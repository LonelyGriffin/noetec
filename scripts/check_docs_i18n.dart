// Noetec.
// Copyright (c) 2026 The Noetec Authors.
// See the AUTHORS file for the full list of contributors.
// AGPLv3 License: https://www.gnu.org/licenses/agpl-3.0.html

// ignore_for_file: avoid_print
import 'dart:io';

const _excludedDirs = <String>{'.github', 'android', 'build', 'ios', 'linux', 'macos', 'skills', 'test', 'test_data', 'web', 'windows'};

const _enSwitcherPattern = '[**English**](%EN%) · [Русский](%RU%)';
const _ruSwitcherPattern = '[English](%EN%) · [**Русский**](%RU%)';

Future<void> main(List<String> args) async {
  if (args.contains('--help') || args.contains('-h')) {
    _printUsage();
    return;
  }

  final requireAll = args.contains('--require-all');
  final unknown = args.where((arg) => arg != '--require-all' && arg != '--help' && arg != '-h').toList();
  if (unknown.isNotEmpty) {
    print('Unknown argument(s): ${unknown.join(', ')}');
    _printUsage();
    exit(2);
  }

  final root = Directory.current;
  final files = _discoverEnglishDocs(root)..sort((a, b) => a.path.compareTo(b.path));

  var ok = 0;
  final missing = <String>[];
  final failures = <String, List<String>>{};

  for (final file in files) {
    final relative = _relativePath(file, root);
    final companion = File(file.path.replaceFirst(RegExp(r'\.md$'), '_RU.md'));

    if (!companion.existsSync()) {
      missing.add(relative);
      continue;
    }

    final problems = _checkPair(english: file, russian: companion);
    if (problems.isEmpty) {
      ok++;
      print('ok    $relative');
    } else {
      failures[relative] = problems;
      print('FAIL  $relative');
      for (final problem in problems) {
        print('        - $problem');
      }
    }
  }

  print('');
  if (missing.isNotEmpty) {
    final label = requireAll ? 'missing' : 'missing (not translated yet)';
    print('$label: ${missing.length}');
    for (final relative in missing) {
      print('  - $relative');
    }
  }
  print('summary: $ok ok, ${missing.length} missing, ${failures.length} failed, ${files.length} english documents');

  final failed = failures.isNotEmpty || (requireAll && missing.isNotEmpty);
  exit(failed ? 1 : 0);
}

void _printUsage() {
  print('''
Usage: dart run scripts/check_docs_i18n.dart [--require-all]

Checks the Russian documentation pairs of this repository: every English
document below must have a <name>_RU.md sibling with the language switcher in
both files, a matching structure, resolving relative links and resolving
in-document anchors. See docs/i18n.md for the convention.

Scope: *.md at the repository root and everything under docs/, excluding the
_RU.md files themselves and the tooling directories (.github, skills, test,
test_data, build, platform folders).

Flags:
  --require-all   fail when an English document has no Russian sibling (used
                  for the coverage gate; without it a missing pair is only
                  reported)
  --help, -h      print this message
''');
}

List<File> _discoverEnglishDocs(Directory root) {
  final result = <File>[];

  for (final entity in root.listSync(followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.md') || _isExcludedFileName(entity.path)) {
      continue;
    }
    result.add(entity);
  }

  final docs = Directory('${root.path}/docs');
  if (docs.existsSync()) {
    for (final entity in docs.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.md') || _isExcludedFileName(entity.path)) {
        continue;
      }
      result.add(entity);
    }
  }

  return result;
}

bool _isExcludedFileName(String path) {
  final name = path.split(Platform.pathSeparator).last;
  if (name.endsWith('_RU.md')) {
    return true;
  }
  return path.split(Platform.pathSeparator).any(_excludedDirs.contains);
}

List<String> _checkPair({required File english, required File russian}) {
  final problems = <String>[];
  final englishName = english.path.split(Platform.pathSeparator).last;
  final russianName = russian.path.split(Platform.pathSeparator).last;

  final englishLines = _readLines(english);
  final russianLines = _readLines(russian);
  final englishMask = _fenceMask(englishLines);
  final russianMask = _fenceMask(russianLines);

  final enSwitcher = _enSwitcherPattern.replaceAll('%EN%', englishName).replaceAll('%RU%', russianName);
  final ruSwitcher = _ruSwitcherPattern.replaceAll('%EN%', englishName).replaceAll('%RU%', russianName);

  problems.addAll(_checkSwitcher(englishLines, englishMask, expected: enSwitcher, file: englishName));
  problems.addAll(_checkSwitcher(russianLines, russianMask, expected: ruSwitcher, file: russianName));

  final englishHeadings = _countHeadings(englishLines, englishMask);
  final russianHeadings = _countHeadings(russianLines, russianMask);
  if (englishHeadings != russianHeadings) {
    problems.add('heading count differs: $englishName has $englishHeadings, $russianName has $russianHeadings');
  }

  final englishFences = englishLines.where(_isFence).length;
  final russianFences = russianLines.where(_isFence).length;
  if (englishFences != russianFences) {
    problems.add('fenced block marker count differs: $englishName has $englishFences, $russianName has $russianFences');
  }

  final ratio = englishLines.isEmpty ? 0.0 : russianLines.length / englishLines.length;
  if (ratio < 0.55 || ratio > 1.8) {
    problems.add('suspicious length ratio: $russianName is ${(ratio * 100).toStringAsFixed(0)}% of $englishName (expected 55–180%)');
  }

  problems.addAll(_checkLinks(fileName: englishName, lines: englishLines, mask: englishMask, selfDirectory: english.parent, switcherLine: enSwitcher));
  problems.addAll(_checkLinks(fileName: russianName, lines: russianLines, mask: russianMask, selfDirectory: russian.parent, switcherLine: ruSwitcher));

  return problems;
}

List<String> _checkSwitcher(List<String> lines, List<bool> mask, {required String expected, required String file}) {
  final matches = <int>[];
  for (var index = 0; index < lines.length; index++) {
    if (!mask[index] && lines[index].trim() == expected) {
      matches.add(index);
    }
  }

  if (matches.isEmpty) {
    return ['$file: language switcher line is missing or differs from "$expected"'];
  }
  if (matches.length > 1) {
    return ['$file: language switcher line appears ${matches.length} times (expected once)'];
  }

  final index = matches.single;
  final h1Index = lines.indexWhere((line) => line.startsWith('# '));
  if (h1Index < 0) {
    return ['$file: no H1 line found'];
  }
  if (index >= 10) {
    return ['$file: language switcher is on line ${index + 1} (must be within the first 10 lines)'];
  }
  if (index < h1Index) {
    return ['$file: language switcher must come after the H1 line'];
  }

  final nextHeading = _nextHeadingIndex(lines, mask, h1Index + 1);
  if (nextHeading >= 0 && nextHeading < index) {
    return ['$file: language switcher must come before the next heading'];
  }

  return const [];
}

int _nextHeadingIndex(List<String> lines, List<bool> mask, int from) {
  for (var index = from; index < lines.length; index++) {
    if (!mask[index] && _isHeading(lines[index])) {
      return index;
    }
  }
  return -1;
}

List<String> _checkLinks({required String fileName, required List<String> lines, required List<bool> mask, required Directory selfDirectory, required String switcherLine}) {
  final problems = <String>[];
  final linkPattern = RegExp(r'\]\(([^)\s]+)\)');
  final headings = <String>{};
  for (var index = 0; index < lines.length; index++) {
    if (!mask[index] && _isHeading(lines[index])) {
      headings.add(_slug(lines[index]));
    }
  }

  for (var index = 0; index < lines.length; index++) {
    if (mask[index] || lines[index].trim() == switcherLine) {
      continue;
    }

    for (final match in linkPattern.allMatches(lines[index])) {
      final target = match.group(1)!;

      if (target.startsWith('#')) {
        if (!headings.contains(target.substring(1).toLowerCase())) {
          problems.add('$fileName: anchor "$target" does not match any heading in the file');
        }
        continue;
      }

      if (target.startsWith('http://') || target.startsWith('https://') || target.startsWith('mailto:')) {
        continue;
      }

      if (!target.endsWith('.md')) {
        continue;
      }

      final path = target.split('#').first;
      if (!File('${selfDirectory.path}/$path').existsSync()) {
        problems.add('$fileName: relative link "$target" does not resolve on disk');
        continue;
      }

      if (fileName.endsWith('_RU.md') && !path.endsWith('_RU.md')) {
        problems.add('$fileName: relative document link "$target" must point at the _RU translation');
      }
    }
  }

  return problems;
}

List<bool> _fenceMask(List<String> lines) {
  final mask = <bool>[];
  var inside = false;
  for (final line in lines) {
    if (_isFence(line)) {
      mask.add(true);
      inside = !inside;
      continue;
    }
    mask.add(inside);
  }
  return mask;
}

int _countHeadings(List<String> lines, List<bool> mask) {
  var count = 0;
  for (var index = 0; index < lines.length; index++) {
    if (!mask[index] && _isHeading(lines[index])) {
      count++;
    }
  }
  return count;
}

bool _isHeading(String line) => RegExp(r'^#{1,6} ').hasMatch(line);

bool _isFence(String line) {
  final trimmed = line.trimLeft();
  return trimmed.startsWith('```') || trimmed.startsWith('~~~');
}

String _slug(String heading) {
  var text = heading.replaceFirst(RegExp(r'^#{1,6} '), '').trim().toLowerCase();
  text = text.replaceAll(RegExp(r'[^a-z0-9\u0400-\u04FF\s_-]'), '');
  text = text.replaceAll(RegExp(r'\s+'), '-');
  return text;
}

List<String> _readLines(File file) => file.readAsLinesSync();

String _relativePath(File file, Directory root) {
  final prefix = root.path.endsWith(Platform.pathSeparator) ? root.path : '${root.path}${Platform.pathSeparator}';
  return file.path.startsWith(prefix) ? file.path.substring(prefix.length) : file.path;
}
