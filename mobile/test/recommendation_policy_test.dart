import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/legacy_decision_adapter.dart';
import 'package:stock_analyzer/analysis/recommendation_policy.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';

void main() {
  group('RecommendationPolicy boundaries', () {
    const cases = <_BoundaryCase>[
      _BoundaryCase(
        score: -55,
        level: RecommendationLevel.strongBearish,
        direction: RecommendationDirection.bearish,
        label: '强回避',
        legacyScore: 1,
        actionable: true,
      ),
      _BoundaryCase(
        score: -35,
        level: RecommendationLevel.bearish,
        direction: RecommendationDirection.bearish,
        label: '回避',
        legacyScore: 2,
        actionable: true,
      ),
      _BoundaryCase(
        score: -20,
        level: RecommendationLevel.cautiousBearish,
        direction: RecommendationDirection.bearish,
        label: '谨慎减仓',
        legacyScore: 3,
        actionable: true,
      ),
      _BoundaryCase(
        score: -12,
        level: RecommendationLevel.bearishWatch,
        direction: RecommendationDirection.bearish,
        label: '偏空观望',
        legacyScore: 4,
        actionable: false,
      ),
      _BoundaryCase(
        score: 0,
        level: RecommendationLevel.neutralWatch,
        direction: RecommendationDirection.neutral,
        label: '观望',
        legacyScore: 5,
        actionable: false,
      ),
      _BoundaryCase(
        score: 12,
        level: RecommendationLevel.bullishWatch,
        direction: RecommendationDirection.bullish,
        label: '偏多观望',
        legacyScore: 6,
        actionable: false,
      ),
      _BoundaryCase(
        score: 20,
        level: RecommendationLevel.cautiousBullish,
        direction: RecommendationDirection.bullish,
        label: '谨慎看多',
        legacyScore: 7,
        actionable: true,
      ),
      _BoundaryCase(
        score: 35,
        level: RecommendationLevel.bullish,
        direction: RecommendationDirection.bullish,
        label: '看多',
        legacyScore: 8,
        actionable: true,
      ),
      _BoundaryCase(
        score: 55,
        level: RecommendationLevel.strongBullish,
        direction: RecommendationDirection.bullish,
        label: '强看多',
        legacyScore: 9,
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
        expect(result.legacyScore, caseData.legacyScore);
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
      expect(result.legacyScore, 6);
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
      expect(result.legacyScore, 6);
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
      expect(result.legacyScore, 6);
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
      expect(result.label, '谨慎看多');
      expect(result.legacyScore, 7);
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
      expect(result.legacyScore, 4);
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
      expect(result.label, '回避');
      expect(result.legacyScore, 2);
      expect(result.actionable, isTrue);
      expect(result.gates, isEmpty);
    });
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
        expectedLegacyScore: 8,
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
        expectedLegacyScore: 9,
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
        expectedLegacyScore: 9,
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
        expectedLegacyScore: 9,
      ),
    ];

    for (final caseData in belowExceptionalCases) {
      test('${caseData.name} just outside the exceptional limit is not 10', () {
        final result = RecommendationPolicy.evaluate(caseData.decision);

        expect(result.level, caseData.expectedLevel);
        expect(result.direction, RecommendationDirection.bullish);
        expect(result.legacyScore, caseData.expectedLegacyScore);
        expect(result.legacyScore, isNot(10));
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
      expect(result.label, '强看多');
      expect(result.legacyScore, 10);
      expect(result.actionable, isTrue);
      expect(result.gates, isEmpty);
    });
  });

  group('LegacyDecisionAdapter', () {
    final source = RecommendationDecision(
      direction: RecommendationDirection.bearish,
      level: RecommendationLevel.strongBearish,
      label: '原始标签',
      legacyScore: 10,
      actionable: false,
      gates: const <String>['ignored_by_adapter'],
    );

    test('scoreOf returns the decision legacy score unchanged', () {
      expect(LegacyDecisionAdapter.scoreOf(source), source.legacyScore);
    });

    test('recommendationOf returns the decision label unchanged', () {
      expect(LegacyDecisionAdapter.recommendationOf(source), source.label);
    });
  });
}

ShortTermDecision _decision({
  required double directionScore,
  double tradeQualityScore = 70,
  double riskScore = 45,
  double evidenceConfidence = 65,
}) {
  return ShortTermDecision(
    directionScore: directionScore,
    tradeQualityScore: tradeQualityScore,
    riskScore: riskScore,
    evidenceConfidence: evidenceConfidence,
    direction: RecommendationDirection.neutral,
    marketRegime: MarketRegime.unknown,
    modelVersion: 'test',
    rawComprehensiveScore: 0,
  );
}

class _BoundaryCase {
  final double score;
  final RecommendationLevel level;
  final RecommendationDirection direction;
  final String label;
  final int legacyScore;
  final bool actionable;

  const _BoundaryCase({
    required this.score,
    required this.level,
    required this.direction,
    required this.label,
    required this.legacyScore,
    required this.actionable,
  });
}

class _ExceptionalCase {
  final String name;
  final ShortTermDecision decision;
  final RecommendationLevel expectedLevel;
  final int expectedLegacyScore;

  const _ExceptionalCase({
    required this.name,
    required this.decision,
    required this.expectedLevel,
    required this.expectedLegacyScore,
  });
}
