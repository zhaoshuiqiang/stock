import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Better Loop F4: encoding guard for source files.
///
/// On Windows, editors that save with the ANSI code page (GBK) silently corrupt
/// Chinese characters in UTF-8 Dart sources; the corruption surfaces as the
/// U+FFFD replacement character or as invalid UTF-8 byte sequences and has
/// repeatedly broken the build (see the fix_encoding*.py scripts). This test
/// scans every lib/**/*.dart file and fails fast, listing the offenders, so the
/// corruption is caught before packaging instead of at compile time.
void main() {
  test('no lib/**/*.dart file contains U+FFFD or invalid UTF-8', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue,
        reason: 'must run from the mobile/ package root');

    final offenders = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final bytes = entity.readAsBytesSync();
      try {
        // Strict decode: throws FormatException on malformed UTF-8.
        final content = utf8.decode(bytes);
        if (content.contains('\uFFFD')) {
          offenders.add('${entity.path} (U+FFFD replacement char)');
        }
      } on FormatException {
        offenders.add('${entity.path} (invalid UTF-8 / likely GBK-corrupted)');
      }
    }

    expect(offenders, isEmpty,
        reason: 'Encoding corruption detected in:\n${offenders.join('\n')}');
  });
}
