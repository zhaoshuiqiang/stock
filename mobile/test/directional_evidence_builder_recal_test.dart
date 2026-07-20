import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/directional_evidence_builder.dart';
import 'package:stock_analyzer/analysis/scoring_config.dart';
import 'package:stock_analyzer/analysis/next_day_predictor.dart';
import 'package:stock_analyzer/analysis/next_session_prediction.dart';
import 'package:stock_analyzer/models/stock_models.dart';

// Self-contained fixtures for the P5 direction-recalibration feature flag
// (ScoringConfig.useRecalibratedDirection). Kept ASCII-only so the file stays
// valid UTF-8 on this toolchain.

HistoryKline _k(
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
    wr14: wr14,
    bias6: bias6,
    ma5: ma5,
    ma10: ma10,
    ma20: ma20,
  );
}

DirectionalEvidenceInput _input(List<HistoryKline> data) {
  return DirectionalEvidenceInput(
    data: data,
    buySignals: const <SignalItem>[],
    sellSignals: const <SignalItem>[],
    quote: QuoteData(code: '000001', price: data.last.close),
    nextDayPrediction: NextDayPredictionResult(
      upProbability: 0.5,
      downProbability: 0.5,
      neutralProbability: 0,
      sampleCount: 20,
      description: 'test',
      featureBins: const <String, String>{},
    ),
    nextSessionPrediction: const NextSessionPrediction.neutral(),
  );
}

// Neutral, low-volatility series: triggers no recalibration-relevant evidence.
List<HistoryKline> _neutral() => <HistoryKline>[
      _k(0, close: 100),
      _k(1, close: 100.2),
      _k(2, close: 100.1),
      _k(3, close: 100.3),
    ];

// Surged + high-volatility + MA-bull + up-volume: the profile the recalibration
// should score lower (chase/volume rewards trimmed, fade evidence added).
List<HistoryKline> _overheated() => <HistoryKline>[
      _k(0, close: 100),
      _k(1, close: 108),
      _k(2, close: 115),
      _k(3, close: 120),
      _k(4, close: 125),
      _k(5,
          close: 130,
          open: 118,
          volume: 2200,
          volMa5: 1000,
          rsi6: 78,
          ma5: 124,
          ma10: 116,
          ma20: 108,
          changePct: 4),
    ];

void main() {
  group('DirectionalEvidenceBuilder recalibration (P5)', () {
    tearDown(() {
      ScoringConfig.useRecalibratedDirection = false;
    });

    test('flag off is byte-identical to on when no recal evidence fires', () {
      ScoringConfig.useRecalibratedDirection = false;
      final off = DirectionalEvidenceBuilder.build(_input(_neutral()));
      ScoringConfig.useRecalibratedDirection = true;
      final on = DirectionalEvidenceBuilder.build(_input(_neutral()));
      expect(on.directionScore, closeTo(off.directionScore, 1e-9));
    });

    test('recalibration lowers score for a surged high-volatility uptrend', () {
      ScoringConfig.useRecalibratedDirection = false;
      final current = DirectionalEvidenceBuilder.build(_input(_overheated()));
      ScoringConfig.useRecalibratedDirection = true;
      final recal = DirectionalEvidenceBuilder.build(_input(_overheated()));
      expect(recal.directionScore, lessThan(current.directionScore));
      expect(current.directionScore - recal.directionScore, greaterThan(2.0));
    });

    test('recalibration makes reversal_momentum clearly bearish on overheat',
        () {
      ScoringConfig.useRecalibratedDirection = true;
      final recal = DirectionalEvidenceBuilder.build(_input(_overheated()));
      expect(recal.components['reversal_momentum']!, lessThan(-0.2));
    });

    test('directionModelVersion tracks the flag', () {
      ScoringConfig.useRecalibratedDirection = false;
      expect(ScoringConfig.directionModelVersion, 'dir-default-v1');
      ScoringConfig.useRecalibratedDirection = true;
      expect(ScoringConfig.directionModelVersion, 'dir-recal-v1');
    });
  });
}
