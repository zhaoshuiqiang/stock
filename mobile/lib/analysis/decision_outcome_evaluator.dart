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
    final benchmark = _normalized(data.adjustedBenchmark);
    final stock = _normalized(data.adjustedStock);
    final signalIndex = benchmark.indexWhere(
      (bar) => _sameDate(bar.date, snapshot.signalTradeDate),
    );
    // signalTradeDate 不在基准序列（如节假日/数据缺口）→ 永远无法匹配，
    // 直接置 invalid，避免 refreshPending 每周期空转占用 limit 槽位。
    // （已通过 [TradingDateUtils] 在写入时归一化周末，此处为双保险。）
    if (signalIndex < 0) {
      return _invalid(outcome, 'signal date not in benchmark series');
    }
    if (signalIndex + outcome.horizon >= benchmark.length) {
      return _pending(outcome);
    }
    final benchmarkSignal = benchmark[signalIndex];
    final benchmarkTarget = benchmark[signalIndex + outcome.horizon];
    final dueDate = benchmarkTarget.date;
    final targetIndex = stock.indexWhere(
      (bar) => !bar.date.isBefore(_date(dueDate)),
    );
    if (targetIndex < 0) return _pending(outcome, dueTradeDate: dueDate);

    final signalAdjusted = snapshot.adjustedSignalPrice ??
        _barOn(stock, snapshot.signalTradeDate)?.close ??
        snapshot.signalPrice;
    if (signalAdjusted <= 0) {
      return _invalid(outcome, 'invalid adjusted signal price');
    }
    final target = stock[targetIndex];
    final entry = stock.cast<HistoryKline?>().firstWhere(
          (bar) => bar!.date.isAfter(_date(snapshot.signalTradeDate)),
          orElse: () => null,
        );
    final forecastReturn = (target.close / signalAdjusted - 1) * 100;
    final benchmarkReturn =
        (benchmarkTarget.close / benchmarkSignal.close - 1) * 100;
    final alphaReturn = forecastReturn - benchmarkReturn;
    final orientation = snapshot.direction == RecommendationDirection.bearish
        ? -1.0
        : snapshot.direction == RecommendationDirection.bullish
            ? 1.0
            : 0.0;
    final rawHit = orientation == 0
        ? forecastReturn.abs() < 0.5
        : forecastReturn * orientation > 0;
    final effectiveHit = orientation == 0
        ? forecastReturn.abs() < 0.5
        : forecastReturn * orientation >= 0.5;
    final alphaHit = orientation == 0
        ? alphaReturn.abs() < 0.5
        : alphaReturn * orientation > 0;
    final path = stock
        .where((bar) =>
            bar.date.isAfter(_date(snapshot.signalTradeDate)) &&
            !bar.date.isAfter(_date(target.date)))
        .toList();
    final orientedReturns = path
        .expand((bar) => [
              (bar.high / signalAdjusted - 1) * 100 * orientation,
              (bar.low / signalAdjusted - 1) * 100 * orientation,
            ])
        .toList();
    final executableValid = entry != null && !_isOnePriceLimit(entry);
    final executableReturn =
        executableValid ? (target.close / entry.open - 1) * 100 : null;
    final rawTarget = data.rawStock == null
        ? null
        : _barOnOrAfter(data.rawStock!, target.date);
    final rawSignal = data.rawStock == null
        ? null
        : _barOn(data.rawStock!, snapshot.signalTradeDate);
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
      deferredTradeDays: stock
          .where((bar) =>
              bar.date.isAfter(_date(dueDate)) &&
              !bar.date.isAfter(_date(target.date)))
          .length,
      evaluatedAt: now ?? DateTime.now(),
      adjustedSignalPriceUsed: signalAdjusted,
      entryOpenPrice: entry?.open,
      targetClosePrice: rawTarget?.close ?? target.close,
      adjustedTargetClosePrice: target.close,
      benchmarkSignalClose: benchmarkSignal.close,
      benchmarkTargetClose: benchmarkTarget.close,
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
      lastAttemptedAt: now ?? DateTime.now(),
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
          DecisionOutcomeRecord value, String reason) =>
      DecisionOutcomeRecord(
        id: value.id,
        snapshotId: value.snapshotId,
        horizon: value.horizon,
        status: DecisionOutcomeStatus.invalid,
        invalidReason: reason,
        attemptCount: value.attemptCount + 1,
        lastAttemptedAt: DateTime.now(),
      );
}
