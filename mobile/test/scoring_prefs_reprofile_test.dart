import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_analyzer/analysis/scoring_config.dart';
import 'package:stock_analyzer/core/scoring_prefs.dart';

/// v4.10: persistence wiring for the realtime reprofile flag. Confirms
/// applyScoringPrefs (invoked at startup and by the settings screen) defaults
/// the flag to false and restores a persisted value, so the settings toggle
/// survives an app restart.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => ScoringConfig.useShortTermRealtimeReprofile = false);

  test('applyScoringPrefs defaults the reprofile flag to false when unset', () async {
    SharedPreferences.setMockInitialValues({});
    ScoringConfig.useShortTermRealtimeReprofile = true; // dirty it first
    applyScoringPrefs(await SharedPreferences.getInstance());
    expect(ScoringConfig.useShortTermRealtimeReprofile, isFalse);
  });

  test('applyScoringPrefs restores the persisted reprofile flag', () async {
    SharedPreferences.setMockInitialValues(
      {kPrefUseShortTermRealtimeReprofile: true},
    );
    applyScoringPrefs(await SharedPreferences.getInstance());
    expect(ScoringConfig.useShortTermRealtimeReprofile, isTrue);
  });
}
