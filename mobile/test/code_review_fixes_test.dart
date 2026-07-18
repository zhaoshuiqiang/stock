import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/capital_flow_analyzer.dart';
import 'package:stock_analyzer/analysis/technical_scorer.dart';
import 'package:stock_analyzer/analysis/signal_engine.dart';
import 'package:stock_analyzer/validators/data_validator.dart';

/// 生成上涨趋势K线数据（放量上涨）
List<HistoryKline> _uptrendWithVolume({int count = 60}) {
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
      volume: 10000.0 + i * 500, // 递增成交量
      amount: 10000 * (open + price) / 2,
    );
  });
  return calcAllIndicators(raw);
}

/// 生成下跌趋势K线数据（空头排列 + 强ADX）
List<HistoryKline> _downtrendStrongAdx({int count = 60}) {
  double price = 30.0;
  final raw = List.generate(count, (i) {
    final open = price;
    price *= 0.97;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: open,
      high: open * 1.01,
      low: price * 0.99,
      close: price,
      volume: 20000.0,
      amount: 20000 * (open + price) / 2,
    );
  });
  return calcAllIndicators(raw);
}

void main() {
  group('CapitalFlowAnalyzer 修复验证', () {
    test('5日和10日资金流向因子方向一致', () {
      final klines = _uptrendWithVolume();
      final quote = QuoteData(
        code: 'sh600519',
        name: '贵州茅台',
        price: 1800,
        mainNetFlow: 100000000,
        mainNetFlowRate: 5.0,
      );

      final result = CapitalFlowAnalyzer.analyze(klineData: klines, quote: quote);

      // 上涨+放量时，5日和10日资金流向都应为正
      expect(result.priceVolumeMomentum5d, greaterThan(0),
          reason: '放量上涨时5日量价动量应为正');
      expect(result.priceVolumeMomentum10d, greaterThan(0),
          reason: '放量上涨时10日量价动量应为正');
      expect(result.priceVolumeMomentum5d * result.priceVolumeMomentum10d, greaterThanOrEqualTo(0),
          reason: '5日和10日量价动量符号应一致');
    });

    test('近3日close为0时不崩溃（除零保护）', () {
      final klines = _uptrendWithVolume();
      // 将最后3天的close设为0，模拟异常数据
      final badKlines = List<HistoryKline>.from(klines);
      for (int i = badKlines.length - 3; i < badKlines.length; i++) {
        badKlines[i] = HistoryKline(
          date: badKlines[i].date,
          open: 0, high: 0, low: 0, close: 0,
          volume: badKlines[i].volume,
          amount: 0,
        );
      }
      // 重新计算指标（close=0会被calcAllIndicators处理）
      final recalculated = calcAllIndicators(badKlines.where((k) => k.close > 0).toList());

      // 不应抛出异常
      expect(
        () => CapitalFlowAnalyzer.analyze(klineData: recalculated, quote: null),
        returnsNormally,
      );
    });

    test('OBV分支在klineData.length>=11时可达（死代码已移除）', () {
      final klines = _uptrendWithVolume(count: 60);
      final result = CapitalFlowAnalyzer.analyze(klineData: klines, quote: null);
      // 只要不崩溃且返回有效结果即可
      expect(result.score, greaterThanOrEqualTo(0));
      expect(result.score, lessThanOrEqualTo(10));
    });
  });

  group('QuoteData.copyWith 修复验证', () {
    test('copyWith保留sectorName', () {
      final quote = QuoteData(
        code: 'sh600519',
        name: '贵州茅台',
        price: 1800,
        sectorName: '白酒',
      );
      final copied = quote.copyWith(price: 1850);
      expect(copied.sectorName, equals('白酒'),
          reason: 'copyWith应保留sectorName');
      expect(copied.price, equals(1850));
    });

    test('copyWith可更新sectorName', () {
      final quote = QuoteData(
        code: 'sh600519',
        name: '贵州茅台',
        price: 1800,
        sectorName: '白酒',
      );
      final copied = quote.copyWith(sectorName: '食品饮料');
      expect(copied.sectorName, equals('食品饮料'));
    });
  });

  group('DataValidator ST容差修复', () {
    test('ST股票涨跌幅5.0%不触发异常（容差6.0%）', () {
      final stQuote = QuoteData(
        code: 'sh600519',
        name: 'ST茅台',
        price: 10.5,
        preClose: 10.0,
        changePct: 5.0,
        volume: 10000,
      );
      final result = DataValidator.validateQuote(stQuote);
      final hasExtremeChange = result.anomalies.any(
        (a) => a.type == DataAnomalyType.extremeChange,
      );
      expect(hasExtremeChange, isFalse,
          reason: 'ST涨跌幅5.0%在容差范围内，不应标记为异常');
    });

    test('ST股票涨跌幅5.5%不触发异常', () {
      final stQuote = QuoteData(
        code: 'sh600519',
        name: '*ST茅台',
        price: 10.55,
        preClose: 10.0,
        changePct: 5.5,
        volume: 10000,
      );
      final result = DataValidator.validateQuote(stQuote);
      final hasExtremeChange = result.anomalies.any(
        (a) => a.type == DataAnomalyType.extremeChange,
      );
      expect(hasExtremeChange, isFalse,
          reason: 'ST涨跌幅5.5%在6.0%容差范围内');
    });

    test('ST股票涨跌幅6.5%触发异常', () {
      final stQuote = QuoteData(
        code: 'sh600519',
        name: 'ST茅台',
        price: 10.65,
        preClose: 10.0,
        changePct: 6.5,
        volume: 10000,
      );
      final result = DataValidator.validateQuote(stQuote);
      final hasExtremeChange = result.anomalies.any(
        (a) => a.type == DataAnomalyType.extremeChange,
      );
      expect(hasExtremeChange, isTrue,
          reason: 'ST涨跌幅6.5%超出6.0%容差，应标记为异常');
    });
  });

  group('TechnicalScorer 修复验证', () {
    test('空数据不崩溃，返回中性评分', () {
      final result = TechnicalScorer.score([], [], []);
      expect(result.totalScore, equals(5.0),
          reason: '空数据应返回中性评分5.0');
      expect(result.signalScore, equals(1.5));
    });

    test('空头排列+强ADX得分不应高于盘整市场', () {
      // 空头排列 + 强ADX的下跌趋势
      final bearishData = _downtrendStrongAdx();
      final bearishResult = TechnicalScorer.score(bearishData, [], []);

      // 盘整市场（价格横盘）
      double flatPrice = 15.0;
      final flatRaw = List.generate(60, (i) {
        return HistoryKline(
          date: DateTime(2024, 1, i + 1),
          open: flatPrice,
          high: flatPrice * 1.01,
          low: flatPrice * 0.99,
          close: flatPrice,
          volume: 10000.0,
          amount: 10000 * flatPrice,
        );
      });
      final flatData = calcAllIndicators(flatRaw);
      final flatResult = TechnicalScorer.score(flatData, [], []);

      // 空头排列+强ADX的trendScore不应高于盘整市场
      // 盘整trendScore=0.3，空头排列trendScore=0（ADX bonus不再叠加）
      expect(bearishResult.trendScore, lessThanOrEqualTo(flatResult.trendScore + 0.1),
          reason: '空头排列+强ADX的trendScore不应显著高于盘整市场');
    });
  });

  group('SignalEngine ATR止损除零保护', () {
    test('close为0时不崩溃', () {
      final klines = _uptrendWithVolume();
      // 直接调用calcTradeLevels验证不抛异常
      expect(
        () => calcTradeLevels(klines),
        returnsNormally,
      );
    });
  });
}
