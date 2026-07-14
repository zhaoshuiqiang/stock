import '../models/stock_models.dart';

class TradeQualityResult {
  final double score;
  final Map<String, double> components;

  const TradeQualityResult({required this.score, required this.components});

  double get timing => components['timing'] ?? 0;
  double get volumePrice => components['volume_price'] ?? 0;
  double get liquidityTurnover => components['liquidity_turnover'] ?? 0;
  double get supportRewardRisk => components['support_reward_risk'] ?? 0;
  double get primaryStrategySupport =>
      components['primary_strategy_support'] ?? 0;
}

class TradeQualityEvaluator {
  static const Map<String, double> weights = {
    'timing': 0.30,
    'volume_price': 0.25,
    'liquidity_turnover': 0.20,
    'support_reward_risk': 0.15,
    'primary_strategy_support': 0.10,
  };

  static TradeQualityResult evaluate({
    required List<HistoryKline> data,
    required List<SignalItem> directionalSignals,
    QuoteData? quote,
    Map<String, dynamic>? tradeLevels,
    bool primaryStrategySupported = false,
    DateTime? now,
  }) {
    final components = <String, double>{
      'timing': _timing(directionalSignals, now ?? DateTime.now()),
      'volume_price': _volumePrice(data, quote),
      'liquidity_turnover': _liquidityTurnover(quote),
      'support_reward_risk': _supportRewardRisk(tradeLevels),
      'primary_strategy_support': primaryStrategySupported ? 85 : 45,
    }.map((key, value) => MapEntry(key, _bounded(value)));
    final score = components.entries.fold<double>(
      0,
      (sum, entry) => sum + entry.value * weights[entry.key]!,
    );
    return TradeQualityResult(
      score: _bounded(score),
      components: Map.unmodifiable(components),
    );
  }

  static double _timing(List<SignalItem> signals, DateTime now) {
    if (signals.isEmpty) return 35;
    var weighted = 0.0;
    var totalWeight = 0.0;
    for (final signal in signals) {
      final durationWeight = switch (signal.duration) {
        SignalDuration.shortTerm => 1.0,
        SignalDuration.mediumTerm => 0.65,
        SignalDuration.longTerm => 0.35,
        null => 0.6,
      };
      final freshnessDate = signal.freshTime ?? signal.timestamp;
      final ageDays = freshnessDate == null
          ? 5
          : now.difference(freshnessDate).inHours.clamp(0, 240) / 24;
      final freshness = ageDays <= 1
          ? 100.0
          : ageDays <= 3
              ? 80.0
              : ageDays <= 5
                  ? 60.0
                  : 35.0;
      final confidence = (signal.confidence ?? 0.6).clamp(0.0, 1.0);
      final strength = (signal.strength / 3).clamp(0.0, 1.0);
      final signalScore =
          freshness * 0.5 + confidence * 100 * 0.3 + strength * 100 * 0.2;
      weighted += signalScore * durationWeight;
      totalWeight += durationWeight;
    }
    final alignmentBonus = signals.length >= 2 ? 8.0 : 0.0;
    return totalWeight == 0 ? 35 : weighted / totalWeight + alignmentBonus;
  }

  static double _volumePrice(List<HistoryKline> data, QuoteData? quote) {
    if (data.isEmpty) return 30;
    final last = data.last;
    final ratio = quote != null && quote.volumeRatio > 0
        ? quote.volumeRatio
        : last.volMa5 > 0
            ? last.volume / last.volMa5
            : 0.0;
    final rising = last.close >= last.open;
    if (rising && ratio >= 1.5) return 90;
    if (rising && ratio >= 1.1) return 72;
    if (rising && ratio > 0) return 55;
    if (!rising && ratio >= 1.3) return 25;
    return 40;
  }

  static double _liquidityTurnover(QuoteData? quote) {
    if (quote == null) return 35;
    final turnover = quote.turnover;
    if (turnover >= 2 && turnover <= 8) return 85;
    if (turnover >= 1 && turnover <= 12) return 65;
    if (turnover > 0 && turnover < 1) return 35;
    if (turnover > 20) return 25;
    return 45;
  }

  static double _supportRewardRisk(Map<String, dynamic>? tradeLevels) {
    if (tradeLevels == null || tradeLevels.isEmpty) return 40;
    final ratio = _asDouble(tradeLevels['risk_reward_ratio']);
    var score = ratio >= 3
        ? 95.0
        : ratio >= 2
            ? 82.0
            : ratio >= 1.5
                ? 65.0
                : ratio > 0
                    ? 30.0
                    : 40.0;
    if (tradeLevels['has_support'] == true) score += 6;
    if (tradeLevels['has_resistance'] == true) score += 3;
    final supportQuality = _asDouble(tradeLevels['support_1_quality']);
    if (supportQuality >= 70) score += 5;
    return score;
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _bounded(double value) => value.clamp(0.0, 100.0).toDouble();
}
