import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/next_session_predictor.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('NextSessionPredictor', () {
    test(
        'returns neutral low-confidence result when comparable samples are scarce',
        () {
      final prediction = NextSessionPredictor.predict([
        _bar(0, close: 10, volume: 1000),
        _bar(1, open: 10, high: 10.3, low: 9.9, close: 10.2, volume: 1100),
      ]);

      expect(prediction.sampleCount, 0);
      expect(prediction.nextOpenUpProbability, closeTo(0.5, 0.001));
      expect(prediction.nextCloseUpProbability, closeTo(0.5, 0.001));
      expect(prediction.confidence, lessThan(0.2));
    });

    test('caps bullish probability for large-rise long-upper-shadow risk', () {
      final data = <HistoryKline>[];
      for (var i = 0; i < 14; i++) {
        final base = 10.0 + i * 0.1;
        data.add(_bar(data.length, close: base, volume: 1000));
        data.add(_bar(
          data.length,
          open: base * 1.06,
          high: base * 1.12,
          low: base * 1.04,
          close: base * 1.07,
          volume: 3200,
        ));
        data.add(_bar(data.length, close: base * 1.085, volume: 1800));
      }
      const base = 12.0;
      data.add(_bar(data.length, close: base, volume: 1000));
      data.add(_bar(
        data.length,
        open: base * 1.06,
        high: base * 1.12,
        low: base * 1.04,
        close: base * 1.07,
        volume: 3200,
      ));

      final prediction = NextSessionPredictor.predict(data);

      expect(prediction.sampleCount, greaterThanOrEqualTo(8));
      expect(prediction.nextCloseUpProbability, lessThanOrEqualTo(0.55));
      expect(prediction.confidence, lessThanOrEqualTo(0.55));
      expect(prediction.scenarioTags, contains('高位回调风险'));
      expect(prediction.riskWarnings, contains('不追高'));
    });

    test('raises continuation probability for repeated strong-close patterns',
        () {
      final data = <HistoryKline>[];
      for (var i = 0; i < 16; i++) {
        final base = 10.0 + i * 0.08;
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
      const base = 12.0;
      data.add(_bar(data.length, close: base, volume: 1000));
      data.add(_bar(
        data.length,
        open: base * 1.01,
        high: base * 1.035,
        low: base * 1.005,
        close: base * 1.032,
        volume: 1300,
      ));

      final prediction = NextSessionPredictor.predict(data);

      expect(prediction.sampleCount, greaterThanOrEqualTo(8));
      expect(prediction.nextCloseUpProbability, greaterThan(0.6));
      expect(prediction.expectedNextCloseReturn, greaterThan(0));
      expect(prediction.confidence, greaterThan(0.45));
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
