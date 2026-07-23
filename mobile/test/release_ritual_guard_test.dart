import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/core/app_version.dart';

/// Better Loop consolidated release-ritual guard.
///
/// Single, executable, reviewable owner for the high-frequency rituals that used
/// to live only as AGENTS.md prose. It replaces the two earlier standalone
/// guards (version_consistency_test.dart / source_encoding_guard_test.dart) and
/// turns those rituals into a mechanical clean/gap gate on every `flutter test`:
///
///   1. Version ritual  - pubspec.yaml / app_version.dart / update_log_screen.dart
///                        must declare the same version (the "3 files must update
///                        together" release ritual).
///   2. Encoding safety - no lib/**/*.dart may contain U+FFFD or invalid UTF-8
///                        (Windows GBK corruption has repeatedly broken the build;
///                        see the fix_encoding*.py scripts).
///   3. Freshness       - AGENTS.md must still document both rituals AND reference
///                        this guard, so the prose and the executable owner cannot
///                        silently drift apart.
///
/// Runs from the package root (mobile/) under `flutter test`.
void main() {
  // Resolve the repo-root AGENTS.md from either the package root (mobile/) or the
  // repository root, so the freshness check is robust to the test cwd.
  File? locateAgentsMd() {
    for (final candidate in const ['../AGENTS.md', 'AGENTS.md']) {
      final file = File(candidate);
      if (file.existsSync()) return file;
    }
    return null;
  }

  group('Release ritual guards (Better Loop consolidated owner)', () {
    test('version ritual: pubspec / app_version / update_log agree', () {
      // 1. pubspec.yaml -> `version: X.Y.Z`
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final pubMatch =
          RegExp(r'^version:\s*(.+)$', multiLine: true).firstMatch(pubspec);
      expect(pubMatch, isNotNull, reason: 'version: not found in pubspec.yaml');
      final pubspecVersion = pubMatch!.group(1)!.trim();

      // 2. app_version.dart constant
      final appVersion = AppVersion.version;

      // 3. update_log_screen.dart latest entry (first `'version': 'vX.Y.Z'`)
      final log = File('lib/screens/update_log_screen.dart').readAsStringSync();
      final logMatch = RegExp(r"'version':\s*'v?([^']+)'").firstMatch(log);
      expect(logMatch, isNotNull,
          reason: 'no version entry found in update_log_screen.dart');
      final latestLogVersion = logMatch!.group(1)!.trim();

      expect(appVersion, pubspecVersion,
          reason:
              'app_version.dart ($appVersion) != pubspec.yaml ($pubspecVersion)');
      expect(latestLogVersion, pubspecVersion,
          reason:
              'update_log latest ($latestLogVersion) != pubspec.yaml ($pubspecVersion)');
    });

    test('encoding safety: no lib/**/*.dart is GBK-corrupted', () {
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
          offenders
              .add('${entity.path} (invalid UTF-8 / likely GBK-corrupted)');
        }
      }

      expect(offenders, isEmpty,
          reason: 'Encoding corruption detected in:\n${offenders.join('\n')}');
    });

    test('freshness: AGENTS.md still documents both rituals and routes here',
        () {
      final agents = locateAgentsMd();
      expect(agents, isNotNull,
          reason: 'AGENTS.md not found from the test cwd; the release-ritual '
              'documentation that routes to this guard is missing.');
      final doc = agents!.readAsStringSync();
      final lower = doc.toLowerCase();

      // (a) Version ritual is still documented and names all three files.
      expect(doc, contains('3 files must update together'),
          reason: 'AGENTS.md no longer documents the 3-file version ritual.');
      for (final f in const [
        'pubspec.yaml',
        'app_version.dart',
        'update_log_screen.dart',
      ]) {
        expect(doc, contains(f),
            reason: 'AGENTS.md version ritual no longer names $f.');
      }

      // (b) Encoding rule is still documented.
      expect(lower, contains('encoding'),
          reason: 'AGENTS.md no longer documents the file-encoding rule.');
      expect(doc, contains('UTF-8'),
          reason: 'AGENTS.md no longer documents the UTF-8 encoding rule.');

      // (c) The prose routes to THIS executable owner (prose <-> owner link).
      expect(doc, contains('release_ritual_guard_test.dart'),
          reason: 'AGENTS.md does not reference this guard, so the documented '
              'rituals are not routed to their executable owner. Add a '
              'reference to mobile/test/release_ritual_guard_test.dart.');
    });
  });
}
