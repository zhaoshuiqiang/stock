import 'package:flutter_test/flutter_test.dart';
import 'package:stock_analyzer/analysis/calibration_metrics.dart';

void main() {
  test('beta-binomial posterior uses configured prior sample size', () {
    expect(
      betaBinomialPosterior(
        hits: 70,
        sampleCount: 100,
        globalBaseRate: 0.6,
      ),
      closeTo(82 / 120, 1e-12),
    );
  });

  test('wilson interval handles zero half and full hit counts', () {
    final zero = wilsonInterval(hits: 0, sampleCount: 100);
    final half = wilsonInterval(hits: 50, sampleCount: 100);
    final full = wilsonInterval(hits: 100, sampleCount: 100);
    expect(zero.lower, 0);
    expect(zero.upper, closeTo(0.03699, 0.0001));
    expect(half.lower, closeTo(0.4038, 0.0002));
    expect(half.upper, closeTo(0.5962, 0.0002));
    expect(full.lower, closeTo(0.9630, 0.0001));
    expect(full.upper, 1);
  });

  test('brier score covers perfect wrong mixed and empty inputs', () {
    expect(brierScore(const []), isNull);
    expect(
      brierScore([
        ProbabilityOutcome(probability: 1, outcome: true),
        ProbabilityOutcome(probability: 0, outcome: false),
      ]),
      0,
    );
    expect(
      brierScore([
        ProbabilityOutcome(probability: 0, outcome: true),
        ProbabilityOutcome(probability: 1, outcome: false),
      ]),
      1,
    );
  });

  test('ECE is population weighted and probability one uses last bucket', () {
    final samples = [
      ProbabilityOutcome(probability: 0.1, outcome: false),
      ProbabilityOutcome(probability: 0.2, outcome: true),
      ProbabilityOutcome(probability: 1.0, outcome: true),
    ];
    expect(expectedCalibrationError(samples, bucketCount: 10),
        closeTo((0.1 + 0.8) / 3, 1e-12));
    expect(expectedCalibrationError(const []), isNull);
  });

  test('invalid probability and counts are rejected', () {
    expect(
      () => ProbabilityOutcome(probability: 1.1, outcome: true),
      throwsArgumentError,
    );
    expect(
      () => betaBinomialPosterior(
        hits: 2,
        sampleCount: 1,
        globalBaseRate: 0.5,
      ),
      throwsArgumentError,
    );
  });
}
