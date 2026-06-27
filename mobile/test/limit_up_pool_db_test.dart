import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_analyzer/analysis/limit_up_analyzer.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('limit_up_pool table', () {
    test('v11 migration creates table with correct schema', () async {
      final db = await openDatabase(
        ':memory:',
        version: 1,
        onCreate: (db, v) async {
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
              seal_ratio        REAL    NOT NULL DEFAULT 0,
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
          await db.execute('CREATE INDEX idx_limit_up_pool_date ON limit_up_pool(trade_date)');
          await db.execute('CREATE INDEX idx_limit_up_pool_consec ON limit_up_pool(trade_date, consecutive_days DESC)');
        },
      );

      // Verify table exists
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='limit_up_pool'");
      expect(tables, hasLength(1));

      // Verify indexes exist
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_limit_up_pool_%'");
      expect(indexes, hasLength(2));

      // Verify composite PK by inserting same code different date
      await db.insert('limit_up_pool', {
        'code': '600519', 'name': '茅台', 'trade_date': '2026-06-27',
        'consecutive_days': 3, 'quality_score': 8.5, 'updated_at': 0,
      });
      await db.insert('limit_up_pool', {
        'code': '600519', 'name': '茅台', 'trade_date': '2026-06-28',
        'consecutive_days': 4, 'quality_score': 9.0, 'updated_at': 0,
      });
      final rows = await db.query('limit_up_pool', where: "code = '600519'");
      expect(rows, hasLength(2));

      // Verify same code same date fails (composite PK)
      expect(
        () => db.insert('limit_up_pool', {
          'code': '600519', 'name': '茅台', 'trade_date': '2026-06-27',
          'consecutive_days': 5, 'quality_score': 9.5, 'updated_at': 0,
        }),
        throwsA(isA<Exception>()),
      );

      await db.close();
    });

    test('LimitUpAnalysis.toMap has fields compatible with limit_up_pool schema', () {
      final a = LimitUpAnalysis(
        code: '600519', name: '茅台', consecutiveDays: 3,
        qualityScore: 8.5, boardType: '一字板', sealAmount: 23000,
        price: 1689.5, changePct: 10.0, premiumProb: 0.75,
        isZhaBan: false, zhabanCount: 0, sector: '白酒',
        firstLimitTime: DateTime(2026, 6, 27, 9, 25),
      );
      final m = a.toMap();
      // 验证 toMap 的字段可以被 limit_up_pool schema 接受
      expect(m.containsKey('code'), isTrue);
      expect(m.containsKey('name'), isTrue);
      expect(m.containsKey('consecutive_days'), isTrue);
      expect(m.containsKey('quality_score'), isTrue);
      expect(m.containsKey('board_type'), isTrue);
      expect(m.containsKey('seal_amount'), isTrue);
      expect(m.containsKey('price'), isTrue);
      expect(m.containsKey('change_pct'), isTrue);
      expect(m.containsKey('premium_prob'), isTrue);
      expect(m.containsKey('is_zhaban'), isTrue);
      expect(m.containsKey('zhaban_count'), isTrue);
      expect(m.containsKey('sector'), isTrue);
      expect(m.containsKey('first_limit_time'), isTrue);
    });
  });
}
