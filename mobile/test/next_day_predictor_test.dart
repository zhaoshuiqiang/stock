import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/next_day_predictor.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('NextDayPredictor', () {
    test('low sample prediction is blended toward neutral probabilities', () {
      final data = _patternData(matchCount: 4, matchOutcomePct: 2.0);

      final result = NextDayPredictor.predict(data, null);

      expect(result.sampleCount, lessThan(NextDayPredictor.minSampleSize));
      expect(result.upProbability, lessThan(0.7));
      expect(result.downProbability, greaterThan(0.3));
      expect(result.description, contains('样本不足'));
    });

    test('weighted matches influence probability more than raw counts', () {
      final data = _weightedPatternData();

      final result = NextDayPredictor.predict(data, null);

      expect(result.sampleCount,
          greaterThanOrEqualTo(NextDayPredictor.minSampleSize));
      expect(result.upProbability, greaterThan(result.downProbability));
      expect(result.upProbability, greaterThan(0.55));
    });
  });
}

List<HistoryKline> _patternData({
  required int matchCount,
  required double matchOutcomePct,
}) {
  final data = <HistoryKline>[];
  double price = 10;

  for (var i = 0; i < 40; i++) {
    final isMatch = i.isEven && matchCount > data.where(_isMatchingBar).length;
    final bar = _bar(
      i,
      price,
      rsi6: isMatch ? 55 : 35,
      k: isMatch ? 60 : 25,
      macdDif: isMatch ? 0.2 : -0.2,
      macdDea: isMatch ? 0.1 : 0.1,
      macdHist: isMatch ? 0.2 : -0.2,
      adx14: isMatch ? 28 : 12,
      volume: isMatch ? 15000 : 8000,
      volMa5: 10000,
      ma5: isMatch ? 10.2 : 9.8,
      ma10: 10,
    );
    data.add(bar);
    if (isMatch) {
      price *= 1 + matchOutcomePct / 100;
    } else {
      price *= 1.001;
    }
  }

  data.add(_bar(
    40,
    price,
    rsi6: 55,
    k: 60,
    macdDif: 0.2,
    macdDea: 0.1,
    macdHist: 0.2,
    adx14: 28,
    volume: 15000,
    volMa5: 10000,
    ma5: 10.2,
    ma10: 10,
  ));
  return data;
}

List<HistoryKline> _weightedPatternData() {
  final data = <HistoryKline>[];
  double price = 10;

  for (var i = 0; i < 25; i++) {
    final strongMatch = i < 16;
    final weakMatch = i >= 16 && i < 25;
    final current = _bar(
      i,
      price,
      rsi6: strongMatch || weakMatch ? 55 : 35,
      k: strongMatch ? 60 : 25,
      macdDif: strongMatch ? 0.2 : -0.2,
      macdDea: 0.1,
      macdHist: strongMatch ? 0.2 : -0.2,
      adx14: strongMatch ? 28 : 12,
      volume: strongMatch ? 15000 : 8000,
      volMa5: 10000,
      ma5: strongMatch ? 10.2 : 9.8,
      ma10: 10,
    );
    data.add(current);
    price *= strongMatch ? 1.02 : 0.99;
  }

  for (var i = 25; i < 40; i++) {
    data.add(_bar(i, price));
    price *= 1.001;
  }

  data.add(_bar(
    40,
    price,
    rsi6: 55,
    k: 60,
    macdDif: 0.2,
    macdDea: 0.1,
    macdHist: 0.2,
    adx14: 28,
    volume: 15000,
    volMa5: 10000,
    ma5: 10.2,
    ma10: 10,
  ));
  return data;
}

bool _isMatchingBar(HistoryKline kline) =>
    kline.rsi6 == 55 &&
    kline.k == 60 &&
    kline.macdDif == 0.2 &&
    kline.adx14 == 28;

HistoryKline _bar(
  int index,
  double close, {
  double rsi6 = 35,
  double k = 25,
  double macdDif = -0.2,
  double macdDea = 0.1,
  double macdHist = -0.2,
  double adx14 = 12,
  double volume = 8000,
  double volMa5 = 10000,
  double ma5 = 9.8,
  double ma10 = 10,
}) {
  return HistoryKline(
    date: DateTime(2024, 1, 1).add(Duration(days: index)),
    open: close * 0.995,
    high: close * 1.01,
    low: close * 0.99,
    close: close,
    volume: volume,
    amount: close * volume * 100,
    rsi6: rsi6,
    k: k,
    d: 45,
    macdDif: macdDif,
    macdDea: macdDea,
    macdHist: macdHist,
    adx14: adx14,
    volMa5: volMa5,
    ma5: ma5,
    ma10: ma10,
  );
}
