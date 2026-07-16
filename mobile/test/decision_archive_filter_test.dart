import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/decision_archive_filter.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  test('default view is manual premarket V3 horizon one without backfill', () {
    const filter = kDefaultDecisionArchiveFilter;
    final rows = <DecisionStatisticsRow>[
      _row(id: 1, horizon: 1),
      _row(id: 1, horizon: 3),
      _row(id: 2, horizon: 1, source: 'archive_backfill', retrospective: true),
      _row(id: 3, horizon: 1, source: 'explore'),
      _row(id: 4, horizon: 1, phase: DecisionSignalPhase.afterClose),
      _row(id: 5, horizon: 1, modelVersion: 'short-term-v2'),
    ];

    final filtered = filter.apply(rows);

    expect(filter.horizon, 1);
    expect(filter.sourceGroup, DecisionArchiveSourceGroup.manual);
    expect(filter.signalPhase, DecisionSignalPhase.preMarket);
    expect(filter.modelVersion, 'short-term-v3');
    expect(filter.includeRetrospective, isFalse);
    expect(filtered, hasLength(1));
    expect(filtered.single.snapshot.id, 1);
  });

  test('same filter exports every horizon for selected snapshots', () {
    const filter = DecisionArchiveViewFilter.premarketV3();
    final rows = <DecisionStatisticsRow>[
      _row(id: 1, horizon: 1),
      _row(id: 1, horizon: 3),
      _row(id: 1, horizon: 5),
      _row(id: 2, horizon: 1, source: 'explore'),
    ];

    expect(filter.apply(rows), hasLength(1));
    expect(filter.apply(rows, includeAllHorizons: true), hasLength(3));
  });

  test('source phase date direction regime model and backfill compose', () {
    final filter = DecisionArchiveViewFilter(
      horizon: 3,
      sourceGroup: DecisionArchiveSourceGroup.manual,
      signalPhase: DecisionSignalPhase.afterClose,
      direction: RecommendationDirection.bearish,
      marketRegime: MarketRegime.pullback,
      modelVersion: 'short-term-v3',
      includeRetrospective: true,
      startTradeDate: DateTime(2026, 7, 10),
      endTradeDate: DateTime(2026, 7, 16),
    );
    final rows = <DecisionStatisticsRow>[
      _row(
        id: 1,
        horizon: 3,
        source: 'archive_backfill',
        retrospective: true,
        phase: DecisionSignalPhase.afterClose,
        direction: RecommendationDirection.bearish,
        regime: MarketRegime.pullback,
        signalDate: DateTime(2026, 7, 15),
      ),
      _row(
        id: 2,
        horizon: 3,
        source: 'archive_backfill',
        retrospective: true,
        phase: DecisionSignalPhase.preMarket,
        direction: RecommendationDirection.bearish,
        regime: MarketRegime.pullback,
        signalDate: DateTime(2026, 7, 15),
      ),
      _row(
        id: 3,
        horizon: 3,
        source: 'archive_backfill',
        retrospective: true,
        phase: DecisionSignalPhase.afterClose,
        direction: RecommendationDirection.bearish,
        regime: MarketRegime.pullback,
        signalDate: DateTime(2026, 7, 9),
      ),
    ];

    final filtered = filter.apply(rows);

    expect(filtered, hasLength(1));
    expect(filtered.single.snapshot.id, 1);
  });
}

DecisionStatisticsRow _row({
  required int id,
  required int horizon,
  String source = 'archive',
  String modelVersion = 'short-term-v3',
  bool retrospective = false,
  DecisionSignalPhase phase = DecisionSignalPhase.preMarket,
  RecommendationDirection direction = RecommendationDirection.bullish,
  MarketRegime regime = MarketRegime.range,
  DateTime? signalDate,
}) {
  final date = signalDate ?? DateTime(2026, 7, 16);
  return DecisionStatisticsRow(
    snapshot: DecisionSnapshotRecord(
      id: id,
      code: id.toString().padLeft(6, '0'),
      source: source,
      signalTime: date,
      signalTradeDate: date,
      evidenceTradeDate: date.subtract(const Duration(days: 1)),
      signalPhase: phase,
      signalPrice: 10,
      benchmarkCode: '000300',
      direction: direction,
      directionScore: direction == RecommendationDirection.bearish ? -30 : 30,
      tradeQualityScore: 60,
      riskScore: 30,
      evidenceConfidence: 70,
      recommendationLevel: 'test',
      recommendationLabel: '测试',
      legacyScore: 7,
      marketRegime: regime,
      modelVersion: modelVersion,
      isRetrospective: retrospective,
      createdAt: date,
    ),
    outcome: DecisionOutcomeRecord(
      id: id * 10 + horizon,
      snapshotId: id,
      horizon: horizon,
    ),
  );
}
