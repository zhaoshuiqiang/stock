import '../models/short_term_decision.dart';

const String _tradeQualityBelowThreshold = 'trade_quality_below_threshold';
const String _riskAboveThreshold = 'risk_above_threshold';
const String _evidenceConfidenceBelowThreshold =
    'evidence_confidence_below_threshold';

// 方向分数阈值（9级强度映射）
const double _kStrongBearishThreshold = -55.0;
const double _kBearishThreshold = -35.0;
const double _kCautiousBearishThreshold = -20.0;
const double _kBearishWatchThreshold = -12.0;
const double _kBullishWatchThreshold = 12.0;
const double _kCautiousBullishThreshold = 20.0;
const double _kBullishThreshold = 35.0;
const double _kStrongBullishThreshold = 55.0;

// 多头执行门控阈值
const double _kStrongBullishQualityMin = 70.0;
const double _kStrongBullishRiskMax = 45.0;
const double _kStrongBullishConfidenceMin = 65.0;
const double _kBullishQualityMin = 60.0;
const double _kBullishRiskMax = 60.0;
const double _kBullishConfidenceMin = 55.0;
const double _kCautiousBullishQualityMin = 55.0;
const double _kCautiousBullishRiskMax = 70.0;

// 空头证据门控阈值
const double _kBearishConfidenceMin = 55.0;

// 例外强多头阈值（legacyScore=10）
const double _kExceptionalQualityMin = 85.0;
const double _kExceptionalRiskMax = 30.0;
const double _kExceptionalConfidenceMin = 80.0;

class RecommendationPolicy {
  static RecommendationDecision evaluate(ShortTermDecision decision) {
    final direction = _directionOf(decision.directionScore);
    final baseLevel = _levelOf(decision.directionScore);
    final gates = _failedExecutionGates(baseLevel, decision);

    if (gates.isNotEmpty && direction == RecommendationDirection.bullish) {
      return RecommendationDecision(
        direction: direction,
        level: RecommendationLevel.bullishWatch,
        label: '偏多观望',
        legacyScore: 6,
        actionable: false,
        gates: gates,
      );
    }

    if (gates.isNotEmpty && direction == RecommendationDirection.bearish) {
      return RecommendationDecision(
        direction: direction,
        level: RecommendationLevel.bearishWatch,
        label: '偏空观望',
        legacyScore: 4,
        actionable: false,
        gates: gates,
      );
    }

    return RecommendationDecision(
      direction: direction,
      level: baseLevel,
      label: _labelOf(baseLevel),
      legacyScore: _isExceptionalStrongBullish(baseLevel, decision, gates)
          ? 10
          : _legacyScoreOf(baseLevel),
      actionable: _isActionableLevel(baseLevel),
      gates: gates,
    );
  }

  static RecommendationDirection _directionOf(double directionScore) {
    if (directionScore >= kDirectionBullishThreshold) {
      return RecommendationDirection.bullish;
    }
    if (directionScore <= kDirectionBearishThreshold) {
      return RecommendationDirection.bearish;
    }
    return RecommendationDirection.neutral;
  }

  static RecommendationLevel _levelOf(double directionScore) {
    if (directionScore <= _kStrongBearishThreshold) {
      return RecommendationLevel.strongBearish;
    }
    if (directionScore <= _kBearishThreshold) {
      return RecommendationLevel.bearish;
    }
    if (directionScore <= _kCautiousBearishThreshold) {
      return RecommendationLevel.cautiousBearish;
    }
    if (directionScore <= _kBearishWatchThreshold) {
      return RecommendationLevel.bearishWatch;
    }
    if (directionScore < _kBullishWatchThreshold) {
      return RecommendationLevel.neutralWatch;
    }
    if (directionScore < _kCautiousBullishThreshold) {
      return RecommendationLevel.bullishWatch;
    }
    if (directionScore < _kBullishThreshold) {
      return RecommendationLevel.cautiousBullish;
    }
    if (directionScore < _kStrongBullishThreshold) {
      return RecommendationLevel.bullish;
    }
    return RecommendationLevel.strongBullish;
  }

  static List<String> _failedExecutionGates(
    RecommendationLevel level,
    ShortTermDecision decision,
  ) {
    final gates = <String>[];

    switch (level) {
      case RecommendationLevel.strongBullish:
        if (decision.tradeQualityScore < _kStrongBullishQualityMin) {
          gates.add(_tradeQualityBelowThreshold);
        }
        if (decision.riskScore > _kStrongBullishRiskMax) {
          gates.add(_riskAboveThreshold);
        }
        if (decision.evidenceConfidence < _kStrongBullishConfidenceMin) {
          gates.add(_evidenceConfidenceBelowThreshold);
        }
        break;
      case RecommendationLevel.bullish:
        if (decision.tradeQualityScore < _kBullishQualityMin) {
          gates.add(_tradeQualityBelowThreshold);
        }
        if (decision.riskScore > _kBullishRiskMax) {
          gates.add(_riskAboveThreshold);
        }
        if (decision.evidenceConfidence < _kBullishConfidenceMin) {
          gates.add(_evidenceConfidenceBelowThreshold);
        }
        break;
      case RecommendationLevel.cautiousBullish:
        if (decision.tradeQualityScore < _kCautiousBullishQualityMin) {
          gates.add(_tradeQualityBelowThreshold);
        }
        if (decision.riskScore > _kCautiousBullishRiskMax) {
          gates.add(_riskAboveThreshold);
        }
        break;
      case RecommendationLevel.strongBearish:
      case RecommendationLevel.bearish:
      case RecommendationLevel.cautiousBearish:
        if (decision.evidenceConfidence < _kBearishConfidenceMin) {
          gates.add(_evidenceConfidenceBelowThreshold);
        }
        break;
      case RecommendationLevel.bearishWatch:
      case RecommendationLevel.neutralWatch:
      case RecommendationLevel.bullishWatch:
        break;
    }

    return gates;
  }

  static String _labelOf(RecommendationLevel level) {
    switch (level) {
      case RecommendationLevel.strongBearish:
        return '强烈卖出';
      case RecommendationLevel.bearish:
        return '卖出';
      case RecommendationLevel.cautiousBearish:
        return '谨慎卖出';
      case RecommendationLevel.bearishWatch:
        return '偏空观望';
      case RecommendationLevel.neutralWatch:
        return '观望';
      case RecommendationLevel.bullishWatch:
        return '偏多观望';
      case RecommendationLevel.cautiousBullish:
        return '谨慎买入';
      case RecommendationLevel.bullish:
        return '买入';
      case RecommendationLevel.strongBullish:
        return '强烈买入';
    }
  }

  static int _legacyScoreOf(RecommendationLevel level) {
    switch (level) {
      case RecommendationLevel.strongBearish:
        return 1;
      case RecommendationLevel.bearish:
        return 2;
      case RecommendationLevel.cautiousBearish:
        return 3;
      case RecommendationLevel.bearishWatch:
        return 4;
      case RecommendationLevel.neutralWatch:
        return 5;
      case RecommendationLevel.bullishWatch:
        return 6;
      case RecommendationLevel.cautiousBullish:
        return 7;
      case RecommendationLevel.bullish:
        return 8;
      case RecommendationLevel.strongBullish:
        return 9;
    }
  }

  static bool _isActionableLevel(RecommendationLevel level) {
    switch (level) {
      case RecommendationLevel.strongBearish:
      case RecommendationLevel.bearish:
      case RecommendationLevel.cautiousBearish:
      case RecommendationLevel.cautiousBullish:
      case RecommendationLevel.bullish:
      case RecommendationLevel.strongBullish:
        return true;
      case RecommendationLevel.bearishWatch:
      case RecommendationLevel.neutralWatch:
      case RecommendationLevel.bullishWatch:
        return false;
    }
  }

  static bool _isExceptionalStrongBullish(
    RecommendationLevel baseLevel,
    ShortTermDecision decision,
    List<String> gates,
  ) {
    // baseLevel == strongBullish 已隐含 directionScore >= 55
    return baseLevel == RecommendationLevel.strongBullish &&
        gates.isEmpty &&
        decision.tradeQualityScore >= _kExceptionalQualityMin &&
        decision.riskScore <= _kExceptionalRiskMax &&
        decision.evidenceConfidence >= _kExceptionalConfidenceMin;
  }
}
