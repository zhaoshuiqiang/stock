import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/recommendation_explainer.dart';
import 'package:stock_analyzer/analysis/signal_engine.dart';
import 'package:stock_analyzer/models/stock_models.dart';

List<HistoryKline> _uptrendData({int count = 80}) {
  double price = 10.0;
  final raw = List.generate(count, (i) {
    final open = price;
    price *= 1.01;
    return HistoryKline(
      date: DateTime(2026, 1, i + 1),
      open: open,
      high: price * 1.02,
      low: open * 0.99,
      close: price,
      volume: 10000 + (i % 5) * 1000,
      amount: 10000 * (open + price) / 2,
    );
  });
  return calcAllIndicators(raw);
}

void main() {
  group('RecommendationExplainer', () {
    test('explain combines signals, capital, confluence, and score', () {
      final text = RecommendationExplainer.explain(
        dimensionScores: {
          '资金面': 7.2,
          '共振': 6.8,
        },
        topSignals: ['MACD金叉', '均线多头排列'],
        buySignalCount: 3,
        sellSignalCount: 1,
        score: 7,
        recommendation: '买入',
      );

      expect(text, contains('MACD金叉'));
      expect(text, contains('3买1卖'));
      expect(text, contains('主力资金强势流入'));
      expect(text, contains('周期信号一致'));
      expect(text, contains('评分7/10'));
    });

    test('explain fallback omits empty recommendation label', () {
      final text = RecommendationExplainer.explain(score: 6);

      expect(text, '综合评分 6/10');
    });

    test('generateAnalysis includes a concise recommendation summary reason',
        () {
      final analysis = generateAnalysis(_uptrendData(), null);

      expect(
        analysis.reasons.any((reason) => reason.startsWith('推荐摘要：')),
        isTrue,
      );
    });
  });
}
