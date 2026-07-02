import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:stock_analyzer/analysis/limit_up_analyzer.dart';
import 'package:stock_analyzer/storage/database_service.dart';

/// limit_up_pool 表的 schema SQL（与 database_service.dart 保持一致）
const _limitUpPoolSchema = '''
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
''';

/// 创建 in-memory DB 并建 limit_up_pool 表 + 索引
Future<dynamic> _openLimitUpPoolDb() async {
  final db = await openDatabase(
    ':memory:',
    version: 1,
    onCreate: (db, v) async {
      await db.execute(_limitUpPoolSchema);
      await db.execute('CREATE INDEX idx_limit_up_pool_date ON limit_up_pool(trade_date)');
      await db.execute('CREATE INDEX idx_limit_up_pool_consec ON limit_up_pool(trade_date, consecutive_days DESC)');
    },
  );
  return db;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('limit_up_pool table', () {
    test('schema creates table with composite PK and indexes', () async {
      final db = await _openLimitUpPoolDb();

      // Verify table exists
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='limit_up_pool'");
      expect(tables, hasLength(1));

      // Verify indexes exist
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_limit_up_pool_%'");
      expect(indexes, hasLength(2));

      // Verify composite PK: same code different date OK
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

    test('LimitUpAnalysis.toMap field names overlap with schema columns', () {
      // 验证 toMap 的字段名与 limit_up_pool schema 列名重叠
      // 注：toMap 包含 schema 中没有的字段（quality, time_grade, position, signals），
      // 且缺少 schema 的必填字段（trade_date, updated_at）。
      // Task 4 的 CRUD 方法负责字段转换。
      final a = LimitUpAnalysis(
        code: '600519', name: '茅台', consecutiveDays: 3,
        qualityScore: 8.5, boardType: '一字板', sealAmount: 23000,
        price: 1689.5, changePct: 10.0, premiumProb: 0.75,
        isZhaBan: false, zhabanCount: 0, sector: '白酒',
        firstLimitTime: DateTime(2026, 6, 27, 9, 25),
      );
      final m = a.toMap();
      // 验证 toMap 包含 schema 中的核心字段（字段名一致）
      expect(m.containsKey('code'), isTrue);
      expect(m.containsKey('name'), isTrue);
      expect(m.containsKey('consecutive_days'), isTrue);
      expect(m.containsKey('quality_score'), isTrue);
      expect(m.containsKey('board_type'), isTrue);
      expect(m.containsKey('seal_amount'), isTrue);
      expect(m.containsKey('seal_rate'), isTrue);  // 修复后字段名一致
      expect(m.containsKey('price'), isTrue);
      expect(m.containsKey('change_pct'), isTrue);
      expect(m.containsKey('premium_prob'), isTrue);
      expect(m.containsKey('is_zhaban'), isTrue);
      expect(m.containsKey('zhaban_count'), isTrue);
      expect(m.containsKey('sector'), isTrue);
      expect(m.containsKey('first_limit_time'), isTrue);
    });

    test('LimitUpAnalysis.toMap can be inserted after field transformation', () async {
      // 验证 toMap 的字段（经过转换后）可以被插入到 limit_up_pool 表
      // 这模拟了 Task 4 CRUD 方法的核心逻辑：移除多余字段，补充必填字段
      final db = await _openLimitUpPoolDb();

      final a = LimitUpAnalysis(
        code: '600519', name: '茅台', consecutiveDays: 3,
        qualityScore: 8.5, boardType: '一字板', sealAmount: 23000,
        sealRate: 2.5, price: 1689.5, changePct: 10.0, premiumProb: 0.75,
        isZhaBan: false, zhabanCount: 0, sector: '白酒',
        firstLimitTime: DateTime(2026, 6, 27, 9, 25),
      );
      final m = a.toMap();

      // 转换：移除 limit_up_pool 表中不存在的字段
      final insertData = Map<String, dynamic>.from(m);
      insertData.remove('quality');
      insertData.remove('time_grade');
      insertData.remove('position');
      insertData.remove('signals');
      // 补充 schema 必填字段
      insertData['trade_date'] = '2026-06-27';
      insertData['updated_at'] = DateTime.now().millisecondsSinceEpoch;

      // 插入不应抛出异常
      await db.insert('limit_up_pool', insertData);

      final rows = await db.query('limit_up_pool');
      expect(rows, hasLength(1));
      expect(rows.first['code'], '600519');
      expect(rows.first['seal_rate'], 2.5);  // 验证 seal_rate 字段名正确
      expect(rows.first['consecutive_days'], 3);

      await db.close();
    });
  });

  group('DatabaseService limit_up_pool CRUD', () {
    late Database db;

    setUp(() async {
      DatabaseService().resetForTesting();
      db = await openDatabase(
        ':memory:',
        version: 1,
        onCreate: (db, v) async {
          await db.execute(_limitUpPoolSchema);
          await db.execute('CREATE INDEX idx_limit_up_pool_date ON limit_up_pool(trade_date)');
          await db.execute('CREATE INDEX idx_limit_up_pool_consec ON limit_up_pool(trade_date, consecutive_days DESC)');
        },
      );
      await DatabaseService().setDatabaseForTesting(db);
    });

    tearDown(() async {
      await db.close();
      DatabaseService().resetForTesting();
    });

    test('replaceLimitUpPool is full replace per trade_date', () async {
      final svc = DatabaseService();
      final date = '2026-06-27';
      final analyses = [
        LimitUpAnalysis(code: '600519', name: '茅台', consecutiveDays: 3, qualityScore: 8.5),
        LimitUpAnalysis(code: '000001', name: '平安银行', consecutiveDays: 1, qualityScore: 6.0),
      ];
      await svc.replaceLimitUpPool(analyses, date);
      final result = await svc.getLimitUpPool(tradeDate: date);
      expect(result, hasLength(2));

      // 替换为 1 条（验证全量替换）
      await svc.replaceLimitUpPool([
        LimitUpAnalysis(code: '600519', name: '茅台', consecutiveDays: 4, qualityScore: 9.0),
      ], date);
      final result2 = await svc.getLimitUpPool(tradeDate: date);
      expect(result2, hasLength(1));
      expect(result2.first.consecutiveDays, 4);
    });

    test('getLimitUpPool returns sorted by consecutive_days DESC', () async {
      final svc = DatabaseService();
      final date = '2026-06-27';
      await svc.replaceLimitUpPool([
        LimitUpAnalysis(code: '000001', name: 'A', consecutiveDays: 1, qualityScore: 5.0),
        LimitUpAnalysis(code: '600519', name: 'B', consecutiveDays: 3, qualityScore: 8.0),
        LimitUpAnalysis(code: '000002', name: 'C', consecutiveDays: 2, qualityScore: 6.0),
      ], date);
      final result = await svc.getLimitUpPool(tradeDate: date);
      expect(result.first.consecutiveDays, 3);  // 高连板在前
      expect(result.last.consecutiveDays, 1);
    });

    test('getLimitUpPoolByDate returns only that date', () async {
      final svc = DatabaseService();
      await svc.replaceLimitUpPool([
        LimitUpAnalysis(code: '600519', name: '茅台', consecutiveDays: 3),
      ], '2026-06-27');
      await svc.replaceLimitUpPool([
        LimitUpAnalysis(code: '000001', name: '平安银行', consecutiveDays: 1),
      ], '2026-06-26');

      final todayPool = await svc.getLimitUpPoolByDate('2026-06-27');
      expect(todayPool.every((a) => a.code == '600519'), isTrue);

      final yPool = await svc.getLimitUpPoolByDate('2026-06-26');
      expect(yPool.every((a) => a.code == '000001'), isTrue);
    });

    test('getLimitUpDates returns distinct dates sorted DESC', () async {
      final svc = DatabaseService();
      await svc.replaceLimitUpPool([
        LimitUpAnalysis(code: '600519', name: '茅台', consecutiveDays: 3),
      ], '2026-06-27');
      await svc.replaceLimitUpPool([
        LimitUpAnalysis(code: '000001', name: '平安银行', consecutiveDays: 1),
      ], '2026-06-26');
      await svc.replaceLimitUpPool([
        LimitUpAnalysis(code: '000002', name: '万科A', consecutiveDays: 2),
      ], '2026-06-28');

      final dates = await svc.getLimitUpDates();
      expect(dates, hasLength(3));
      expect(dates.first, '2026-06-28');  // 最新在前
      expect(dates.last, '2026-06-26');
    });

    test('replaceLimitUpPool handles empty list', () async {
      final svc = DatabaseService();
      final date = '2026-06-27';
      // 先插入 1 条
      await svc.replaceLimitUpPool([
        LimitUpAnalysis(code: '600519', name: '茅台', consecutiveDays: 3),
      ], date);
      // 用空列表替换
      await svc.replaceLimitUpPool([], date);
      final result = await svc.getLimitUpPool(tradeDate: date);
      expect(result, isEmpty);
    });
  });
}
