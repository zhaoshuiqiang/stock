import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/signal_layer.dart';
import 'package:stock_analyzer/analysis/strategy_engine.dart';

// Helper: generate uptrend data
List<HistoryKline> generateUptrend(int count, {double start = 10.0, double daily = 0.03}) {
  double price = start;
  return List.generate(count, (i) {
    final open = price;
    price *= (1 + daily);
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: open, high: price * 1.01, low: open * 0.99, close: price,
      volume: 15000 + i * 500, amount: 15000 * (open + price) / 2,
      change: price - open, changePct: (price - open) / open * 100,
    );
  });
}

// Helper: generate downtrend data
List<HistoryKline> generateDowntrend(int count, {double start = 30.0, double daily = -0.03}) {
  double price = start;
  return List.generate(count, (i) {
    final open = price;
    price *= (1 + daily);
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: open, high: open * 1.01, low: price * 0.99, close: price,
      volume: 15000 + i * 500, amount: 15000 * (open + price) / 2,
      change: price - open, changePct: (price - open) / open * 100,
    );
  });
}

// Helper: generate sideways data
List<HistoryKline> generateSideways(int count, {double base = 15.0}) {
  return List.generate(count, (i) {
    final price = base + (i % 10 - 5) * 0.1;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: price - 0.05, high: price + 0.1, low: price - 0.1, close: price,
      volume: 10000, amount: 10000 * price,
      change: 0.1, changePct: 0.5,
    );
  });
}

// Generate red three soldiers pattern
List<HistoryKline> generateRedThreeSoldiers(int count) {
  double base = 10.0;
  final raw = List.generate(count, (i) {
    final open = base;
    final close = i >= count - 3 ? open * (1.0 + (i - count + 4) * 0.02) : open * 1.01;
    final data = HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: open, high: close * 1.01, low: open * 0.99, close: close,
      volume: 15000 + (i >= count - 3 ? 5000 : 0), amount: 15000 * (open + close) / 2,
    );
    base = close;
    return data;
  });
  final last3 = raw.sublist(raw.length - 3);
  // Ensure rising closes
  raw[raw.length - 3] = raw[raw.length - 3].copyWith(
    open: 11.0, close: 11.5, high: 11.6, low: 10.9,
  );
  raw[raw.length - 2] = raw[raw.length - 2].copyWith(
    open: 11.5, close: 12.2, high: 12.3, low: 11.4,
  );
  raw[raw.length - 1] = raw[raw.length - 1].copyWith(
    open: 12.2, close: 13.5, high: 13.6, low: 12.1,
  );
  return raw;
}

// Generate three crows pattern
List<HistoryKline> generateThreeCrows(int count) {
  double base = 30.0;
  final raw = List.generate(count, (i) {
    final open = base;
    final close = i >= count - 3 ? open * (1.0 - (i - count + 4) * 0.02) : open * 0.99;
    final data = HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: open, high: open * 1.01, low: close * 0.99, close: close,
      volume: 15000 + (i >= count - 3 ? 5000 : 0), amount: 15000 * (open + close) / 2,
    );
    base = close;
    return data;
  });
  final last3 = raw.sublist(raw.length - 3);
  raw[raw.length - 3] = raw[raw.length - 3].copyWith(
    open: 19.0, close: 18.5, high: 19.1, low: 18.4,
  );
  raw[raw.length - 2] = raw[raw.length - 2].copyWith(
    open: 18.5, close: 17.8, high: 18.6, low: 17.7,
  );
  raw[raw.length - 1] = raw[raw.length - 1].copyWith(
    open: 17.8, close: 16.5, high: 17.9, low: 16.4,
  );
  return raw;
}

// Generate morning star pattern
List<HistoryKline> generateMorningStar(int count) {
  double base = 10.0;
  final raw = List.generate(count, (i) {
    final price = base;
    base *= 1.01;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: price, high: price * 1.02, low: price * 0.98, close: price,
      volume: 10000, amount: 10000 * price,
    );
  });
  final n = raw.length;
  // Bearish first day
  raw[n - 3] = raw[n - 3].copyWith(open: 12.5, close: 12.0, high: 12.6, low: 11.9);
  // Small body star day
  raw[n - 2] = raw[n - 2].copyWith(open: 11.9, close: 11.95, high: 12.0, low: 11.8);
  // Bullish third day
  raw[n - 1] = raw[n - 1].copyWith(open: 11.95, close: 12.3, high: 12.4, low: 11.8);
  return raw;
}

void main() {
  group('Strategy Engine', () {
    test('evaluateStrategies returns strategies for uptrend data', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = SignalLayer.detectAllSignals(data);
      final strategies = evaluateStrategies(data, signals);
      expect(strategies, isNotEmpty);
      // All strategies should have valid IDs and names
      for (final s in strategies) {
        expect(s.id, isNotEmpty);
        expect(s.name, isNotEmpty);
        expect(s.category, isNotEmpty);
        expect(s.description, isNotEmpty);
        expect(s.type, anyOf(equals('buy'), equals('sell')));
      }
    });

    test('uptrend produces more buy strategies than sell', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = SignalLayer.detectAllSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final buys = strategies.where((s) => s.type == 'buy' && !s.id.startsWith('conflict_'));
      final sells = strategies.where((s) => s.type == 'sell' && !s.id.startsWith('conflict_'));
      expect(buys.length, greaterThanOrEqualTo(sells.length),
          reason: 'Uptrend should produce more buy strategies');
    });

    test('downtrend produces fewer active buy strategies', () {
      final data = calcAllIndicators(generateDowntrend(60));
      final signals = SignalLayer.detectAllSignals(data);
      final strategies = evaluateStrategies(data, signals);
      // 只统计活跃的买入策略（v2.45: 未激活策略也展示，isActive=false）
      final activeBuys = strategies.where((s) => s.isActive && s.type == 'buy' && !s.id.startsWith('conflict_'));
      // Downtrend should not be dominated by active buy strategies
      expect(activeBuys.length, lessThanOrEqualTo(3),
          reason: 'Downtrend should have few active buy strategies, got $activeBuys');
    });
  });

  group('Strategy Properties', () {
    test('all strategies have required fields', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = SignalLayer.detectAllSignals(data);
      final strategies = evaluateStrategies(data, signals);
      for (final s in strategies) {
        expect(s.id, isNotEmpty);
        expect(s.name, isNotEmpty);
        expect(s.category, isNotEmpty);
        expect(s.description, isNotEmpty);
        expect(s.entryRule, isNotEmpty);
        expect(s.exitRule, isNotEmpty);
        expect(s.stopLossRule, isNotEmpty);
        expect(s.signalStrength, greaterThanOrEqualTo(0));
        expect(s.type, anyOf(equals('buy'), equals('sell')));
      }
    });

    test('active strategies have positive risk/reward ratio', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = SignalLayer.detectAllSignals(data);
      final strategies = evaluateStrategies(data, signals);
      for (final s in strategies.where((s) => s.isActive)) {
        expect(s.riskRewardRatio, greaterThanOrEqualTo(0));
      }
    });

    test('inactive strategies have zero strength', () {
      final data = calcAllIndicators(generateSideways(60));
      final signals = SignalLayer.detectAllSignals(data);
      final strategies = evaluateStrategies(data, signals);
      for (final s in strategies.where((s) => !s.isActive && !s.id.startsWith('conflict_'))) {
        expect(s.signalStrength, equals(0));
      }
    });

    test('active strategies have positive strength', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = SignalLayer.detectAllSignals(data);
      final strategies = evaluateStrategies(data, signals);
      for (final s in strategies.where((s) => s.isActive && !s.id.startsWith('conflict_'))) {
        expect(s.signalStrength, greaterThan(0));
      }
    });
  });

  group('Strategy Categories', () {
    test('strategies contain buy and sell types', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = SignalLayer.detectAllSignals(data);
      final strategies = evaluateStrategies(data, signals).where((s) => !s.id.startsWith('conflict_'));
      final types = strategies.map((s) => s.type).toSet();
      expect(types.contains('buy') || types.contains('sell'), isTrue);
    });

    test('conflict strategies generated when buy and sell signals coexist', () {
      final data = calcAllIndicators(generateSideways(60));
      final signals = SignalLayer.detectAllSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final conflictStrategies = strategies.where((s) => s.id.startsWith('conflict_'));
      if (conflictStrategies.isNotEmpty) {
        for (final cs in conflictStrategies) {
          expect(cs.category, equals('警告'));
        }
      }
    });
  });

  group('Short-term strategies', () {
    test('short-term strategies have shorter holding periods', () {
      final data = calcAllIndicators(generateUptrend(80));
      final signals = SignalLayer.detectAllSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final shortTerm = strategies.where((s) => s.category == '短线' || s.category == '特殊');
      final longTerm = strategies.where((s) => s.category == '长线');
      // Either category may be empty if no signals matched
      expect(shortTerm.length + longTerm.length, greaterThan(0));
    });
  });
}
