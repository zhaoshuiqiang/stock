import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/core/app_version.dart';

/// Better Loop F3: mechanical guard for the "3 files must update together"
/// release ritual (pubspec.yaml / app_version.dart / update_log_screen.dart).
///
/// Fails when the three declared versions drift apart, preventing an APK whose
/// displayed version does not match the built code. Runs from the package root
/// (mobile/) under `flutter test`.
void main() {
  test('version is consistent across pubspec, app_version and update log', () {
    // 1. pubspec.yaml -> `version: X.Y.Z`
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final pubMatch =
        RegExp(r'^version:\s*(.+)$', multiLine: true).firstMatch(pubspec);
    expect(pubMatch, isNotNull, reason: 'version: not found in pubspec.yaml');
    final pubspecVersion = pubMatch!.group(1)!.trim();

    // 2. app_version.dart constant
    final appVersion = AppVersion.version;

    // 3. update_log_screen.dart latest entry (first `'version': 'vX.Y.Z'`)
    final log =
        File('lib/screens/update_log_screen.dart').readAsStringSync();
    final logMatch =
        RegExp(r"'version':\s*'v?([^']+)'").firstMatch(log);
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
}
