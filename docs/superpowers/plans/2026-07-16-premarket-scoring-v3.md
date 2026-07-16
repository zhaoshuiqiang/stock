# Premarket Scoring V3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct the short-term scoring semantics, make premarket decisions mature against the same-day close, and expose trustworthy 1/3/5-day diagnostics and filtered exports for manual model iteration.

**Architecture:** Keep `ShortTermDecisionEngine` as the only production recommendation source. Convert numeric rules and `SignalItem`s into component/family evidence before aggregation, persist capture phase and evidence date in SQLite v24, evaluate outcomes from the evidence-date anchor, and keep diagnostics/export as pure Dart transformations over typed decision rows.

**Tech Stack:** Flutter/Dart, sqflite, flutter_test, fl_chart, PowerShell release script.

---

## File map

- Create `mobile/lib/analysis/signal_evidence_classifier.dart`: assign each signal to one direction component and one independent indicator family.
- Modify `mobile/lib/analysis/signal_detector.dart`: stop boosting confidence from repeated same-indicator signals and annotate only independent same-direction component coverage.
- Modify `mobile/lib/analysis/directional_evidence_builder.dart`: normalize strength on 0..100, aggregate by family, center relative strength against the market, and report family conflicts.
- Modify `mobile/lib/analysis/market_regime_classifier.dart`: reject the all-zero fallback context while retaining a genuine flat market with breadth.
- Modify `mobile/lib/analysis/trade_quality_evaluator.dart`: make volume/price and support quality direction-aware and normalize strength on 0..100.
- Modify `mobile/lib/analysis/evidence_confidence_calculator.dart`: treat family conflict and missing critical inputs as confidence penalties only.
- Modify `mobile/lib/analysis/recommendation_policy.dart`: add the critical-data execution gate.
- Modify `mobile/lib/analysis/short_term_decision_engine.dart`: use `short-term-v3`, pass direction into quality evaluation, and carry the evidence trade date.
- Modify `mobile/lib/analysis/signal_engine.dart`: pass the last completed stock return instead of `industryRSScore` into the V3 direction path.
- Modify `mobile/lib/models/short_term_decision.dart`: persist the optional evidence trade date with the decision so batch summaries retain the original anchor.
- Modify `mobile/lib/models/stock_models.dart`: add capture phase/actionability/gates/app version/retrospective fields to snapshots with backward-compatible defaults.
- Modify `mobile/lib/analysis/trading_date_utils.dart`: classify capture phase and resolve the last completed weekday when a decision lacks a K-line evidence date.
- Modify `mobile/lib/analysis/decision_tracker.dart`: capture actual time, actual recommendation level, phase, evidence date, app version, gates, and retrospective provenance.
- Modify `mobile/lib/analysis/archive_service.dart`: mark historical recomputation as `archive_backfill` and retrospective.
- Modify `mobile/lib/storage/decision_tracking_schema.dart`: include v24 snapshot columns on fresh installs.
- Modify `mobile/lib/storage/database_service.dart`: migrate v23 to v24 and support phase/date/source/retrospective filters.
- Modify `mobile/lib/analysis/decision_outcome_evaluator.dart`: anchor premarket horizon 1 at signal day T and all forecast/benchmark/path returns at evidence day T-1.
- Modify `mobile/lib/analysis/decision_statistics.dart`: report bull/bear/balanced/neutral metrics and oriented return/Alpha with correct sample gates.
- Create `mobile/lib/analysis/decision_score_diagnostics.dart`: calculate score buckets, Spearman correlations, distribution bias, monotonicity, and readiness.
- Create `mobile/lib/widgets/decision_score_diagnostics_panel.dart`: render diagnostics without expanding the archive screen further.
- Modify `mobile/lib/widgets/decision_archive_summary.dart`: prioritize bull/bear balanced and neutral stability metrics.
- Modify `mobile/lib/widgets/decision_calibration_summary.dart`: show oriented returns and explicit 30-outcome/10-date progress.
- Modify `mobile/lib/services/decision_csv_exporter.dart`: export provenance, gates, components, and complete 1/3/5-day results.
- Modify `mobile/lib/screens/archive_screen.dart`: default to manual + premarket + latest model + horizon 1, apply one filter set to UI and export, and show detailed phase/evidence/gate data.
- Modify version files `mobile/pubspec.yaml`, `mobile/lib/core/app_version.dart`, and `mobile/lib/screens/update_log_screen.dart` for `3.31.20260716`.

### Task 1: Normalize and classify independent direction evidence

**Files:**
- Create: `mobile/lib/analysis/signal_evidence_classifier.dart`
- Modify: `mobile/lib/analysis/directional_evidence_builder.dart`
- Test: `mobile/test/signal_evidence_classifier_test.dart`
- Test: `mobile/test/directional_evidence_builder_test.dart`
- Test: `mobile/test/signal_detector_confluence_test.dart`

- [ ] **Step 1: Write classifier and production-scale strength tests**

Add tests that construct signals with production strengths and assert the public classification contract:

```dart
test('classifies Chinese volume pattern divergence and gap vocabulary', () {
  expect(classify('量价', '放量上涨').component, volumeFlowComponentKey);
  expect(classify('K线形态', '启明星').family, 'candlestick_reversal');
  expect(classify('MACD', 'MACD顶背离').family, 'macd_divergence');
  expect(classify('缺口', '向上跳空突破').family, 'gap_reversal');
});

test('strength 75 contributes more than 45 without saturation', () {
  final weak = buildWith(_signal(strength: 45));
  final strong = buildWith(_signal(strength: 75));
  expect(strong.components[trendComponentKey]!,
      greaterThan(weak.components[trendComponentKey]!));
  expect(strong.components[trendComponentKey]!, lessThan(1));
});
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```powershell
cd mobile
D:\flutter\bin\flutter.bat test test/signal_evidence_classifier_test.dart test/directional_evidence_builder_test.dart test/signal_detector_confluence_test.dart
```

Expected: FAIL because `SignalEvidenceClassifier` does not exist and strength 45/75 currently saturates through `/10`.

- [ ] **Step 3: Implement the classifier contract**

Create these public types and constants:

```dart
class SignalEvidenceClassification {
  final String component;
  final String family;
  const SignalEvidenceClassification(this.component, this.family);
}

class SignalEvidenceClassifier {
  static SignalEvidenceClassification classify(SignalItem signal) { /* deterministic token table */ }
}

class SignalConfluenceAnnotator {
  static List<SignalItem> annotate(List<SignalItem> signals) { /* component coverage only */ }
}
```

The deterministic table must map MA/ADX/MACD cross/trend BOLL to trend; RSI/KDJ/WR/CCI/BIAS/MACD divergence/candlestick/gap to reversal-momentum; and volume/OBV/fund flow/turnover/量价/资金/背离 to volume-flow. MACD divergence must be checked before the generic MACD trend rule. No ordinary signal text may enter relative-strength or next-session.

- [ ] **Step 4: Replace additive signal aggregation with family aggregation**

Represent every numeric rule and signal as this internal value:

```dart
class _EvidenceObservation {
  final String component;
  final String family;
  final double signedValue;
  final String source;
}
```

For each `(component, family)`, retain the strongest positive and strongest negative value. Use the one retained value when only one direction exists; otherwise use `(positive + negative) / 2` and add `evidence_family_conflict`. Compute each component as the arithmetic mean of its retained family values, clamped to `-1..1`.

Normalize signals exactly as:

```dart
signedValue = directionSign *
    (signal.strength / 100).clamp(0.0, 1.0) *
    durationWeight *
    (signal.confidence ?? 0.8).clamp(0.0, 1.0);
```

Split existing numeric trend/reversal/volume calculations into MA, price momentum, ADX, market structure, RSI, WR, KDJ, BIAS, volume-price, and capital-flow families so a matching `SignalItem` cannot add the same fact twice.

- [ ] **Step 5: Replace repeated-indicator confidence enhancement**

In `SignalDetector.detectSignals`, replace `_enhanceConfluenceSignals` with `SignalConfluenceAnnotator.annotate`. The annotator must preserve every signal's original confidence and set `signalCount` to the number of distinct classified components present on that signal's direction. Two MA signals therefore remain one component of coverage; MA + RSI + volume-flow signals produce coverage three. Opposite-direction signals are counted separately.

- [ ] **Step 6: Add duplicate/conflict/confluence regression tests and verify GREEN**

Cover these exact cases:

```dart
test('numeric MA and textual MA count once', () { /* same family, strongest wins */ });
test('same-family same-direction duplicates retain the strongest', () { /* 75 beats 45 */ });
test('same-family opposite evidence offsets and records conflict', () {
  expect(result.dataQualityFlags, contains('evidence_family_conflict'));
});
test('short term contribution exceeds medium and long term', () { /* 1.0 > .75 > .45 */ });
test('confidence scales otherwise identical signals', () { /* .9 > .4 */ });
test('same-indicator repeats do not raise confidence', () { /* original value retained */ });
test('signalCount reflects independent same-direction components', () { /* MA+RSI+量价 = 3 */ });
```

Run the command from Step 2. Expected: PASS.

- [ ] **Step 7: Commit the evidence unit**

```powershell
git add mobile/lib/analysis/signal_evidence_classifier.dart mobile/lib/analysis/directional_evidence_builder.dart mobile/lib/analysis/signal_detector.dart mobile/test/signal_evidence_classifier_test.dart mobile/test/directional_evidence_builder_test.dart mobile/test/signal_detector_confluence_test.dart
git commit -m "feat(scoring): normalize and deduplicate signal evidence"
```

### Task 2: Correct relative strength, market validity, quality, policy, and model identity

**Files:**
- Modify: `mobile/lib/analysis/market_regime_classifier.dart`
- Modify: `mobile/lib/analysis/trade_quality_evaluator.dart`
- Modify: `mobile/lib/analysis/evidence_confidence_calculator.dart`
- Modify: `mobile/lib/analysis/recommendation_policy.dart`
- Modify: `mobile/lib/analysis/short_term_decision_engine.dart`
- Modify: `mobile/lib/analysis/signal_engine.dart`
- Modify: `mobile/lib/models/short_term_decision.dart`
- Test: `mobile/test/market_regime_classifier_test.dart`
- Test: `mobile/test/trade_quality_and_risk_test.dart`
- Test: `mobile/test/recommendation_policy_test.dart`
- Test: `mobile/test/short_term_decision_engine_test.dart`
- Test: `mobile/test/short_term_decision_model_test.dart`

- [ ] **Step 1: Write failing semantic tests**

Add tests for:

```dart
expect(relativeStrength(stock: 1.2, market: 1.2), 0);
expect(relativeStrength(stock: 3.0, market: 1.0), closeTo(0.4, 1e-9));
expect(relativeStrength(stock: -2.0, market: 1.0), closeTo(-0.6, 1e-9));
```

Also prove that changing PE/PB-derived `industryRSScore` cannot change V3 direction, an all-zero/zero-breadth neutral context is invalid, a flat context with nonzero breadth remains range, bullish quality favors volume-up/price-up, bearish quality favors volume-up/price-down, neutral quality gets no directional volume reward, and critical market/history flags downgrade actionable levels.

- [ ] **Step 2: Run focused tests and verify RED**

```powershell
cd mobile
D:\flutter\bin\flutter.bat test test/market_regime_classifier_test.dart test/trade_quality_and_risk_test.dart test/recommendation_policy_test.dart test/short_term_decision_engine_test.dart test/short_term_decision_model_test.dart
```

Expected: FAIL on zero-centered relative strength, direction-aware quality, critical-data gating, and model version.

- [ ] **Step 3: Implement zero-centered stock-versus-market relative strength**

Replace the `industryRelativeStrength` decision input with `stockLastCompletedChangePct`. When market context is valid, calculate:

```dart
((stockLastCompletedChangePct - marketContext.avgChangePct) / 5)
    .clamp(-1.0, 1.0)
```

When market context is missing/invalid, return zero and keep the corresponding data-quality flag. In `signal_engine.dart`, pass `data.last.changePct`; keep `PercentileResult.industryRSScore` only in explanatory percentile output.

- [ ] **Step 4: Implement direction-aware trade quality**

Change the public call to require `RecommendationDirection direction`. Use `/100` for timing strength, count distinct signal families for the limited alignment bonus, return a neutral volume-price score for neutral direction, reward rising high-volume bars only for bullish decisions, reward falling high-volume bars only for bearish decisions, and return a neutral support/reward-risk component for bearish decisions.

- [ ] **Step 5: Implement critical-data gate and model v3 identity**

Set:

```dart
static const String modelVersion = 'short-term-v3';
```

Add `critical_data_missing` to recommendation gates whenever decision flags contain `history_data_missing`, `market_context_missing`, or `market_context_invalid`. Preserve the direction sign and downgrade actionable bull/bear recommendations to their watch level. Add optional `DateTime? evidenceTradeDate` to `ShortTermDecision`, JSON serialization, and `copyWith`; populate it from `input.data.last.date`.

- [ ] **Step 6: Run focused tests and verify GREEN**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 7: Commit the V3 scoring policy**

```powershell
git add mobile/lib/analysis/market_regime_classifier.dart mobile/lib/analysis/trade_quality_evaluator.dart mobile/lib/analysis/evidence_confidence_calculator.dart mobile/lib/analysis/recommendation_policy.dart mobile/lib/analysis/short_term_decision_engine.dart mobile/lib/analysis/signal_engine.dart mobile/lib/models/short_term_decision.dart mobile/test/market_regime_classifier_test.dart mobile/test/trade_quality_and_risk_test.dart mobile/test/recommendation_policy_test.dart mobile/test/short_term_decision_engine_test.dart mobile/test/short_term_decision_model_test.dart
git commit -m "feat(scoring): introduce short-term-v3 decision semantics"
```

### Task 3: Persist capture provenance and isolate retrospective backfill

**Files:**
- Modify: `mobile/lib/models/stock_models.dart`
- Modify: `mobile/lib/analysis/trading_date_utils.dart`
- Modify: `mobile/lib/analysis/decision_tracker.dart`
- Modify: `mobile/lib/analysis/archive_service.dart`
- Test: `mobile/test/decision_tracking_models_test.dart`
- Test: `mobile/test/decision_tracker_test.dart`
- Test: `mobile/test/archive_service_test.dart`

- [ ] **Step 1: Write failing snapshot and capture tests**

The round-trip test must assert these values survive map serialization:

```dart
evidenceTradeDate: DateTime(2026, 7, 15),
signalPhase: DecisionSignalPhase.preMarket,
actionable: true,
recommendationGates: const ['risk_above_threshold'],
appVersion: '3.31.20260716',
isRetrospective: false,
```

The tracker test must inject `capturedAt: DateTime(2026, 7, 16, 8, 45)`, prove `signalTime` equals capture time rather than quote update time, prove `recommendationLevel` stores `RecommendationDecision.level.name`, and prove a backfill row uses source `archive_backfill` with `isRetrospective == true`.

- [ ] **Step 2: Run focused tests and verify RED**

```powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_tracking_models_test.dart test/decision_tracker_test.dart test/archive_service_test.dart
```

Expected: FAIL because the provenance fields and capture-time injection do not exist and recommendation level currently stores the direction name.

- [ ] **Step 3: Add typed phase and backward-compatible snapshot fields**

Define:

```dart
enum DecisionSignalPhase { preMarket, intraday, afterClose, nonTrading, unknown }
```

Add the six v24 fields to `DecisionSnapshotRecord`. In `fromMap`, use `signal_trade_date` when `evidence_trade_date` is absent, `unknown` for phase, `false` for actionability/retrospective, an empty gate list, and an empty app version.

- [ ] **Step 4: Add deterministic capture-phase helpers**

Implement `TradingDateUtils.signalPhase(DateTime capturedAt)` with weekday handling and boundaries before 09:30, 09:30 through 15:00, and after 15:00. Implement `previousWeekday(DateTime)` for the fallback evidence date; the decision's persisted evidence date always takes precedence.

- [ ] **Step 5: Correct DecisionTracker and ArchiveService**

Extend `DecisionTracker.capture` with optional `capturedAt`, `signalPhase`, `evidenceTradeDate`, and `isRetrospective`. Resolve the recommendation through `analysis.recommendationDecision ?? RecommendationPolicy.evaluate(decision)`, store its level/label/legacy score/actionable/gates, use `AppVersion.version`, and reject capture when the resolved evidence date is absent.

For historical recomputation call:

```dart
source: 'archive_backfill',
isRetrospective: true,
```

and append `retrospective_backfill` to stored data-quality flags without mutating the original decision object.

- [ ] **Step 6: Run focused tests and verify GREEN**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 7: Commit provenance capture**

```powershell
git add mobile/lib/models/stock_models.dart mobile/lib/analysis/trading_date_utils.dart mobile/lib/analysis/decision_tracker.dart mobile/lib/analysis/archive_service.dart mobile/test/decision_tracking_models_test.dart mobile/test/decision_tracker_test.dart mobile/test/archive_service_test.dart
git commit -m "feat(tracking): persist decision phase and evidence provenance"
```

### Task 4: Upgrade SQLite to v24 and expose complete filters

**Files:**
- Modify: `mobile/lib/storage/decision_tracking_schema.dart`
- Modify: `mobile/lib/storage/database_service.dart`
- Test: `mobile/test/decision_tracking_db_test.dart`
- Test: `mobile/test/decision_statistics_db_test.dart`

- [ ] **Step 1: Write failing v23-to-v24 migration tests**

Create a legacy v23 `decision_snapshots` row, run `DatabaseService.upgradeDatabaseForTesting(db, 23, 24)`, and assert the old row remains plus these defaults:

```dart
expect(row['evidence_trade_date'], isNull);
expect(row['signal_phase'], 'unknown');
expect(row['actionable'], 0);
expect(row['recommendation_gates_json'], '[]');
expect(row['app_version'], '');
expect(row['is_retrospective'], 0);
```

Add a query test proving retrospective rows are excluded by default and included only when `includeRetrospective: true`; phase/source/date/model filters must compose with `AND` semantics.

- [ ] **Step 2: Run DB tests and verify RED**

```powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_tracking_db_test.dart test/decision_statistics_db_test.dart
```

Expected: FAIL because database version 24, columns, and filters are absent.

- [ ] **Step 3: Add schema and additive migration**

Set database version to 24. Add the six fields to fresh-install SQL and execute six guarded `ALTER TABLE` statements under `if (oldVersion < 24)`. Add an index covering `signal_phase`, `is_retrospective`, `model_version`, and `signal_trade_date`.

- [ ] **Step 4: Extend filter/query types**

Extend `DecisionStatisticsFilter` with:

```dart
final List<String>? sources;
final DecisionSignalPhase? signalPhase;
final DateTime? startTradeDate;
final DateTime? endTradeDate;
final bool includeRetrospective;
```

Default `includeRetrospective` to false. Apply each filter in `getDecisionStatisticsRows` and apply the same default exclusion in calibration row loading. Update snapshot-code lookup to accept both `archive` and `archive_backfill` so repeated backfill runs remain idempotent.

- [ ] **Step 5: Run DB tests and verify GREEN**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 6: Commit database v24**

```powershell
git add mobile/lib/storage/decision_tracking_schema.dart mobile/lib/storage/database_service.dart mobile/lib/analysis/decision_statistics.dart mobile/test/decision_tracking_db_test.dart mobile/test/decision_statistics_db_test.dart
git commit -m "feat(db): migrate decision tracking to schema v24"
```

### Task 5: Anchor premarket 1/3/5-day outcomes correctly

**Files:**
- Modify: `mobile/lib/analysis/decision_outcome_evaluator.dart`
- Test: `mobile/test/decision_outcome_evaluator_test.dart`

- [ ] **Step 1: Write failing premarket anchor tests**

Use benchmark dates T-1=`2026-07-15`, T=`2026-07-16`, T+2=`2026-07-20`. For a premarket snapshot with signal date T and evidence date T-1, assert horizon 1 targets T, forecast return starts from T-1 adjusted close, executable return starts from T open, benchmark return starts from T-1 benchmark close, and MFE/MAE include T's high/low. Assert horizon 3 targets the third benchmark trading date after T-1. Add an after-close test where evidence date equals signal date and horizon 1 targets the next trading day. Add a legacy unknown-phase test that preserves the old signal-date anchor.

- [ ] **Step 2: Run evaluator tests and verify RED**

```powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_outcome_evaluator_test.dart
```

Expected: FAIL because the evaluator currently uses `signalTradeDate + horizon` and the post-signal entry for every phase.

- [ ] **Step 3: Implement one anchor for forecast, benchmark, entry, and path**

Resolve `anchorDate = snapshot.evidenceTradeDate`. Find the anchor in the benchmark sequence and use `anchorIndex + horizon` as the due date. For premarket, the first executable stock bar is on or after `signalTradeDate`; for other phases it is strictly after the evidence date. Read the adjusted signal close from the adjusted stock series at the evidence date, not from the captured quote. Build MFE/MAE from the executable entry date through target date. Preserve pending/invalid behavior and explicit reasons when anchor/target data are unavailable.

- [ ] **Step 4: Run evaluator tests and verify GREEN**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 5: Commit outcome anchoring**

```powershell
git add mobile/lib/analysis/decision_outcome_evaluator.dart mobile/test/decision_outcome_evaluator_test.dart
git commit -m "fix(tracking): anchor premarket outcomes to same-day close"
```

### Task 6: Add balanced statistics and score diagnostics

**Files:**
- Modify: `mobile/lib/analysis/decision_statistics.dart`
- Create: `mobile/lib/analysis/decision_score_diagnostics.dart`
- Test: `mobile/test/decision_statistics_test.dart`
- Test: `mobile/test/decision_score_diagnostics_test.dart`

- [ ] **Step 1: Write failing metric tests**

Create mixed bullish/bearish/neutral evaluated rows and assert independent denominators, balanced hit `(bullHit + bearHit) / 2`, neutral stability from `abs(alphaReturn) <= 0.5`, and oriented bearish return/Alpha sign reversal. Add a calibration test with 30 outcomes but only 9 dates and one with 29 outcomes but 10 dates; both must remain ineligible.

- [ ] **Step 2: Write failing diagnostic tests**

Cover score bucket boundaries `12`, `20`, `35`, `55`, `100`; tied ranks; constant inputs; empty inputs; signed score/return correlation; five component correlations; direction bias above 70%; and monotonicity eligibility requiring 20 samples and 5 dates in both adjacent buckets.

- [ ] **Step 3: Run statistics tests and verify RED**

```powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_statistics_test.dart test/decision_score_diagnostics_test.dart
```

Expected: FAIL because split/oriented metrics and score diagnostics do not exist and calibration currently gates at 10/5.

- [ ] **Step 4: Implement split and oriented summary fields**

Keep existing raw fields for compatibility and add explicit bullish, bearish, balanced, neutral-stability, oriented-return, and oriented-Alpha fields with their sample counts. Restore Brier/ECE eligibility to:

```dart
probabilitySamples.length >= 30 && signalDates >= 10
```

- [ ] **Step 5: Implement pure diagnostic analysis**

`DecisionScoreDiagnostics.analyze(rows)` must produce bucket rows even when correlation is ineligible, return null correlations below 30 samples/10 dates, use average ranks for ties, and never emit NaN for empty/constant inputs. Correlate signed `directionScore` and signed component values with raw `forecastReturn`; use absolute score only for strength buckets.

- [ ] **Step 6: Run statistics tests and verify GREEN**

Run the command from Step 3. Expected: PASS.

- [ ] **Step 7: Commit diagnostics**

```powershell
git add mobile/lib/analysis/decision_statistics.dart mobile/lib/analysis/decision_score_diagnostics.dart mobile/test/decision_statistics_test.dart mobile/test/decision_score_diagnostics_test.dart
git commit -m "feat(archive): add balanced score diagnostics"
```

### Task 7: Make archive UI and CSV use one complete filter set

**Files:**
- Create: `mobile/lib/widgets/decision_score_diagnostics_panel.dart`
- Modify: `mobile/lib/widgets/decision_archive_summary.dart`
- Modify: `mobile/lib/widgets/decision_calibration_summary.dart`
- Modify: `mobile/lib/services/decision_csv_exporter.dart`
- Modify: `mobile/lib/screens/archive_screen.dart`
- Test: `mobile/test/archive_screen_decision_test.dart`
- Test: `mobile/test/decision_csv_exporter_test.dart`

- [ ] **Step 1: Write failing widget/export tests**

Assert the summary displays `看多命中`, `看空命中`, `多空平衡`, `中性稳定`, and `Alpha命中`. Assert the default archive state uses horizon 1, source `archive`, phase `preMarket`, model `short-term-v3`, and excludes retrospective rows. Assert the detail view displays capture time, signal/evidence dates, phase, actionable state, and gates.

For CSV, assert headers include `app_version`, `is_retrospective`, `signal_time`, `evidence_trade_date`, `signal_phase`, `actionable`, `recommendation_gates`, raw/effective/Alpha hit fields, target dates, executable validity, and complete 1/3/5 outcomes.

- [ ] **Step 2: Run UI/export tests and verify RED**

```powershell
cd mobile
D:\flutter\bin\flutter.bat test test/archive_screen_decision_test.dart test/decision_csv_exporter_test.dart
```

Expected: FAIL because the new metrics/defaults/provenance/export fields are absent.

- [ ] **Step 3: Implement the diagnostics panel and summaries**

Render compact cards/tables from `DecisionScoreDiagnostics`: direction distribution and bias warning, four score buckets, score/component Spearman eligibility, monotonicity state, and read-only optimization readiness. Use `Wrap`, horizontally scrollable tables, or constrained grids so 360px-wide screens do not overflow.

- [ ] **Step 4: Apply one filter object to list, summary, diagnostics, and export**

Initialize horizon to 1, phase to `preMarket`, model to `ShortTermDecisionEngine.modelVersion`, source group to manual archive, and retrospective to false. Load all 1/3/5 outcome rows once, derive the current-horizon view from one `DecisionStatisticsFilter`, and reuse the same snapshot filters for summary, diagnostics, detail list, readiness, and export. Export all horizons for the selected snapshots even though the page summary shows one horizon; calculate readiness from all filtered 1/3/5 rows rather than only the visible horizon.

- [ ] **Step 5: Expand detail and CSV output**

Display recommendation level/actionability/gates, capture time, phase, signal/evidence dates, five direction components, quality/risk, and each horizon target/oriented result. Change the legacy tab warning/button to `实时核对` wording. Show export success count from `buildDecisionExportRows(...).length`, not `_archives.length`.

- [ ] **Step 6: Run UI/export tests and verify GREEN**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 7: Commit archive diagnostics and export**

```powershell
git add mobile/lib/widgets/decision_score_diagnostics_panel.dart mobile/lib/widgets/decision_archive_summary.dart mobile/lib/widgets/decision_calibration_summary.dart mobile/lib/services/decision_csv_exporter.dart mobile/lib/screens/archive_screen.dart mobile/test/archive_screen_decision_test.dart mobile/test/decision_csv_exporter_test.dart
git commit -m "feat(archive): expose premarket diagnostics and filtered export"
```

### Task 8: Version, review, verification, build, and release commit

**Files:**
- Modify: `mobile/pubspec.yaml`
- Modify: `mobile/lib/core/app_version.dart`
- Modify: `mobile/lib/screens/update_log_screen.dart`
- Review: every file changed since `553f0ea`

- [ ] **Step 1: Update all release version locations**

Set the app version to `3.31.20260716` in `pubspec.yaml` and `app_version.dart`. Add an update-log entry that states: scoring strength/family correction, true stock-versus-market relative strength, premarket same-day-close evaluation, retrospective isolation, balanced diagnostics, and filtered decision CSV.

- [ ] **Step 2: Format only intentionally changed Dart files**

```powershell
cd mobile
D:\flutter\bin\dart.bat format lib/analysis/signal_evidence_classifier.dart lib/analysis/directional_evidence_builder.dart lib/analysis/signal_detector.dart lib/analysis/market_regime_classifier.dart lib/analysis/trade_quality_evaluator.dart lib/analysis/evidence_confidence_calculator.dart lib/analysis/recommendation_policy.dart lib/analysis/short_term_decision_engine.dart lib/analysis/signal_engine.dart lib/analysis/trading_date_utils.dart lib/analysis/decision_tracker.dart lib/analysis/archive_service.dart lib/analysis/decision_outcome_evaluator.dart lib/analysis/decision_statistics.dart lib/analysis/decision_score_diagnostics.dart lib/models/short_term_decision.dart lib/models/stock_models.dart lib/storage/decision_tracking_schema.dart lib/storage/database_service.dart lib/services/decision_csv_exporter.dart lib/screens/archive_screen.dart lib/screens/update_log_screen.dart lib/widgets/decision_archive_summary.dart lib/widgets/decision_calibration_summary.dart lib/widgets/decision_score_diagnostics_panel.dart test/signal_evidence_classifier_test.dart test/directional_evidence_builder_test.dart test/signal_detector_confluence_test.dart test/market_regime_classifier_test.dart test/trade_quality_and_risk_test.dart test/recommendation_policy_test.dart test/short_term_decision_engine_test.dart test/short_term_decision_model_test.dart test/decision_tracking_models_test.dart test/decision_tracker_test.dart test/archive_service_test.dart test/decision_tracking_db_test.dart test/decision_statistics_db_test.dart test/decision_outcome_evaluator_test.dart test/decision_statistics_test.dart test/decision_score_diagnostics_test.dart test/archive_screen_decision_test.dart test/decision_csv_exporter_test.dart
```

Expected: all listed files formatted; no unrelated file is touched.

- [ ] **Step 3: Perform an independent second-pass review**

Review `git diff 553f0ea --` without relying on implementation notes. Record findings with file/line references and verify: no strength divisor remains `/10` or `/3` in the V3 path; every signal maps to one component/family; PE/PB-derived score is absent from V3 direction; critical data cannot be actionable; recommendation level is not direction name; premarket h1 is T; backfill is excluded by default; migration is additive; export uses current filters; no nullable field can crash legacy rows; no UI overflow-prone fixed row was added.

- [ ] **Step 4: Fix every Critical and Important review finding with RED/GREEN tests**

For each behavior defect, add a focused failing regression test, run it to confirm the expected failure, implement the smallest fix, and rerun the focused test to pass. Do not change production behavior for a review finding without a regression test.

- [ ] **Step 5: Run focused and broad verification**

```powershell
cd mobile
D:\flutter\bin\flutter.bat test test/signal_evidence_classifier_test.dart test/directional_evidence_builder_test.dart test/market_regime_classifier_test.dart test/trade_quality_and_risk_test.dart test/recommendation_policy_test.dart test/short_term_decision_engine_test.dart test/decision_tracking_models_test.dart test/decision_tracker_test.dart test/decision_tracking_db_test.dart test/decision_outcome_evaluator_test.dart test/decision_statistics_test.dart test/decision_score_diagnostics_test.dart test/decision_csv_exporter_test.dart test/archive_screen_decision_test.dart
D:\flutter\bin\flutter.bat analyze
D:\flutter\bin\flutter.bat test
```

Expected: focused tests and full suite exit 0; analyzer has no new error in changed files. Existing repository-wide infos must be identified separately rather than silently attributed to this change.

- [ ] **Step 6: Build the release APK**

```powershell
cd ..
powershell -File mobile/build_release.ps1
Get-Item stock-v3.31.20260716.apk | Select-Object Name,Length,LastWriteTime
```

Expected: build exits 0 and `stock-v3.31.20260716.apk` exists in the repository root.

- [ ] **Step 7: Stage only release scope and commit**

Run `git status --short`, then explicitly stage the specification, plan, modified production/test/version files, and the release APK only if repository release convention tracks APKs. Do not stage `.codegraph/daemon.pid`, `stockmobile`, `android-emulator/`, archive CSVs, `new/`, diff outputs, or test output files.

```powershell
git commit -m "v3.31.20260716: 优化盘前评分与留档诊断闭环

- 修正信号强度、证据归类去重与相对强弱方向偏置
- 对齐盘前决策到当日收盘并隔离回溯补录样本
- 增加多空平衡、评分相关性、单调性和筛选导出诊断
- 升级 SQLite v24，完成全量测试与 Release APK 构建"
```

- [ ] **Step 8: Verify the release commit contents**

```powershell
git show --stat --oneline HEAD
git status --short
```

Expected: HEAD is the `v3.31.20260716` release commit; only the pre-existing unrelated dirty/untracked paths remain. Do not push unless the user separately requests it.
