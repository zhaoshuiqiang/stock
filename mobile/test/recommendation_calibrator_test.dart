import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/recommendation_calibrator.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('RecommendationCalibrator', () {
    test('caps weak buy recommendation when sell conflict is present', () {
      final result = RecommendationCalibrator.calibrateScore(
        score: 6,
        data: _klines(close: [10, 10.1, 10.0, 9.9, 9.8]),
        buySignals: [_signal(type: 'buy', indicator: 'OBV', strength: 1)],
        sellSignals: [_signal(type: 'sell', indicator: 'MA', strength: 2)],
      );

      expect(result.score, equals(5));
      expect(result.reason, isNotEmpty);
    });

    test('keeps buy recommendation when buy evidence clearly dominates', () {
      final result = RecommendationCalibrator.calibrateScore(
        score: 7,
        data: _klines(close: [10, 10.2, 10.4, 10.8, 11.2]),
        buySignals: [
          _signal(type: 'buy', indicator: 'MA', strength: 3),
          _signal(type: 'buy', indicator: 'MACD', strength: 3),
          _signal(type: 'buy', indicator: 'VOL', strength: 2),
        ],
        sellSignals: const [],
      );

      expect(result.score, equals(7));
      expect(result.reason, isEmpty);
    });

    test('caps 0-100 strength buy recommendation when sell conflict is close',
        () {
      final result = RecommendationCalibrator.calibrateScore(
        score: 6,
        data: _klines(close: [10, 10.1, 10.0, 9.95, 9.9]),
        buySignals: [
          _signal(type: 'buy', indicator: 'MACD', strength: 80),
          _signal(type: 'buy', indicator: 'OBV', strength: 80),
        ],
        sellSignals: [
          _signal(type: 'sell', indicator: 'MA', strength: 78),
          _signal(type: 'sell', indicator: 'KDJ', strength: 78),
        ],
      );

      expect(result.score, equals(5));
      expect(result.reason, isNotEmpty);
    });

    test('keeps 0-100 strength buy recommendation when evidence dominates', () {
      final result = RecommendationCalibrator.calibrateScore(
        score: 7,
        data: _klines(close: [10, 10.2, 10.4, 10.8, 11.2]),
        buySignals: [
          _signal(type: 'buy', indicator: 'MA', strength: 85),
          _signal(type: 'buy', indicator: 'MACD', strength: 85),
          _signal(type: 'buy', indicator: 'VOL', strength: 70),
        ],
        sellSignals: [
          _signal(type: 'sell', indicator: 'KDJ', strength: 45),
        ],
      );

      expect(result.score, equals(7));
      expect(result.reason, isEmpty);
    });

    test('caps sell recommendation after sharp decline with rebound evidence',
        () {
      final result = RecommendationCalibrator.calibrateScore(
        score: 3,
        data: _klines(close: [10, 9.6, 9.2, 8.9, 8.6], rsi6: 28, wr14: 86),
        buySignals: [_signal(type: 'buy', indicator: 'WR', strength: 2)],
        sellSignals: [_signal(type: 'sell', indicator: 'MACD', strength: 2)],
        currentChangePct: -4.2,
      );

      expect(result.score, equals(4));
      expect(result.reason, isNotEmpty);
    });

    test('keeps sell recommendation when sell evidence is clean and dominant',
        () {
      final result = RecommendationCalibrator.calibrateScore(
        score: 3,
        data: _klines(close: [10, 9.9, 9.7, 9.6, 9.5], rsi6: 42, wr14: 45),
        buySignals: const [],
        sellSignals: [
          _signal(type: 'sell', indicator: 'MA', strength: 3),
          _signal(type: 'sell', indicator: 'MACD', strength: 3),
        ],
        currentChangePct: -1.2,
      );

      expect(result.score, equals(3));
      expect(result.reason, isEmpty);
    });
  });
}

List<HistoryKline> _klines({
  required List<double> close,
  double rsi6 = 55,
  double wr14 = 50,
}) {
  return List.generate(close.length, (i) {
    final c = close[i];
    final prev = i == 0 ? c : close[i - 1];
    final recent = close.sublist(0, i + 1);
    final ma = recent.reduce((a, b) => a + b) / recent.length;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: prev,
      high: c * 1.02,
      low: c * 0.98,
      close: c,
      volume: 1000 + i * 100,
      amount: c * (1000 + i * 100),
      changePct: prev > 0 ? (c / prev - 1) * 100 : 0,
      ma5: ma,
      ma10: ma,
      ma20: ma,
      rsi6: rsi6,
      wr14: wr14,
      bias6: ma > 0 ? (c / ma - 1) * 100 : 0,
    );
  });
}

SignalItem _signal({
  required String type,
  required String indicator,
  required int strength,
}) {
  return SignalItem(
    type: type,
    indicator: indicator,
    signal: '$indicator-$type',
    strength: strength,
    duration: SignalDuration.shortTerm,
    confidence: 0.8,
  );
}
