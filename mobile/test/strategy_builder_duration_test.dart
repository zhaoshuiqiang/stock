import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/strategy_builder.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('StrategyBuilder preferredDuration filtering', () {
    test('shortTerm only returns short-term or defensive short strategies', () {
      final strategies = StrategyBuilder.buildLayeredStrategies(
        _trendData(),
        const [],
        SignalDuration.shortTerm,
      );

      expect(strategies, isNotEmpty);
      expect(
        strategies.where((s) => s.strategyType == 'long' && s.category == '长线'),
        isEmpty,
        reason: '短线策略列表不应混入长线策略',
      );
      expect(
        strategies.any((s) => s.category == '短线' || s.strategyType == 'short'),
        isTrue,
      );
    });

    test('longTerm only returns long-term strategies', () {
      final strategies = StrategyBuilder.buildLayeredStrategies(
        _trendData(),
        const [],
        SignalDuration.longTerm,
      );

      expect(strategies, isNotEmpty);
      expect(
        strategies
            .where((s) => s.category == '短线' || s.strategyType == 'short'),
        isEmpty,
        reason: '长线策略列表不应混入短线买入/防守策略',
      );
      expect(strategies.any((s) => s.strategyType == 'long'), isTrue);
    });
  });
}

List<HistoryKline> _trendData() {
  double price = 10;
  return List.generate(30, (i) {
    final open = price;
    price += 0.2;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: open,
      high: price * 1.01,
      low: open * 0.99,
      close: price,
      volume: 10000 + i * 1000,
      amount: price * (10000 + i * 1000),
      ma5: price - 0.2,
      ma10: price - 0.5,
      ma20: price - 1.0,
      ma60: price - 1.5,
      volMa5: 10000 + i * 800,
      atr14: price * 0.03,
      rsi6: 58,
      rsi12: 52,
      k: 45,
      d: 40,
      macdDif: 0.2,
      macdDea: 0.1,
      adx14: 26,
      plusDi14: 30,
      minusDi14: 12,
    );
  });
}
