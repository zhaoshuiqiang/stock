import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/recommendation_policy.dart';
import 'package:stock_analyzer/analysis/signal_engine.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('generateAnalysis short-term integration', () {
    test('adds short-term tradeability score to dimension scores and reasons',
        () {
      final data = calcAllIndicators(_trendData(lastJumpPct: 2.5));
      final quote = _quote(
        price: data.last.close,
        changePct: 2.5,
        mainNetFlowRate: 6,
        turnover: 4,
        amplitude: 4,
      );

      final analysis = generateAnalysis(
        data,
        quote,
        enableAsyncSideEffects: false,
      );

      expect(analysis.shortTermDecision, isNotNull);
      final policy = RecommendationPolicy.evaluate(analysis.shortTermDecision!);
      expect(analysis.score, policy.legacyScore);
      expect(analysis.recommendation, policy.label);
      expect(analysis.confidenceScore,
          analysis.shortTermDecision!.evidenceConfidence / 100);

      expect(analysis.dimensionScores?['趋势'], isNotNull);
      expect(analysis.dimensionScores!['趋势'], greaterThanOrEqualTo(3));
      expect(
        analysis.reasons.any((r) => r.contains('趋势') || r.contains('反转动量')),
        isTrue,
      );
    });

    test('caps high-score chase setup to cautious buy at most', () {
      final data = calcAllIndicators(_trendData(lastJumpPct: 10.2));
      final quote = _quote(
        price: data.last.close,
        changePct: 10.2,
        mainNetFlowRate: 8,
        turnover: 12,
        amplitude: 10,
      );

      final analysis = generateAnalysis(
        data,
        quote,
        enableAsyncSideEffects: false,
      );

      expect(analysis.score, lessThanOrEqualTo(7));
      expect(analysis.shortTermDecision!.directionScore, lessThanOrEqualTo(34));
      expect(analysis.recommendation, isNot(anyOf('强烈买入', '买入')));
      expect(
        analysis.reasons.any((r) => r.contains('追高') || r.contains('涨停')),
        isTrue,
      );
    });
  });
}

List<HistoryKline> _trendData({required double lastJumpPct}) {
  var price = 10.0;
  return List.generate(30, (i) {
    final open = price;
    if (i == 29) {
      price *= 1 + lastJumpPct / 100;
    } else {
      price *= 1.012;
    }
    final volume = i == 29 ? 32000.0 : 10000.0 + i * 500;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: open,
      high: price * 1.01,
      low: open * 0.99,
      close: price,
      volume: volume,
      amount: volume * price,
    );
  });
}

QuoteData _quote({
  required double price,
  required double changePct,
  required double mainNetFlowRate,
  required double turnover,
  required double amplitude,
}) {
  final preClose = price / (1 + changePct / 100);
  return QuoteData(
    code: 'sh600001',
    name: '测试股票',
    price: price,
    changePct: changePct,
    open: preClose,
    high: price * 1.01,
    low: preClose * 0.99,
    preClose: preClose,
    mainNetFlow: mainNetFlowRate * 1000000,
    mainNetFlowRate: mainNetFlowRate,
    turnover: turnover,
    amplitude: amplitude,
    pe: 20,
    pb: 2,
  );
}
