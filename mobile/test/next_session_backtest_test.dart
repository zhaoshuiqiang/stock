import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/next_session_backtest.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('NextSessionBacktest', () {
    test('walk-forward evaluation does not use future comparable samples', () {
      final data = [
        _bar(0, close: 10, volume: 1000),
        _bar(1, open: 10.1, high: 10.4, low: 10.0, close: 10.35, volume: 1200),
        _bar(2, close: 10.5, volume: 1100),
        _bar(3, open: 10.6, high: 10.9, low: 10.5, close: 10.85, volume: 1300),
        _bar(4, close: 11.0, volume: 1200),
      ];

      final result = NextSessionBacktest.run(data, minTrainingBars: 1);

      expect(result.evaluations.first.index, 1);
      expect(result.evaluations.first.prediction.sampleCount, 0);
    });

    test('computes direction, brier, return and calibration metrics', () {
      final data = <HistoryKline>[];
      for (var i = 0; i < 20; i++) {
        final base = 10.0 + i * 0.06;
        data.add(_bar(data.length, close: base, volume: 1000));
        data.add(_bar(
          data.length,
          open: base * 1.01,
          high: base * 1.035,
          low: base * 1.005,
          close: base * 1.032,
          volume: 1300,
        ));
        data.add(_bar(data.length, close: base * 1.05, volume: 1400));
      }

      final result = NextSessionBacktest.run(data, minTrainingBars: 5);

      expect(result.totalPredictions, greaterThan(0));
      expect(result.nextCloseDirectionAccuracy, inInclusiveRange(0, 1));
      expect(result.nextOpenDirectionAccuracy, inInclusiveRange(0, 1));
      expect(result.brierScore, inInclusiveRange(0, 1));
      expect(result.averageNextCloseReturn, isNotNaN);
      expect(result.calibrationBuckets, isNotEmpty);
      expect(
        result.calibrationBuckets.every(
          (bucket) =>
              bucket.lowerBound < bucket.upperBound && bucket.count >= 0,
        ),
        isTrue,
      );
    });
  });
}

HistoryKline _bar(
  int day, {
  double open = 10,
  double high = 10,
  double low = 10,
  required double close,
  required double volume,
}) {
  final resolvedHigh = high == 10 ? close : high;
  final resolvedLow = low == 10 ? close : low;
  return HistoryKline(
    date: DateTime(2024, 1, 1).add(Duration(days: day)),
    open: open,
    high: resolvedHigh,
    low: resolvedLow,
    close: close,
    volume: volume,
  );
}
