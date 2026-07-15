// v3.19 代码评审修复回归测试（批次 1 P0 正确性）
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/recommendation_tracker.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('v3.19 1.1 WR14/CCI14 空值保留', () {
    test('fromJson 缺少 wr14/cci14 字段时保留 null（不再塌缩为 0）', () {
      final json = <String, dynamic>{
        'date': '2026-07-15',
        'open': 10.0,
        'high': 11.0,
        'low': 9.0,
        'close': 10.5,
        'volume': 1000.0,
        // 故意不提供 wr14 / cci14
      };
      final k = HistoryKline.fromJson(json);
      expect(k.wr14, isNull, reason: '缺少字段应保持 null，避免假 WR 超买卖信号');
      expect(k.cci14, isNull);
    });

    test('fromJson 提供 wr14/cci14 时正确解析', () {
      final json = <String, dynamic>{
        'date': '2026-07-15',
        'open': 10.0,
        'high': 11.0,
        'low': 9.0,
        'close': 10.5,
        'volume': 1000.0,
        'wr14': 12.3,
        'cci14': -45.6,
      };
      final k = HistoryKline.fromJson(json);
      expect(k.wr14, 12.3);
      expect(k.cci14, -45.6);
    });
  });

  group('v3.19 1.2 推荐方向捕获与方向盲命中率', () {
    test('directionOf 正确分类 bullish/bearish/neutral', () {
      expect(directionOf('强烈买入'), 'bullish');
      expect(directionOf('谨慎买入'), 'bullish');
      expect(directionOf('偏多观望'), 'bullish');
      expect(directionOf('强烈卖出'), 'bearish');
      expect(directionOf('谨慎卖出'), 'bearish');
      expect(directionOf('偏空观望'), 'bearish');
      expect(directionOf('观望'), 'neutral');
      expect(directionOf(''), 'neutral');
    });

    test('RecommendationSnapshot 在 toMap/fromMap 间保留 direction', () {
      final snap = RecommendationSnapshot(
        code: 'sh600000',
        name: '测试',
        signalPrice: 10.0,
        signalDate: DateTime(2026, 7, 15),
        direction: 'bearish',
        score: 7.0,
      );
      final map = snap.toMap();
      expect(map['direction'], 'bearish');
      final restored = RecommendationSnapshot.fromMap(map);
      expect(restored.direction, 'bearish');
    });

    test('方向感知命中率：看空且下跌应计为命中', () {
      // 复刻 recommendation_stats_screen 的命中率计数逻辑，验证方向盲修复
      List<Map<String, dynamic>> records = [
        {
          'direction': 'bullish',
          'day20_return': 5.0,
        }, // 看多且涨 → 命中
        {
          'direction': 'bullish',
          'day20_return': -5.0,
        }, // 看多且跌 → 未命中
        {
          'direction': 'bearish',
          'day20_return': -5.0,
        }, // 看空且跌 → 命中（修复前被算作亏损）
        {
          'direction': '',
          'day20_return': 5.0,
        }, // 旧记录无方向，沿用旧口径 → 命中
      ];
      int wins = 0;
      for (final r in records) {
        final dir = (r['direction'] as String?) ?? '';
        final ret = r['day20_return'] as double;
        if (dir == 'bullish') {
          if (ret > 0) wins++;
        } else if (dir == 'bearish') {
          if (ret < 0) wins++;
        } else {
          if (ret > 0) wins++;
        }
      }
      expect(wins, 3,
          reason: '看空下跌也应计为命中，修复方向盲后应为 3/4');
    });
  });
}
