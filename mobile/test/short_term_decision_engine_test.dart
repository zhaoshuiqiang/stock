import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/next_day_predictor.dart';
import 'package:stock_analyzer/analysis/next_session_prediction.dart';
import 'package:stock_analyzer/analysis/short_term_decision_engine.dart';
import 'package:stock_analyzer/analysis/strategy_engine.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  test('neutral data returns score 5 observation and v3 model', () {
    final result = ShortTermDecisionEngine.evaluate(_input(
      data: _data(trend: 0),
    ));

    expect(result.decision.direction, RecommendationDirection.neutral);
    expect(result.recommendation.legacyScore, 5);
    expect(result.recommendation.actionable, isFalse);
    expect(result.decision.modelVersion, 'short-term-v3');
    expect(result.decision.evidenceTradeDate, DateTime(2026, 7, 6));
  });

  test('clean bullish evidence selects one compatible primary strategy', () {
    final result = ShortTermDecisionEngine.evaluate(_input(
      data: _data(trend: 1),
      buySignals: [_signal('MA'), _signal('volume')],
      quote: QuoteData(
        code: 'sh600001',
        name: 'test',
        price: 11,
        open: 10.7,
        high: 11.1,
        low: 10.6,
        preClose: 10.7,
        changePct: 2.8,
        turnover: 4,
        volumeRatio: 1.8,
        mainNetFlowRate: 6,
      ),
      activeStrategies: [
        _strategy('primary', strength: 80),
        _strategy('support', strength: 70),
      ],
      nextDayPrediction: _prediction(up: 0.75, down: 0.15),
      nextSessionPrediction: const NextSessionPrediction(
        nextOpenUpProbability: 0.7,
        nextCloseUpProbability: 0.75,
        expectedNextCloseReturn: 1.5,
        downsideRiskProbability: 0.2,
        confidence: 0.8,
        sampleCount: 30,
        scenarioTags: [],
        riskWarnings: [],
      ),
    ));

    expect(result.decision.direction, RecommendationDirection.bullish);
    expect(result.decision.primaryStrategyId, 'primary');
    expect(result.decision.supportingStrategyIds, ['support']);
    expect(result.decision.tradeQualityScore, inInclusiveRange(0, 100));
    expect(result.decision.riskScore, inInclusiveRange(0, 100));
  });

  test('missing market context is explicit and does not invent a regime', () {
    final result = ShortTermDecisionEngine.evaluate(_input(
      data: _data(trend: 0),
    ));

    expect(result.decision.marketRegime, MarketRegime.unknown);
    expect(
        result.decision.dataQualityFlags, contains('market_context_missing'));
  });

  test('missing or invalid quote price blocks actionable recommendations', () {
    final invalidQuote = QuoteData(
      code: 'sh600001',
      name: 'test',
      price: 0,
      open: 10.7,
      high: 11.1,
      low: 10.6,
      preClose: 10.7,
      changePct: 2.8,
      turnover: 4,
      volumeRatio: 1.8,
      mainNetFlowRate: 6,
    );

    for (final quote in <QuoteData?>[null, invalidQuote]) {
      final result = ShortTermDecisionEngine.evaluate(_input(
        data: _data(trend: 1, lastChangePct: 5),
        buySignals: [_signal('MA'), _signal('volume')],
        quote: quote,
        marketContext: _market(avgChangePct: 0.1),
        activeStrategies: [_strategy('primary', strength: 90)],
        nextDayPrediction: _prediction(up: 0.95, down: 0),
        nextSessionPrediction: const NextSessionPrediction(
          nextOpenUpProbability: 0.9,
          nextCloseUpProbability: 0.95,
          expectedNextCloseReturn: 3,
          downsideRiskProbability: 0.05,
          confidence: 1,
          sampleCount: 100,
          scenarioTags: [],
          riskWarnings: [],
        ),
      ));

      expect(result.decision.directionScore, greaterThanOrEqualTo(20));
      expect(result.decision.dataQualityFlags, contains('quote_data_missing'));
      expect(result.recommendation.gates, contains('critical_data_missing'));
      expect(result.recommendation.actionable, isFalse);
    }
  });

  test('relative strength is centered on stock performance versus market', () {
    double relative(double stockChange, double marketChange) =>
        ShortTermDecisionEngine.evaluate(
          _input(
            data: _data(trend: 0, lastChangePct: stockChange),
            marketContext: _market(avgChangePct: marketChange),
          ),
        ).decision.directionComponents['relative_strength']!;

    expect(relative(1.2, 1.2), 0);
    expect(relative(3, 1), closeTo(0.4, 0.000001));
    expect(relative(-2, 1), closeTo(-0.6, 0.000001));
  });

  test('legacy percentile relative score cannot bias v3 direction', () {
    final low = ShortTermDecisionEngine.evaluate(
      _input(
        data: _data(trend: 0, lastChangePct: 1),
        marketContext: _market(avgChangePct: 1),
        industryRelativeStrength: 0.05,
      ),
    );
    final high = ShortTermDecisionEngine.evaluate(
      _input(
        data: _data(trend: 0, lastChangePct: 1),
        marketContext: _market(avgChangePct: 1),
        industryRelativeStrength: 0.95,
      ),
    );

    expect(high.decision.directionScore, low.decision.directionScore);
    expect(high.decision.directionComponents['relative_strength'], 0);
  });
}

ShortTermDecisionInput _input({
  required List<HistoryKline> data,
  List<SignalItem> buySignals = const [],
  List<SignalItem> sellSignals = const [],
  QuoteData? quote,
  MarketContext? marketContext,
  double? industryRelativeStrength,
  List<TradingStrategy> activeStrategies = const [],
  NextDayPredictionResult? nextDayPrediction,
  NextSessionPrediction nextSessionPrediction =
      const NextSessionPrediction.neutral(),
}) {
  return ShortTermDecisionInput(
    data: data,
    quote: quote,
    buySignals: buySignals,
    sellSignals: sellSignals,
    marketContext: marketContext,
    marketStructure: null,
    industryRelativeStrength: industryRelativeStrength,
    nextDayPrediction: nextDayPrediction ?? _prediction(),
    nextSessionPrediction: nextSessionPrediction,
    tradeLevels: const {
      'risk_reward_ratio': 2.5,
      'has_support': true,
    },
    activeStrategies: activeStrategies,
    rawComprehensiveScore: 5,
  );
}

List<HistoryKline> _data({required int trend, double? lastChangePct}) {
  return List.generate(6, (index) {
    final close = trend == 0 ? 10.0 : 10 + index * 0.2 * trend;
    final open = close - 0.08 * trend;
    return HistoryKline(
      date: DateTime(2026, 7, index + 1),
      open: open,
      high: close * 1.01,
      low: close * 0.99,
      close: close,
      volume: trend == 0 ? 1000 : 1000 + index * 300,
      amount: close * 1000,
      changePct:
          index == 5 && lastChangePct != null ? lastChangePct : trend * 1.5,
      amplitude: 3,
      turnover: 4,
      ma5: trend == 0 ? 10 : close,
      ma10: trend == 0 ? 10 : close - 0.15 * trend,
      ma20: trend == 0 ? 10 : close - 0.3 * trend,
      volMa5: 1200,
      atr14: close * 0.03,
      rsi6: trend == 0 ? 50 : 60,
      wr14: trend == 0 ? 50 : 35,
      adx14: trend == 0 ? 10 : 30,
      plusDi14: trend > 0 ? 30 : 15,
      minusDi14: trend > 0 ? 15 : 30,
    );
  });
}

SignalItem _signal(String indicator) => SignalItem(
      type: 'buy',
      indicator: indicator,
      signal: 'test',
      strength: 80,
      confidence: 0.9,
      duration: SignalDuration.shortTerm,
      freshTime: DateTime(2026, 7, 15),
    );

TradingStrategy _strategy(String id, {required int strength}) =>
    TradingStrategy(
      id: id,
      name: id,
      category: 'test',
      description: '',
      entryRule: '',
      exitRule: '',
      stopLossRule: '',
      isActive: true,
      signalStrength: strength,
      type: 'buy',
      strategyType: 'short',
      minConfidence: 0.5,
      riskRewardRatio: 2,
    );

NextDayPredictionResult _prediction({double up = 0.5, double down = 0.5}) =>
    NextDayPredictionResult(
      upProbability: up,
      downProbability: down,
      neutralProbability: 0,
      sampleCount: 20,
      description: 'test',
      featureBins: const {},
    );

MarketContext _market({required double avgChangePct}) => MarketContext(
      shIndexPct: avgChangePct,
      szIndexPct: avgChangePct,
      indexChange: avgChangePct,
      marketTrend: 'neutral',
      upCount: 2100,
      downCount: 2100,
      avgChangePct: avgChangePct,
      updateTime: DateTime(2026, 7, 6),
    );
