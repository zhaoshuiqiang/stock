import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/directional_evidence_builder.dart';
import 'package:stock_analyzer/analysis/isolate_scan.dart';
import 'package:stock_analyzer/analysis/recommendation_policy.dart';
import 'package:stock_analyzer/analysis/recommendation_thresholds.dart';
import 'package:stock_analyzer/analysis/scoring_config.dart';
import 'package:stock_analyzer/models/stock_models.dart';

List<HistoryKline> _rawKlines(int n, {double base = 10.0}) {
  return List.generate(n, (i) {
    final p = base + i * 0.15;
    return HistoryKline(
      date: DateTime(2024, 1, 1).add(Duration(days: i)),
      open: p * 0.99,
      high: p * 1.02,
      low: p * 0.98,
      close: p,
      volume: 100000 + i * 1000.0,
    );
  });
}

IsolateScanRequest _req(List<IsolateScanItem> items) => IsolateScanRequest(
      items: items,
      activeWeights: DirectionalEvidenceBuilder.componentWeights,
      activeThresholds: RecommendationThresholds.defaults,
    );

void main() {
  // runBatchAnalysis restores scoring config into the (here: current) isolate's
  // statics; reset them so it cannot leak into other tests in this file.
  tearDown(() {
    DirectionalEvidenceBuilder.applyWeightOverride(null);
    RecommendationPolicy.applyThresholdOverride(null);
    ScoringConfig.useCalibratedThresholds = false;
    ScoringConfig.riskProfile = RiskProfile.balanced;
  });

  group('runBatchAnalysis (isolate entry)', () {
    test('analyzes valid items and skips items with insufficient data', () {
      final klines = _rawKlines(40);
      final out = runBatchAnalysis(_req([
        IsolateScanItem(
          code: 'sh600000',
          klines: klines,
          quote: QuoteData(code: 'sh600000', name: 'T', price: klines.last.close),
        ),
        IsolateScanItem(
          code: 'short',
          klines: klines.take(5).toList(),
          quote: QuoteData(code: 'short'),
        ),
      ]));
      expect(out.length, 1); // short-data item skipped
      expect(out.first.code, 'sh600000');
      expect(out.first.evidenceDate, klines.last.date);
      expect(out.first.analysis.recommendation, isNotEmpty);
      expect(out.first.analysis.score, greaterThanOrEqualTo(0));
    });

    test('empty request returns empty list', () {
      expect(runBatchAnalysis(_req(const [])), isEmpty);
    });

    test('per-item failure does not abort the whole batch', () {
      final good = _rawKlines(40);
      final out = runBatchAnalysis(_req([
        IsolateScanItem(
          code: 'a',
          klines: good,
          quote: QuoteData(code: 'a', price: good.last.close),
        ),
        IsolateScanItem(
          code: 'b',
          klines: good,
          quote: QuoteData(code: 'b', price: good.last.close),
        ),
      ]));
      expect(out.length, 2);
      expect(out.map((r) => r.code).toSet(), {'a', 'b'});
    });

    test('restores active scoring config into worker statics', () {
      // Simulate the flag-on dispatch snapshot: a non-default risk profile
      // baked into activeThresholds must survive into the worker.
      ScoringConfig.riskProfile = RiskProfile.aggressive;
      final aggressiveThresholds = RecommendationPolicy.active;
      ScoringConfig.riskProfile = RiskProfile.balanced;

      runBatchAnalysis(IsolateScanRequest(
        items: const [],
        activeWeights: DirectionalEvidenceBuilder.componentWeights,
        activeThresholds: aggressiveThresholds,
      ));

      // After the run, the worker installed the passed override.
      expect(ScoringConfig.useCalibratedThresholds, isTrue);
      expect(RecommendationPolicy.active.strongBullishQualityMin,
          aggressiveThresholds.strongBullishQualityMin);
    });
  });
}
