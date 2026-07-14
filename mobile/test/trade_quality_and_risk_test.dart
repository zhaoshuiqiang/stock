import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/directional_evidence_builder.dart';
import 'package:stock_analyzer/analysis/short_term_risk_evaluator.dart';
import 'package:stock_analyzer/analysis/trade_quality_evaluator.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('TradeQualityEvaluator', () {
    test('fresh aligned signals and confirmed volume improve quality', () {
      final now = DateTime(2026, 7, 15);
      final data = _klines(
        close: [10, 10.1, 10.3, 10.5, 10.8],
        volume: [1000, 1000, 1100, 1500, 2200],
      );

      final weak = TradeQualityEvaluator.evaluate(
        data: data,
        directionalSignals: const [],
        quote: _quote(turnover: 4),
        now: now,
      );
      final confirmed = TradeQualityEvaluator.evaluate(
        data: data,
        directionalSignals: [
          _signal(freshTime: now.subtract(const Duration(days: 1))),
          _signal(
            indicator: 'MA',
            freshTime: now.subtract(const Duration(days: 2)),
          ),
        ],
        quote: _quote(turnover: 4, volumeRatio: 1.8),
        now: now,
      );

      expect(confirmed.timing, greaterThan(weak.timing));
      expect(confirmed.volumePrice, greaterThan(weak.volumePrice));
      expect(confirmed.score, greaterThan(weak.score));
    });

    test('good support and reward-risk improve quality', () {
      final data = _klines(
        close: [10, 10.1, 10.2, 10.3, 10.4],
        volume: [1000, 1050, 1100, 1150, 1200],
      );
      final poor = TradeQualityEvaluator.evaluate(
        data: data,
        directionalSignals: const [],
        quote: _quote(turnover: 4),
        tradeLevels: const {'risk_reward_ratio': 0.8},
      );
      final good = TradeQualityEvaluator.evaluate(
        data: data,
        directionalSignals: const [],
        quote: _quote(turnover: 4),
        tradeLevels: const {
          'risk_reward_ratio': 2.8,
          'has_support': true,
          'has_resistance': true,
          'support_1_quality': 85,
        },
      );

      expect(good.supportRewardRisk, greaterThan(poor.supportRewardRisk));
      expect(good.score, greaterThan(poor.score));
    });
  });

  group('ShortTermRiskEvaluator', () {
    test('ATR, one-price limit, turnover, ST, and missing data increase risk',
        () {
      final normal = ShortTermRiskEvaluator.evaluate(
        data: _klines(
          close: [10, 10.1, 10.2, 10.3, 10.4],
          volume: [1000, 1050, 1100, 1150, 1200],
          atrPct: 3,
        ),
        quote: _quote(turnover: 4, amplitude: 4),
      );
      final risky = ShortTermRiskEvaluator.evaluate(
        data: _klines(
          close: [10, 10.2, 10.5, 10.9, 11.5],
          volume: [1000, 1300, 1700, 2300, 3100],
          atrPct: 10,
        ),
        quote: _quote(
          name: 'ST test',
          changePct: 10,
          turnover: 28,
          amplitude: 12,
          high: 11,
          low: 11,
        ),
        dataQualityFlags: const ['market_context_missing'],
      );

      expect(risky.volatility, greaterThan(normal.volatility));
      expect(
          risky.executionConstraints, greaterThan(normal.executionConstraints));
      expect(risky.liquidity, greaterThan(normal.liquidity));
      expect(risky.eventDataQuality, greaterThan(normal.eventDataQuality));
      expect(risky.score, greaterThan(normal.score));
    });

    test('risk inputs do not change directional evidence score', () {
      final evidence = DirectionalEvidenceResult(
        components: {
          'trend': 0.4,
          'reversal_momentum': 0.2,
          'volume_flow': 0.3,
          'relative_strength': 0.1,
          'next_session': 0.2,
        },
        stockEvidence: 28,
        marketBias: 25,
        directionScore: 27.4,
        marketRegime: MarketRegime.rebound,
        guardReasons: [],
        dataQualityFlags: [],
        signalComponentOwnership: {},
      );

      ShortTermRiskEvaluator.evaluate(
        data: _klines(
          close: [10, 10.5, 11, 11.6, 12.2],
          volume: [1000, 1500, 2000, 2600, 3300],
          atrPct: 12,
        ),
        quote: _quote(changePct: 10, turnover: 30, high: 12, low: 12),
      );

      expect(evidence.directionScore, 27.4);
    });
  });

  test('component scores and weighted totals stay within 0 to 100', () {
    final quality = TradeQualityEvaluator.evaluate(
      data: _klines(close: [10], volume: [1000], atrPct: 50),
      directionalSignals: [
        _signal(strength: 99, confidence: 5, freshTime: DateTime(2030)),
      ],
      quote: _quote(turnover: 100, volumeRatio: 100),
      tradeLevels: const {'risk_reward_ratio': 100},
      primaryStrategySupported: true,
    );
    final risk = ShortTermRiskEvaluator.evaluate(
      data: _klines(close: [10], volume: [1000], atrPct: 50),
      quote: _quote(
        name: 'ST test',
        changePct: 100,
        turnover: 100,
        amplitude: 100,
        high: 10,
        low: 10,
      ),
      dataQualityFlags: const ['a', 'b', 'c', 'd'],
    );

    expect(quality.components.keys, {
      'timing',
      'volume_price',
      'liquidity_turnover',
      'support_reward_risk',
      'primary_strategy_support',
    });
    expect(risk.components.keys, {
      'volatility',
      'execution_constraints',
      'chase_oversold_execution',
      'liquidity',
      'event_data_quality',
    });
    for (final score in [...quality.components.values, quality.score]) {
      expect(score, inInclusiveRange(0, 100));
    }
    for (final score in [...risk.components.values, risk.score]) {
      expect(score, inInclusiveRange(0, 100));
    }
  });
}

List<HistoryKline> _klines({
  required List<double> close,
  required List<double> volume,
  double atrPct = 3,
}) {
  return List.generate(close.length, (index) {
    final price = close[index];
    final open = index == 0 ? price : close[index - 1];
    final recentVolume = volume.sublist(0, index + 1);
    final volMa5 = recentVolume.reduce((a, b) => a + b) / recentVolume.length;
    return HistoryKline(
      date: DateTime(2026, 7, index + 1),
      open: open,
      high: price * 1.02,
      low: price * 0.98,
      close: price,
      volume: volume[index],
      amount: price * volume[index],
      changePct: open > 0 ? (price / open - 1) * 100 : 0,
      amplitude: 4,
      turnover: 4,
      volMa5: volMa5,
      atr14: price * atrPct / 100,
      rsi6: 55,
      wr14: 45,
    );
  });
}

SignalItem _signal({
  String indicator = 'KDJ',
  int strength = 3,
  double confidence = 0.8,
  DateTime? freshTime,
}) {
  return SignalItem(
    type: 'buy',
    indicator: indicator,
    signal: 'test',
    strength: strength,
    duration: SignalDuration.shortTerm,
    confidence: confidence,
    freshTime: freshTime,
  );
}

QuoteData _quote({
  String name = 'test',
  double changePct = 1,
  double turnover = 4,
  double amplitude = 4,
  double volumeRatio = 1,
  double high = 10.5,
  double low = 9.5,
}) {
  return QuoteData(
    code: 'sh600001',
    name: name,
    price: 10,
    preClose: 10 / (1 + changePct / 100),
    open: 10,
    high: high,
    low: low,
    changePct: changePct,
    turnover: turnover,
    amplitude: amplitude,
    volumeRatio: volumeRatio,
  );
}
