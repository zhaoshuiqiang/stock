import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/signal_layer.dart';

// ─── Helper: convert a list of prices into HistoryKline objects ───
List<HistoryKline> _pricesToKlines(List<double> prices, {List<double>? volumes}) {
  return List.generate(prices.length, (i) {
    final price = prices[i];
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: price * 0.99,
      high: price * 1.02,
      low: price * 0.98,
      close: price,
      volume: volumes != null && i < volumes.length ? volumes[i] : 10000.0 + (i % 5) * 2000,
      amount: 10000 * price,
      change: i > 0 ? price - prices[i - 1] : 0,
      changePct: i > 0 && prices[i - 1] > 0
          ? (price - prices[i - 1]) / prices[i - 1] * 100
          : 0,
    );
  });
}

/// Generate base kline data with indicators calculated.
List<HistoryKline> _baseData({int count = 40}) {
  final prices = List.generate(count, (i) => 15.0 + (i % 10) * 0.5);
  return calcAllIndicators(_pricesToKlines(prices));
}

void main() {
  // ─── detectAllSignals edge cases ───
  group('detectAllSignals returns empty for empty data', () {
    test('empty list returns no signals', () {
      final signals = SignalLayer.detectAllSignals([]);
      expect(signals, isEmpty);
    });
  });

  group('detectAllSignals returns empty for insufficient data', () {
    test('single data point returns no signals', () {
      final data = [HistoryKline(date: DateTime(2024, 1, 1), close: 10.0)];
      final signals = SignalLayer.detectAllSignals(data);
      expect(signals, isEmpty);
    });

    test('zero-length list returns no signals', () {
      final signals = SignalLayer.detectAllSignals(<HistoryKline>[]);
      expect(signals, isEmpty);
    });
  });

  group('detectAllSignals merges layered and unique signals without duplicates', () {
    test('layered and unique signals are merged, duplicates by signal name removed', () {
      // Use enough data to trigger both layered and unique signals
      var data = _baseData(count: 40);
      final n = data.length;

      // Set up conditions for BOLL squeeze breakout (unique signal)
      // Need bollMid > 0 and contracting bandwidth
      // Also set up a layered signal (e.g., MA golden cross)
      data[n - 2] = data[n - 2].copyWith(
        ma5: 14.0,
        ma10: 15.0,
        bollUpper: 17.0,
        bollMid: 15.0,
        bollLower: 13.0,
      );
      data[n - 1] = data[n - 1].copyWith(
        ma5: 16.0,
        ma10: 15.0,
        bollUpper: 17.0,
        bollMid: 15.0,
        bollLower: 13.0,
      );

      final signals = SignalLayer.detectAllSignals(data);

      // Verify no duplicate signal names
      final signalNames = signals.map((s) => s.signal).toList();
      expect(signalNames.toSet().length, equals(signalNames.length),
          reason: 'No duplicate signal names should exist');
    });

    test('unique signals with same name as layered signal are not added', () {
      // Create data where both layered and unique would produce "缩量上涨"
      // The layered signal from SignalDetector uses "缩量上涨" and the unique
      // _detectVolumePriceDivergence also uses "缩量上涨"
      // We just verify dedup works by checking no duplicate names
      var data = _baseData(count: 40);
      final signals = SignalLayer.detectAllSignals(data);
      final names = signals.map((s) => s.signal).toList();
      expect(names.toSet().length, equals(names.length));
    });
  });

  group('detectUniqueSignals detects BOLL squeeze pattern', () {
    test('BOLL squeeze breakout detected when bandwidth contracts and price breaks upper band', () {
      // Build data with contracting BOLL bandwidth and breakout
      final raw = List.generate(30, (i) {
        // Stable price with gradually narrowing BOLL bands
        final price = 15.0 + (i % 3 - 1) * 0.01;
        return HistoryKline(
          date: DateTime(2024, 1, i + 1),
          open: price,
          high: price + 0.02,
          low: price - 0.02,
          close: price,
          volume: 10000.0,
          amount: 10000 * price,
        );
      });
      var data = calcAllIndicators(raw);
      final n = data.length;

      // Force BOLL squeeze conditions:
      // - bollMid > 0
      // - bandwidth contracting for last 5 days
      // - current bandwidth <= minBw * 1.1
      // - close > bollUpper and volume > avgVol * 1.5 for breakout
      final bollMid = 15.0;
      // Create gradually narrowing bandwidths for last 20 bars
      for (int i = n - 20; i < n; i++) {
        final step = i - (n - 20); // 0..19
        final bw = 10.0 - step * 0.3; // narrowing from 10% to ~4.3%
        final halfBw = bollMid * bw / 200;
        data[i] = data[i].copyWith(
          bollUpper: bollMid + halfBw,
          bollMid: bollMid,
          bollLower: bollMid - halfBw,
        );
      }
      // Last bar: breakout above upper band with high volume
      data[n - 1] = data[n - 1].copyWith(
        close: data[n - 1].bollUpper + 0.5,
        volume: 50000.0, // much higher than average
        bollUpper: data[n - 1].bollUpper,
        bollMid: data[n - 1].bollMid,
        bollLower: data[n - 1].bollLower,
      );

      final signals = SignalLayer.detectUniqueSignals(data);
      final squeeze = signals.where((s) => s.signal == '布林带收口蓄势');
      expect(squeeze.isNotEmpty, true, reason: 'Should detect BOLL squeeze signal');

      final breakout = signals.where((s) => s.signal == '布林带放量突破上轨');
      expect(breakout.isNotEmpty, true, reason: 'Should detect BOLL upper breakout with volume');
      expect(breakout.first.type, 'buy');
    });

    test('BOLL squeeze with lower band breakout detected', () {
      final raw = List.generate(30, (i) {
        final price = 15.0 + (i % 3 - 1) * 0.01;
        return HistoryKline(
          date: DateTime(2024, 1, i + 1),
          open: price,
          high: price + 0.02,
          low: price - 0.02,
          close: price,
          volume: 10000.0,
          amount: 10000 * price,
        );
      });
      var data = calcAllIndicators(raw);
      final n = data.length;

      final bollMid = 15.0;
      for (int i = n - 20; i < n; i++) {
        final step = i - (n - 20);
        final bw = 10.0 - step * 0.3;
        final halfBw = bollMid * bw / 200;
        data[i] = data[i].copyWith(
          bollUpper: bollMid + halfBw,
          bollMid: bollMid,
          bollLower: bollMid - halfBw,
        );
      }
      // Last bar: breakout below lower band
      data[n - 1] = data[n - 1].copyWith(
        close: data[n - 1].bollLower - 0.5,
        volume: 10000.0, // normal volume, not enough for upper breakout
        bollUpper: data[n - 1].bollUpper,
        bollMid: data[n - 1].bollMid,
        bollLower: data[n - 1].bollLower,
      );

      final signals = SignalLayer.detectUniqueSignals(data);
      final lowerBreak = signals.where((s) => s.signal == '布林带跌破下轨');
      expect(lowerBreak.isNotEmpty, true, reason: 'Should detect BOLL lower band breakout');
      expect(lowerBreak.first.type, 'sell');
    });
  });

  group('detectUniqueSignals detects volume-price divergence', () {
    test('放量滞涨 detected when volume surges but price stagnates', () {
      // Build data: 15+ bars, last 3 days have high volume but price barely moves
      final prices = List.generate(20, (i) => 15.0 + (i % 5) * 0.1);
      final volumes = List.generate(20, (i) {
        if (i >= 17) return 50000.0; // last 3 days high volume
        return 10000.0;
      });
      final data = calcAllIndicators(_pricesToKlines(prices, volumes: volumes));
      final n = data.length;

      // Force the last 3 days avg volume > 10-day avg * 1.5
      // and price change over 3 days < 2%
      data[n - 1] = data[n - 1].copyWith(
        close: 15.2, // similar to 4 days ago
        volume: 50000.0,
      );
      data[n - 4] = data[n - 4].copyWith(close: 15.1); // 4 days ago close
      // Ensure last 10 days have lower avg volume
      for (int i = n - 10; i < n - 3; i++) {
        data[i] = data[i].copyWith(volume: 10000.0);
      }
      data[n - 2] = data[n - 2].copyWith(volume: 50000.0);
      data[n - 3] = data[n - 3].copyWith(volume: 50000.0);

      final signals = SignalLayer.detectUniqueSignals(data);
      final stagnation = signals.where((s) => s.signal == '放量滞涨');
      expect(stagnation.isNotEmpty, true, reason: 'Should detect 放量滞涨 signal');
      expect(stagnation.first.type, 'sell');
    });

    test('缩量上涨 detected when price rises with declining volume', () {
      // Algorithm: priceChange5d > 3% and volume strictly declining for last 5 bars
      // (data[n-1].volume < data[n-2].volume < ... < data[n-5].volume)
      var data = _baseData(count: 20);
      final n = data.length;

      // Force last.close / data[n-6].close > 1.03 (price rises >3% in 5 days)
      data[n - 6] = data[n - 6].copyWith(close: 10.0);
      data[n - 1] = data[n - 1].copyWith(close: 11.0); // +10% > 3%

      // Force volume strictly declining for last 5 bars
      data[n - 5] = data[n - 5].copyWith(volume: 50000.0);
      data[n - 4] = data[n - 4].copyWith(volume: 40000.0);
      data[n - 3] = data[n - 3].copyWith(volume: 30000.0);
      data[n - 2] = data[n - 2].copyWith(volume: 20000.0);
      data[n - 1] = data[n - 1].copyWith(volume: 10000.0);

      final signals = SignalLayer.detectUniqueSignals(data);
      final shrinkRise = signals.where((s) => s.signal == '缩量上涨');
      expect(shrinkRise.isNotEmpty, true, reason: 'Should detect 缩量上涨 signal');
      expect(shrinkRise.first.type, 'sell');
    });

    test('缩量止跌 detected after significant decline with shrinking volume', () {
      // Algorithm: priceChange10d < -10%, recent3Change.abs() < 1%, avg3Vol < avg10Vol * 0.5
      var data = _baseData(count: 20);
      final n = data.length;

      // Force 10-day decline > 10%: last.close / data[n-11].close - 1 < -0.10
      data[n - 11] = data[n - 11].copyWith(close: 20.0);
      data[n - 1] = data[n - 1].copyWith(close: 15.0); // -25% < -10%

      // Force recent 3 days price stable: |last.close / data[n-4].close - 1| < 1%
      data[n - 4] = data[n - 4].copyWith(close: 15.0); // same as last

      // Force avg3Vol < avg10Vol * 0.5
      // Set last 3 days volume very low, previous 7 days higher
      for (int i = n - 10; i < n - 3; i++) {
        data[i] = data[i].copyWith(volume: 20000.0);
      }
      data[n - 3] = data[n - 3].copyWith(volume: 3000.0);
      data[n - 2] = data[n - 2].copyWith(volume: 3000.0);
      data[n - 1] = data[n - 1].copyWith(volume: 3000.0);

      final signals = SignalLayer.detectUniqueSignals(data);
      final stopDecline = signals.where((s) => s.signal == '缩量止跌');
      expect(stopDecline.isNotEmpty, true, reason: 'Should detect 缩量止跌 signal');
      expect(stopDecline.first.type, 'buy');
    });
  });
}
