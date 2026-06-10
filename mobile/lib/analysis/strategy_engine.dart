import '../models/stock_models.dart';

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
    signalStrength: macdGoldenCross ? (last.macdDif > 0 ? 90 : 75) : 0,
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

  // 9. MACD零轴上方金叉战法
  final macdAboveZero = signals.any((s) => s.signal == 'MACD金叉') && last.macdDif > 0;
  strategies.add(TradingStrategy(
    id: 'macd_above_zero_cross',
    name: 'MACD零轴上方金叉',
    category: '趋势',
    description: 'MACD在零轴上方形成金叉，说明多头趋势强劲，是比普通金叉更强的买入信号。中线持股为主。',
    entryRule: 'MACD在零轴上方DIF上穿DEA',
    exitRule: 'MACD柱连续缩短3日或DIF下穿DEA',
    stopLossRule: '跌破金叉日最低价或MA20',
    isActive: macdAboveZero,
    signalStrength: macdAboveZero ? 90 : 0,
    entryPrice: macdAboveZero ? price : null,
    targetPrice: macdAboveZero ? price * 1.15 : null,
    stopLossPrice: macdAboveZero ? last.low : null,
    type: 'buy',
  ));

  // 10. 均线粘合突破战法
  final maClose = last.close > 0 &&
      (last.ma5 - last.ma10).abs() / last.close < 0.02 &&
      (last.ma10 - last.ma20).abs() / last.close < 0.02 &&
      last.ma5 > 0 && last.ma10 > 0 && last.ma20 > 0;
  final maBreakout = maClose && last.close > last.ma5 && last.close > last.ma10 && last.close > last.ma20;
  strategies.add(TradingStrategy(
    id: 'ma_converge_breakout',
    name: '均线粘合突破战法',
    category: '趋势',
    description: '多条均线靠拢粘合说明市场成本趋于一致，即将选择方向突破。放量突破均线密集区是强买入信号。',
    entryRule: 'MA5/MA10/MA20粘合后放量突破，收盘站上所有均线',
    exitRule: '跌破MA20或均线重新粘合',
    stopLossRule: '跌破粘合区间下沿',
    isActive: maBreakout,
    signalStrength: maBreakout ? 85 : (maClose ? 55 : 0),
    entryPrice: maBreakout ? price : null,
    targetPrice: maBreakout ? price * 1.12 : null,
    stopLossPrice: maBreakout ? last.ma20 * 0.98 : null,
    type: 'buy',
  ));

  // 11. 红三兵战法
  final redThreeSoldiers = data.length >= 3 &&
      data[data.length - 3].close > data[data.length - 3].open &&
      data[data.length - 2].close > data[data.length - 2].open &&
      last.close > last.open &&
      data[data.length - 2].close > data[data.length - 3].close &&
      last.close > data[data.length - 2].close &&
      last.close > prev.close;
  strategies.add(TradingStrategy(
    id: 'red_three_soldiers',
    name: '红三兵战法',
    category: 'K线形态',
    description: '连续三根阳线且收盘价逐步抬高，是强烈的看涨信号。出现在底部区域更为可靠，预示趋势反转向上。',
    entryRule: '连续3根阳线且收盘价递增',
    exitRule: '出现长上影线或放量阴线',
    stopLossRule: '跌破第一根阳线最低点',
    isActive: redThreeSoldiers,
    signalStrength: redThreeSoldiers ? 75 : 0,
    entryPrice: redThreeSoldiers ? price : null,
    targetPrice: redThreeSoldiers ? price * 1.08 : null,
    stopLossPrice: redThreeSoldiers ? data[data.length - 3].low : null,
    type: 'buy',
  ));

  // 12. 早晨之星战法
  final morningStar = data.length >= 3 &&
      data[data.length - 3].close < data[data.length - 3].open && // 第一根阴线
      data[data.length - 2].open > 0 &&
      (data[data.length - 2].close - data[data.length - 2].open).abs() / data[data.length - 2].open < 0.01 && // 第二根十字星
      last.close > last.open && // 第三根阳线
      last.close > (data[data.length - 3].open + data[data.length - 3].close) / 2; // 阳线收复阴线一半以上
  strategies.add(TradingStrategy(
    id: 'morning_star',
    name: '早晨之星战法',
    category: 'K线形态',
    description: '由阴线+十字星+阳线组成，是经典的底部反转形态。第三根阳线深入第一根阴线实体越多，反转信号越强。',
    entryRule: '阴线+十字星+阳线组合出现，阳线收复阴线过半',
    exitRule: '跌破十字星最低点',
    stopLossRule: '十字星最低点下方2%',
    isActive: morningStar,
    signalStrength: morningStar ? 80 : 0,
    entryPrice: morningStar ? price : null,
    targetPrice: morningStar ? price * 1.1 : null,
    stopLossPrice: morningStar ? data[data.length - 2].low * 0.98 : null,
    type: 'buy',
  ));

  // 13. 量价齐升战法
  final volPriceUp = last.close > prev.close && last.volume > prev.volume * 1.3 &&
      last.close > last.open && prev.close > prev.open;
  strategies.add(TradingStrategy(
    id: 'volume_price_up',
    name: '量价齐升战法',
    category: '量价',
    description: '股价上涨同时成交量放大，说明买盘积极，资金持续流入。连续量价齐升是强势行情的典型特征。',
    entryRule: '当日量价齐升，量比>1.3',
    exitRule: '出现缩量滞涨或放量滞涨',
    stopLossRule: '跌破放量上涨起始日最低价',
    isActive: volPriceUp,
    signalStrength: volPriceUp ? 70 : 0,
    entryPrice: volPriceUp ? price : null,
    stopLossPrice: volPriceUp ? prev.low : null,
    type: 'buy',
  ));

  // 14. 布林带支撑战法
  final bollSupport = last.low <= last.bollLower * 1.005 && last.close > last.bollLower &&
      last.bollLower > 0;
  strategies.add(TradingStrategy(
    id: 'boll_support',
    name: '布林带支撑战法',
    category: '震荡',
    description: '股价触及布林带下轨后企稳回升，说明下轨支撑有效。适合在震荡行情中低吸操作。',
    entryRule: '股价触及布林带下轨后收阳',
    exitRule: '股价触及布林带上轨或中轨压力明显',
    stopLossRule: '跌破布林带下轨3%',
    isActive: bollSupport,
    signalStrength: bollSupport ? 65 : 0,
    entryPrice: bollSupport ? price : null,
    targetPrice: bollSupport ? last.bollMid : null,
    stopLossPrice: bollSupport ? last.bollLower * 0.97 : null,
    type: 'buy',
  ));

  // 15. KDJ超买死叉战法（卖出信号）
  final kdjOverboughtCross = last.k < last.d && prev.k >= prev.d && prev.k > 70;
  strategies.add(TradingStrategy(
    id: 'kdj_overbought_cross',
    name: 'KDJ超买死叉战法',
    category: '反转',
    description: 'KDJ在超买区（K>70）形成死叉，是短线见顶信号。J值从100以上拐头向下更为可靠，应及时减仓。',
    entryRule: 'K线下穿D线且K值>70',
    exitRule: 'K值<30或K线重新上穿D线',
    stopLossRule: '突破死叉日最高价',
    isActive: kdjOverboughtCross,
    signalStrength: kdjOverboughtCross ? 75 : 0,
    entryPrice: kdjOverboughtCross ? price : null,
    stopLossPrice: kdjOverboughtCross ? last.high * 1.02 : null,
    type: 'sell',
  ));

  // 16. RSI超买回落战法（卖出信号）
  final rsiOverboughtDrop = last.rsi6 < 70 && prev.rsi6 >= 70;
  strategies.add(TradingStrategy(
    id: 'rsi_overbought_drop',
    name: 'RSI超买回落战法',
    category: '震荡',
    description: 'RSI6从超买区（>70）回落跌破70，说明短期买盘衰竭，可能出现回调。适合短线减仓或止盈。',
    entryRule: 'RSI6从70以上跌破70',
    exitRule: 'RSI6<30或重新突破50',
    stopLossRule: 'RSI6重新突破70',
    isActive: rsiOverboughtDrop,
    signalStrength: rsiOverboughtDrop ? 65 : 0,
    entryPrice: rsiOverboughtDrop ? price : null,
    stopLossPrice: rsiOverboughtDrop ? last.high * 1.02 : null,
    type: 'sell',
  ));

  // 17. 三只乌鸦战法（卖出信号）
  final threeCrows = data.length >= 3 &&
      data[data.length - 3].close < data[data.length - 3].open &&
      data[data.length - 2].close < data[data.length - 2].open &&
      last.close < last.open &&
      data[data.length - 2].close < data[data.length - 3].close &&
      last.close < data[data.length - 2].close;
  strategies.add(TradingStrategy(
    id: 'three_crows',
    name: '三只乌鸦战法',
    category: 'K线形态',
    description: '连续三根阴线且收盘价逐步走低，是强烈的看跌信号。出现在高位区域更为危险，预示趋势反转向下。',
    entryRule: '连续3根阴线且收盘价递减',
    exitRule: '出现放量阳线反包',
    stopLossRule: '突破第一根阴线最高点',
    isActive: threeCrows,
    signalStrength: threeCrows ? 75 : 0,
    entryPrice: threeCrows ? price : null,
    stopLossPrice: threeCrows ? data[data.length - 3].high * 1.02 : null,
    type: 'sell',
  ));

  // 18. 均线空头排列战法（卖出信号）
  final maBearish = last.ma5 < last.ma10 && last.ma10 < last.ma20 && last.ma20 > 0;
  strategies.add(TradingStrategy(
    id: 'ma_bearish',
    name: '均线空头排列战法',
    category: '趋势',
    description: 'MA5<MA10<MA20为空头排列，说明处于下降趋势中。反弹至MA10附近是减仓机会，不宜抄底。',
    entryRule: '空头排列形成后，股价反弹至MA10附近受阻',
    exitRule: '均线重新多头排列',
    stopLossRule: '突破MA20',
    isActive: maBearish,
    signalStrength: maBearish ? 70 : 0,
    entryPrice: maBearish ? price : null,
    stopLossPrice: maBearish ? last.ma20 * 1.02 : null,
    type: 'sell',
  ));

  // Detect buy/sell strategy conflicts
  final activeBuyStrategies = strategies.where((s) => s.isActive && s.type == 'buy').toList();
  final activeSellStrategies = strategies.where((s) => s.isActive && s.type == 'sell').toList();

  if (activeBuyStrategies.isNotEmpty && activeSellStrategies.isNotEmpty) {
    // Add conflict note to conflicting strategies
    for (final s in activeBuyStrategies) {
      strategies.add(TradingStrategy(
        id: 'conflict_${s.id}',
        name: '${s.name}(冲突)',
        category: '警告',
        description: '买入策略${s.name}与卖出策略${activeSellStrategies.map((e) => e.name).join('/')}同时激活，信号矛盾，建议谨慎操作',
        entryRule: '多空信号冲突，观望为主',
        exitRule: '等待信号统一',
        stopLossRule: '严格止损',
        isActive: true,
        signalStrength: 50,
        type: 'buy',
      ));
    }
  }

  return strategies;
}
