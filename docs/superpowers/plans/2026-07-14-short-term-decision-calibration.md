# Short-Term Decision Calibration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce leakage-safe 1/3/5-day calibrated effective-hit probabilities and typed decision statistics without enabling automatic production weight changes.

**Architecture:** Pure statistical utilities calculate posterior probability, Wilson intervals, Brier, and ECE. A calibration model is trained only from outcomes mature before the new signal date and returns per-horizon estimates; a small service reads typed database rows and enriches AnalysisResult before snapshots are saved.

**Tech Stack:** Dart math, sqflite typed queries, Flutter test.

---

## Dependencies

Complete both core and tracking plans first.

## File Map

Create:

- mobile/lib/analysis/calibration_metrics.dart
- mobile/lib/analysis/decision_calibrator.dart
- mobile/lib/analysis/decision_calibration_service.dart
- mobile/lib/analysis/decision_statistics.dart
- mobile/test/calibration_metrics_test.dart
- mobile/test/decision_calibrator_test.dart
- mobile/test/decision_calibration_service_test.dart
- mobile/test/decision_statistics_test.dart
- mobile/test/decision_statistics_db_test.dart

Modify:

- mobile/lib/models/stock_models.dart
- mobile/lib/storage/database_service.dart
- mobile/lib/analysis/opportunity_engine.dart
- mobile/lib/analysis/explore_engine.dart
- mobile/lib/screens/quote_screen.dart

### Task 1: Implement Statistical Primitives

**Files:**

- Create: mobile/lib/analysis/calibration_metrics.dart
- Test: mobile/test/calibration_metrics_test.dart

- [ ] **Step 1: Write failing math tests**

Cover:

- Beta-Binomial posterior with effective prior sample size 20;
- Wilson interval for 0/100, 50/100, and 100/100;
- Brier for perfect, completely wrong, and mixed predictions;
- ECE with 10 equal-width buckets;
- probability 1.0 belongs to bucket index 9;
- empty input returns null metrics rather than NaN;
- probabilities outside 0..1 throw ArgumentError.

- [ ] **Step 2: Run and verify failure**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/calibration_metrics_test.dart
~~~

- [ ] **Step 3: Implement exact APIs**

~~~dart
double betaBinomialPosterior({
  required int hits,
  required int sampleCount,
  required double globalBaseRate,
  int priorSampleSize = 20,
});

ConfidenceInterval wilsonInterval({
  required int hits,
  required int sampleCount,
  double z = 1.959963984540054,
});

double? brierScore(List<ProbabilityOutcome> samples);
double? expectedCalibrationError(
  List<ProbabilityOutcome> samples, {
  int bucketCount = 10,
});
~~~

Use population-weighted ECE and skip empty buckets.

- [ ] **Step 4: Run and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/calibration_metrics_test.dart
git add mobile/lib/analysis/calibration_metrics.dart mobile/test/calibration_metrics_test.dart
git commit -m "feat: add calibration metrics"
~~~

### Task 2: Build Leakage-Safe Calibration Buckets

**Files:**

- Create: mobile/lib/analysis/decision_calibrator.dart
- Modify: mobile/lib/models/stock_models.dart
- Test: mobile/test/decision_calibrator_test.dart

- [ ] **Step 1: Write failing eligibility tests**

Cover:

- 99 versus 100 valid samples;
- 19 versus 20 distinct signal dates;
- 94.9% versus 95% coverage;
- same modelVersion is required for bucket and global base rate;
- bullish and bearish buckets never mix;
- 1/3/5 horizons never mix;
- no estimate is returned for neutral direction;
- strength bands are 12-19.99, 20-34.99, 35-54.99, and 55-100;
- outcomes with target dates on or after the new signal date are excluded.

- [ ] **Step 2: Run and verify failure**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_calibrator_test.dart
~~~

- [ ] **Step 3: Implement typed calibration rows**

DecisionCalibrationRow includes modelVersion, horizon, direction, directionScore, marketRegime, signalTradeDate, targetTradeDate, status, and effectiveDirectionHit. Define DecisionCalibrationRow and DecisionStatisticsRow in stock_models.dart so storage does not depend on analysis-layer classes.

DecisionCalibrator.buildModel accepts rows and asOfTradeDate. It discards rows whose result was not knowable before asOfTradeDate.

- [ ] **Step 4: Implement estimates**

For each eligible bucket:

1. compute the same-model/horizon/direction global base rate;
2. compute the posterior with prior size 20;
3. compute the raw-hit Wilson interval;
4. return CalibrationEstimate for the requested horizon.

Do not use Brier/ECE as the first-estimate gate. They evaluate previously saved signal-time probabilities.

- [ ] **Step 5: Run and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_calibrator_test.dart test/calibration_metrics_test.dart
git add mobile/lib/analysis/decision_calibrator.dart mobile/lib/models/stock_models.dart mobile/test/decision_calibrator_test.dart
git commit -m "feat: calibrate decisions by horizon and regime"
~~~

### Task 3: Add Typed Calibration And Statistics Queries

**Files:**

- Modify: mobile/lib/storage/database_service.dart
- Test: mobile/test/decision_statistics_db_test.dart

- [ ] **Step 1: Write failing database query tests**

Verify filters for horizon, direction, marketRegime, modelVersion, source, primaryStrategyId, minimum/maximum direction score, and asOfTradeDate. Verify queries read only decision_snapshots and decision_outcomes and return typed rows.

- [ ] **Step 2: Implement query types and methods**

Add:

~~~dart
Future<List<DecisionCalibrationRow>> getDecisionCalibrationRows({
  required String modelVersion,
  required DateTime asOfTradeDate,
});

Future<List<DecisionStatisticsRow>> getDecisionStatisticsRows({
  int? horizon,
  RecommendationDirection? direction,
  MarketRegime? marketRegime,
  String? modelVersion,
  String? source,
  String? primaryStrategyId,
  double? minDirectionScore,
  double? maxDirectionScore,
});
~~~

The calibration query excludes outcomes whose target_trade_date is not before asOfTradeDate. Do not join legacy tables.

- [ ] **Step 3: Run and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_statistics_db_test.dart test/decision_tracking_db_test.dart
git add mobile/lib/storage/database_service.dart mobile/test/decision_statistics_db_test.dart
git commit -m "feat: query decision calibration data"
~~~

### Task 4: Enrich Decisions Before Snapshot Capture

**Files:**

- Create: mobile/lib/analysis/decision_calibration_service.dart
- Modify: mobile/lib/analysis/opportunity_engine.dart
- Modify: mobile/lib/analysis/explore_engine.dart
- Modify: mobile/lib/screens/quote_screen.dart
- Test: mobile/test/decision_calibration_service_test.dart

- [ ] **Step 1: Write failing service tests**

Use a fake row loader. Verify:

- cold start leaves calibrationByHorizon empty;
- eligible rows add independent 1/3/5 CalibrationEstimate values;
- the original decision is not mutated;
- asOfTradeDate is forwarded;
- neutral decisions remain uncalibrated;
- a known future outcome cannot influence an earlier signal.

- [ ] **Step 2: Implement the service**

~~~dart
class DecisionCalibrationService {
  Future<AnalysisResult> enrich(
    AnalysisResult analysis, {
    required DateTime asOfTradeDate,
  });
}
~~~

Load rows once per model version and date, build a DecisionCalibrationModel, estimate each horizon, and return analysis.copyWith(shortTermDecision: decision.copyWith(calibrationByHorizon: estimates)).

- [ ] **Step 3: Integrate asynchronous callers**

After generateAnalysis and before DecisionTracker.capture:

~~~dart
analysis = await _decisionCalibrationService.enrich(
  analysis,
  asOfTradeDate: calculated.last.date,
);
~~~

Apply this in OpportunityEngine, ExploreEngine, and QuoteScreen. If the service fails, log and retain the uncalibrated decision; never synthesize 50%.

- [ ] **Step 4: Run and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_calibration_service_test.dart test/opportunity_engine_short_term_test.dart test/explore_engine_short_term_test.dart
git add mobile/lib/analysis/decision_calibration_service.dart mobile/lib/analysis/opportunity_engine.dart mobile/lib/analysis/explore_engine.dart mobile/lib/screens/quote_screen.dart mobile/test/decision_calibration_service_test.dart
git commit -m "feat: attach signal-time calibration estimates"
~~~

### Task 5: Add Typed Decision Statistics

**Files:**

- Create: mobile/lib/analysis/decision_statistics.dart
- Test: mobile/test/decision_statistics_test.dart

- [ ] **Step 1: Write failing aggregation tests**

Verify:

- pending rows do not enter return denominators;
- invalid rows do not become zero returns;
- evaluated count, pending count, invalid count, and coverage are distinct;
- raw/effective/Alpha hit rates use their own denominators;
- mean and median return/Alpha are correct;
- MFE/MAE are grouped by horizon;
- Wilson uses raw hit counts, not posterior probability;
- Brier/ECE use only matured rows with signal-time predicted_probability;
- Brier/ECE remain null below 30 probability-bearing outcomes or 10 signal dates;
- direction-score bucket monotonicity is reported, not assumed.
- strategy performance groups by primaryStrategyId only; supporting strategies contribute co-occurrence counts but never duplicate wins or returns.

- [ ] **Step 2: Implement typed results**

Create DecisionStatisticsFilter, DecisionStatisticsSummary, DecisionBucketStatistics, and DecisionCalibrationQuality. Avoid Map<String, dynamic> in public APIs.

- [ ] **Step 3: Implement aggregation**

Coverage is evaluated / (evaluated + invalid + matured-but-still-pending). Future not-yet-due outcomes do not reduce coverage. Calculate Brier/ECE only from stored predicted_probability values.

- [ ] **Step 4: Run and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_statistics_test.dart test/calibration_metrics_test.dart
git add mobile/lib/analysis/decision_statistics.dart mobile/test/decision_statistics_test.dart
git commit -m "feat: aggregate decision performance statistics"
~~~

### Task 6: Keep Automatic Weight Optimization Out Of The New Model

**Files:**

- Modify: mobile/lib/analysis/weight_optimizer.dart only if a shared caller would otherwise consume new rows
- Test: mobile/test/decision_statistics_test.dart

- [ ] **Step 1: Add an isolation assertion**

Verify new decision statistics and calibration services never query recommendation_tracking and never instantiate WeightOptimizer.

- [ ] **Step 2: Keep legacy behavior explicitly scoped**

Do not delete WeightOptimizer. Add a documentation comment that it is legacy-only and ensure no new-model import references it.

- [ ] **Step 3: Run legacy optimizer tests**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/recommendation_tracker_test.dart
~~~

Expected: PASS.

- [ ] **Step 4: Commit only if production code changed**

~~~powershell
git add mobile/lib/analysis/weight_optimizer.dart
git commit -m "docs: mark weight optimizer as legacy only"
~~~

Skip the commit when no production edit is needed.

### Task 7: Verify Calibration Plan

- [ ] **Step 1: Format changed files**

Run dart format on calibration_metrics.dart, decision_calibrator.dart, decision_calibration_service.dart, decision_statistics.dart, database_service.dart, the three integration callers, and all new tests.

- [ ] **Step 2: Run focused tests**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/calibration_metrics_test.dart test/decision_calibrator_test.dart test/decision_calibration_service_test.dart test/decision_statistics_test.dart test/decision_statistics_db_test.dart
~~~

Expected: all PASS.

- [ ] **Step 3: Run tracking and core regressions**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_tracker_test.dart test/decision_tracking_integration_test.dart test/short_term_decision_engine_test.dart test/signal_engine_short_term_test.dart
~~~

Expected: all PASS.
