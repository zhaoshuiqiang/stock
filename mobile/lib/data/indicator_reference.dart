class IndicatorInfo {
  final String name;
  final String category;
  final String formula;
  final String description;
  final String usage;
  final String interpretation;
  final String riskTips;

  const IndicatorInfo({
    required this.name,
    required this.category,
    required this.formula,
    required this.description,
    required this.usage,
    required this.interpretation,
    required this.riskTips,
  });
}

class IndicatorReference {
  static final List<IndicatorInfo> all = [
    IndicatorInfo(
      name: 'MACD',
      category: '趋势',
      formula: 'DIF = EMA(12) - EMA(26)\nDEA = EMA(DIF, 9)\nMACD = 2 × (DIF - DEA)',
      description: '指数平滑异同移动平均线，通过短期EMA与长期EMA的差值，判断多空力量变化和趋势转折。',
      usage: '1. DIF金叉DEA且MACD柱由负转正：买入信号\n2. DIF死叉DEA且MACD柱由正转负：卖出信号\n3. 股价创新高但DIF不创新高：顶背离，预示下跌\n4. 股价创新低但DIF不创新低：底背离，预示上涨',
      interpretation: 'DIF>0：多头市场；DIF<0：空头市场。柱状图反映多空力量强弱，红柱越长多头越强，绿柱越长空头越强。',
      riskTips: 'MACD滞后性较强，不适用于盘整行情。背离信号需结合成交量确认，单独使用准确率有限。',
    ),
    IndicatorInfo(
      name: 'KDJ',
      category: '震荡',
      formula: 'RSV = (C - L9) / (H9 - L9) × 100\nK = SMA(RSV, 3, 1)\nD = SMA(K, 3, 1)\nJ = 3K - 2D',
      description: '随机指标，通过计算当前价格在最近N日最高价最低价区间中的相对位置，判断超买超卖状态。',
      usage: '1. K值>80：超买区域，可能回调\n2. K值<20：超卖区域，可能反弹\n3. K金叉D且J线向上穿越0轴：买入信号\n4. K死叉D且J线向下穿越100轴：卖出信号',
      interpretation: 'J线反应最灵敏，K线次之，D线最平稳。三线同向时趋势较强，交叉频繁时市场震荡。',
      riskTips: '强势行情中指标可能长期处于超买区，弱势行情中长期处于超卖区，需结合趋势指标使用。',
    ),
    IndicatorInfo(
      name: 'RSI',
      category: '震荡',
      formula: 'RSI = 100 - 100 / (1 + RS)\nRS = 平均上涨幅度 / 平均下跌幅度',
      description: '相对强弱指数，通过比较一定时期内平均上涨幅度与平均下跌幅度，衡量市场强弱程度。',
      usage: '1. RSI>70：超买，可能下跌\n2. RSI<30：超卖，可能上涨\n3. 股价创新高但RSI未创新高：顶背离\n4. 股价创新低但RSI未创新低：底背离',
      interpretation: 'RSI在50以上为多头市场，50以下为空头市场。趋势行情中RSI往往在50-70或30-50之间波动。',
      riskTips: '极端行情下RSI可能出现钝化，即指标长期处于超买或超卖区但价格仍持续涨跌。',
    ),
    IndicatorInfo(
      name: 'BOLL',
      category: '趋势',
      formula: '中轨 = MA(20)\n上轨 = MA(20) + 2 × σ\n下轨 = MA(20) - 2 × σ',
      description: '布林带，通过计算价格的标准差确定价格波动区间，反映市场波动性和趋势状态。',
      usage: '1. 价格突破上轨：可能继续上涨或回调\n2. 价格跌破下轨：可能继续下跌或反弹\n3. 收口变窄：市场即将变盘\n4. 张口扩大：趋势加速',
      interpretation: '布林带宽度反映波动率，窄带表示低波动，宽带表示高波动。中轨是重要支撑/阻力位。',
      riskTips: '布林带适用于趋势跟踪，盘整行情中信号频繁失效。需结合其他指标确认方向。',
    ),
    IndicatorInfo(
      name: 'MA',
      category: '趋势',
      formula: 'MA(n) = Σ(收盘价) / n',
      description: '移动平均线，通过平滑价格波动显示趋势方向和支撑阻力位。常用周期有5日、10日、20日、60日。',
      usage: '1. 均线多头排列(MA5>MA10>MA20)：上升趋势\n2. 均线空头排列(MA5<MA10<MA20)：下降趋势\n3. 价格上穿均线：买入信号\n4. 价格下穿均线：卖出信号',
      interpretation: '短期均线反应灵敏，长期均线稳定性好。均线密集缠绕表示盘整，发散表示趋势明确。',
      riskTips: '均线滞后于价格，信号延迟。均线被频繁穿越时为震荡行情，不宜使用均线策略。',
    ),
    IndicatorInfo(
      name: 'ADX',
      category: '趋势',
      formula: '+DI = 上升幅度均值 / TR均值 × 100\n-DI = 下降幅度均值 / TR均值 × 100\nADX = DI差值的平滑均值',
      description: '平均趋向指数，衡量趋势强度而非方向。ADX值越高趋势越强，越低则越接近盘整。',
      usage: '1. ADX>25：趋势较强\n2. ADX>40：趋势很强\n3. ADX<20：盘整行情\n4. +DI>-DI：上升趋势；+DI<-DI：下降趋势',
      interpretation: 'ADX上升表示趋势正在加强，ADX下降表示趋势正在减弱或进入盘整。',
      riskTips: 'ADX不指示方向，需结合+DI和-DI判断。横盘震荡时ADX值可能失真。',
    ),
    IndicatorInfo(
      name: 'CCI',
      category: '震荡',
      formula: 'CCI = (TP - MA) / (0.015 × MD)\nTP = (H+L+C)/3',
      description: '商品通道指数，衡量价格偏离其统计平均值的程度，识别超买超卖和趋势反转。',
      usage: '1. CCI>100：超买区域\n2. CCI<-100：超卖区域\n3. CCI从+100以上回落：卖出信号\n4. CCI从-100以下回升：买入信号',
      interpretation: 'CCI在±100之间为正常区间，超出此范围表示极端行情。CCI穿越±100是重要信号。',
      riskTips: '极端行情下CCI可能持续超出±100，需结合趋势方向判断是否为有效信号。',
    ),
    IndicatorInfo(
      name: 'WR',
      category: '震荡',
      formula: 'WR = (Hn - C) / (Hn - Ln) × 100',
      description: '威廉指标，通过计算收盘价在最近N日最高价最低价区间的位置，判断超买超卖状态。',
      usage: '1. WR<-20：超买，可能下跌\n2. WR>-80：超卖，可能上涨\n3. WR从-20以下回升：卖出信号\n4. WR从-80以上回落：买入信号',
      interpretation: 'WR值越小越接近超买，越大越接近超卖。与RSI原理相似但刻度相反。',
      riskTips: '超买超卖只是预警信号，不代表立即反转。需等待价格形态确认。',
    ),
    IndicatorInfo(
      name: 'ATR',
      category: '波动',
      formula: 'TR = max(H-L, |H-PrevC|, |L-PrevC|)\nATR = MA(TR, 14)',
      description: '平均真实波幅，衡量市场波动性。ATR值越大说明波动越剧烈，越小说明越平稳。',
      usage: '1. 设置止损：通常用1.5-2倍ATR作为止损距离\n2. 设置目标：通常用2-3倍ATR作为止盈目标\n3. 过滤信号：低ATR时减少交易频率',
      interpretation: 'ATR反映市场活跃度，高ATR适合波段交易，低ATR适合短线或观望。',
      riskTips: 'ATR只衡量波动幅度，不指示方向。需结合趋势指标使用。',
    ),
    IndicatorInfo(
      name: 'OBV',
      category: '量能',
      formula: '上涨日：OBV += 成交量\n下跌日：OBV -= 成交量\n平盘日：OBV不变',
      description: '能量潮指标，通过成交量变化反映资金流向，验证价格趋势的有效性。',
      usage: '1. OBV与股价同步上涨：量价配合，上涨趋势健康\n2. OBV与股价同步下跌：量价配合，下跌趋势持续\n3. 股价上涨但OBV下降：顶背离，上涨乏力\n4. 股价下跌但OBV上升：底背离，下跌即将结束',
      interpretation: 'OBV领先于价格变化，可提前预警趋势反转。连续上涨/下跌时OBV应同步变化。',
      riskTips: 'OBV对成交量异常敏感，需排除对倒成交量的影响。停牌复牌后OBV可能失真。',
    ),
  ];

  static List<IndicatorInfo> getByCategory(String category) {
    return all.where((i) => i.category == category).toList();
  }

  static IndicatorInfo? findByName(String name) {
    return all.firstWhere((i) => i.name.toLowerCase() == name.toLowerCase(), orElse: () => all.first);
  }
}