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
    riskLevel: 'DEF',
    buySignalCount: 0,
    sellSignalCount: 0,
    activeStrategyCount: 0,
    confluenceScore: 0,
    topSignals: '',
    archivedAt: archivedAt,
  );
}

void main() {
  group('ArchiveReliabilityEvaluator.calculateRelativeAlpha', () {
    test('single cohort: alpha is demeaned against the cohort market return',
        () {
      final at = DateTime(2026, 7, 23, 22, 0);
      final b1 = _record(recommendation: '谨慎买入', price: 10, archivedAt: at);
      final b2 = _record(recommendation: '谨慎买入', price: 10, archivedAt: at);
      final s1 = _record(recommendation: '谨慎卖出', price: 10, archivedAt: at);

      final stats = ArchiveReliabilityEvaluator.calculateRelativeAlpha(
        records: [b1, b2, s1],
        currentPriceOf: (r) {
          if (r == b1) return 10.1; // +1%
          if (r == b2) return 9.9; // -1%
          return 9.7; // -3%
        },
      );

      expect(stats.sampleCount, equals(3));
      expect(stats.cohortCount, equals(1));
      // cohort mean = (+1 -1 -3)/3 = -1.0
      expect(stats.marketMeanReturn, closeTo(-1.0, 1e-6));
      expect(stats.downBreadthPct, closeTo(66.667, 0.01));
      // bullish alphas: (1-(-1))=+2, (-1-(-1))=0 -> mean +1
      expect(stats.bullishCount, equals(2));
      expect(stats.bullishAlpha, closeTo(1.0, 1e-6));
      // bearish alpha: (-3-(-1)) = -2
      expect(stats.bearishCount, equals(1));
      expect(stats.bearishAlpha, closeTo(-2.0, 1e-6));
      expect(stats.neutralCount, equals(0));
      expect(stats.hasEnoughData, isTrue);
    });

    test('two cohorts: each record is demeaned against its own cohort', () {
      final d1 = DateTime(2026, 7, 22, 22, 0);
      final d2 = DateTime(2026, 7, 23, 22, 0);
      final a = _record(recommendation: '谨慎买入', price: 10, archivedAt: d1);
      final b = _record(recommendation: '观望', price: 10, archivedAt: d1);
      final c = _record(recommendation: '谨慎买入', price: 10, archivedAt: d2);
      final d = _record(recommendation: '观望', price: 10, archivedAt: d2);

      final stats = ArchiveReliabilityEvaluator.calculateRelativeAlpha(
        records: [a, b, c, d],
        currentPriceOf: (r) {
          if (r == a) return 10.3; // +3% (cohort d1)
          if (r == b) return 9.9; // -1% (cohort d1)
          if (r == c) return 9.8; // -2% (cohort d2)
          return 9.6; // -4% (cohort d2)
        },
      );

      expect(stats.sampleCount, equals(4));
      expect(stats.cohortCount, equals(2));
      // d1 mean = +1 -> alpha a = +2 ; d2 mean = -3 -> alpha c = +1 ; mean 1.5
      expect(stats.bullishCount, equals(2));
      expect(stats.bullishAlpha, closeTo(1.5, 1e-6));
      // neutral alphas: b = -1-1 = -2 ; d = -4-(-3) = -1 ; mean -1.5
      expect(stats.neutralCount, equals(2));
      expect(stats.neutralAlpha, closeTo(-1.5, 1e-6));
      expect(stats.marketMeanReturn, closeTo(-1.0, 1e-6));
      expect(stats.downBreadthPct, closeTo(75.0, 1e-6));
    });

    test('empty / invalid prices yield a zeroed, insufficient result', () {
      final at = DateTime(2026, 7, 23, 22, 0);
      final r = _record(recommendation: '谨慎买入', price: 10, archivedAt: at);
      final stats = ArchiveReliabilityEvaluator.calculateRelativeAlpha(
        records: [r],
        currentPriceOf: (_) => 0, // invalid -> skipped
      );
      expect(stats.sampleCount, equals(0));
      expect(stats.hasEnoughData, isFalse);
    });
  });
}
