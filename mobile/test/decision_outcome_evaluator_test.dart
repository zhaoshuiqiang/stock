import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/decision_market_data_provider.dart';
import 'package:stock_analyzer/analysis/decision_outcome_evaluator.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  test('uses benchmark trading days and evaluates bullish return and alpha',
      () {
    final snapshot = _snapshot(RecommendationDirection.bullish);
    final result = DecisionOutcomeEvaluator.evaluate(
      snapshot: snapshot,
      outcome: DecisionOutcomeRecord(snapshotId: 1, horizon: 1),
      data: DecisionMarketData(
        adjustedStock: [_bar('2026-07-14', 10), _bar('2026-07-16', 10.1)],
        adjustedBenchmark: [_bar('2026-07-14', 100), _bar('2026-07-16', 100.5)],
      ),
      now: DateTime(2026, 7, 16, 16),
    );
    expect(result.status, DecisionOutcomeStatus.evaluated);
    expect(result.dueTradeDate, DateTime(2026, 7, 16));
    expect(result.forecastReturn, closeTo(1, 0.0001));
    expect(result.alphaReturn, closeTo(0.5, 0.0001));
    expect(result.effectiveDirectionHit, isTrue);
  });

  test('zero return is not a hit and exact half percent is effective', () {
    DecisionOutcomeRecord run(double close) =>
        DecisionOutcomeEvaluator.evaluate(
          snapshot: _snapshot(RecommendationDirection.bearish),
          outcome: DecisionOutcomeRecord(snapshotId: 1, horizon: 1),
          data: DecisionMarketData(
            adjustedStock: [_bar('2026-07-14', 10), _bar('2026-07-15', close)],
            adjustedBenchmark: [
              _bar('2026-07-14', 100),
              _bar('2026-07-15', 100)
            ],
          ),
          now: DateTime(2026, 7, 15, 16),
        );
    expect(run(10).rawDirectionHit, isFalse);
    expect(run(9.95).effectiveDirectionHit, isTrue);
  });

  test('missing future benchmark data remains pending', () {
    final result = DecisionOutcomeEvaluator.evaluate(
      snapshot: _snapshot(RecommendationDirection.neutral),
      outcome: DecisionOutcomeRecord(snapshotId: 1, horizon: 3),
      data: DecisionMarketData(
        adjustedStock: [_bar('2026-07-14', 10)],
        adjustedBenchmark: [_bar('2026-07-14', 100)],
      ),
      now: DateTime(2026, 7, 20),
    );
    expect(result.status, DecisionOutcomeStatus.pending);
    expect(result.forecastReturn, isNull);
  });
}

DecisionSnapshotRecord _snapshot(RecommendationDirection direction) =>
    DecisionSnapshotRecord(
      id: 1,
      code: '000001',
      source: 'test',
      signalTime: DateTime(2026, 7, 14, 15),
      signalTradeDate: DateTime(2026, 7, 14),
      signalPrice: 10,
      adjustedSignalPrice: 10,
      benchmarkCode: '000300',
      direction: direction,
      directionScore: 50,
      tradeQualityScore: 70,
      riskScore: 30,
      evidenceConfidence: 70,
      recommendationLevel: direction.name,
      recommendationLabel: direction.name,
      legacyScore: 7,
      marketRegime: MarketRegime.range,
      modelVersion: 'v2',
      createdAt: DateTime(2026, 7, 14, 15),
    );

HistoryKline _bar(String date, double close) => HistoryKline(
      date: DateTime.parse(date),
      open: close,
      high: close,
      low: close,
      close: close,
    );
