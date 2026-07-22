import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/decision_calibrator.dart';
import 'package:stock_analyzer/analysis/scoring_config.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/stock_models.dart';

/// v4.14: opt-in calibration cold-start. When ScoringConfig.useCalibrationColdStart
/// is off the strict per-(regime x band) gate (>=100/20/95%) is byte-identical to
/// before; when on, progressively wider tiers surface a labeled small-sample
/// estimate so the decision page stops showing "暂无数据" indefinitely.
DecisionCalibrationRow _row({
  double directionScore = 40, // strengthBand == 2
  MarketRegime marketRegime = MarketRegime.range,
  DateTime? signalTradeDate,
  bool hit = true,
}) =>
    DecisionCalibrationRow(
      modelVersion: 'v2',
      horizon: 3,
      direction: RecommendationDirection.bullish,
      directionScore: directionScore,
      marketRegime: marketRegime,
      signalTradeDate: signalTradeDate ?? DateTime(2026, 1, 1),
      targetTradeDate: DateTime(2026, 2, 1),
      status: DecisionOutcomeStatus.evaluated,
      effectiveDirectionHit: hit,
    );

List<DecisionCalibrationRow> _rows({
  required int count,
  required int distinctDates,
  int hits = -1,
}) {
  final h = hits < 0 ? (count * 0.7).round() : hits;
  return List.generate(
    count,
    (i) => _row(
      signalTradeDate: DateTime(2026, 1, 1 + i % distinctDates),
      hit: i < h,
    ),
  );
}

CalibrationEstimate? _estimate(List<DecisionCalibrationRow> rows) =>
    DecisionCalibrator.buildModel(rows, asOfTradeDate: DateTime(2026, 7, 1))
        .estimate(
      modelVersion: 'v2',
      horizon: 3,
      direction: RecommendationDirection.bullish,
      directionScore: 40,
      marketRegime: MarketRegime.range,
    );

void main() {
  tearDown(() => ScoringConfig.useCalibrationColdStart = false);

  test('disabled: a sub-strict sample stays null (legacy behavior)', () {
    ScoringConfig.useCalibrationColdStart = false;
    expect(_estimate(_rows(count: 30, distinctDates: 8)), isNull);
  });

  test('enabled: direction-level tier yields a labeled small-sample estimate',
      () {
    ScoringConfig.useCalibrationColdStart = true;
    final est = _estimate(_rows(count: 25, distinctDates: 8, hits: 18));
    expect(est, isNotNull);
    expect(est!.isColdStart, isTrue);
    expect(est.sampleCount, 25);
  });

  test('enabled: band-level tier (>=40) also produces a cold-start estimate',
      () {
    ScoringConfig.useCalibrationColdStart = true;
    final est = _estimate(_rows(count: 45, distinctDates: 10, hits: 30));
    expect(est, isNotNull);
    expect(est!.isColdStart, isTrue);
    expect(est.sampleCount, 45);
  });

  test('enabled: still rejects too-few samples (<20)', () {
    ScoringConfig.useCalibrationColdStart = true;
    expect(_estimate(_rows(count: 15, distinctDates: 8)), isNull);
  });

  test('strict tier wins over cold-start (isColdStart false at >=100/20)', () {
    ScoringConfig.useCalibrationColdStart = true;
    final est = _estimate(_rows(count: 100, distinctDates: 20, hits: 70));
    expect(est, isNotNull);
    expect(est!.isColdStart, isFalse);
    expect(est.sampleCount, 100);
    expect(est.probability, closeTo(0.7, 1e-9));
  });
}
