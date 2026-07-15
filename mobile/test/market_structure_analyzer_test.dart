import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/market_structure_analyzer.dart';

List<HistoryKline> _sidewaysData({int count = 45}) {
  final raw = List.generate(count, (i) {
    final price = 15.0 + (i % 7 - 3) * 0.2;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: price - 0.1,
      high: price + 0.2,
      low: price - 0.2,
      close: price,
      volume: 10000.0,
      amount: 10000 * price,
    );
  });
  return calcAllIndicators(raw);
}

void main() {
  group('MarketStructureAnalyzer (fix 3.5 短历史吸筹判定)', () {
    test('短历史(<60根) 在 ADX 20-25 + 价格贴近MA + 缩量 时判定为底部积累', () {
      final data = _sidewaysData(count: 45);
      // 末5根缩量：volMa5 仍基于原 10000 计算，故 volume/volMa5≈0.5 < 0.7
      final modified = <HistoryKline>[
        for (int i = 0; i < data.length; i++)
          if (i >= data.length - 5)
            data[i].copyWith(volume: 5000.0)
          else
            data[i],
      ];
      final lastIdx = modified.length - 1;
      modified[lastIdx] = modified[lastIdx].copyWith(adx14: 22.0, volume: 5000.0);

      final result = MarketStructureAnalyzer.analyze(modified);
      expect(result.structure, MarketStructure.accumulation);
    });

    test('长历史(>=60根) 仍优先用 MA60 判定吸筹', () {
      final data = _sidewaysData(count: 60);
      final modified = <HistoryKline>[
        for (int i = 0; i < data.length; i++)
          if (i >= data.length - 5)
            data[i].copyWith(volume: 5000.0)
          else
            data[i],
      ];
      final lastIdx = modified.length - 1;
      modified[lastIdx] = modified[lastIdx].copyWith(adx14: 22.0, volume: 5000.0);

      final result = MarketStructureAnalyzer.analyze(modified);
      // ma60 在 60 根时可用，价格贴近 ma60 → 仍应判定为吸筹
      expect(result.structure, MarketStructure.accumulation);
    });

    test('数据不足 30 根返回默认盘整', () {
      final data = _sidewaysData(count: 20);
      final result = MarketStructureAnalyzer.analyze(data);
      expect(result.structure, MarketStructure.consolidation);
    });
  });
}
