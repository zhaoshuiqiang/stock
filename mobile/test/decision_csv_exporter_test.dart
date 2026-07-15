import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/services/decision_csv_exporter.dart';

void main() {
  test('exports versioned dimensions and independent horizon outcomes', () {
    final snapshot = DecisionSnapshotRecord.minimalForTesting(
      id: 1,
      code: '000001',
      signalTradeDate: DateTime(2026, 7, 14),
    );
    final csv = buildDecisionCsv([
      DecisionExportRow(
        snapshot: snapshot,
        outcomes: {
          1: DecisionOutcomeRecord(snapshotId: 1, horizon: 1),
          3: DecisionOutcomeRecord(
            snapshotId: 1,
            horizon: 3,
            status: DecisionOutcomeStatus.evaluated,
            forecastReturn: 1.2,
            alphaReturn: 0.6,
            predictedProbability: 0.7,
            predictedSampleCount: 120,
            predictedWilsonLower: 0.61,
            predictedWilsonUpper: 0.78,
          ),
          5: DecisionOutcomeRecord(
            snapshotId: 1,
            horizon: 5,
            status: DecisionOutcomeStatus.invalid,
            invalidReason: '数据不足',
          ),
        },
      ),
    ]);
    expect(csv.startsWith('\ufeff'), isTrue);
    expect(csv, contains('model_version'));
    expect(csv, contains('direction_score'));
    expect(csv, contains('h3_forecast_return'));
    expect(csv, contains('h3_predicted_probability'));
    expect(csv, contains('pending'));
    expect(csv, contains('invalid'));
    expect(csv, isNot(contains('pending,0')));
  });

  test('groups all outcome horizons by decision snapshot for export', () {
    final first = DecisionSnapshotRecord.minimalForTesting(
      id: 1,
      code: '000001',
      signalTradeDate: DateTime(2026, 7, 14),
    );
    final second = DecisionSnapshotRecord.minimalForTesting(
      id: 2,
      code: '000002',
      signalTradeDate: DateTime(2026, 7, 14),
    );

    final rows = buildDecisionExportRows([
      DecisionStatisticsRow(
        snapshot: first,
        outcome: DecisionOutcomeRecord(snapshotId: 1, horizon: 1),
      ),
      DecisionStatisticsRow(
        snapshot: first,
        outcome: DecisionOutcomeRecord(snapshotId: 1, horizon: 3),
      ),
      DecisionStatisticsRow(
        snapshot: second,
        outcome: DecisionOutcomeRecord(snapshotId: 2, horizon: 5),
      ),
    ]);

    expect(rows, hasLength(2));
    expect(rows.first.outcomes.keys, containsAll(<int>[1, 3]));
    expect(rows.last.outcomes.keys, contains(5));
  });

  test('uses a distinct filename prefix for decision exports', () {
    expect(
      decisionExportFileName(DateTime(2026, 7, 15, 9, 8, 7)),
      'decision_export_20260715_090807.csv',
    );
  });
}
