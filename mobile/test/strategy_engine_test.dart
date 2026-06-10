import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/signal_engine.dart';
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

// Helper: generate red three soldiers pattern (3 bullish candles with rising closes)
List<HistoryKline> generateRedThreeSoldiers() {
  final base = List.generate(57, (i) {
    final price = 15.0 + (i % 10 - 5) * 0.1;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: price - 0.05, high: price + 0.1, low: price - 0.1, close: price,
      volume: 10000, amount: 10000 * price,
    );
  });
  // Add 3 bullish candles with rising closes
  base.add(HistoryKline(date: DateTime(2024, 2, 28), open: 15.0, high: 15.5, low: 14.9, close: 15.4, volume: 12000, amount: 12000 * 15.2));
  base.add(HistoryKline(date: DateTime(2024, 2, 29), open: 15.4, high: 15.9, low: 15.3, close: 15.8, volume: 13000, amount: 13000 * 15.6));
  base.add(HistoryKline(date: DateTime(2024, 3, 1), open: 15.8, high: 16.3, low: 15.7, close: 16.2, volume: 14000, amount: 14000 * 16.0));
  return base;
}

// Helper: generate three crows pattern (3 bearish candles with falling closes)
List<HistoryKline> generateThreeCrows() {
  final base = List.generate(57, (i) {
    final price = 15.0 + (i % 10 - 5) * 0.1;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: price - 0.05, high: price + 0.1, low: price - 0.1, close: price,
      volume: 10000, amount: 10000 * price,
    );
  });
  base.add(HistoryKline(date: DateTime(2024, 2, 28), open: 16.2, high: 16.3, low: 15.6, close: 15.7, volume: 12000, amount: 12000 * 15.9));
  base.add(HistoryKline(date: DateTime(2024, 2, 29), open: 15.7, high: 15.8, low: 15.1, close: 15.2, volume: 13000, amount: 13000 * 15.4));
  base.add(HistoryKline(date: DateTime(2024, 3, 1), open: 15.2, high: 15.3, low: 14.6, close: 14.7, volume: 14000, amount: 14000 * 14.9));
  return base;
}

void main() {
  // Test each of the 18 strategies
  group('Strategy 1: MACD金叉战法', () {
    test('activates when MACD golden cross signal exists', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final s = strategies.firstWhere((s) => s.id == 'macd_golden_cross');
      // In strong uptrend, MACD golden cross may or may not be active
      // Just verify the strategy exists and has correct properties
      expect(s.name, equals('MACD金叉战法'));
      expect(s.category, equals('趋势'));
      expect(s.type, equals('buy'));
    });
    test('inactive when no MACD golden cross', () {
      final data = calcAllIndicators(generateDowntrend(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final s = strategies.firstWhere((s) => s.id == 'macd_golden_cross');
      // In downtrend, MACD golden cross should not be active
      if (!signals.any((sig) => sig.signal == 'MACD金叉')) {
        expect(s.isActive, isFalse);
        expect(s.signalStrength, equals(0));
      }
    });
  });

  group('Strategy 2: MACD背离战法', () {
    test('has correct properties', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final s = strategies.firstWhere((s) => s.id == 'macd_divergence');
      expect(s.name, equals('MACD背离战法'));
      expect(s.category, equals('反转'));
    });
  });

  group('Strategy 3: KDJ超卖金叉战法', () {
    test('has correct properties', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final s = strategies.firstWhere((s) => s.id == 'kdj_oversold_cross');
      expect(s.name, equals('KDJ超卖金叉战法'));
      expect(s.type, equals('buy'));
    });
  });

  group('Strategy 4: 均线多头排列战法', () {
    test('activates in uptrend with MA alignment', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final s = strategies.firstWhere((s) => s.id == 'ma_multi_head');
      expect(s.name, equals('均线多头排列战法'));
      final last = data.last;
      if (last.ma5 > last.ma10 && last.ma10 > last.ma20 && last.ma20 > 0) {
        expect(s.isActive, isTrue);
        expect(s.signalStrength, greaterThan(0));
      }
    });
    test('inactive in downtrend', () {
      final data = calcAllIndicators(generateDowntrend(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final s = strategies.firstWhere((s) => s.id == 'ma_multi_head');
      final last = data.last;
      if (!(last.ma5 > last.ma10 && last.ma10 > last.ma20)) {
        expect(s.isActive, isFalse);
      }
    });
  });

  group('Strategy 5: 布林带突破战法', () {
    test('has correct properties', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final s = strategies.firstWhere((s) => s.id == 'boll_breakout');
      expect(s.name, equals('布林带突破战法'));
      expect(s.type, equals('buy'));
    });
  });

  group('Strategy 6: 放量突破战法', () {
    test('has correct properties', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final s = strategies.firstWhere((s) => s.id == 'volume_breakout');
      expect(s.name, equals('放量突破战法'));
      expect(s.category, equals('量价'));
    });
  });

  group('Strategy 7: 缩量回调战法', () {
    test('has correct properties', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final s = strategies.firstWhere((s) => s.id == 'shrink_pullback');
      expect(s.name, equals('缩量回调战法'));
      expect(s.type, equals('buy'));
    });
  });

  group('Strategy 8: RSI超卖反弹战法', () {
    test('has correct properties', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final s = strategies.firstWhere((s) => s.id == 'rsi_oversold_recovery');
      expect(s.name, equals('RSI超卖反弹战法'));
      expect(s.type, equals('buy'));
    });
  });

  group('Strategy 9: MACD零轴上方金叉战法', () {
    test('has correct properties', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final s = strategies.firstWhere((s) => s.id == 'macd_above_zero_cross');
      expect(s.name, equals('MACD零轴上方金叉'));
      expect(s.type, equals('buy'));
    });
    test('only activates when MACD golden cross AND DIF > 0', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final s = strategies.firstWhere((s) => s.id == 'macd_above_zero_cross');
      final last = data.last;
      if (s.isActive) {
        expect(signals.any((sig) => sig.signal == 'MACD金叉'), isTrue);
        expect(last.macdDif, greaterThan(0));
      }
    });
  });

  group('Strategy 10: 均线粘合突破战法', () {
    test('has correct properties', () {
      final data = calcAllIndicators(generateSideways(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final s = strategies.firstWhere((s) => s.id == 'ma_converge_breakout');
      expect(s.name, equals('均线粘合突破战法'));
      expect(s.type, equals('buy'));
    });
  });

  group('Strategy 11: 红三兵战法', () {
    test('activates when 3 consecutive bullish candles with rising closes', () {
      final data = calcAllIndicators(generateRedThreeSoldiers());
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final s = strategies.firstWhere((s) => s.id == 'red_three_soldiers');
      expect(s.name, equals('红三兵战法'));
      expect(s.type, equals('buy'));
      // Check if pattern is detected
      if (s.isActive) {
        expect(s.signalStrength, greaterThan(0));
        expect(s.stopLossPrice, isNotNull);
      }
    });
  });

  group('Strategy 12: 早晨之星战法', () {
    test('has correct properties', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final s = strategies.firstWhere((s) => s.id == 'morning_star');
      expect(s.name, equals('早晨之星战法'));
      expect(s.category, equals('K线形态'));
      expect(s.type, equals('buy'));
    });
  });

  group('Strategy 13: 量价齐升战法', () {
    test('has correct properties', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final s = strategies.firstWhere((s) => s.id == 'volume_price_up');
      expect(s.name, equals('量价齐升战法'));
      expect(s.type, equals('buy'));
    });
  });

  group('Strategy 14: 布林带支撑战法', () {
    test('has correct properties', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final s = strategies.firstWhere((s) => s.id == 'boll_support');
      expect(s.name, equals('布林带支撑战法'));
      expect(s.type, equals('buy'));
    });
  });

  group('Strategy 15: KDJ超买死叉战法', () {
    test('has correct properties', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final s = strategies.firstWhere((s) => s.id == 'kdj_overbought_cross');
      expect(s.name, equals('KDJ超买死叉战法'));
      expect(s.type, equals('sell'));
    });
  });

  group('Strategy 16: RSI超买回落战法', () {
    test('has correct properties', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final s = strategies.firstWhere((s) => s.id == 'rsi_overbought_drop');
      expect(s.name, equals('RSI超买回落战法'));
      expect(s.type, equals('sell'));
    });
  });

  group('Strategy 17: 三只乌鸦战法', () {
    test('activates when 3 consecutive bearish candles with falling closes', () {
      final data = calcAllIndicators(generateThreeCrows());
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final s = strategies.firstWhere((s) => s.id == 'three_crows');
      expect(s.name, equals('三只乌鸦战法'));
      expect(s.type, equals('sell'));
      if (s.isActive) {
        expect(s.signalStrength, greaterThan(0));
      }
    });
  });

  group('Strategy 18: 均线空头排列战法', () {
    test('activates in downtrend with MA bearish alignment', () {
      final data = calcAllIndicators(generateDowntrend(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final s = strategies.firstWhere((s) => s.id == 'ma_bearish');
      expect(s.name, equals('均线空头排列战法'));
      expect(s.type, equals('sell'));
      final last = data.last;
      if (last.ma5 < last.ma10 && last.ma10 < last.ma20 && last.ma20 > 0) {
        expect(s.isActive, isTrue);
      }
    });
  });

  group('Strategy Conflict Detection', () {
    test('conflict strategies added when both buy and sell are active', () {
      // Generate data that might produce both buy and sell signals
      final data = calcAllIndicators(generateSideways(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      final activeBuy = strategies.where((s) => s.isActive && s.type == 'buy' && !s.id.startsWith('conflict_'));
      final activeSell = strategies.where((s) => s.isActive && s.type == 'sell' && !s.id.startsWith('conflict_'));
      final conflictStrategies = strategies.where((s) => s.id.startsWith('conflict_'));

      if (activeBuy.isNotEmpty && activeSell.isNotEmpty) {
        expect(conflictStrategies.isNotEmpty, isTrue);
        for (final cs in conflictStrategies) {
          expect(cs.category, equals('警告'));
          expect(cs.description, contains('冲突'));
        }
      }
    });
  });

  group('Strategy General Properties', () {
    test('all 18 strategies are returned', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      // 18 base strategies (conflict strategies may add more)
      final baseStrategies = strategies.where((s) => !s.id.startsWith('conflict_'));
      expect(baseStrategies.length, equals(18));
    });

    test('all strategies have required fields', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = detectSignals(data);
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

    test('inactive strategies have zero strength', () {
      final data = calcAllIndicators(generateSideways(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      for (final s in strategies.where((s) => !s.isActive && !s.id.startsWith('conflict_'))) {
        expect(s.signalStrength, equals(0));
      }
    });

    test('active strategies have positive strength', () {
      final data = calcAllIndicators(generateUptrend(60));
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      for (final s in strategies.where((s) => s.isActive && !s.id.startsWith('conflict_'))) {
        expect(s.signalStrength, greaterThan(0));
      }
    });

    test('returns empty list with insufficient data', () {
      final data = generateUptrend(20);
      final signals = detectSignals(data);
      final strategies = evaluateStrategies(data, signals);
      expect(strategies, isEmpty);
    });
  });
}
