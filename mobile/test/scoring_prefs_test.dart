import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stock_analyzer/core/scoring_prefs.dart';
import 'package:stock_analyzer/analysis/scoring_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Reset to defaults before each case so tests are order-independent.
    ScoringConfig.useRecalibratedDirection = false;
    ScoringConfig.useDynamicDirectionWeights = false;
    ScoringConfig.useCalibratedThresholds = false;
    ScoringConfig.showCalibratedProbability = false;
    ScoringConfig.useIsolateScan = false;
    ScoringConfig.riskProfile = RiskProfile.balanced;
  });

  test('applyScoringPrefs loads every flag from SharedPreferences', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kPrefUseRecalibratedDirection: true,
      kPrefUseDynamicDirectionWeights: true,
      kPrefUseCalibratedThresholds: true,
      kPrefShowCalibratedProbability: true,
      kPrefUseIsolateScan: true,
      kPrefRiskProfile: 'aggressive',
    });
    final prefs = await SharedPreferences.getInstance();

    applyScoringPrefs(prefs);

    expect(ScoringConfig.useRecalibratedDirection, isTrue);
    expect(ScoringConfig.useDynamicDirectionWeights, isTrue);
    expect(ScoringConfig.useCalibratedThresholds, isTrue);
    expect(ScoringConfig.showCalibratedProbability, isTrue);
    expect(ScoringConfig.useIsolateScan, isTrue);
    expect(ScoringConfig.riskProfile, RiskProfile.aggressive);
    // Version tag tracks the recalibration flag.
    expect(ScoringConfig.directionModelVersion, 'dir-recal-v1');
  });

  test('applyScoringPrefs defaults to off / balanced when unset', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    applyScoringPrefs(prefs);

    expect(ScoringConfig.useRecalibratedDirection, isFalse);
    expect(ScoringConfig.useDynamicDirectionWeights, isFalse);
    expect(ScoringConfig.useCalibratedThresholds, isFalse);
    expect(ScoringConfig.showCalibratedProbability, isFalse);
    expect(ScoringConfig.useIsolateScan, isFalse);
    expect(ScoringConfig.riskProfile, RiskProfile.balanced);
    expect(ScoringConfig.directionModelVersion, 'dir-default-v1');
  });

  test('conservative risk profile is parsed', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      kPrefRiskProfile: 'conservative',
    });
    final prefs = await SharedPreferences.getInstance();

    applyScoringPrefs(prefs);

    expect(ScoringConfig.riskProfile, RiskProfile.conservative);
  });
}
