import 'dart:convert';

import '../models/stock_models.dart';

class DecisionExportRow {
  final DecisionSnapshotRecord snapshot;
  final Map<int, DecisionOutcomeRecord> outcomes;

  const DecisionExportRow({required this.snapshot, required this.outcomes});
}

String buildDecisionCsv(List<DecisionExportRow> rows) {
  final headers = <String>[
    'code',
    'name',
    'source',
    'signal_trade_date',
    'model_version',
    'direction',
    'direction_score',
    'trade_quality_score',
    'risk_score',
    'evidence_confidence',
    'market_regime',
    'recommendation_label',
    'legacy_score',
    'primary_strategy_id',
    'primary_strategy_name',
    'supporting_strategy_ids',
    'direction_components',
    'quality_components',
    'risk_components',
    'data_quality_flags',
    for (final horizon in const [1, 3, 5]) ...[
      'h${horizon}_status',
      'h${horizon}_forecast_return',
      'h${horizon}_executable_return',
      'h${horizon}_alpha_return',
      'h${horizon}_mfe',
      'h${horizon}_mae',
      'h${horizon}_effective_hit',
      'h${horizon}_alpha_hit',
      'h${horizon}_predicted_probability',
      'h${horizon}_predicted_sample_count',
      'h${horizon}_wilson_lower',
      'h${horizon}_wilson_upper',
      'h${horizon}_invalid_reason',
    ],
  ];
  final lines = <String>[headers.map(_escape).join(',')];
  for (final row in rows) {
    final snapshot = row.snapshot;
    final values = <Object?>[
      snapshot.code,
      snapshot.name,
      snapshot.source,
      _date(snapshot.signalTradeDate),
      snapshot.modelVersion,
      snapshot.direction.name,
      snapshot.directionScore,
      snapshot.tradeQualityScore,
      snapshot.riskScore,
      snapshot.evidenceConfidence,
      snapshot.marketRegime.name,
      snapshot.recommendationLabel,
      snapshot.legacyScore,
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
        outcome?.forecastReturn,
        outcome?.executableReturn,
        outcome?.alphaReturn,
        outcome?.mfe,
        outcome?.mae,
        _bool(outcome?.effectiveDirectionHit),
        _bool(outcome?.alphaHit),
        outcome?.predictedProbability,
        outcome?.predictedProbability == null
            ? null
            : outcome?.predictedSampleCount,
        outcome?.predictedWilsonLower,
        outcome?.predictedWilsonUpper,
        outcome?.invalidReason,
      ]);
    }
    lines.add(values.map(_escape).join(','));
  }
  return '\ufeff${lines.join('\r\n')}';
}

String _date(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
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
