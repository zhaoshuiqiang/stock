enum RecommendationDirection { bullish, neutral, bearish }

enum RecommendationLevel {
  strongBearish,
  bearish,
  cautiousBearish,
  bearishWatch,
  neutralWatch,
  bullishWatch,
  cautiousBullish,
  bullish,
  strongBullish,
}

enum MarketRegime {
  bullishTrend,
  bearishTrend,
  rebound,
  pullback,
  range,
  highVolatility,
  unknown,
}

const Set<int> _supportedCalibrationHorizons = <int>{1, 3, 5};

class CalibrationEstimate {
  final int horizon;
  final double probability;
  final int sampleCount;
  final double wilsonLower;
  final double wilsonUpper;

  CalibrationEstimate({
    required this.horizon,
    required this.probability,
    required this.sampleCount,
    required this.wilsonLower,
    required this.wilsonUpper,
  }) {
    if (!_supportedCalibrationHorizons.contains(horizon)) {
      throw ArgumentError.value(
        horizon,
        'horizon',
        'must be one of 1, 3, or 5',
      );
    }
    _validateRange(probability, 'probability', 0.0, 1.0);
    if (sampleCount < 0) {
      throw ArgumentError.value(
        sampleCount,
        'sampleCount',
        'must be greater than or equal to 0',
      );
    }
    _validateRange(wilsonLower, 'wilsonLower', 0.0, 1.0);
    _validateRange(wilsonUpper, 'wilsonUpper', 0.0, 1.0);
  }

  factory CalibrationEstimate.fromJson(Map<String, dynamic> json) {
    return CalibrationEstimate(
      horizon: _intValue(json['horizon'], 'horizon'),
      probability: _doubleValue(json['probability'], 'probability'),
      sampleCount: _intValue(json['sample_count'], 'sample_count'),
      wilsonLower: _doubleValue(json['wilson_lower'], 'wilson_lower'),
      wilsonUpper: _doubleValue(json['wilson_upper'], 'wilson_upper'),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'horizon': horizon,
        'probability': probability,
        'sample_count': sampleCount,
        'wilson_lower': wilsonLower,
        'wilson_upper': wilsonUpper,
      };
}

class ShortTermDecision {
  final double directionScore;
  final double tradeQualityScore;
  final double riskScore;
  final double evidenceConfidence;
  final Map<int, CalibrationEstimate> calibrationByHorizon;
  final RecommendationDirection direction;
  final MarketRegime marketRegime;
  final Map<String, double> directionComponents;
  final Map<String, double> qualityComponents;
  final Map<String, double> riskComponents;
  final String? primaryStrategyId;
  final String? primaryStrategyName;
  final List<String> supportingStrategyIds;
  final List<String> dataQualityFlags;
  final String modelVersion;
  final double rawComprehensiveScore;

  ShortTermDecision({
    required this.directionScore,
    required this.tradeQualityScore,
    required this.riskScore,
    required this.evidenceConfidence,
    Map<int, CalibrationEstimate> calibrationByHorizon = const {},
    required this.direction,
    required this.marketRegime,
    Map<String, double> directionComponents = const {},
    Map<String, double> qualityComponents = const {},
    Map<String, double> riskComponents = const {},
    this.primaryStrategyId,
    this.primaryStrategyName,
    List<String> supportingStrategyIds = const [],
    List<String> dataQualityFlags = const [],
    required this.modelVersion,
    required this.rawComprehensiveScore,
  })  : calibrationByHorizon = Map<int, CalibrationEstimate>.unmodifiable(
          calibrationByHorizon,
        ),
        directionComponents = Map<String, double>.unmodifiable(
          directionComponents,
        ),
        qualityComponents = Map<String, double>.unmodifiable(
          qualityComponents,
        ),
        riskComponents = Map<String, double>.unmodifiable(riskComponents),
        supportingStrategyIds = List<String>.unmodifiable(
          supportingStrategyIds,
        ),
        dataQualityFlags = List<String>.unmodifiable(dataQualityFlags) {
    _validateRange(directionScore, 'directionScore', -100.0, 100.0);
    _validateRange(tradeQualityScore, 'tradeQualityScore', 0.0, 100.0);
    _validateRange(riskScore, 'riskScore', 0.0, 100.0);
    _validateRange(evidenceConfidence, 'evidenceConfidence', 0.0, 100.0);

    for (final entry in this.calibrationByHorizon.entries) {
      if (!_supportedCalibrationHorizons.contains(entry.key)) {
        throw ArgumentError.value(
          entry.key,
          'calibrationByHorizon',
          'keys must be one of 1, 3, or 5',
        );
      }
      if (entry.value.horizon != entry.key) {
        throw ArgumentError.value(
          entry.value.horizon,
          'calibrationByHorizon',
          'estimate horizon must match its map key',
        );
      }
    }
  }

  factory ShortTermDecision.fromJson(Map<String, dynamic> json) {
    return ShortTermDecision(
      directionScore: _doubleValue(
        json['direction_score'],
        'direction_score',
        fallback: 0.0,
      ),
      tradeQualityScore: _doubleValue(
        json['trade_quality_score'],
        'trade_quality_score',
        fallback: 0.0,
      ),
      riskScore: _doubleValue(
        json['risk_score'],
        'risk_score',
        fallback: 0.0,
      ),
      evidenceConfidence: _doubleValue(
        json['evidence_confidence'],
        'evidence_confidence',
        fallback: 0.0,
      ),
      calibrationByHorizon: _calibrationMap(json['calibration_by_horizon']),
      direction: _enumValue(
        RecommendationDirection.values,
        json['direction'],
        RecommendationDirection.neutral,
      ),
      marketRegime: _enumValue(
        MarketRegime.values,
        json['market_regime'],
        MarketRegime.unknown,
      ),
      directionComponents: _doubleMap(json['direction_components']),
      qualityComponents: _doubleMap(json['quality_components']),
      riskComponents: _doubleMap(json['risk_components']),
      primaryStrategyId: json['primary_strategy_id'] as String?,
      primaryStrategyName: json['primary_strategy_name'] as String?,
      supportingStrategyIds: _stringList(json['supporting_strategy_ids']),
      dataQualityFlags: _stringList(json['data_quality_flags']),
      modelVersion: json['model_version'] as String? ?? '',
      rawComprehensiveScore: _doubleValue(
        json['raw_comprehensive_score'],
        'raw_comprehensive_score',
        fallback: 0.0,
      ),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'direction_score': directionScore,
        'trade_quality_score': tradeQualityScore,
        'risk_score': riskScore,
        'evidence_confidence': evidenceConfidence,
        'calibration_by_horizon': calibrationByHorizon.map(
          (horizon, estimate) => MapEntry(
            horizon.toString(),
            estimate.toJson(),
          ),
        ),
        'direction': direction.name,
        'market_regime': marketRegime.name,
        'direction_components': Map<String, double>.from(directionComponents),
        'quality_components': Map<String, double>.from(qualityComponents),
        'risk_components': Map<String, double>.from(riskComponents),
        'primary_strategy_id': primaryStrategyId,
        'primary_strategy_name': primaryStrategyName,
        'supporting_strategy_ids': List<String>.from(supportingStrategyIds),
        'data_quality_flags': List<String>.from(dataQualityFlags),
        'model_version': modelVersion,
        'raw_comprehensive_score': rawComprehensiveScore,
      };

  ShortTermDecision copyWith({
    double? directionScore,
    double? tradeQualityScore,
    double? riskScore,
    double? evidenceConfidence,
    Map<int, CalibrationEstimate>? calibrationByHorizon,
    RecommendationDirection? direction,
    MarketRegime? marketRegime,
    Map<String, double>? directionComponents,
    Map<String, double>? qualityComponents,
    Map<String, double>? riskComponents,
    String? primaryStrategyId,
    String? primaryStrategyName,
    List<String>? supportingStrategyIds,
    List<String>? dataQualityFlags,
    String? modelVersion,
    double? rawComprehensiveScore,
  }) {
    return ShortTermDecision(
      directionScore: directionScore ?? this.directionScore,
      tradeQualityScore: tradeQualityScore ?? this.tradeQualityScore,
      riskScore: riskScore ?? this.riskScore,
      evidenceConfidence: evidenceConfidence ?? this.evidenceConfidence,
      calibrationByHorizon: calibrationByHorizon ?? this.calibrationByHorizon,
      direction: direction ?? this.direction,
      marketRegime: marketRegime ?? this.marketRegime,
      directionComponents: directionComponents ?? this.directionComponents,
      qualityComponents: qualityComponents ?? this.qualityComponents,
      riskComponents: riskComponents ?? this.riskComponents,
      primaryStrategyId: primaryStrategyId ?? this.primaryStrategyId,
      primaryStrategyName: primaryStrategyName ?? this.primaryStrategyName,
      supportingStrategyIds:
          supportingStrategyIds ?? this.supportingStrategyIds,
      dataQualityFlags: dataQualityFlags ?? this.dataQualityFlags,
      modelVersion: modelVersion ?? this.modelVersion,
      rawComprehensiveScore:
          rawComprehensiveScore ?? this.rawComprehensiveScore,
    );
  }
}

class RecommendationDecision {
  final RecommendationDirection direction;
  final RecommendationLevel level;
  final String label;
  final int legacyScore;
  final bool actionable;
  final List<String> gates;

  RecommendationDecision({
    required this.direction,
    required this.level,
    required this.label,
    required this.legacyScore,
    required this.actionable,
    List<String> gates = const [],
  }) : gates = List<String>.unmodifiable(gates) {
    if (legacyScore < 1 || legacyScore > 10) {
      throw ArgumentError.value(
        legacyScore,
        'legacyScore',
        'must be between 1 and 10 inclusive',
      );
    }
  }

  factory RecommendationDecision.fromJson(Map<String, dynamic> json) {
    return RecommendationDecision(
      direction: _enumValue(
        RecommendationDirection.values,
        json['direction'],
        RecommendationDirection.neutral,
      ),
      level: _enumValue(
        RecommendationLevel.values,
        json['level'],
        RecommendationLevel.neutralWatch,
      ),
      label: json['label'] as String? ?? '',
      legacyScore: _intValue(
        json['legacy_score'],
        'legacy_score',
        fallback: 5,
      ),
      actionable: json['actionable'] as bool? ?? false,
      gates: _stringList(json['gates']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'direction': direction.name,
        'level': level.name,
        'label': label,
        'legacy_score': legacyScore,
        'actionable': actionable,
        'gates': List<String>.from(gates),
      };
}

void _validateRange(
  double value,
  String name,
  double minimum,
  double maximum,
) {
  if (!value.isFinite || value < minimum || value > maximum) {
    throw ArgumentError.value(
      value,
      name,
      'must be between $minimum and $maximum inclusive',
    );
  }
}

double _doubleValue(
  Object? value,
  String name, {
  double? fallback,
}) {
  if (value == null && fallback != null) {
    return fallback;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw ArgumentError.value(value, name, 'must be numeric');
}

int _intValue(
  Object? value,
  String name, {
  int? fallback,
}) {
  if (value == null && fallback != null) {
    return fallback;
  }
  if (value is int) {
    return value;
  }
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw ArgumentError.value(value, name, 'must be an integer');
}

T _enumValue<T extends Enum>(
  List<T> values,
  Object? rawValue,
  T fallback,
) {
  if (rawValue is String) {
    for (final value in values) {
      if (value.name == rawValue) {
        return value;
      }
    }
  }
  return fallback;
}

Map<int, CalibrationEstimate> _calibrationMap(Object? value) {
  if (value is! Map) {
    return <int, CalibrationEstimate>{};
  }

  final result = <int, CalibrationEstimate>{};
  for (final entry in value.entries) {
    final horizon = entry.key is int
        ? entry.key as int
        : int.tryParse(entry.key.toString());
    if (horizon == null) {
      throw ArgumentError.value(
        entry.key,
        'calibration_by_horizon',
        'keys must be integer horizons',
      );
    }
    if (entry.value is! Map) {
      throw ArgumentError.value(
        entry.value,
        'calibration_by_horizon',
        'values must be calibration objects',
      );
    }

    final estimateJson = Map<String, dynamic>.from(entry.value as Map);
    estimateJson.putIfAbsent('horizon', () => horizon);
    result[horizon] = CalibrationEstimate.fromJson(estimateJson);
  }
  return result;
}

Map<String, double> _doubleMap(Object? value) {
  if (value is! Map) {
    return <String, double>{};
  }

  return value.map<String, double>((key, rawValue) {
    return MapEntry(
      key.toString(),
      _doubleValue(rawValue, key.toString()),
    );
  });
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return <String>[];
  }
  return List<String>.from(value);
}
