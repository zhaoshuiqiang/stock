import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:stock_analyzer/models/stock_models.dart';

/// position_daily_snapshot 表 schema（与 database_service.dart 保持一致）
const _snapshotSchema = '''
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
''';

String _formatDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PortfolioSnapshot 模型', () {
    test('fromMap/toMap 往返一致', () {
      final snapshot = PortfolioSnapshot(
        id: 1,
        date: DateTime(2026, 7, 7),
        totalCost: 10000,
        totalMarketValue: 11000,
        totalPnl: 1000,
        totalPnlPct: 10.0,
        todayPnl: 200,
        todayPnlPct: 1.85,
        availableCash: 5000,
        totalAssets: 16000,
        positionsJson: '[{"code":"600519"}]',
      );

      final map = snapshot.toMap();
      final restored = PortfolioSnapshot.fromMap(map);

      expect(restored.totalCost, 10000);
      expect(restored.totalMarketValue, 11000);
      expect(restored.totalPnl, 1000);
      expect(restored.totalPnlPct, 10.0);
      expect(restored.todayPnl, 200);
      expect(restored.todayPnlPct, 1.85);
      expect(restored.availableCash, 5000);
      expect(restored.totalAssets, 16000);
      expect(restored.positionsJson, '[{"code":"600519"}]');
    });

    test('负盈亏正确处理', () {
      final snapshot = PortfolioSnapshot(
        date: DateTime(2026, 7, 7),
        totalPnl: -5000,
        totalPnlPct: -25.0,
        todayPnl: -300,
        todayPnlPct: -1.5,
      );

      final map = snapshot.toMap();
      final restored = PortfolioSnapshot.fromMap(map);

      expect(restored.totalPnl, -5000);
      expect(restored.totalPnlPct, -25.0);
      expect(restored.todayPnl, -300);
      expect(restored.todayPnlPct, -1.5);
    });

    test('snapshot_date 格式为 yyyy-MM-dd', () {
      final snapshot = PortfolioSnapshot(date: DateTime(2026, 7, 7));
      final map = snapshot.toMap();
      expect(map['snapshot_date'], '2026-07-07');
    });
  });

  group('position_daily_snapshot 表', () {
    late Database db;

    setUp(() async {
      db = await openDatabase(':memory:', version: 1,
          onCreate: (d, v) async {
        await d.execute(_snapshotSchema);
      });
    });

    tearDown(() async {
      await db.close();
    });

    test('saveDailySnapshot 按日期去重（INSERT OR REPLACE）', () async {
      final snapshot1 = PortfolioSnapshot(
          date: DateTime(2026, 7, 7), totalPnl: 1000);
      final snapshot2 = PortfolioSnapshot(
          date: DateTime(2026, 7, 7), totalPnl: 2000);

      await db.insert('position_daily_snapshot', snapshot1.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert('position_daily_snapshot', snapshot2.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);

      final result = await db.query('position_daily_snapshot',
          where: 'snapshot_date = ?',
          whereArgs: [_formatDate(DateTime(2026, 7, 7))]);

      expect(result.length, 1);
      expect(result.first['total_pnl'], 2000);
    });

    test('getSnapshots 日期范围过滤', () async {
      await db.insert('position_daily_snapshot',
          PortfolioSnapshot(date: DateTime(2026, 7, 1), totalPnl: 100).toMap());
      await db.insert('position_daily_snapshot',
          PortfolioSnapshot(date: DateTime(2026, 7, 5), totalPnl: 200).toMap());
      await db.insert('position_daily_snapshot',
          PortfolioSnapshot(date: DateTime(2026, 7, 10), totalPnl: 300).toMap());

      final result = await db.query('position_daily_snapshot',
          where: 'snapshot_date >= ? AND snapshot_date <= ?',
          whereArgs: [_formatDate(DateTime(2026, 7, 3)), _formatDate(DateTime(2026, 7, 8))],
          orderBy: 'snapshot_date ASC');

      expect(result.length, 1);
      expect(result.first['total_pnl'], 200);
    });

    test('hasSnapshotForDate 准确判断', () async {
      await db.insert('position_daily_snapshot',
          PortfolioSnapshot(date: DateTime(2026, 7, 7), totalPnl: 500).toMap());

      final hasDate = await db.query('position_daily_snapshot',
          where: 'snapshot_date = ?',
          whereArgs: [_formatDate(DateTime(2026, 7, 7))],
          limit: 1);
      final noDate = await db.query('position_daily_snapshot',
          where: 'snapshot_date = ?',
          whereArgs: [_formatDate(DateTime(2026, 7, 8))],
          limit: 1);

      expect(hasDate.isNotEmpty, true);
      expect(noDate.isNotEmpty, false);
    });

    test('getSnapshotDates 返回所有日期升序', () async {
      await db.insert('position_daily_snapshot',
          PortfolioSnapshot(date: DateTime(2026, 7, 5)).toMap());
      await db.insert('position_daily_snapshot',
          PortfolioSnapshot(date: DateTime(2026, 7, 1)).toMap());

      final result = await db.query('position_daily_snapshot',
          columns: ['snapshot_date'], orderBy: 'snapshot_date ASC');

      expect(result.length, 2);
      expect(result[0]['snapshot_date'], '2026-07-01');
      expect(result[1]['snapshot_date'], '2026-07-05');
    });
  });
}
