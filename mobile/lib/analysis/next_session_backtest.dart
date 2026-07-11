import '../models/stock_models.dart';
import 'next_session_prediction.dart';
import 'next_session_predictor.dart';

class NextSessionBacktest {
  static NextSessionBacktestResult run(
    List<HistoryKline> data, {
    int minTrainingBars = 30,
  }) {
    final evaluations = <NextSessionBacktestEvaluation>[];
    if (data.length < 3) {
      return NextSessionBacktestResult.empty();
    }

    final start = minTrainingBars.clamp(1, data.length - 2);
    for (var i = start; i < data.length - 1; i++) {
      final historySoFar = data.sublist(0, i + 1);
      final prediction = NextSessionPredictor.predict(historySoFar);
      final today = data[i];
      final next = data[i + 1];
      if (today.close <= 0) continue;

      evaluations.add(NextSessionBacktestEvaluation(
        index: i,
        prediction: prediction,
        nextOpenReturn: (next.open / today.close - 1) * 100,
        nextCloseReturn: (next.close / today.close - 1) * 100,
      ));
    }

    return NextSessionBacktestResult.fromEvaluations(evaluations);
  }
}

class NextSessionBacktestResult {
  final int totalPredictions;
  final double nextOpenDirectionAccuracy;
  final double nextCloseDirectionAccuracy;
  final double brierScore;
  final double averageNextCloseReturn;
  final List<CalibrationBucket> calibrationBuckets;
  final List<NextSessionBacktestEvaluation> evaluations;

  const NextSessionBacktestResult({
    required this.totalPredictions,
    required this.nextOpenDirectionAccuracy,
    required this.nextCloseDirectionAccuracy,
    required this.brierScore,
    required this.averageNextCloseReturn,
    required this.calibrationBuckets,
    required this.evaluations,
  });

  factory NextSessionBacktestResult.empty() {
    return const NextSessionBacktestResult(
      totalPredictions: 0,
      nextOpenDirectionAccuracy: 0,
      nextCloseDirectionAccuracy: 0,
      brierScore: 0,
      averageNextCloseReturn: 0,
      calibrationBuckets: [],
      evaluations: [],
    );
  }

  factory NextSessionBacktestResult.fromEvaluations(
    List<NextSessionBacktestEvaluation> evaluations,
  ) {
    if (evaluations.isEmpty) return NextSessionBacktestResult.empty();

    final openCorrect = evaluations.where((e) {
      return (e.prediction.nextOpenUpProbability >= 0.5) ==
          (e.nextOpenReturn > 0);
    }).length;
    final closeCorrect = evaluations.where((e) {
      return (e.prediction.nextCloseUpProbability >= 0.5) ==
          (e.nextCloseReturn > 0);
    }).length;
    final brier = evaluations.map((e) {
          final actual = e.nextCloseReturn > 0 ? 1.0 : 0.0;
          final error = e.prediction.nextCloseUpProbability - actual;
          return error * error;
        }).reduce((a, b) => a + b) /
        evaluations.length;
    final avgReturn =
        evaluations.map((e) => e.nextCloseReturn).reduce((a, b) => a + b) /
            evaluations.length;

    return NextSessionBacktestResult(
      totalPredictions: evaluations.length,
      nextOpenDirectionAccuracy: openCorrect / evaluations.length,
      nextCloseDirectionAccuracy: closeCorrect / evaluations.length,
      brierScore: brier,
      averageNextCloseReturn: avgReturn,
      calibrationBuckets: _buildCalibrationBuckets(evaluations),
      evaluations: evaluations,
    );
  }

  static List<CalibrationBucket> _buildCalibrationBuckets(
    List<NextSessionBacktestEvaluation> evaluations,
  ) {
    final buckets = <CalibrationBucket>[];
    for (var i = 0; i < 5; i++) {
      final lower = i / 5;
      final upper = (i + 1) / 5;
      final items = evaluations.where((evaluation) {
        final probability = evaluation.prediction.nextCloseUpProbability;
        if (i == 4) {
          return probability >= lower && probability <= upper;
        }
        return probability >= lower && probability < upper;
      }).toList();
      if (items.isEmpty) {
        buckets.add(CalibrationBucket(
          lowerBound: lower,
          upperBound: upper,
          count: 0,
          averagePredictedProbability: 0,
          actualUpRate: 0,
          averageNextCloseReturn: 0,
        ));
        continue;
      }

      buckets.add(CalibrationBucket(
        lowerBound: lower,
        upperBound: upper,
        count: items.length,
        averagePredictedProbability: items
                .map((e) => e.prediction.nextCloseUpProbability)
                .reduce((a, b) => a + b) /
            items.length,
        actualUpRate:
            items.where((e) => e.nextCloseReturn > 0).length / items.length,
        averageNextCloseReturn:
            items.map((e) => e.nextCloseReturn).reduce((a, b) => a + b) /
                items.length,
      ));
    }
    return buckets;
  }
}

class NextSessionBacktestEvaluation {
  final int index;
  final NextSessionPrediction prediction;
  final double nextOpenReturn;
  final double nextCloseReturn;

  const NextSessionBacktestEvaluation({
    required this.index,
    required this.prediction,
    required this.nextOpenReturn,
    required this.nextCloseReturn,
  });
}

class CalibrationBucket {
  final double lowerBound;
  final double upperBound;
  final int count;
  final double averagePredictedProbability;
  final double actualUpRate;
  final double averageNextCloseReturn;

  const CalibrationBucket({
    required this.lowerBound,
    required this.upperBound,
    required this.count,
    required this.averagePredictedProbability,
    required this.actualUpRate,
    required this.averageNextCloseReturn,
  });
}
