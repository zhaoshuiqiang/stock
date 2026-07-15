import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/indicators.dart';
import 'package:stock_analyzer/analysis/short_term_direction_model.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/short_term_direction.dart';
import 'package:stock_analyzer/models/stock_models.dart';

const _bullishComponents = <String, double>{
  'trend': 0.45,
  'reversal_momentum': 0.30,
  'volume_flow': 0.40,
  'relative_strength': 0.20,
  'next_session': 0.30,
};

const _bearishComponents = <String, double>{
  'trend': -0.45,
  'reversal_momentum': -0.30,
  'volume_flow': -0.40,
  'relative_strength': -0.20,
  'next_session': -0.30,
};

const _flatComponents = <String, double>{
  'trend': 0.05,
  'reversal_momentum': -0.05,
  'volume_flow': 0.05,
  'relative_strength': 0.0,
  'next_session': 0.0,
};

List<HistoryKline> _bars({
  int count = 30,
  double lastChangePct = 1.0,
  double lastRsi6 = 50,
  double lastBias6 = 0,
}) {
  final raw = List.generate(count, (i) {
    final price = 15.0 + (i % 7 - 3) * 0.1;
    return HistoryKline(
      date: DateTime(2024, 1, i + 1),
      open: price - 0.05,
      high: price + 0.1,
      low: price - 0.1,
      close: price,
      volume: 10000.0,
      amount: 10000 * price,
      changePct: 1.0,
    );
  });
  final data = calcAllIndicators(raw);
  final lastIdx = data.length - 1;
  // 显式控制末根指标，避免无意触发去动量偏置
  data[lastIdx] = data[lastIdx].copyWith(
    changePct: lastChangePct,
    rsi6: lastRsi6,
    bias6: lastBias6,
  );
  return data;
}

MarketContext _ctx(double avgChangePct) => MarketContext(
      shIndexPct: avgChangePct,
      szIndexPct: avgChangePct,
      indexChange: 0,
      marketTrend: 'neutral',
      upCount: 100,
      downCount: 100,
      avgChangePct: avgChangePct,
      updateTime: DateTime.now(),
    );

void main() {
  group('ShortTermDirectionModel', () {
    test('强多头分量 → 看涨，概率落在 [0.5,0.9]', () {
      final f = ShortTermDirectionModel.evaluate(
        components: _bullishComponents,
        marketContext: _ctx(0),
        data: _bars(),
      );
      expect(f.direction, RecommendationDirection.bullish);
      expect(f.probability, inInclusiveRange(0.5, 0.9));
      expect(f.momentumPenalized, isFalse);
      expect(f.supportingEvidence, isNotEmpty);
    });

    test('强空头分量 → 看跌', () {
      final f = ShortTermDirectionModel.evaluate(
        components: _bearishComponents,
        marketContext: _ctx(0),
        data: _bars(),
      );
      expect(f.direction, RecommendationDirection.bearish);
    });

    test('稀疏分量 → 震荡', () {
      final f = ShortTermDirectionModel.evaluate(
        components: _flatComponents,
        marketContext: _ctx(0),
        data: _bars(),
      );
      expect(f.direction, RecommendationDirection.neutral);
    });

    test('4.4 去动量偏置：已大涨+高分时被下调', () {
      final normal = ShortTermDirectionModel.evaluate(
        components: _bullishComponents,
        marketContext: _ctx(0),
        data: _bars(lastChangePct: 1.0),
      );
      final surged = ShortTermDirectionModel.evaluate(
        components: _bullishComponents,
        marketContext: _ctx(0),
        data: _bars(lastChangePct: 9.5),
      );
      expect(surged.momentumPenalized, isTrue);
      expect(surged.rawScore, lessThan(normal.rawScore));
    });

    test('4.4 市场状态门控：熊市偏置拉低多头 rawScore', () {
      final bullMarket = ShortTermDirectionModel.evaluate(
        components: _bullishComponents,
        marketContext: _ctx(3.0),
        data: _bars(),
      );
      final bearMarket = ShortTermDirectionModel.evaluate(
        components: _bullishComponents,
        marketContext: _ctx(-3.0),
        data: _bars(),
      );
      expect(bearMarket.rawScore, lessThan(bullMarket.rawScore));
    });

    test('DirectionForecast 可序列化往返', () {
      final f = ShortTermDirectionModel.evaluate(
        components: _bullishComponents,
        marketContext: _ctx(1.0),
        data: _bars(),
        horizonDays: 5,
      );
      final round = DirectionForecast.fromJson(f.toJson());
      expect(round.direction, f.direction);
      expect(round.probability, f.probability);
      expect(round.horizonDays, 5);
      expect(round.componentScores, f.componentScores);
      expect(round.directionLabel, '看涨');
    });
  });
}
