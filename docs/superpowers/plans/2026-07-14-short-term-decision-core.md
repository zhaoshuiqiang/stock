# Short-Term Decision Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce the unified short-term decision model, deterministic scoring engine, recommendation policy, and consistent Signal/Opportunity integration while preserving legacy callers.

**Architecture:** New pure Dart components produce direction, trade quality, risk, evidence confidence, and a single recommendation direction. SignalEngine owns orchestration and exposes the result through AnalysisResult; a compatibility adapter supplies the existing integer score and Chinese recommendation text. No new core component reads a database or performs HTTP requests.

**Tech Stack:** Dart 3, Flutter test, existing stock_models.dart indicators and signal types.

---

## Execution Order

Complete this plan before:

1. 2026-07-14-short-term-decision-tracking.md
2. 2026-07-14-short-term-decision-calibration.md
3. 2026-07-14-short-term-decision-ui-rollout.md

## File Map

Create:

- mobile/lib/models/short_term_decision.dart
- mobile/lib/analysis/market_regime_classifier.dart
- mobile/lib/analysis/directional_evidence_builder.dart
- mobile/lib/analysis/trade_quality_evaluator.dart
- mobile/lib/analysis/short_term_risk_evaluator.dart
- mobile/lib/analysis/primary_strategy_selector.dart
- mobile/lib/analysis/evidence_confidence_calculator.dart
- mobile/lib/analysis/recommendation_policy.dart
- mobile/lib/analysis/legacy_decision_adapter.dart
- mobile/lib/analysis/short_term_decision_engine.dart
- mobile/test/short_term_decision_model_test.dart
- mobile/test/recommendation_policy_test.dart
- mobile/test/market_regime_classifier_test.dart
- mobile/test/directional_evidence_builder_test.dart
- mobile/test/trade_quality_and_risk_test.dart
- mobile/test/primary_strategy_selector_test.dart
- mobile/test/evidence_confidence_calculator_test.dart
- mobile/test/short_term_decision_engine_test.dart
- mobile/test/opportunity_engine_short_term_test.dart

Modify:

- mobile/lib/models/stock_models.dart
- mobile/lib/analysis/confidence_calculator.dart
- mobile/lib/analysis/signal_engine.dart
- mobile/lib/analysis/opportunity_engine.dart
- mobile/test/confidence_calculator_test.dart
- mobile/test/signal_engine_short_term_test.dart

### Task 1: Add The Decision Domain Model

**Files:**

- Create: mobile/lib/models/short_term_decision.dart
- Modify: mobile/lib/models/stock_models.dart:874-1198
- Test: mobile/test/short_term_decision_model_test.dart

- [ ] **Step 1: Write the failing model tests**

~~~dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  test('decision round-trips without converting evidence confidence to probability', () {
    final decision = ShortTermDecision(
      directionScore: 0,
      tradeQualityScore: 64,
      riskScore: 42,
      evidenceConfidence: 71,
      calibrationByHorizon: const {},
      direction: RecommendationDirection.neutral,
      marketRegime: MarketRegime.range,
      directionComponents: const {'trend': 0.2},
      qualityComponents: const {'timing': 0.7},
      riskComponents: const {'volatility': 0.4},
      primaryStrategyId: null,
      primaryStrategyName: null,
      supportingStrategyIds: const [],
      dataQualityFlags: const [],
      modelVersion: 'short-term-v2',
      rawComprehensiveScore: 6.2,
    );

    final restored = ShortTermDecision.fromJson(decision.toJson());

    expect(restored.direction, RecommendationDirection.neutral);
    expect(restored.evidenceConfidence, 71);
    expect(restored.calibrationByHorizon, isEmpty);
    expect(restored.modelVersion, 'short-term-v2');
  });

  test('analysis result keeps a nullable decision for legacy JSON', () {
    final result = AnalysisResult.fromJson(const {
      'score': 5,
      'recommendation': '观望',
    });

    expect(result.shortTermDecision, isNull);
  });
}
~~~

- [ ] **Step 2: Run the tests and verify the missing types fail**

Run:

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/short_term_decision_model_test.dart
~~~

Expected: compilation fails because short_term_decision.dart and AnalysisResult.shortTermDecision do not exist.

- [ ] **Step 3: Implement immutable decision types and JSON codecs**

Create enums RecommendationDirection, RecommendationLevel, MarketRegime and classes CalibrationEstimate, ShortTermDecision, and RecommendationDecision. CalibrationEstimate stores horizon, probability, sampleCount, wilsonLower, and wilsonUpper. ShortTermDecision must implement copyWith so calibration can enrich an immutable decision later. Use enum.name for JSON, clamp numeric values in constructors with assertions, and parse unknown enum values to neutral/unknown.

The ShortTermDecision constructor must contain exactly these public fields:

~~~dart
final double directionScore;
final double tradeQualityScore;
final double riskScore;
final double evidenceConfidence;
final Map<int, CalibrationEstimate> calibrationByHorizon;
final RecommendationDirection direction;
final MarketRegime marketRegime;
final Map<String, double> directionComponents;
final Map<String, double> qualityComponents;
final Map<String, double> riskComponents;
final String? primaryStrategyId;
final String? primaryStrategyName;
final List<String> supportingStrategyIds;
final List<String> dataQualityFlags;
final String modelVersion;
final double rawComprehensiveScore;
~~~

RecommendationDecision must contain direction, level, label, legacyScore, actionable, and gates.

- [ ] **Step 4: Add the nullable field to AnalysisResult**

Import short_term_decision.dart from stock_models.dart and add:

~~~dart
final ShortTermDecision? shortTermDecision;
~~~

Update the constructor, fromJson, toJson, and copyWith. Legacy JSON without short_term_decision must return null.

- [ ] **Step 5: Run model and existing serialization tests**

Run:

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/short_term_decision_model_test.dart test/stock_models_test.dart
~~~

Expected: PASS.

- [ ] **Step 6: Commit the model**

~~~powershell
git add mobile/lib/models/short_term_decision.dart mobile/lib/models/stock_models.dart mobile/test/short_term_decision_model_test.dart
git commit -m "feat: add short-term decision model"
~~~

### Task 2: Centralize Recommendation Policy And Legacy Mapping

**Files:**

- Create: mobile/lib/analysis/recommendation_policy.dart
- Create: mobile/lib/analysis/legacy_decision_adapter.dart
- Test: mobile/test/recommendation_policy_test.dart

- [ ] **Step 1: Write table-driven policy tests**

Test all boundaries -55, -35, -20, -12, 12, 20, 35, 55 and verify:

- directionScore 0 maps to neutral, label 观望, legacy score 5;
- bullish direction with quality below its gate becomes 偏多观望 without changing direction;
- risk above the gate makes a bullish decision non-actionable;
- bearish evidence confidence below 55 becomes 偏空观望;
- the exceptional score 10 requires direction >= 55, quality >= 85, risk <= 30, and evidence >= 80.

Use a helper:

~~~dart
ShortTermDecision decision({
  double direction = 0,
  double quality = 70,
  double risk = 30,
  double evidence = 70,
}) => ShortTermDecision(
  directionScore: direction,
  tradeQualityScore: quality,
  riskScore: risk,
  evidenceConfidence: evidence,
  calibrationByHorizon: const {},
  direction: direction >= 12
      ? RecommendationDirection.bullish
      : direction <= -12
          ? RecommendationDirection.bearish
          : RecommendationDirection.neutral,
  marketRegime: MarketRegime.range,
  directionComponents: const {},
  qualityComponents: const {},
  riskComponents: const {},
  primaryStrategyId: null,
  primaryStrategyName: null,
  supportingStrategyIds: const [],
  dataQualityFlags: const [],
  modelVersion: 'short-term-v2',
  rawComprehensiveScore: 5,
);
~~~

- [ ] **Step 2: Run the test and verify failure**

Run:

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/recommendation_policy_test.dart
~~~

Expected: compilation fails because RecommendationPolicy is missing.

- [ ] **Step 3: Implement RecommendationPolicy**

Implement the exact score bands and long-side quality/risk/evidence gates from the design spec. Bearish labels must describe reduce/avoid semantics and must not imply opening a short position.

- [ ] **Step 4: Implement LegacyDecisionAdapter**

LegacyDecisionAdapter exposes:

~~~dart
static int scoreOf(RecommendationDecision decision);
static String recommendationOf(RecommendationDecision decision);
~~~

It delegates to RecommendationDecision values and contains no independent thresholds.

- [ ] **Step 5: Run the policy test**

Expected: PASS.

- [ ] **Step 6: Commit**

~~~powershell
git add mobile/lib/analysis/recommendation_policy.dart mobile/lib/analysis/legacy_decision_adapter.dart mobile/test/recommendation_policy_test.dart
git commit -m "feat: centralize short-term recommendation policy"
~~~

### Task 3: Classify Market Regime Once

**Files:**

- Create: mobile/lib/analysis/market_regime_classifier.dart
- Test: mobile/test/market_regime_classifier_test.dart

- [ ] **Step 1: Write failing classification tests**

Cover null context -> unknown, strong positive trend -> bullishTrend, positive recovery after a negative trend -> rebound, strong negative trend -> bearishTrend, mild negative -> pullback, high breadth volatility -> highVolatility, and neutral values -> range.

The classifier result must expose both regime and the fixed bias mapping:

~~~dart
expect(result.marketBias, 50);   // bullishTrend
expect(result.marketBias, 25);   // rebound
expect(result.marketBias, -20);  // pullback
expect(result.marketBias, -50);  // bearishTrend
~~~

- [ ] **Step 2: Run and verify failure**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/market_regime_classifier_test.dart
~~~

- [ ] **Step 3: Implement deterministic classification**

Use MarketContext.marketTrend, avgChangePct, shIndexPct, szIndexPct, and breadth from upCount/downCount. Return unknown with a market_context_missing quality flag when context is null. Keep the fixed bias table in one const map.

- [ ] **Step 4: Run the test and commit**

~~~powershell
git add mobile/lib/analysis/market_regime_classifier.dart mobile/test/market_regime_classifier_test.dart
git commit -m "feat: add unified market regime classifier"
~~~

### Task 4: Build Deduplicated Direction Evidence

**Files:**

- Create: mobile/lib/analysis/directional_evidence_builder.dart
- Test: mobile/test/directional_evidence_builder_test.dart

- [ ] **Step 1: Write failing evidence tests**

Use synthetic HistoryKline values to prove:

- the component map contains only trend, reversal_momentum, volume_flow, relative_strength, next_session;
- component weights sum to 1.0;
- market contribution changes the final score by no more than 20 points;
- a -5% three-day decline plus RSI6 28 and WR14 86 caps a bearish result at -19 unless trend and volume-flow are both <= -0.45;
- an 8% daily rise with overbought evidence caps an unconfirmed bullish result at 34;
- the same SignalItem cannot be counted in two component signal sets.

- [ ] **Step 2: Run and verify failure**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/directional_evidence_builder_test.dart
~~~

- [ ] **Step 3: Implement the input and result types**

DirectionalEvidenceInput contains data, buySignals, sellSignals, quote, marketContext, marketStructure, industryRelativeStrength, NextDayPredictionResult, and NextSessionPrediction. industryRelativeStrength reuses the existing percentile industry RS value when available. DirectionalEvidenceResult contains the five normalized components, stockEvidence, marketBias, directionScore, marketRegime, guard reasons, and data quality flags.

- [ ] **Step 4: Implement component ownership**

Reuse current RSI/KDJ/WR/BIAS/MA/ADX thresholds. Assign each indicator to one primary component. Normalize every component to -1..1 and aggregate:

~~~dart
final stockEvidence = 100 * (
  trend * 0.30 +
  reversalMomentum * 0.25 +
  volumeFlow * 0.20 +
  relativeStrength * 0.15 +
  nextSession * 0.10
);
final score = (stockEvidence * 0.80 + marketBias * 0.20)
    .clamp(-100.0, 100.0)
    .toDouble();
~~~

Apply the rebound and chase guards after aggregation and include the guard reason.

- [ ] **Step 5: Run the focused tests and commit**

~~~powershell
git add mobile/lib/analysis/directional_evidence_builder.dart mobile/test/directional_evidence_builder_test.dart
git commit -m "feat: add deduplicated directional evidence"
~~~

### Task 5: Separate Trade Quality From Risk

**Files:**

- Create: mobile/lib/analysis/trade_quality_evaluator.dart
- Create: mobile/lib/analysis/short_term_risk_evaluator.dart
- Test: mobile/test/trade_quality_and_risk_test.dart

- [ ] **Step 1: Write failing tests**

Cover:

- fresh aligned signals and confirmed volume improve quality;
- good support/resistance reward-risk improves quality;
- ATR, one-price limits, excessive turnover, ST status, and missing data increase risk;
- changing risk inputs leaves DirectionalEvidenceResult.directionScore unchanged;
- every returned component score is 0..100 and weighted totals are 0..100.

- [ ] **Step 2: Run and verify failure**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/trade_quality_and_risk_test.dart
~~~

- [ ] **Step 3: Implement TradeQualityEvaluator**

Return a typed score with timing 30%, volume-price 25%, liquidity-turnover 20%, support/reward-risk 15%, and primary-strategy support 10%. Migrate reusable ShortTermScorer logic without applying direction penalties.

- [ ] **Step 4: Implement ShortTermRiskEvaluator**

Return volatility 25%, execution constraints 25%, chase/oversold execution risk 20%, liquidity 15%, and ST/event/data quality 15%. Higher values mean higher risk.

- [ ] **Step 5: Run current ShortTermScorer regression tests**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/trade_quality_and_risk_test.dart test/short_term_scorer_test.dart
~~~

Expected: PASS.

- [ ] **Step 6: Commit**

~~~powershell
git add mobile/lib/analysis/trade_quality_evaluator.dart mobile/lib/analysis/short_term_risk_evaluator.dart mobile/test/trade_quality_and_risk_test.dart
git commit -m "feat: separate trade quality and short-term risk"
~~~

### Task 6: Select One Primary Strategy

**Files:**

- Create: mobile/lib/analysis/primary_strategy_selector.dart
- Modify: mobile/lib/analysis/strategy_builder.dart
- Test: mobile/test/primary_strategy_selector_test.dart

- [ ] **Step 1: Write failing strategy tests**

Verify inactive strategies are ignored, long-only strategies are ignored for a short-term decision, bullish decisions only accept buy strategies, bearish decisions only accept sell strategies, minConfidence is enforced, the highest signal-strength/risk-reward candidate becomes primary, and all remaining compatible ids are supporting only. Add regression assertions that the two active defensive strategies built by StrategyBuilder have type sell.

- [ ] **Step 2: Run and verify failure**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/primary_strategy_selector_test.dart
~~~

- [ ] **Step 3: Implement PrimaryStrategySelector**

Expose:

~~~dart
StrategySelectionResult select({
  required List<TradingStrategy> strategies,
  required RecommendationDirection direction,
  required double evidenceConfidence,
});
~~~

Filter by isActive, strategyType short/both, aligned type, and minConfidence. Sort by signalStrength descending, then riskRewardRatio descending, then id for deterministic ties. Return at most one primary strategy and supporting ids.

- [ ] **Step 4: Fix defensive strategy types**

Set type: 'sell' on the active defensive/exit strategies that currently inherit the buy default. Do not change their activation rules in this task.

- [ ] **Step 5: Run and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/primary_strategy_selector_test.dart test/strategy_engine_test.dart
git add mobile/lib/analysis/primary_strategy_selector.dart mobile/lib/analysis/strategy_builder.dart mobile/test/primary_strategy_selector_test.dart
git commit -m "fix: select and attribute one primary strategy"
~~~

### Task 7: Add Evidence Confidence

**Files:**

- Create: mobile/lib/analysis/evidence_confidence_calculator.dart
- Test: mobile/test/evidence_confidence_calculator_test.dart

- [ ] **Step 1: Write failing tests**

Verify independent component agreement contributes 40%, data coverage 25%, freshness 20%, history stability 15%, missing market data lowers confidence, and the result never supplies a probability.

- [ ] **Step 2: Implement**

Expose:

~~~dart
EvidenceConfidenceResult calculate({
  required Map<String, double> directionComponents,
  required List<SignalItem> directionalSignals,
  required List<String> dataQualityFlags,
  double historicalStability = 50,
});
~~~

Return score 0..100 and a component breakdown. With no mature history, historicalStability is exactly 50.

- [ ] **Step 3: Run and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/evidence_confidence_calculator_test.dart
git add mobile/lib/analysis/evidence_confidence_calculator.dart mobile/test/evidence_confidence_calculator_test.dart
git commit -m "feat: add evidence confidence index"
~~~

### Task 8: Compose The Pure Short-Term Decision Engine

**Files:**

- Create: mobile/lib/analysis/short_term_decision_engine.dart
- Test: mobile/test/short_term_decision_engine_test.dart

- [ ] **Step 1: Write failing end-to-end pure engine tests**

Cover neutral data, clean bullish evidence, clean bearish evidence, rebound guard, chase guard, high-risk bullish watch, missing market context, and modelVersion short-term-v2.

- [ ] **Step 2: Implement ShortTermDecisionInput**

The input contains all pre-fetched values and no services:

~~~dart
List<HistoryKline> data;
QuoteData? quote;
List<SignalItem> buySignals;
List<SignalItem> sellSignals;
MarketContext? marketContext;
MarketStructureResult? marketStructure;
double? industryRelativeStrength;
NextDayPredictionResult nextDayPrediction;
NextSessionPrediction nextSessionPrediction;
Map<String, dynamic>? tradeLevels;
List<TradingStrategy> activeStrategies;
double rawComprehensiveScore;
~~~

- [ ] **Step 3: Implement orchestration**

Call the evidence, quality, risk, and confidence components; derive RecommendationDirection from directionScore; select one primary strategy with PrimaryStrategySelector; build ShortTermDecision with primary/supporting strategy ids; then call RecommendationPolicy to return both decision and recommendation.

- [ ] **Step 4: Run and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/short_term_decision_engine_test.dart
git add mobile/lib/analysis/short_term_decision_engine.dart mobile/test/short_term_decision_engine_test.dart
git commit -m "feat: compose short-term decision engine"
~~~

### Task 9: Integrate SignalEngine And Unify Direction Consumers

**Files:**

- Modify: mobile/lib/analysis/signal_engine.dart:284-865
- Modify: mobile/lib/analysis/confidence_calculator.dart:21-340
- Modify: mobile/test/signal_engine_short_term_test.dart
- Modify: mobile/test/confidence_calculator_test.dart

- [ ] **Step 1: Add failing integration tests**

Add tests proving:

- a neutral decision is recommendation 观望 and score 5 everywhere;
- score-derived sell direction is no longer used for a neutral decision;
- a sharp-decline oversold sell result is raised to weak bearish observation;
- prediction support and backtest aligned signals use RecommendationDirection;
- AnalysisResult.shortTermDecision survives copyWith and JSON.

- [ ] **Step 2: Change ConfidenceCalculator to accept direction**

Add required RecommendationDirection direction to calculate and breakdown. Replace every totalScore >= 6 / <= 5 direction branch with enum comparisons. Keep totalScore only where a numeric strength is genuinely required.

- [ ] **Step 3: Replace scattered final-score gates in SignalEngine**

After existing indicators, predictions, strategies, and trade levels are available, call ShortTermDecisionEngine once. Set:

~~~dart
final totalScore = recommendationDecision.legacyScore;
final recommendation = recommendationDecision.label;
final confidenceScore = shortTermDecision.evidenceConfidence / 100;
~~~

Delete the final-decision use of ShortTermScorer.capRecommendationScore, the one-sided calibration application, and _applyNextSessionRiskGate. Keep the old helpers temporarily only if an existing public test imports them; otherwise remove them.

- [ ] **Step 4: Make prediction and backtest support enum-based**

Change _predictionSupportForRecommendation and aligned/opposite signal selection to accept RecommendationDirection. Score 5 must never be treated as sell.

- [ ] **Step 5: Run focused regression tests**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/signal_engine_short_term_test.dart test/confidence_calculator_test.dart test/recommendation_calibrator_test.dart test/short_term_scorer_test.dart test/signal_engine_test.dart
~~~

Expected: PASS.

- [ ] **Step 6: Commit**

~~~powershell
git add mobile/lib/analysis/signal_engine.dart mobile/lib/analysis/confidence_calculator.dart mobile/test/signal_engine_short_term_test.dart mobile/test/confidence_calculator_test.dart
git commit -m "refactor: route final recommendations through decision engine"
~~~

### Task 10: Pass Market Context Through Opportunity Analysis

**Files:**

- Modify: mobile/lib/analysis/opportunity_engine.dart:114-220
- Test: mobile/test/opportunity_engine_short_term_test.dart
- Test: mobile/test/explore_engine_short_term_test.dart

- [ ] **Step 1: Extract a testable cached-analysis helper**

Add a visible-for-testing pure helper that accepts calculated K-lines, quote, MarketContext, and an analysis generator callback. The helper must call generateAnalysis with marketContext and enableAsyncSideEffects false.

- [ ] **Step 2: Write the failing test**

Use a callback that records named arguments and verify marketContext is the same instance and asynchronous side effects are disabled.

- [ ] **Step 3: Fetch MarketContext once per batch run**

Import MarketContextProvider and include getMarketContext() in the existing Future.wait with quotes and MarketTiming. Pass the result to every cached analysis call. On failure pass null; the decision engine must then emit unknown regime and a data quality flag.

- [ ] **Step 4: Preserve OpportunityResult compatibility**

Keep existing score and recommendation fields from AnalysisResult. Add an optional ShortTermDecision field plus decision_json serialization only if the current opportunity table migration is implemented in the tracking plan; until then the field remains in memory and fromMap accepts absence.

- [ ] **Step 5: Run focused tests**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/opportunity_engine_short_term_test.dart test/explore_engine_short_term_test.dart test/refactor_regression_test.dart
~~~

Expected: PASS.

- [ ] **Step 6: Commit**

~~~powershell
git add mobile/lib/analysis/opportunity_engine.dart mobile/test/opportunity_engine_short_term_test.dart mobile/test/explore_engine_short_term_test.dart
git commit -m "fix: pass market context into opportunity decisions"
~~~

### Task 11: Verify Core Plan

**Files:** No production edits expected.

- [ ] **Step 1: Format changed Dart files**

~~~powershell
cd mobile
D:\flutter\bin\dart.bat format lib/models/short_term_decision.dart lib/models/stock_models.dart lib/analysis/market_regime_classifier.dart lib/analysis/directional_evidence_builder.dart lib/analysis/trade_quality_evaluator.dart lib/analysis/short_term_risk_evaluator.dart lib/analysis/primary_strategy_selector.dart lib/analysis/strategy_builder.dart lib/analysis/evidence_confidence_calculator.dart lib/analysis/recommendation_policy.dart lib/analysis/legacy_decision_adapter.dart lib/analysis/short_term_decision_engine.dart lib/analysis/confidence_calculator.dart lib/analysis/signal_engine.dart lib/analysis/opportunity_engine.dart test/short_term_decision_model_test.dart test/recommendation_policy_test.dart test/market_regime_classifier_test.dart test/directional_evidence_builder_test.dart test/trade_quality_and_risk_test.dart test/primary_strategy_selector_test.dart test/evidence_confidence_calculator_test.dart test/short_term_decision_engine_test.dart test/opportunity_engine_short_term_test.dart
~~~

- [ ] **Step 2: Run core tests**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/short_term_decision_model_test.dart test/recommendation_policy_test.dart test/market_regime_classifier_test.dart test/directional_evidence_builder_test.dart test/trade_quality_and_risk_test.dart test/primary_strategy_selector_test.dart test/evidence_confidence_calculator_test.dart test/short_term_decision_engine_test.dart test/opportunity_engine_short_term_test.dart test/signal_engine_short_term_test.dart test/confidence_calculator_test.dart
~~~

Expected: all PASS.

- [ ] **Step 3: Run static analysis on changed files**

~~~powershell
cd mobile
D:\flutter\bin\dart.bat analyze lib/models/short_term_decision.dart lib/models/stock_models.dart lib/analysis/market_regime_classifier.dart lib/analysis/directional_evidence_builder.dart lib/analysis/trade_quality_evaluator.dart lib/analysis/short_term_risk_evaluator.dart lib/analysis/primary_strategy_selector.dart lib/analysis/strategy_builder.dart lib/analysis/evidence_confidence_calculator.dart lib/analysis/recommendation_policy.dart lib/analysis/legacy_decision_adapter.dart lib/analysis/short_term_decision_engine.dart lib/analysis/confidence_calculator.dart lib/analysis/signal_engine.dart lib/analysis/opportunity_engine.dart
~~~

Expected: no new errors.
