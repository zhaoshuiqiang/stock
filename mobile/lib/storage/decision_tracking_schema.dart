import 'package:sqflite/sqflite.dart';

Future<void> createDecisionTrackingSchema(DatabaseExecutor db) async {
  await db.execute('''
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
    )
  ''');
  await db.execute('''
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
    )
  ''');
  await db
      .execute('''CREATE INDEX IF NOT EXISTS idx_decision_snapshots_trade_date
    ON decision_snapshots(signal_trade_date)''');
  await db.execute('''CREATE INDEX IF NOT EXISTS idx_decision_snapshots_filter
    ON decision_snapshots(direction, model_version, source, signal_trade_date)''');
  await db.execute('''CREATE INDEX IF NOT EXISTS idx_decision_outcomes_pending
    ON decision_outcomes(status, horizon, due_trade_date)''');
}
