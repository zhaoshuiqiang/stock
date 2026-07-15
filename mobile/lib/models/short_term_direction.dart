import 'short_term_decision.dart';

/// 短线方向预测结果（Batch 4 基线模型输出）
///
/// 设计目标：把分散的方向判断整合成一个显式、可解释、可校准的短线方向输出。
/// - [direction] 涨/跌/震荡
/// - [probability] 方向正确的概率（0.5~0.9，避免虚假确定性）
/// - [horizonDays] 预测持有期（交易日）
/// - [componentScores] 5 维分量（-1~1），供 UI 雷达/可解释展示
/// - [supportingEvidence] 人类可读的支撑证据
/// 所有输入均来自 t-1 及之前，无前视偏差。
class DirectionForecast {
  final RecommendationDirection direction;
  final double probability;
  final int horizonDays;
  final Map<String, double> componentScores;
  final List<String> supportingEvidence;
  final String marketRegime;
  final bool momentumPenalized;
  final double rawScore;
  final String modelVersion;

  const DirectionForecast({
    required this.direction,
    required this.probability,
    required this.horizonDays,
    required this.componentScores,
    required this.supportingEvidence,
    required this.marketRegime,
    required this.momentumPenalized,
    required this.rawScore,
    required this.modelVersion,
  });

  static RecommendationDirection _parseDirection(String? value) {
    switch (value) {
      case 'bullish':
        return RecommendationDirection.bullish;
      case 'bearish':
        return RecommendationDirection.bearish;
      default:
        return RecommendationDirection.neutral;
    }
  }

  factory DirectionForecast.fromJson(Map<String, dynamic> json) {
    final comps = <String, double>{};
    final rawComps = json['component_scores'];
    if (rawComps is Map) {
      rawComps.forEach((k, v) {
        if (v is num) comps[k.toString()] = v.toDouble();
      });
    }
    return DirectionForecast(
      direction: _parseDirection(json['direction'] as String?),
      probability: (json['probability'] as num?)?.toDouble() ?? 0.5,
      horizonDays: (json['horizon_days'] as num?)?.toInt() ?? 3,
      componentScores: comps,
      supportingEvidence: (json['supporting_evidence'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      marketRegime: json['market_regime'] as String? ?? '',
      momentumPenalized: json['momentum_penalized'] == true,
      rawScore: (json['raw_score'] as num?)?.toDouble() ?? 0.0,
      modelVersion: json['model_version'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'direction': direction.name,
      'probability': probability,
      'horizon_days': horizonDays,
      'component_scores': componentScores,
      'supporting_evidence': supportingEvidence,
      'market_regime': marketRegime,
      'momentum_penalized': momentumPenalized,
      'raw_score': rawScore,
      'model_version': modelVersion,
    };
  }

  String get directionLabel {
    switch (direction) {
      case RecommendationDirection.bullish:
        return '看涨';
      case RecommendationDirection.bearish:
        return '看跌';
      case RecommendationDirection.neutral:
        return '震荡';
    }
  }
}
