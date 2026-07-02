import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';

GlobalIndex _idx(String code, String market, double changePct) {
  return GlobalIndex(
    code: code,
    name: code,
    price: 100.0,
    changePct: changePct,
    changePoint: changePct,
    market: market,
  );
}

void main() {
  group('GlobalIndex.calculateTrend', () {
    test('空列表返回中性默认值', () {
      final t = GlobalIndex.calculateTrend([]);
      expect(t.trend, equals('中性'));
      expect(t.avg, equals(0.0));
      expect(t.upCount, equals(0));
      expect(t.downCount, equals(0));
    });

    test('全部上涨 → 偏多', () {
      final indices = [
        _idx('NDX', 'US', 1.5),
        _idx('SPX', 'US', 0.8),
        _idx('DJIA', 'US', 0.6),
      ];
      final t = GlobalIndex.calculateTrend(indices);
      expect(t.trend, equals('偏多'));
      expect(t.upCount, equals(3));
      expect(t.downCount, equals(0));
      expect(t.avg, closeTo(0.9667, 0.01));
    });

    test('全部下跌 → 偏空', () {
      final indices = [
        _idx('NDX', 'US', -1.5),
        _idx('SPX', 'US', -0.8),
        _idx('DJIA', 'US', -0.6),
      ];
      final t = GlobalIndex.calculateTrend(indices);
      expect(t.trend, equals('偏空'));
      expect(t.upCount, equals(0));
      expect(t.downCount, equals(3));
    });

    test('小幅波动(|avg|<=0.5) → 中性', () {
      final indices = [
        _idx('NDX', 'US', 0.3),
        _idx('SPX', 'US', -0.2),
        _idx('DJIA', 'US', 0.1),
      ];
      final t = GlobalIndex.calculateTrend(indices);
      expect(t.trend, equals('中性'));
      expect(t.upCount, equals(2));
      expect(t.downCount, equals(1));
      expect(t.avg.abs(), lessThanOrEqualTo(0.5));
    });

    test('涨跌混合但均值>0.5 → 偏多', () {
      final indices = [
        _idx('NDX', 'US', 2.0),
        _idx('SPX', 'US', -0.3),
        _idx('DJIA', 'US', 1.0),
      ];
      final t = GlobalIndex.calculateTrend(indices);
      expect(t.trend, equals('偏多'));
      expect(t.upCount, equals(2));
      expect(t.downCount, equals(1));
    });

    test('changePct=0 不计入涨跌', () {
      final indices = [
        _idx('NDX', 'US', 0.0),
        _idx('SPX', 'US', 1.0),
      ];
      final t = GlobalIndex.calculateTrend(indices);
      expect(t.upCount, equals(1));
      expect(t.downCount, equals(0));
    });
  });
}
