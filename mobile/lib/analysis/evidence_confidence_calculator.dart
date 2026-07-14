import '../models/stock_models.dart';

class EvidenceConfidenceResult {
  final double score;
  final Map<String, double> components;

  const EvidenceConfidenceResult({
    required this.score,
    required this.components,
  });

  double get componentAgreement => components['component_agreement'] ?? 0;
  double get dataCoverage => components['data_coverage'] ?? 0;
  double get freshness => components['freshness'] ?? 0;
  double get historyStability => components['history_stability'] ?? 0;
}

class EvidenceConfidenceCalculator {
  static const Map<String, double> weights = {
    'component_agreement': 0.40,
    'data_coverage': 0.25,
    'freshness': 0.20,
    'history_stability': 0.15,
  };

  static EvidenceConfidenceResult calculate({
    required Map<String, double> directionComponents,
    required List<SignalItem> directionalSignals,
    required List<String> dataQualityFlags,
    double historicalStability = 50,
    DateTime? now,
  }) {
    final components = <String, double>{
      'component_agreement': _agreement(directionComponents),
      'data_coverage': _coverage(directionComponents, dataQualityFlags),
      'freshness': _freshness(directionalSignals, now ?? DateTime.now()),
      'history_stability': historicalStability,
    }.map((key, value) => MapEntry(key, _bounded(value)));
    final score = components.entries.fold<double>(
      0,
      (sum, entry) => sum + entry.value * weights[entry.key]!,
    );
    return EvidenceConfidenceResult(
      score: _bounded(score),
      components: Map.unmodifiable(components),
    );
  }

  static double _agreement(Map<String, double> components) {
    final meaningful = components.values
        .where((value) => value.isFinite && value.abs() >= 0.05)
        .toList();
    if (meaningful.isEmpty) return 25;
    final positive = meaningful
        .where((value) => value > 0)
        .fold<double>(0, (sum, value) => sum + value.abs());
    final negative = meaningful
        .where((value) => value < 0)
        .fold<double>(0, (sum, value) => sum + value.abs());
    final total = positive + negative;
    if (total == 0) return 25;
    final dominantShare = (positive > negative ? positive : negative) / total;
    final breadth = (meaningful.length / 5).clamp(0.0, 1.0);
    return dominantShare * 80 + breadth * 20;
  }

  static double _coverage(
    Map<String, double> components,
    List<String> dataQualityFlags,
  ) {
    final covered = components.values
        .where((value) => value.isFinite && value.abs() >= 0.01)
        .length;
    var score = (covered / 5).clamp(0.0, 1.0) * 100;
    for (final flag in dataQualityFlags.toSet()) {
      score -= flag.contains('missing') ? 18 : 10;
    }
    return score;
  }

  static double _freshness(List<SignalItem> signals, DateTime now) {
    if (signals.isEmpty) return 35;
    var total = 0.0;
    for (final signal in signals) {
      final date = signal.freshTime ?? signal.timestamp;
      final ageHours = date == null
          ? 24 * 7
          : now.difference(date).inHours.clamp(0, 24 * 30);
      final ageScore = ageHours <= 24
          ? 100.0
          : ageHours <= 72
              ? 80.0
              : ageHours <= 120
                  ? 60.0
                  : 30.0;
      final confidence = (signal.confidence ?? 0.6).clamp(0.0, 1.0) * 100;
      total += ageScore * 0.7 + confidence * 0.3;
    }
    return total / signals.length;
  }

  static double _bounded(double value) => value.clamp(0.0, 100.0).toDouble();
}
