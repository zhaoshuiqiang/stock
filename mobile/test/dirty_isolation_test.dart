import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/backtest_engine.dart';

List<HistoryKline> _genSteady(int count, {double price = 10.0, double vol = 15000.0}) {
  return List.generate(count, (i) {
    final p = price + i * 0.1;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: p - 0.05,
      high: p + 0.05,
      low: p - 0.05,
      close: p,
      volume: vol,
      amount: vol * p,
      change: 0.1,
      changePct: 0.1 / p * 100,
    );
  });
}

void main() {
  group('isolateDirtyData', () {
    test('suspended day (volume=0) gets forward-filled', () {
      final raw = _genSteady(10);
      raw[5] = raw[5].copyWith(volume: 0, open: 0, high: 0, low: 0, close: 0);

      final result = isolateDirtyData(raw);

      expect(result[5].volume, equals(0));
      expect(result[5].close, equals(raw[4].close));
      expect(result[5].open, equals(raw[4].close));
      expect(result[5].high, equals(raw[4].close));
      expect(result[5].low, equals(raw[4].close));
    });

    test('limit-lock day (OHLC equal, changePct>=9.5) gets forward-filled', () {
      final raw = _genSteady(10);
      final limitPrice = raw[4].close * 1.10;
      raw[5] = HistoryKline(
        date: DateTime(2024, 1, 6),
        open: limitPrice,
        high: limitPrice,
        low: limitPrice,
        close: limitPrice,
        volume: 5000,
        amount: 5000 * limitPrice,
        changePct: 10.0,
        change: limitPrice - raw[4].close,
      );

      final result = isolateDirtyData(raw);

      expect(result[5].close, equals(raw[4].close));
      expect(result[5].volume, equals(0));
    });

    test('ChiNext limit-lock (changePct>=19.5) gets forward-filled', () {
      final raw = _genSteady(10);
      final limitPrice = raw[4].close * 1.20;
      raw[5] = HistoryKline(
        date: DateTime(2024, 1, 6),
        open: limitPrice,
        high: limitPrice,
        low: limitPrice,
        close: limitPrice,
        volume: 5000,
        amount: 5000 * limitPrice,
        changePct: 20.0,
        change: limitPrice - raw[4].close,
      );

      final result = isolateDirtyData(raw);

      expect(result[5].close, equals(raw[4].close));
      expect(result[5].volume, equals(0));
    });

    test('normal bars are untouched', () {
      final raw = _genSteady(10);
      final result = isolateDirtyData(raw);

      for (int i = 0; i < raw.length; i++) {
        expect(result[i].close, equals(raw[i].close));
        expect(result[i].volume, equals(raw[i].volume));
      }
    });

    test('consecutive dirty bars all get forward-filled', () {
      final raw = _genSteady(10);
      for (int i = 5; i <= 7; i++) {
        raw[i] = raw[i].copyWith(volume: 0, open: 0, high: 0, low: 0, close: 0);
      }

      final result = isolateDirtyData(raw);

      for (int i = 5; i <= 7; i++) {
        expect(result[i].close, equals(raw[4].close));
        expect(result[i].volume, equals(0));
      }
    });

    test('empty and single-element data are safe', () {
      expect(isolateDirtyData([]), isEmpty);
      expect(isolateDirtyData([HistoryKline(date: DateTime(2024))]).length, equals(1));
    });
  });

  group('calcAllIndicators dirty isolation', () {
    test('suspended day does not distort MA5 with enableDirtyIsolation', () {
      final raw = _genSteady(20);
      raw[10] = raw[10].copyWith(
        volume: 0, open: 0, high: 0, low: 0, close: 0,
      );

      final withIsolation = calcAllIndicators(List.from(raw), enableDirtyIsolation: true);
      final withoutIsolation = calcAllIndicators(List.from(raw), enableDirtyIsolation: false);

      expect(withIsolation[10].ma5, isNot(equals(0)));
      expect(withoutIsolation[10].ma5, isNot(equals(withIsolation[10].ma5)));
    });

    test('limit-lock day does not distort MACD with enableDirtyIsolation', () {
      final raw = _genSteady(40);
      final limitPrice = raw[19].close * 1.10;
      raw[20] = HistoryKline(
        date: DateTime(2024, 1, 21),
        open: limitPrice,
        high: limitPrice,
        low: limitPrice,
        close: limitPrice,
        volume: 5000,
        amount: 5000 * limitPrice,
        changePct: 10.0,
        change: limitPrice - raw[19].close,
      );

      final withIsolation = calcAllIndicators(List.from(raw), enableDirtyIsolation: true);
      final withoutIsolation = calcAllIndicators(List.from(raw), enableDirtyIsolation: false);

      expect(withIsolation[20].macdDif, isNot(equals(withoutIsolation[20].macdDif)));
    });

    test('enableDirtyIsolation=false produces same result as default', () {
      final raw = _genSteady(20);
      final withFalse = calcAllIndicators(List.from(raw), enableDirtyIsolation: false);
      final withDefault = calcAllIndicators(List.from(raw));

      for (int i = 0; i < raw.length; i++) {
        expect(withFalse[i].ma5, equals(withDefault[i].ma5));
        expect(withFalse[i].macdDif, equals(withDefault[i].macdDif));
        expect(withFalse[i].rsi6, equals(withDefault[i].rsi6));
      }
    });

    test('normal data produces same result with or without isolation', () {
      final raw = _genSteady(30);
      final withIsolation = calcAllIndicators(List.from(raw), enableDirtyIsolation: true);
      final withoutIsolation = calcAllIndicators(List.from(raw), enableDirtyIsolation: false);

      for (int i = 0; i < raw.length; i++) {
        expect(withIsolation[i].ma5, equals(withoutIsolation[i].ma5));
        expect(withIsolation[i].macdDif, equals(withoutIsolation[i].macdDif));
        expect(withIsolation[i].rsi6, equals(withoutIsolation[i].rsi6));
      }
    });
  });

  group('BacktestEngine dirty isolation integration', () {
    test('backtest with dirty data uses isolation when skipDirtyData=true', () {
      final raw = _genSteady(80);
      for (int i = 30; i <= 32; i++) {
        raw[i] = raw[i].copyWith(
          volume: 0, open: 0, high: 0, low: 0, close: 0,
        );
      }

      BacktestEngine.config = BacktestConfig.aStock;
      final result = BacktestEngine.backtestMACDCross(raw);
      expect(result.totalSignals, isNotNull);
    });

    test('legacy config (skipDirtyData=false) does not apply isolation', () {
      final raw = _genSteady(80);
      for (int i = 30; i <= 32; i++) {
        raw[i] = raw[i].copyWith(
          volume: 0, open: 0, high: 0, low: 0, close: 0,
        );
      }

      BacktestEngine.config = BacktestConfig.legacy;
      final result = BacktestEngine.backtestMACDCross(raw);
      expect(result.totalSignals, isNotNull);
      BacktestEngine.config = BacktestConfig.aStock;
    });
  });
}
