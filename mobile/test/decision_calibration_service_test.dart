import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/decision_calibration_service.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  test('cold start leaves decision uncalibrated and forwards as-of date',
      () async {
    DateTime? received;
    final service = DecisionCalibrationService(rowLoader: (
      modelVersion,
      asOfTradeDate,
    ) async {
      received = asOfTradeDate;
      return [];
    });
    final original = _analysis();
    final date = DateTime(2026, 7, 14);
    final enriched = await service.enrich(original, asOfTradeDate: date);
    expect(received, date);
    expect(enriched.shortTermDecision!.calibrationByHorizon, isEmpty);
    expect(enriched.shortTermDecision, isNot(same(original.shortTermDecision)));
  });

  test('eligible history adds independent horizon estimates', () async {
    final rows = <DecisionCalibrationRow>[];
    for (final horizon in [1, 3, 5]) {
      rows.addAll(List.generate(
        100,
        (index) => DecisionCalibrationRow(
          modelVersion: 'v2',
          horizon: horizon,
          direction: RecommendationDirection.bullish,
          directionScore: 40,
          marketRegime: MarketRegime.range,
          signalTradeDate: DateTime(2026, 1, 1 + index % 20),
          targetTradeDate: DateTime(2026, 2, 1 + index % 20),
          status: DecisionOutcomeStatus.evaluated,
          effectiveDirectionHit: index < 60 + horizon,
        ),
      ));
    }
    final service = DecisionCalibrationService(
      rowLoader: (_, __) async => rows,
    );
    final result = await service.enrich(
      _analysis(),
      asOfTradeDate: DateTime(2026, 7, 1),
    );
    expect(result.shortTermDecision!.calibrationByHorizon.keys, [1, 3, 5]);
    expect(result.shortTermDecision!.calibrationByHorizon[1]!.probability,
        isNot(result.shortTermDecision!.calibrationByHorizon[5]!.probability));
  });
}

AnalysisResult _analysis() => AnalysisResult(
      quote: QuoteData(code: '000001', price: 10),
      score: 7,
      recommendation: '看多',
      shortTermDecision: ShortTermDecision(
        directionScore: 40,
        tradeQualityScore: 70,
        riskScore: 30,
        evidenceConfidence: 70,
        direction: RecommendationDirection.bullish,
        marketRegime: MarketRegime.range,
        modelVersion: 'v2',
        rawComprehensiveScore: 7,
      ),
    );
