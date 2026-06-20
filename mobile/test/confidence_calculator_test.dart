import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/confidence_calculator.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('ConfidenceCalculator', () {
    HistoryKline makeLast() => HistoryKline(
          date: DateTime.now(),
          close: 10.0,
          open: 9.5,
          high: 10.5,
          low: 9.0,
        );

    List<SignalItem> makeBuySignals(int count) => List.generate(
          count,
          (i) => SignalItem(
            type: 'buy',
            indicator: 'RSI',
            signal: 'RSI超卖',
            description: 'RSI指标超卖',
            strength: 3,
            duration: SignalDuration.shortTerm,
          ),
        );

    List<SignalItem> makeSellSignals(int count) => List.generate(
          count,
          (i) => SignalItem(
            type: 'sell',
            indicator: 'MACD',
            signal: 'MACD死叉',
            description: 'MACD指标死叉',
            strength: 3,
            duration: SignalDuration.longTerm,
          ),
        );

    test('returns confidence within valid range (0.2-0.95)', () {
      final buySignals = makeBuySignals(3);
      final sellSignals = makeSellSignals(1);
      final allSignals = [...buySignals, ...sellSignals];
      final last = makeLast();

      final result = ConfidenceCalculator.calculate(
        buySignals: buySignals,
        sellSignals: sellSignals,
        signals: allSignals,
        totalScore: 7,
        last: last,
        quote: null,
      );

      expect(result.confidenceScore, greaterThanOrEqualTo(0.2));
      expect(result.confidenceScore, lessThanOrEqualTo(0.95));
      expect(result.validatedSignals, isNotNull);
    });

    test('breakdown contains all 6 dimensions', () {
      final buySignals = makeBuySignals(2);
      final sellSignals = makeSellSignals(1);

      final bd = ConfidenceCalculator.breakdown(
        buySignals: buySignals,
        sellSignals: sellSignals,
        totalScore: 5,
      );

      expect(bd.containsKey('signal_consistency'), isTrue);
      expect(bd.containsKey('fundamental_support'), isTrue);
      expect(bd.containsKey('sentiment_confirm'), isTrue);
      expect(bd.containsKey('market_confirm'), isTrue);
      expect(bd.containsKey('structure_confirm'), isTrue);
      expect(bd.containsKey('signal_freshness'), isTrue);
      expect(bd.length, equals(6));
    });

    test('default confidence without external data is around 0.5', () {
      final buySignals = makeBuySignals(1);
      final sellSignals = makeSellSignals(1);
      final allSignals = [...buySignals, ...sellSignals];
      final last = makeLast();

      final result = ConfidenceCalculator.calculate(
        buySignals: buySignals,
        sellSignals: sellSignals,
        signals: allSignals,
        totalScore: 5,
        last: last,
        quote: null,
      );

      // 无基本面/情绪/市场数据时，各维度默认0.5，加权后约0.5
      // signal_consistency: buyCount==sellCount → 0.3 + 0 = 0.3
      // 其余均为0.5
      // 0.3*0.30 + 0.5*0.25 + 0.5*0.20 + 0.5*0.15 + 0.5*0.10 = 0.09+0.125+0.1+0.075+0.05 = 0.44
      // clamp(0.3, 0.95) → 0.44
      expect(result.confidenceScore, greaterThanOrEqualTo(0.3));
      expect(result.confidenceScore, lessThanOrEqualTo(0.6));
    });
  });
}
