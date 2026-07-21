// Scoring feature-flag persistence.
//
// Loads/applies ScoringConfig flags from SharedPreferences. Kept ASCII-only so
// the file stays valid UTF-8 on this toolchain. Pure flag application only;
// DirectionalWeightOptimizer.loadAndApply() is invoked by callers (main.dart at
// startup, and the settings screen when the dynamic-weights toggle changes).
import 'package:shared_preferences/shared_preferences.dart';
import '../analysis/scoring_config.dart';

const String kPrefUseRecalibratedDirection = 'use_recalibrated_direction';
const String kPrefUseDynamicDirectionWeights = 'use_dynamic_direction_weights';
const String kPrefUseCalibratedThresholds = 'use_calibrated_thresholds';
const String kPrefShowCalibratedProbability = 'show_calibrated_probability';
const String kPrefUseIsolateScan = 'use_isolate_scan';
const String kPrefRiskProfile = 'risk_profile';
const String kPrefDeemphasizeTrendStrength = 'deemphasize_trend_strength';
const String kPrefDeemphasizeBreakoutChase = 'deemphasize_breakout_chase';
const String kPrefUseReboundGuard = 'use_rebound_guard';

/// Load persisted scoring flags into [ScoringConfig]. Defaults (all off /
/// balanced) when unset, so behavior stays byte-identical to pre-P5 until the
/// user opts in from the settings screen.
void applyScoringPrefs(SharedPreferences prefs) {
  ScoringConfig.useRecalibratedDirection =
      prefs.getBool(kPrefUseRecalibratedDirection) ?? false;
  ScoringConfig.useDynamicDirectionWeights =
      prefs.getBool(kPrefUseDynamicDirectionWeights) ?? false;
  ScoringConfig.useCalibratedThresholds =
      prefs.getBool(kPrefUseCalibratedThresholds) ?? false;
  ScoringConfig.showCalibratedProbability =
      prefs.getBool(kPrefShowCalibratedProbability) ?? false;
  ScoringConfig.useIsolateScan =
      prefs.getBool(kPrefUseIsolateScan) ?? false;
  ScoringConfig.deemphasizeTrendStrength =
      prefs.getBool(kPrefDeemphasizeTrendStrength) ?? false;
  ScoringConfig.deemphasizeBreakoutChase =
      prefs.getBool(kPrefDeemphasizeBreakoutChase) ?? false;
  ScoringConfig.useReboundGuard =
      prefs.getBool(kPrefUseReboundGuard) ?? false;
  switch (prefs.getString(kPrefRiskProfile)) {
    case 'conservative':
      ScoringConfig.riskProfile = RiskProfile.conservative;
      break;
    case 'aggressive':
      ScoringConfig.riskProfile = RiskProfile.aggressive;
      break;
    default:
      ScoringConfig.riskProfile = RiskProfile.balanced;
  }
}
