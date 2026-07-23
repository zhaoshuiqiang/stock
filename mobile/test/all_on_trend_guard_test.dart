import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/directional_evidence_builder.dart';
import 'package:stock_analyzer/analysis/market_structure_analyzer.dart';
import 'package:stock_analyzer/analysis/next_day_predictor.dart';
import 'package:stock_analyzer/analysis/next_session_prediction.dart';
import 'package:stock_analyzer/analysis/scoring_config.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/stock_models.dart';

/// P0-1a: strong-trend guard for the all-on stacking scenario.
///
/// When >=2 trend/chase dampeners are active they can over-suppress a genuinely
/// healthy uptrend below the +12 bullish band. The guard restores such a stock
/// to the bullish threshold, and is a strict no-op when <2 dampeners are active
/// (so every single-flag archive-validated result stays byte-identical).
void main() {
  void enableAllTrendDampeners() {
    ScoringConfig.deemphasizeTrendStrength = true;
    ScoringConfig.deemphasizeBreakoutChase = true;
    ScoringConfig.useShortTermTrendDiscount = true;
    ScoringConfig.useShortTermRealtimeReprofile = true;
    ScoringConfig.useRecalibratedDirection = true;
  }

  void resetFlags() {
    ScoringConfig.deemphasizeTrendStrength = false;
    ScoringConfig.deemphasizeBreakoutChase = false;
    ScoringConfig.useShortTermTrendDiscount = false;
    ScoringConfig.useShortTermRealtimeReprofile = false;
    ScoringConfig.useRecalibratedDirection = false;
  }

  setUp(resetFlags);
  tearDown(resetFlags);

  group('ScoringConfig.activeTrendDampenerCount', () {
    test('counts each active dampener; zero by default', () {
      expect(ScoringConfig.activeTrendDampenerCount, 0);
      ScoringConfig.deemphasizeTrendStrength = true;
      ScoringConfig.useShortTermTrendDiscount = true;
      expect(ScoringConfig.activeTrendDampenerCount, 2);
      enableAllTrendDampeners();
      expect(ScoringConfig.activeTrendDampenerCount, 5);
    });
  });

  group('strongTrendGuard', () {
    test('does not fire when all dampeners are off (byte-identical)', () {
      final result = DirectionalEvidenceBuilder.build(_strongTrendInput());
      expect(result.guardReasons, isNot(contains(strongTrendGuard)));
    });

    test('does not fire with only one dampener active (needs >=2)', () {
      ScoringConfig.deemphasizeTrendStrength = true;
      final result = DirectionalEvidenceBuilder.build(_strongTrendInput());
      expect(ScoringConfig.activeTrendDampenerCount, 1);
      expect(result.guardReasons, isNot(contains(strongTrendGuard)));
    });

    test('fires for a confirmed healthy uptrend when all dampeners stack', () {
      enableAllTrendDampeners();
      final result = DirectionalEvidenceBuilder.build(_strongTrendInput());
      expect(result.guardReasons, contains(strongTrendGuard));
      // Restored to (at least) the bullish threshold -- never lowers.
      expect(result.directionScore,
          greaterThanOrEqualTo(kDirectionBullishThreshold));
    });

    test('does not rescue a parabolic/chase stock even when all stack', () {
      enableAllTrendDampeners();
      // Same trend structure but today is +9% => chase territory, not the
      // guard's job (the chase penalty handles it).
      final result = DirectionalEvidenceBuilder.build(
        _strongTrendInput(quoteChangePct: 9.0),
      );
      expect(result.guardReasons, isNot(contains(strongTrendGuard)));
    });
  });
}

/// A confirmed, non-parabolic strong uptrend whose (dampened) direction score
/// lands in the weak-neutral [0, +12) band so the guard's effect is observable.
DirectionalEvidenceInput _strongTrendInput({double quoteChangePct = 2.0}) {
  final data = <HistoryKline>[
    for (var i = 0; i < 8; i++) _bar(i, close: 100.0 + i, open: 99.7 + i),
    // A single down bar caps _consecutiveRiseDays well below the 4-day cutoff.
    _bar(8, close: 106.5, open: 107.0, changePct: -0.5),
    _bar(
      9,
      close: 108.0,
      open: 107.5,
      changePct: 2.0,
      ma5: 107,
      ma10: 105,
      ma20: 103,
      adx14: 30,
      plusDi14: 30,
      minusDi14: 15,
      rsi6: 60,
      bias6: 3,
    ),
  ];
  return DirectionalEvidenceInput(
    data: data,
    buySignals: const <SignalItem>[],
    sellSignals: const <SignalItem>[],
    quote: QuoteData(code: '000001', price: 108.0, changePct: quoteChangePct),
    marketContext: _neutralMarket(),
    marketStructure: MarketStructureResult.unknown(),
    // Left null so relative-strength stays 0 and the score sits safely inside
    // [0, +12); the uptrend check reads quote.changePct instead.
    stockLastCompletedChangePct: null,
    nextDayPrediction: _neutralPrediction(),
    nextSessionPrediction: const NextSessionPrediction.neutral(),
  );
}

HistoryKline _bar(
  int day, {
  required double close,
  required double open,
  double changePct = 0,
  double ma5 = 0,
  double ma10 = 0,
  double ma20 = 0,
  double adx14 = 0,
  double plusDi14 = 0,
  double minusDi14 = 0,
  double rsi6 = 50,
  double bias6 = 0,
}) {
  return HistoryKline(
    date: DateTime.utc(2026, 7, day + 1),
    open: open,
    high: math.max(open, close) + 0.2,
    low: math.min(open, close) - 0.1,
    close: close,
    volume: 1000,
    volMa5: 1000,
    changePct: changePct,
    rsi6: rsi6,
    bias6: bias6,
    ma5: ma5,
    ma10: ma10,
    ma20: ma20,
    adx14: adx14,
    plusDi14: plusDi14,
    minusDi14: minusDi14,
  );
}

NextDayPredictionResult _neutralPrediction() {
  return NextDayPredictionResult(
    upProbability: 0.5,
    downProbability: 0.5,
    neutralProbability: 0,
    sampleCount: 20,
    description: 'test',
    featureBins: const <String, String>{},
  );
}

MarketContext _neutralMarket() {
  return MarketContext(
    shIndexPct: 0,
    szIndexPct: 0,
    indexChange: 0,
    marketTrend: 'neutral',
    upCount: 2200,
    downCount: 2100,
    avgChangePct: 0,
    updateTime: DateTime.utc(2026, 7, 14),
  );
}
