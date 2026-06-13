import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/stock_models.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final dbPath = path.join(documentsDirectory.path, 'stock_analysis.db');

    return await openDatabase(
      dbPath,
      version: 4,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            ALTER TABLE alerts ADD COLUMN alert_type TEXT DEFAULT '';
          ''');
          await db.execute('''
            ALTER TABLE alerts ADD COLUMN indicator_type TEXT DEFAULT '';
          ''');
        }
        if (oldVersion < 3) {
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
        }
        if (oldVersion < 4) {
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
              analyzed_at INTEGER NOT NULL
            )
          ''');
        }
      },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE watchlist (
        code TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        added_at INTEGER NOT NULL
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
        analyzed_at INTEGER NOT NULL
      )
    ''');
  }

  Future<void> addToWatchlist(String code, String name) async {
    final db = await database;
    await db.insert(
      'watchlist',
      {
        'code': code,
        'name': name,
        'added_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
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
      orderBy: 'added_at DESC',
    );

    return result.map((row) => WatchlistItem(
      code: row['code'] as String,
      name: row['name'] as String,
      addedAt: DateTime.fromMillisecondsSinceEpoch(row['added_at'] as int),
    )).toList();
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

    return result.map((row) => AlertRule(
      id: row['id'] as int,
      code: row['code'] as String,
      name: row['name'] as String,
      conditionType: row['condition_type'] as String,
      thresholdValue: row['threshold_value'] as double,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      enabled: (row['enabled'] as int) == 1,
      lastTriggeredAt: row['last_triggered_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['last_triggered_at'] as int)
          : null,
      alertType: row['alert_type'] as String? ?? '',
      indicatorType: row['indicator_type'] as String? ?? '',
    )).toList();
  }

  Future<List<AlertRule>> getEnabledAlerts() async {
    final db = await database;
    final result = await db.query(
      'alerts',
      where: 'enabled = 1',
    );

    return result.map((row) => AlertRule(
      id: row['id'] as int,
      code: row['code'] as String,
      name: row['name'] as String,
      conditionType: row['condition_type'] as String,
      thresholdValue: row['threshold_value'] as double,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      enabled: true,
      lastTriggeredAt: row['last_triggered_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['last_triggered_at'] as int)
          : null,
      alertType: row['alert_type'] as String? ?? '',
      indicatorType: row['indicator_type'] as String? ?? '',
    )).toList();
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
    final result = await db.query('archive_records', orderBy: 'archived_at DESC');
    return result.map((row) => ArchiveRecord.fromMap(row)).toList();
  }

  Future<ArchiveRecord?> getArchiveById(int id) async {
    final db = await database;
    final result = await db.query('archive_records', where: 'id = ?', whereArgs: [id], limit: 1);
    if (result.isEmpty) return null;
    return ArchiveRecord.fromMap(result.first);
  }

  Future<void> deleteArchive(int id) async {
    final db = await database;
    await db.delete('archive_records', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> closeDb() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
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
    final result = await db.rawQuery('SELECT MAX(analyzed_at) as last_time FROM explore_results');
    if (result.isNotEmpty && result.first['last_time'] != null) {
      return DateTime.fromMillisecondsSinceEpoch(result.first['last_time'] as int);
    }
    return null;
  }

  Future<void> clearExploreResults() async {
    final db = await database;
    await db.delete('explore_results');
  }
}
