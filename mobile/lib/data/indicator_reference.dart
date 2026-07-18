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
    // ── 评分/决策体系 ──
    IndicatorInfo(
      name: '综合评分(1-10)',
      category: '评分',
      formula: '加权融合: 技术面33% + 资金面18% + 实时行情16% + 共振12% + 情绪10% + 基本面7% + 结构4%\n短线模式: 技术35% + 资金22% + 实时18% + 共振10% + 板块10% + 结构5%',
      description: '7维加权评分体系，输出1-10分整数。“超短线导向”权重设计，技术面最重，基本面最轻。',
      usage: '≥ 8分: 强烈买入 | ≥ 7: 买入 | ≥ 6: 谨慎买入 | 5: 观望 | ≤ 4: 偏空 | ≤ 3: 卖出',
      interpretation: '评分是批量扫描时的快照，进入详情页后会用实时行情重新计算，分数可能不同。\n3层惩罚机制: 追高风险因子[0.40,1.0] × 市场环境因子[0.50,1.0] × 预测修正因子[0.85,1.05]\n总乘积不低于0.40(保底)。板块动量加成: 主线×1.0-1.3, 退潮×0.85',
      riskTips: '评分仅反映技术面当前状态，不是涨跌预测。同一只股票在不同时间点可能得到完全不同的分数。',
    ),
    IndicatorInfo(
      name: '短线决策引擎',
      category: '评分',
      formula: '方向证据(6维加权) → 方向判定(≥±12) → 执行门控(质量/风险/置信度) → 9级推荐',
      description: '独立于评分的方向判定系统，综合趋势(25%) + 反转动量(25%) + 量价流(20%) + 相对强度(15%) + 次日预测(5%) + 板块动量(10%)。',
      usage: '方向分≥+55: 强烈买入 | ≥+35: 买入 | ≥+20: 谨慎买入 | ≥+12: 偏多观望\n方向分≤-55: 强烈卖出 | ≤-35: 卖出 | ≤-20: 谨慎卖出 | ≤-12: 偏空观望',
      interpretation: '多头执行门控: 强烈买入需交易质量≥70 + 风险≤45 + 置信度≥65。门控不通过时降级为“偏多观望”。',
      riskTips: '决策引擎基于历史K线计算，不能预知突发消息、政策变化、市场情绪剧变等事件。',
    ),
    IndicatorInfo(
      name: '1/3/5日校准概率',
      category: '评分',
      formula: 'Beta-Binomial后验 + Wilson 95%置信区间\nBrier Score + ECE校准误差',
      description: '基于历史决策记录，统计“看多后1/3/5个交易日的实际命中率”。需积累≥10个样本才能展示。',
      usage: '点击“1日/3日/5日”切换查看不同持有周期的预测准确率。\n短线用户1日，超短线评估当日留档次日看结果。',
      interpretation: '校准概率越接近实际命中率越好。Wilson区间反映样本量带来的不确定性，区间越窄越可靠。',
      riskTips: '样本量不足时结果仅供参考。市场环境变化可能导致历史校准不再适用。',
    ),
    IndicatorInfo(
      name: '方向合理率',
      category: '评分',
      formula: '当天阈值=1.0% | 次日阈值=1.5% | 之后=2.0×√(days/5) clamp(2,12)',
      description: '留档后根据实际涨跌幅与推荐方向的匹配程度评估。看多且涨了=合理，看多但跌了=偏差。',
      usage: '早盘留档 → 盘后查看“方向合理率”，评估当天的预测胜率。\n可按“看多/看空/观望”筛选查看分方向胜率。',
      interpretation: '四级评价: 非常合理(涨超阈值) > 合理(方向正确) > 偏差(方向正确但幅度不足) > 非常偏差(方向完全反了)',
      riskTips: '该指标为实时浮动，随当前行情变化。同一留档在不同时刻查看可能结果不同。',
    ),
    // ── 技术指标 ──
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
    // ── A股特色信号 ──
    IndicatorInfo(
      name: '涨停板信号',
      category: '评分',
      formula: '涨停打开: changePct≥limitPct×0.95 且 high>close\n涨停回封: changePct≥limitPct 且 |high-close|<0.5% 且 low<close×0.99',
      description: 'A股T+1制度下的特色信号。涨停打开为卖出信号(封板失败)，涨停回封为买入信号(多空博弈后多方胜出)。主板涨跌幅限制9.5%，创业板/科创板19.5%，北交所29.5%。',
      usage: '1. 涨停打开: 封板失败，短线卖出信号(confidence=0.80)\n2. 涨停回封: 盘中打开后重新封板，买入信号(confidence=0.75)',
      interpretation: '涨停打开说明抛压较大，封不住板。涨停回封说明多方力量强劲，重新夺回主导权。',
      riskTips: '涨停信号依赖日K线数据，无法区分盘中具体打开时间。回封信号需结合量能判断真实性。',
    ),
    IndicatorInfo(
      name: '尾盘异动信号',
      category: '评分',
      formula: '尾盘急拉: changePct>3% 且 upperShadow>0.5 且 closePosition<0.5\n尾盘急跌: changePct<-2% 且 lowerShadow>0.25 且 upperShadow<0.15 且 close<open',
      description: '尾盘急拉(日K降级检测): 长上影线+涨幅>3%+收盘位置偏低，疑似尾盘拉升后回落。尾盘急跌: 放量下挫+下影线较长+阴线，空方主导。',
      usage: '1. 尾盘急拉: 疑似主力尾盘拉高出货，卖出信号(confidence=0.70)\n2. 尾盘急跌: 空方尾盘主导，卖出信号(confidence=0.65)',
      interpretation: '尾盘异动反映最后30分钟的资金行为。急拉后留长上影线，次日低开概率大。急跌说明尾盘抛压沉重。',
      riskTips: '日K线无法精确识别尾盘行为，仅为降级检测。有分时数据时可更准确判断。',
    ),
    IndicatorInfo(
      name: '板块动量评分',
      category: '评分',
      formula: '综合板块轮动+过热检测+涨停潮+相对强度\nscore∈[-1.0, 1.0], 映射到[0, 10]分',
      description: '整合SectorRotation/SectorHeatDetector/LimitUpAnalysis数据，计算个股的板块动量评分。仅短线模式生效(权重10%)。',
      usage: '1. 主线板块+板块加速: 正向动量\n2. 板块退潮+减速: 负向动量\n3. 板块过热: 主线加成受限\n4. 板块龙头(相对强度>0.8): 额外加成',
      interpretation: '主线板块个股获得mainLineBonus(1.0-1.3倍)加成。退潮板块个股获得0.85折扣。过热板块加成受限。',
      riskTips: '板块数据依赖API返回，数据缺失时板块动量为0(中性)。过热检测基于3日连涨+涨停家数，可能滞后。',
    ),
  ];

  static List<IndicatorInfo> getByCategory(String category) {
    return all.where((i) => i.category == category).toList();
  }

  static IndicatorInfo? findByName(String name) {
    return all.firstWhere((i) => i.name.toLowerCase() == name.toLowerCase(), orElse: () => all.first);
  }
}