import '../models/stock_models.dart';

class ShortTermRiskResult {
  final double score;
  final Map<String, double> components;

  const ShortTermRiskResult({required this.score, required this.components});

  double get volatility => components['volatility'] ?? 0;
  double get executionConstraints => components['execution_constraints'] ?? 0;
  double get chaseOversoldExecution =>
      components['chase_oversold_execution'] ?? 0;
  double get liquidity => components['liquidity'] ?? 0;
  double get eventDataQuality => components['event_data_quality'] ?? 0;
}

class ShortTermRiskEvaluator {
  static const Map<String, double> weights = {
    'volatility': 0.25,
    'execution_constraints': 0.25,
    'chase_oversold_execution': 0.20,
    'liquidity': 0.15,
    'event_data_quality': 0.15,
  };

  static ShortTermRiskResult evaluate({
    required List<HistoryKline> data,
    QuoteData? quote,
    List<String> dataQualityFlags = const [],
    bool hasEventRisk = false,
  }) {
    final components = <String, double>{
      'volatility': _volatility(data, quote),
      'execution_constraints': _executionConstraints(quote),
      'chase_oversold_execution': _chaseOversold(data, quote),
      'liquidity': _liquidity(quote),
      'event_data_quality':
          _eventDataQuality(data, quote, dataQualityFlags, hasEventRisk),
    }.map((key, value) => MapEntry(key, _bounded(value)));
    final score = components.entries.fold<double>(
      0,
      (sum, entry) => sum + entry.value * weights[entry.key]!,
    );
    return ShortTermRiskResult(
      score: _bounded(score),
      components: Map.unmodifiable(components),
    );
  }

  static double _volatility(List<HistoryKline> data, QuoteData? quote) {
    if (data.isEmpty) return 70;
    final last = data.last;
    final atrPct = last.close > 0 ? last.atr14 / last.close * 100 : 0.0;
    var score = atrPct >= 10
        ? 95.0
        : atrPct >= 8
            ? 85.0
            : atrPct >= 5
                ? 65.0
                : atrPct > 0
                    ? 35.0
                    : 55.0;
    if ((quote?.amplitude ?? last.amplitude) >= 10) score += 10;
    return score;
  }

  static double _executionConstraints(QuoteData? quote) {
    if (quote == null) return 65;
    var score = 25.0;
    final onePrice = quote.high > 0 && quote.low > 0 && quote.high == quote.low;
    final limitThreshold = _limitThreshold(quote.code);
    if (onePrice && quote.changePct.abs() >= limitThreshold) return 100;
    if (quote.changePct.abs() >= limitThreshold) score = 90;
    if (quote.changePct.abs() >= 7) score += 15;
    return score;
  }

  static double _chaseOversold(List<HistoryKline> data, QuoteData? quote) {
    if (data.isEmpty) return 60;
    final last = data.last;
    var score = 30.0;
    if (data.length >= 4) {
      final reference = data[data.length - 4].close;
      if (reference > 0) {
        final change3d = (last.close / reference - 1) * 100;
        if (change3d >= 12) score = 90;
        if (change3d <= -8) score = 75;
      }
    }
    if ((quote?.changePct ?? 0) >= 8) score += 15;
    final wr14 = last.wr14;
    if (last.rsi6 >= 80 || wr14 != null && wr14 <= 10) score += 10;
    if (last.rsi6 > 0 && last.rsi6 <= 20 || wr14 != null && wr14 >= 90) {
      score += 10;
    }
    return score;
  }

  static double _liquidity(QuoteData? quote) {
    if (quote == null) return 65;
    final turnover = quote.turnover;
    if (turnover > 25) return 95;
    if (turnover > 15) return 80;
    if (turnover >= 2 && turnover <= 8) return 25;
    if (turnover > 0 && turnover < 0.8) return 75;
    return 45;
  }

  static double _eventDataQuality(
    List<HistoryKline> data,
    QuoteData? quote,
    List<String> flags,
    bool hasEventRisk,
  ) {
    var score = 20.0;
    if (data.length < 5) score += 25;
    if (quote == null || quote.price <= 0) score += 20;
    if (quote != null && _isSt(quote.name)) score += 35;
    if (hasEventRisk) score += 25;
    score += flags.length.clamp(0, 4) * 12;
    return score;
  }

  static bool _isSt(String name) {
    final normalized = name.toUpperCase().replaceAll(' ', '');
    return normalized.contains('ST');
  }

  static double _limitThreshold(String code) {
    final normalized = code.replaceFirst(RegExp(r'^(sh|sz|bj)'), '');
    if (normalized.startsWith('8') || normalized.startsWith('43')) return 29;
    if (normalized.startsWith('688') || normalized.startsWith('30')) return 19;
    return 9.5;
  }

  static double _bounded(double value) => value.clamp(0.0, 100.0).toDouble();
}
