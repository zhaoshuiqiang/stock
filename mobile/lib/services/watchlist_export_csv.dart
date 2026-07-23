import 'package:intl/intl.dart';

import '../analysis/opportunity_engine.dart';
import '../models/short_term_decision.dart';
import '../models/stock_models.dart';

/// 自选股导出条目：绑定代码/名称 + 可选实时行情与分析结果。
class WatchlistExportItem {
  final String code;
  final String name;
  final QuoteData? quote;
  final OpportunityResult? opp;

  const WatchlistExportItem({
    required this.code,
    required this.name,
    this.quote,
    this.opp,
  });
}

/// 构建自选股导出 CSV（BOM + CRLF，与留档导出口径一致，便于外部/AI 分析）。
/// 无分析结果的个股仅导出行情列，分析相关列留空。
String buildWatchlistExportCsv({
  required List<WatchlistExportItem> items,
  required DateTime now,
}) {
  const headers = [
    '代码', '名称', '现价', '涨跌幅(%)', '评分', '推荐', '风险等级',
    '买入信号数', '卖出信号数', '活跃战法数', '共振评分',
    '方向分', '交易质量', '风险分', '证据置信', '方向', '市场结构',
    '入场低', '入场高', '止损', '止盈1', '止盈2', '止盈3', '盈亏比',
    'topSignals', '导出时间',
  ];
  final ts = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
  final lines = <String>[headers.map(_escape).join(',')];
  for (final it in items) {
    final q = it.quote;
    final opp = it.opp;
    final price = (q != null && q.price > 0) ? q.price : (opp?.price ?? 0);
    final chg = q != null ? q.changePct : (opp?.changePct ?? 0);
    final d = opp?.shortTermDecision;
    final tl = opp?.tradeLevels;
    final row = <Object?>[
      it.code,
      it.name,
      price > 0 ? price.toStringAsFixed(3) : null,
      price > 0 ? chg.toStringAsFixed(2) : null,
      opp?.score.toStringAsFixed(1),
      opp?.recommendation,
      opp?.riskLevel,
      opp?.buySignalCount,
      opp?.sellSignalCount,
      opp?.activeStrategyCount,
      opp?.confluenceScore,
      d?.directionScore.toStringAsFixed(0),
      d?.tradeQualityScore.toStringAsFixed(0),
      d?.riskScore.toStringAsFixed(0),
      d?.evidenceConfidence.toStringAsFixed(0),
      _directionLabel(d?.direction),
      _regimeLabel(d?.marketRegime),
      _num(tl, 'entry_low'),
      _num(tl, 'entry_high'),
      _num(tl, 'stop_loss'),
      _num(tl, 'tp1'),
      _num(tl, 'tp2'),
      _num(tl, 'tp3'),
      _num(tl, 'risk_reward_ratio'),
      opp?.topSignals.join('  '),
      ts,
    ];
    lines.add(row.map(_escape).join(','));
  }
  return '\ufeff${lines.join('\r\n')}';
}

String? _num(Map<String, dynamic>? tl, String key) {
  if (tl == null) return null;
  final v = tl[key];
  if (v is num) return v.toStringAsFixed(2);
  return v?.toString();
}

String? _regimeLabel(MarketRegime? r) {
  switch (r) {
    case MarketRegime.bullishTrend:
      return '上升趋势';
    case MarketRegime.bearishTrend:
      return '下降趋势';
    case MarketRegime.rebound:
      return '反弹';
    case MarketRegime.pullback:
      return '回调';
    case MarketRegime.range:
      return '震荡';
    case MarketRegime.highVolatility:
      return '高波动';
    case MarketRegime.unknown:
      return '未知';
    case null:
      return null;
  }
}

String? _directionLabel(RecommendationDirection? d) {
  switch (d) {
    case RecommendationDirection.bullish:
      return '看多';
    case RecommendationDirection.bearish:
      return '看空';
    case RecommendationDirection.neutral:
      return '中性';
    case null:
      return null;
  }
}

String _escape(Object? value) {
  if (value == null) return '';
  final text = value.toString().replaceAll('\r', ' ').replaceAll('\n', ' ');
  return text.contains(',') || text.contains('"')
      ? '"${text.replaceAll('"', '""')}"'
      : text;
}
