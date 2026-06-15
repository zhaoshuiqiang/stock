import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/position_manager.dart';
import 'package:stock_analyzer/analysis/indicators.dart';

// ---- Helper ----

HistoryKline makeKline({
  double close = 10.0,
  double atr14 = 0.3,
}) {
  return HistoryKline(
    date: DateTime(2024, 6, 1),
    open: close,
    high: close * 1.02,
    low: close * 0.98,
    close: close,
    volume: 10000,
    amount: 10000 * close,
    change: 0,
    changePct: 0,
    atr14: atr14,
  );
}

void main() {
  // ─── 仓位计算修复验证 ─────────────────────────────────────────

  group('PositionManager.calculatePosition 修复验证', () {
    test('低波动率(atrPct=1%)应返回重仓(100%)', () {
      // atrPct = atr14/close * 100 = 0.1/10 * 100 = 1%
      final kline = makeKline(close: 10.0, atr14: 0.1);
      final pos = PositionManager.calculatePosition(kline);
      // baseRiskPct=2.5, suggestedPosition = 2.5/1 = 2.5, clamp -> 1.0
      expect(pos, equals(1.0));
    });

    test('中等波动率(atrPct=3%)应返回偏大仓位(~83%)', () {
      // atrPct = 0.3/10 * 100 = 3%
      final kline = makeKline(close: 10.0, atr14: 0.3);
      final pos = PositionManager.calculatePosition(kline);
      // suggestedPosition = 2.5/3 = 0.833
      expect(pos, closeTo(0.833, 0.01));
      expect(pos, lessThan(1.0)); // 不再是100%重仓
    });

    test('较高波动率(atrPct=5%)应返回半仓(50%)', () {
      // atrPct = 0.5/10 * 100 = 5%
      final kline = makeKline(close: 10.0, atr14: 0.5);
      final pos = PositionManager.calculatePosition(kline);
      // suggestedPosition = 2.5/5 = 0.5
      expect(pos, closeTo(0.5, 0.01));
    });

    test('高波动率(atrPct=8%)应返回轻仓(~31%)', () {
      // atrPct = 0.8/10 * 100 = 8%
      final kline = makeKline(close: 10.0, atr14: 0.8);
      final pos = PositionManager.calculatePosition(kline);
      // suggestedPosition = 2.5/8 = 0.3125
      expect(pos, closeTo(0.3125, 0.01));
    });

    test('极高波动率(atrPct=15%)应返回迷你仓(~17%)', () {
      // atrPct = 1.5/10 * 100 = 15%
      final kline = makeKline(close: 10.0, atr14: 1.5);
      final pos = PositionManager.calculatePosition(kline);
      // suggestedPosition = 2.5/15 = 0.167
      expect(pos, closeTo(0.167, 0.01));
    });

    test('典型A股蓝筹股(波动2-3%)仓位应在60-100%之间', () {
      // 模拟贵州茅台级别：close=1700, atr14=40 -> atrPct=2.35%
      final kline = makeKline(close: 1700.0, atr14: 40.0);
      final pos = PositionManager.calculatePosition(kline);
      // suggestedPosition = 2.5/2.35 = 1.064 -> clamp 1.0
      expect(pos, greaterThanOrEqualTo(0.6));
      expect(pos, lessThanOrEqualTo(1.0));
    });

    test('典型A股小盘股(波动5-8%)仓位应在25-50%之间', () {
      // 模拟小盘股：close=15, atr14=0.9 -> atrPct=6%
      final kline = makeKline(close: 15.0, atr14: 0.9);
      final pos = PositionManager.calculatePosition(kline);
      // suggestedPosition = 2.5/6 = 0.417
      expect(pos, greaterThanOrEqualTo(0.25));
      expect(pos, lessThanOrEqualTo(0.5));
    });

    test('atrPct<=0.5%极低波动应返回maxPosition', () {
      final kline = makeKline(close: 10.0, atr14: 0.04); // atrPct=0.4%
      final pos = PositionManager.calculatePosition(kline);
      expect(pos, equals(1.0));
    });

    test('atrPct>=20%极高波动应返回minPosition', () {
      final kline = makeKline(close: 10.0, atr14: 2.5); // atrPct=25%
      final pos = PositionManager.calculatePosition(kline);
      expect(pos, equals(0.1));
    });

    test('atr14<=0或close<=0应返回默认0.5', () {
      expect(PositionManager.calculatePosition(makeKline(close: 10.0, atr14: 0)), equals(0.5));
      expect(PositionManager.calculatePosition(makeKline(close: 0, atr14: 0.3)), equals(0.5));
      expect(PositionManager.calculatePosition(makeKline(close: -1, atr14: 0.3)), equals(0.5));
    });
  });

  // ─── 仓位建议文本验证 ─────────────────────────────────────────

  group('PositionManager.getPositionAdvice 文本验证', () {
    test('重仓区间(>=0.8)应包含"重仓"', () {
      final advice = PositionManager.getPositionAdvice(0.9);
      expect(advice, contains('重仓'));
    });

    test('偏大区间(0.6-0.8)应包含"偏小"或仓位百分比', () {
      final advice = PositionManager.getPositionAdvice(0.7);
      expect(advice, contains('70%'));
    });

    test('半仓区间(0.4-0.6)应包含"半仓"', () {
      final advice = PositionManager.getPositionAdvice(0.5);
      expect(advice, contains('半仓'));
    });

    test('轻仓区间(0.25-0.4)应包含"轻仓"', () {
      final advice = PositionManager.getPositionAdvice(0.3);
      expect(advice, contains('轻仓'));
    });

    test('迷你仓区间(<0.25)应包含"迷你仓"和"严格止损"', () {
      final advice = PositionManager.getPositionAdvice(0.15);
      expect(advice, contains('迷你仓'));
      expect(advice, contains('严格止损'));
    });
  });

  // ─── 波动率等级验证 ─────────────────────────────────────────

  group('PositionManager.getVolatilityLevel 验证', () {
    test('atrPct<2为低波动', () {
      expect(PositionManager.getVolatilityLevel(1.5), equals('低波动'));
    });

    test('atrPct 2-3为中等波动', () {
      expect(PositionManager.getVolatilityLevel(2.5), equals('中等波动'));
    });

    test('atrPct 3-5为高波动', () {
      expect(PositionManager.getVolatilityLevel(4.0), equals('高波动'));
    });

    test('atrPct>=5为极高波动', () {
      expect(PositionManager.getVolatilityLevel(6.0), equals('极高波动'));
    });
  });

  // ─── 修复前后对比 ─────────────────────────────────────────

  group('修复前后对比 - baseRiskPct 10.0 vs 2.5', () {
    test('典型A股波动3%: 旧参数100%重仓, 新参数83%', () {
      final kline = makeKline(close: 10.0, atr14: 0.3); // atrPct=3%
      // 新参数(baseRiskPct=2.5)
      final newPos = PositionManager.calculatePosition(kline);
      expect(newPos, closeTo(0.833, 0.01));
      // 旧参数(baseRiskPct=10.0)的结果
      final oldPos = PositionManager.calculatePosition(kline, baseRiskPct: 10.0);
      expect(oldPos, equals(1.0)); // 旧参数下3%波动也是100%重仓
      // 确认修复有效
      expect(newPos, lessThan(oldPos));
    });

    test('典型A股波动5%: 旧参数100%重仓, 新参数50%', () {
      final kline = makeKline(close: 10.0, atr14: 0.5); // atrPct=5%
      final newPos = PositionManager.calculatePosition(kline);
      expect(newPos, closeTo(0.5, 0.01));
      final oldPos = PositionManager.calculatePosition(kline, baseRiskPct: 10.0);
      expect(oldPos, equals(1.0)); // 旧参数下5%波动也是100%重仓
      expect(newPos, lessThan(oldPos));
    });
  });

  // ─── 指标摘要中ATR键名验证 ─────────────────────────────────

  group('指标摘要ATR键名验证', () {
    test('getIndicatorSummary应包含ATR14键而非atr_pct', () {
      // 生成足够K线数据
      final prices = List.generate(80, (i) => 10.0 + (i % 10) * 0.5);
      final klines = prices.asMap().entries.map((e) {
        return HistoryKline(
          date: DateTime(2024, 1, e.key + 1),
          open: e.value,
          high: e.value * 1.02,
          low: e.value * 0.98,
          close: e.value,
          volume: 10000,
          amount: 10000 * e.value,
          change: e.key > 0 ? e.value - prices[e.key - 1] : 0,
          changePct: e.key > 0 ? (e.value - prices[e.key - 1]) / prices[e.key - 1] * 100 : 0,
        );
      }).toList();

      final calculated = calcAllIndicators(klines);
      final summary = getIndicatorSummary(calculated);

      // 确认ATR14键存在
      expect(summary.containsKey('ATR14'), isTrue,
          reason: '指标摘要应包含ATR14键');
      // 确认atr_pct键不存在
      expect(summary.containsKey('atr_pct'), isFalse,
          reason: '指标摘要不包含atr_pct键，quant_screen应使用ATR14自行计算');
    });
  });
}
