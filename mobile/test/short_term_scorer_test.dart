import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/short_term_scorer.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('ShortTermScorer', () {
    test(
        'scores high for short-term momentum with volume and fund confirmation',
        () {
      final data = _klines(
        close: [10, 10.2, 10.5, 10.9, 11.2],
        volume: [1000, 1100, 1200, 1800, 2200],
      );
      final quote = _quote(
        price: 11.2,
        changePct: 2.8,
        mainNetFlowRate: 6,
        turnover: 4,
        amplitude: 4,
      );

      final result = ShortTermScorer.score(
        data: data,
        buySignals: [
          _signal('KDJ金叉', 'KDJ', 2),
          _signal('放量上涨', '量价', 2),
        ],
        sellSignals: const [],
        quote: quote,
      );

      expect(result.score, greaterThanOrEqualTo(7));
      expect(result.actionLabel, equals('短线可参与'));
      expect(result.maxRecommendationScore, equals(10));
      expect(result.riskCaps, isEmpty);
    });

    test(
        'caps recommendation when price is already limit-up or chase risk is high',
        () {
      final data = _klines(
        close: [10, 10.3, 10.7, 11.1, 12.2],
        volume: [1000, 1200, 1400, 1800, 2500],
      );
      final quote = _quote(
        price: 12.2,
        changePct: 10.1,
        mainNetFlowRate: 8,
        turnover: 12,
        amplitude: 10,
      );

      final result = ShortTermScorer.score(
        data: data,
        buySignals: [_signal('放量突破', '量价', 3)],
        sellSignals: const [],
        quote: quote,
      );

      expect(result.score, lessThanOrEqualTo(6));
      expect(result.maxRecommendationScore, lessThanOrEqualTo(6));
      expect(
        result.riskCaps.any((r) => r.contains('涨停') || r.contains('追高')),
        isTrue,
      );
    });

    test('penalizes conflicting sell signals and recent weakness', () {
      final data = _klines(
        close: [10, 9.8, 9.4, 9.2, 9.0],
        volume: [1000, 1500, 1800, 2100, 2300],
      );
      final quote = _quote(
        price: 9,
        changePct: -3.2,
        mainNetFlowRate: -5,
        turnover: 3,
        amplitude: 6,
      );

      final result = ShortTermScorer.score(
        data: data,
        buySignals: [_signal('RSI超卖回升', 'RSI', 1)],
        sellSignals: [
          _signal('放量下跌', '量价', 3, type: 'sell'),
          _signal('MA死叉', 'MA', 2, type: 'sell'),
        ],
        quote: quote,
      );

      expect(result.score, lessThanOrEqualTo(4));
      expect(result.actionLabel, equals('短线回避'));
    });

    test('uses valuation as risk cap not hard exclusion', () {
      final data = _klines(
        close: [10, 10.1, 10.3, 10.6, 10.9],
        volume: [1000, 1100, 1300, 1700, 1900],
      );
      final quote = _quote(
        price: 10.9,
        changePct: 2.2,
        mainNetFlowRate: 5,
        turnover: 3,
        amplitude: 4,
        pe: -1,
      );

      final result = ShortTermScorer.score(
        data: data,
        buySignals: [_signal('放量突破', '量价', 2)],
        sellSignals: const [],
        quote: quote,
      );

      expect(result.score, greaterThanOrEqualTo(5));
      expect(
        result.riskCaps.any((r) => r.contains('估值') || r.contains('亏损')),
        isTrue,
      );
    });
  });
}

List<HistoryKline> _klines({
  required List<double> close,
  required List<double> volume,
}) {
  return List.generate(close.length, (i) {
    final c = close[i];
    final prev = i == 0 ? c : close[i - 1];
    final recentClose = close.sublist(0, i + 1);
    final recentVol = volume.sublist(0, i + 1);
    final ma5 = _avg(recentClose.length > 5
        ? recentClose.sublist(recentClose.length - 5)
        : recentClose);
    final volMa5 = _avg(recentVol.length > 5
        ? recentVol.sublist(recentVol.length - 5)
        : recentVol);
    final changePct = prev > 0 ? (c / prev - 1) * 100 : 0.0;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: prev,
      high: c * 1.02,
      low: c * 0.98,
      close: c,
      volume: volume[i],
      amount: volume[i] * c,
      changePct: changePct,
      amplitude: 4,
      ma5: ma5,
      ma10: ma5 * 0.99,
      ma20: ma5 * 0.98,
      volMa5: volMa5,
      atr14: c * 0.03,
      rsi6: c >= prev ? 62 : 38,
      k: c >= prev ? 55 : 35,
      d: c >= prev ? 45 : 45,
      j: c >= prev ? 75 : 15,
      bias6: ma5 > 0 ? (c / ma5 - 1) * 100 : 0,
      adx14: 24,
      plusDi14: c >= prev ? 28 : 12,
      minusDi14: c >= prev ? 14 : 30,
      obv: volume.sublist(0, i + 1).fold<double>(0, (sum, v) => sum + v),
    );
  });
}

double _avg(List<double> values) =>
    values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;

SignalItem _signal(
  String name,
  String indicator,
  int strength, {
  String type = 'buy',
}) {
  return SignalItem(
    type: type,
    indicator: indicator,
    signal: name,
    strength: strength,
    duration: SignalDuration.shortTerm,
    confidence: 0.7,
  );
}

QuoteData _quote({
  required double price,
  required double changePct,
  required double mainNetFlowRate,
  required double turnover,
  required double amplitude,
  double pe = 20,
}) {
  return QuoteData(
    code: 'sh600001',
    name: '测试股票',
    price: price,
    changePct: changePct,
    open: price / (1 + changePct / 100),
    high: price * 1.02,
    low: price * 0.98,
    preClose: price / (1 + changePct / 100),
    mainNetFlow: mainNetFlowRate == 0 ? 0 : mainNetFlowRate * 1000000,
    mainNetFlowRate: mainNetFlowRate,
    turnover: turnover,
    amplitude: amplitude,
    pe: pe,
    pb: 2,
  );
}
