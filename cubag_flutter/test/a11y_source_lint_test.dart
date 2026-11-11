// UI-02 / UI-03 regression guard: scans lib/ source.
//  - Every IconButton needs a tooltip (it is also the screen-reader label).
//  - The low-contrast greys removed in UI-02 must not come back.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Not routed; excluded until deleted (see audit INC-02).
const _skip = {'landing_page.dart', 'public_home_page.dart'};

Iterable<File> _dartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => !_skip.contains(f.uri.pathSegments.last));

/// Index of the ')' that closes the '(' at [open].
int _close(String src, int open) {
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '(') depth++;
    if (src[i] == ')' && --depth == 0) return i;
  }
  return src.length - 1;
}

void main() {
  test('every IconButton has a tooltip', () {
    final missing = <String>[];
    final call = RegExp(r'\bIconButton(\.(?!styleFrom)\w+)?\s*\(');
    for (final f in _dartFiles()) {
      final src = f.readAsStringSync();
      for (final m in call.allMatches(src)) {
        final open = src.indexOf('(', m.start);
        final body = src.substring(open, _close(src, open));
        if (!RegExp(r'\btooltip\s*:').hasMatch(body)) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          missing.add('${f.path}:$line');
        }
      }
    }
    expect(missing, isEmpty, reason: 'IconButton without tooltip');
  });

  test('low-contrast text greys are not used', () {
    final bad = RegExp(r'0x[Ff]{2}(94[Aa]3[Bb]8|9[Cc][Aa]3[Aa][Ff])');
    final hits = [
      for (final f in _dartFiles())
        if (bad.hasMatch(f.readAsStringSync())) f.path,
    ];
    expect(hits, isEmpty, reason: 'use AppColors.textMuted (#5F6B7E)');
  });
}
