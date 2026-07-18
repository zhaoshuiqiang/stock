import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/recommendation_policy.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';

double _continuousScore(double directionScore, [int gateCount = 0]) {
  var score = (5.0 + directionScore / 100.0 * 5.0).clamp(1.0, 10.0);
  for (var i = 0; i < gateCount; i++) {
    score -= 0.5;
  }
  return score.clamp(1.0, 10.0);
}

void main() {
  group('RecommendationPolicy boundaries', () {
    const cases = <_BoundaryCase>[
      _BoundaryCase(
        score: -55,
        level: RecommendationLevel.strongBearish,
        direction: RecommendationDirection.bearish,
        label: '强烈卖出',
        actionable: true,
      ),
      _BoundaryCase(
        score: -35,
        level: RecommendationLevel.bearish,
        direction: RecommendationDirection.bearish,
        label: '卖出',
        actionable: true,
      ),
      _BoundaryCase(
        score: -20,
        level: RecommendationLevel.cautiousBearish,
        direction: RecommendationDirection.bearish,
        label: '谨慎卖出',
        actionable: true,
      ),
      _BoundaryCase(
        score: -12,
        level: RecommendationLevel.bearishWatch,
        direction: RecommendationDirection.bearish,
        label: '偏空观望',
        actionable: false,
      ),
      _BoundaryCase(
        score: 0,
        level: RecommendationLevel.neutralWatch,
        direction: RecommendationDirection.neutral,
        label: '观望',
        actionable: false,
      ),
      _BoundaryCase(
        score: 12,
        level: RecommendationLevel.bullishWatch,
        direction: RecommendationDirection.bullish,
        label: '偏多观望',
        actionable: false,
      ),
      _BoundaryCase(
        score: 20,
        level: RecommendationLevel.cautiousBullish,
        direction: RecommendationDirection.bullish,
        label: '谨慎买入',
        actionable: true,
      ),
      _BoundaryCase(
        score: 35,
        level: RecommendationLevel.bullish,
        direction: RecommendationDirection.bullish,
        label: '买入',
        actionable: true,
      ),
      _BoundaryCase(
        score: 55,
        level: RecommendationLevel.strongBullish,
        direction: RecommendationDirection.bullish,
        label: '强烈买入',
        actionable: true,
      ),
    ];

    for (final caseData in cases) {
      test('maps score ${caseData.score} at the inclusive boundary', () {
        final result = RecommendationPolicy.evaluate(
          _decision(directionScore: caseData.score),
        );

        expect(result.level, caseData.level);
        expect(result.direction, caseData.direction);
        expect(result.label, caseData.label);
        expect(result.legacyScore, closeTo(_continuousScore(caseData.score), 0.01));
        expect(result.actionable, caseData.actionable);
        expect(result.gates, isEmpty);
      });
    }
  });

  group('RecommendationPolicy threshold probes', () {
    const cases = <_ProbeCase>[
      _ProbeCase(score: -55.01, level: RecommendationLevel.strongBearish, direction: RecommendationDirection.bearish, actionable: true),
      _ProbeCase(score: -55, level: RecommendationLevel.strongBearish, direction: RecommendationDirection.bearish, actionable: true),
      _ProbeCase(score: -54.99, level: RecommendationLevel.bearish, direction: RecommendationDirection.bearish, actionable: true),
      _ProbeCase(score: -35.01, level: RecommendationLevel.bearish, direction: RecommendationDirection.bearish, actionable: true),
      _ProbeCase(score: -35, level: RecommendationLevel.bearish, direction: RecommendationDirection.bearish, actionable: true),
      _ProbeCase(score: -34.99, level: RecommendationLevel.cautiousBearish, direction: RecommendationDirection.bearish, actionable: true),
      _ProbeCase(score: -20.01, level: RecommendationLevel.cautiousBearish, direction: RecommendationDirection.bearish, actionable: true),
      _ProbeCase(score: -20, level: RecommendationLevel.cautiousBearish, direction: RecommendationDirection.bearish, actionable: true),
      _ProbeCase(score: -19.99, level: RecommendationLevel.bearishWatch, direction: RecommendationDirection.bearish, actionable: false),
      _ProbeCase(score: -12.01, level: RecommendationLevel.bearishWatch, direction: RecommendationDirection.bearish, actionable: false),
      _ProbeCase(score: -12, level: RecommendationLevel.bearishWatch, direction: RecommendationDirection.bearish, actionable: false),
      _ProbeCase(score: -11.99, level: RecommendationLevel.neutralWatch, direction: RecommendationDirection.neutral, actionable: false),
      _ProbeCase(score: 11.99, level: RecommendationLevel.neutralWatch, direction: RecommendationDirection.neutral, actionable: false),
      _ProbeCase(score: 12, level: RecommendationLevel.bullishWatch, direction: RecommendationDirection.bullish, actionable: false),
      _ProbeCase(score: 12.01, level: RecommendationLevel.bullishWatch, direction: RecommendationDirection.bullish, actionable: false),
      _ProbeCase(score: 19.99, level: RecommendationLevel.bullishWatch, direction: RecommendationDirection.bullish, actionable: false),
      _ProbeCase(score: 20, level: RecommendationLevel.cautiousBullish, direction: RecommendationDirection.bullish, actionable: true),
      _ProbeCase(score: 20.01, level: RecommendationLevel.cautiousBullish, direction: RecommendationDirection.bullish, actionable: true),
      _ProbeCase(score: 34.99, level: RecommendationLevel.cautiousBullish, direction: RecommendationDirection.bullish, actionable: true),
      _ProbeCase(score: 35, level: RecommendationLevel.bullish, direction: RecommendationDirection.bullish, actionable: true),
      _ProbeCase(score: 35.01, level: RecommendationLevel.bullish, direction: RecommendationDirection.bullish, actionable: true),
      _ProbeCase(score: 54.99, level: RecommendationLevel.bullish, direction: RecommendationDirection.bullish, actionable: true),
      _ProbeCase(score: 55, level: RecommendationLevel.strongBullish, direction: RecommendationDirection.bullish, actionable: true),
      _ProbeCase(score: 55.01, level: RecommendationLevel.strongBullish, direction: RecommendationDirection.bullish, actionable: true),
    ];

    for (final caseData in cases) {
      test('maps score ${caseData.score} to ${caseData.level.name}', () {
        final result = RecommendationPolicy.evaluate(
          _decision(directionScore: caseData.score),
        );

        expect(result.level, caseData.level);
        expect(result.direction, caseData.direction);
        expect(result.legacyScore, closeTo(_continuousScore(caseData.score), 0.01));
        expect(result.actionable, caseData.actionable);
        expect(result.gates, isEmpty);
      });
    }
  });

  group('RecommendationPolicy execution gates', () {
    test(
        'downgrades insufficient-quality bullish decisions without changing direction',
        () {
      final input = _decision(
        directionScore: 55,
        tradeQualityScore: 69.99,
      );

      final result = RecommendationPolicy.evaluate(input);

      expect(result.level, RecommendationLevel.bullishWatch);
      expect(result.direction, RecommendationDirection.bullish);
      expect(result.label, '偏多观望');
      expect(result.legacyScore, closeTo(6.0, 0.01));
      expect(result.actionable, isFalse);
      expect(result.gates, <String>['trade_quality_below_threshold']);
      expect(input.directionScore, 55);
    });

    test('downgrades bullish decisions above their risk threshold', () {
      final result = RecommendationPolicy.evaluate(
        _decision(
          directionScore: 35,
          tradeQualityScore: 60,
          riskScore: 60.01,
          evidenceConfidence: 55,
        ),
      );

      expect(result.level, RecommendationLevel.bullishWatch);
      expect(result.direction, RecommendationDirection.bullish);
      expect(result.label, '偏多观望');
      expect(result.legacyScore, closeTo(6.0, 0.01));
      expect(result.actionable, isFalse);
      expect(result.gates, <String>['risk_above_threshold']);
    });

    test('downgrades bullish decisions below their evidence threshold', () {
      final result = RecommendationPolicy.evaluate(
        _decision(
          directionScore: 35,
          tradeQualityScore: 60,
          riskScore: 60,
          evidenceConfidence: 54.99,
        ),
      );

      expect(result.level, RecommendationLevel.bullishWatch);
      expect(result.direction, RecommendationDirection.bullish);
      expect(result.label, '偏多观望');
      expect(result.legacyScore, closeTo(6.0, 0.01));
      expect(result.actionable, isFalse);
      expect(
        result.gates,
        <String>['evidence_confidence_below_threshold'],
      );
    });

    test('does not impose an evidence gate on cautious bullish decisions', () {
      final result = RecommendationPolicy.evaluate(
        _decision(
          directionScore: 20,
          tradeQualityScore: 55,
          riskScore: 70,
          evidenceConfidence: 0,
        ),
      );

      expect(result.level, RecommendationLevel.cautiousBullish);
      expect(result.direction, RecommendationDirection.bullish);
      expect(result.label, '谨慎买入');
      expect(result.legacyScore, closeTo(_continuousScore(20), 0.01));
      expect(result.actionable, isTrue);
      expect(result.gates, isEmpty);
    });

    test('downgrades bearish decisions when evidence is 54.99', () {
      final result = RecommendationPolicy.evaluate(
        _decision(
          directionScore: -35,
          evidenceConfidence: 54.99,
        ),
      );

      expect(result.level, RecommendationLevel.bearishWatch);
      expect(result.direction, RecommendationDirection.bearish);
      expect(result.label, '偏空观望');
      expect(result.legacyScore, closeTo(4.0, 0.01));
      expect(result.actionable, isFalse);
      expect(
        result.gates,
        <String>['evidence_confidence_below_threshold'],
      );
    });

    test('keeps bearish decisions actionable at evidence 55', () {
      final result = RecommendationPolicy.evaluate(
        _decision(
          directionScore: -35,
          evidenceConfidence: 55,
        ),
      );

      expect(result.level, RecommendationLevel.bearish);
      expect(result.direction, RecommendationDirection.bearish);
      expect(result.label, '卖出');
      expect(result.legacyScore, closeTo(_continuousScore(-35), 0.01));
      expect(result.actionable, isTrue);
      expect(result.gates, isEmpty);
    });

    for (final flag in const <String>[
      'history_data_missing',
      'market_context_missing',
      'market_context_invalid',
      'quote_data_missing',
    ]) {
      test('critical data flag $flag downgrades bullish execution', () {
        final result = RecommendationPolicy.evaluate(
          _decision(
            directionScore: 35,
            tradeQualityScore: 70,
            riskScore: 30,
            evidenceConfidence: 70,
            dataQualityFlags: <String>[flag],
          ),
        );

        expect(result.direction, RecommendationDirection.bullish);
        expect(result.level, RecommendationLevel.bullishWatch);
        expect(result.actionable, isFalse);
        expect(result.gates, contains('critical_data_missing'));
      });
    }

    test('critical data downgrades bearish execution without flipping sign',
        () {
      final result = RecommendationPolicy.evaluate(
        _decision(
          directionScore: -35,
          evidenceConfidence: 70,
          dataQualityFlags: const <String>['market_context_invalid'],
        ),
      );

      expect(result.direction, RecommendationDirection.bearish);
      expect(result.level, RecommendationLevel.bearishWatch);
      expect(result.actionable, isFalse);
      expect(result.gates, contains('critical_data_missing'));
    });
  });

  group('RecommendationPolicy bullish gate boundaries', () {
    const cases = <_GateCase>[
      _GateCase(
        name: 'strong bullish quality just fails',
        directionScore: 55,
        tradeQualityScore: 69.99,
        riskScore: 45,
        evidenceConfidence: 65,
        expectedLevel: RecommendationLevel.bullishWatch,
        expectedActionable: false,
        expectedGates: <String>['trade_quality_below_threshold'],
      ),
      _GateCase(
        name: 'strong bullish quality just passes',
        directionScore: 55,
        tradeQualityScore: 70,
        riskScore: 45,
        evidenceConfidence: 65,
        expectedLevel: RecommendationLevel.strongBullish,
        expectedActionable: true,
      ),
      _GateCase(
        name: 'strong bullish risk just fails',
        directionScore: 55,
        tradeQualityScore: 70,
        riskScore: 45.01,
        evidenceConfidence: 65,
        expectedLevel: RecommendationLevel.bullishWatch,
        expectedActionable: false,
        expectedGates: <String>['risk_above_threshold'],
      ),
      _GateCase(
        name: 'strong bullish risk just passes',
        directionScore: 55,
        tradeQualityScore: 70,
        riskScore: 45,
        evidenceConfidence: 65,
        expectedLevel: RecommendationLevel.strongBullish,
        expectedActionable: true,
      ),
      _GateCase(
        name: 'strong bullish evidence just fails',
        directionScore: 55,
        tradeQualityScore: 70,
        riskScore: 45,
        evidenceConfidence: 64.99,
        expectedLevel: RecommendationLevel.bullishWatch,
        expectedActionable: false,
        expectedGates: <String>['evidence_confidence_below_threshold'],
      ),
      _GateCase(
        name: 'strong bullish evidence just passes',
        directionScore: 55,
        tradeQualityScore: 70,
        riskScore: 45,
        evidenceConfidence: 65,
        expectedLevel: RecommendationLevel.strongBullish,
        expectedActionable: true,
      ),
      _GateCase(
        name: 'bullish quality just fails',
        directionScore: 35,
        tradeQualityScore: 59.99,
        riskScore: 60,
        evidenceConfidence: 55,
        expectedLevel: RecommendationLevel.bullishWatch,
        expectedActionable: false,
        expectedGates: <String>['trade_quality_below_threshold'],
      ),
      _GateCase(
        name: 'bullish quality just passes',
        directionScore: 35,
        tradeQualityScore: 60,
        riskScore: 60,
        evidenceConfidence: 55,
        expectedLevel: RecommendationLevel.bullish,
        expectedActionable: true,
      ),
      _GateCase(
        name: 'bullish risk just fails',
        directionScore: 35,
        tradeQualityScore: 60,
        riskScore: 60.01,
        evidenceConfidence: 55,
        expectedLevel: RecommendationLevel.bullishWatch,
        expectedActionable: false,
        expectedGates: <String>['risk_above_threshold'],
      ),
      _GateCase(
        name: 'bullish risk just passes',
        directionScore: 35,
        tradeQualityScore: 60,
        riskScore: 60,
        evidenceConfidence: 55,
        expectedLevel: RecommendationLevel.bullish,
        expectedActionable: true,
      ),
      _GateCase(
        name: 'bullish evidence just fails',
        directionScore: 35,
        tradeQualityScore: 60,
        riskScore: 60,
        evidenceConfidence: 54.99,
        expectedLevel: RecommendationLevel.bullishWatch,
        expectedActionable: false,
        expectedGates: <String>['evidence_confidence_below_threshold'],
      ),
      _GateCase(
        name: 'bullish evidence just passes',
        directionScore: 35,
        tradeQualityScore: 60,
        riskScore: 60,
        evidenceConfidence: 55,
        expectedLevel: RecommendationLevel.bullish,
        expectedActionable: true,
      ),
      _GateCase(
        name: 'cautious bullish quality just fails',
        directionScore: 20,
        tradeQualityScore: 54.99,
        riskScore: 70,
        evidenceConfidence: 0,
        expectedLevel: RecommendationLevel.bullishWatch,
        expectedActionable: false,
        expectedGates: <String>['trade_quality_below_threshold'],
      ),
      _GateCase(
        name: 'cautious bullish quality just passes',
        directionScore: 20,
        tradeQualityScore: 55,
        riskScore: 70,
        evidenceConfidence: 0,
        expectedLevel: RecommendationLevel.cautiousBullish,
        expectedActionable: true,
      ),
      _GateCase(
        name: 'cautious bullish risk just fails',
        directionScore: 20,
        tradeQualityScore: 55,
        riskScore: 70.01,
        evidenceConfidence: 0,
        expectedLevel: RecommendationLevel.bullishWatch,
        expectedActionable: false,
        expectedGates: <String>['risk_above_threshold'],
      ),
      _GateCase(
        name: 'cautious bullish risk just passes',
        directionScore: 20,
        tradeQualityScore: 55,
        riskScore: 70,
        evidenceConfidence: 0,
        expectedLevel: RecommendationLevel.cautiousBullish,
        expectedActionable: true,
      ),
    ];

    for (final caseData in cases) {
      test(caseData.name, () {
        final result = RecommendationPolicy.evaluate(
          _decision(
            directionScore: caseData.directionScore,
            tradeQualityScore: caseData.tradeQualityScore,
            riskScore: caseData.riskScore,
            evidenceConfidence: caseData.evidenceConfidence,
          ),
        );

        expect(result.direction, RecommendationDirection.bullish);
        expect(result.level, caseData.expectedLevel);
        expect(result.actionable, caseData.expectedActionable);
        expect(result.gates, caseData.expectedGates);
      });
    }
  });

  group('RecommendationPolicy bearish evidence boundaries', () {
    const cases = <_BearishEvidenceCase>[
      _BearishEvidenceCase(
        name: 'strong bearish evidence just fails',
        directionScore: -55,
        evidenceConfidence: 54.99,
        expectedLevel: RecommendationLevel.bearishWatch,
        expectedActionable: false,
        expectedGates: <String>['evidence_confidence_below_threshold'],
      ),
      _BearishEvidenceCase(
        name: 'strong bearish evidence just passes',
        directionScore: -55,
        evidenceConfidence: 55,
        expectedLevel: RecommendationLevel.strongBearish,
        expectedActionable: true,
      ),
      _BearishEvidenceCase(
        name: 'bearish evidence just fails',
        directionScore: -35,
        evidenceConfidence: 54.99,
        expectedLevel: RecommendationLevel.bearishWatch,
        expectedActionable: false,
        expectedGates: <String>['evidence_confidence_below_threshold'],
      ),
      _BearishEvidenceCase(
        name: 'bearish evidence just passes',
        directionScore: -35,
        evidenceConfidence: 55,
        expectedLevel: RecommendationLevel.bearish,
        expectedActionable: true,
      ),
      _BearishEvidenceCase(
        name: 'cautious bearish evidence just fails',
        directionScore: -20,
        evidenceConfidence: 54.99,
        expectedLevel: RecommendationLevel.bearishWatch,
        expectedActionable: false,
        expectedGates: <String>['evidence_confidence_below_threshold'],
      ),
      _BearishEvidenceCase(
        name: 'cautious bearish evidence just passes',
        directionScore: -20,
        evidenceConfidence: 55,
        expectedLevel: RecommendationLevel.cautiousBearish,
        expectedActionable: true,
      ),
    ];

    for (final caseData in cases) {
      test(caseData.name, () {
        final result = RecommendationPolicy.evaluate(
          _decision(
            directionScore: caseData.directionScore,
            evidenceConfidence: caseData.evidenceConfidence,
          ),
        );

        expect(result.direction, RecommendationDirection.bearish);
        expect(result.level, caseData.expectedLevel);
        expect(result.actionable, caseData.expectedActionable);
        expect(result.gates, caseData.expectedGates);
      });
    }
  });

  group('RecommendationPolicy exceptional legacy score', () {
    final belowExceptionalCases = <_ExceptionalCase>[
      _ExceptionalCase(
        name: 'direction score',
        decision: _decision(
          directionScore: 54.99,
          tradeQualityScore: 85,
          riskScore: 30,
          evidenceConfidence: 80,
        ),
        expectedLevel: RecommendationLevel.bullish,
      ),
      _ExceptionalCase(
        name: 'trade quality',
        decision: _decision(
          directionScore: 55,
          tradeQualityScore: 84.99,
          riskScore: 30,
          evidenceConfidence: 80,
        ),
        expectedLevel: RecommendationLevel.strongBullish,
      ),
      _ExceptionalCase(
        name: 'risk',
        decision: _decision(
          directionScore: 55,
          tradeQualityScore: 85,
          riskScore: 30.01,
          evidenceConfidence: 80,
        ),
        expectedLevel: RecommendationLevel.strongBullish,
      ),
      _ExceptionalCase(
        name: 'evidence',
        decision: _decision(
          directionScore: 55,
          tradeQualityScore: 85,
          riskScore: 30,
          evidenceConfidence: 79.99,
        ),
        expectedLevel: RecommendationLevel.strongBullish,
      ),
    ];

    for (final caseData in belowExceptionalCases) {
      test('${caseData.name} just outside the exceptional limit is not 10', () {
        final result = RecommendationPolicy.evaluate(caseData.decision);

        expect(result.level, caseData.expectedLevel);
        expect(result.direction, RecommendationDirection.bullish);
        expect(result.legacyScore, isNot(10.0));
        expect(result.legacyScore, lessThan(10.0));
        expect(result.actionable, isTrue);
        expect(result.gates, isEmpty);
      });
    }

    test('returns legacy 10 only when every exceptional condition is met', () {
      final result = RecommendationPolicy.evaluate(
        _decision(
          directionScore: 55,
          tradeQualityScore: 85,
          riskScore: 30,
          evidenceConfidence: 80,
        ),
      );

      expect(result.level, RecommendationLevel.strongBullish);
      expect(result.direction, RecommendationDirection.bullish);
      expect(result.label, '强烈买入');
      expect(result.legacyScore, 10.0);
      expect(result.actionable, isTrue);
      expect(result.gates, isEmpty);
    });
  });

  group('RecommendationDecision field access', () {
    final source = RecommendationDecision(
      direction: RecommendationDirection.bearish,
      level: RecommendationLevel.strongBearish,
      label: '强烈卖出',
      legacyScore: 10.0,
      actionable: false,
      gates: const <String>['test_gate'],
    );

    test('fields are directly accessible without adapter', () {
      expect(source.legacyScore, 10.0);
      expect(source.label, '强烈卖出');
      expect(source.actionable, false);
      expect(source.gates, ['test_gate']);
    });
  });
}

ShortTermDecision _decision({
  required double directionScore,
  double tradeQualityScore = 70,
  double riskScore = 45,
  double evidenceConfidence = 65,
  List<String> dataQualityFlags = const <String>[],
}) {
  return ShortTermDecision(
    directionScore: directionScore,
    tradeQualityScore: tradeQualityScore,
    riskScore: riskScore,
    evidenceConfidence: evidenceConfidence,
    direction: RecommendationDirection.neutral,
    marketRegime: MarketRegime.unknown,
    dataQualityFlags: dataQualityFlags,
    modelVersion: 'test',
    rawComprehensiveScore: 0,
  );
}

class _BoundaryCase {
  final double score;
  final RecommendationLevel level;
  final RecommendationDirection direction;
  final String label;
  final bool actionable;

  const _BoundaryCase({
    required this.score,
    required this.level,
    required this.direction,
    required this.label,
    required this.actionable,
  });
}

class _ProbeCase {
  final double score;
  final RecommendationLevel level;
  final RecommendationDirection direction;
  final bool actionable;

  const _ProbeCase({
    required this.score,
    required this.level,
    required this.direction,
    required this.actionable,
  });
}

class _ExceptionalCase {
  final String name;
  final ShortTermDecision decision;
  final RecommendationLevel expectedLevel;

  const _ExceptionalCase({
    required this.name,
    required this.decision,
    required this.expectedLevel,
  });
}

class _GateCase {
  final String name;
  final double directionScore;
  final double tradeQualityScore;
  final double riskScore;
  final double evidenceConfidence;
  final RecommendationLevel expectedLevel;
  final bool expectedActionable;
  final List<String> expectedGates;

  const _GateCase({
    required this.name,
    required this.directionScore,
    required this.tradeQualityScore,
    required this.riskScore,
    required this.evidenceConfidence,
    required this.expectedLevel,
    required this.expectedActionable,
    this.expectedGates = const <String>[],
  });
}

class _BearishEvidenceCase {
  final String name;
  final double directionScore;
  final double evidenceConfidence;
  final RecommendationLevel expectedLevel;
  final bool expectedActionable;
  final List<String> expectedGates;

  const _BearishEvidenceCase({
    required this.name,
    required this.directionScore,
    required this.evidenceConfidence,
    required this.expectedLevel,
    required this.expectedActionable,
    this.expectedGates = const <String>[],
  });
}
