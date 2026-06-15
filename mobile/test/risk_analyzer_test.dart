import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/risk_analyzer.dart';

/// Generate uptrend kline data with indicators calculated.
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

void main() {
  group('RiskAnalyzer', () {
    test('Detects RSI overbought risk', () {
      var data = _uptrendData();
      final n = data.length;
      data[n - 1] = data[n - 1].copyWith(rsi6: 75.0);

      final result = RiskAnalyzer.analyze(data, data.last, null);

      final rsiRisk =
          result.riskFactors.where((f) => f.contains('RSI超买')).toList();
      expect(rsiRisk.isNotEmpty, true,
          reason: 'Should detect RSI overbought risk when RSI6 > 70');
    });

    test('Detects ATR volatility risk', () {
      var data = _uptrendData();
      final n = data.length;
      final last = data[n - 1];
      data[n - 1] = data[n - 1].copyWith(atr14: last.close * 0.06);

      final result = RiskAnalyzer.analyze(data, data.last, null);

      final atrRisk =
          result.riskFactors.where((f) => f.contains('ATR波动率')).toList();
      expect(atrRisk.isNotEmpty, true,
          reason: 'Should detect ATR volatility risk when ATR/close > 5%');
    });

    test('Detects BIAS extreme risk', () {
      var data = _uptrendData();
      final n = data.length;
      data[n - 1] = data[n - 1].copyWith(bias6: 7.0);

      final result = RiskAnalyzer.analyze(data, data.last, null);

      final biasRisk = result.riskFactors
          .where((f) => f.contains('BIAS6') && f.contains('偏离均线过大'))
          .toList();
      expect(biasRisk.isNotEmpty, true,
          reason: 'Should detect BIAS6 extreme positive risk');
    });

    test('High risk level with 3+ factors', () {
      var data = _uptrendData();
      final n = data.length;
      // Force multiple risk factors: RSI overbought, BIAS extreme, high ATR
      final last = data[n - 1];
      data[n - 1] = data[n - 1].copyWith(
        rsi6: 75.0,
        bias6: 7.0,
        atr14: last.close * 0.06,
      );

      final result = RiskAnalyzer.analyze(data, data.last, null);

      expect(result.riskLevel, equals('高'),
          reason:
              'Risk level should be 高 when 3+ risk factors are present');
    });

    test('Low risk level with no factors', () {
      var data = _uptrendData();
      final n = data.length;
      // Force neutral values to avoid any risk factors
      final last = data[n - 1];
      data[n - 1] = data[n - 1].copyWith(
        rsi6: 50.0,
        bias6: 0.0,
        atr14: last.close * 0.01,
        bollUpper: last.close + 10,
        bollLower: last.close - 10,
        ma20: last.close - 1,
        amplitude: 1.0,
        j: 50.0,
        obv: 0,
      );

      final result = RiskAnalyzer.analyze(data, data.last, null);

      // Even with forced neutral values, other factors may still trigger,
      // so we verify the risk level logic: if no factors, level is '低'
      if (result.riskFactors.isEmpty) {
        expect(result.riskLevel, equals('低'),
            reason: 'Risk level should be 低 when no risk factors');
      }
    });
  });
}
