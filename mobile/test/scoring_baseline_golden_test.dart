import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/recommendation_policy.dart';
import 'package:stock_analyzer/models/short_term_decision.dart';

/// P0.2 characterization ("golden") test.
///
/// Locks the CURRENT live recommendation mapping (RecommendationPolicy) so any
/// future threshold/gate calibration (plan P2.2) is a deliberate, reviewed
/// change rather than an accidental drift. These values are derived directly
/// from recommendation_policy.dart:
///   - direction bands: +/-12 / +/-20 / +/-35 / +/-55
///   - legacyScore = (5 + directionScore/100*5).clamp(1,10) - 0.5 per failed gate
///   - exceptional strongBullish (q>=85,risk<=30,conf>=80,no gates) => 10.0
///   - gated bullish -> 偏多观望(6.0); gated bearish -> 偏空观望(4.0)
ShortTermDecision _decision({
  required double directionScore,
  double tradeQualityScore = 90,
  double riskScore = 10,
  double evidenceConfidence = 90,
}) {
  return ShortTermDecision(
    directionScore: directionScore,
    tradeQualityScore: tradeQualityScore,
    riskScore: riskScore,
    evidenceConfidence: evidenceConfidence,
    calibrationByHorizon: const <int, CalibrationEstimate>{},
    direction: RecommendationDirection.neutral,
    marketRegime: MarketRegime.range,
    directionComponents: const <String, double>{},
    qualityComponents: const <String, double>{},
    riskComponents: const <String, double>{},
    dataQualityFlags: const <String>[],
    modelVersion: 'short-term-v3',
    rawComprehensiveScore: 6.0,
  );
}

void main() {
  group('RecommendationPolicy golden mapping (gates passing)', () {
    void expectCase(
      double ds,
      String label,
      double legacyScore,
      bool actionable, {
      double quality = 90,
    }) {
      final r = RecommendationPolicy.evaluate(
          _decision(directionScore: ds, tradeQualityScore: quality));
      expect(r.label, label, reason: 'label @ ds=$ds');
      expect(r.legacyScore, closeTo(legacyScore, 1e-9),
          reason: 'legacyScore @ ds=$ds');
      expect(r.actionable, actionable, reason: 'actionable @ ds=$ds');
    }

    test('strong bullish, non-exceptional quality', () {
      // q=75 passes strongBullish gate (>=70) but is below exceptional (85).
      expectCase(60, '强烈买入', 8.0, true, quality: 75);
    });
    test('strong bullish, exceptional -> capped legacyScore 10', () {
      expectCase(70, '强烈买入', 10.0, true);
    });
    test('bullish', () => expectCase(40, '买入', 7.0, true));
    test('cautious bullish', () => expectCase(25, '谨慎买入', 6.25, true));
    test('bullish watch (not actionable)',
        () => expectCase(15, '偏多观望', 5.75, false));
    test('neutral watch', () => expectCase(0, '观望', 5.0, false));
    test('bearish', () {
      final r = RecommendationPolicy.evaluate(_decision(
          directionScore: -40, tradeQualityScore: 50, riskScore: 50));
      expect(r.label, '卖出');
      expect(r.legacyScore, closeTo(3.0, 1e-9));
      expect(r.actionable, isTrue);
    });
    test('strong bearish', () {
      final r = RecommendationPolicy.evaluate(_decision(directionScore: -70));
      expect(r.label, '强烈卖出');
      expect(r.legacyScore, closeTo(1.5, 1e-9));
      expect(r.actionable, isTrue);
    });
  });

  group('RecommendationPolicy golden mapping (gates failing)', () {
    test('bullish level with low trade quality is demoted to 偏多观望', () {
      final r = RecommendationPolicy.evaluate(
          _decision(directionScore: 70, tradeQualityScore: 50));
      expect(r.label, '偏多观望');
      expect(r.legacyScore, 6.0);
      expect(r.actionable, isFalse);
      expect(r.gates, isNotEmpty);
    });

    test('bearish level with low confidence is demoted to 偏空观望', () {
      final r = RecommendationPolicy.evaluate(
          _decision(directionScore: -40, evidenceConfidence: 40));
      expect(r.label, '偏空观望');
      expect(r.legacyScore, 4.0);
      expect(r.actionable, isFalse);
      expect(r.gates, isNotEmpty);
    });
  });
}
