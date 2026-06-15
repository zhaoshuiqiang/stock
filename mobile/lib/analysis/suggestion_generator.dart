import '../models/stock_models.dart';
import 'position_manager.dart';

class SuggestionGenerator {
  static List<String> generate({
    required String recommendation,
    required List<HistoryKline> data,
    required HistoryKline last,
    required QuoteData? quote,
    required List<SignalItem> buySignals,
    required List<SignalItem> sellSignals,
    required int totalScore,
  }) {
    final suggestions = <String>[];
    double recentLow = last.low;
    if (data.length >= 10) {
      final recent10 = data.sublist(data.length - 10);
      recentLow = recent10.map((k) => k.low).reduce((a, b) => a < b ? a : b);
    }
    final stopLossRef = last.ma20 > 0 ? last.ma20 : recentLow;

    if (recommendation == '强烈买入') {
      suggestions.add('多项技术指标强烈共振偏多，但需结合基本面和大盘环境综合判断');
      suggestions.add('可考虑分批建仓，首批仓位控制在30%以内，确认趋势后逐步加仓');
      suggestions.add('建议止损位设在${stopLossRef.toStringAsFixed(2)}附近（MA20/近期低点下方）');
    } else if (recommendation == '买入') {
      if (buySignals.length >= 3 && totalScore >= 8) {
        suggestions.add('多项技术指标共振偏多，但需结合基本面和大盘环境综合判断');
        suggestions.add('可考虑分批建仓，首批仓位控制在20%以内，确认趋势后逐步加仓');
      } else {
        suggestions.add('技术面偏多，可轻仓关注，但不宜追高');
        suggestions.add('建议先试探性建仓10%，确认支撑有效后再考虑加仓');
      }
      suggestions.add('建议止损位设在${stopLossRef.toStringAsFixed(2)}附近（MA20/近期低点下方）');
      if (quote != null && quote.pe > 0 && quote.pe < 15) {
        suggestions.add('动态市盈率${quote.pe.toStringAsFixed(1)}倍，估值较低，具有一定安全边际');
      }
    } else if (recommendation == '谨慎买入') {
      suggestions.add('技术面偏多但不确定性较大，建议谨慎操作');
      suggestions.add('可试探性轻仓买入，仓位控制在10%以内，确认趋势后再加仓');
      suggestions.add('建议止损位设在${stopLossRef.toStringAsFixed(2)}附近（MA20/近期低点下方）');
    } else if (recommendation == '偏多观望') {
      suggestions.add('技术面略偏多，但信号不够强烈，建议轻仓观察');
      suggestions.add('关注关键阻力位突破情况，突破后可考虑加仓');
      if (quote != null && quote.pe > 50) {
        suggestions.add('当前估值偏高（PE=${quote.pe.toStringAsFixed(1)}），注意仓位控制');
      }
    } else if (recommendation == '偏空观望') {
      suggestions.add('技术面略偏空，建议谨慎观望，控制仓位');
      suggestions.add('等待企稳信号出现后再考虑入场');
      if (quote != null && quote.pe > 50) {
        suggestions.add('当前估值偏高（PE=${quote.pe.toStringAsFixed(1)}），注意仓位控制');
      }
    } else if (recommendation == '谨慎卖出') {
      suggestions.add('技术面偏空但尚不极端，建议适当减仓，降低风险敞口');
      suggestions.add('关注支撑位${recentLow.toStringAsFixed(2)}的防守情况，跌破则加速减仓');
    } else if (recommendation == '卖出') {
      suggestions.add('技术面偏弱，建议适当减仓，降低风险敞口');
      suggestions.add('关注支撑位${recentLow.toStringAsFixed(2)}的防守情况，跌破则加速减仓');
      if (quote != null && quote.pe > 0 && quote.pb > 0 && quote.pb < 1) {
        suggestions.add('市净率${quote.pb.toStringAsFixed(2)}倍破净，可能存在安全边际，不宜恐慌性抛售');
      }
    } else {
      suggestions.add('技术面偏空信号较强，建议及时止损或止盈，规避风险');
      if (sellSignals.length >= 3) {
        suggestions.add('多项指标共振偏空，建议大幅减仓观望');
      } else {
        suggestions.add('建议分批减仓，避免一次性清仓');
      }
      suggestions.add('等待调整结束（如RSI回到50附近、MACD金叉）后再考虑入场');
    }

    // 基本面补充建议
    if (quote != null) {
      if (quote.pe > 0 && quote.pe < 15 && quote.pb > 0 && quote.pb < 1.5) {
        suggestions.add('基本面估值较低（PE=${quote.pe.toStringAsFixed(1)}, PB=${quote.pb.toStringAsFixed(2)}），具有中长期投资价值');
      }
    }

    // 仓位建议
    try {
      final positionManager = PositionManager.calculatePosition(last);
      suggestions.add(PositionManager.getPositionAdvice(positionManager));
    } catch (_) {}

    return suggestions;
  }
}
