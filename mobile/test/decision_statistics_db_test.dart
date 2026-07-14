import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/storage/database_service.dart';
import 'package:stock_analyzer/storage/decision_tracking_schema.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('typed decision queries apply filters and as-of cutoff', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) => createDecisionTrackingSchema(db),
    );
    final service = DatabaseService();
    service.resetForTesting();
    await service.setDatabaseForTesting(db);
    final id = await service.saveDecisionSnapshotWithOutcomes(
      DecisionSnapshotRecord(
        code: '000001',
        source: 'explore',
        signalTime: DateTime(2026, 1, 1),
        signalTradeDate: DateTime(2026, 1, 1),
        signalPrice: 10,
        benchmarkCode: '000300',
        direction: RecommendationDirection.bullish,
        directionScore: 40,
        tradeQualityScore: 70,
        riskScore: 30,
        evidenceConfidence: 75,
        recommendationLevel: 'bullish',
        recommendationLabel: '看多',
        legacyScore: 8,
        marketRegime: MarketRegime.range,
        modelVersion: 'v2',
        primaryStrategyId: 'trend',
        createdAt: DateTime(2026, 1, 1),
      ),
    );
    final outcomes = await service.getDecisionOutcomes(id);
    for (final outcome in outcomes) {
      await db.update(
        'decision_outcomes',
        {
          'status': 'evaluated',
          'target_trade_date':
              '2026-01-${(1 + outcome.horizon).toString().padLeft(2, '0')}',
          'effective_direction_hit': 1,
          'forecast_return': 1.5,
        },
        where: 'id = ?',
        whereArgs: [outcome.id],
      );
    }

    final calibration = await service.getDecisionCalibrationRows(
      modelVersion: 'v2',
      asOfTradeDate: DateTime(2026, 1, 10),
    );
    expect(calibration, hasLength(3));
    expect(calibration.first, isA<DecisionCalibrationRow>());

    final statistics = await service.getDecisionStatisticsRows(
      horizon: 3,
      direction: RecommendationDirection.bullish,
      marketRegime: MarketRegime.range,
      modelVersion: 'v2',
      source: 'explore',
      primaryStrategyId: 'trend',
      minDirectionScore: 35,
      maxDirectionScore: 55,
    );
    expect(statistics, hasLength(1));
    expect(statistics.single.outcome.horizon, 3);
    expect(statistics.single.snapshot.code, '000001');

    expect(
      await service.getDecisionStatisticsRows(source: 'opportunity'),
      isEmpty,
    );
    await db.close();
  });
}
