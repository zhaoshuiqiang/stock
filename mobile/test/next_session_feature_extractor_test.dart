import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/next_session_feature_extractor.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('NextSessionFeatureExtractor', () {
    test('flags large rise with long upper shadow as pullback risk', () {
      final data = [
        _bar(0, close: 10, volume: 1000),
        _bar(1, open: 10.6, high: 11.2, low: 10.4, close: 10.7, volume: 3200),
      ];

      final features = NextSessionFeatureExtractor.extract(data);

      expect(features.changePct, closeTo(7, 0.01));
      expect(features.closePosition, closeTo(0.375, 0.001));
      expect(features.upperShadowRatio, greaterThan(0.6));
      expect(features.volumeRatio5, greaterThan(3));
      expect(features.scenarioTags, contains('高位回调风险'));
      expect(features.scenarioTags, contains('长上影分歧'));
      expect(features.riskWarnings, contains('不追高'));
    });

    test('flags heavy-volume weak close as volume stall', () {
      final data = [
        _bar(0, close: 10, volume: 1000),
        _bar(1, close: 10.1, volume: 1000),
        _bar(2, open: 10.2, high: 10.9, low: 10.1, close: 10.35, volume: 3500),
      ];

      final features = NextSessionFeatureExtractor.extract(data);

      expect(features.changePct, greaterThan(2));
      expect(features.volumeRatio5, greaterThan(2));
      expect(features.closePosition, lessThan(0.4));
      expect(features.scenarioTags, contains('放量滞涨'));
    });

    test('flags rising on weak volume as do-not-chase', () {
      final data = [
        _bar(0, close: 10, volume: 2000),
        _bar(1, close: 10.1, volume: 2100),
        _bar(2, open: 10.1, high: 10.5, low: 10.05, close: 10.45, volume: 900),
      ];

      final features = NextSessionFeatureExtractor.extract(data);

      expect(features.changePct, greaterThan(3));
      expect(features.volumeRatio5, lessThan(0.7));
      expect(features.scenarioTags, contains('缩量上涨不追'));
    });

    test('flags oversold lower-shadow stabilization as rebound watch', () {
      final data = [
        _bar(0, close: 10.5, volume: 1400),
        _bar(1, close: 10.0, volume: 1300),
        _bar(2, close: 9.6, volume: 1200),
        _bar(3, close: 9.2, volume: 1100),
        _bar(4, open: 9.15, high: 9.45, low: 8.75, close: 9.35, volume: 900),
      ];

      final features = NextSessionFeatureExtractor.extract(data);

      expect(features.return5, lessThan(-8));
      expect(features.lowerShadowRatio, greaterThan(0.55));
      expect(features.closePosition, greaterThan(0.75));
      expect(features.scenarioTags, contains('超跌反弹'));
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
  double turnover = 0,
  double rsi6 = 50,
  double k = 50,
  double d = 50,
  double j = 50,
  double macdHist = 0,
}) {
  final resolvedHigh = high == 10 ? close : high;
  final resolvedLow = low == 10 ? close : low;
  return HistoryKline(
    date: DateTime(2024, 1, day + 1),
    open: open,
    high: resolvedHigh,
    low: resolvedLow,
    close: close,
    volume: volume,
    turnover: turnover,
    rsi6: rsi6,
    k: k,
    d: d,
    j: j,
    macdHist: macdHist,
  );
}
