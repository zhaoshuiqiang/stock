import '../models/stock_models.dart';
import 'signal_engine.dart';

class TradingStrategy {
  final String id;
  final String name;
  final String category;
  final String description;
  final String entryRule;
  final String exitRule;
  final String stopLossRule;
  final bool isActive;
  final int signalStrength;
  final double? entryPrice;
  final double? targetPrice;
  final double? stopLossPrice;
  final String type;

  TradingStrategy({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.entryRule,
    required this.exitRule,
    required this.stopLossRule,
    this.isActive = false,
    this.signalStrength = 0,
    this.entryPrice,
    this.targetPrice,
    this.stopLossPrice,
    this.type = 'buy',
  });
}

List<TradingStrategy> evaluateStrategies(List<HistoryKline> data, List<SignalItem> signals) {
  if (data.length < 30) return [];

  final last = data[data.length - 1];
  final prev = data[data.length - 2];
  final price = last.close;

  final strategies = <TradingStrategy>[];

  // 1. MACD金叉战法
  final macdGoldenCross = signals.any((s) => s.signal == 'MACD金叉');
  strategies.add(TradingStrategy(
    id: 'macd_golden_cross',
    name: 'MACD金叉战法',
    category: '趋势',
    description: 'DIF上穿DEA形成金叉，是最经典的中线买入信号。零轴上方金叉更强，配合放量确认信号可靠性更高。',
    entryRule: 'DIF上穿DEA且MACD柱由绿转红',
    exitRule: 'DIF下穿DEA或MACD柱连续缩短3日',
    stopLossRule: '跌破金叉日最低价',
    isActive: macdGoldenCross,
    signalStrength: macdGoldenCross ? 85 : 0,
    entryPrice: macdGoldenCross ? price : null,
    stopLossPrice: macdGoldenCross ? last.low : null,
    type: 'buy',
  ));

  // 2. MACD背离战法
  final macdBottomDiv = signals.any((s) => s.signal == 'MACD底背离');
  final macdTopDiv = signals.any((s) => s.signal == 'MACD顶背离');
  strategies.add(TradingStrategy(
    id: 'macd_divergence',
    name: 'MACD背离战法',
    category: '反转',
    description: '股价创新低但MACD不创新低为底背离，预示下跌动能衰竭即将反转。顶背离则相反，预示见顶回落。',
    entryRule: macdBottomDiv ? '确认底背离后，DIF开始拐头向上时入场' : '顶背离出现后减仓或离场',
    exitRule: 'DIF再次向下拐头或跌破入场价',
    stopLossRule: macdBottomDiv ? '背离最低点下方2%' : '突破近期高点',
    isActive: macdBottomDiv || macdTopDiv,
    signalStrength: (macdBottomDiv || macdTopDiv) ? 85 : 0,
    entryPrice: macdBottomDiv ? price : null,
    stopLossPrice: macdBottomDiv ? last.low * 0.98 : null,
    type: macdBottomDiv ? 'buy' : 'sell',
  ));

  // 3. KDJ超卖金叉战法
  final kdjOversoldCross = last.k > last.d && prev.k <= prev.d && prev.k < 30;
  strategies.add(TradingStrategy(
    id: 'kdj_oversold_cross',
    name: 'KDJ超卖金叉战法',
    category: '反转',
    description: 'KDJ在超卖区（K<30）形成金叉，是短线反弹的经典信号。J值从负值区域拐头向上更为可靠。',
    entryRule: 'K线上穿D线且K值<30',
    exitRule: 'K值>80或K线下穿D线',
    stopLossRule: '跌破金叉前最低点',
    isActive: kdjOversoldCross,
    signalStrength: kdjOversoldCross ? 75 : 0,
    entryPrice: kdjOversoldCross ? price : null,
    stopLossPrice: kdjOversoldCross ? last.low * 0.99 : null,
    type: 'buy',
  ));

  // 4. 均线多头排列战法
  final maMultiHead = last.ma5 > last.ma10 && last.ma10 > last.ma20 && last.ma20 > 0 &&
      (last.ma60 == 0 || last.ma20 > last.ma60);
  final pullbackToMa10 = maMultiHead && last.low <= last.ma10 * 1.01 && last.close > last.ma10;
  strategies.add(TradingStrategy(
    id: 'ma_multi_head',
    name: '均线多头排列战法',
    category: '趋势',
    description: 'MA5>MA10>MA20>MA60为多头排列，说明处于上升趋势中。回踩MA10不破是最佳入场时机。',
    entryRule: '多头排列形成后，股价回踩MA10附近企稳',
    exitRule: 'MA5下穿MA10或跌破MA20',
    stopLossRule: '跌破MA20',
    isActive: maMultiHead,
    signalStrength: pullbackToMa10 ? 80 : (maMultiHead ? 65 : 0),
    entryPrice: pullbackToMa10 ? price : null,
    targetPrice: maMultiHead ? last.close * 1.1 : null,
    stopLossPrice: maMultiHead ? last.ma20 : null,
    type: 'buy',
  ));

  // 5. 布林带突破战法
  final bollSqueeze = signals.any((s) => s.signal == '布林带收口蓄势');
  final bollBreakout = signals.any((s) => s.signal.contains('布林带') && s.signal.contains('突破'));
  strategies.add(TradingStrategy(
    id: 'boll_breakout',
    name: '布林带突破战法',
    category: '趋势',
    description: '布林带收口（带宽收窄）意味着股价波动减小，即将选择方向突破。放量突破上轨为买入信号。',
    entryRule: '布林带收口后放量突破上轨',
    exitRule: '股价回落至中轨下方',
    stopLossRule: '跌破布林带中轨',
    isActive: bollSqueeze || bollBreakout,
    signalStrength: bollBreakout ? 80 : (bollSqueeze ? 60 : 0),
    entryPrice: bollBreakout ? price : null,
    stopLossPrice: bollBreakout ? last.bollMid : null,
    type: 'buy',
  ));

  // 6. 放量突破战法
  final volBreakout = signals.any((s) => s.signal == '放量上涨');
  strategies.add(TradingStrategy(
    id: 'volume_breakout',
    name: '放量突破战法',
    category: '量价',
    description: '成交量放大至均量2倍以上，同时股价上涨突破关键阻力位，说明主力资金积极介入，后续上涨概率大。',
    entryRule: '量比>2且股价突破前期高点或重要均线',
    exitRule: '连续3日缩量或跌破突破日收盘价',
    stopLossRule: '跌破突破日最低价',
    isActive: volBreakout,
    signalStrength: volBreakout ? 80 : 0,
    entryPrice: volBreakout ? price : null,
    stopLossPrice: volBreakout ? last.low : null,
    type: 'buy',
  ));

  // 7. 缩量回调战法
  final isUptrend = last.ma20 > 0 && last.close > last.ma20 &&
      data.length >= 20 && last.close > data[data.length - 20].close;
  final avgVol5 = data.sublist(data.length - 5).map((d) => d.volume).reduce((a, b) => a + b) / 5;
  final avgVol10 = data.sublist(data.length - 10).map((d) => d.volume).reduce((a, b) => a + b) / 10;
  final shrinkPullback = isUptrend && avgVol5 < avgVol10 * 0.7 && last.close < prev.close;
  strategies.add(TradingStrategy(
    id: 'shrink_pullback',
    name: '缩量回调战法',
    category: '量价',
    description: '上涨趋势中缩量回调说明抛压减轻，是逢低买入的好时机。量能萎缩至均量70%以下时关注。',
    entryRule: '上升趋势中量能萎缩至均量70%以下，股价回踩均线企稳',
    exitRule: '放量下跌或跌破MA20',
    stopLossRule: '跌破MA20或近期最低点',
    isActive: shrinkPullback,
    signalStrength: shrinkPullback ? 70 : 0,
    entryPrice: shrinkPullback ? price : null,
    stopLossPrice: shrinkPullback ? last.ma20 : null,
    type: 'buy',
  ));

  // 8. RSI超卖反弹战法
  final rsiOversoldRecovery = last.rsi6 > 30 && prev.rsi6 <= 30 && prev.rsi6 > 0;
  strategies.add(TradingStrategy(
    id: 'rsi_oversold_recovery',
    name: 'RSI超卖反弹战法',
    category: '震荡',
    description: 'RSI6从超卖区（<30）回升突破30，说明短期卖压释放完毕，可能出现技术性反弹。适合短线操作。',
    entryRule: 'RSI6从30以下回升突破30',
    exitRule: 'RSI6>70或RSI6再次跌破50',
    stopLossRule: '跌破RSI超卖时的最低点',
    isActive: rsiOversoldRecovery,
    signalStrength: rsiOversoldRecovery ? 65 : 0,
    entryPrice: rsiOversoldRecovery ? price : null,
    stopLossPrice: rsiOversoldRecovery ? last.low * 0.99 : null,
    type: 'buy',
  ));

  return strategies;
}
