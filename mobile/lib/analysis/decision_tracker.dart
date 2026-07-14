import 'package:flutter/foundation.dart';

import '../models/stock_models.dart';
import '../storage/database_service.dart';
import 'decision_market_data_provider.dart';
import 'decision_outcome_evaluator.dart';

Future<void> captureDecisionBatchForTesting({
  required List<AnalysisResult> analyses,
  required String source,
  required DecisionTracker tracker,
  required DateTime signalTradeDate,
  required String benchmarkCode,
}) async {
  for (final analysis in analyses) {
    if (analysis.shortTermDecision == null || analysis.quote == null) continue;
    await tracker.capture(
      analysis: analysis,
      source: source,
      signalTradeDate: signalTradeDate,
      benchmarkCode: benchmarkCode,
    );
  }
}

class DecisionTracker {
  final DatabaseService storage;
  final DecisionMarketDataSource marketData;

  DecisionTracker({
    DatabaseService? storage,
    DecisionMarketDataSource? marketData,
  })  : storage = storage ?? DatabaseService(),
        marketData = marketData ?? DecisionMarketDataProvider();

  Future<int> capture({
    required AnalysisResult analysis,
    required String source,
    required DateTime signalTradeDate,
    required String benchmarkCode,
    String sectorName = '',
  }) async {
    final decision = analysis.shortTermDecision;
    final quote = analysis.quote;
    if (decision == null || quote == null || quote.price <= 0) {
      throw ArgumentError(
          'A priced analysis with shortTermDecision is required');
    }
    final now = DateTime.now();
    final snapshot = DecisionSnapshotRecord(
      code: quote.code,
      name: quote.name,
      source: source,
      signalTime: quote.updateTime ?? now,
      signalTradeDate: signalTradeDate,
      signalPrice: quote.price,
      adjustedSignalPrice: quote.price,
      benchmarkCode: benchmarkCode,
      sectorName: sectorName,
      direction: decision.direction,
      directionScore: decision.directionScore,
      tradeQualityScore: decision.tradeQualityScore,
      riskScore: decision.riskScore,
      evidenceConfidence: decision.evidenceConfidence,
      recommendationLevel: decision.direction.name,
      recommendationLabel: analysis.recommendation,
      legacyScore: analysis.score.clamp(1, 10),
      marketRegime: decision.marketRegime,
      marketChangePct: analysis.marketContext?.shIndexPct,
      modelVersion: decision.modelVersion,
      primaryStrategyId: decision.primaryStrategyId,
      primaryStrategyName: decision.primaryStrategyName,
      supportingStrategyIds: decision.supportingStrategyIds,
      directionComponents: decision.directionComponents,
      qualityComponents: decision.qualityComponents,
      riskComponents: decision.riskComponents,
      dataQualityFlags: decision.dataQualityFlags,
      createdAt: now,
    );
    return storage.saveDecisionSnapshotWithOutcomes(
      snapshot,
      calibrations: decision.calibrationByHorizon,
    );
  }

  Future<void> refreshPending({int limit = 100, DateTime? now}) async {
    final work = await storage.getPendingDecisionWorkItems(limit: limit);
    final groups = <String, List<DecisionEvaluationWorkItem>>{};
    for (final item in work) {
      final key = '${item.snapshot.code}|${item.snapshot.benchmarkCode}';
      groups.putIfAbsent(key, () => []).add(item);
    }
    for (final items in groups.values) {
      DecisionMarketData data;
      try {
        data = await marketData.load(
          code: items.first.snapshot.code,
          benchmarkCode: items.first.snapshot.benchmarkCode,
        );
      } catch (error) {
        for (final item in items) {
          await _recordFailure(item.outcome, now ?? DateTime.now());
        }
        debugPrint('Decision tracking market data failed: $error');
        continue;
      }
      for (final item in items) {
        try {
          final evaluated = DecisionOutcomeEvaluator.evaluate(
            snapshot: item.snapshot,
            outcome: item.outcome,
            data: data,
            now: now,
          );
          await storage.saveDecisionOutcome(evaluated);
        } catch (error) {
          await _recordFailure(item.outcome, now ?? DateTime.now());
          debugPrint('Decision outcome evaluation failed: $error');
        }
      }
    }
  }

  Future<void> _recordFailure(
      DecisionOutcomeRecord outcome, DateTime at) async {
    final db = await storage.database;
    await db.rawUpdate('''
      UPDATE decision_outcomes
      SET attempt_count = attempt_count + 1, last_attempted_at = ?
      WHERE id = ? AND status = 'pending'
    ''', [at.millisecondsSinceEpoch, outcome.id]);
  }
}
