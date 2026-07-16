import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock_analyzer/analysis/decision_statistics.dart';
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
      filter: const DecisionStatisticsFilter(
        horizon: 3,
        direction: RecommendationDirection.bullish,
        marketRegime: MarketRegime.range,
        modelVersion: 'v2',
        source: 'explore',
      ),
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

  test('phase date source and retrospective filters compose', () async {
    final db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) => createDecisionTrackingSchema(db),
    );
    final service = DatabaseService();
    service.resetForTesting();
    await service.setDatabaseForTesting(db);
    await service.saveDecisionSnapshotWithOutcomes(
      _snapshot(
        code: '000001',
        source: 'archive',
        signalDate: DateTime(2026, 7, 16),
        phase: DecisionSignalPhase.preMarket,
      ),
    );
    await service.saveDecisionSnapshotWithOutcomes(
      _snapshot(
        code: '000002',
        source: 'archive_backfill',
        signalDate: DateTime(2026, 7, 15),
        phase: DecisionSignalPhase.afterClose,
        retrospective: true,
      ),
    );

    expect(await service.getDecisionStatisticsRows(), hasLength(3));
    expect(
      await service.getDecisionStatisticsRows(
        filter: const DecisionStatisticsFilter(includeRetrospective: true),
      ),
      hasLength(6),
    );
    expect(
      await service.getDecisionStatisticsRows(
        filter: DecisionStatisticsFilter(
          horizon: 1,
          sources: const ['archive'],
          signalPhase: DecisionSignalPhase.preMarket,
          startTradeDate: DateTime(2026, 7, 16),
          endTradeDate: DateTime(2026, 7, 16),
        ),
      ),
      hasLength(1),
    );
    await db.close();
  });
}

DecisionSnapshotRecord _snapshot({
  required String code,
  required String source,
  required DateTime signalDate,
  required DecisionSignalPhase phase,
  bool retrospective = false,
}) =>
    DecisionSnapshotRecord(
      code: code,
      source: source,
      signalTime: signalDate,
      signalTradeDate: signalDate,
      evidenceTradeDate: signalDate.subtract(const Duration(days: 1)),
      signalPhase: phase,
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
      actionable: true,
      marketRegime: MarketRegime.range,
      modelVersion: 'short-term-v3',
      isRetrospective: retrospective,
      createdAt: signalDate,
    );
