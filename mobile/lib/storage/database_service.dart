import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/stock_models.dart';
import '../models/short_term_decision.dart';
import '../analysis/limit_up_analyzer.dart';
import '../analysis/decision_statistics.dart';
import 'decision_tracking_schema.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Future<Database>? _dbFuture;

  Future<Database> get database async {
    if (_dbFuture != null) return _dbFuture!;
    _dbFuture = _initDatabase();
    return _dbFuture!;
  }

  /// 用于测试：注入 in-memory DB，绕过 path_provider
  @visibleForTesting
  Future<void> setDatabaseForTesting(Database db) async {
    _dbFuture = Future.value(db);
  }

  /// 用于测试：重置 singleton 状态
  @visibleForTesting
  void resetForTesting() {
    _dbFuture = null;
  }

  @visibleForTesting
  static Future<void> upgradeDatabaseForTesting(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 21 && newVersion >= 21) {
      await db.transaction(createDecisionTrackingSchema);
    }
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final dbPath = path.join(documentsDirectory.path, 'stock_analysis.db');

    return await openDatabase(
      dbPath,
      version: 21,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await db.transaction((txn) async {
          if (oldVersion < 2) {
            await txn.execute('''
              ALTER TABLE alerts ADD COLUMN alert_type TEXT DEFAULT '';
            ''');
            await txn.execute('''
              ALTER TABLE alerts ADD COLUMN indicator_type TEXT DEFAULT '';
            ''');
          }
          if (oldVersion < 3) {
            await txn.execute('''
              CREATE TABLE archive_records (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                code TEXT NOT NULL,
                name TEXT NOT NULL,
                price REAL NOT NULL,
                change_pct REAL NOT NULL,
                score INTEGER NOT NULL,
                recommendation TEXT NOT NULL,
                risk_level TEXT NOT NULL,
                buy_signal_count INTEGER NOT NULL DEFAULT 0,
                sell_signal_count INTEGER NOT NULL DEFAULT 0,
                active_strategy_count INTEGER NOT NULL DEFAULT 0,
                confluence_score INTEGER NOT NULL DEFAULT 0,
                trade_levels_json TEXT,
                top_signals TEXT DEFAULT '',
                archived_at INTEGER NOT NULL
              )
            ''');
          }
          if (oldVersion < 4) {
            await txn.execute('''
              CREATE TABLE explore_results (
                code TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                price REAL NOT NULL,
                change_pct REAL NOT NULL,
                pe REAL DEFAULT 0,
                pb REAL DEFAULT 0,
                score INTEGER NOT NULL,
                recommendation TEXT NOT NULL,
                sector TEXT DEFAULT '',
                confluence_score INTEGER DEFAULT 0,
                analyzed_at INTEGER NOT NULL
              )
            ''');
          }
          if (oldVersion < 5) {
            await txn.execute('''
              CREATE TABLE opportunity_results (
                code TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                price REAL NOT NULL,
                change_pct REAL NOT NULL,
                score INTEGER NOT NULL,
                recommendation TEXT NOT NULL,
                risk_level TEXT NOT NULL,
                buy_signal_count INTEGER NOT NULL DEFAULT 0,
                sell_signal_count INTEGER NOT NULL DEFAULT 0,
                active_strategy_count INTEGER NOT NULL DEFAULT 0,
                confluence_score INTEGER NOT NULL DEFAULT 0,
                trade_levels_json TEXT,
                top_signals TEXT DEFAULT '',
                analyzed_at INTEGER NOT NULL
              )
            ''');
            await txn.execute('''
              CREATE TABLE sector_pick_results (
                code TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                recommendation TEXT NOT NULL,
                score INTEGER NOT NULL,
                sector TEXT NOT NULL,
                analyzed_at INTEGER NOT NULL
              )
            ''');
          }
          if (oldVersion < 6) {
            await txn.execute('''
              CREATE TABLE home_cache (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at INTEGER NOT NULL
              )
            ''');
          }
          if (oldVersion < 7) {
            await txn.execute('''
              ALTER TABLE watchlist ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0
            ''');
          }
          if (oldVersion < 8) {
            // Phase 2: 概念标签
            await txn.execute('''
              ALTER TABLE explore_results ADD COLUMN concept_summary TEXT DEFAULT ''
            ''');
            await txn.execute('''
              ALTER TABLE explore_results ADD COLUMN day5_return REAL
            ''');
            await txn.execute('''
              ALTER TABLE explore_results ADD COLUMN day10_return REAL
            ''');
            await txn.execute('''
              ALTER TABLE explore_results ADD COLUMN day20_return REAL
            ''');
            await txn.execute('''
              ALTER TABLE explore_results ADD COLUMN market_structure TEXT DEFAULT ''
            ''');
            // Phase 3: 推荐收益追踪
            await txn.execute('''
              CREATE TABLE recommendation_tracking (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                code TEXT NOT NULL,
                name TEXT NOT NULL,
                signal_price REAL NOT NULL,
                signal_date INTEGER NOT NULL,
                market_structure TEXT DEFAULT '',
                strategy TEXT DEFAULT '',
                concept_tags TEXT DEFAULT '',
                day5_price REAL,
                day5_return REAL,
                day10_price REAL,
                day10_return REAL,
                day20_price REAL,
                day20_return REAL,
                last_checked_date INTEGER,
                is_closed INTEGER DEFAULT 0
              )
            ''');
          }
          if (oldVersion < 9) {
            // v2.33: 持仓管理
            await txn.execute('''
              CREATE TABLE positions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                code TEXT NOT NULL,
                name TEXT NOT NULL,
                quantity INTEGER NOT NULL DEFAULT 0,
                avg_price REAL NOT NULL DEFAULT 0,
                buy_date INTEGER,
                notes TEXT DEFAULT '',
                created_at INTEGER NOT NULL
              )
            ''');
            await txn
                .execute('CREATE INDEX idx_positions_code ON positions(code)');
          }
          if (oldVersion < 10) {
            // v2.33: sector_pick_results 增加主线轮动字段
            await txn.execute(
              'ALTER TABLE sector_pick_results ADD COLUMN mainLine INTEGER NOT NULL DEFAULT 0',
            );
            await txn.execute(
              'ALTER TABLE sector_pick_results ADD COLUMN bonus REAL NOT NULL DEFAULT 1.0',
            );
            await txn.execute(
              'ALTER TABLE sector_pick_results ADD COLUMN originalScore INTEGER',
            );
            await txn.execute(
              'ALTER TABLE sector_pick_results ADD COLUMN sectorCode TEXT NOT NULL DEFAULT \'\'',
            );
          }
          if (oldVersion < 11) {
            // v2.34: 打板梯队池（情绪温度计 + 连板分组）
            // 注：此处建表不含 time_grade/quality/position，由 v13 干净重建统一补齐
            await txn.execute('''
              CREATE TABLE limit_up_pool (
                code              TEXT    NOT NULL,
                name              TEXT    NOT NULL,
                trade_date        TEXT    NOT NULL,
                limit_up_price    REAL    NOT NULL DEFAULT 0,
                first_limit_time  INTEGER,
                last_limit_time   INTEGER,
                consecutive_days  INTEGER NOT NULL DEFAULT 1,
                board_type        TEXT    NOT NULL DEFAULT '',
                seal_amount       REAL    NOT NULL DEFAULT 0,
                seal_rate         REAL    NOT NULL DEFAULT 0,
                volume_ratio      REAL    NOT NULL DEFAULT 0,
                turnover_rate     REAL    NOT NULL DEFAULT 0,
                is_zhaban         INTEGER NOT NULL DEFAULT 0,
                zhaban_count      INTEGER NOT NULL DEFAULT 0,
                sector            TEXT,
                quality_score     REAL    NOT NULL DEFAULT 0,
                premium_prob      REAL    NOT NULL DEFAULT 0,
                price             REAL    NOT NULL DEFAULT 0,
                change_pct        REAL    NOT NULL DEFAULT 0,
                updated_at        INTEGER NOT NULL,
                PRIMARY KEY (code, trade_date)
              )
            ''');
            await txn.execute(
                'CREATE INDEX idx_limit_up_pool_date ON limit_up_pool(trade_date)');
            await txn.execute(
                'CREATE INDEX idx_limit_up_pool_consec ON limit_up_pool(trade_date, consecutive_days DESC)');
            debugPrint('[DB] v10→v11: created limit_up_pool table');
          }
          if (oldVersion < 13) {
            // v2.35: 干净重建 limit_up_pool 表，修复 v12 migration 重复列问题
            await txn.execute('DROP TABLE IF EXISTS limit_up_pool');
            await txn.execute('''
              CREATE TABLE limit_up_pool (
                code              TEXT    NOT NULL,
                name              TEXT    NOT NULL,
                trade_date        TEXT    NOT NULL,
                limit_up_price    REAL    NOT NULL DEFAULT 0,
                first_limit_time  INTEGER,
                last_limit_time   INTEGER,
                consecutive_days  INTEGER NOT NULL DEFAULT 1,
                board_type        TEXT    NOT NULL DEFAULT '',
                seal_amount       REAL    NOT NULL DEFAULT 0,
                seal_rate         REAL    NOT NULL DEFAULT 0,
                volume_ratio      REAL    NOT NULL DEFAULT 0,
                turnover_rate     REAL    NOT NULL DEFAULT 0,
                is_zhaban         INTEGER NOT NULL DEFAULT 0,
                zhaban_count      INTEGER NOT NULL DEFAULT 0,
                sector            TEXT,
                quality_score     REAL    NOT NULL DEFAULT 0,
                premium_prob      REAL    NOT NULL DEFAULT 0,
                price             REAL    NOT NULL DEFAULT 0,
                change_pct        REAL    NOT NULL DEFAULT 0,
                time_grade        TEXT    NOT NULL DEFAULT '未知',
                quality           TEXT    NOT NULL DEFAULT '一般',
                position          TEXT    NOT NULL DEFAULT '',
                updated_at        INTEGER NOT NULL,
                PRIMARY KEY (code, trade_date)
              )
            ''');
            await txn.execute(
                'CREATE INDEX idx_limit_up_pool_date ON limit_up_pool(trade_date)');
            await txn.execute(
                'CREATE INDEX idx_limit_up_pool_consec ON limit_up_pool(trade_date, consecutive_days DESC)');
            await txn.execute(
                'CREATE INDEX idx_limit_up_pool_code ON limit_up_pool(code)');
            debugPrint(
                '[DB] v12→v13: rebuilt limit_up_pool table with all columns');
          }
          if (oldVersion < 14) {
            // v2.53: AI决策反馈闭环 — 增加反思存储和Alpha计算字段
            await txn.execute('''
              ALTER TABLE recommendation_tracking ADD COLUMN reflection TEXT DEFAULT ''
            ''');
            await txn.execute('''
              ALTER TABLE recommendation_tracking ADD COLUMN alpha_vs_market REAL
            ''');
            await txn.execute('''
              ALTER TABLE recommendation_tracking ADD COLUMN confidence_adjustment TEXT DEFAULT ''
            ''');
            debugPrint(
                '[DB] v13→v14: added reflection/alpha/confidence_adjustment columns');
          }
          if (oldVersion < 15) {
            // v3.0: 持仓增加浮动盈亏、盈亏比例、市值字段
            await txn.execute('''
              ALTER TABLE positions ADD COLUMN float_pnl REAL NOT NULL DEFAULT 0
            ''');
            await txn.execute('''
              ALTER TABLE positions ADD COLUMN pnl_pct REAL NOT NULL DEFAULT 0
            ''');
            await txn.execute('''
              ALTER TABLE positions ADD COLUMN market_value REAL NOT NULL DEFAULT 0
            ''');
            await txn.execute('''
              ALTER TABLE positions ADD COLUMN today_pnl REAL NOT NULL DEFAULT 0
            ''');
            await txn.execute('''
              ALTER TABLE positions ADD COLUMN today_pnl_pct REAL NOT NULL DEFAULT 0
            ''');
            await txn.execute('''
              ALTER TABLE positions ADD COLUMN latest_price REAL NOT NULL DEFAULT 0
            ''');
            debugPrint(
                '[DB] v14→v15: added float_pnl/pnl_pct/market_value/today_pnl columns to positions');
          }
          if (oldVersion < 16) {
            // v3.1: 持仓每日快照表（收益率趋势图数据源）
            await txn.execute('''
              CREATE TABLE position_daily_snapshot (
                id                  INTEGER PRIMARY KEY AUTOINCREMENT,
                snapshot_date       TEXT    NOT NULL UNIQUE,
                total_cost          REAL    NOT NULL DEFAULT 0,
                total_market_value  REAL    NOT NULL DEFAULT 0,
                total_pnl           REAL    NOT NULL DEFAULT 0,
                total_pnl_pct       REAL    NOT NULL DEFAULT 0,
                today_pnl           REAL    NOT NULL DEFAULT 0,
                today_pnl_pct       REAL    NOT NULL DEFAULT 0,
                available_cash      REAL    NOT NULL DEFAULT 0,
                total_assets        REAL    NOT NULL DEFAULT 0,
                positions_json      TEXT    DEFAULT '',
                created_at          INTEGER NOT NULL
              )
            ''');
            await txn.execute(
                'CREATE INDEX idx_snapshot_date ON position_daily_snapshot(snapshot_date)');
            debugPrint('[DB] v15→v16: created position_daily_snapshot table');
          }
          if (oldVersion < 17) {
            // v3.2: 推荐追踪表增加维度评分JSON字段（用于动态权重优化）
            await txn.execute(
                "ALTER TABLE recommendation_tracking ADD COLUMN dimension_scores_json TEXT DEFAULT ''");
            debugPrint(
                '[DB] v16→v17: added dimension_scores_json column to recommendation_tracking');
          }
          if (oldVersion < 18) {
            // v3.2: 推荐反馈机制 — 用户可对推荐结果给出好评/差评
            await txn.execute(
                "ALTER TABLE recommendation_tracking ADD COLUMN feedback TEXT DEFAULT ''");
          }
          if (oldVersion < 19) {
            // v3.10: 情绪温度计结果持久化（启动时快速恢复）
            await txn.execute('''
              CREATE TABLE IF NOT EXISTS sentiment (
                id INTEGER PRIMARY KEY DEFAULT 1,
                temperature REAL NOT NULL DEFAULT 50,
                phase TEXT NOT NULL DEFAULT 'freezing',
                zhaban_rate REAL NOT NULL DEFAULT 0,
                continuation_rate REAL NOT NULL DEFAULT 0,
                seal_success_rate REAL NOT NULL DEFAULT 0,
                money_making_effect REAL NOT NULL DEFAULT 0,
                limit_up_count INTEGER NOT NULL DEFAULT 0,
                limit_down_count INTEGER NOT NULL DEFAULT 0,
                continuation_height INTEGER NOT NULL DEFAULT 0,
                signals TEXT NOT NULL DEFAULT '[]',
                timestamp INTEGER NOT NULL
              )
            ''');
          }
          if (oldVersion < 20) {
            await txn.execute(
                "ALTER TABLE recommendation_tracking ADD COLUMN score REAL");
          }
          if (oldVersion < 21) {
            await createDecisionTrackingSchema(txn);
          }
          // 索引补建（幂等，保证升级路径和新装路径都有）
          await txn.execute(
              'CREATE INDEX IF NOT EXISTS idx_recommendation_tracking_code ON recommendation_tracking(code)');
          await txn.execute(
              'CREATE INDEX IF NOT EXISTS idx_alerts_code ON alerts(code)');
          await txn.execute(
              'CREATE INDEX IF NOT EXISTS idx_limit_up_pool_code ON limit_up_pool(code)');
          // v3.2: 性能优化 — 为高频查询列添加索引
          await txn.execute(
              'CREATE INDEX IF NOT EXISTS idx_archive_records_code ON archive_records(code)');
          await txn.execute(
              'CREATE INDEX IF NOT EXISTS idx_archive_records_archived_at ON archive_records(archived_at)');
          await txn.execute(
              'CREATE INDEX IF NOT EXISTS idx_recommendation_tracking_date ON recommendation_tracking(signal_date)');
          await txn.execute(
              'CREATE INDEX IF NOT EXISTS idx_explore_results_score ON explore_results(score)');
        });
      },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE watchlist (
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        added_at INTEGER NOT NULL,
        is_pinned INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE alerts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        condition_type TEXT NOT NULL,
        threshold_value REAL NOT NULL,
        created_at INTEGER NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        last_triggered_at INTEGER,
        alert_type TEXT DEFAULT '',
        indicator_type TEXT DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE archive_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        change_pct REAL NOT NULL,
        score INTEGER NOT NULL,
        recommendation TEXT NOT NULL,
        risk_level TEXT NOT NULL,
        buy_signal_count INTEGER NOT NULL DEFAULT 0,
        sell_signal_count INTEGER NOT NULL DEFAULT 0,
        active_strategy_count INTEGER NOT NULL DEFAULT 0,
        confluence_score INTEGER NOT NULL DEFAULT 0,
        trade_levels_json TEXT,
        top_signals TEXT DEFAULT '',
        archived_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE explore_results (
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        change_pct REAL NOT NULL,
        pe REAL DEFAULT 0,
        pb REAL DEFAULT 0,
        score INTEGER NOT NULL,
        recommendation TEXT NOT NULL,
        sector TEXT DEFAULT '',
        confluence_score INTEGER DEFAULT 0,
        analyzed_at INTEGER NOT NULL,
        concept_summary TEXT DEFAULT '',
        day5_return REAL,
        day10_return REAL,
        day20_return REAL,
        market_structure TEXT DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE opportunity_results (
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        change_pct REAL NOT NULL,
        score INTEGER NOT NULL,
        recommendation TEXT NOT NULL,
        risk_level TEXT NOT NULL,
        buy_signal_count INTEGER NOT NULL DEFAULT 0,
        sell_signal_count INTEGER NOT NULL DEFAULT 0,
        active_strategy_count INTEGER NOT NULL DEFAULT 0,
        confluence_score INTEGER NOT NULL DEFAULT 0,
        trade_levels_json TEXT,
        top_signals TEXT DEFAULT '',
        analyzed_at INTEGER NOT NULL
      )
    ''');

    await createDecisionTrackingSchema(db);

    await db.execute('''
      CREATE TABLE sector_pick_results (
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        recommendation TEXT NOT NULL,
        score INTEGER NOT NULL,
        sector TEXT NOT NULL,
        analyzed_at INTEGER NOT NULL,
        mainLine INTEGER NOT NULL DEFAULT 0,
        bonus REAL NOT NULL DEFAULT 1.0,
        originalScore INTEGER,
        sectorCode TEXT NOT NULL DEFAULT ''
      )
    ''');

    await db.execute('''
      CREATE TABLE home_cache (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE recommendation_tracking (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        signal_price REAL NOT NULL,
        signal_date INTEGER NOT NULL,
        market_structure TEXT DEFAULT '',
        strategy TEXT DEFAULT '',
        concept_tags TEXT DEFAULT '',
        day5_price REAL,
        day5_return REAL,
        day10_price REAL,
        day10_return REAL,
        day20_price REAL,
        day20_return REAL,
        last_checked_date INTEGER,
        is_closed INTEGER DEFAULT 0,
        reflection TEXT DEFAULT '',
        alpha_vs_market REAL,
        confidence_adjustment TEXT DEFAULT '',
        dimension_scores_json TEXT DEFAULT '',
        feedback TEXT DEFAULT '',
        score REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE positions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL,
        name TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 0,
        avg_price REAL NOT NULL DEFAULT 0,
        float_pnl REAL NOT NULL DEFAULT 0,
        pnl_pct REAL NOT NULL DEFAULT 0,
        market_value REAL NOT NULL DEFAULT 0,
        today_pnl REAL NOT NULL DEFAULT 0,
        today_pnl_pct REAL NOT NULL DEFAULT 0,
        latest_price REAL NOT NULL DEFAULT 0,
        buy_date INTEGER,
        notes TEXT DEFAULT '',
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_positions_code ON positions(code)');
    await db.execute('''
      CREATE TABLE position_daily_snapshot (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        snapshot_date       TEXT    NOT NULL UNIQUE,
        total_cost          REAL    NOT NULL DEFAULT 0,
        total_market_value  REAL    NOT NULL DEFAULT 0,
        total_pnl           REAL    NOT NULL DEFAULT 0,
        total_pnl_pct       REAL    NOT NULL DEFAULT 0,
        today_pnl           REAL    NOT NULL DEFAULT 0,
        today_pnl_pct       REAL    NOT NULL DEFAULT 0,
        available_cash      REAL    NOT NULL DEFAULT 0,
        total_assets        REAL    NOT NULL DEFAULT 0,
        positions_json      TEXT    DEFAULT '',
        created_at          INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_snapshot_date ON position_daily_snapshot(snapshot_date)');
    await db.execute('''
      CREATE TABLE limit_up_pool (
        code              TEXT    NOT NULL,
        name              TEXT    NOT NULL,
        trade_date        TEXT    NOT NULL,
        limit_up_price    REAL    NOT NULL DEFAULT 0,
        first_limit_time  INTEGER,
        last_limit_time   INTEGER,
        consecutive_days  INTEGER NOT NULL DEFAULT 1,
        board_type        TEXT    NOT NULL DEFAULT '',
        seal_amount       REAL    NOT NULL DEFAULT 0,
        seal_rate         REAL    NOT NULL DEFAULT 0,
        volume_ratio      REAL    NOT NULL DEFAULT 0,
        turnover_rate     REAL    NOT NULL DEFAULT 0,
        is_zhaban         INTEGER NOT NULL DEFAULT 0,
        zhaban_count      INTEGER NOT NULL DEFAULT 0,
        sector            TEXT,
        quality_score     REAL    NOT NULL DEFAULT 0,
        premium_prob      REAL    NOT NULL DEFAULT 0,
        price             REAL    NOT NULL DEFAULT 0,
        change_pct        REAL    NOT NULL DEFAULT 0,
        time_grade        TEXT    NOT NULL DEFAULT '未知',
        quality           TEXT    NOT NULL DEFAULT '一般',
        position          TEXT    NOT NULL DEFAULT '',
        updated_at        INTEGER NOT NULL,
        PRIMARY KEY (code, trade_date)
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_limit_up_pool_date ON limit_up_pool(trade_date)');
    await db.execute(
        'CREATE INDEX idx_limit_up_pool_consec ON limit_up_pool(trade_date, consecutive_days DESC)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_limit_up_pool_code ON limit_up_pool(code)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_recommendation_tracking_code ON recommendation_tracking(code)');
    await db
        .execute('CREATE INDEX IF NOT EXISTS idx_alerts_code ON alerts(code)');
    // v3.2: 性能优化 — 为高频查询列添加索引
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_archive_records_code ON archive_records(code)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_archive_records_archived_at ON archive_records(archived_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_recommendation_tracking_date ON recommendation_tracking(signal_date)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_explore_results_score ON explore_results(score)');
    // v3.10: 情绪温度计持久化
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sentiment (
        id INTEGER PRIMARY KEY DEFAULT 1,
        temperature REAL NOT NULL DEFAULT 50,
        phase TEXT NOT NULL DEFAULT 'freezing',
        zhaban_rate REAL NOT NULL DEFAULT 0,
        continuation_rate REAL NOT NULL DEFAULT 0,
        seal_success_rate REAL NOT NULL DEFAULT 0,
        money_making_effect REAL NOT NULL DEFAULT 0,
        limit_up_count INTEGER NOT NULL DEFAULT 0,
        limit_down_count INTEGER NOT NULL DEFAULT 0,
        continuation_height INTEGER NOT NULL DEFAULT 0,
        signals TEXT NOT NULL DEFAULT '[]',
        timestamp INTEGER NOT NULL
      )
    ''');
  }

  Future<void> addToWatchlist(
    String code,
    String name, {
    bool isPinned = false,
  }) async {
    final db = await database;
    await db.insert(
      'watchlist',
      {
        'code': code,
        'name': name,
        'added_at': DateTime.now().millisecondsSinceEpoch,
        'is_pinned': isPinned ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> removeFromWatchlist(String code) async {
    final db = await database;
    await db.delete(
      'watchlist',
      where: 'code = ?',
      whereArgs: [code],
    );
  }

  Future<void> batchAddToWatchlist(List<WatchlistItem> items) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final item in items) {
        await txn.insert(
          'watchlist',
          {
            'code': item.code,
            'name': item.name,
            'added_at': item.addedAt.millisecondsSinceEpoch,
            'is_pinned': item.isPinned ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<void> batchRemoveFromWatchlist(List<String> codes) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final code in codes) {
        await txn.delete('watchlist', where: 'code = ?', whereArgs: [code]);
      }
    });
  }

  Future<void> clearWatchlist() async {
    final db = await database;
    await db.delete('watchlist');
  }

  Future<bool> isInWatchlist(String code) async {
    final db = await database;
    final result = await db.query(
      'watchlist',
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<List<WatchlistItem>> getWatchlist() async {
    final db = await database;
    final result = await db.query(
      'watchlist',
      orderBy: 'is_pinned DESC, added_at DESC',
    );

    return result
        .map((row) => WatchlistItem(
              code: row['code'] as String,
              name: row['name'] as String,
              addedAt:
                  DateTime.fromMillisecondsSinceEpoch(row['added_at'] as int),
              isPinned: (row['is_pinned'] as int) == 1,
            ))
        .toList();
  }

  Future<void> togglePin(String code, bool pinned) async {
    final db = await database;
    await db.update(
      'watchlist',
      {'is_pinned': pinned ? 1 : 0},
      where: 'code = ?',
      whereArgs: [code],
    );
  }

  Future<int> addAlert(AlertRule rule) async {
    final db = await database;
    return await db.insert(
      'alerts',
      {
        'code': rule.code,
        'name': rule.name,
        'condition_type': rule.conditionType,
        'threshold_value': rule.thresholdValue,
        'created_at': rule.createdAt.millisecondsSinceEpoch,
        'enabled': rule.enabled ? 1 : 0,
        'last_triggered_at': rule.lastTriggeredAt?.millisecondsSinceEpoch,
        'alert_type': rule.alertType,
        'indicator_type': rule.indicatorType,
      },
    );
  }

  Future<void> updateAlert(AlertRule rule) async {
    final db = await database;
    await db.update(
      'alerts',
      {
        'name': rule.name,
        'condition_type': rule.conditionType,
        'threshold_value': rule.thresholdValue,
        'enabled': rule.enabled ? 1 : 0,
        'last_triggered_at': rule.lastTriggeredAt?.millisecondsSinceEpoch,
        'alert_type': rule.alertType,
        'indicator_type': rule.indicatorType,
      },
      where: 'id = ?',
      whereArgs: [rule.id],
    );
  }

  Future<void> deleteAlert(int id) async {
    final db = await database;
    await db.delete(
      'alerts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<AlertRule>> getAlerts() async {
    final db = await database;
    final result = await db.query(
      'alerts',
      orderBy: 'created_at DESC',
    );

    return result
        .map((row) => AlertRule(
              id: row['id'] as int,
              code: row['code'] as String,
              name: row['name'] as String,
              conditionType: row['condition_type'] as String,
              thresholdValue: row['threshold_value'] as double,
              createdAt:
                  DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
              enabled: (row['enabled'] as int) == 1,
              lastTriggeredAt: row['last_triggered_at'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(
                      row['last_triggered_at'] as int)
                  : null,
              alertType: row['alert_type'] as String? ?? '',
              indicatorType: row['indicator_type'] as String? ?? '',
            ))
        .toList();
  }

  Future<List<AlertRule>> getEnabledAlerts() async {
    final db = await database;
    final result = await db.query(
      'alerts',
      where: 'enabled = 1',
    );

    return result
        .map((row) => AlertRule(
              id: row['id'] as int,
              code: row['code'] as String,
              name: row['name'] as String,
              conditionType: row['condition_type'] as String,
              thresholdValue: row['threshold_value'] as double,
              createdAt:
                  DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
              enabled: true,
              lastTriggeredAt: row['last_triggered_at'] != null
                  ? DateTime.fromMillisecondsSinceEpoch(
                      row['last_triggered_at'] as int)
                  : null,
              alertType: row['alert_type'] as String? ?? '',
              indicatorType: row['indicator_type'] as String? ?? '',
            ))
        .toList();
  }

  Future<void> updateAlertTriggerTime(int id, DateTime time) async {
    final db = await database;
    await db.update(
      'alerts',
      {'last_triggered_at': time.millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> addArchive(ArchiveRecord record) async {
    final db = await database;
    return await db.insert('archive_records', record.toMap());
  }

  Future<List<ArchiveRecord>> getArchives() async {
    final db = await database;
    final result =
        await db.query('archive_records', orderBy: 'archived_at DESC');
    return result.map((row) => ArchiveRecord.fromMap(row)).toList();
  }

  Future<ArchiveRecord?> getArchiveById(int id) async {
    final db = await database;
    final result = await db.query('archive_records',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (result.isEmpty) return null;
    return ArchiveRecord.fromMap(result.first);
  }

  Future<void> deleteArchive(int id) async {
    final db = await database;
    await db.delete('archive_records', where: 'id = ?', whereArgs: [id]);
  }

  /// v3.3: 批量删除全部留档记录（单条SQL，O(1)性能）
  Future<void> deleteAllArchives() async {
    final db = await database;
    await db.delete('archive_records');
  }

  Future<void> closeDb() async {
    if (_dbFuture != null) {
      final db = await _dbFuture!;
      await db.close();
      _dbFuture = null;
    }
  }

  // ========== 探索结果 CRUD ==========

  Future<void> replaceExploreResults(List<ExploreResult> results) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('explore_results');
      for (final r in results) {
        await txn.insert('explore_results', r.toMap());
      }
    });
  }

  Future<List<ExploreResult>> getExploreResults() async {
    final db = await database;
    final result = await db.query('explore_results', orderBy: 'score DESC');
    return result.map((row) => ExploreResult.fromMap(row)).toList();
  }

  Future<DateTime?> getExploreLastTime() async {
    final db = await database;
    final result = await db
        .rawQuery('SELECT MAX(analyzed_at) as last_time FROM explore_results');
    if (result.isNotEmpty && result.first['last_time'] != null) {
      return DateTime.fromMillisecondsSinceEpoch(
          result.first['last_time'] as int);
    }
    return null;
  }

  Future<void> clearExploreResults() async {
    final db = await database;
    await db.delete('explore_results');
  }

  // ========== 机会结果缓存 CRUD ==========

  Future<void> replaceOpportunityResults(
      List<Map<String, dynamic>> results) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('opportunity_results');
      for (final r in results) {
        await txn.insert('opportunity_results', r);
      }
    });
  }

  Future<List<Map<String, dynamic>>> getOpportunityResults() async {
    final db = await database;
    final result = await db.query('opportunity_results', orderBy: 'score DESC');
    return result;
  }

  Future<DateTime?> getOpportunityLastTime() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT MAX(analyzed_at) as last_time FROM opportunity_results');
    if (result.isNotEmpty && result.first['last_time'] != null) {
      return DateTime.fromMillisecondsSinceEpoch(
          result.first['last_time'] as int);
    }
    return null;
  }

  // ========== 板块精选结果缓存 CRUD ==========

  Future<void> replaceSectorPickResults(
      List<Map<String, dynamic>> results) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('sector_pick_results');
      for (final r in results) {
        await txn.insert('sector_pick_results', r);
      }
    });
  }

  Future<List<Map<String, dynamic>>> getSectorPickResults() async {
    final db = await database;
    final result = await db.query('sector_pick_results', orderBy: 'score DESC');
    return result;
  }

  Future<DateTime?> getSectorPickLastTime() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT MAX(analyzed_at) as last_time FROM sector_pick_results');
    if (result.isNotEmpty && result.first['last_time'] != null) {
      return DateTime.fromMillisecondsSinceEpoch(
          result.first['last_time'] as int);
    }
    return null;
  }

  // ========== 打板梯队池 CRUD (v2.34) ==========

  /// 全量替换指定交易日的打板池数据
  Future<void> replaceLimitUpPool(
      List<LimitUpAnalysis> analyses, String tradeDate) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('limit_up_pool',
          where: 'trade_date = ?', whereArgs: [tradeDate]);
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final a in analyses) {
        final m = a.toMap();
        // signals 是 List 类型，SQLite 无法直接存储
        m.remove('signals');
        // 补充 schema 必填字段
        m['trade_date'] = tradeDate;
        m['updated_at'] = now;
        await txn.insert('limit_up_pool', m);
      }
    });
  }

  /// 获取打板池数据（默认今日，可指定日期）
  Future<List<LimitUpAnalysis>> getLimitUpPool({String? tradeDate}) async {
    final db = await database;
    // 使用上海时区(UTC+8)计算默认交易日，与 replaceLimitUpPool 写入时区一致
    final date = tradeDate ??
        DateTime.now()
            .toUtc()
            .add(const Duration(hours: 8))
            .toIso8601String()
            .substring(0, 10);
    final result = await db.query(
      'limit_up_pool',
      where: 'trade_date = ?',
      whereArgs: [date],
      orderBy: 'consecutive_days DESC, seal_amount DESC',
    );
    return result.map((m) => LimitUpAnalysis.fromMap(m)).toList();
  }

  /// 获取指定交易日的打板池（历史回看用）
  Future<List<LimitUpAnalysis>> getLimitUpPoolByDate(String tradeDate) async {
    return getLimitUpPool(tradeDate: tradeDate);
  }

  /// 按股票代码查当日打板池记录（裸6位代码），无则返回 null
  Future<LimitUpAnalysis?> getLimitUpAnalysisByCode(String bareCode) async {
    final pool = await getLimitUpPool();
    for (final a in pool) {
      if (a.code == bareCode) return a;
    }
    return null;
  }

  /// 获取最近的打板池交易日列表（情绪周期曲线用）
  Future<List<String>> getLimitUpDates({int limit = 30}) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT DISTINCT trade_date FROM limit_up_pool ORDER BY trade_date DESC LIMIT ?',
      [limit],
    );
    return result.map((m) => m['trade_date'] as String).toList();
  }

  // ========== 首页缓存 CRUD ==========

  Future<void> saveHomeCache(String key, String value) async {
    final db = await database;
    await db.insert(
      'home_cache',
      {
        'key': key,
        'value': value,
        'updated_at': DateTime.now().millisecondsSinceEpoch
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getHomeCache(String key) async {
    final db = await database;
    final result = await db.query('home_cache',
        where: 'key = ?', whereArgs: [key], limit: 1);
    if (result.isNotEmpty) return result.first['value'] as String;
    return null;
  }

  Future<DateTime?> getHomeCacheTime(String key) async {
    final db = await database;
    final result = await db.query('home_cache',
        where: 'key = ?', whereArgs: [key], limit: 1);
    if (result.isNotEmpty && result.first['updated_at'] != null) {
      return DateTime.fromMillisecondsSinceEpoch(
          result.first['updated_at'] as int);
    }
    return null;
  }

  Future<void> saveMarketQuotesCache(List<QuoteData> quotes) async {
    final json = jsonEncode(quotes.map((q) => q.toJson()).toList());
    await saveHomeCache('market_quotes', json);
  }

  Future<List<QuoteData>> getMarketQuotesCache() async {
    final json = await getHomeCache('market_quotes');
    if (json == null) return [];
    final list = jsonDecode(json) as List;
    return list
        .map((e) => QuoteData.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveSectorsCache(List<SectorInfo> sectors) async {
    final json = jsonEncode(sectors.map((s) => s.toJson()).toList());
    await saveHomeCache('hot_sectors', json);
  }

  Future<List<SectorInfo>> getSectorsCache() async {
    final json = await getHomeCache('hot_sectors');
    if (json == null) return [];
    final list = jsonDecode(json) as List;
    return list
        .map((e) => SectorInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ========== 推荐收益追踪 CRUD ==========

  Future<void> insertRecommendationSnapshot(
      Map<String, dynamic> snapshot) async {
    final db = await database;
    await db.insert('recommendation_tracking', snapshot);
  }

  /// 获取所有活跃推荐（is_closed = 0）的 code 集合，用于批量去重
  Future<Set<String>> getActiveRecommendationCodes() async {
    final db = await database;
    final rows = await db.query(
      'recommendation_tracking',
      columns: ['code'],
      where: 'is_closed = 0',
    );
    return rows.map((r) => r['code'] as String).toSet();
  }

  /// 批量插入推荐快照（事务包裹，提升并发性能）
  Future<void> batchInsertRecommendationSnapshots(
      List<Map<String, dynamic>> snapshots) async {
    if (snapshots.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final snapshot in snapshots) {
        await txn.insert('recommendation_tracking', snapshot);
      }
    });
  }

  Future<void> updateRecommendationReturn(
      int id, int days, double price, double returnPct) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (days == 5) {
      await db.update(
          'recommendation_tracking',
          {
            'day5_price': price,
            'day5_return': returnPct,
            'last_checked_date': now
          },
          where: 'id = ?',
          whereArgs: [id]);
    } else if (days == 10) {
      await db.update(
          'recommendation_tracking',
          {
            'day10_price': price,
            'day10_return': returnPct,
            'last_checked_date': now
          },
          where: 'id = ?',
          whereArgs: [id]);
    } else if (days == 20) {
      await db.update(
          'recommendation_tracking',
          {
            'day20_price': price,
            'day20_return': returnPct,
            'last_checked_date': now
          },
          where: 'id = ?',
          whereArgs: [id]);
    }
  }

  Future<List<Map<String, dynamic>>> getRecentRecommendations(
      {int limit = 50}) async {
    final db = await database;
    return db.query('recommendation_tracking',
        orderBy: 'signal_date DESC', limit: limit);
  }

  Future<Map<String, dynamic>?> getRecommendationByCode(String code) async {
    final db = await database;
    final results = await db.query('recommendation_tracking',
        where: 'code = ? AND is_closed = 0',
        whereArgs: [code],
        orderBy: 'signal_date DESC',
        limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<void> closeRecommendation(int id) async {
    final db = await database;
    await db.update('recommendation_tracking', {'is_closed': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  /// v3.2: 用户反馈 — 更新推荐的可信度评价
  /// [feedback] 值为 'helpful' / 'not_helpful' / '' (清除)
  Future<void> updateRecommendationFeedback(int id, String feedback) async {
    final db = await database;
    await db.update('recommendation_tracking', {'feedback': feedback},
        where: 'id = ?', whereArgs: [id]);
  }

  /// v3.2: 获取推荐反馈统计（用于权重优化）
  Future<Map<String, int>> getFeedbackStats() async {
    final db = await database;
    final helpful = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM recommendation_tracking WHERE feedback = 'helpful'"));
    final notHelpful = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM recommendation_tracking WHERE feedback = 'not_helpful'"));
    return {
      'helpful': helpful ?? 0,
      'not_helpful': notHelpful ?? 0,
      'total': (helpful ?? 0) + (notHelpful ?? 0),
    };
  }

  Future<void> clearOldRecommendations({int days = 90}) async {
    final db = await database;
    final cutoff =
        DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    await db.delete('recommendation_tracking',
        where: 'signal_date < ?', whereArgs: [cutoff]);
  }

  /// v3.13: 获取某只股票的历史评分趋势（最近20条记录）
  /// 返回按时间升序的 {date, score} 列表
  Future<List<Map<String, dynamic>>> getScoreTrend(String code) async {
    final db = await database;
    final rows = await db.query(
      'recommendation_tracking',
      columns: [
        'signal_date',
        'score',
        'dimension_scores_json',
        'signal_price'
      ],
      where: 'code = ?',
      whereArgs: [code],
      orderBy: 'signal_date ASC',
      limit: 20,
    );
    return rows.map((row) {
      double score = (row['score'] as num?)?.toDouble() ?? 0;
      // 兼容旧数据：score 为 null 时从 dimension_scores_json 反推
      if (score == 0) {
        final dimJson = row['dimension_scores_json'] as String?;
        if (dimJson != null && dimJson.isNotEmpty) {
          try {
            final dims = jsonDecode(dimJson) as Map<String, dynamic>;
            final total =
                dims.values.whereType<double>().fold(0.0, (a, b) => a + b);
            score = (total / dims.length).clamp(0, 10).toDouble();
          } catch (_) {}
        }
      }
      return {
        'date': DateTime.fromMillisecondsSinceEpoch(row['signal_date'] as int),
        'score': score,
      };
    }).toList();
  }

  // ========== 持仓管理 CRUD (v2.33) ==========

  Future<int> addPosition(Position position) async {
    final db = await database;
    try {
      return await db.insert('positions', position.toMap());
    } catch (e) {
      debugPrint('[DB] addPosition 失败: $e');
      // 检查表结构，自动修复缺失的列
      await _ensurePositionsColumns(db);
      return await db.insert('positions', position.toMap());
    }
  }

  /// 确保 positions 表包含所有必要列（防止升级失败导致缺列）
  Future<void> _ensurePositionsColumns(Database db) async {
    final columns = await db.rawQuery('PRAGMA table_info(positions)');
    final existing = columns.map((c) => c['name'] as String).toSet();
    debugPrint('[DB] positions 表现有列: $existing');

    const required = {
      'float_pnl': 'REAL NOT NULL DEFAULT 0',
      'pnl_pct': 'REAL NOT NULL DEFAULT 0',
      'market_value': 'REAL NOT NULL DEFAULT 0',
      'today_pnl': 'REAL NOT NULL DEFAULT 0',
      'today_pnl_pct': 'REAL NOT NULL DEFAULT 0',
      'latest_price': 'REAL NOT NULL DEFAULT 0',
    };

    for (final entry in required.entries) {
      if (!existing.contains(entry.key)) {
        debugPrint('[DB] 补建缺失列: ${entry.key}');
        await db.execute(
          'ALTER TABLE positions ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }
  }

  Future<void> updatePosition(Position position) async {
    final db = await database;
    if (position.id == null) return;
    await db.update(
      'positions',
      {
        'quantity': position.quantity,
        'avg_price': position.avgPrice,
        'float_pnl': position.floatPnl,
        'pnl_pct': position.pnlPct,
        'market_value': position.marketValue,
        'today_pnl': position.todayPnl,
        'today_pnl_pct': position.todayPnlPct,
        'latest_price': position.latestPrice,
        'buy_date': position.buyDate?.millisecondsSinceEpoch,
        'notes': position.notes,
      },
      where: 'id = ?',
      whereArgs: [position.id],
    );
  }

  Future<void> deletePosition(int id) async {
    final db = await database;
    await db.delete('positions', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllPositions() async {
    final db = await database;
    await db.delete('positions');
  }

  Future<List<Position>> getPositions() async {
    final db = await database;
    final result = await db.query('positions', orderBy: 'created_at DESC');
    return result.map((row) => Position.fromMap(row)).toList();
  }

  /// 返回 code → Position 的映射，用于自选列表 O(1) 查找持仓标记
  Future<Map<String, Position>> getPositionMap() async {
    final positions = await getPositions();
    return {for (final p in positions) p.code: p};
  }

  // ========== 持仓快照 CRUD (v3.1) ==========

  /// 保存每日快照（按日期去重，INSERT OR REPLACE）
  Future<int> saveDailySnapshot(PortfolioSnapshot snapshot) async {
    final db = await database;
    return await db.insert(
      'position_daily_snapshot',
      snapshot.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 查询指定日期范围的快照
  Future<List<PortfolioSnapshot>> getSnapshots({
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    final db = await database;
    final where = <String>[];
    final args = <dynamic>[];
    if (startDate != null) {
      where.add('snapshot_date >= ?');
      args.add(_formatSnapshotDate(startDate));
    }
    if (endDate != null) {
      where.add('snapshot_date <= ?');
      args.add(_formatSnapshotDate(endDate));
    }
    final result = await db.query(
      'position_daily_snapshot',
      where: where.isNotEmpty ? where.join(' AND ') : null,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'snapshot_date ASC',
      limit: limit,
    );
    return result.map((row) => PortfolioSnapshot.fromMap(row)).toList();
  }

  /// 检查指定日期的快照是否已存在
  Future<bool> hasSnapshotForDate(DateTime date) async {
    final db = await database;
    final result = await db.query(
      'position_daily_snapshot',
      where: 'snapshot_date = ?',
      whereArgs: [_formatSnapshotDate(date)],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// 获取所有快照日期
  Future<List<DateTime>> getSnapshotDates() async {
    final db = await database;
    final result = await db.query(
      'position_daily_snapshot',
      columns: ['snapshot_date'],
      orderBy: 'snapshot_date ASC',
    );
    return result
        .map((row) => DateTime.parse(row['snapshot_date'] as String))
        .toList();
  }

  // --- 情绪温度计持久化 (v3.10) ---

  Future<void> saveSentiment(SentimentResult sentiment) async {
    final db = await database;
    await db.insert(
      'sentiment',
      sentiment.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<SentimentResult?> getLatestSentiment() async {
    final db = await database;
    final rows = await db.query('sentiment', limit: 1);
    if (rows.isEmpty) return null;
    return SentimentResult.fromMap(rows.first);
  }

  Future<int> saveDecisionSnapshotWithOutcomes(
    DecisionSnapshotRecord snapshot, {
    Map<int, CalibrationEstimate> calibrations = const {},
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      final snapshotMap = Map<String, dynamic>.from(snapshot.toMap())
        ..remove('id');
      var snapshotId = await txn.insert(
        'decision_snapshots',
        snapshotMap,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      if (snapshotId == 0) {
        final existing = await txn.query(
          'decision_snapshots',
          columns: const ['id'],
          where:
              'code = ? AND source = ? AND signal_trade_date = ? AND model_version = ?',
          whereArgs: [
            snapshot.code,
            snapshot.source,
            snapshotMap['signal_trade_date'],
            snapshot.modelVersion,
          ],
          limit: 1,
        );
        if (existing.isEmpty) {
          throw StateError('Decision snapshot conflict could not be resolved');
        }
        snapshotId = (existing.first['id'] as num).toInt();
      }

      final predictionCreatedAt = snapshot.createdAt.millisecondsSinceEpoch;
      for (final horizon in const [1, 3, 5]) {
        final estimate = calibrations[horizon];
        await txn.insert(
          'decision_outcomes',
          {
            'snapshot_id': snapshotId,
            'horizon': horizon,
            if (estimate != null) ...{
              'predicted_probability': estimate.probability,
              'predicted_sample_count': estimate.sampleCount,
              'predicted_wilson_lower': estimate.wilsonLower,
              'predicted_wilson_upper': estimate.wilsonUpper,
              'prediction_created_at': predictionCreatedAt,
            },
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      return snapshotId;
    });
  }

  Future<DecisionSnapshotRecord?> getDecisionSnapshot(int id) async {
    final db = await database;
    final rows = await db.query(
      'decision_snapshots',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : DecisionSnapshotRecord.fromMap(rows.first);
  }

  Future<List<DecisionOutcomeRecord>> getDecisionOutcomes(
      int snapshotId) async {
    final db = await database;
    final rows = await db.query(
      'decision_outcomes',
      where: 'snapshot_id = ?',
      whereArgs: [snapshotId],
      orderBy: 'horizon ASC',
    );
    return rows.map(DecisionOutcomeRecord.fromMap).toList(growable: false);
  }

  Future<List<DecisionEvaluationWorkItem>> getPendingDecisionWorkItems({
    int limit = 100,
  }) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT o.*
      FROM decision_outcomes o
      JOIN decision_snapshots s ON s.id = o.snapshot_id
      WHERE o.status = 'pending'
      ORDER BY s.signal_trade_date ASC, o.horizon ASC
      LIMIT ?
    ''', [limit]);
    final result = <DecisionEvaluationWorkItem>[];
    for (final row in rows) {
      final outcome = DecisionOutcomeRecord.fromMap(row);
      final snapshot = await getDecisionSnapshot(outcome.snapshotId);
      if (snapshot != null) {
        result.add(DecisionEvaluationWorkItem(
          snapshot: snapshot,
          outcome: outcome,
        ));
      }
    }
    return result;
  }

  Future<void> saveDecisionOutcome(DecisionOutcomeRecord outcome) async {
    if (outcome.id == null) {
      throw ArgumentError('Decision outcome id is required for updates');
    }
    final db = await database;
    final map = Map<String, dynamic>.from(outcome.toMap())..remove('id');
    await db.update(
      'decision_outcomes',
      map,
      where: 'id = ?',
      whereArgs: [outcome.id],
    );
  }

  Future<List<DecisionCalibrationRow>> getDecisionCalibrationRows({
    required String modelVersion,
    required DateTime asOfTradeDate,
  }) async {
    final rows = await getDecisionStatisticsRows(modelVersion: modelVersion);
    final cutoff = _formatSnapshotDate(asOfTradeDate);
    return rows
        .where((row) {
          final target = row.outcome.targetTradeDate;
          return target != null &&
              _formatSnapshotDate(target).compareTo(cutoff) < 0;
        })
        .map((row) => DecisionCalibrationRow(
              modelVersion: row.snapshot.modelVersion,
              horizon: row.outcome.horizon,
              direction: row.snapshot.direction,
              directionScore: row.snapshot.directionScore,
              marketRegime: row.snapshot.marketRegime,
              signalTradeDate: row.snapshot.signalTradeDate,
              targetTradeDate: row.outcome.targetTradeDate,
              status: row.outcome.status,
              effectiveDirectionHit: row.outcome.effectiveDirectionHit,
            ))
        .toList(growable: false);
  }

  Future<List<DecisionStatisticsRow>> getDecisionStatisticsRows({
    DecisionStatisticsFilter? filter,
    int? horizon,
    RecommendationDirection? direction,
    MarketRegime? marketRegime,
    String? modelVersion,
    String? source,
    String? primaryStrategyId,
    double? minDirectionScore,
    double? maxDirectionScore,
  }) async {
    final selectedHorizon = filter?.horizon ?? horizon;
    if (selectedHorizon != null &&
        !const <int>{1, 3, 5}.contains(selectedHorizon)) {
      throw ArgumentError.value(
        selectedHorizon,
        'horizon',
        'Only 1, 3, and 5 trading-day horizons are supported.',
      );
    }
    final selectedDirection = filter?.direction ?? direction;
    final selectedMarketRegime = filter?.marketRegime ?? marketRegime;
    final selectedModelVersion = filter?.modelVersion ?? modelVersion;
    final selectedSource = filter?.source ?? source;
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];
    void add(String clause, Object? value) {
      where.add(clause);
      args.add(value);
    }

    if (selectedDirection != null) {
      add('direction = ?', selectedDirection.name);
    }
    if (selectedMarketRegime != null) {
      add('market_regime = ?', selectedMarketRegime.name);
    }
    if (selectedModelVersion != null) {
      add('model_version = ?', selectedModelVersion);
    }
    if (selectedSource != null) add('source = ?', selectedSource);
    if (primaryStrategyId != null) {
      add('primary_strategy_id = ?', primaryStrategyId);
    }
    if (minDirectionScore != null) {
      add('direction_score >= ?', minDirectionScore);
    }
    if (maxDirectionScore != null) {
      add('direction_score <= ?', maxDirectionScore);
    }
    final snapshotRows = await db.query(
      'decision_snapshots',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'signal_trade_date DESC, id DESC',
    );
    final result = <DecisionStatisticsRow>[];
    for (final snapshotMap in snapshotRows) {
      final snapshot = DecisionSnapshotRecord.fromMap(snapshotMap);
      final outcomeRows = await db.query(
        'decision_outcomes',
        where: selectedHorizon == null
            ? 'snapshot_id = ?'
            : 'snapshot_id = ? AND horizon = ?',
        whereArgs: selectedHorizon == null
            ? [snapshot.id]
            : [snapshot.id, selectedHorizon],
        orderBy: 'horizon ASC',
      );
      for (final outcomeMap in outcomeRows) {
        result.add(DecisionStatisticsRow(
          snapshot: snapshot,
          outcome: DecisionOutcomeRecord.fromMap(outcomeMap),
        ));
      }
    }
    return result;
  }

  static String _formatSnapshotDate(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}
