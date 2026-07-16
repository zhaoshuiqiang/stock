import 'package:flutter/foundation.dart';

import '../core/app_version.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import 'decision_market_data_provider.dart';
import 'decision_outcome_evaluator.dart';
import 'recommendation_policy.dart';
import 'trading_date_utils.dart';

/// 批量捕获决策快照的结果汇总。
/// [success] 成功写入数；[failed] 失败数；[failedCodes] 失败标的代码（便于排查）。
class CaptureBatchResult {
  final int success;
  final int failed;
  final List<String> failedCodes;

  const CaptureBatchResult({
    this.success = 0,
    this.failed = 0,
    this.failedCodes = const [],
  });
}

/// v3.32: 逐只捕获，单只失败不影响其余（此前任一只抛异常会中断整批且被调用方吞掉，
/// 导致全市场扫描整批决策快照静默丢失）。返回成功/失败汇总便于排查。
Future<CaptureBatchResult> captureDecisionBatchForTesting({
  required List<AnalysisResult> analyses,
  required String source,
  required DecisionTracker tracker,
  required DateTime signalTradeDate,
  required String benchmarkCode,
}) async {
  var success = 0;
  final failedCodes = <String>[];
  for (final analysis in analyses) {
    if (analysis.shortTermDecision == null || analysis.quote == null) continue;
    try {
      await tracker.capture(
        analysis: analysis,
        source: source,
        signalTradeDate: signalTradeDate,
        benchmarkCode: benchmarkCode,
      );
      success++;
    } catch (e) {
      final code = analysis.quote?.code ?? '?';
      failedCodes.add(code);
      debugPrint('captureDecisionBatch 单只失败($code): $e');
    }
  }
  return CaptureBatchResult(
    success: success,
    failed: failedCodes.length,
    failedCodes: failedCodes,
  );
}

/// 决策快照保留天数：超过该天数的历史快照在每次扫描后自动清理，避免表无限增长。
const int kDecisionDataRetentionDays = 90;

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
    DateTime? capturedAt,
    DateTime? evidenceTradeDate,
    DecisionSignalPhase? signalPhase,
    bool isRetrospective = false,
  }) async {
    final decision = analysis.shortTermDecision;
    final quote = analysis.quote;
    if (decision == null || quote == null || quote.price <= 0) {
      throw ArgumentError(
          'A priced analysis with shortTermDecision is required');
    }
    final now = capturedAt ?? DateTime.now();
    final phase = signalPhase ?? TradingDateUtils.signalPhase(now);
    final resolvedEvidenceDate =
        evidenceTradeDate ?? decision.evidenceTradeDate;
    if (decision.modelVersion == 'short-term-v3' &&
        resolvedEvidenceDate == null) {
      throw ArgumentError('short-term-v3 requires an evidence trade date');
    }
    final normalizedSignalDate =
        TradingDateUtils.normalizeToTradeDate(signalTradeDate);
    final normalizedEvidenceDate = TradingDateUtils.normalizeToTradeDate(
      resolvedEvidenceDate ?? normalizedSignalDate,
    );
    final recommendation = analysis.recommendationDecision ??
        RecommendationPolicy.evaluate(decision);
    final flags = <String>{...decision.dataQualityFlags};
    if (isRetrospective) flags.add('retrospective_backfill');
    final snapshot = DecisionSnapshotRecord(
      code: quote.code,
      name: quote.name,
      source: source,
      signalTime: now,
      signalTradeDate: normalizedSignalDate,
      evidenceTradeDate: normalizedEvidenceDate,
      signalPhase: phase,
      signalPrice: quote.price,
      benchmarkCode: benchmarkCode,
      sectorName: sectorName,
      direction: decision.direction,
      directionScore: decision.directionScore,
      tradeQualityScore: decision.tradeQualityScore,
      riskScore: decision.riskScore,
      evidenceConfidence: decision.evidenceConfidence,
      recommendationLevel: recommendation.level.name,
      recommendationLabel: recommendation.label,
      legacyScore: recommendation.legacyScore,
      actionable: recommendation.actionable,
      recommendationGates: recommendation.gates,
      marketRegime: decision.marketRegime,
      marketChangePct: analysis.marketContext?.avgChangePct,
      modelVersion: decision.modelVersion,
      appVersion: AppVersion.version,
      isRetrospective: isRetrospective,
      primaryStrategyId: decision.primaryStrategyId,
      primaryStrategyName: decision.primaryStrategyName,
      supportingStrategyIds: decision.supportingStrategyIds,
      directionComponents: decision.directionComponents,
      qualityComponents: decision.qualityComponents,
      riskComponents: decision.riskComponents,
      dataQualityFlags: flags.toList(growable: false),
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

  /// 清理超过保留期的历史决策快照（及其 outcomes），防止决策表无限增长。
  /// 默认保留 [kDecisionDataRetentionDays] 天，按 signal_trade_date 计算。
  /// [excludeSources] 中的来源不会被清理，默认保护用户显式留档(source='archive')。
  Future<int> purgeOldSnapshots({
    int keepDays = kDecisionDataRetentionDays,
    List<String> excludeSources = const ['archive'],
  }) =>
      storage.purgeOldDecisionData(
        keepDays: keepDays,
        excludeSources: excludeSources,
      );

  /// 评估失败重试上限：超过后标记 invalid，避免不可匹配的快照永久占用
  /// [refreshPending] 的 limit 槽位、饿死真正可评估的快照。
  static const int kMaxEvalAttempts = 5;

  Future<void> _recordFailure(
      DecisionOutcomeRecord outcome, DateTime at) async {
    final db = await storage.database;
    final next = outcome.attemptCount + 1;
    if (next >= kMaxEvalAttempts) {
      await db.rawUpdate('''
        UPDATE decision_outcomes
        SET attempt_count = ?, last_attempted_at = ?, status = 'invalid',
            invalid_reason = 'eval_failed'
        WHERE id = ? AND status = 'pending'
      ''', [next, at.millisecondsSinceEpoch, outcome.id]);
    } else {
      await db.rawUpdate('''
        UPDATE decision_outcomes
        SET attempt_count = ?, last_attempted_at = ?
        WHERE id = ? AND status = 'pending'
      ''', [next, at.millisecondsSinceEpoch, outcome.id]);
    }
  }
}
