/// 交易日工具。
///
/// 决策快照的 [signalTradeDate] 用于对齐基准（000300）K 线序列以计算
/// 1/3/5 交易日命中率。若归档发生在周末/节假日（序列中无该日期），
/// 评估时会永远无法匹配 → 快照永久停留在 pending。因此在写入前先把日期
/// 归一化为最近的交易日（周六→前一个周五，周日→前一个周五）。
///
/// 注：仅处理周末；法定节假日需用交易日历进一步修正，但评估器对
/// `signalIndex < 0` 已做 invalid 兜底（见 [DecisionOutcomeEvaluator]），
/// 故此处不必覆盖全部节假日即可避免「永久 pending」。
class TradingDateUtils {
  const TradingDateUtils._();

  /// 将任意日期归一化为最近的交易日（向前回退到周五及之前）。
  static DateTime normalizeToTradeDate(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    switch (d.weekday) {
      case DateTime.saturday:
        return d.subtract(const Duration(days: 1));
      case DateTime.sunday:
        return d.subtract(const Duration(days: 2));
      default:
        return d;
    }
  }

  /// 是否为交易日（非周末）。用于「今日归档」等筛选的快捷判断。
  static bool isTradeDate(DateTime date) {
    final w = date.weekday;
    return w >= DateTime.monday && w <= DateTime.friday;
  }
}
