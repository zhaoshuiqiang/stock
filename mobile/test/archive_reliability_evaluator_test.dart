import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/archive_reliability_evaluator.dart';
import 'package:stock_analyzer/models/stock_models.dart';

ArchiveRecord _record({
  required String recommendation,
  required double price,
  required DateTime archivedAt,
}) {
  return ArchiveRecord(
    code: 'sz000001',
    name: 'test',
    price: price,
    changePct: 0,
    score: 5,
    recommendation: recommendation,
    riskLevel: '中',
    buySignalCount: 0,
    sellSignalCount: 0,
    activeStrategyCount: 0,
    confluenceScore: 0,
    topSignals: '',
    archivedAt: archivedAt,
  );
}

void main() {
  group('ArchiveReliabilityEvaluator', () {
    test(
        'calculates directional stats separately for bullish bearish and neutral records',
        () {
      final archivedAt = DateTime(2026, 7, 9, 22, 6);
      final now = DateTime(2026, 7, 10, 14, 22);
      final bullish = _record(
        recommendation: '谨慎买入',
        price: 10,
        archivedAt: archivedAt,
      );
      final bearishHit = _record(
        recommendation: '谨慎卖出',
        price: 10,
        archivedAt: archivedAt,
      );
      final bearishMiss = _record(
        recommendation: '偏空观望',
        price: 10,
        archivedAt: archivedAt,
      );
      final neutral = _record(
        recommendation: '观望',
        price: 10,
        archivedAt: archivedAt,
      );

      final stats = ArchiveReliabilityEvaluator.calculateStats(
        records: [bullish, bearishHit, bearishMiss, neutral],
        currentPriceOf: (record) {
          if (record == bullish) return 10.3;
          if (record == bearishHit) return 9.8;
          if (record == bearishMiss) return 10.3;
          return 10.1;
        },
        now: now,
      );

      expect(stats.total, equals(4));
      expect(stats.reasonableTotal, equals(3));
      expect(stats.directionReasonableRate, closeTo(75.0, 0.001));
      expect(stats.bullishTotal, equals(1));
      expect(stats.bullishHits, equals(1));
      expect(stats.bullishHitRate, closeTo(100.0, 0.001));
      expect(stats.bearishTotal, equals(2));
      expect(stats.bearishHits, equals(1));
      expect(stats.bearishHitRate, closeTo(50.0, 0.001));
      expect(stats.neutralTotal, equals(1));
      expect(stats.neutralStable, equals(1));
      expect(stats.neutralStableRate, closeTo(100.0, 0.001));
    });

    test('matches type filters with the same directional semantics as stats',
        () {
      final archivedAt = DateTime(2026, 7, 9, 22, 6);
      final bullishWatch = _record(
        recommendation: '偏多观望',
        price: 10,
        archivedAt: archivedAt,
      );
      final bearishWatch = _record(
        recommendation: '偏空观望',
        price: 10,
        archivedAt: archivedAt,
      );
      final neutral = _record(
        recommendation: '观望',
        price: 10,
        archivedAt: archivedAt,
      );

      expect(
        ArchiveReliabilityEvaluator.matchesTypeFilter(bullishWatch, '买入'),
        isTrue,
      );
      expect(
        ArchiveReliabilityEvaluator.matchesTypeFilter(bullishWatch, '观望'),
        isFalse,
      );
      expect(
        ArchiveReliabilityEvaluator.matchesTypeFilter(bearishWatch, '卖出'),
        isTrue,
      );
      expect(
        ArchiveReliabilityEvaluator.matchesTypeFilter(bearishWatch, '观望'),
        isFalse,
      );
      expect(
        ArchiveReliabilityEvaluator.matchesTypeFilter(neutral, '观望'),
        isTrue,
      );
      expect(
        ArchiveReliabilityEvaluator.matchesTypeFilter(neutral, '买入'),
        isFalse,
      );
    });
  });
}
