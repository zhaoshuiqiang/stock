import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/decision_calibrator.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  test('eligible bucket returns posterior estimate after hard gates', () {
    final rows = _rows(count: 100, distinctDates: 20, hits: 70);
    final model = DecisionCalibrator.buildModel(
      rows,
      asOfTradeDate: DateTime(2026, 7, 1),
    );
    final estimate = model.estimate(
      modelVersion: 'v2',
      horizon: 3,
      direction: RecommendationDirection.bullish,
      directionScore: 40,
      marketRegime: MarketRegime.range,
    );
    expect(estimate, isNotNull);
    expect(estimate!.sampleCount, 100);
    expect(estimate.probability, closeTo(0.7, 1e-12));
  });

  test('rejects 99 samples fewer than 20 dates and coverage below 95%', () {
    CalibrationEstimate? estimate(List<DecisionCalibrationRow> rows) =>
        DecisionCalibrator.buildModel(
          rows,
          asOfTradeDate: DateTime(2026, 7, 1),
        ).estimate(
          modelVersion: 'v2',
          horizon: 3,
          direction: RecommendationDirection.bullish,
          directionScore: 40,
          marketRegime: MarketRegime.range,
        );
    expect(estimate(_rows(count: 99, distinctDates: 20, hits: 70)), isNull);
    expect(estimate(_rows(count: 100, distinctDates: 19, hits: 70)), isNull);
    expect(
      estimate([
        ..._rows(count: 100, distinctDates: 20, hits: 70),
        ...List.generate(6, (_) => _row(status: DecisionOutcomeStatus.invalid)),
      ]),
      isNull,
    );
  });

  test('does not mix direction horizon version or future-known outcomes', () {
    final rows = _rows(count: 100, distinctDates: 20, hits: 70);
    final model = DecisionCalibrator.buildModel(
      [
        ...rows,
        ..._rows(count: 100, distinctDates: 20, hits: 100)
            .map((row) => row.copyWith(modelVersion: 'v3')),
        _row(
          targetTradeDate: DateTime(2026, 7, 1),
          effectiveDirectionHit: true,
        ),
      ],
      asOfTradeDate: DateTime(2026, 7, 1),
    );
    final estimate = model.estimate(
      modelVersion: 'v2',
      horizon: 3,
      direction: RecommendationDirection.bullish,
      directionScore: 40,
      marketRegime: MarketRegime.range,
    );
    expect(estimate!.sampleCount, 100);
    expect(
      model.estimate(
        modelVersion: 'v2',
        horizon: 3,
        direction: RecommendationDirection.neutral,
        directionScore: 0,
        marketRegime: MarketRegime.range,
      ),
      isNull,
    );
  });

  test('strength bands have stable inclusive lower boundaries', () {
    expect(DecisionCalibrator.strengthBand(12), 0);
    expect(DecisionCalibrator.strengthBand(19.99), 0);
    expect(DecisionCalibrator.strengthBand(20), 1);
    expect(DecisionCalibrator.strengthBand(35), 2);
    expect(DecisionCalibrator.strengthBand(55), 3);
    expect(DecisionCalibrator.strengthBand(100), 3);
  });
}

List<DecisionCalibrationRow> _rows({
  required int count,
  required int distinctDates,
  required int hits,
}) =>
    List.generate(
      count,
      (index) => _row(
        signalTradeDate: DateTime(2026, 1, 1 + index % distinctDates),
        targetTradeDate: DateTime(2026, 2, 1 + index % distinctDates),
        effectiveDirectionHit: index < hits,
      ),
    );

DecisionCalibrationRow _row({
  String modelVersion = 'v2',
  DateTime? signalTradeDate,
  DateTime? targetTradeDate,
  DecisionOutcomeStatus status = DecisionOutcomeStatus.evaluated,
  bool? effectiveDirectionHit = true,
}) =>
    DecisionCalibrationRow(
      modelVersion: modelVersion,
      horizon: 3,
      direction: RecommendationDirection.bullish,
      directionScore: 40,
      marketRegime: MarketRegime.range,
      signalTradeDate: signalTradeDate ?? DateTime(2026, 1, 1),
      targetTradeDate: targetTradeDate ?? DateTime(2026, 2, 1),
      status: status,
      effectiveDirectionHit: effectiveDirectionHit,
    );
