/// Central scoring feature flags + version tags — single source of truth.
///
/// Every flag defaults to OFF so the live engine stays byte-identical to the
/// pre-v4.3 behavior until data-driven calibration is explicitly enabled and
/// validated against the accuracy report (scripts/analyze_decision_accuracy.py).
///
/// Flags are mutable statics (not `const`) so they can be toggled at runtime
/// (e.g. from settings or tests) without recompiling. Version tags are stamped
/// onto persisted decisions so historical scores are never silently compared
/// with scores produced under a different weight/threshold regime.
/// User risk appetite that tunes recommendation execution-gate strictness (P3).
/// `balanced` is the neutral default and leaves gates byte-identical.
enum RiskProfile { conservative, balanced, aggressive }

class ScoringConfig {
  ScoringConfig._();

  /// P2.1 — use data-driven direction-component weights derived from realized
  /// outcomes instead of the static [DirectionalEvidenceBuilder.componentWeights].
  static bool useDynamicDirectionWeights = false;

  /// P2.2 — use backtest-calibrated recommendation thresholds/gates.
  static bool useCalibratedThresholds = false;

  /// P2.3 — surface the calibrated hit probability next to the legacy 1-10 score.
  static bool showCalibratedProbability = false;

  /// P3 personalization: user risk appetite. `balanced` == no gate change, so
  /// the default remains byte-identical to pre-P3 behavior.
  static RiskProfile riskProfile = RiskProfile.balanced;

  /// P4.1: offload batch-scan analysis to a background isolate (via compute).
  /// Default off; enable after on-device frame-time validation.
  static bool useIsolateScan = false;

  /// P5 — 循证校准方向证据：低波/反转 fade + 降低追涨/放量奖励（基于离线 IC 证据）。
  /// 默认关；开启后 DirectionalEvidenceBuilder 应用循证微调，关闭时字节等价回退。
  static bool useRecalibratedDirection = false;

  /// v4.7 P1 — de-emphasize the lagging ADX '趋势强度强劲' signal (both directions).
  /// Archive validation showed it is contrarian at reversals (bull -1.3%, bear
  /// +2.4% next-day). Default off; enable after cross-day validation.
  static bool deemphasizeTrendStrength = false;

  /// v4.7 P2 — de-emphasize the '趋势突破上轨' upper-band breakout BUY signal
  /// (archive: 0% next-day win, -3.4%). Default off.
  static bool deemphasizeBreakoutChase = false;

  /// v4.7 P3 — rebound guard: pull bearish-leaning scores toward neutral when the
  /// stock is oversold/crashed (mean-reversion bounce likely; mirror of the chase
  /// penalty). Default off; validate cross-day before enabling.
  static bool useReboundGuard = false;

  /// v4.10 - short-term realtime inverted-U reprofile: move the reward peak
  /// from (1,3] to mild pullback/flat (-2..+1) and turn the 3-5% chase zone
  /// into a penalty. Evidence: 3281-row archive (mild pullback -2..0% =>
  /// +0.30% forward; 3-5% => -0.54%, worst hit rate). Default off; the
  /// scorer is byte-identical to the legacy inverted-U when this is false.
  static bool useShortTermRealtimeReprofile = false;

  /// 方向模型版本标签：随循证校准开关切换，可写入 decision_snapshots.model_version，
  /// 使不同口径的历史分数不被混合统计。
  static String get directionModelVersion =>
      useRecalibratedDirection ? 'dir-recal-v1' : 'dir-default-v1';

  /// Bumped whenever the active direction weights change, so old/new decisions
  /// stay comparable only within the same version.
  static const String defaultWeightsVersion = 'w-default-v1';

  /// Bumped whenever recommendation thresholds/gates change.
  static const String defaultPolicyVersion = 'p-default-v1';

  /// Runtime weights version tag (updated by the optimizer bootstrap when
  /// dynamic weights are applied; stays default when the flag is off).
  static String activeWeightsVersion = defaultWeightsVersion;

  // ---- Optimizer guardrails (mirror DecisionCalibrator statistical rigor) ----

  /// Minimum evaluated samples before dynamic weights may deviate from default.
  static const int minWeightSamples = 100;

  /// Minimum distinct signal dates (guards against a single day dominating).
  static const int minWeightDates = 20;

  /// Per-component maximum absolute weight adjustment per optimization run.
  static const double maxWeightAdjustment = 0.08;

  /// Recency decay (older outcomes count less); 1.0 == no decay.
  static const double weightDecayFactor = 0.98;
}
