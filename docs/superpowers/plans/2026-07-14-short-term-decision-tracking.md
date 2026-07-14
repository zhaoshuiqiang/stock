# Short-Term Decision Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist every new-model decision and evaluate fixed 1/3/5 trading-day outcomes with forward-adjusted prices, benchmark Alpha, executable returns, MFE/MAE, and corporate-action handling.

**Architecture:** Database v21 adds normalized decision_snapshots and decision_outcomes tables while leaving legacy archive and recommendation tables untouched. A pure evaluator consumes injected adjusted/raw stock and benchmark K-lines; DecisionTracker handles idempotent persistence and refresh orchestration.

**Tech Stack:** Dart, sqflite, sqflite_common_ffi tests, existing ApiClient and HistoryKline model.

---

## Dependencies

Complete 2026-07-14-short-term-decision-core.md first.

## File Map

Create:

- mobile/lib/storage/decision_tracking_schema.dart
- mobile/lib/analysis/decision_market_data_provider.dart
- mobile/lib/analysis/decision_outcome_evaluator.dart
- mobile/lib/analysis/decision_tracker.dart
- mobile/test/decision_tracking_models_test.dart
- mobile/test/decision_tracking_db_test.dart
- mobile/test/decision_kline_api_test.dart
- mobile/test/decision_outcome_evaluator_test.dart
- mobile/test/decision_tracker_test.dart
- mobile/test/decision_tracking_integration_test.dart

Modify:

- mobile/lib/models/stock_models.dart
- mobile/lib/storage/database_service.dart
- mobile/lib/api/api_client.dart
- mobile/lib/analysis/opportunity_engine.dart
- mobile/lib/analysis/explore_engine.dart

### Task 1: Add Typed Tracking Records

**Files:**

- Modify: mobile/lib/models/stock_models.dart
- Test: mobile/test/decision_tracking_models_test.dart

- [ ] **Step 1: Write failing model tests**

Cover DecisionOutcomeStatus pending/evaluated/invalid, nullable booleans, date text codecs, JSON component maps, primary/supporting strategy fields, signal-time predicted probability/sample/Wilson fields, snapshot toMap/fromMap, outcome toMap/fromMap, and horizon validation.

Use ISO date-only values:

~~~dart
expect(record.signalTradeDate, DateTime(2026, 7, 14));
expect(record.toMap()['signal_trade_date'], '2026-07-14');
~~~

- [ ] **Step 2: Run and verify failure**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_tracking_models_test.dart
~~~

- [ ] **Step 3: Implement records**

Add:

- DecisionSnapshotRecord
- DecisionOutcomeRecord
- DecisionEvaluationWorkItem
- DecisionOutcomeStatus

Reuse RecommendationDirection and MarketRegime from short_term_decision.dart. Store booleans as nullable 0/1 integers. Reject horizons outside 1, 3, 5 with ArgumentError.

- [ ] **Step 4: Run and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_tracking_models_test.dart test/stock_models_test.dart
git add mobile/lib/models/stock_models.dart mobile/test/decision_tracking_models_test.dart
git commit -m "feat: add decision tracking records"
~~~

### Task 2: Add Database v21 Schema And Migration

**Files:**

- Create: mobile/lib/storage/decision_tracking_schema.dart
- Modify: mobile/lib/storage/database_service.dart:33-390,392-650
- Test: mobile/test/decision_tracking_db_test.dart

- [ ] **Step 1: Write the v20-to-v21 migration test**

Create an in-memory v20 database with one archive_records row and one recommendation_tracking row. Invoke a visible-for-testing upgrade helper, then assert both legacy rows remain and the two new tables, indexes, foreign key, checks, and unique constraints exist.

- [ ] **Step 2: Run and verify failure**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_tracking_db_test.dart
~~~

- [ ] **Step 3: Create the shared schema helper**

decision_tracking_schema.dart exposes:

~~~dart
Future<void> createDecisionTrackingSchema(DatabaseExecutor db);
~~~

It executes the exact v21 schema:

~~~sql
CREATE TABLE IF NOT EXISTS decision_snapshots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  code TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  source TEXT NOT NULL,
  signal_time INTEGER NOT NULL,
  signal_trade_date TEXT NOT NULL,
  signal_price REAL NOT NULL CHECK(signal_price > 0),
  adjusted_signal_price REAL CHECK(adjusted_signal_price > 0),
  benchmark_code TEXT NOT NULL,
  sector_name TEXT NOT NULL DEFAULT '',
  direction TEXT NOT NULL CHECK(direction IN ('bullish','neutral','bearish')),
  direction_score REAL NOT NULL CHECK(direction_score BETWEEN -100 AND 100),
  trade_quality_score REAL NOT NULL CHECK(trade_quality_score BETWEEN 0 AND 100),
  risk_score REAL NOT NULL CHECK(risk_score BETWEEN 0 AND 100),
  evidence_confidence REAL NOT NULL CHECK(evidence_confidence BETWEEN 0 AND 100),
  recommendation_level TEXT NOT NULL,
  recommendation_label TEXT NOT NULL,
  legacy_score INTEGER NOT NULL CHECK(legacy_score BETWEEN 1 AND 10),
  market_regime TEXT NOT NULL CHECK(market_regime IN
    ('bullishTrend','bearishTrend','rebound','pullback','range','highVolatility','unknown')),
  market_change_pct REAL,
  model_version TEXT NOT NULL,
  primary_strategy_id TEXT,
  primary_strategy_name TEXT,
  supporting_strategy_ids_json TEXT NOT NULL DEFAULT '[]',
  direction_components_json TEXT NOT NULL DEFAULT '{}',
  quality_components_json TEXT NOT NULL DEFAULT '{}',
  risk_components_json TEXT NOT NULL DEFAULT '{}',
  data_quality_flags_json TEXT NOT NULL DEFAULT '[]',
  created_at INTEGER NOT NULL,
  UNIQUE(code, source, signal_trade_date, model_version)
);

CREATE TABLE IF NOT EXISTS decision_outcomes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  snapshot_id INTEGER NOT NULL,
  horizon INTEGER NOT NULL CHECK(horizon IN (1,3,5)),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK(status IN ('pending','evaluated','invalid')),
  due_trade_date TEXT,
  entry_trade_date TEXT,
  target_trade_date TEXT,
  deferred_trade_days INTEGER NOT NULL DEFAULT 0 CHECK(deferred_trade_days >= 0),
  evaluated_at INTEGER,
  adjusted_signal_price_used REAL,
  entry_open_price REAL,
  target_close_price REAL,
  adjusted_target_close_price REAL,
  benchmark_signal_close REAL,
  benchmark_target_close REAL,
  forecast_return REAL,
  executable_return REAL,
  benchmark_return REAL,
  alpha_return REAL,
  mfe REAL,
  mae REAL,
  raw_direction_hit INTEGER CHECK(raw_direction_hit IS NULL OR raw_direction_hit IN (0,1)),
  effective_direction_hit INTEGER CHECK(effective_direction_hit IS NULL OR effective_direction_hit IN (0,1)),
  alpha_hit INTEGER CHECK(alpha_hit IS NULL OR alpha_hit IN (0,1)),
  corporate_action_detected INTEGER CHECK(corporate_action_detected IS NULL OR corporate_action_detected IN (0,1)),
  executable_valid INTEGER CHECK(executable_valid IS NULL OR executable_valid IN (0,1)),
  executable_invalid_reason TEXT NOT NULL DEFAULT '',
  invalid_reason TEXT NOT NULL DEFAULT '',
  last_attempted_at INTEGER,
  attempt_count INTEGER NOT NULL DEFAULT 0 CHECK(attempt_count >= 0),
  predicted_probability REAL CHECK(predicted_probability BETWEEN 0 AND 1),
  predicted_sample_count INTEGER NOT NULL DEFAULT 0 CHECK(predicted_sample_count >= 0),
  predicted_wilson_lower REAL CHECK(predicted_wilson_lower BETWEEN 0 AND 1),
  predicted_wilson_upper REAL CHECK(predicted_wilson_upper BETWEEN 0 AND 1),
  prediction_created_at INTEGER,
  FOREIGN KEY(snapshot_id) REFERENCES decision_snapshots(id) ON DELETE CASCADE,
  UNIQUE(snapshot_id, horizon)
);
~~~

Also create indexes idx_decision_snapshots_trade_date, idx_decision_snapshots_filter, and idx_decision_outcomes_pending.

- [ ] **Step 4: Wire new-install and upgrade paths**

Set database version to 21. Add onConfigure PRAGMA foreign_keys=ON. Call the helper from _createTables and from if (oldVersion < 21). Add upgradeDatabaseForTesting that calls the same internal upgrade function as production.

- [ ] **Step 5: Run migration tests and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_tracking_db_test.dart test/recommendation_tracker_test.dart
git add mobile/lib/storage/decision_tracking_schema.dart mobile/lib/storage/database_service.dart mobile/test/decision_tracking_db_test.dart
git commit -m "feat: add decision tracking database schema"
~~~

### Task 3: Add Atomic CRUD And Pending Work Queries

**Files:**

- Modify: mobile/lib/storage/database_service.dart
- Test: mobile/test/decision_tracking_db_test.dart

- [ ] **Step 1: Add failing CRUD tests**

Verify:

- saveDecisionSnapshotWithOutcomes creates one snapshot and exactly three pending outcomes;
- duplicate save is idempotent;
- same code on another trade date, source, or model version is allowed;
- deleting a snapshot cascades outcomes;
- no orphan outcome remains if a transaction fails;
- pending query returns typed work items ordered by signal date.

- [ ] **Step 2: Implement transaction methods**

Add:

~~~dart
Future<int> saveDecisionSnapshotWithOutcomes(
  DecisionSnapshotRecord snapshot, {
  Map<int, CalibrationEstimate> calibrations = const {},
});
Future<DecisionSnapshotRecord?> getDecisionSnapshot(int id);
Future<List<DecisionOutcomeRecord>> getDecisionOutcomes(int snapshotId);
Future<List<DecisionEvaluationWorkItem>> getPendingDecisionWorkItems({int limit = 100});
Future<void> saveDecisionOutcome(DecisionOutcomeRecord outcome);
~~~

Insert the snapshot with ConflictAlgorithm.ignore, query the existing id on conflict, and INSERT OR IGNORE horizons 1, 3, 5 in the same transaction. Copy each signal-time CalibrationEstimate into the matching outcome predicted_* fields; missing estimates remain null and must never be backfilled after the result is known. A failed refresh increments attempt_count and last_attempted_at but never writes zero returns.

- [ ] **Step 3: Run and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_tracking_db_test.dart
git add mobile/lib/storage/database_service.dart mobile/test/decision_tracking_db_test.dart
git commit -m "feat: add atomic decision tracking CRUD"
~~~

### Task 4: Provide Strict Adjusted And Raw K-Line Sources

**Files:**

- Modify: mobile/lib/api/api_client.dart
- Create: mobile/lib/analysis/decision_market_data_provider.dart
- Test: mobile/test/decision_kline_api_test.dart

- [ ] **Step 1: Write parser and fallback tests**

Use fake HTTP payloads to verify:

- qfq requests use TDX/Tencent qfqday or EastMoney fqt=1;
- raw requests use EastMoney fqt=0;
- qfq and raw cache keys cannot collide;
- strict qfq never falls back to Sina raw history;
- returned bars are sorted and de-duplicated by date.

- [ ] **Step 2: Implement explicit ApiClient methods**

Add:

~~~dart
Future<List<HistoryKline>> getForwardAdjustedHistory(String code, {int days = 180});
Future<List<HistoryKline>> getRawHistory(String code, {int days = 180});
~~~

Reuse existing parsing helpers. Strict qfq fallback order is TDX, Tencent, EastMoney. Raw may use EastMoney then Sina.

- [ ] **Step 3: Implement injectable provider**

DecisionMarketDataProvider exposes one method returning adjusted stock, optional raw stock, and adjusted benchmark bars. Keep network calls outside DecisionOutcomeEvaluator.

- [ ] **Step 4: Run and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_kline_api_test.dart test/api_parsing_test.dart test/backtest_validation_test.dart
git add mobile/lib/api/api_client.dart mobile/lib/analysis/decision_market_data_provider.dart mobile/test/decision_kline_api_test.dart
git commit -m "feat: add strict decision kline sources"
~~~

### Task 5: Implement Pure 1/3/5 Trading-Day Evaluation

**Files:**

- Create: mobile/lib/analysis/decision_outcome_evaluator.dart
- Test: mobile/test/decision_outcome_evaluator_test.dart

- [ ] **Step 1: Write failing evaluation tests**

Add explicit fixtures for:

- weekend and holiday gaps represented only by actual benchmark bars;
- delayed refresh evaluating different historical 1/3/5 targets;
- target stock suspension and deferred evaluation;
- raw-price decline but qfq gain after a dividend;
- zero return not counted as bullish or bearish hit;
- effective hit boundaries at exactly +/-0.5%;
- bullish and bearish Alpha;
- direction-oriented MFE/MAE;
- one-price limit affecting executable validity but not forecast validity;
- missing future data remaining pending.

- [ ] **Step 2: Implement date alignment**

Sort and de-duplicate bars. Locate signal_trade_date in benchmark bars. The Nth benchmark bar after the signal date determines due_trade_date. Use the first stock bar on or after that due date as target_trade_date and record deferred_trade_days.

- [ ] **Step 3: Implement return formulas**

~~~dart
forecastReturn = (targetAdjustedClose / signalAdjustedClose - 1) * 100;
executableReturn = (targetAdjustedClose / entryAdjustedOpen - 1) * 100;
benchmarkReturn = (benchmarkTargetClose / benchmarkSignalClose - 1) * 100;
alphaReturn = forecastReturn - benchmarkReturn;
~~~

Store executableReturn as the real long-price return even for bearish decisions. Use direction-oriented values only for hit and MFE/MAE calculations.

- [ ] **Step 4: Implement corporate action and execution validity**

Set corporate_action_detected when the absolute difference between qfq and raw cumulative returns exceeds 0.5 percentage points. A one-price limit can invalidate executable return but must not invalidate forecast return.

- [ ] **Step 5: Run and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_outcome_evaluator_test.dart
git add mobile/lib/analysis/decision_outcome_evaluator.dart mobile/test/decision_outcome_evaluator_test.dart
git commit -m "feat: evaluate fixed trading-day outcomes"
~~~

### Task 6: Implement DecisionTracker

**Files:**

- Create: mobile/lib/analysis/decision_tracker.dart
- Test: mobile/test/decision_tracker_test.dart

- [ ] **Step 1: Write failing tracker tests**

Use an in-memory database and fake market-data provider. Verify all directions are saved, same-day duplicates are idempotent, the next trade date creates a new snapshot, stock/benchmark histories are loaded once per code group, one failure does not block other work, and failures never write zero outcomes.

- [ ] **Step 2: Implement snapshot capture**

DecisionTracker.capture accepts AnalysisResult, source, signalTradeDate, benchmarkCode, and sectorName. It requires shortTermDecision, converts it to DecisionSnapshotRecord, and calls saveDecisionSnapshotWithOutcomes with shortTermDecision.calibrationByHorizon.

- [ ] **Step 3: Implement pending refresh**

Group work by code and benchmark, load market data once, call the pure evaluator for each pending horizon, and save each result independently. Keep a failed item pending with attempt metadata.

- [ ] **Step 4: Run and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_tracker_test.dart test/decision_outcome_evaluator_test.dart test/decision_tracking_db_test.dart
git add mobile/lib/analysis/decision_tracker.dart mobile/test/decision_tracker_test.dart
git commit -m "feat: track all decision directions"
~~~

### Task 7: Integrate Capture Without Legacy Selection Bias

**Files:**

- Modify: mobile/lib/analysis/opportunity_engine.dart
- Modify: mobile/lib/analysis/explore_engine.dart
- Test: mobile/test/decision_tracking_integration_test.dart

- [ ] **Step 1: Write failing integration tests**

Verify opportunity/explore captures include source, modelVersion, marketRegime, benchmark, and every direction. Verify score < 6 and bearish decisions are retained. Verify legacy archive_records and recommendation_tracking rows never appear in new queries.

- [ ] **Step 2: Add explicit capture points**

Capture after a successful batch analysis at the outer engine layer, not inside generateAnalysis. Use source opportunity or explore. Keep enableAsyncSideEffects false for batch generation to prevent old RecommendationTracker duplication.

- [ ] **Step 3: Keep legacy tracking unchanged**

Do not delete recommendation_tracking or archive_records. Do not feed their rows into DecisionTracker or new statistics.

- [ ] **Step 4: Run and commit**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_tracking_integration_test.dart test/recommendation_tracker_test.dart test/archive_reliability_evaluator_test.dart test/explore_engine_short_term_test.dart
git add mobile/lib/analysis/opportunity_engine.dart mobile/lib/analysis/explore_engine.dart mobile/test/decision_tracking_integration_test.dart
git commit -m "feat: capture versioned decision snapshots"
~~~

### Task 8: Verify Tracking Plan

- [ ] **Step 1: Format all changed Dart files**

Run dart format on the model, schema, database, API, provider, evaluator, tracker, integrations, and six new test files.

- [ ] **Step 2: Run tracking tests**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/decision_tracking_models_test.dart test/decision_tracking_db_test.dart test/decision_kline_api_test.dart test/decision_outcome_evaluator_test.dart test/decision_tracker_test.dart test/decision_tracking_integration_test.dart
~~~

Expected: all PASS.

- [ ] **Step 3: Run regression tests**

~~~powershell
cd mobile
D:\flutter\bin\flutter.bat test test/recommendation_tracker_test.dart test/archive_reliability_evaluator_test.dart test/api_parsing_test.dart test/backtest_validation_test.dart
~~~

Expected: all PASS.
