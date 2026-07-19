import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../storage/database_service.dart';
import 'directional_evidence_builder.dart';
import 'scoring_config.dart';

/// One tracked decision paired with its realized outcome, used to learn which
/// direction components actually predict the realized move.
@immutable
class DirectionOutcomeSample {
  /// Signed component values as stored in `decision_snapshots.direction_components_json`
  /// (each roughly in [-1, 1]; positive == bullish evidence).
  final Map<String, double> components;

  /// Realized executable return (%) over the evaluation horizon.
  final double realizedReturn;

  /// Signal trade date (for recency weighting + distinct-date guard).
  final DateTime signalDate;

  const DirectionOutcomeSample({
    required this.components,
    required this.realizedReturn,
    required this.signalDate,
  });
}

/// Data-driven optimizer for the REAL direction-component weights consumed by
/// [DirectionalEvidenceBuilder]. This replaces the dead 7-dim [WeightOptimizer]
/// (which was both unwired and taxonomy-mismatched to the live 5+1-dim engine).
///
/// Method — for each component:
///   - consider only "active" samples where |componentValue| >= [_activeThreshold]
///     (a component near zero carries no directional opinion for that sample);
///   - compute the recency-weighted rate at which sign(componentValue) matches
///     sign(realizedReturn) — i.e. how often the component points the right way;
///   - components that agree with reality more than chance (0.5) are up-weighted,
///     those below chance are down-weighted, bounded by [maxAdjustment];
///   - renormalize so weights sum to 1.0 (preserving the fold semantics).
///
/// All guardrails mirror [DecisionCalibrator]: insufficient samples / distinct
/// dates / per-component activity fall back to the static defaults, so the
/// engine degrades gracefully to today's behavior.
class DirectionalWeightOptimizer {
  DirectionalWeightOptimizer._();

  static const double _activeThreshold = 0.05;
  static const int _minActivePerComponent = 20;

  /// Pure optimization over [samples]. Returns a normalized weight map with the
  /// same keys as [defaults] (defaults to [DirectionalEvidenceBuilder.componentWeights]).
  static Map<String, double> optimize(
    List<DirectionOutcomeSample> samples, {
    Map<String, double>? defaults,
    int minSamples = ScoringConfig.minWeightSamples,
    int minDates = ScoringConfig.minWeightDates,
    double maxAdjustment = ScoringConfig.maxWeightAdjustment,
    double decayFactor = ScoringConfig.weightDecayFactor,
    DateTime? asOf,
  }) {
    final base = defaults ?? DirectionalEvidenceBuilder.componentWeights;
    if (samples.length < minSamples) return _normalize(base);

    final distinctDates = samples
        .map((s) => _dayKey(s.signalDate))
        .toSet()
        .length;
    if (distinctDates < minDates) return _normalize(base);

    final now = asOf ?? DateTime.now();
    final adjusted = <String, double>{};
    for (final key in base.keys) {
      final defaultW = base[key]!;
      double agreeWeight = 0;
      double totalWeight = 0;
      int activeCount = 0;
      for (final s in samples) {
        final v = s.components[key] ?? 0;
        if (v.abs() < _activeThreshold) continue;
        if (s.realizedReturn == 0) continue; // no directional truth
        final w = _timeWeight(now.difference(s.signalDate).inDays, decayFactor);
        totalWeight += w;
        activeCount++;
        final agrees = (v > 0) == (s.realizedReturn > 0);
        if (agrees) agreeWeight += w;
      }
      if (activeCount < _minActivePerComponent || totalWeight <= 0) {
        adjusted[key] = defaultW; // not enough evidence for this component
        continue;
      }
      final agreement = agreeWeight / totalWeight; // 0..1
      final deviation = agreement - 0.5; // -0.5..0.5
      final confidence = math.min(1.0, activeCount / minSamples);
      final adj = (deviation * confidence * 2 * maxAdjustment)
          .clamp(-maxAdjustment, maxAdjustment);
      adjusted[key] = (defaultW + adj).clamp(0.02, 0.5);
    }
    return _normalize(adjusted);
  }

  /// Build samples from raw joined rows (decision_snapshots x decision_outcomes).
  /// Each row must carry `direction_components_json`, `signal_trade_date`,
  /// `executable_return`. Rows with unparseable data are skipped.
  static List<DirectionOutcomeSample> buildSamplesFromRows(
    List<Map<String, dynamic>> rows,
  ) {
    final out = <DirectionOutcomeSample>[];
    for (final row in rows) {
      try {
        final ret = (row['executable_return'] as num?)?.toDouble();
        final dateStr = row['signal_trade_date'] as String?;
        final compJson = row['direction_components_json'] as String?;
        if (ret == null || dateStr == null || compJson == null) continue;
        final date = DateTime.tryParse(dateStr);
        if (date == null) continue;
        final decoded = jsonDecode(compJson);
        if (decoded is! Map) continue;
        final components = <String, double>{};
        decoded.forEach((k, v) {
          final d = (v is num) ? v.toDouble() : double.tryParse(v.toString());
          if (d != null) components[k.toString()] = d;
        });
        if (components.isEmpty) continue;
        out.add(DirectionOutcomeSample(
          components: components,
          realizedReturn: ret,
          signalDate: date,
        ));
      } catch (_) {
        continue;
      }
    }
    return out;
  }

  /// Flag-gated bootstrap: when [ScoringConfig.useDynamicDirectionWeights] is on,
  /// load evaluated 3-day outcomes, optimize, and install the weight override on
  /// [DirectionalEvidenceBuilder]. No-op (and resets to defaults) when off.
  ///
  /// Call once per session (e.g. app start / before a batch scan); never on the
  /// per-stock hot path. Any failure degrades to default weights.
  static Future<void> loadAndApply({
    DatabaseService? storage,
    int horizon = 3,
  }) async {
    if (!ScoringConfig.useDynamicDirectionWeights) {
      DirectionalEvidenceBuilder.applyWeightOverride(null);
      ScoringConfig.activeWeightsVersion = ScoringConfig.defaultWeightsVersion;
      return;
    }
    try {
      final db = await (storage ?? DatabaseService()).database;
      final rows = await db.rawQuery('''
        SELECT s.direction_components_json AS direction_components_json,
               s.signal_trade_date AS signal_trade_date,
               o.executable_return AS executable_return
        FROM decision_snapshots s
        JOIN decision_outcomes o ON o.snapshot_id = s.id
        WHERE o.horizon = ?
          AND o.status = 'evaluated'
          AND o.executable_return IS NOT NULL
        ORDER BY s.signal_trade_date DESC
        LIMIT 2000
      ''', [horizon]);
      final samples = buildSamplesFromRows(rows);
      final weights = optimize(samples);
      final isDefault = _isSameAsDefault(weights);
      DirectionalEvidenceBuilder.applyWeightOverride(isDefault ? null : weights);
      ScoringConfig.activeWeightsVersion =
          isDefault ? ScoringConfig.defaultWeightsVersion : 'w-dyn-v1';
    } catch (e) {
      debugPrint('DirectionalWeightOptimizer.loadAndApply failed: $e');
      DirectionalEvidenceBuilder.applyWeightOverride(null);
      ScoringConfig.activeWeightsVersion = ScoringConfig.defaultWeightsVersion;
    }
  }

  static bool _isSameAsDefault(Map<String, double> weights) {
    final def = _normalize(DirectionalEvidenceBuilder.componentWeights);
    for (final key in def.keys) {
      if (((weights[key] ?? 0) - def[key]!).abs() > 1e-9) return false;
    }
    return true;
  }

  static Map<String, double> _normalize(Map<String, double> w) {
    final total = w.values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return Map<String, double>.from(w);
    return {for (final e in w.entries) e.key: e.value / total};
  }

  static String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  static double _timeWeight(int daysAgo, double decay) {
    if (daysAgo <= 0) return 1.0;
    return math.pow(decay.clamp(0.0, 1.0).toDouble(), daysAgo).toDouble();
  }
}
