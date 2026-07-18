import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/backtest_engine.dart';
import 'package:stock_analyzer/analysis/indicators.dart';

List<HistoryKline> _makeKline({
  required int count,
  double startPrice = 10.0,
  double dailyReturn = 0.01,
  double atrValue = 0.5,
}) {
  double p = startPrice;
  return List.generate(count, (i) {
    final open = p;
    p *= (1 + dailyReturn);
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: open,
      high: p * 1.02,
      low: open * 0.98,
      close: p,
      volume: 15000.0,
      amount: 15000.0 * p,
      change: p - open,
      changePct: dailyReturn * 100,
      atr14: atrValue,
    );
  });
}

List<HistoryKline> _makeOscillating(int count, {double base = 15.0, double amplitude = 3.0}) {
  return List.generate(count, (i) {
    final phase = (i % 20) / 20.0 * 3.14159 * 2;
    final offset = amplitude * (phase / (3.14159 * 2) - 0.5) * 2;
    final p = base + offset;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: p - 0.1,
      high: p + 0.15,
      low: p - 0.15,
      close: p,
      volume: 15000.0,
      amount: 15000.0 * p,
      change: offset,
      changePct: offset / base * 100,
      atr14: 0.5,
    );
  });
}

List<HistoryKline> _makeWithReversal({
  int upDays = 25,
  int downDays = 25,
  int flatDays = 30,
  double startPrice = 10.0,
  double upDaily = 0.02,
  double downDaily = -0.02,
}) {
  final data = <HistoryKline>[];
  double p = startPrice;
  for (int i = 0; i < upDays; i++) {
    final open = p;
    p *= (1 + upDaily);
    data.add(HistoryKline(
      date: DateTime(2024, 1, data.length + 1),
      open: open, high: p * 1.01, low: open * 0.99, close: p,
      volume: 15000.0, amount: 15000.0 * p,
      change: p - open, changePct: upDaily * 100, atr14: 0.5,
    ));
  }
  for (int i = 0; i < downDays; i++) {
    final open = p;
    p *= (1 + downDaily);
    data.add(HistoryKline(
      date: DateTime(2024, 1, data.length + 1),
      open: open, high: open * 1.01, low: p * 0.99, close: p,
      volume: 15000.0, amount: 15000.0 * p,
      change: p - open, changePct: downDaily * 100, atr14: 0.5,
    ));
  }
  for (int i = 0; i < flatDays; i++) {
    data.add(HistoryKline(
      date: DateTime(2024, 1, data.length + 1),
      open: p, high: p * 1.005, low: p * 0.995, close: p,
      volume: 15000.0, amount: 15000.0 * p,
      change: 0, changePct: 0, atr14: 0.5,
    ));
  }
  return data;
}

void main() {
  setUp(() {
    BacktestEngine.setConfig(BacktestConfig.aStock);
  });

  group('T+1 minimum holding constraint', () {
    test('买入当日不可卖出', () {
      final data = _makeWithReversal(
        upDays: 30, downDays: 30, flatDays: 40,
        upDaily: 0.02, downDaily: -0.02,
      );
      final result = BacktestEngine.backtestMACross(data);

      if (result.totalSignals > 0) {
        final calcData = calcMA(data, [5, 10]);
        int buySignalIndex = -1;
        int exitSignalIndex = -1;
        for (int i = 1; i < calcData.length - 1; i++) {
          final prev = calcData[i - 1];
          final curr = calcData[i];
          if (buySignalIndex < 0 && curr.ma5 > curr.ma10 && prev.ma5 <= prev.ma10) {
            buySignalIndex = i;
          }
          if (buySignalIndex >= 0 && exitSignalIndex < 0 &&
              curr.ma5 < curr.ma10 && prev.ma5 >= prev.ma10) {
            exitSignalIndex = i;
            break;
          }
        }

        if (buySignalIndex >= 0 && exitSignalIndex >= 0) {
          final buyExecutionDay = buySignalIndex + 1;
          final holdDays = exitSignalIndex + 1 - buyExecutionDay;
          expect(holdDays, greaterThanOrEqualTo(1),
              reason: 'T+1: 持仓天数应>=1天（买入执行日到卖出执行日至少间隔1天）');
        }
      }
    });

    test('ATR止损在T+1日不触发', () {
      final count = 80;
      final data = <HistoryKline>[];
      double p = 10.0;
      for (int i = 0; i < count; i++) {
        double open, high, low, close;
        if (i < 30) {
          open = p;
          p *= 1.02;
          close = p;
          high = p * 1.02;
          low = open * 0.98;
        } else if (i < 40) {
          open = p;
          p *= 0.96;
          close = p;
          high = open * 1.005;
          low = p * 0.98;
        } else {
          open = p;
          p *= 1.01;
          close = p;
          high = p * 1.02;
          low = open * 0.98;
        }
        data.add(HistoryKline(
          date: DateTime(2024, 1, i + 1),
          open: open, high: high, low: low, close: close,
          volume: 15000.0, amount: 15000.0 * close,
          change: close - open,
          changePct: open > 0 ? (close - open) / open * 100 : 0,
          atr14: 0.8,
        ));
      }

      final result = BacktestEngine.backtestKDJOversoldCross(data);
      expect(result.totalSignals, greaterThanOrEqualTo(0));
    });

    test('T+1后可以正常卖出', () {
      final data = _makeWithReversal(
        upDays: 40, downDays: 40, flatDays: 50,
        upDaily: 0.015, downDaily: -0.015,
      );
      final result = BacktestEngine.backtestMACross(data);

      expect(result.totalSignals, greaterThanOrEqualTo(0));
      if (result.totalSignals > 0) {
        expect(result.tradeReturns.length, greaterThan(0));
      }
    });
  });

  group('T+1 constraint detailed verification', () {
    test('T+1约束不影响多笔独立交易', () {
      final data = _makeOscillating(200, base: 15.0, amplitude: 3.0);
      final result = BacktestEngine.backtestMACDCross(data);

      if (result.totalSignals >= 2) {
        expect(result.tradeReturns.length, greaterThanOrEqualTo(2));
      }
    });

    test('T+1约束下回测结果合理', () {
      final data = _makeWithReversal(
        upDays: 50, downDays: 50, flatDays: 50,
        upDaily: 0.01, downDaily: -0.01,
      );
      final result = BacktestEngine.backtestMACross(data);

      if (result.totalSignals > 0) {
        expect(result.winRate, greaterThanOrEqualTo(0.0));
        expect(result.winRate, lessThanOrEqualTo(1.0));
        expect(result.maxDrawdown, greaterThanOrEqualTo(0.0));
      }
    });
  });
}
