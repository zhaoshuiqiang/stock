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

  test('batch capture stores the actual bearish recommendation in new tables',
      () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await createDecisionTrackingSchema(db);
        await db
            .execute('CREATE TABLE archive_records (id INTEGER PRIMARY KEY)');
        await db.execute(
            'CREATE TABLE recommendation_tracking (id INTEGER PRIMARY KEY)');
      },
    );
    final storage = DatabaseService();
    storage.resetForTesting();
    await storage.setDatabaseForTesting(db);
    final analysis = AnalysisResult(
      quote: QuoteData(code: '000001', name: '平安银行', price: 10),
      score: 3,
      recommendation: '看空',
      shortTermDecision: ShortTermDecision(
        directionScore: -72,
        tradeQualityScore: 68,
        riskScore: 42,
        evidenceConfidence: 70,
        direction: RecommendationDirection.bearish,
        marketRegime: MarketRegime.bearishTrend,
        modelVersion: 'short-term-v2',
        rawComprehensiveScore: 3,
      ),
    );

    await captureDecisionBatchForTesting(
      analyses: [analysis],
      source: 'explore',
      tracker: DecisionTracker(storage: storage, marketData: _UnusedData()),
      signalTradeDate: DateTime(2026, 7, 14),
      benchmarkCode: '000300',
    );

    final snapshots = await db.query('decision_snapshots');
    expect(snapshots, hasLength(1));
    expect(snapshots.single['direction'], 'bearish');
    expect(snapshots.single['recommendation_level'], 'strongBearish');
    expect(snapshots.single['legacy_score'], closeTo(1.4, 0.01));
    expect(await db.query('archive_records'), isEmpty);
    expect(await db.query('recommendation_tracking'), isEmpty);
    await db.close();
  });
}

class _UnusedData implements DecisionMarketDataSource {
  @override
  Future<DecisionMarketData> load({
    required String code,
    required String benchmarkCode,
    int days = 180,
  }) =>
      throw UnimplementedError();
}
