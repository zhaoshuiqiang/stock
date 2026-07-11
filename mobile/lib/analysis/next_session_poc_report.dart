import 'next_session_backtest.dart';

class NextSessionPocReport {
  final NextSessionBacktestResult backtest;
  final bool productionReady;
  final List<String> passedCriteria;
  final List<String> failedCriteria;

  const NextSessionPocReport({
    required this.backtest,
    required this.productionReady,
    required this.passedCriteria,
    required this.failedCriteria,
  });

  factory NextSessionPocReport.evaluate(
    NextSessionBacktestResult backtest, {
    double baselineNextCloseHitRate = 0.5,
    double transactionCostPct = 0.2,
  }) {
    final passed = <String>[];
    final failed = <String>[];
    final highConfidenceBuckets = backtest.calibrationBuckets
        .where((b) => b.count > 0 && b.averagePredictedProbability >= 0.6)
        .toList();

    final highCount =
        highConfidenceBuckets.fold<int>(0, (sum, b) => sum + b.count);
    final weightedHitRate = highCount == 0
        ? 0.0
        : highConfidenceBuckets.fold<double>(
              0,
              (sum, b) => sum + b.actualUpRate * b.count,
            ) /
            highCount;
    final weightedReturn = highCount == 0
        ? 0.0
        : highConfidenceBuckets.fold<double>(
              0,
              (sum, b) => sum + b.averageNextCloseReturn * b.count,
            ) /
            highCount;

    final hitRateEdge = weightedHitRate - baselineNextCloseHitRate;
    if (hitRateEdge >= 0.05) {
      passed.add('高置信多头桶胜率较基线提升不少于5个百分点');
    } else {
      failed.add('高置信多头桶胜率未较基线提升5个百分点');
    }

    if (weightedReturn > transactionCostPct) {
      passed.add('高置信多头桶扣除成本后仍为正收益');
    } else {
      failed.add('高置信多头桶平均收益未覆盖交易成本');
    }

    if (_isMonotonic(backtest.calibrationBuckets)) {
      passed.add('概率分桶实际上涨率保持方向性单调');
    } else {
      failed.add('概率分桶实际上涨率不单调');
    }

    if (_highRiskBucketIsWorse(backtest)) {
      passed.add('高风险桶收益弱于中性桶');
    } else {
      failed.add('高风险桶未明显弱于中性桶');
    }

    return NextSessionPocReport(
      backtest: backtest,
      productionReady: failed.isEmpty,
      passedCriteria: passed,
      failedCriteria: failed,
    );
  }

  String toMarkdown() {
    final buffer = StringBuffer()
      ..writeln('# Next Session Prediction POC Report')
      ..writeln()
      ..writeln('## Summary')
      ..writeln()
      ..writeln('- Samples: ${backtest.totalPredictions}')
      ..writeln(
          '- Next open accuracy: ${(backtest.nextOpenDirectionAccuracy * 100).toStringAsFixed(1)}%')
      ..writeln(
          '- Next close accuracy: ${(backtest.nextCloseDirectionAccuracy * 100).toStringAsFixed(1)}%')
      ..writeln('- Brier score: ${backtest.brierScore.toStringAsFixed(4)}')
      ..writeln(
          '- Avg next-close return: ${backtest.averageNextCloseReturn.toStringAsFixed(3)}%')
      ..writeln()
      ..writeln('## Gate Result')
      ..writeln()
      ..writeln(productionReady
          ? '可以接入推荐门控，但仍不得把概率当作确定性结论。'
          : '不建议接入推荐升级；只能作为风险提示或降级门控。')
      ..writeln()
      ..writeln('## Passed Criteria')
      ..writeln();

    for (final item in passedCriteria) {
      buffer.writeln('- $item');
    }
    if (passedCriteria.isEmpty) buffer.writeln('- None');

    buffer
      ..writeln()
      ..writeln('## Failed Criteria')
      ..writeln();
    for (final item in failedCriteria) {
      buffer.writeln('- $item');
    }
    if (failedCriteria.isEmpty) buffer.writeln('- None');

    buffer
      ..writeln()
      ..writeln('## Calibration Buckets')
      ..writeln()
      ..writeln('| Bucket | Count | Predicted | Actual Up | Avg Return |')
      ..writeln('| --- | ---: | ---: | ---: | ---: |');
    for (final bucket in backtest.calibrationBuckets) {
      buffer.writeln(
        '| ${bucket.lowerBound.toStringAsFixed(1)}-${bucket.upperBound.toStringAsFixed(1)} '
        '| ${bucket.count} '
        '| ${(bucket.averagePredictedProbability * 100).toStringAsFixed(1)}% '
        '| ${(bucket.actualUpRate * 100).toStringAsFixed(1)}% '
        '| ${bucket.averageNextCloseReturn.toStringAsFixed(3)}% |',
      );
    }
    return buffer.toString();
  }

  static bool _isMonotonic(List<CalibrationBucket> buckets) {
    final active = buckets.where((b) => b.count > 0).toList();
    for (var i = 1; i < active.length; i++) {
      if (active[i].actualUpRate + 0.001 < active[i - 1].actualUpRate) {
        return false;
      }
    }
    return active.length >= 2;
  }

  static bool _highRiskBucketIsWorse(NextSessionBacktestResult backtest) {
    final low = backtest.calibrationBuckets
        .where((b) => b.count > 0 && b.upperBound <= 0.4)
        .toList();
    final neutral = backtest.calibrationBuckets
        .where((b) => b.count > 0 && b.lowerBound >= 0.4 && b.upperBound <= 0.6)
        .toList();
    if (low.isEmpty || neutral.isEmpty) {
      return backtest.evaluations.any((e) =>
          e.prediction.downsideRiskProbability >= 0.55 &&
          e.nextCloseReturn < backtest.averageNextCloseReturn);
    }
    final lowReturn = low.fold<double>(
          0,
          (sum, b) => sum + b.averageNextCloseReturn * b.count,
        ) /
        low.fold<int>(0, (sum, b) => sum + b.count);
    final neutralReturn = neutral.fold<double>(
          0,
          (sum, b) => sum + b.averageNextCloseReturn * b.count,
        ) /
        neutral.fold<int>(0, (sum, b) => sum + b.count);
    return lowReturn < neutralReturn;
  }
}
