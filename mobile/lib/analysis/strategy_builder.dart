import '../models/stock_models.dart';
import 'strategy_engine.dart';

/// 策略构建器
/// 负责生成分层策略库（短线/长线/特殊）
class StrategyBuilder {
  /// 生成分层策略库
  static List<TradingStrategy> buildLayeredStrategies(
    List<HistoryKline> data,
    List<SignalItem> signals,
    SignalDuration? preferredDuration,
  ) {
    final strategies = <TradingStrategy>[];

    // 短线策略库（6-8种）
    strategies.addAll(_buildShortTermStrategies(data, signals));

    // 长线策略库（6-8种）
    strategies.addAll(_buildLongTermStrategies(data, signals));

    // 特殊策略（2-3种）
    strategies.addAll(_buildSpecialStrategies(data, signals));

    // 按策略类型和活跃度排序
    strategies.sort((a, b) {
      // 优先显示与用户偏好匹配的策略
      if (a.strategyType == 'short' && preferredDuration == SignalDuration.shortTerm) return -1;
      if (b.strategyType == 'long' && preferredDuration == SignalDuration.longTerm) return -1;
      if (a.isActive && !b.isActive) return -1;
      if (!a.isActive && b.isActive) return 1;
      return b.signalStrength.compareTo(a.signalStrength);
    });

    return strategies;
  }

  /// 短线策略库（1-5天操作）
  static List<TradingStrategy> _buildShortTermStrategies(
      List<HistoryKline> data, List<SignalItem> signals) {
    final strategies = <TradingStrategy>[];
    final last = data.last;
    final prev = data[data.length - 2];

    // 1. KDJ超买卖点
    if (last.k > last.d && prev.k <= prev.d && prev.k < 30) {
      strategies.add(TradingStrategy(
        id: 'kdj_short_buy',
        name: 'KDJ超买金叉',
        category: '短线',
        description: 'KDJ在超卖区（K<30）形成金叉，短线反弹信号，适合1-3天操作',
        entryRule: 'K线上穿D线且K值<30，立即入场',
        exitRule: 'K值>80或K线下穿D线，立即离场',
        stopLossRule: '跌破金叉前最低点3%',
        isActive: true,
        signalStrength: 75,
        strategyType: 'short',
        recommendedDuration: 3,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 2,
        minConfidence: 0.65,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['KDJ', 'RSI'],
      ));
    }

    // 2. MACD底背离短线
    final bottomDivergence = signals.any((s) => s.signal.contains('底背离'));
    if (bottomDivergence && last.macdDif > last.macdDea) {
      strategies.add(TradingStrategy(
        id: 'macd_short_divergence',
        name: 'MACD底背离短线',
        category: '短线',
        description: '股价创新低但MACD不创新低，下跌动能衰竭，短线反弹机会',
        entryRule: '底背离确认后，DIF开始拐头向上时入场',
        exitRule: 'DIF再次向下拐头或跌破入场价',
        stopLossRule: '背离最低点下方2%',
        isActive: true,
        signalStrength: 80,
        strategyType: 'short',
        recommendedDuration: 5,
        maxDrawdown: 0.06,
        consecutiveLossLimit: 3,
        minConfidence: 0.7,
        riskRewardRatio: 2.5,
        compatibleIndicators: ['MACD', 'RSI'],
      ));
    }

    // 3. 缩量回调
    final isUptrend = last.ma20 > 0 && last.close > last.ma20;
    final avgVol5 = data.sublist(data.length - 5).map((d) => d.volume).reduce((a, b) => a + b) / 5;
    final shrinkPullback = isUptrend && avgVol5 < last.volMa5 * 0.7 && last.close < prev.close;
    if (shrinkPullback) {
      strategies.add(TradingStrategy(
        id: 'shrink_pullback_short',
        name: '缩量回调',
        category: '短线',
        description: '上涨趋势中缩量回调，抛压减轻，短线逢低买入机会',
        entryRule: '量能萎缩至均量70%以下，股价回踩均线企稳',
        exitRule: '放量下跌或跌破MA20',
        stopLossRule: '跌破MA20或近期最低点3%',
        isActive: true,
        signalStrength: 70,
        strategyType: 'short',
        recommendedDuration: 5,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 3,
        minConfidence: 0.6,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['MA', '量价'],
      ));
    }

    // 4. RSI超卖反弹
    if (prev.rsi6 <= 30 && last.rsi6 > 30) {
      strategies.add(TradingStrategy(
        id: 'rsi_oversold_short',
        name: 'RSI超卖反弹',
        category: '短线',
        description: 'RSI从超卖区回升突破30，短线反弹信号',
        entryRule: 'RSI6从30以下回升突破30',
        exitRule: 'RSI6>70或RSI6再次跌破50',
        stopLossRule: '跌破RSI超卖时的最低点3%',
        isActive: true,
        signalStrength: 65,
        strategyType: 'short',
        recommendedDuration: 3,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 2,
        minConfidence: 0.6,
        riskRewardRatio: 1.8,
        compatibleIndicators: ['RSI'],
      ));
    }

    // 5. 均线突破
    if (last.close > last.ma5 && prev.close <= prev.ma5) {
      strategies.add(TradingStrategy(
        id: 'ma_breakout_short',
        name: '均线突破',
        category: '短线',
        description: '股价向上突破5日均线，短期走势转强',
        entryRule: '股价站上MA5',
        exitRule: '股价跌破MA5',
        stopLossRule: '跌破MA5下方2%',
        isActive: true,
        signalStrength: 60,
        strategyType: 'short',
        recommendedDuration: 3,
        maxDrawdown: 0.04,
        consecutiveLossLimit: 2,
        minConfidence: 0.55,
        riskRewardRatio: 1.5,
        compatibleIndicators: ['MA'],
      ));
    }

    // 6. 放量突破
    final volBreakout = last.volume > last.volMa5 * 2 && last.close > last.open;
    if (volBreakout) {
      strategies.add(TradingStrategy(
        id: 'volume_breakout_short',
        name: '放量突破',
        category: '短线',
        description: '成交量放大至均量2倍以上，股价上涨，短线买入信号',
        entryRule: '量比>2且股价上涨',
        exitRule: '连续3日缩量或跌破突破日收盘价',
        stopLossRule: '跌破突破日最低点3%',
        isActive: true,
        signalStrength: 75,
        strategyType: 'short',
        recommendedDuration: 5,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 2,
        minConfidence: 0.65,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['量价', 'MA'],
      ));
    }

    return strategies;
  }

  /// 长线策略库（1-4周/1-3个月操作）
  static List<TradingStrategy> _buildLongTermStrategies(
      List<HistoryKline> data, List<SignalItem> signals) {
    final strategies = <TradingStrategy>[];
    final last = data.last;
    final prev = data[data.length - 2];

    // 1. 均线多头排列
    final maMultiHead = last.ma5 > last.ma10 && last.ma10 > last.ma20 && last.ma20 > 0 &&
        (last.ma60 == 0 || last.ma20 > last.ma60);
    if (maMultiHead) {
      strategies.add(TradingStrategy(
        id: 'ma_multi_head_long',
        name: '均线多头排列',
        category: '长线',
        description: 'MA5>MA10>MA20>MA60，长期上升趋势，中线持股为主',
        entryRule: '多头排列形成后，股价回踩MA10附近企稳',
        exitRule: 'MA5下穿MA10或跌破MA20',
        stopLossRule: '跌破MA20',
        isActive: true,
        signalStrength: 85,
        strategyType: 'long',
        recommendedDuration: 30,
        maxDrawdown: 0.08,
        consecutiveLossLimit: 4,
        minConfidence: 0.7,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['MA', 'MACD'],
      ));
    }

    // 2. MACD零轴上方金叉
    if (last.macdDif > last.macdDea && last.macdDif > 0) {
      strategies.add(TradingStrategy(
        id: 'macd_zero_above_cross',
        name: 'MACD零轴上方金叉',
        category: '长线',
        description: 'MACD在零轴上方形成金叉，多头趋势强劲，中线持股为主',
        entryRule: 'MACD在零轴上方DIF上穿DEA',
        exitRule: 'MACD柱连续缩短3日或DIF下穿DEA',
        stopLossRule: '跌破金叉日最低价或MA20',
        isActive: true,
        signalStrength: 90,
        strategyType: 'long',
        recommendedDuration: 45,
        maxDrawdown: 0.08,
        consecutiveLossLimit: 4,
        minConfidence: 0.75,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['MACD', 'MA'],
      ));
    }

    // 3. RSI中轨支撑
    if (last.ma5 > 0 && last.close > last.ma10 && last.rsi12 > 40 && last.rsi12 < 60) {
      strategies.add(TradingStrategy(
        id: 'rsi_support_long',
        name: 'RSI中轨支撑',
        category: '长线',
        description: 'RSI在40-60区间运行，中轨附近企稳，长期持有',
        entryRule: 'RSI12在40-60区间，股价回踩MA10企稳',
        exitRule: 'RSI12>70或RSI12<30',
        stopLossRule: 'RSI12<30或跌破MA20',
        isActive: true,
        signalStrength: 70,
        strategyType: 'long',
        recommendedDuration: 30,
        maxDrawdown: 0.06,
        consecutiveLossLimit: 3,
        minConfidence: 0.65,
        riskRewardRatio: 1.8,
        compatibleIndicators: ['RSI', 'MA'],
      ));
    }

    // 4. 布林带突破
    final bollSqueeze = signals.any((s) => s.signal.contains('布林带收口'));
    final bollBreakout = signals.any((s) => s.signal.contains('布林带') && s.signal.contains('突破'));
    if (bollBreakout && last.close > last.bollUpper) {
      strategies.add(TradingStrategy(
        id: 'boll_breakout_long',
        name: '布林带突破',
        category: '长线',
        description: '布林带收口后放量突破上轨，向上趋势确立，中线持有',
        entryRule: '布林带收口后放量突破上轨',
        exitRule: '股价回落至中轨下方',
        stopLossRule: '跌破布林带中轨',
        isActive: true,
        signalStrength: 80,
        strategyType: 'long',
        recommendedDuration: 30,
        maxDrawdown: 0.07,
        consecutiveLossLimit: 3,
        minConfidence: 0.7,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['BOLL', 'MACD'],
      ));
    }

    // 5. 趋势强度确认（ADX）
    if (last.adx14 > 25) {
      strategies.add(TradingStrategy(
        id: 'adx_trend_long',
        name: '趋势强度确认',
        category: '长线',
        description: 'ADX>25，趋势明确，可顺势而为，长期持有',
        entryRule: 'ADX>25，趋势强度强劲',
        exitRule: 'ADX<20或趋势转弱',
        stopLossRule: '跌破近期重要支撑',
        isActive: true,
        signalStrength: 75,
        strategyType: 'long',
        recommendedDuration: 45,
        maxDrawdown: 0.08,
        consecutiveLossLimit: 4,
        minConfidence: 0.75,
        riskRewardRatio: 1.8,
        compatibleIndicators: ['ADX', 'MA'],
      ));
    }

    // 6. 放量突破后回踩确认
    final pullbackMaMultiHead = last.ma5 > last.ma10 && last.ma10 > last.ma20;
    final pullbackToMa10 = pullbackMaMultiHead && last.low <= last.ma10 * 1.01;
    if (pullbackMaMultiHead && pullbackToMa10) {
      strategies.add(TradingStrategy(
        id: 'breakout_pullback_confirm',
        name: '突破+回踩确认',
        category: '长线',
        description: '均线多头排列后回踩MA10企稳，最佳入场时机，中线持有',
        entryRule: '多头排列后回踩MA10附近不破',
        exitRule: 'MA5下穿MA10或跌破MA20',
        stopLossRule: '跌破MA10下方2%',
        isActive: true,
        signalStrength: 85,
        strategyType: 'long',
        recommendedDuration: 20,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 3,
        minConfidence: 0.7,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['MA', 'MACD'],
      ));
    }

    return strategies;
  }

  /// 特殊策略（2-3种）
  static List<TradingStrategy> _buildSpecialStrategies(
      List<HistoryKline> data, List<SignalItem> signals) {
    final strategies = <TradingStrategy>[];
    final last = data.last;

    // 1. 缩量止跌
    final priceChange10d = (last.close / data[data.length - 11].close - 1) * 100;
    final recent3Change = (last.close / data[data.length - 4].close - 1) * 100;
    final avg3Vol = data.sublist(data.length - 3).map((d) => d.volume).reduce((a, b) => a + b) / 3;
    final avg10Vol = data.sublist(data.length - 10).map((d) => d.volume).reduce((a, b) => a + b) / 10;
    if (priceChange10d < -10 && recent3Change.abs() < 1 && avg3Vol < avg10Vol * 0.5) {
      strategies.add(TradingStrategy(
        id: 'volume_stop_drop',
        name: '缩量止跌',
        category: '特殊',
        description: '前期大幅下跌后量能萎缩，价格企稳，止跌信号',
        entryRule: '前期跌幅超10%后量能萎缩至均量50%以下，价格企稳',
        exitRule: '放量上涨或跌破企稳价位',
        stopLossRule: '跌破企稳价位3%',
        isActive: true,
        signalStrength: 65,
        strategyType: 'both',
        recommendedDuration: 15,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 2,
        minConfidence: 0.6,
        riskRewardRatio: 1.8,
        compatibleIndicators: ['量价', 'MACD'],
      ));
    }

    // 2. 放量突破
    final volBreakout = last.volume > last.volMa5 * 2 && last.close > last.open;
    if (volBreakout) {
      strategies.add(TradingStrategy(
        id: 'volume_breakout_special',
        name: '放量突破',
        category: '特殊',
        description: '成交量放大至均量2倍以上，股价上涨，主力资金介入',
        entryRule: '量比>2且股价上涨',
        exitRule: '连续3日缩量或跌破突破日收盘价',
        stopLossRule: '跌破突破日最低价3%',
        isActive: true,
        signalStrength: 75,
        strategyType: 'short',
        recommendedDuration: 5,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 2,
        minConfidence: 0.65,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['量价', 'MA'],
      ));
    }

    return strategies;
  }
}
