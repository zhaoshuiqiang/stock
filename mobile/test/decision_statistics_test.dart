import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/decision_statistics.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  test('summary separates statuses denominators and return statistics', () {
    final rows = [
      _row(
          status: DecisionOutcomeStatus.evaluated,
          forecast: 2,
          alpha: 1,
          rawHit: true,
          effectiveHit: true,
          alphaHit: true,
          mfe: 3,
          mae: -1),
      _row(
          status: DecisionOutcomeStatus.evaluated,
          forecast: -1,
          alpha: -2,
          rawHit: false,
          effectiveHit: false,
          alphaHit: false,
          mfe: 1,
          mae: -3),
      _row(status: DecisionOutcomeStatus.invalid),
      _row(
          status: DecisionOutcomeStatus.pending,
          dueDate: DateTime(2026, 7, 14)),
      _row(
          status: DecisionOutcomeStatus.pending,
          dueDate: DateTime(2026, 7, 20)),
    ];
    final summary = DecisionStatistics.summarize(
      rows,
      now: DateTime(2026, 7, 15),
    );
    expect(summary.evaluatedCount, 2);
    expect(summary.invalidCount, 1);
    expect(summary.pendingCount, 2);
    expect(summary.maturedPendingCount, 1);
    expect(summary.coverage, 0.5);
    expect(summary.rawHitRate, 0.5);
    expect(summary.effectiveHitRate, 0.5);
    expect(summary.alphaHitRate, 0.5);
    expect(summary.meanReturn, 0.5);
    expect(summary.medianReturn, 0.5);
    expect(summary.meanAlpha, -0.5);
    expect(summary.meanMfe, 2);
    expect(summary.meanMae, -2);
  });

  test('calibration quality requires 30 outcomes and 10 signal dates', () {
    final insufficient = List.generate(
      29,
      (i) => _row(
          status: DecisionOutcomeStatus.evaluated,
          predicted: 0.7,
          effectiveHit: i < 20),
    );
    expect(
        DecisionStatistics.summarize(insufficient).calibration.brier, isNull);
    final enough = List.generate(
      30,
      (i) => _row(
        status: DecisionOutcomeStatus.evaluated,
        predicted: 0.7,
        effectiveHit: i < 21,
        signalDate: DateTime(2026, 1, 1 + i % 10),
      ),
    );
    final quality = DecisionStatistics.summarize(enough).calibration;
    expect(quality.sampleCount, 30);
    expect(quality.brier, isNotNull);
    expect(quality.ece, isNotNull);
  });
}

DecisionStatisticsRow _row({
  required DecisionOutcomeStatus status,
  double? forecast,
  double? alpha,
  bool? rawHit,
  bool? effectiveHit,
  bool? alphaHit,
  double? mfe,
  double? mae,
  double? predicted,
  DateTime? dueDate,
  DateTime? signalDate,
}) =>
    DecisionStatisticsRow(
      snapshot: DecisionSnapshotRecord.minimalForTesting(
        id: 1,
        code: '000001',
        signalTradeDate: signalDate ?? DateTime(2026, 1, 1),
      ),
      outcome: DecisionOutcomeRecord(
        id: 1,
        snapshotId: 1,
        horizon: 3,
        status: status,
        dueTradeDate: dueDate,
        forecastReturn: forecast,
        alphaReturn: alpha,
        rawDirectionHit: rawHit,
        effectiveDirectionHit: effectiveHit,
        alphaHit: alphaHit,
        mfe: mfe,
        mae: mae,
        predictedProbability: predicted,
      ),
    );
