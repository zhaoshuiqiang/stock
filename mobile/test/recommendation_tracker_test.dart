import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_analyzer/analysis/recommendation_tracker.dart';
import 'package:stock_analyzer/analysis/weight_optimizer.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/storage/database_service.dart';

const _recommendationTrackingSchema = '''
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
    score REAL,
    direction TEXT DEFAULT ''
  )
''';

Future<Database> _openRecommendationDb() async {
  return openDatabase(
    ':memory:',
    version: 1,
    onCreate: (db, version) async {
      await db.execute(_recommendationTrackingSchema);
      await db.execute(
        'CREATE INDEX idx_recommendation_tracking_code ON recommendation_tracking(code)',
      );
      await db.execute(
        'CREATE INDEX idx_recommendation_tracking_date ON recommendation_tracking(signal_date)',
      );
    },
  );
}

AnalysisResult _analysis({
  required String code,
  int score = 6,
  Map<String, double>? dimensionScores,
}) {
  return AnalysisResult(
    quote: QuoteData(
      code: code,
      name: '测试股$code',
      price: 10.0,
    ),
    score: score,
    recommendation: score >= 6 ? '谨慎买入' : '偏多观望',
    dimensionScores: dimensionScores,
  );
}

Future<void> _insertClosedRecommendation(
  Database db, {
  required String code,
  required DateTime signalDate,
  required double day20Return,
  required Map<String, double> dimensionScores,
}) async {
  await db.insert('recommendation_tracking', {
    'code': code,
    'name': '测试股$code',
    'signal_price': 10.0,
    'signal_date': signalDate.millisecondsSinceEpoch,
    'day20_return': day20Return,
    'is_closed': 1,
    'dimension_scores_json': jsonEncode(dimensionScores),
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;

  setUp(() async {
    DatabaseService().resetForTesting();
    db = await _openRecommendationDb();
    await DatabaseService().setDatabaseForTesting(db);
  });

  tearDown(() async {
    await db.close();
    DatabaseService().resetForTesting();
  });

  group('RecommendationTracker dimension score persistence', () {
    test('track writes dimension scores JSON for score >= 6 recommendations',
        () async {
      final tracker = RecommendationTracker();
      final dims = {
        '技术面': 7.2,
        '资金面': 6.1,
        '实时行情': 5.8,
        '共振': 6.7,
        '情绪': 5.0,
        '基本面': 4.9,
        '结构': 6.0,
      };

      final snapshot = await tracker.track(_analysis(
        code: 'sh600001',
        dimensionScores: dims,
      ));

      expect(snapshot, isNotNull);
      final rows = await db.query('recommendation_tracking');
      expect(rows, hasLength(1));

      final encoded = rows.first['dimension_scores_json'] as String;
      expect(encoded, isNotEmpty);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      expect(decoded['技术面'], 7.2);
      expect(decoded['基本面'], 4.9);
    });

    test('track does not write score < 6 recommendations', () async {
      final tracker = RecommendationTracker();

      final snapshot = await tracker.track(_analysis(
        code: 'sh600002',
        score: 5,
        dimensionScores: {'技术面': 7.0},
      ));

      expect(snapshot, isNull);
      final rows = await db.query('recommendation_tracking');
      expect(rows, isEmpty);
    });

    test('trackBatch writes dimension scores and deduplicates active codes',
        () async {
      final tracker = RecommendationTracker();
      final analyses = [
        _analysis(code: 'sh600003', dimensionScores: {'技术面': 7.0}),
        _analysis(code: 'sh600003', dimensionScores: {'技术面': 8.0}),
        _analysis(code: 'sh600004', dimensionScores: {'资金面': 6.5}),
      ];

      final snapshots = await tracker.trackBatch(analyses);

      expect(snapshots, hasLength(2));
      final rows = await db.query(
        'recommendation_tracking',
        orderBy: 'code ASC',
      );
      expect(rows.map((r) => r['code']), ['sh600003', 'sh600004']);
      expect(
          jsonDecode(rows[0]['dimension_scores_json'] as String)['技术面'], 7.0);
      expect(
          jsonDecode(rows[1]['dimension_scores_json'] as String)['资金面'], 6.5);
    });

    test('RecommendationSnapshot round-trips dimension scores from map', () {
      final snapshot = RecommendationSnapshot.fromMap({
        'id': 1,
        'code': 'sh600005',
        'name': '测试股',
        'signal_price': 10.0,
        'signal_date': DateTime(2026, 7, 9).millisecondsSinceEpoch,
        'dimension_scores_json': '{"技术面":7.5,"资金面":6}',
      });

      expect(snapshot.dimensionScores, {'技术面': 7.5, '资金面': 6.0});
      expect(
          snapshot.toMap()['dimension_scores_json'], '{"技术面":7.5,"资金面":6.0}');
    });
  });

  group('WeightOptimizer historical weighting', () {
    test('strong decay lets recent wins outweigh stale losses', () async {
      final now = DateTime.now();
      for (var i = 0; i < 4; i++) {
        await _insertClosedRecommendation(
          db,
          code: 'old$i',
          signalDate: now.subtract(Duration(days: 120 + i)),
          day20Return: -5.0,
          dimensionScores: {'技术面': 8.0},
        );
      }
      for (var i = 0; i < 2; i++) {
        await _insertClosedRecommendation(
          db,
          code: 'new$i',
          signalDate: now.subtract(Duration(days: i + 1)),
          day20Return: 6.0,
          dimensionScores: {'技术面': 8.0},
        );
      }

      final weights = await WeightOptimizer().getOptimizedWeights(
        minSamples: 1,
        maxAdjustment: 0.08,
        decayFactor: 0.5,
      );

      expect(
        weights['技术面']!,
        greaterThan(WeightOptimizer.kDefaultWeights['技术面']!),
        reason:
            'Recent successful technical-score records should dominate stale failures',
      );
      expect(
        weights.values.reduce((a, b) => a + b),
        closeTo(1.0, 0.000001),
      );
    });

    test('dimension performance report keeps sample counts below threshold',
        () async {
      await _insertClosedRecommendation(
        db,
        code: 'few1',
        signalDate: DateTime.now().subtract(const Duration(days: 1)),
        day20Return: 3.0,
        dimensionScores: {'技术面': 7.0},
      );

      final report = await WeightOptimizer().getDimensionPerformanceReport(
        minSamples: 3,
      );
      final tech = report.firstWhere((row) => row['name'] == '技术面');

      expect(tech['sample_count'], 1);
      expect(tech['has_enough_data'], isFalse);
      expect(tech['current_weight'], WeightOptimizer.kDefaultWeights['技术面']);
    });
  });

  group('tradingDaysBetween (fix 1.14: 交易日口径)', () {
    test('周五到下周三：交易日 < 自然日', () {
      // 2026-07-10 是周五，2026-07-15 是周三：自然日差 5，交易日应为 3
      final friday = DateTime(2026, 7, 10);
      final wednesday = DateTime(2026, 7, 15);
      expect(wednesday.difference(friday).inDays, 5);
      expect(tradingDaysBetween(friday, wednesday), 3);
    });

    test('周一到下周一：5 个交易日', () {
      final monday = DateTime(2026, 7, 6);
      final nextMonday = DateTime(2026, 7, 13);
      expect(nextMonday.difference(monday).inDays, 7);
      expect(tradingDaysBetween(monday, nextMonday), 5);
    });

    test('end 不晚于 start 返回 0', () {
      expect(
          tradingDaysBetween(DateTime(2026, 7, 15), DateTime(2026, 7, 15)), 0);
      expect(
          tradingDaysBetween(DateTime(2026, 7, 15), DateTime(2026, 7, 10)), 0);
    });

    test('跨越长周末的里程碑不会提前触发', () {
      // 自然日已 >=5 但交易日 <5 时，不应计入 5 日里程碑
      final friday = DateTime(2026, 7, 10);
      final wednesday = DateTime(2026, 7, 15);
      expect(tradingDaysBetween(friday, wednesday) < 5, isTrue);
    });
  });
}
