import 'dart:convert';

import '../models/short_term_decision.dart';
import '../models/stock_models.dart';

class DecisionExportRow {
  final DecisionSnapshotRecord snapshot;
  final Map<int, DecisionOutcomeRecord> outcomes;

  const DecisionExportRow({required this.snapshot, required this.outcomes});
}

List<DecisionExportRow> buildDecisionExportRows(
  List<DecisionStatisticsRow> rows,
) {
  final snapshots = <int, DecisionSnapshotRecord>{};
  final outcomes = <int, Map<int, DecisionOutcomeRecord>>{};
  for (final row in rows) {
    final snapshotId = row.snapshot.id;
    if (snapshotId == null) {
      throw ArgumentError.value(
        row.snapshot,
        'rows',
        'Decision export rows require persisted snapshot ids.',
      );
    }
    snapshots[snapshotId] = row.snapshot;
    outcomes.putIfAbsent(snapshotId, () => <int, DecisionOutcomeRecord>{})[
        row.outcome.horizon] = row.outcome;
  }
  return snapshots.entries
      .map(
        (entry) => DecisionExportRow(
          snapshot: entry.value,
          outcomes: Map<int, DecisionOutcomeRecord>.unmodifiable(
            outcomes[entry.key]!,
          ),
        ),
      )
      .toList(growable: false);
}

String decisionExportFileName(DateTime now) {
  String part(int value, int width) => value.toString().padLeft(width, '0');
  final stamp = '${part(now.year, 4)}${part(now.month, 2)}${part(now.day, 2)}_'
      '${part(now.hour, 2)}${part(now.minute, 2)}${part(now.second, 2)}';
  return 'decision_export_$stamp.csv';
}

String buildDecisionCsv(List<DecisionExportRow> rows) {
  final headers = <String>[
    'code',
    'name',
    'app_version',
    'model_version',
    'source',
    'is_retrospective',
    'signal_time',
    'signal_trade_date',
    'evidence_trade_date',
    'signal_phase',
    'signal_price',
    'adjusted_signal_price',
    'benchmark_code',
    'sector_name',
    'direction',
    'direction_score',
    'trade_quality_score',
    'risk_score',
    'evidence_confidence',
    'recommendation_level',
    'recommendation_label',
    'legacy_score',
    'actionable',
    'recommendation_gates',
    'market_regime',
    'market_change_pct',
    'primary_strategy_id',
    'primary_strategy_name',
    'supporting_strategy_ids',
    'direction_components',
    'quality_components',
    'risk_components',
    'data_quality_flags',
    for (final horizon in const [1, 3, 5]) ...[
      'h${horizon}_status',
      'h${horizon}_due_trade_date',
      'h${horizon}_entry_trade_date',
      'h${horizon}_target_trade_date',
      'h${horizon}_deferred_trade_days',
      'h${horizon}_evaluated_at',
      'h${horizon}_adjusted_signal_price_used',
      'h${horizon}_entry_open_price',
      'h${horizon}_target_close_price',
      'h${horizon}_adjusted_target_close_price',
      'h${horizon}_benchmark_signal_close',
      'h${horizon}_benchmark_target_close',
      'h${horizon}_forecast_return',
      'h${horizon}_oriented_return',
      'h${horizon}_executable_return',
      'h${horizon}_oriented_executable_return',
      'h${horizon}_benchmark_return',
      'h${horizon}_alpha_return',
      'h${horizon}_oriented_alpha',
      'h${horizon}_mfe',
      'h${horizon}_mae',
      'h${horizon}_raw_hit',
      'h${horizon}_effective_hit',
      'h${horizon}_alpha_hit',
      'h${horizon}_corporate_action_detected',
      'h${horizon}_executable_valid',
      'h${horizon}_executable_invalid_reason',
      'h${horizon}_predicted_probability',
      'h${horizon}_predicted_sample_count',
      'h${horizon}_wilson_lower',
      'h${horizon}_wilson_upper',
      'h${horizon}_prediction_created_at',
      'h${horizon}_invalid_reason',
      'h${horizon}_attempt_count',
      'h${horizon}_last_attempted_at',
    ],
  ];
  final lines = <String>[headers.map(_escape).join(',')];
  for (final row in rows) {
    final snapshot = row.snapshot;
    final values = <Object?>[
      snapshot.code,
      snapshot.name,
      snapshot.appVersion,
      snapshot.modelVersion,
      snapshot.source,
      _bool(snapshot.isRetrospective),
      _dateTime(snapshot.signalTime),
      _date(snapshot.signalTradeDate),
      _dateNullable(snapshot.evidenceTradeDate),
      snapshot.signalPhase.name,
      snapshot.signalPrice,
      snapshot.adjustedSignalPrice,
      snapshot.benchmarkCode,
      snapshot.sectorName,
      snapshot.direction.name,
      snapshot.directionScore,
      snapshot.tradeQualityScore,
      snapshot.riskScore,
      snapshot.evidenceConfidence,
      snapshot.recommendationLevel,
      snapshot.recommendationLabel,
      snapshot.legacyScore,
      _bool(snapshot.actionable),
      jsonEncode(snapshot.recommendationGates),
      snapshot.marketRegime.name,
      snapshot.marketChangePct,
      snapshot.primaryStrategyId,
      snapshot.primaryStrategyName,
      jsonEncode(snapshot.supportingStrategyIds),
      jsonEncode(snapshot.directionComponents),
      jsonEncode(snapshot.qualityComponents),
      jsonEncode(snapshot.riskComponents),
      jsonEncode(snapshot.dataQualityFlags),
    ];
    for (final horizon in const [1, 3, 5]) {
      final outcome = row.outcomes[horizon];
      values.addAll([
        outcome?.status.name ?? 'pending',
        _dateNullable(outcome?.dueTradeDate),
        _dateNullable(outcome?.entryTradeDate),
        _dateNullable(outcome?.targetTradeDate),
        outcome?.deferredTradeDays,
        _dateTimeNullable(outcome?.evaluatedAt),
        outcome?.adjustedSignalPriceUsed,
        outcome?.entryOpenPrice,
        outcome?.targetClosePrice,
        outcome?.adjustedTargetClosePrice,
        outcome?.benchmarkSignalClose,
        outcome?.benchmarkTargetClose,
        outcome?.forecastReturn,
        _oriented(snapshot.direction, outcome?.forecastReturn),
        outcome?.executableReturn,
        _oriented(snapshot.direction, outcome?.executableReturn),
        outcome?.benchmarkReturn,
        outcome?.alphaReturn,
        _oriented(snapshot.direction, outcome?.alphaReturn),
        outcome?.mfe,
        outcome?.mae,
        _bool(outcome?.rawDirectionHit),
        _bool(outcome?.effectiveDirectionHit),
        _bool(outcome?.alphaHit),
        _bool(outcome?.corporateActionDetected),
        _bool(outcome?.executableValid),
        outcome?.executableInvalidReason,
        outcome?.predictedProbability,
        outcome?.predictedProbability == null
            ? null
            : outcome?.predictedSampleCount,
        outcome?.predictedWilsonLower,
        outcome?.predictedWilsonUpper,
        _dateTimeNullable(outcome?.predictionCreatedAt),
        outcome?.invalidReason,
        outcome?.attemptCount,
        _dateTimeNullable(outcome?.lastAttemptedAt),
      ]);
    }
    lines.add(values.map(_escape).join(','));
  }
  return '\ufeff${lines.join('\r\n')}';
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String? _dateNullable(DateTime? value) => value == null ? null : _date(value);
String _dateTime(DateTime value) => value.toIso8601String();
String? _dateTimeNullable(DateTime? value) =>
    value == null ? null : _dateTime(value);
double? _oriented(
  RecommendationDirection direction,
  double? value,
) {
  if (value == null || direction == RecommendationDirection.neutral) {
    return null;
  }
  return direction == RecommendationDirection.bearish ? -value : value;
}

String? _bool(bool? value) => value == null ? null : (value ? '1' : '0');
String _escape(Object? value) {
  if (value == null) return '';
  final text = value.toString();
  if (text.contains(',') ||
      text.contains('"') ||
      text.contains('\n') ||
      text.contains('\r')) {
    return '"${text.replaceAll('"', '""')}"';
  }
  return text;
}
