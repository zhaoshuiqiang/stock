import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/signal_layer.dart';
import 'package:stock_analyzer/analysis/signal_detector.dart';
import 'package:stock_analyzer/analysis/scoring_config.dart';

List<HistoryKline> _baseData({int count = 40}) {
  final prices = List.generate(count, (i) => 10.0 + i * 0.1);
  final raw = List.generate(prices.length, (i) {
    final price = prices[i];
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: price * 0.99,
      high: price * 1.02,
      low: price * 0.98,
      close: price,
      volume: 10000.0 + (i % 5) * 2000,
      amount: 10000 * price,
      change: i > 0 ? price - prices[i - 1] : 0,
      changePct: i > 0 && prices[i - 1] > 0
          ? (price - prices[i - 1]) / prices[i - 1] * 100
          : 0,
    );
  });
  return calcAllIndicators(raw);
}

void main() {
  group('涨停打开信号', () {
    test('检测到涨停打开（涨幅>=9.5%但未封板）', () {
      var data = _baseData();
      final n = data.length;
      final prevClose = data[n - 2].close;
      final lastClose = prevClose * 1.096;
      final lastHigh = prevClose * 1.12;
      data[n - 1] = data[n - 1].copyWith(
        open: prevClose * 1.095,
        high: lastHigh,
        low: prevClose * 1.08,
        close: lastClose,
      );
      // Verify the data is correct
      expect(data[n - 1].close, lastClose);
      expect(data[n - 2].close, prevClose);
      final changePct = (data[n - 1].close - data[n - 2].close) / data[n - 2].close * 100;
      expect(changePct, greaterThanOrEqualTo(9.5));
      expect(data[n - 1].high, greaterThan(data[n - 1].close * 1.005));

      final signals = SignalDetector.detectLayeredSignals(data, code: '600001');
      final limitOpen = signals.where((s) => s.signal == '涨停打开');
      expect(limitOpen.isNotEmpty, true, reason: 'Should detect 涨停打开 signal, got ${signals.map((s) => s.signal).toList()}');
      expect(limitOpen.first.type, 'sell');
      expect(limitOpen.first.indicator, '涨停板');
      expect(limitOpen.first.strength, 80);
      expect(limitOpen.first.confidence, 0.80);
    });

    test('科创板涨停打开（涨幅>=19.5%）', () {
      var data = _baseData();
      final n = data.length;
      final prevClose = data[n - 2].close;
      data[n - 1] = data[n - 1].copyWith(
        open: prevClose * 1.15,
        high: prevClose * 1.25,
        low: prevClose * 1.10,
        close: prevClose * 1.196,
      );

      final signals = SignalLayer.detectAllSignals(data, code: '688001');
      final limitOpen = signals.where((s) => s.signal == '涨停打开');
      expect(limitOpen.isNotEmpty, true, reason: 'Should detect 涨停打开 for 科创板');
    });

    test('封板成功不触发涨停打开', () {
      var data = _baseData();
      final n = data.length;
      final prevClose = data[n - 2].close;
      data[n - 1] = data[n - 1].copyWith(
        open: prevClose * 1.095,
        high: prevClose * 1.10,
        low: prevClose * 1.095,
        close: prevClose * 1.10,
      );

      final signals = SignalLayer.detectAllSignals(data, code: '600001');
      final limitOpen = signals.where((s) => s.signal == '涨停打开');
      expect(limitOpen.isEmpty, true, reason: 'Should not detect 涨停打开 when sealed');
    });

    test('涨幅不足不触发涨停打开', () {
      var data = _baseData();
      final n = data.length;
      final prevClose = data[n - 2].close;
      data[n - 1] = data[n - 1].copyWith(
        open: prevClose * 1.05,
        high: prevClose * 1.08,
        low: prevClose * 1.04,
        close: prevClose * 1.06,
      );

      final signals = SignalLayer.detectAllSignals(data, code: '600001');
      final limitOpen = signals.where((s) => s.signal == '涨停打开');
      expect(limitOpen.isEmpty, true, reason: 'Should not detect 涨停打开 when change < 9.5%');
    });
  });

  group('涨停回封信号', () {
    test('检测到涨停回封（涨停封板但盘中曾打开）', () {
      var data = _baseData();
      final n = data.length;
      final prevClose = data[n - 2].close;
      data[n - 1] = data[n - 1].copyWith(
        open: prevClose * 1.095,
        high: prevClose * 1.1001,
        low: prevClose * 1.08,
        close: prevClose * 1.10,
      );

      final signals = SignalLayer.detectAllSignals(data, code: '600001');
      final limitReseal = signals.where((s) => s.signal == '涨停回封');
      expect(limitReseal.isNotEmpty, true, reason: 'Should detect 涨停回封 signal');
      expect(limitReseal.first.type, 'buy');
      expect(limitReseal.first.indicator, '涨停板');
      expect(limitReseal.first.strength, 75);
      expect(limitReseal.first.confidence, 0.75);
    });

    test('盘中未打开不触发涨停回封', () {
      var data = _baseData();
      final n = data.length;
      final prevClose = data[n - 2].close;
      data[n - 1] = data[n - 1].copyWith(
        open: prevClose * 1.095,
        high: prevClose * 1.1001,
        low: prevClose * 1.095,
        close: prevClose * 1.10,
      );

      final signals = SignalLayer.detectAllSignals(data, code: '600001');
      final limitReseal = signals.where((s) => s.signal == '涨停回封');
      expect(limitReseal.isEmpty, true, reason: 'Should not detect 涨停回封 when never opened intraday');
    });
  });

  group('尾盘急拉信号', () {
    test('检测到尾盘急拉（涨幅>3%，上影线占比>0.5，收盘位置<0.5）', () {
      var data = _baseData();
      final n = data.length;
      final prevClose = data[n - 2].close;
      data[n - 1] = data[n - 1].copyWith(
        open: prevClose * 1.02,
        high: prevClose * 1.08,
        low: prevClose * 1.01,
        close: prevClose * 1.04,
      );

      final signals = SignalLayer.detectAllSignals(data, code: '600001');
      final latePull = signals.where((s) => s.signal == '尾盘急拉');
      expect(latePull.isNotEmpty, true, reason: 'Should detect 尾盘急拉 signal');
      expect(latePull.first.type, 'sell');
      expect(latePull.first.indicator, '尾盘');
      expect(latePull.first.strength, 70);
      expect(latePull.first.confidence, 0.70);
    });

    test('涨幅不足不触发尾盘急拉', () {
      var data = _baseData();
      final n = data.length;
      final prevClose = data[n - 2].close;
      data[n - 1] = data[n - 1].copyWith(
        open: prevClose * 1.01,
        high: prevClose * 1.05,
        low: prevClose * 1.00,
        close: prevClose * 1.02,
      );

      final signals = SignalLayer.detectAllSignals(data, code: '600001');
      final latePull = signals.where((s) => s.signal == '尾盘急拉');
      expect(latePull.isEmpty, true, reason: 'Should not detect 尾盘急拉 when change <= 3%');
    });
  });

  group('尾盘急跌信号', () {
    test('跌幅不足不触发尾盘急跌', () {
      var data = _baseData();
      final n = data.length;
      final prevClose = data[n - 2].close;
      data[n - 1] = data[n - 1].copyWith(
        open: prevClose * 0.99,
        high: prevClose * 0.995,
        low: prevClose * 0.985,
        close: prevClose * 0.99,
      );

      final signals = SignalLayer.detectAllSignals(data, code: '600001');
      final lateDrop = signals.where((s) => s.signal == '尾盘急跌');
      expect(lateDrop.isEmpty, true, reason: 'Should not detect 尾盘急跌 when decline <= 2%');
    });

    test('收盘位置过高不触发尾盘急跌', () {
      var data = _baseData();
      final n = data.length;
      final prevClose = data[n - 2].close;
      data[n - 1] = data[n - 1].copyWith(
        open: prevClose * 0.97,
        high: prevClose * 0.98,
        low: prevClose * 0.93,
        close: prevClose * 0.96,
      );

      final signals = SignalLayer.detectAllSignals(data, code: '600001');
      final lateDrop = signals.where((s) => s.signal == '尾盘急跌');
      expect(lateDrop.isEmpty, true, reason: 'Should not detect 尾盘急跌 when closePosition >= 0.3');
    });
  });

  group('v4.7 signal de-emphasis flags', () {
    tearDown(() {
      ScoringConfig.deemphasizeTrendStrength = false;
      ScoringConfig.deemphasizeBreakoutChase = false;
    });

    test('P1 deemphasizeTrendStrength lowers 趋势强度强劲 buy strength', () {
      var data = _baseData();
      final n = data.length;
      data[n - 1] =
          data[n - 1].copyWith(adx14: 30.0, plusDi14: 30.0, minusDi14: 15.0);

      ScoringConfig.deemphasizeTrendStrength = false;
      var sig = SignalDetector.detectLayeredSignals(data)
          .firstWhere((s) => s.signal == '趋势强度强劲');
      expect(sig.strength, 75);
      expect(sig.confidence, 0.8);

      ScoringConfig.deemphasizeTrendStrength = true;
      sig = SignalDetector.detectLayeredSignals(data)
          .firstWhere((s) => s.signal == '趋势强度强劲');
      expect(sig.strength, 50);
      expect(sig.confidence, 0.55);
    });

    test('P2 deemphasizeBreakoutChase lowers 趋势突破上轨 strength', () {
      var data = _baseData();
      final n = data.length;
      data[n - 2] = data[n - 2].copyWith(close: 18.0, bollUpper: 20.0);
      data[n - 1] = data[n - 1].copyWith(
          close: 25.0,
          high: 26.0,
          bollUpper: 20.0,
          adx14: 30.0,
          plusDi14: 30.0,
          minusDi14: 15.0);

      ScoringConfig.deemphasizeBreakoutChase = false;
      var sig = SignalDetector.detectLayeredSignals(data)
          .firstWhere((s) => s.signal == '趋势突破上轨');
      expect(sig.strength, 75);

      ScoringConfig.deemphasizeBreakoutChase = true;
      sig = SignalDetector.detectLayeredSignals(data)
          .firstWhere((s) => s.signal == '趋势突破上轨');
      expect(sig.strength, 50);
    });
  });
}
