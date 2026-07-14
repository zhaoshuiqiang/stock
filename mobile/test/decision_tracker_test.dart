import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_analyzer/analysis/decision_market_data_provider.dart';
import 'package:stock_analyzer/analysis/decision_tracker.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/storage/database_service.dart';
import 'package:stock_analyzer/storage/decision_tracking_schema.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late DatabaseService storage;

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) => createDecisionTrackingSchema(db),
    );
    storage = DatabaseService();
    storage.resetForTesting();
    await storage.setDatabaseForTesting(db);
  });

  tearDown(() async => db.close());

  test('capture stores bearish decisions and is idempotent by trade date',
      () async {
    final tracker = DecisionTracker(storage: storage, marketData: _FakeData());
    final analysis = _analysis(RecommendationDirection.bearish);

    final first = await tracker.capture(
      analysis: analysis,
      source: 'explore',
      signalTradeDate: DateTime(2026, 7, 14),
      benchmarkCode: '000300',
      sectorName: '银行',
    );
    final duplicate = await tracker.capture(
      analysis: analysis,
      source: 'explore',
      signalTradeDate: DateTime(2026, 7, 14),
      benchmarkCode: '000300',
      sectorName: '银行',
    );

    expect(duplicate, first);
    expect(await db.query('decision_snapshots'), hasLength(1));
    expect(await db.query('decision_outcomes'), hasLength(3));
    expect((await storage.getDecisionSnapshot(first))!.direction,
        RecommendationDirection.bearish);
  });

  test('refresh loads histories once per code group and evaluates all horizons',
      () async {
    final data = _FakeData();
    final tracker = DecisionTracker(storage: storage, marketData: data);
    await tracker.capture(
      analysis: _analysis(RecommendationDirection.bullish),
      source: 'opportunity',
      signalTradeDate: DateTime(2026, 7, 14),
      benchmarkCode: '000300',
    );

    await tracker.refreshPending(now: DateTime(2026, 7, 22, 16));

    expect(data.loadCount, 1);
    final outcomes = await db.query('decision_outcomes');
    expect(outcomes.every((row) => row['status'] == 'evaluated'), isTrue);
    expect(outcomes.every((row) => row['forecast_return'] != null), isTrue);
  });
}

AnalysisResult _analysis(RecommendationDirection direction) => AnalysisResult(
      quote: QuoteData(code: '000001', name: '平安银行', price: 10),
      score: direction == RecommendationDirection.bearish ? 3 : 8,
      recommendation: direction.name,
      shortTermDecision: ShortTermDecision(
        directionScore: direction == RecommendationDirection.bearish ? -70 : 70,
        tradeQualityScore: 75,
        riskScore: 30,
        evidenceConfidence: 72,
        direction: direction,
        marketRegime: MarketRegime.range,
        modelVersion: 'short-term-v2',
        rawComprehensiveScore: 7,
      ),
    );

class _FakeData implements DecisionMarketDataSource {
  int loadCount = 0;

  @override
  Future<DecisionMarketData> load({
    required String code,
    required String benchmarkCode,
    int days = 180,
  }) async {
    loadCount++;
    final dates = [14, 15, 16, 17, 20, 21];
    return DecisionMarketData(
      adjustedStock: [
        for (var i = 0; i < dates.length; i++)
          HistoryKline(
            date: DateTime(2026, 7, dates[i]),
            open: 10 + i * 0.1,
            high: 10.1 + i * 0.1,
            low: 9.9 + i * 0.1,
            close: 10 + i * 0.1,
          ),
      ],
      adjustedBenchmark: [
        for (var i = 0; i < dates.length; i++)
          HistoryKline(
            date: DateTime(2026, 7, dates[i]),
            open: 100.0 + i,
            high: 101.0 + i,
            low: 99.0 + i,
            close: 100.0 + i,
          ),
      ],
    );
  }
}
