import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/next_session_predictor.dart';
import 'package:stock_analyzer/models/stock_models.dart';

/// v4.12 regression: on normal-length, varied history the next-session KNN must
/// produce real neighbors (sampleCount >= minSampleSize) instead of the
/// degenerate 50/50 neutral (sampleCount 0). Previously a strict `similarity >=
/// 0.5` radius filtered out almost every bar, so the "next-day prediction" was
/// stuck at 50% with 0 samples on real stocks.

/// Deterministic but diverse OHLCV series so few bars clear the old 0.5 radius.
List<HistoryKline> _variedSeries(int count) {
  final raw = <HistoryKline>[];
  var price = 20.0;
  for (var i = 0; i < count; i++) {
    final pct = ((i * 37) % 13 - 6) / 100.0; // spread across -6%..+6%
    final open = price;
    final close = price * (1 + pct);
    final high = math.max(open, close) * (1 + ((i * 17) % 5) / 200.0);
    final low = math.min(open, close) * (1 - ((i * 23) % 5) / 200.0);
    final volume = 1000.0 + ((i * 53) % 900);
    raw.add(HistoryKline(
      date: DateTime(2024, 1, 1).add(Duration(days: i)),
      open: open,
      high: high,
      low: low,
      close: close,
      volume: volume,
      amount: volume * close,
    ));
    price = close;
  }
  return calcAllIndicators(raw);
}

void main() {
  group('NextSessionPredictor K-nearest selection', () {
    test('varied 60-bar history yields real samples, not the 0-sample neutral',
        () {
      final data = _variedSeries(60);
      final prediction = NextSessionPredictor.predict(data);

      // The core fix: normal-length history must produce neighbors.
      expect(prediction.sampleCount,
          greaterThanOrEqualTo(NextSessionPredictor.minSampleSize));
      expect(prediction.nextCloseUpProbability, inInclusiveRange(0.0, 1.0));
      expect(prediction.downsideRiskProbability, inInclusiveRange(0.0, 1.0));
    });

    test('a shorter 20-bar varied history still produces samples', () {
      final data = _variedSeries(20);
      final prediction = NextSessionPredictor.predict(data);
      expect(prediction.sampleCount,
          greaterThanOrEqualTo(NextSessionPredictor.minSampleSize));
    });

    test('too-short history (<3 bars) still returns the safe neutral', () {
      final data = _variedSeries(2);
      final prediction = NextSessionPredictor.predict(data);
      expect(prediction.sampleCount, 0);
      expect(prediction.nextCloseUpProbability, closeTo(0.5, 0.001));
    });
  });
}
