import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';
import 'package:stock_analyzer/models/stock_models.dart';

void main() {
  group('ShortTermDecision', () {
    test('round-trips all decision fields and horizon calibration', () {
      final original = _sampleDecision();

      final json = original.toJson();
      final restored = ShortTermDecision.fromJson(json);

      expect(json['evidence_confidence'], 82.5);
      expect(json['evidence_confidence'], isA<double>());
      expect(
        (json['calibration_by_horizon'] as Map<String, dynamic>)['3'],
        isA<Map<String, dynamic>>(),
      );
      expect(restored.directionScore, 48.0);
      expect(restored.tradeQualityScore, 71.0);
      expect(restored.riskScore, 34.0);
      expect(restored.evidenceConfidence, 82.5);
      expect(restored.direction, RecommendationDirection.bullish);
      expect(restored.marketRegime, MarketRegime.bullishTrend);
      expect(restored.calibrationByHorizon.keys, containsAll(<int>[1, 3, 5]));
      expect(restored.calibrationByHorizon[3]!.probability, 0.64);
      expect(restored.calibrationByHorizon[3]!.sampleCount, 180);
      expect(restored.calibrationByHorizon[3]!.wilsonLower, 0.57);
      expect(restored.calibrationByHorizon[3]!.wilsonUpper, 0.70);
      expect(restored.primaryStrategyId, 'momentum_breakout');
      expect(restored.primaryStrategyName, 'Momentum breakout');
      expect(
        restored.supportingStrategyIds,
        <String>['volume_confirmation', 'trend_alignment'],
      );
      expect(restored.dataQualityFlags, <String>['stale_fundamentals']);
      expect(restored.directionComponents, <String, double>{
        'technical': 42.0,
        'capitalFlow': 6.0,
      });
      expect(restored.qualityComponents, <String, double>{
        'confluence': 45.0,
        'structure': 26.0,
      });
      expect(restored.riskComponents, <String, double>{
        'volatility': 20.0,
        'liquidity': 14.0,
      });
      expect(restored.modelVersion, 'short-term-v2');
      expect(restored.rawComprehensiveScore, 7.4);
    });

    test('keeps evidence confidence on the 0 to 100 scale', () {
      final restored = ShortTermDecision.fromJson(
        _sampleDecision().toJson(),
      );

      expect(restored.evidenceConfidence, 82.5);
      expect(restored.calibrationByHorizon[1]!.probability, 0.58);
      expect(restored.evidenceConfidence, isNot(0.825));
    });

    test('falls back for unknown enums and defaults missing collections', () {
      final decision = ShortTermDecision.fromJson(<String, dynamic>{
        'direction_score': 0,
        'trade_quality_score': 50,
        'risk_score': 50,
        'evidence_confidence': 40,
        'direction': 'not_a_direction',
        'market_regime': 'not_a_regime',
        'model_version': 'future-version',
        'raw_comprehensive_score': 5,
      });

      expect(decision.direction, RecommendationDirection.neutral);
      expect(decision.marketRegime, MarketRegime.unknown);
      expect(decision.calibrationByHorizon, isEmpty);
      expect(decision.directionComponents, isEmpty);
      expect(decision.qualityComponents, isEmpty);
      expect(decision.riskComponents, isEmpty);
      expect(decision.supportingStrategyIds, isEmpty);
      expect(decision.dataQualityFlags, isEmpty);
    });

    test('copyWith preserves the original and immutable collections', () {
      final sourceStrategies = <String>['volume_confirmation'];
      final original = _sampleDecision(
        supportingStrategyIds: sourceStrategies,
      );
      sourceStrategies.add('late_mutation');

      final copied = original.copyWith(
        directionScore: -21.0,
        direction: RecommendationDirection.bearish,
        supportingStrategyIds: <String>['defensive_reversal'],
      );

      expect(original.directionScore, 48.0);
      expect(original.direction, RecommendationDirection.bullish);
      expect(original.supportingStrategyIds, <String>['volume_confirmation']);
      expect(copied.directionScore, -21.0);
      expect(copied.direction, RecommendationDirection.bearish);
      expect(copied.supportingStrategyIds, <String>['defensive_reversal']);
      expect(copied.tradeQualityScore, original.tradeQualityScore);
      expect(
        () => copied.supportingStrategyIds.add('mutation'),
        throwsUnsupportedError,
      );
      expect(
        () => copied.directionComponents['mutation'] = 1.0,
        throwsUnsupportedError,
      );
      expect(
        () => copied.calibrationByHorizon[1] = CalibrationEstimate(
          horizon: 1,
          probability: 0.5,
          sampleCount: 1,
          wilsonLower: 0.1,
          wilsonUpper: 0.9,
        ),
        throwsUnsupportedError,
      );
    });

    test('rejects invalid decision score ranges with ArgumentError', () {
      final invalidBuilders = <ShortTermDecision Function()>[
        () => _sampleDecision(directionScore: -100.1),
        () => _sampleDecision(directionScore: 100.1),
        () => _sampleDecision(tradeQualityScore: -0.1),
        () => _sampleDecision(tradeQualityScore: 100.1),
        () => _sampleDecision(riskScore: -0.1),
        () => _sampleDecision(riskScore: 100.1),
        () => _sampleDecision(evidenceConfidence: -0.1),
        () => _sampleDecision(evidenceConfidence: 100.1),
      ];

      for (final build in invalidBuilders) {
        expect(build, throwsArgumentError);
      }
    });
  });

  group('CalibrationEstimate', () {
    test('rejects unsupported horizons and invalid ranges', () {
      final invalidBuilders = <CalibrationEstimate Function()>[
        () => CalibrationEstimate(
              horizon: 2,
              probability: 0.5,
              sampleCount: 10,
              wilsonLower: 0.4,
              wilsonUpper: 0.6,
            ),
        () => CalibrationEstimate(
              horizon: 1,
              probability: -0.01,
              sampleCount: 10,
              wilsonLower: 0.4,
              wilsonUpper: 0.6,
            ),
        () => CalibrationEstimate(
              horizon: 3,
              probability: 1.01,
              sampleCount: 10,
              wilsonLower: 0.4,
              wilsonUpper: 0.6,
            ),
        () => CalibrationEstimate(
              horizon: 5,
              probability: 0.5,
              sampleCount: -1,
              wilsonLower: 0.4,
              wilsonUpper: 0.6,
            ),
        () => CalibrationEstimate(
              horizon: 1,
              probability: 0.5,
              sampleCount: 10,
              wilsonLower: -0.01,
              wilsonUpper: 0.6,
            ),
        () => CalibrationEstimate(
              horizon: 3,
              probability: 0.5,
              sampleCount: 10,
              wilsonLower: 0.4,
              wilsonUpper: 1.01,
            ),
      ];

      for (final build in invalidBuilders) {
        expect(build, throwsArgumentError);
      }
    });
  });

  group('RecommendationDecision', () {
    test('round-trips fields and keeps gates immutable', () {
      final original = RecommendationDecision(
        direction: RecommendationDirection.bullish,
        level: RecommendationLevel.cautiousBullish,
        label: 'Cautious buy',
        legacyScore: 7,
        actionable: true,
        gates: <String>['liquidity_ok', 'risk_within_limit'],
      );

      final restored = RecommendationDecision.fromJson(original.toJson());

      expect(restored.direction, RecommendationDirection.bullish);
      expect(restored.level, RecommendationLevel.cautiousBullish);
      expect(restored.label, 'Cautious buy');
      expect(restored.legacyScore, 7);
      expect(restored.actionable, isTrue);
      expect(restored.gates, <String>['liquidity_ok', 'risk_within_limit']);
      expect(() => restored.gates.add('mutation'), throwsUnsupportedError);
    });

    test('uses neutral fallbacks and validates legacy score', () {
      final restored = RecommendationDecision.fromJson(<String, dynamic>{
        'direction': 'future_direction',
        'level': 'future_level',
        'label': 'Watch',
        'legacy_score': 5,
        'actionable': false,
      });

      expect(restored.direction, RecommendationDirection.neutral);
      expect(restored.level, RecommendationLevel.neutralWatch);
      expect(restored.gates, isEmpty);
      expect(
        () => RecommendationDecision(
          direction: RecommendationDirection.neutral,
          level: RecommendationLevel.neutralWatch,
          label: 'Invalid',
          legacyScore: 0,
          actionable: false,
          gates: const <String>[],
        ),
        throwsArgumentError,
      );
      expect(
        () => RecommendationDecision(
          direction: RecommendationDirection.neutral,
          level: RecommendationLevel.neutralWatch,
          label: 'Invalid',
          legacyScore: 11,
          actionable: false,
          gates: const <String>[],
        ),
        throwsArgumentError,
      );
    });
  });

  group('AnalysisResult short-term decision', () {
    test('legacy JSON remains compatible without a decision', () {
      final result = AnalysisResult.fromJson(<String, dynamic>{
        'score': 6,
        'recommendation': 'Watch',
      });

      expect(result.shortTermDecision, isNull);
    });

    test('JSON and copyWith retain or replace the decision', () {
      final decision = _sampleDecision();
      final original = AnalysisResult(
        score: 7,
        shortTermDecision: decision,
      );

      final restored = AnalysisResult.fromJson(original.toJson());
      final preserved = original.copyWith(score: 8);
      final replacement = decision.copyWith(directionScore: -12.0);
      final replaced = original.copyWith(shortTermDecision: replacement);

      expect(original.toJson()['short_term_decision'], decision.toJson());
      expect(restored.shortTermDecision, isNotNull);
      expect(restored.shortTermDecision!.directionScore, 48.0);
      expect(restored.shortTermDecision!.calibrationByHorizon[5]!.horizon, 5);
      expect(preserved.shortTermDecision, same(decision));
      expect(replaced.shortTermDecision, same(replacement));
      expect(original.shortTermDecision, same(decision));
    });
  });
}

ShortTermDecision _sampleDecision({
  double directionScore = 48.0,
  double tradeQualityScore = 71.0,
  double riskScore = 34.0,
  double evidenceConfidence = 82.5,
  List<String>? supportingStrategyIds,
}) {
  return ShortTermDecision(
    directionScore: directionScore,
    tradeQualityScore: tradeQualityScore,
    riskScore: riskScore,
    evidenceConfidence: evidenceConfidence,
    calibrationByHorizon: <int, CalibrationEstimate>{
      1: CalibrationEstimate(
        horizon: 1,
        probability: 0.58,
        sampleCount: 240,
        wilsonLower: 0.52,
        wilsonUpper: 0.64,
      ),
      3: CalibrationEstimate(
        horizon: 3,
        probability: 0.64,
        sampleCount: 180,
        wilsonLower: 0.57,
        wilsonUpper: 0.70,
      ),
      5: CalibrationEstimate(
        horizon: 5,
        probability: 0.67,
        sampleCount: 120,
        wilsonLower: 0.58,
        wilsonUpper: 0.75,
      ),
    },
    direction: RecommendationDirection.bullish,
    marketRegime: MarketRegime.bullishTrend,
    directionComponents: <String, double>{
      'technical': 42.0,
      'capitalFlow': 6.0,
    },
    qualityComponents: <String, double>{
      'confluence': 45.0,
      'structure': 26.0,
    },
    riskComponents: <String, double>{
      'volatility': 20.0,
      'liquidity': 14.0,
    },
    primaryStrategyId: 'momentum_breakout',
    primaryStrategyName: 'Momentum breakout',
    supportingStrategyIds: supportingStrategyIds ??
        <String>['volume_confirmation', 'trend_alignment'],
    dataQualityFlags: <String>['stale_fundamentals'],
    modelVersion: 'short-term-v2',
    rawComprehensiveScore: 7.4,
  );
}
