import 'package:flutter_test/flutter_test.dart';
import 'package:noetec/service/page_file_name_sanitizer.dart';

void main() {
  group('PageFileNameSanitizer —', () {
    void expectSanitized(String raw, String expected) {
      expect(PageFileNameSanitizer.sanitize(raw), expected);
    }

    test('keeps plain names untouched', () {
      expectSanitized('hello', 'hello');
    });

    test('keeps spaces', () {
      expectSanitized('my page', 'my page');
    });

    test('keeps an explicit .md extension', () {
      expectSanitized('todo.md', 'todo.md');
    });

    test('replaces forward slash with a dash', () {
      expectSanitized('a/b', 'a-b');
    });

    test('replaces colon with a dash', () {
      expectSanitized('a:b', 'a-b');
    });

    test('replaces backslash with a dash', () {
      expectSanitized(r'a\b', 'a-b');
    });

    test('replaces question mark and asterisk', () {
      expectSanitized('a?b*', 'a-b');
    });

    test('replaces angle brackets and pipe', () {
      expectSanitized('<a|b>', 'a-b');
    });

    test('collapses repeated slashes into a single dash', () {
      expectSanitized('a///b', 'a-b');
    });

    test('collapses runs of dashes into a single dash', () {
      expectSanitized('a---b', 'a-b');
    });

    test('trims surrounding whitespace', () {
      expectSanitized('  hello  ', 'hello');
    });

    test('replaces control characters with a dash', () {
      expectSanitized('a\nb', 'a-b');
    });

    test('strips dashes produced at the edges', () {
      expectSanitized('/hello/', 'hello');
    });

    test('throws on an empty name', () {
      expect(
        () => PageFileNameSanitizer.sanitize(''),
        throwsA(isA<PageNameInvalidException>()),
      );
    });

    test('throws on whitespace-only input', () {
      expect(
        () => PageFileNameSanitizer.sanitize('   '),
        throwsA(isA<PageNameInvalidException>()),
      );
    });

    test('throws on separator-only input', () {
      expect(
        () => PageFileNameSanitizer.sanitize('///'),
        throwsA(isA<PageNameInvalidException>()),
      );
    });

    test('throws on a single dot', () {
      expect(
        () => PageFileNameSanitizer.sanitize('.'),
        throwsA(isA<PageNameInvalidException>()),
      );
    });

    test('throws on a double dot', () {
      expect(
        () => PageFileNameSanitizer.sanitize('..'),
        throwsA(isA<PageNameInvalidException>()),
      );
    });
  });
}
