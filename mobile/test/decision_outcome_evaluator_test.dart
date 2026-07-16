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

  test('neutral outcomes do not populate directional hit fields', () {
    final result = DecisionOutcomeEvaluator.evaluate(
      snapshot: _snapshot(RecommendationDirection.neutral),
      outcome: DecisionOutcomeRecord(snapshotId: 1, horizon: 1),
      data: DecisionMarketData(
        adjustedStock: [_bar('2026-07-14', 10), _bar('2026-07-15', 10.1)],
        adjustedBenchmark: [
          _bar('2026-07-14', 100),
          _bar('2026-07-15', 100),
        ],
      ),
      now: DateTime(2026, 7, 15, 16),
    );

    expect(result.status, DecisionOutcomeStatus.evaluated);
    expect(result.rawDirectionHit, isNull);
    expect(result.effectiveDirectionHit, isNull);
    expect(result.alphaHit, isNull);
    expect(result.mfe, isNull);
    expect(result.mae, isNull);
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

  test('invalid outcomes preserve capture-time probability metadata', () {
    final attemptedAt = DateTime(2026, 7, 16, 16, 30);
    final predictionCreatedAt = DateTime(2026, 7, 16, 8, 45);
    final result = DecisionOutcomeEvaluator.evaluate(
      snapshot: _snapshot(RecommendationDirection.bullish),
      outcome: DecisionOutcomeRecord(
        snapshotId: 1,
        horizon: 1,
        predictedProbability: 0.63,
        predictedSampleCount: 128,
        predictedWilsonLower: 0.54,
        predictedWilsonUpper: 0.71,
        predictionCreatedAt: predictionCreatedAt,
      ),
      data: DecisionMarketData(
        adjustedStock: [_bar('2026-07-14', 10)],
        adjustedBenchmark: [_bar('2026-07-15', 100)],
      ),
      now: attemptedAt,
    );

    expect(result.status, DecisionOutcomeStatus.invalid);
    expect(result.lastAttemptedAt, attemptedAt);
    expect(result.predictedProbability, 0.63);
    expect(result.predictedSampleCount, 128);
    expect(result.predictedWilsonLower, 0.54);
    expect(result.predictedWilsonUpper, 0.71);
    expect(result.predictionCreatedAt, predictionCreatedAt);
  });

  test('missing adjusted evidence price never falls back to raw quote price',
      () {
    final result = DecisionOutcomeEvaluator.evaluate(
      snapshot: _snapshot(
        RecommendationDirection.bullish,
        signalTradeDate: DateTime(2026, 7, 15),
        evidenceTradeDate: DateTime(2026, 7, 14),
        signalPhase: DecisionSignalPhase.preMarket,
        signalPrice: 9,
        includeAdjustedSignalPrice: false,
      ),
      outcome: DecisionOutcomeRecord(snapshotId: 1, horizon: 1),
      data: DecisionMarketData(
        adjustedStock: [_bar('2026-07-15', 10)],
        adjustedBenchmark: [
          _bar('2026-07-14', 100),
          _bar('2026-07-15', 101),
        ],
      ),
      now: DateTime(2026, 7, 15, 16),
    );

    expect(result.status, DecisionOutcomeStatus.invalid);
    expect(result.invalidReason, 'adjusted evidence price unavailable');
    expect(result.forecastReturn, isNull);
  });

  test('premarket horizon one targets signal-day close from evidence-day close',
      () {
    final snapshot = _snapshot(
      RecommendationDirection.bullish,
      signalTradeDate: DateTime(2026, 7, 16),
      evidenceTradeDate: DateTime(2026, 7, 15),
      signalPhase: DecisionSignalPhase.preMarket,
      modelVersion: 'short-term-v3',
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
    expect(result.mfe, closeTo(5.8823529, 0.000001));
    expect(result.mae, closeTo(-1.9607843, 0.000001));
  });

  test('target-day intraday bars remain pending until market close', () {
    final result = DecisionOutcomeEvaluator.evaluate(
      snapshot: _snapshot(
        RecommendationDirection.bullish,
        signalTradeDate: DateTime(2026, 7, 16),
        evidenceTradeDate: DateTime(2026, 7, 15),
        signalPhase: DecisionSignalPhase.preMarket,
      ),
      outcome: DecisionOutcomeRecord(snapshotId: 1, horizon: 1),
      data: DecisionMarketData(
        adjustedStock: [
          _bar('2026-07-15', 10),
          _bar('2026-07-16', 10.3),
        ],
        adjustedBenchmark: [
          _bar('2026-07-15', 100),
          _bar('2026-07-16', 101),
        ],
      ),
      now: DateTime(2026, 7, 16, 10),
    );

    expect(result.status, DecisionOutcomeStatus.pending);
    expect(result.dueTradeDate, DateTime(2026, 7, 16));
    expect(result.forecastReturn, isNull);
    expect(result.targetTradeDate, isNull);
  });

  test('stale premarket evidence cannot evaluate before the signal day', () {
    final result = DecisionOutcomeEvaluator.evaluate(
      snapshot: _snapshot(
        RecommendationDirection.bullish,
        signalTradeDate: DateTime(2026, 7, 16),
        evidenceTradeDate: DateTime(2026, 7, 14),
        signalPhase: DecisionSignalPhase.preMarket,
        modelVersion: 'short-term-v3',
      ),
      outcome: DecisionOutcomeRecord(snapshotId: 1, horizon: 1),
      data: DecisionMarketData(
        adjustedStock: [
          _bar('2026-07-14', 10),
          _bar('2026-07-15', 10.2),
          _bar('2026-07-16', 10.4),
        ],
        adjustedBenchmark: [
          _bar('2026-07-14', 100),
          _bar('2026-07-15', 101),
          _bar('2026-07-16', 102),
        ],
      ),
      now: DateTime(2026, 7, 16, 16),
    );

    expect(result.status, DecisionOutcomeStatus.invalid);
    expect(result.invalidReason, 'premarket evidence date is stale');
    expect(result.forecastReturn, isNull);
  });

  test('premarket horizon three follows benchmark trading-day sequence', () {
    final snapshot = _snapshot(
      RecommendationDirection.bullish,
      signalTradeDate: DateTime(2026, 7, 16),
      evidenceTradeDate: DateTime(2026, 7, 15),
      signalPhase: DecisionSignalPhase.preMarket,
      modelVersion: 'short-term-v3',
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
      now: DateTime(2026, 7, 20, 16),
    );

    expect(result.dueTradeDate, DateTime(2026, 7, 20));
    expect(result.targetTradeDate, DateTime(2026, 7, 20));
  });

  test('one-price entry has no executable return or path excursion', () {
    final result = DecisionOutcomeEvaluator.evaluate(
      snapshot: _snapshot(
        RecommendationDirection.bullish,
        signalTradeDate: DateTime(2026, 7, 16),
        evidenceTradeDate: DateTime(2026, 7, 15),
        signalPhase: DecisionSignalPhase.preMarket,
      ),
      outcome: DecisionOutcomeRecord(snapshotId: 1, horizon: 1),
      data: DecisionMarketData(
        adjustedStock: [
          _bar('2026-07-15', 10),
          _bar(
            '2026-07-16',
            11,
            open: 11,
            high: 11,
            low: 11,
            changePct: 10,
          ),
        ],
        adjustedBenchmark: [
          _bar('2026-07-15', 100),
          _bar('2026-07-16', 101),
        ],
      ),
      now: DateTime(2026, 7, 16, 16),
    );

    expect(result.executableValid, isFalse);
    expect(result.executableReturn, isNull);
    expect(result.mfe, isNull);
    expect(result.mae, isNull);
  });

  test('suspension deferral counts benchmark trading days', () {
    final result = DecisionOutcomeEvaluator.evaluate(
      snapshot: _snapshot(
        RecommendationDirection.bullish,
        signalTradeDate: DateTime(2026, 7, 16),
        evidenceTradeDate: DateTime(2026, 7, 15),
        signalPhase: DecisionSignalPhase.preMarket,
      ),
      outcome: DecisionOutcomeRecord(snapshotId: 1, horizon: 1),
      data: DecisionMarketData(
        adjustedStock: [
          _bar('2026-07-15', 10),
          _bar('2026-07-20', 10.4, open: 10.2),
        ],
        adjustedBenchmark: [
          _bar('2026-07-15', 100),
          _bar('2026-07-16', 101),
          _bar('2026-07-17', 102),
          _bar('2026-07-20', 103),
        ],
      ),
      now: DateTime(2026, 7, 20, 16),
    );

    expect(result.dueTradeDate, DateTime(2026, 7, 16));
    expect(result.targetTradeDate, DateTime(2026, 7, 20));
    expect(result.deferredTradeDays, 2);
    expect(result.forecastReturn, closeTo(4, 0.000001));
    expect(result.benchmarkTargetClose, 103);
    expect(result.benchmarkReturn, closeTo(3, 0.000001));
    expect(result.alphaReturn, closeTo(1, 0.000001));
  });

  test('suspension resume-day bar remains pending before close', () {
    final result = DecisionOutcomeEvaluator.evaluate(
      snapshot: _snapshot(
        RecommendationDirection.bullish,
        signalTradeDate: DateTime(2026, 7, 16),
        evidenceTradeDate: DateTime(2026, 7, 15),
        signalPhase: DecisionSignalPhase.preMarket,
      ),
      outcome: DecisionOutcomeRecord(snapshotId: 1, horizon: 1),
      data: DecisionMarketData(
        adjustedStock: [
          _bar('2026-07-15', 10),
          _bar('2026-07-20', 10.4, open: 10.2),
        ],
        adjustedBenchmark: [
          _bar('2026-07-15', 100),
          _bar('2026-07-16', 101),
          _bar('2026-07-17', 102),
          _bar('2026-07-20', 103),
        ],
      ),
      now: DateTime(2026, 7, 20, 10),
    );

    expect(result.status, DecisionOutcomeStatus.pending);
    expect(result.dueTradeDate, DateTime(2026, 7, 16));
    expect(result.targetTradeDate, isNull);
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
      now: DateTime(2026, 7, 17, 16),
    );

    expect(result.dueTradeDate, DateTime(2026, 7, 17));
  });
}

DecisionSnapshotRecord _snapshot(
  RecommendationDirection direction, {
  DateTime? signalTradeDate,
  DateTime? evidenceTradeDate,
  DecisionSignalPhase signalPhase = DecisionSignalPhase.unknown,
  double signalPrice = 10,
  bool includeAdjustedSignalPrice = true,
  String modelVersion = 'v2',
}) =>
    DecisionSnapshotRecord(
      id: 1,
      code: '000001',
      source: 'test',
      signalTime: signalTradeDate ?? DateTime(2026, 7, 14, 15),
      signalTradeDate: signalTradeDate ?? DateTime(2026, 7, 14),
      evidenceTradeDate: evidenceTradeDate,
      signalPhase: signalPhase,
      signalPrice: signalPrice,
      adjustedSignalPrice: includeAdjustedSignalPrice ? 10 : null,
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
      modelVersion: modelVersion,
      createdAt: DateTime(2026, 7, 14, 15),
    );

HistoryKline _bar(
  String date,
  double close, {
  double? open,
  double? high,
  double? low,
  double changePct = 0,
}) =>
    HistoryKline(
      date: DateTime.parse(date),
      open: open ?? close,
      high: high ?? close,
      low: low ?? close,
      close: close,
      changePct: changePct,
    );
