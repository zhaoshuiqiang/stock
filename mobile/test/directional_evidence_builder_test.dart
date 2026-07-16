import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/directional_evidence_builder.dart';
import 'package:stock_analyzer/analysis/market_structure_analyzer.dart';
import 'package:stock_analyzer/analysis/next_day_predictor.dart';
import 'package:stock_analyzer/analysis/next_session_prediction.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('DirectionalEvidenceBuilder', () {
    test('returns exactly the five direction component buckets', () {
      final result = DirectionalEvidenceBuilder.build(_input());

      expect(
        result.components.keys,
        unorderedEquals(<String>[
          'trend',
          'reversal_momentum',
          'volume_flow',
          'relative_strength',
          'next_session',
        ]),
      );
      for (final value in result.components.values) {
        expect(value, inInclusiveRange(-1.0, 1.0));
      }
    });

    test('component weights sum to one', () {
      final sum = DirectionalEvidenceBuilder.componentWeights.values
          .fold<double>(0, (total, weight) => total + weight);

      expect(sum, closeTo(1.0, 0.000001));
    });

    test('market contribution changes the final score by no more than 20', () {
      final result = DirectionalEvidenceBuilder.build(
        _input(
          marketContext: _market(
            marketTrend: 'strong_up',
            shIndexPct: 1.2,
            szIndexPct: 1.1,
            avgChangePct: 1.0,
            upCount: 3600,
            downCount: 900,
          ),
        ),
      );

      final scoreWithoutMarketContribution = result.stockEvidence * 0.8;
      final marketContribution =
          result.directionScore - scoreWithoutMarketContribution;

      expect(result.marketRegime, MarketRegime.bullishTrend);
      expect(marketContribution.abs(), lessThanOrEqualTo(20));
    });

    test('rebound guard caps unconfirmed oversold bearish evidence at -19', () {
      final result = DirectionalEvidenceBuilder.build(
        _input(
          data: <HistoryKline>[
            _kline(0, close: 100),
            _kline(1, close: 98),
            _kline(2, close: 96),
            _kline(3, close: 95, rsi6: 28, wr14: 86),
          ],
          sellSignals: <SignalItem>[
            _signal(type: 'sell', indicator: 'MACD', strength: 90),
          ],
          industryRelativeStrength: -100,
          nextSessionPrediction: const NextSessionPrediction(
            nextOpenUpProbability: 0.2,
            nextCloseUpProbability: 0.2,
            expectedNextCloseReturn: -3,
            downsideRiskProbability: 0.8,
            confidence: 1,
            sampleCount: 40,
            scenarioTags: <String>[],
            riskWarnings: <String>[],
          ),
        ),
      );

      expect(result.guardReasons, contains('oversold_rebound_guard'));
      expect(result.directionScore, greaterThanOrEqualTo(-19));
    });

    test(
        'rebound guard does not cap when bearish trend and volume are confirmed',
        () {
      final result = DirectionalEvidenceBuilder.build(
        _input(
          data: <HistoryKline>[
            _kline(0, close: 100),
            _kline(1, close: 98),
            _kline(2, close: 96),
            _kline(
              3,
              close: 95,
              open: 97,
              volume: 2000,
              volMa5: 1000,
              rsi6: 28,
              wr14: 86,
            ),
          ],
          sellSignals: <SignalItem>[
            _signal(type: 'sell', indicator: 'MACD', strength: 90),
            _signal(type: 'sell', indicator: 'VOLUME', strength: 90),
          ],
          nextSessionPrediction: const NextSessionPrediction(
            nextOpenUpProbability: 0.2,
            nextCloseUpProbability: 0.2,
            expectedNextCloseReturn: -3,
            downsideRiskProbability: 0.8,
            confidence: 1,
            sampleCount: 40,
            scenarioTags: <String>[],
            riskWarnings: <String>[],
          ),
        ),
      );

      expect(result.components['trend'], lessThanOrEqualTo(-0.45));
      expect(result.components['volume_flow'], lessThanOrEqualTo(-0.45));
      expect(result.guardReasons, isNot(contains('oversold_rebound_guard')));
      expect(result.directionScore, lessThan(-19));
    });

    test('chase guard caps unconfirmed overbought bullish evidence at 34', () {
      final result = DirectionalEvidenceBuilder.build(
        _input(
          data: <HistoryKline>[
            _kline(0, close: 100),
            _kline(1, close: 101),
            _kline(2, close: 102),
            _kline(3,
                close: 110.16, open: 102, changePct: 8, rsi6: 78, wr14: 8),
          ],
          buySignals: <SignalItem>[
            _signal(type: 'buy', indicator: 'MA', strength: 90),
          ],
          industryRelativeStrength: 100,
          marketContext: _market(
            marketTrend: 'strong_up',
            shIndexPct: 1.2,
            szIndexPct: 1.1,
            avgChangePct: 1.0,
            upCount: 3600,
            downCount: 900,
          ),
          nextDayPrediction: _prediction(
            upProbability: 0.8,
            downProbability: 0.2,
          ),
          nextSessionPrediction: const NextSessionPrediction(
            nextOpenUpProbability: 0.8,
            nextCloseUpProbability: 0.8,
            expectedNextCloseReturn: 3,
            downsideRiskProbability: 0.2,
            confidence: 1,
            sampleCount: 40,
            scenarioTags: <String>[],
            riskWarnings: <String>[],
          ),
        ),
      );

      expect(result.guardReasons, contains('chase_guard'));
      expect(result.directionScore, lessThanOrEqualTo(34));
    });

    test('does not count the same signal in more than one component', () {
      final shared = _signal(
        type: 'buy',
        indicator: 'RSI',
        signal: 'volume reversal breakout',
        strength: 10,
      );

      final result = DirectionalEvidenceBuilder.build(
        _input(
          buySignals: <SignalItem>[shared],
          sellSignals: <SignalItem>[shared],
        ),
      );

      expect(result.signalComponentOwnership, hasLength(1));
      expect(
        result.signalComponentOwnership.values.single,
        'reversal_momentum',
      );
    });

    test('production strength 75 exceeds 45 without saturating', () {
      final weak = DirectionalEvidenceBuilder.build(
        _input(buySignals: <SignalItem>[
          _signal(type: 'buy', indicator: 'MA', strength: 45),
        ]),
      );
      final strong = DirectionalEvidenceBuilder.build(
        _input(buySignals: <SignalItem>[
          _signal(type: 'buy', indicator: 'MA', strength: 75),
        ]),
      );

      expect(strong.components[trendComponentKey],
          greaterThan(weak.components[trendComponentKey]!));
      expect(strong.components[trendComponentKey], lessThan(1));
    });

    test('duration and confidence scale otherwise identical signals', () {
      double trend(SignalDuration duration, double confidence) =>
          DirectionalEvidenceBuilder.build(
            _input(buySignals: <SignalItem>[
              _signal(
                type: 'buy',
                indicator: 'MA',
                strength: 80,
                duration: duration,
                confidence: confidence,
              ),
            ]),
          ).components[trendComponentKey]!;

      expect(trend(SignalDuration.shortTerm, 1),
          greaterThan(trend(SignalDuration.mediumTerm, 1)));
      expect(trend(SignalDuration.mediumTerm, 1),
          greaterThan(trend(SignalDuration.longTerm, 1)));
      expect(trend(SignalDuration.shortTerm, 0.9),
          greaterThan(trend(SignalDuration.shortTerm, 0.4)));
    });

    test('same-family same-direction duplicates retain strongest evidence', () {
      final strongestOnly = DirectionalEvidenceBuilder.build(
        _input(buySignals: <SignalItem>[
          _signal(type: 'buy', indicator: 'MA', strength: 75),
        ]),
      );
      final duplicated = DirectionalEvidenceBuilder.build(
        _input(buySignals: <SignalItem>[
          _signal(type: 'buy', indicator: 'MA', strength: 45),
          _signal(type: 'buy', indicator: 'MA', strength: 75),
        ]),
      );

      expect(duplicated.components[trendComponentKey],
          strongestOnly.components[trendComponentKey]);
    });

    test('same-family opposite evidence offsets and records conflict', () {
      final result = DirectionalEvidenceBuilder.build(
        _input(
          buySignals: <SignalItem>[
            _signal(type: 'buy', indicator: 'MA', strength: 75),
          ],
          sellSignals: <SignalItem>[
            _signal(type: 'sell', indicator: 'MA', strength: 45),
          ],
        ),
      );

      expect(result.components[trendComponentKey], closeTo(0.15, 0.000001));
      expect(result.dataQualityFlags, contains('evidence_family_conflict'));
    });

    test('numeric and textual MA evidence share one family', () {
      final data = <HistoryKline>[
        _kline(0, close: 100),
        _kline(1, close: 100),
        _kline(2, close: 100),
        _kline(3, close: 100, ma5: 103, ma10: 102, ma20: 101),
      ];
      final signalOnly = DirectionalEvidenceBuilder.build(
        _input(
          data: _neutralData(),
          buySignals: <SignalItem>[
            _signal(type: 'buy', indicator: 'MA', strength: 60),
          ],
        ),
      );
      final combined = DirectionalEvidenceBuilder.build(
        _input(
          data: data,
          buySignals: <SignalItem>[
            _signal(type: 'buy', indicator: 'MA', strength: 60),
          ],
        ),
      );

      expect(combined.components[trendComponentKey],
          signalOnly.components[trendComponentKey]);
    });

    // v3.3: WR14 null fallback tests for oversold/chase guards
    test('oversold guard activates with WR14=null using bias6 fallback', () {
      final result = DirectionalEvidenceBuilder.build(
        _input(
          data: <HistoryKline>[
            _kline(0, close: 100),
            _kline(1, close: 98),
            _kline(2, close: 96),
            _kline(3,
                close: 95,
                rsi6: 28,
                wr14: -999,
                bias6: -9), // WR14=-999 treated as null, bias6<=-8=oversold
          ],
          sellSignals: <SignalItem>[
            _signal(type: 'sell', indicator: 'MACD', strength: 90),
          ],
          industryRelativeStrength: -100,
          nextSessionPrediction: const NextSessionPrediction(
            nextOpenUpProbability: 0.2,
            nextCloseUpProbability: 0.2,
            expectedNextCloseReturn: -3,
            downsideRiskProbability: 0.8,
            confidence: 1,
            sampleCount: 40,
            scenarioTags: <String>[],
            riskWarnings: <String>[],
          ),
        ),
      );

      expect(result.guardReasons, contains('oversold_rebound_guard'));
      expect(result.directionScore, greaterThanOrEqualTo(-19));
    });

    test(
        'oversold guard does NOT activate with WR14=null and bias6 not oversold',
        () {
      final result = DirectionalEvidenceBuilder.build(
        _input(
          data: <HistoryKline>[
            _kline(0, close: 100),
            _kline(1, close: 98),
            _kline(2, close: 96),
            _kline(3,
                close: 95,
                rsi6: 28,
                wr14: -999,
                bias6: -5), // bias6=-5 is NOT extreme oversold
          ],
          sellSignals: <SignalItem>[
            _signal(type: 'sell', indicator: 'MACD', strength: 90),
          ],
          nextSessionPrediction: const NextSessionPrediction(
            nextOpenUpProbability: 0.2,
            nextCloseUpProbability: 0.2,
            expectedNextCloseReturn: -3,
            downsideRiskProbability: 0.8,
            confidence: 1,
            sampleCount: 40,
            scenarioTags: <String>[],
            riskWarnings: <String>[],
          ),
        ),
      );

      // Guard should NOT activate because bias6=-5 is not extreme enough
      // to trigger the oversold protection without WR14 confirmation
      expect(result.guardReasons, isNot(contains('oversold_rebound_guard')));
    });

    test('chase guard activates with WR14=null using bias6 fallback', () {
      final result = DirectionalEvidenceBuilder.build(
        _input(
          data: <HistoryKline>[
            _kline(0, close: 100),
            _kline(1, close: 101),
            _kline(2, close: 102),
            _kline(3,
                close: 110.16,
                open: 102,
                changePct: 8,
                rsi6: 65, // RSI<70, so guard falls through to WR14/bias6
                wr14: -999, // WR14=-999 treated as null, use bias6 fallback
                bias6: 9), // bias6>=8=overbought
          ],
          buySignals: <SignalItem>[
            _signal(type: 'buy', indicator: 'MA', strength: 90),
          ],
          industryRelativeStrength: 100,
          marketContext: _market(
            marketTrend: 'strong_up',
            shIndexPct: 1.2,
            szIndexPct: 1.1,
            avgChangePct: 1.0,
            upCount: 3600,
            downCount: 900,
          ),
          nextSessionPrediction: const NextSessionPrediction(
            nextOpenUpProbability: 0.8,
            nextCloseUpProbability: 0.8,
            expectedNextCloseReturn: 3,
            downsideRiskProbability: 0.2,
            confidence: 1,
            sampleCount: 40,
            scenarioTags: <String>[],
            riskWarnings: <String>[],
          ),
        ),
      );

      expect(result.guardReasons, contains('chase_guard'));
      expect(result.directionScore, lessThanOrEqualTo(34));
    });

    test('chase guard does NOT activate with WR14=null and bias6 not extreme',
        () {
      final result = DirectionalEvidenceBuilder.build(
        _input(
          data: <HistoryKline>[
            _kline(0, close: 100),
            _kline(1, close: 101),
            _kline(2, close: 102),
            _kline(3,
                close: 110.16,
                open: 102,
                changePct: 8,
                rsi6: 65, // RSI<70, guard checks WR14/bias6
                wr14: -999, // WR14=-999 treated as null
                bias6: 6), // bias6=6 < 8, NOT extreme overbought
          ],
          buySignals: <SignalItem>[
            _signal(type: 'buy', indicator: 'MA', strength: 90),
          ],
          marketContext: _market(
            marketTrend: 'strong_up',
            shIndexPct: 1.2,
            szIndexPct: 1.1,
            avgChangePct: 1.0,
            upCount: 3600,
            downCount: 900,
          ),
          nextSessionPrediction: const NextSessionPrediction(
            nextOpenUpProbability: 0.8,
            nextCloseUpProbability: 0.8,
            expectedNextCloseReturn: 3,
            downsideRiskProbability: 0.2,
            confidence: 1,
            sampleCount: 40,
            scenarioTags: <String>[],
            riskWarnings: <String>[],
          ),
        ),
      );

      // Guard should NOT activate because bias6=6 is not extreme enough
      // to trigger chase protection without WR14 confirmation
      expect(result.guardReasons, isNot(contains('chase_guard')));
    });
  });
}

DirectionalEvidenceInput _input({
  List<HistoryKline>? data,
  List<SignalItem> buySignals = const <SignalItem>[],
  List<SignalItem> sellSignals = const <SignalItem>[],
  QuoteData? quote,
  MarketContext? marketContext,
  MarketStructureResult? marketStructure,
  double? industryRelativeStrength,
  NextDayPredictionResult? nextDayPrediction,
  NextSessionPrediction nextSessionPrediction =
      const NextSessionPrediction.neutral(),
}) {
  final inputData = data ?? _neutralData();
  return DirectionalEvidenceInput(
    data: inputData,
    buySignals: buySignals,
    sellSignals: sellSignals,
    quote: quote ?? QuoteData(code: '000001', price: inputData.last.close),
    marketContext: marketContext,
    marketStructure: marketStructure ?? MarketStructureResult.unknown(),
    industryRelativeStrength: industryRelativeStrength,
    nextDayPrediction: nextDayPrediction ?? _prediction(),
    nextSessionPrediction: nextSessionPrediction,
  );
}

List<HistoryKline> _neutralData() {
  return <HistoryKline>[
    _kline(0, close: 100),
    _kline(1, close: 100.2),
    _kline(2, close: 100.1),
    _kline(3, close: 100.3),
  ];
}

HistoryKline _kline(
  int day, {
  required double close,
  double? open,
  double volume = 1000,
  double volMa5 = 1000,
  double changePct = 0,
  double rsi6 = 50,
  double wr14 = 50,
  double bias6 = 0,
  double ma5 = 0,
  double ma10 = 0,
  double ma20 = 0,
}) {
  return HistoryKline(
    date: DateTime.utc(2026, 7, day + 1),
    open: open ?? close,
    high: math.max(open ?? close, close),
    low: math.min(open ?? close, close),
    close: close,
    volume: volume,
    volMa5: volMa5,
    changePct: changePct,
    rsi6: rsi6,
    wr14: wr14 == -999 ? null : wr14,
    bias6: bias6,
    ma5: ma5,
    ma10: ma10,
    ma20: ma20,
  );
}

SignalItem _signal({
  required String type,
  required String indicator,
  String signal = '',
  int strength = 8,
  SignalDuration duration = SignalDuration.shortTerm,
  double confidence = 1,
}) {
  return SignalItem(
    type: type,
    indicator: indicator,
    signal: signal,
    strength: strength,
    confidence: confidence,
    duration: duration,
  );
}

NextDayPredictionResult _prediction({
  double upProbability = 0.5,
  double downProbability = 0.5,
}) {
  return NextDayPredictionResult(
    upProbability: upProbability,
    downProbability: downProbability,
    neutralProbability: 0,
    sampleCount: 20,
    description: 'test',
    featureBins: const <String, String>{},
  );
}

MarketContext _market({
  required String marketTrend,
  required double shIndexPct,
  required double szIndexPct,
  required double avgChangePct,
  required int upCount,
  required int downCount,
}) {
  return MarketContext(
    shIndexPct: shIndexPct,
    szIndexPct: szIndexPct,
    indexChange: (shIndexPct + szIndexPct) / 2,
    marketTrend: marketTrend,
    upCount: upCount,
    downCount: downCount,
    avgChangePct: avgChangePct,
    updateTime: DateTime.utc(2026, 7, 14),
  );
}
