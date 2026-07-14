# Short-Term Decision UI And Rollout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate decision presentation, archives, statistics, and CSV export to the new multi-dimensional and fixed-horizon model while keeping legacy records separately accessible.

**Architecture:** Pure exporters and statistics view models sit outside widgets. Quote UI reads AnalysisResult.shortTermDecision; archive and statistics screens query typed decision rows and provide a separate legacy mode. The final task bumps the app version, runs all tests, and builds the release APK.

**Tech Stack:** Flutter Material, Dart services, widget tests, existing share_plus/path_provider export flow.

---

## Dependencies

Complete core, tracking, and calibration plans first.

## File Map

Create:

- mobile/lib/services/legacy_archive_csv_exporter.dart
- mobile/lib/services/decision_csv_exporter.dart
- mobile/lib/widgets/short_term_decision_panel.dart
- mobile/lib/widgets/decision_archive_summary.dart
- mobile/lib/widgets/decision_calibration_summary.dart
- mobile/test/legacy_archive_csv_exporter_test.dart
- mobile/test/decision_csv_exporter_test.dart
- mobile/test/trading_dashboard_decision_test.dart
- mobile/test/archive_screen_decision_test.dart
- mobile/test/recommendation_stats_screen_decision_test.dart
- mobile/test/decision_ui_consistency_test.dart

Modify:

- mobile/lib/widgets/trading_dashboard.dart
- mobile/lib/widgets/analysis_result_card.dart
- mobile/lib/screens/quote_screen.dart
- mobile/lib/screens/archive_screen.dart
- mobile/lib/screens/recommendation_stats_screen.dart
- mobile/lib/screens/quant_screen.dart
- mobile/pubspec.yaml
- mobile/lib/core/app_version.dart
- mobile/lib/screens/update_log_screen.dart

### Task 1: Extract Legacy CSV Without Behavior Change

**Files:**

- Create: mobile/lib/services/legacy_archive_csv_exporter.dart
- Modify: mobile/lib/screens/archive_screen.dart:431-560
- Test: mobile/test/legacy_archive_csv_exporter_test.dart

- [ ] **Step 1: Write the failing exporter tests**

Assert the exact existing 18 headers and order, UTF-8 BOM, commas/quotes/newlines escaping, empty topSignals, and current-price/reliability fields supplied by a callback.

The test fixture must be constructed in Dart and must not read untracked CSV files.

- [ ] **Step 2: Run and verify failure**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/legacy_archive_csv_exporter_test.dart
~~~

- [ ] **Step 3: Implement the pure exporter**

Expose:

~~~dart
String buildLegacyArchiveCsv({
  required List<ArchiveRecord> records,
  required QuoteData? Function(String code) quoteOf,
  required DateTime now,
});
~~~

Move header construction, escaping, return calculation, and reliability labels out of ArchiveScreen. Preserve byte-for-byte column semantics.

- [ ] **Step 4: Delegate file writing to the existing screen flow**

ArchiveScreen keeps path_provider, share, and snackbar behavior but calls the pure exporter for content.

- [ ] **Step 5: Run and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/legacy_archive_csv_exporter_test.dart test/archive_reliability_evaluator_test.dart
git add mobile/lib/services/legacy_archive_csv_exporter.dart mobile/lib/screens/archive_screen.dart mobile/test/legacy_archive_csv_exporter_test.dart
git commit -m "refactor: extract legacy archive csv exporter"
~~~

### Task 2: Add Versioned Decision CSV

**Files:**

- Create: mobile/lib/services/decision_csv_exporter.dart
- Test: mobile/test/decision_csv_exporter_test.dart

- [ ] **Step 1: Write failing column and null tests**

Verify model/source/trade date, four scores, market state, primary/supporting strategies, five evidence components, and independent 1/3/5 status/return/Alpha/MFE/MAE columns. Pending, invalid, null calibration, and unavailable execution values must be empty or explicit status strings, never numeric zero.

- [ ] **Step 2: Implement the exporter**

~~~dart
String buildDecisionCsv(List<DecisionExportRow> rows);
~~~

Define DecisionExportRow in the same service with one DecisionSnapshotRecord and a map of horizon to DecisionOutcomeRecord. Include per-horizon predicted probability, sample count, and Wilson interval. Use a filename prefix decision_export_ so legacy scripts do not mistake it for archive_export_.

- [ ] **Step 3: Run and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_csv_exporter_test.dart
git add mobile/lib/services/decision_csv_exporter.dart mobile/test/decision_csv_exporter_test.dart
git commit -m "feat: export versioned decision outcomes"
~~~

### Task 3: Add The Reusable Four-Dimension Decision Panel

**Files:**

- Create: mobile/lib/widgets/short_term_decision_panel.dart
- Modify: mobile/lib/widgets/trading_dashboard.dart
- Modify: mobile/lib/screens/quote_screen.dart
- Test: mobile/test/trading_dashboard_decision_test.dart

- [ ] **Step 1: Write failing widget tests**

Verify:

- direction, trade quality, risk, and evidence confidence render in a stable 2x2 grid;
- evidence confidence renders as /100, not as an up probability;
- selecting 1/3/5 days displays only that horizon's CalibrationEstimate;
- no probability text appears when the selected horizon is absent;
- legacy AnalysisResult without shortTermDecision falls back to the current score/recommendation block;
- long labels do not overflow at 360px width.

- [ ] **Step 2: Implement ShortTermDecisionPanel**

Use fixed grid tracks and existing screen colors. Use icons for direction, quality, risk, and evidence. The panel receives ShortTermDecision, RecommendationDecision, selectedHorizon, and onHorizonChanged.

- [ ] **Step 3: Integrate with TradingDashboard**

Replace only the old summary area. Do not duplicate the panel inside another card. QuoteScreen continues passing AnalysisResult to TradingDashboard.

- [ ] **Step 4: Run and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/trading_dashboard_decision_test.dart
git add mobile/lib/widgets/short_term_decision_panel.dart mobile/lib/widgets/trading_dashboard.dart mobile/lib/screens/quote_screen.dart mobile/test/trading_dashboard_decision_test.dart
git commit -m "feat: show short-term decision dimensions"
~~~

### Task 4: Add Typed Archive Summary Widgets

**Files:**

- Create: mobile/lib/widgets/decision_archive_summary.dart
- Test: mobile/test/archive_screen_decision_test.dart

- [ ] **Step 1: Write failing summary tests**

Construct DecisionStatisticsSummary values and verify Alpha hit and effective hit are primary, raw hit is secondary, counts for evaluated/pending/invalid are separate, coverage is visible, and the selected horizon is included in labels.

- [ ] **Step 2: Implement the pure widget**

The widget accepts a typed summary and contains no database calls. Use compact metric cells, a segmented 1/3/5 control, and no nested cards.

- [ ] **Step 3: Run and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/archive_screen_decision_test.dart
git add mobile/lib/widgets/decision_archive_summary.dart mobile/test/archive_screen_decision_test.dart
git commit -m "feat: add decision archive summary"
~~~

### Task 5: Migrate ArchiveScreen To Dual Data Modes

**Files:**

- Modify: mobile/lib/screens/archive_screen.dart
- Modify: mobile/test/archive_screen_decision_test.dart

- [ ] **Step 1: Add failing screen-state tests**

Verify default mode is 新模型, mode switching exposes 历史口径, 1/3/5 switching reloads the correct query, direction/regime/model/source filters are passed, legacy and new totals are never added, and export uses the active mode's exporter.

- [ ] **Step 2: Add typed new-model state**

Store selected horizon, data mode, DecisionStatisticsFilter, snapshot/outcome rows, and DecisionStatisticsSummary. Load new data through DatabaseService and DecisionStatistics; keep existing _archives and quote refresh only for legacy mode.

- [ ] **Step 3: Build the new list**

Each new-model row displays signal date, source, model version, direction, four scores, selected-horizon status, return, Alpha, MFE/MAE, and calibration only when signal-time probability exists.

- [ ] **Step 4: Keep legacy evaluator isolated**

ArchiveReliabilityEvaluator remains under 历史口径 only. Do not convert legacy 偏多观望 records to the new enum.

- [ ] **Step 5: Run and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/archive_screen_decision_test.dart test/legacy_archive_csv_exporter_test.dart test/decision_csv_exporter_test.dart test/archive_reliability_evaluator_test.dart
git add mobile/lib/screens/archive_screen.dart mobile/test/archive_screen_decision_test.dart
git commit -m "feat: migrate archives to fixed-horizon decisions"
~~~

### Task 6: Migrate Recommendation Statistics

**Files:**

- Create: mobile/lib/widgets/decision_calibration_summary.dart
- Modify: mobile/lib/screens/recommendation_stats_screen.dart
- Test: mobile/test/recommendation_stats_screen_decision_test.dart

- [ ] **Step 1: Write failing widget tests**

Verify the default view reads new decision statistics and displays Wilson interval, mean/median return and Alpha, MFE/MAE, Brier/ECE availability, sample dates, monotonicity, and primary-strategy performance. Verify supporting strategies show co-occurrence only. Verify historical experiment mode still displays old RecommendationTracker/WeightOptimizer data with an explicit historical label.

- [ ] **Step 2: Implement DecisionCalibrationSummary**

Use typed DecisionStatisticsSummary and bucket values. Brier/ECE show insufficient sample instead of 0 when null.

- [ ] **Step 3: Update screen data loading**

Default queries decision_* tables. Move existing recommendation_tracking and WeightOptimizer loading behind the historical mode. Do not expose optimized weights as active production weights.

- [ ] **Step 4: Run and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/recommendation_stats_screen_decision_test.dart test/recommendation_tracker_test.dart
git add mobile/lib/widgets/decision_calibration_summary.dart mobile/lib/screens/recommendation_stats_screen.dart mobile/test/recommendation_stats_screen_decision_test.dart
git commit -m "feat: show calibrated decision statistics"
~~~

### Task 7: Audit Confidence And Probability Wording

**Files:**

- Modify: mobile/lib/widgets/analysis_result_card.dart
- Modify: mobile/lib/screens/quant_screen.dart
- Test: mobile/test/decision_ui_consistency_test.dart

- [ ] **Step 1: Write failing wording tests**

Search rendered text and verify evidenceConfidence is named 证据一致性, calibrated probability includes horizon and effective-hit wording, bearish calibration is not called 上涨概率, and legacy confidence is not displayed as a probability.

- [ ] **Step 2: Update labels**

Keep labels concise and functional. Do not add explanatory feature copy to screens.

- [ ] **Step 3: Run and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_ui_consistency_test.dart
git add mobile/lib/widgets/analysis_result_card.dart mobile/lib/screens/quant_screen.dart mobile/test/decision_ui_consistency_test.dart
git commit -m "fix: distinguish evidence confidence from probability"
~~~

### Task 8: Cross-Surface Consistency Regression

**Files:**

- Modify: mobile/test/decision_ui_consistency_test.dart

- [ ] **Step 1: Add one shared decision fixture**

Use the same bullish 3-day calibrated decision in dashboard, archive summary, statistics summary, and CSV.

- [ ] **Step 2: Assert consistent fields**

Direction, horizon, modelVersion, probability, sample count, Wilson interval, return, Alpha, MFE, and MAE must match. A missing 1-day calibration must remain absent everywhere.

- [ ] **Step 3: Run all new UI/export tests**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/trading_dashboard_decision_test.dart test/archive_screen_decision_test.dart test/recommendation_stats_screen_decision_test.dart test/legacy_archive_csv_exporter_test.dart test/decision_csv_exporter_test.dart test/decision_ui_consistency_test.dart
~~~

Expected: all PASS.

- [ ] **Step 4: Commit**

~~~powershell
git add mobile/test/decision_ui_consistency_test.dart
git commit -m "test: verify decision consistency across surfaces"
~~~

### Task 9: Version, Full Verification, And Release Build

**Files:**

- Modify: mobile/pubspec.yaml
- Modify: mobile/lib/core/app_version.dart
- Modify: mobile/lib/screens/update_log_screen.dart

- [ ] **Step 1: Set version 3.16.20260714**

Update all three version locations together. The update log entry must state unified short-term direction, separate quality/risk/evidence, fixed 1/3/5 trading-day tracking, adjusted-price evaluation, and calibrated statistics.

- [ ] **Step 2: Format intentional files**

Run dart format only on changed Dart production and test files. Review git diff for unrelated formatting churn.

- [ ] **Step 3: Run all focused suites**

Run every new test from all four plans plus signal_engine_test.dart, scoring_logic_test.dart, recommendation_tracker_test.dart, archive_reliability_evaluator_test.dart, api_parsing_test.dart, and backtest_validation_test.dart.

Expected: all PASS.

- [ ] **Step 4: Run full tests**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test
~~~

Expected: all tests PASS.

- [ ] **Step 5: Run full analysis**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat analyze
~~~

Expected: no new errors; distinguish existing repository warnings from changes.

- [ ] **Step 6: Build release APK**

~~~powershell
cd ..
powershell -File mobile/build_release.ps1
~~~

Expected: D:\MyProjects\stock\stock-v3.16.20260714.apk exists and the script reports its size.

- [ ] **Step 7: Commit release metadata**

~~~powershell
git add mobile/pubspec.yaml mobile/lib/core/app_version.dart mobile/lib/screens/update_log_screen.dart
git commit -m "v3.16.20260714: release short-term decision redesign"
~~~

Do not push unless the user explicitly requests it.
