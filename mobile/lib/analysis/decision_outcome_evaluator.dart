import '../models/short_term_decision.dart';
import '../models/stock_models.dart';
import 'decision_market_data_provider.dart';

class DecisionOutcomeEvaluator {
  static DecisionOutcomeRecord evaluate({
    required DecisionSnapshotRecord snapshot,
    required DecisionOutcomeRecord outcome,
    required DecisionMarketData data,
    DateTime? now,
  }) {
    final evaluationTime = now ?? DateTime.now();
    final benchmark = _normalized(data.adjustedBenchmark);
    final stock = _normalized(data.adjustedStock);
    final evidenceDate = snapshot.evidenceTradeDate ?? snapshot.signalTradeDate;
    final evidenceIndex = benchmark.indexWhere(
      (bar) => _sameDate(bar.date, evidenceDate),
    );
    // evidenceTradeDate 不在基准序列（如节假日/数据缺口）→ 永远无法匹配，
    // 直接置 invalid，避免 refreshPending 每周期空转占用 limit 槽位。
    // （已通过 [TradingDateUtils] 在写入时归一化周末，此处为双保险。）
    if (evidenceIndex < 0) {
      return _invalid(
        outcome,
        'evidence date not in benchmark series',
        now: evaluationTime,
      );
    }
    if (snapshot.modelVersion == 'short-term-v3' &&
        snapshot.signalPhase == DecisionSignalPhase.preMarket) {
      if (!_date(evidenceDate).isBefore(_date(snapshot.signalTradeDate))) {
        return _invalid(
          outcome,
          'premarket evidence date is stale',
          now: evaluationTime,
        );
      }
      if (evidenceIndex + 1 >= benchmark.length) {
        return _pending(outcome);
      }
      if (!_sameDate(
        benchmark[evidenceIndex + 1].date,
        snapshot.signalTradeDate,
      )) {
        return _invalid(
          outcome,
          'premarket evidence date is stale',
          now: evaluationTime,
        );
      }
    }
    if (evidenceIndex + outcome.horizon >= benchmark.length) {
      return _pending(outcome);
    }
    final benchmarkSignal = benchmark[evidenceIndex];
    final benchmarkTarget = benchmark[evidenceIndex + outcome.horizon];
    final dueDate = benchmarkTarget.date;
    if (!_isMatured(dueDate, evaluationTime)) {
      return _pending(outcome, dueTradeDate: dueDate);
    }
    final targetIndex = stock.indexWhere(
      (bar) => !bar.date.isBefore(_date(dueDate)),
    );
    if (targetIndex < 0) return _pending(outcome, dueTradeDate: dueDate);

    final signalAdjusted =
        _barOn(stock, evidenceDate)?.close ?? snapshot.adjustedSignalPrice;
    if (signalAdjusted == null ||
        !signalAdjusted.isFinite ||
        signalAdjusted <= 0) {
      return _invalid(
        outcome,
        'adjusted evidence price unavailable',
        now: evaluationTime,
      );
    }
    final target = stock[targetIndex];
    if (!_isMatured(target.date, evaluationTime)) {
      return _pending(outcome, dueTradeDate: dueDate);
    }
    final actualBenchmarkTarget = _barOn(benchmark, target.date);
    if (actualBenchmarkTarget == null) {
      return _pending(outcome, dueTradeDate: dueDate);
    }
    final entry = stock.cast<HistoryKline?>().firstWhere(
          (bar) => snapshot.signalPhase == DecisionSignalPhase.preMarket
              ? !bar!.date.isBefore(_date(snapshot.signalTradeDate))
              : bar!.date.isAfter(_date(evidenceDate)),
          orElse: () => null,
        );
    final forecastReturn = (target.close / signalAdjusted - 1) * 100;
    final benchmarkReturn =
        (actualBenchmarkTarget.close / benchmarkSignal.close - 1) * 100;
    final alphaReturn = forecastReturn - benchmarkReturn;
    final orientation = snapshot.direction == RecommendationDirection.bearish
        ? -1.0
        : snapshot.direction == RecommendationDirection.bullish
            ? 1.0
            : 0.0;
    final bool? rawHit =
        orientation == 0 ? null : forecastReturn * orientation > 0;
    final bool? effectiveHit =
        orientation == 0 ? null : forecastReturn * orientation >= 0.5;
    final bool? alphaHit =
        orientation == 0 ? null : alphaReturn * orientation > 0;
    final executableValid =
        entry != null && entry.open > 0 && !_isOnePriceLimit(entry);
    final path = executableValid && orientation != 0
        ? stock
            .where((bar) =>
                !bar.date.isBefore(_date(entry.date)) &&
                !bar.date.isAfter(_date(target.date)))
            .toList()
        : const <HistoryKline>[];
    final orientedReturns = path
        .expand((bar) => [
              (bar.high / entry!.open - 1) * 100 * orientation,
              (bar.low / entry.open - 1) * 100 * orientation,
            ])
        .toList();
    final executableReturn =
        executableValid ? (target.close / entry.open - 1) * 100 : null;
    final rawTarget = data.rawStock == null
        ? null
        : _barOnOrAfter(data.rawStock!, target.date);
    final rawSignal =
        data.rawStock == null ? null : _barOn(data.rawStock!, evidenceDate);
    final rawReturn = rawTarget == null || rawSignal == null
        ? null
        : (rawTarget.close / rawSignal.close - 1) * 100;

    return DecisionOutcomeRecord(
      id: outcome.id,
      snapshotId: outcome.snapshotId,
      horizon: outcome.horizon,
      status: DecisionOutcomeStatus.evaluated,
      dueTradeDate: dueDate,
      entryTradeDate: entry?.date,
      targetTradeDate: target.date,
      deferredTradeDays: benchmark
          .where((bar) =>
              bar.date.isAfter(_date(dueDate)) &&
              !bar.date.isAfter(_date(target.date)))
          .length,
      evaluatedAt: evaluationTime,
      adjustedSignalPriceUsed: signalAdjusted,
      entryOpenPrice: entry?.open,
      targetClosePrice: rawTarget?.close ?? target.close,
      adjustedTargetClosePrice: target.close,
      benchmarkSignalClose: benchmarkSignal.close,
      benchmarkTargetClose: actualBenchmarkTarget.close,
      forecastReturn: forecastReturn,
      executableReturn: executableReturn,
      benchmarkReturn: benchmarkReturn,
      alphaReturn: alphaReturn,
      mfe: orientedReturns.isEmpty
          ? null
          : orientedReturns.reduce((a, b) => a > b ? a : b),
      mae: orientedReturns.isEmpty
          ? null
          : orientedReturns.reduce((a, b) => a < b ? a : b),
      rawDirectionHit: rawHit,
      effectiveDirectionHit: effectiveHit,
      alphaHit: alphaHit,
      corporateActionDetected:
          rawReturn == null ? null : (forecastReturn - rawReturn).abs() > 0.5,
      executableValid: executableValid,
      executableInvalidReason:
          executableValid ? '' : 'one-price limit or missing entry',
      attemptCount: outcome.attemptCount + 1,
      lastAttemptedAt: evaluationTime,
      predictedProbability: outcome.predictedProbability,
      predictedSampleCount: outcome.predictedSampleCount,
      predictedWilsonLower: outcome.predictedWilsonLower,
      predictedWilsonUpper: outcome.predictedWilsonUpper,
      predictionCreatedAt: outcome.predictionCreatedAt,
    );
  }

  static List<HistoryKline> _normalized(List<HistoryKline> bars) {
    final values = <String, HistoryKline>{};
    for (final bar in bars) {
      values['${bar.date.year}-${bar.date.month}-${bar.date.day}'] = bar;
    }
    return values.values.toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  static DateTime _date(DateTime value) =>
      DateTime(value.year, value.month, value.day);
  static bool _sameDate(DateTime a, DateTime b) => _date(a) == _date(b);
  static HistoryKline? _barOn(List<HistoryKline> bars, DateTime date) =>
      bars.cast<HistoryKline?>().firstWhere(
            (bar) => _sameDate(bar!.date, date),
            orElse: () => null,
          );
  static HistoryKline? _barOnOrAfter(List<HistoryKline> bars, DateTime date) =>
      _normalized(bars).cast<HistoryKline?>().firstWhere(
            (bar) => !bar!.date.isBefore(_date(date)),
            orElse: () => null,
          );
  static bool _isOnePriceLimit(HistoryKline bar) =>
      bar.high == bar.low &&
      bar.open == bar.close &&
      bar.changePct.abs() >= 9.5;

  static bool _isMatured(DateTime due, DateTime current) {
    final dueDate = _date(due);
    final currentDate = _date(current);
    if (dueDate.isBefore(currentDate)) return true;
    if (dueDate.isAfter(currentDate)) return false;
    return current.hour * 60 + current.minute >= 15 * 60;
  }

  static DecisionOutcomeRecord _pending(DecisionOutcomeRecord value,
          {DateTime? dueTradeDate}) =>
      DecisionOutcomeRecord(
        id: value.id,
        snapshotId: value.snapshotId,
        horizon: value.horizon,
        dueTradeDate: dueTradeDate,
        attemptCount: value.attemptCount,
        predictedProbability: value.predictedProbability,
        predictedSampleCount: value.predictedSampleCount,
        predictedWilsonLower: value.predictedWilsonLower,
        predictedWilsonUpper: value.predictedWilsonUpper,
        predictionCreatedAt: value.predictionCreatedAt,
      );

  static DecisionOutcomeRecord _invalid(
          DecisionOutcomeRecord value, String reason,
          {DateTime? now}) =>
      DecisionOutcomeRecord(
        id: value.id,
        snapshotId: value.snapshotId,
        horizon: value.horizon,
        status: DecisionOutcomeStatus.invalid,
        invalidReason: reason,
        attemptCount: value.attemptCount + 1,
        lastAttemptedAt: now ?? DateTime.now(),
        predictedProbability: value.predictedProbability,
        predictedSampleCount: value.predictedSampleCount,
        predictedWilsonLower: value.predictedWilsonLower,
        predictedWilsonUpper: value.predictedWilsonUpper,
        predictionCreatedAt: value.predictionCreatedAt,
      );
}
