import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/signal_engine.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('generateAnalysis next-session integration', () {
    test('adds next-session prediction payload to analysis result', () {
      final analysis = generateAnalysis(_continuationFixture(), null);
      final nextSession =
          analysis.nextDayPrediction?['next_session'] as Map<String, dynamic>?;

      expect(nextSession, isNotNull);
      expect(nextSession!['next_close_up_probability'], isA<double>());
      expect(nextSession['confidence'], isA<double>());
      expect(nextSession['scenario_tags'], isA<List>());
      expect(analysis.dimensionScores?['次交易预测'], isNotNull);
    });

    test('downgrades aggressive buy recommendation on high pullback risk', () {
      final analysis = generateAnalysis(_largeRiseUpperShadowFixture(), null);
      final nextSession =
          analysis.nextDayPrediction?['next_session'] as Map<String, dynamic>?;

      expect(nextSession?['scenario_tags'], contains('高位回调风险'));
      expect(analysis.recommendation, isNot(anyOf('强烈买入', '买入')));
      expect(
        analysis.suggestions.first,
        contains('次交易日回调风险'),
      );
    });
  });
}

List<HistoryKline> _continuationFixture() {
  final data = <HistoryKline>[];
  for (var i = 0; i < 18; i++) {
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
  return data;
}

List<HistoryKline> _largeRiseUpperShadowFixture() {
  final data = <HistoryKline>[];
  for (var i = 0; i < 18; i++) {
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
  return data;
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
