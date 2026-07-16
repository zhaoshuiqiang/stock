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

  test('premarket horizon one targets signal-day close from evidence-day close',
      () {
    final snapshot = _snapshot(
      RecommendationDirection.bullish,
      signalTradeDate: DateTime(2026, 7, 16),
      evidenceTradeDate: DateTime(2026, 7, 15),
      signalPhase: DecisionSignalPhase.preMarket,
    );
    final result = DecisionOutcomeEvaluator.evaluate(
      snapshot: snapshot,
      outcome: DecisionOutcomeRecord(snapshotId: 1, horizon: 1),
      data: DecisionMarketData(
        adjustedStock: [
          _bar('2026-07-15', 10),
          _bar('2026-07-16', 10.5, open: 10.2, high: 10.8, low: 10),
        ],
        adjustedBenchmark: [
          _bar('2026-07-15', 100),
          _bar('2026-07-16', 101),
        ],
      ),
      now: DateTime(2026, 7, 16, 16),
    );

    expect(result.status, DecisionOutcomeStatus.evaluated);
    expect(result.dueTradeDate, DateTime(2026, 7, 16));
    expect(result.targetTradeDate, DateTime(2026, 7, 16));
    expect(result.entryTradeDate, DateTime(2026, 7, 16));
    expect(result.adjustedSignalPriceUsed, 10);
    expect(result.entryOpenPrice, 10.2);
    expect(result.forecastReturn, closeTo(5, 0.000001));
    expect(result.benchmarkReturn, closeTo(1, 0.000001));
    expect(result.alphaReturn, closeTo(4, 0.000001));
    expect(result.executableReturn, closeTo(2.941176, 0.0001));
    expect(result.mfe, closeTo(8, 0.000001));
    expect(result.mae, closeTo(0, 0.000001));
  });

  test('premarket horizon three follows benchmark trading-day sequence', () {
    final snapshot = _snapshot(
      RecommendationDirection.bullish,
      signalTradeDate: DateTime(2026, 7, 16),
      evidenceTradeDate: DateTime(2026, 7, 15),
      signalPhase: DecisionSignalPhase.preMarket,
    );
    final bars = <HistoryKline>[
      _bar('2026-07-15', 10),
      _bar('2026-07-16', 10.1),
      _bar('2026-07-17', 10.2),
      _bar('2026-07-20', 10.3),
    ];
    final benchmark = <HistoryKline>[
      _bar('2026-07-15', 100),
      _bar('2026-07-16', 101),
      _bar('2026-07-17', 102),
      _bar('2026-07-20', 103),
    ];

    final result = DecisionOutcomeEvaluator.evaluate(
      snapshot: snapshot,
      outcome: DecisionOutcomeRecord(snapshotId: 1, horizon: 3),
      data: DecisionMarketData(
        adjustedStock: bars,
        adjustedBenchmark: benchmark,
      ),
    );

    expect(result.dueTradeDate, DateTime(2026, 7, 20));
    expect(result.targetTradeDate, DateTime(2026, 7, 20));
  });

  test('after-close horizon one keeps the next-trading-day target', () {
    final snapshot = _snapshot(
      RecommendationDirection.bullish,
      signalTradeDate: DateTime(2026, 7, 16),
      evidenceTradeDate: DateTime(2026, 7, 16),
      signalPhase: DecisionSignalPhase.afterClose,
    );
    final result = DecisionOutcomeEvaluator.evaluate(
      snapshot: snapshot,
      outcome: DecisionOutcomeRecord(snapshotId: 1, horizon: 1),
      data: DecisionMarketData(
        adjustedStock: [
          _bar('2026-07-16', 10),
          _bar('2026-07-17', 10.2),
        ],
        adjustedBenchmark: [
          _bar('2026-07-16', 100),
          _bar('2026-07-17', 101),
        ],
      ),
    );

    expect(result.dueTradeDate, DateTime(2026, 7, 17));
  });
}

DecisionSnapshotRecord _snapshot(
  RecommendationDirection direction, {
  DateTime? signalTradeDate,
  DateTime? evidenceTradeDate,
  DecisionSignalPhase signalPhase = DecisionSignalPhase.unknown,
}) =>
    DecisionSnapshotRecord(
      id: 1,
      code: '000001',
      source: 'test',
      signalTime: signalTradeDate ?? DateTime(2026, 7, 14, 15),
      signalTradeDate: signalTradeDate ?? DateTime(2026, 7, 14),
      evidenceTradeDate: evidenceTradeDate,
      signalPhase: signalPhase,
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

HistoryKline _bar(
  String date,
  double close, {
  double? open,
  double? high,
  double? low,
}) =>
    HistoryKline(
      date: DateTime.parse(date),
      open: open ?? close,
      high: high ?? close,
      low: low ?? close,
      close: close,
    );
