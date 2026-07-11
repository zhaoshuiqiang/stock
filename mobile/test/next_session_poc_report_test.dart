import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/next_session_backtest.dart';
import 'package:stock_analyzer/analysis/next_session_poc_report.dart';
import 'package:stock_analyzer/analysis/next_session_prediction.dart';

void main() {
  group('NextSessionPocReport', () {
    test('fails production gate when high-confidence bucket is weak', () {
      final result = NextSessionBacktestResult(
        totalPredictions: 20,
        nextOpenDirectionAccuracy: 0.5,
        nextCloseDirectionAccuracy: 0.52,
        brierScore: 0.25,
        averageNextCloseReturn: -0.1,
        calibrationBuckets: const [
          CalibrationBucket(
            lowerBound: 0.6,
            upperBound: 0.8,
            count: 10,
            averagePredictedProbability: 0.68,
            actualUpRate: 0.51,
            averageNextCloseReturn: -0.05,
          ),
        ],
        evaluations: const [],
      );

      final report = NextSessionPocReport.evaluate(
        result,
        baselineNextCloseHitRate: 0.5,
      );

      expect(report.productionReady, isFalse);
      expect(report.failedCriteria, isNotEmpty);
      expect(report.toMarkdown(), contains('不建议接入推荐升级'));
    });

    test('passes production gate when criteria are met', () {
      final result = NextSessionBacktestResult(
        totalPredictions: 100,
        nextOpenDirectionAccuracy: 0.58,
        nextCloseDirectionAccuracy: 0.61,
        brierScore: 0.21,
        averageNextCloseReturn: 0.2,
        calibrationBuckets: const [
          CalibrationBucket(
            lowerBound: 0.4,
            upperBound: 0.6,
            count: 20,
            averagePredictedProbability: 0.52,
            actualUpRate: 0.52,
            averageNextCloseReturn: 0.02,
          ),
          CalibrationBucket(
            lowerBound: 0.6,
            upperBound: 0.8,
            count: 30,
            averagePredictedProbability: 0.68,
            actualUpRate: 0.58,
            averageNextCloseReturn: 0.35,
          ),
          CalibrationBucket(
            lowerBound: 0.8,
            upperBound: 1.0,
            count: 12,
            averagePredictedProbability: 0.84,
            actualUpRate: 0.72,
            averageNextCloseReturn: 0.5,
          ),
        ],
        evaluations: [
          _evaluation(probability: 0.82, nextCloseReturn: 0.6),
          _evaluation(probability: 0.78, nextCloseReturn: 0.3),
          _evaluation(probability: 0.35, nextCloseReturn: -0.4),
        ],
      );

      final report = NextSessionPocReport.evaluate(
        result,
        baselineNextCloseHitRate: 0.5,
      );

      expect(report.productionReady, isTrue);
      expect(report.failedCriteria, isEmpty);
      expect(report.toMarkdown(), contains('可以接入推荐门控'));
    });
  });
}

NextSessionBacktestEvaluation _evaluation({
  required double probability,
  required double nextCloseReturn,
}) {
  return NextSessionBacktestEvaluation(
    index: 0,
    prediction: NextSessionPrediction(
      nextOpenUpProbability: probability,
      nextCloseUpProbability: probability,
      expectedNextCloseReturn: nextCloseReturn,
      downsideRiskProbability: 1 - probability,
      confidence: 0.7,
      sampleCount: 20,
      scenarioTags: const [],
      riskWarnings: const [],
    ),
    nextOpenReturn: nextCloseReturn,
    nextCloseReturn: nextCloseReturn,
  );
}
