import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/technical_scorer.dart';

/// Generate klines with a strong uptrend pattern.
List<HistoryKline> _uptrendData({int count = 60}) {
  double price = 10.0;
  final raw = List.generate(count, (i) {
    final open = price;
    price *= 1.02;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: open,
      high: price * 1.01,
      low: open * 0.99,
      close: price,
      volume: 10000.0 + (i % 5) * 2000,
      amount: 10000 * (open + price) / 2,
    );
  });
  return calcAllIndicators(raw);
}

/// Generate klines with a strong downtrend pattern.
List<HistoryKline> _downtrendData({int count = 60}) {
  double price = 30.0;
  final raw = List.generate(count, (i) {
    final open = price;
    price *= 0.98;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: open,
      high: open * 1.01,
      low: price * 0.99,
      close: price,
      volume: 10000.0 + (i % 5) * 2000,
      amount: 10000 * (open + price) / 2,
    );
  });
  return calcAllIndicators(raw);
}

void main() {
  group('TechnicalScorer', () {
    test('Uptrend produces higher total score than downtrend', () {
      final upData = _uptrendData();
      final downData = _downtrendData();

      final upResult = TechnicalScorer.score(upData, [], []);
      final downResult = TechnicalScorer.score(downData, [], []);

      expect(upResult.totalScore, greaterThan(downResult.totalScore),
          reason: 'Uptrend should score higher than downtrend');
    });

    test('All sub-scores are within valid ranges', () {
      final data = _uptrendData();
      final result = TechnicalScorer.score(data, [], []);

      expect(result.signalScore, inInclusiveRange(0.0, 3.0),
          reason: 'signalScore should be in [0, 3]');
      expect(result.trendScore, inInclusiveRange(0.0, 2.0),
          reason: 'trendScore should be in [0, 2]');
      expect(result.momentumScore, inInclusiveRange(0.0, 2.0),
          reason: 'momentumScore should be in [0, 2]');
      expect(result.volumeScore, inInclusiveRange(0.0, 1.5),
          reason: 'volumeScore should be in [0, 1.5]');
      expect(result.volatilityScore, inInclusiveRange(0.0, 1.5),
          reason: 'volatilityScore should be in [0, 1.5]');
      expect(result.totalScore, inInclusiveRange(0.0, 10.0),
          reason: 'totalScore should be in [0, 10]');
    });

    test('Trend score is higher for MA bullish alignment', () {
      final upData = _uptrendData();
      final downData = _downtrendData();

      final upResult = TechnicalScorer.score(upData, [], []);
      final downResult = TechnicalScorer.score(downData, [], []);

      expect(upResult.trendScore, greaterThan(downResult.trendScore),
          reason: 'Bullish MA alignment should have higher trend score');
    });

    test('Momentum score penalizes extreme BIAS', () {
      final data = _uptrendData();

      // Force moderate RSI so momentum baseline is not at ceiling
      final moderateData = List<HistoryKline>.from(data);
      moderateData[moderateData.length - 1] =
          moderateData[moderateData.length - 1].copyWith(rsi6: 55.0, bias6: 1.0);

      // Force extreme BIAS with same RSI
      final extremeData = List<HistoryKline>.from(data);
      extremeData[extremeData.length - 1] =
          extremeData[extremeData.length - 1].copyWith(rsi6: 55.0, bias6: 8.0);

      final moderateResult = TechnicalScorer.score(moderateData, [], []);
      final extremeResult = TechnicalScorer.score(extremeData, [], []);

      expect(extremeResult.momentumScore, lessThan(moderateResult.momentumScore),
          reason: 'Extreme BIAS should reduce momentum score');
    });

    test('Buy signals increase signal score', () {
      final data = _uptrendData();

      final noSignalResult = TechnicalScorer.score(data, [], []);

      final buySignals = [
        SignalItem(
          type: 'buy',
          indicator: 'MA',
          signal: '均线多头排列',
          description: 'test',
          strength: 80,
        ),
        SignalItem(
          type: 'buy',
          indicator: 'MACD',
          signal: 'MACD金叉',
          description: 'test',
          strength: 70,
        ),
      ];

      final withBuyResult = TechnicalScorer.score(data, buySignals, []);

      expect(withBuyResult.signalScore, greaterThan(noSignalResult.signalScore),
          reason: 'Buy signals should increase signal score');
    });
  });
}
