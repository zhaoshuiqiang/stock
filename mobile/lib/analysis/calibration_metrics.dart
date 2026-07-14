import 'dart:math' as math;

class ConfidenceInterval {
  final double lower;
  final double upper;

  const ConfidenceInterval(this.lower, this.upper);
}

class ProbabilityOutcome {
  final double probability;
  final bool outcome;

  const ProbabilityOutcome._({
    required this.probability,
    required this.outcome,
  });

  factory ProbabilityOutcome({
    required double probability,
    required bool outcome,
  }) {
    _validateProbability(probability, 'probability');
    return ProbabilityOutcome._(probability: probability, outcome: outcome);
  }
}

double betaBinomialPosterior({
  required int hits,
  required int sampleCount,
  required double globalBaseRate,
  int priorSampleSize = 20,
}) {
  _validateCounts(hits, sampleCount);
  _validateProbability(globalBaseRate, 'globalBaseRate');
  if (priorSampleSize < 0) {
    throw ArgumentError.value(priorSampleSize, 'priorSampleSize');
  }
  final denominator = sampleCount + priorSampleSize;
  if (denominator == 0) return globalBaseRate;
  return (hits + globalBaseRate * priorSampleSize) / denominator;
}

ConfidenceInterval wilsonInterval({
  required int hits,
  required int sampleCount,
  double z = 1.959963984540054,
}) {
  _validateCounts(hits, sampleCount);
  if (!z.isFinite || z <= 0) throw ArgumentError.value(z, 'z');
  if (sampleCount == 0) return const ConfidenceInterval(0, 1);
  final n = sampleCount.toDouble();
  final p = hits / n;
  final z2 = z * z;
  final denominator = 1 + z2 / n;
  final center = (p + z2 / (2 * n)) / denominator;
  final margin = z * math.sqrt((p * (1 - p) + z2 / (4 * n)) / n) / denominator;
  return ConfidenceInterval(
    hits == 0 ? 0 : math.max(0, center - margin),
    hits == sampleCount ? 1 : math.min(1, center + margin),
  );
}

double? brierScore(List<ProbabilityOutcome> samples) {
  if (samples.isEmpty) return null;
  var sum = 0.0;
  for (final sample in samples) {
    final error = sample.probability - (sample.outcome ? 1 : 0);
    sum += error * error;
  }
  return sum / samples.length;
}

double? expectedCalibrationError(
  List<ProbabilityOutcome> samples, {
  int bucketCount = 10,
}) {
  if (samples.isEmpty) return null;
  if (bucketCount <= 0) throw ArgumentError.value(bucketCount, 'bucketCount');
  final probabilitySums = List<double>.filled(bucketCount, 0);
  final outcomeSums = List<int>.filled(bucketCount, 0);
  final counts = List<int>.filled(bucketCount, 0);
  for (final sample in samples) {
    final index = math.min(
      bucketCount - 1,
      (sample.probability * bucketCount).floor(),
    );
    probabilitySums[index] += sample.probability;
    outcomeSums[index] += sample.outcome ? 1 : 0;
    counts[index]++;
  }
  var result = 0.0;
  for (var i = 0; i < bucketCount; i++) {
    if (counts[i] == 0) continue;
    final averageProbability = probabilitySums[i] / counts[i];
    final actualRate = outcomeSums[i] / counts[i];
    result +=
        (averageProbability - actualRate).abs() * counts[i] / samples.length;
  }
  return result;
}

void _validateCounts(int hits, int sampleCount) {
  if (sampleCount < 0 || hits < 0 || hits > sampleCount) {
    throw ArgumentError('hits must be between zero and sampleCount');
  }
}

void _validateProbability(double value, String name) {
  if (!value.isFinite || value < 0 || value > 1) {
    throw ArgumentError.value(value, name, 'must be between 0 and 1');
  }
}
