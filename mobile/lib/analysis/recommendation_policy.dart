import '../models/short_term_decision.dart';

const String _tradeQualityBelowThreshold = 'trade_quality_below_threshold';
const String _riskAboveThreshold = 'risk_above_threshold';
const String _evidenceConfidenceBelowThreshold =
    'evidence_confidence_below_threshold';

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
    if (directionScore >= 12) {
      return RecommendationDirection.bullish;
    }
    if (directionScore <= -12) {
      return RecommendationDirection.bearish;
    }
    return RecommendationDirection.neutral;
  }

  static RecommendationLevel _levelOf(double directionScore) {
    if (directionScore <= -55) {
      return RecommendationLevel.strongBearish;
    }
    if (directionScore <= -35) {
      return RecommendationLevel.bearish;
    }
    if (directionScore <= -20) {
      return RecommendationLevel.cautiousBearish;
    }
    if (directionScore <= -12) {
      return RecommendationLevel.bearishWatch;
    }
    if (directionScore < 12) {
      return RecommendationLevel.neutralWatch;
    }
    if (directionScore < 20) {
      return RecommendationLevel.bullishWatch;
    }
    if (directionScore < 35) {
      return RecommendationLevel.cautiousBullish;
    }
    if (directionScore < 55) {
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
        if (decision.tradeQualityScore < 70) {
          gates.add(_tradeQualityBelowThreshold);
        }
        if (decision.riskScore > 45) {
          gates.add(_riskAboveThreshold);
        }
        if (decision.evidenceConfidence < 65) {
          gates.add(_evidenceConfidenceBelowThreshold);
        }
        break;
      case RecommendationLevel.bullish:
        if (decision.tradeQualityScore < 60) {
          gates.add(_tradeQualityBelowThreshold);
        }
        if (decision.riskScore > 60) {
          gates.add(_riskAboveThreshold);
        }
        if (decision.evidenceConfidence < 55) {
          gates.add(_evidenceConfidenceBelowThreshold);
        }
        break;
      case RecommendationLevel.cautiousBullish:
        if (decision.tradeQualityScore < 55) {
          gates.add(_tradeQualityBelowThreshold);
        }
        if (decision.riskScore > 70) {
          gates.add(_riskAboveThreshold);
        }
        break;
      case RecommendationLevel.strongBearish:
      case RecommendationLevel.bearish:
      case RecommendationLevel.cautiousBearish:
        if (decision.evidenceConfidence < 55) {
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
    return baseLevel == RecommendationLevel.strongBullish &&
        gates.isEmpty &&
        decision.directionScore >= 55 &&
        decision.tradeQualityScore >= 85 &&
        decision.riskScore <= 30 &&
        decision.evidenceConfidence >= 80;
  }
}
