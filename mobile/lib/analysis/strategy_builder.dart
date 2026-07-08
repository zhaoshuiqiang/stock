import '../models/stock_models.dart';
import 'strategy_engine.dart';

/// 策略构建器
/// 负责生成分层策略库（短线/长线/特殊）
class StrategyBuilder {
  /// 计算ATR止损价（买入策略）
  static double? _calcATRStopLoss(
      HistoryKline last, double atrMultiplier, String strategyType) {
    if (last.atr14 <= 0) {
      // 降级为固定百分比
      return strategyType == 'short' ? last.close * 0.97 : last.close * 0.95;
    }
    return last.close - last.atr14 * atrMultiplier;
  }

  /// 计算ATR止盈目标价
  static double? _calcATRTarget(
      HistoryKline last, double atrMultiplier, String strategyType) {
    if (last.atr14 <= 0) {
      return strategyType == 'short' ? last.close * 1.05 : last.close * 1.10;
    }
    return last.close + last.atr14 * atrMultiplier;
  }

  /// 生成分层策略库
  static List<TradingStrategy> buildLayeredStrategies(
    List<HistoryKline> data,
    List<SignalItem> signals,
    SignalDuration? preferredDuration,
  ) {
    final strategies = <TradingStrategy>[];

    // 短线策略库（6-8种）—— 始终生成所有策略，条件不满足时isActive=false
    strategies.addAll(_buildShortTermStrategies(data, signals));

    // 长线策略库（6-8种）
    strategies.addAll(_buildLongTermStrategies(data, signals));

    // 特殊策略（2-3种）
    strategies.addAll(_buildSpecialStrategies(data, signals));

    // 补充所有未触发的策略定义（条件不满足但仍展示）
    strategies.addAll(_buildInactiveStrategies(data, strategies));

    // 去重（按id）
    final seen = <String>{};
    strategies.removeWhere((s) => !seen.add(s.id));

    if (preferredDuration != null) {
      strategies.removeWhere((s) => !_matchesDuration(s, preferredDuration));
    }

    // 按策略类型和活跃度排序
    strategies.sort((a, b) {
      if (a.isActive && !b.isActive) return -1;
      if (!a.isActive && b.isActive) return 1;
      return b.signalStrength.compareTo(a.signalStrength);
    });

    return strategies;
  }

  static bool _matchesDuration(
      TradingStrategy strategy, SignalDuration preferredDuration) {
    switch (preferredDuration) {
      case SignalDuration.shortTerm:
        return strategy.strategyType == 'short' ||
            strategy.strategyType == 'both' ||
            strategy.category == '短线' ||
            strategy.category == '防守';
      case SignalDuration.longTerm:
        return strategy.strategyType == 'long' && strategy.category == '长线';
      case SignalDuration.mediumTerm:
        return strategy.recommendedDuration >= 5 &&
            strategy.recommendedDuration <= 20;
    }
  }

  /// 补充所有策略定义（条件不满足时isActive=false），确保面板不会为空
  static List<TradingStrategy> _buildInactiveStrategies(
      List<HistoryKline> data, List<TradingStrategy> existing) {
    final existingIds = existing.map((s) => s.id).toSet();
    final all = <TradingStrategy>[];
    final last = data.isNotEmpty ? data.last : null;

    final definitions = [
      (
        'kdj_short_buy',
        'KDJ超卖金叉',
        '短线',
        'KDJ在超卖区（K<30）形成金叉，短线反弹信号',
        'K线上穿D线且K值<30',
        'K值>80或K线下穿D线',
        '跌破入场价-1.5xATR'
      ),
      (
        'macd_short_divergence',
        'MACD底背离短线',
        '短线',
        '股价创新低但MACD不创新低，短线反弹机会',
        '底背离确认后DIF拐头向上',
        'DIF再次向下拐头',
        '跌破入场价-1xATR'
      ),
      (
        'shrink_pullback_short',
        '缩量回调',
        '短线',
        '上涨趋势中缩量回调，短线逢低买入机会',
        '量能萎缩至均量70%以下',
        '放量下跌或跌破MA20',
        '跌破入场价-1xATR'
      ),
      (
        'rsi_oversold_short',
        'RSI超卖反弹',
        '短线',
        'RSI从超卖区回升突破30，短线反弹信号',
        'RSI6从30以下回升突破30',
        'RSI6>70或跌破50',
        '跌破入场价-1xATR'
      ),
      (
        'ma_breakout_short',
        '均线突破',
        '短线',
        '股价向上突破5日均线，短期走势转强',
        '股价站上MA5',
        '股价跌破MA5',
        '跌破入场价-1xATR'
      ),
      (
        'volume_breakout_short',
        '放量突破',
        '短线',
        '成交量放大至均量2倍以上，短线买入信号',
        '量比>2且股价上涨',
        '连续3日缩量',
        '跌破入场价-1xATR'
      ),
      (
        'ma_multi_head_long',
        '均线多头排列',
        '长线',
        'MA5>MA10>MA20，长期上升趋势',
        '多头排列形成后回踩MA10',
        'MA5下穿MA10',
        '跌破入场价-2xATR'
      ),
      (
        'macd_zero_above_cross',
        'MACD零轴上方金叉',
        '长线',
        'MACD在零轴上方形成金叉，多头趋势强劲',
        '零轴上方DIF上穿DEA',
        'DIF下穿DEA',
        '跌破入场价-2xATR'
      ),
      (
        'rsi_support_long',
        'RSI中轨支撑',
        '长线',
        'RSI在40-60区间运行，中轨附近企稳',
        'RSI12在40-60区间回踩',
        'RSI12>70或<30',
        '跌破入场价-2xATR'
      ),
      (
        'boll_breakout_long',
        '布林带突破',
        '长线',
        '布林带收口后放量突破上轨',
        '布林带收口后放量突破',
        '回落至中轨下方',
        '跌破入场价-2xATR'
      ),
      (
        'adx_trend_long',
        '趋势强度确认',
        '长线',
        'ADX>25，趋势明确',
        'ADX>25趋势强劲',
        'ADX<20趋势转弱',
        '跌破入场价-2xATR'
      ),
      (
        'breakout_pullback_confirm',
        '突破+回踩确认',
        '长线',
        '均线多头排列后回踩MA10企稳',
        '多头排列后回踩MA10',
        'MA5下穿MA10',
        '跌破入场价-2xATR'
      ),
      (
        'volume_stop_drop',
        '缩量止跌',
        '特殊',
        '前期大幅下跌后量能萎缩，价格企稳',
        '跌幅超10%后量能萎缩50%',
        '放量上涨或跌破企稳价',
        '跌破入场价-1.5xATR'
      ),
      (
        'ma20_break_defense',
        'MA20破位防守',
        '防守',
        '股价跌破MA20，趋势可能转弱',
        '收盘价跌破MA20',
        '股价重新站回MA20',
        '跌破入场价-1.5xATR'
      ),
      (
        'high_volume_stall',
        '高位放量滞涨止盈',
        '防守',
        '大幅上涨后放量滞涨，主力派发信号',
        '20日涨>20%+放量滞涨',
        '放量跌破MA10',
        '跌破入场价-1.5xATR'
      ),
    ];

    for (final (id, name, category, desc, entry, exit, stop) in definitions) {
      if (!existingIds.contains(id)) {
        all.add(TradingStrategy(
          id: id,
          name: name,
          category: category,
          description: desc,
          entryRule: entry,
          exitRule: exit,
          stopLossRule: stop,
          isActive: false,
          signalStrength: 0,
          strategyType: category == '短线' ? 'short' : 'long',
          entryPrice: last?.close ?? 0,
        ));
      }
    }
    return all;
  }

  /// 短线策略库（1-5天操作）
  static List<TradingStrategy> _buildShortTermStrategies(
      List<HistoryKline> data, List<SignalItem> signals) {
    final strategies = <TradingStrategy>[];
    final last = data.last;
    final prev = data[data.length - 2];

    // 1. KDJ超卖金叉（P1-11修复：原名称"超买"反了，条件是超卖区K<30）
    // v2.30: 增加中期趋势过滤 — 上升趋势或震荡市有效，下跌趋势中为陷阱
    final kdjMidTrendOk =
        last.ma10 > last.ma20 || (last.adx14 > 0 && last.adx14 < 20);
    if (last.k > last.d && prev.k <= prev.d && prev.k < 30 && kdjMidTrendOk) {
      strategies.add(TradingStrategy(
        id: 'kdj_short_buy',
        name: 'KDJ超卖金叉',
        category: '短线',
        description: 'KDJ在超卖区（K<30）形成金叉，短线反弹信号，适合1-3天操作',
        entryRule: 'K线上穿D线且K值<30，立即入场',
        exitRule: 'K值>80或K线下穿D线，立即离场',
        stopLossRule:
            '跌破入场价-1xATR(${(last.atr14 > 0 ? last.atr14.toStringAsFixed(2) : "3%")})',
        isActive: true,
        signalStrength: 75,
        strategyType: 'short',
        recommendedDuration: 3,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 2,
        minConfidence: 0.65,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['KDJ', 'RSI'],
        entryPrice: last.close,
        stopLossPrice: _calcATRStopLoss(last, 1.5, 'short'),
        targetPrice: _calcATRTarget(last, 2.0, 'short'),
      ));
    }

    // 2. MACD底背离短线
    // v2.30: 增加+DI趋势确认（近10日至少有+DI>-DI的天数）
    final diRising = _checkDiRecentTrend(data, 10, 0.5); // 近10日至少50%天数+DI>-DI
    final bottomDivergence = signals.any((s) => s.signal.contains('底背离'));
    if (bottomDivergence && last.macdDif > last.macdDea && diRising) {
      strategies.add(TradingStrategy(
        id: 'macd_short_divergence',
        name: 'MACD底背离短线',
        category: '短线',
        description: '股价创新低但MACD不创新低，下跌动能衰竭，短线反弹机会',
        entryRule: '底背离确认后，DIF开始拐头向上时入场',
        exitRule: 'DIF再次向下拐头或跌破入场价',
        stopLossRule: '跌破入场价-1xATR',
        isActive: true,
        signalStrength: 80,
        strategyType: 'short',
        recommendedDuration: 5,
        maxDrawdown: 0.06,
        consecutiveLossLimit: 3,
        minConfidence: 0.7,
        riskRewardRatio: 2.5,
        compatibleIndicators: ['MACD', 'RSI'],
        entryPrice: last.close,
        stopLossPrice: _calcATRStopLoss(last, 1.5, 'short'),
        targetPrice: _calcATRTarget(last, 2.0, 'short'),
      ));
    }

    // 3. 缩量回调
    // v2.30-review: 确保数据充足，避免 sublist RangeError
    final isUptrend = last.ma20 > 0 && last.close > last.ma20;
    final shrinkPullback = data.length >= 5 &&
        isUptrend &&
        data
                    .sublist(data.length - 5)
                    .map((d) => d.volume)
                    .reduce((a, b) => a + b) /
                5 <
            last.volMa5 * 0.7 &&
        last.close < prev.close;
    if (shrinkPullback) {
      strategies.add(TradingStrategy(
        id: 'shrink_pullback_short',
        name: '缩量回调',
        category: '短线',
        description: '上涨趋势中缩量回调，抛压减轻，短线逢低买入机会',
        entryRule: '量能萎缩至均量70%以下，股价回踩均线企稳',
        exitRule: '放量下跌或跌破MA20',
        stopLossRule: '跌破入场价-1xATR',
        isActive: true,
        signalStrength: 70,
        strategyType: 'short',
        recommendedDuration: 5,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 3,
        minConfidence: 0.6,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['MA', '量价'],
        entryPrice: last.close,
        stopLossPrice: _calcATRStopLoss(last, 1.5, 'short'),
        targetPrice: _calcATRTarget(last, 2.0, 'short'),
      ));
    }

    // 4. RSI超卖反弹
    // v2.30: 增加短期趋势过滤 — 股价在MA20上方时超卖反弹更可靠
    if (prev.rsi6 <= 30 && last.rsi6 > 30 && last.close > last.ma20) {
      strategies.add(TradingStrategy(
        id: 'rsi_oversold_short',
        name: 'RSI超卖反弹',
        category: '短线',
        description: 'RSI从超卖区回升突破30，短线反弹信号',
        entryRule: 'RSI6从30以下回升突破30',
        exitRule: 'RSI6>70或RSI6再次跌破50',
        stopLossRule: '跌破入场价-1xATR',
        isActive: true,
        signalStrength: 65,
        strategyType: 'short',
        recommendedDuration: 3,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 2,
        minConfidence: 0.6,
        riskRewardRatio: 1.8,
        compatibleIndicators: ['RSI'],
        entryPrice: last.close,
        stopLossPrice: _calcATRStopLoss(last, 1.5, 'short'),
        targetPrice: _calcATRTarget(last, 2.0, 'short'),
      ));
    }

    // 5. 均线突破
    // v2.30: 增加中期趋势过滤 — MA20 > MA60 时突破更可靠
    final midTrendOk = last.ma60 <= 0 || last.ma20 > last.ma60;
    if (last.close > last.ma5 && prev.close <= prev.ma5 && midTrendOk) {
      strategies.add(TradingStrategy(
        id: 'ma_breakout_short',
        name: '均线突破',
        category: '短线',
        description: '股价向上突破5日均线，短期走势转强',
        entryRule: '股价站上MA5',
        exitRule: '股价跌破MA5',
        stopLossRule: '跌破入场价-1xATR',
        isActive: true,
        signalStrength: 60,
        strategyType: 'short',
        recommendedDuration: 3,
        maxDrawdown: 0.04,
        consecutiveLossLimit: 2,
        minConfidence: 0.55,
        riskRewardRatio: 1.5,
        compatibleIndicators: ['MA'],
        entryPrice: last.close,
        stopLossPrice: _calcATRStopLoss(last, 1.5, 'short'),
        targetPrice: _calcATRTarget(last, 2.0, 'short'),
      ));
    }

    // 6. 放量突破
    // v2.30: 排除ADX<20缩量区（震荡市中放量常是假突破）
    final volBreakout = last.volume > last.volMa5 * 2 &&
        last.close > last.open &&
        (last.adx14 <= 0 || last.adx14 >= 20);
    if (volBreakout) {
      strategies.add(TradingStrategy(
        id: 'volume_breakout_short',
        name: '放量突破',
        category: '短线',
        description: '成交量放大至均量2倍以上，股价上涨，短线买入信号',
        entryRule: '量比>2且股价上涨',
        exitRule: '连续3日缩量或跌破突破日收盘价',
        stopLossRule: '跌破入场价-1xATR',
        isActive: true,
        signalStrength: 75,
        strategyType: 'short',
        recommendedDuration: 5,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 2,
        minConfidence: 0.65,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['量价', 'MA'],
        entryPrice: last.close,
        stopLossPrice: _calcATRStopLoss(last, 1.5, 'short'),
        targetPrice: _calcATRTarget(last, 2.0, 'short'),
      ));
    }

    return strategies;
  }

  /// 长线策略库（1-4周/1-3个月操作）
  static List<TradingStrategy> _buildLongTermStrategies(
      List<HistoryKline> data, List<SignalItem> signals) {
    final strategies = <TradingStrategy>[];
    final last = data.last;

    // 1. 均线多头排列
    final maMultiHead = last.ma5 > last.ma10 &&
        last.ma10 > last.ma20 &&
        last.ma20 > 0 &&
        (last.ma60 == 0 || last.ma20 > last.ma60);
    if (maMultiHead) {
      strategies.add(TradingStrategy(
        id: 'ma_multi_head_long',
        name: '均线多头排列',
        category: '长线',
        description: 'MA5>MA10>MA20>MA60，长期上升趋势，中线持股为主',
        entryRule: '多头排列形成后，股价回踩MA10附近企稳',
        exitRule: 'MA5下穿MA10或跌破MA20',
        stopLossRule: '跌破入场价-2xATR',
        isActive: true,
        signalStrength: 85,
        strategyType: 'long',
        recommendedDuration: 30,
        maxDrawdown: 0.08,
        consecutiveLossLimit: 4,
        minConfidence: 0.7,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['MA', 'MACD'],
        entryPrice: last.close,
        stopLossPrice: _calcATRStopLoss(last, 2.0, 'long'),
        targetPrice: _calcATRTarget(last, 3.0, 'long'),
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
        stopLossRule: '跌破入场价-2xATR',
        isActive: true,
        signalStrength: 90,
        strategyType: 'long',
        recommendedDuration: 45,
        maxDrawdown: 0.08,
        consecutiveLossLimit: 4,
        minConfidence: 0.75,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['MACD', 'MA'],
        entryPrice: last.close,
        stopLossPrice: _calcATRStopLoss(last, 2.0, 'long'),
        targetPrice: _calcATRTarget(last, 3.0, 'long'),
      ));
    }

    // 3. RSI中轨支撑
    if (last.ma5 > 0 &&
        last.close > last.ma10 &&
        last.rsi12 > 40 &&
        last.rsi12 < 60) {
      strategies.add(TradingStrategy(
        id: 'rsi_support_long',
        name: 'RSI中轨支撑',
        category: '长线',
        description: 'RSI在40-60区间运行，中轨附近企稳，长期持有',
        entryRule: 'RSI12在40-60区间，股价回踩MA10企稳',
        exitRule: 'RSI12>70或RSI12<30',
        stopLossRule: '跌破入场价-2xATR',
        isActive: true,
        signalStrength: 70,
        strategyType: 'long',
        recommendedDuration: 30,
        maxDrawdown: 0.06,
        consecutiveLossLimit: 3,
        minConfidence: 0.65,
        riskRewardRatio: 1.8,
        compatibleIndicators: ['RSI', 'MA'],
        entryPrice: last.close,
        stopLossPrice: _calcATRStopLoss(last, 2.0, 'long'),
        targetPrice: _calcATRTarget(last, 3.0, 'long'),
      ));
    }

    // 4. 布林带突破
    final bollBreakout =
        signals.any((s) => s.signal.contains('布林带') && s.signal.contains('突破'));
    if (bollBreakout && last.close > last.bollUpper) {
      strategies.add(TradingStrategy(
        id: 'boll_breakout_long',
        name: '布林带突破',
        category: '长线',
        description: '布林带收口后放量突破上轨，向上趋势确立，中线持有',
        entryRule: '布林带收口后放量突破上轨',
        exitRule: '股价回落至中轨下方',
        stopLossRule: '跌破入场价-2xATR',
        isActive: true,
        signalStrength: 80,
        strategyType: 'long',
        recommendedDuration: 30,
        maxDrawdown: 0.07,
        consecutiveLossLimit: 3,
        minConfidence: 0.7,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['BOLL', 'MACD'],
        entryPrice: last.close,
        stopLossPrice: _calcATRStopLoss(last, 2.0, 'long'),
        targetPrice: _calcATRTarget(last, 3.0, 'long'),
      ));
    }

    // 5. 趋势强度确认（ADX）— 必须同时确认方向（+DI > -DI）避免在下跌趋势中发出买入信号
    if (last.adx14 > 25 && last.plusDi14 > last.minusDi14) {
      strategies.add(TradingStrategy(
        id: 'adx_trend_long',
        name: '趋势强度确认',
        category: '长线',
        description: 'ADX>25，趋势明确，可顺势而为，长期持有',
        entryRule: 'ADX>25，趋势强度强劲',
        exitRule: 'ADX<20或趋势转弱',
        stopLossRule: '跌破入场价-2xATR',
        isActive: true,
        signalStrength: 75,
        strategyType: 'long',
        recommendedDuration: 45,
        maxDrawdown: 0.08,
        consecutiveLossLimit: 4,
        minConfidence: 0.75,
        riskRewardRatio: 1.8,
        compatibleIndicators: ['ADX', 'MA'],
        entryPrice: last.close,
        stopLossPrice: _calcATRStopLoss(last, 2.0, 'long'),
        targetPrice: _calcATRTarget(last, 3.0, 'long'),
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
        stopLossRule: '跌破入场价-2xATR',
        isActive: true,
        signalStrength: 85,
        strategyType: 'long',
        recommendedDuration: 20,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 3,
        minConfidence: 0.7,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['MA', 'MACD'],
        entryPrice: last.close,
        stopLossPrice: _calcATRStopLoss(last, 2.0, 'long'),
        targetPrice: _calcATRTarget(last, 3.0, 'long'),
      ));
    }

    return strategies;
  }

  /// 特殊策略（2-3种）
  static List<TradingStrategy> _buildSpecialStrategies(
      List<HistoryKline> data, List<SignalItem> signals) {
    final strategies = <TradingStrategy>[];
    if (data.length < 11) return strategies;
    final last = data.last;

    // 1. 缩量止跌
    final priceChange10d =
        (last.close / data[data.length - 11].close - 1) * 100;
    final recent3Change = (last.close / data[data.length - 4].close - 1) * 100;
    final avg3Vol = data
            .sublist(data.length - 3)
            .map((d) => d.volume)
            .reduce((a, b) => a + b) /
        3;
    final avg10Vol = data
            .sublist(data.length - 10)
            .map((d) => d.volume)
            .reduce((a, b) => a + b) /
        10;
    if (priceChange10d < -10 &&
        recent3Change.abs() < 1 &&
        avg3Vol < avg10Vol * 0.5) {
      strategies.add(TradingStrategy(
        id: 'volume_stop_drop',
        name: '缩量止跌',
        category: '特殊',
        description: '前期大幅下跌后量能萎缩，价格企稳，止跌信号',
        entryRule: '前期跌幅超10%后量能萎缩至均量50%以下，价格企稳',
        exitRule: '放量上涨或跌破企稳价位',
        stopLossRule: '跌破入场价-1.5xATR',
        isActive: true,
        signalStrength: 65,
        strategyType: 'both',
        recommendedDuration: 15,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 2,
        minConfidence: 0.6,
        riskRewardRatio: 1.8,
        compatibleIndicators: ['量价', 'MACD'],
        entryPrice: last.close,
        stopLossPrice: _calcATRStopLoss(last, 1.5, 'both'),
      ));
    }

    // v2.30: 防守/卖出策略

    // 2. MA20破位防守
    final prev = data[data.length - 2];
    if (last.ma20 > 0 &&
        prev.ma20 > 0 &&
        last.close < last.ma20 &&
        prev.close >= prev.ma20) {
      strategies.add(TradingStrategy(
        id: 'ma20_break_defense',
        name: 'MA20破位防守',
        category: '防守',
        description: '股价跌破MA20，趋势可能转弱，建议减仓至30%防守',
        entryRule: '收盘价跌破MA20时减仓防守',
        exitRule: '股价重新站回MA20',
        stopLossRule: '跌破入场价-1.5xATR',
        isActive: true,
        signalStrength: 70,
        strategyType: 'short',
        recommendedDuration: 5,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 2,
        minConfidence: 0.6,
        riskRewardRatio: 1.5,
        compatibleIndicators: ['MA'],
        entryPrice: last.close,
        stopLossPrice: _calcATRStopLoss(last, 1.5, 'short'),
      ));
    }

    // 3. 高位放量滞涨止盈
    double change20d = 0;
    if (data.length >= 21) {
      final close20ago = data[data.length - 21].close;
      if (close20ago > 0) change20d = (last.close / close20ago - 1) * 100;
    }
    final volSurge = last.volume > last.volMa5 * 2;
    final stallRise = last.changePct < 1;
    if (change20d > 20 && volSurge && stallRise) {
      strategies.add(TradingStrategy(
        id: 'high_volume_stall',
        name: '高位放量滞涨止盈',
        category: '防守',
        description: '大幅上涨后放量滞涨，主力派发信号，建议止盈',
        entryRule: '近20日涨>20%+放量但涨幅<1%',
        exitRule: '放量跌破MA10',
        stopLossRule: '跌破入场价-1.5xATR',
        isActive: true,
        signalStrength: 75,
        strategyType: 'short',
        recommendedDuration: 3,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 2,
        minConfidence: 0.65,
        riskRewardRatio: 1.5,
        compatibleIndicators: ['量价', 'MA'],
        entryPrice: last.close,
        stopLossPrice: _calcATRStopLoss(last, 1.5, 'short'),
      ));
    }

    // 4. 熊市清仓（大盘确认+个股破MA60）
    // 注意：此策略需要大盘数据，在没有大盘数据时不触发
    // 实际触发逻辑在 signal_engine.dart 中根据 marketContext 补充

    // P1-10修复：移除与短线#6重复的"放量突破"策略（原特殊版本条件、名称、类型完全相同）

    return strategies;
  }

  /// 返回全部13个战法的元数据（无需K线数据），用于战法说明页
  static List<TradingStrategy> getAllStrategyDefinitions() {
    return [
      // ── 短线策略（6个）──
      TradingStrategy(
        id: 'kdj_short_buy',
        name: 'KDJ超卖金叉',
        category: '短线',
        description: 'KDJ在超卖区（K<30）形成金叉，短线反弹信号，适合1-3天操作',
        entryRule: 'K线上穿D线且K值<30，立即入场',
        exitRule: 'K值>80或K线下穿D线，立即离场',
        stopLossRule: '跌破入场价-1.5xATR',
        isActive: false,
        signalStrength: 75,
        type: 'buy',
        strategyType: 'short',
        recommendedDuration: 3,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 2,
        minConfidence: 0.65,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['KDJ', 'RSI'],
      ),
      TradingStrategy(
        id: 'macd_short_divergence',
        name: 'MACD底背离短线',
        category: '短线',
        description: '股价创新低但MACD不创新低，下跌动能衰竭，短线反弹机会',
        entryRule: '底背离确认后，DIF开始拐头向上时入场',
        exitRule: 'DIF再次向下拐头或跌破入场价',
        stopLossRule: '跌破入场价-1.5xATR',
        isActive: false,
        signalStrength: 80,
        type: 'buy',
        strategyType: 'short',
        recommendedDuration: 5,
        maxDrawdown: 0.06,
        consecutiveLossLimit: 3,
        minConfidence: 0.70,
        riskRewardRatio: 2.5,
        compatibleIndicators: ['MACD', 'RSI'],
      ),
      TradingStrategy(
        id: 'shrink_pullback_short',
        name: '缩量回调',
        category: '短线',
        description: '上涨趋势中缩量回调，抛压减轻，短线逢低买入机会',
        entryRule: '量能萎缩至均量70%以下，股价回踩均线企稳',
        exitRule: '放量下跌或跌破MA20',
        stopLossRule: '跌破入场价-1.5xATR',
        isActive: false,
        signalStrength: 70,
        type: 'buy',
        strategyType: 'short',
        recommendedDuration: 5,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 3,
        minConfidence: 0.60,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['MA', '量价'],
      ),
      TradingStrategy(
        id: 'rsi_oversold_short',
        name: 'RSI超卖反弹',
        category: '短线',
        description: 'RSI从超卖区回升突破30，短线反弹信号',
        entryRule: 'RSI6从30以下回升突破30',
        exitRule: 'RSI6>70或RSI6再次跌破50',
        stopLossRule: '跌破入场价-1.5xATR',
        isActive: false,
        signalStrength: 65,
        type: 'buy',
        strategyType: 'short',
        recommendedDuration: 3,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 2,
        minConfidence: 0.60,
        riskRewardRatio: 1.8,
        compatibleIndicators: ['RSI'],
      ),
      TradingStrategy(
        id: 'ma_breakout_short',
        name: '均线突破',
        category: '短线',
        description: '股价向上突破5日均线，短期走势转强',
        entryRule: '股价站上MA5',
        exitRule: '股价跌破MA5',
        stopLossRule: '跌破入场价-1.5xATR',
        isActive: false,
        signalStrength: 60,
        type: 'buy',
        strategyType: 'short',
        recommendedDuration: 3,
        maxDrawdown: 0.04,
        consecutiveLossLimit: 2,
        minConfidence: 0.55,
        riskRewardRatio: 1.5,
        compatibleIndicators: ['MA'],
      ),
      TradingStrategy(
        id: 'volume_breakout_short',
        name: '放量突破',
        category: '短线',
        description: '成交量放大至均量2倍以上，股价上涨，短线买入信号',
        entryRule: '量比>2且股价上涨',
        exitRule: '连续3日缩量或跌破突破日收盘价',
        stopLossRule: '跌破入场价-1.5xATR',
        isActive: false,
        signalStrength: 75,
        type: 'buy',
        strategyType: 'short',
        recommendedDuration: 5,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 2,
        minConfidence: 0.65,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['量价', 'MA'],
      ),
      // ── 长线策略（6个）──
      TradingStrategy(
        id: 'ma_multi_head_long',
        name: '均线多头排列',
        category: '长线',
        description: 'MA5>MA10>MA20>MA60，长期上升趋势，中线持股为主',
        entryRule: '多头排列形成后，股价回踩MA10附近企稳',
        exitRule: 'MA5下穿MA10或跌破MA20',
        stopLossRule: '跌破入场价-2xATR',
        isActive: false,
        signalStrength: 85,
        type: 'buy',
        strategyType: 'long',
        recommendedDuration: 30,
        maxDrawdown: 0.08,
        consecutiveLossLimit: 4,
        minConfidence: 0.70,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['MA', 'MACD'],
      ),
      TradingStrategy(
        id: 'macd_zero_above_cross',
        name: 'MACD零轴上方金叉',
        category: '长线',
        description: 'MACD在零轴上方形成金叉，多头趋势强劲，中线持股为主',
        entryRule: 'MACD在零轴上方DIF上穿DEA',
        exitRule: 'MACD柱连续缩短3日或DIF下穿DEA',
        stopLossRule: '跌破入场价-2xATR',
        isActive: false,
        signalStrength: 90,
        type: 'buy',
        strategyType: 'long',
        recommendedDuration: 45,
        maxDrawdown: 0.08,
        consecutiveLossLimit: 4,
        minConfidence: 0.75,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['MACD', 'MA'],
      ),
      TradingStrategy(
        id: 'rsi_support_long',
        name: 'RSI中轨支撑',
        category: '长线',
        description: 'RSI在40-60区间运行，中轨附近企稳，长期持有',
        entryRule: 'RSI12在40-60区间，股价回踩MA10企稳',
        exitRule: 'RSI12>70或RSI12<30',
        stopLossRule: '跌破入场价-2xATR',
        isActive: false,
        signalStrength: 70,
        type: 'buy',
        strategyType: 'long',
        recommendedDuration: 30,
        maxDrawdown: 0.06,
        consecutiveLossLimit: 3,
        minConfidence: 0.65,
        riskRewardRatio: 1.8,
        compatibleIndicators: ['RSI', 'MA'],
      ),
      TradingStrategy(
        id: 'boll_breakout_long',
        name: '布林带突破',
        category: '长线',
        description: '布林带收口后放量突破上轨，向上趋势确立，中线持有',
        entryRule: '布林带收口后放量突破上轨',
        exitRule: '股价回落至中轨下方',
        stopLossRule: '跌破入场价-2xATR',
        isActive: false,
        signalStrength: 80,
        type: 'buy',
        strategyType: 'long',
        recommendedDuration: 30,
        maxDrawdown: 0.07,
        consecutiveLossLimit: 3,
        minConfidence: 0.70,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['BOLL', 'MACD'],
      ),
      TradingStrategy(
        id: 'adx_trend_long',
        name: '趋势强度确认',
        category: '长线',
        description: 'ADX>25且+DI>-DI，趋势明确，可顺势而为，长期持有',
        entryRule: 'ADX>25且+DI>-DI，趋势强度强劲',
        exitRule: 'ADX<20或趋势转弱',
        stopLossRule: '跌破入场价-2xATR',
        isActive: false,
        signalStrength: 75,
        type: 'buy',
        strategyType: 'long',
        recommendedDuration: 45,
        maxDrawdown: 0.08,
        consecutiveLossLimit: 4,
        minConfidence: 0.75,
        riskRewardRatio: 1.8,
        compatibleIndicators: ['ADX', 'MA'],
      ),
      TradingStrategy(
        id: 'breakout_pullback_confirm',
        name: '突破+回踩确认',
        category: '长线',
        description: '均线多头排列后回踩MA10企稳，最佳入场时机，中线持有',
        entryRule: '多头排列后回踩MA10附近不破',
        exitRule: 'MA5下穿MA10或跌破MA20',
        stopLossRule: '跌破入场价-2xATR',
        isActive: false,
        signalStrength: 85,
        type: 'buy',
        strategyType: 'long',
        recommendedDuration: 20,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 3,
        minConfidence: 0.70,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['MA', 'MACD'],
      ),
      // ── 特殊策略（1个）──
      TradingStrategy(
        id: 'volume_stop_drop',
        name: '缩量止跌',
        category: '特殊',
        description: '前期大幅下跌后量能萎缩，价格企稳，止跌信号',
        entryRule: '前期跌幅超10%后量能萎缩至均量50%以下，价格企稳',
        exitRule: '放量上涨或跌破企稳价位',
        stopLossRule: '跌破入场价-1.5xATR',
        isActive: false,
        signalStrength: 65,
        type: 'buy',
        strategyType: 'both',
        recommendedDuration: 15,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 2,
        minConfidence: 0.60,
        riskRewardRatio: 1.8,
        compatibleIndicators: ['量价', 'MACD'],
      ),
      // ── v2.30: 防守/卖出策略（4个）──
      TradingStrategy(
        id: 'ma20_break_defense',
        name: 'MA20破位防守',
        category: '防守',
        description: '股价跌破MA20，趋势可能转弱，建议减仓防守',
        entryRule: '收盘价跌破MA20，减仓至30%',
        exitRule: '股价站回MA20上方',
        stopLossRule: '跌破入场价-1.5xATR',
        isActive: false,
        signalStrength: 70,
        type: 'sell',
        strategyType: 'short',
        recommendedDuration: 5,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 2,
        minConfidence: 0.60,
        riskRewardRatio: 1.5,
        compatibleIndicators: ['MA'],
      ),
      TradingStrategy(
        id: 'high_volume_stall',
        name: '高位放量滞涨止盈',
        category: '防守',
        description: '大幅上涨后放量但涨幅收窄，主力派发信号，建议止盈',
        entryRule: '近20日涨幅>20%且当日放量(>2xMA5)但涨幅<1%',
        exitRule: '放量跌破MA10',
        stopLossRule: '跌破入场价-1.5xATR',
        isActive: false,
        signalStrength: 75,
        type: 'sell',
        strategyType: 'short',
        recommendedDuration: 3,
        maxDrawdown: 0.05,
        consecutiveLossLimit: 2,
        minConfidence: 0.65,
        riskRewardRatio: 1.5,
        compatibleIndicators: ['量价', 'MA'],
      ),
      TradingStrategy(
        id: 'sector_weakness_rotate',
        name: '板块转弱调仓',
        category: '防守',
        description: '行业板块转弱，个股跟随下行风险大，建议调仓',
        entryRule: '行业指数走弱+个股RSI<45',
        exitRule: '行业企稳或个股RSI回升',
        stopLossRule: '跌破入场价-2xATR',
        isActive: false,
        signalStrength: 60,
        type: 'sell',
        strategyType: 'long',
        recommendedDuration: 10,
        maxDrawdown: 0.08,
        consecutiveLossLimit: 3,
        minConfidence: 0.55,
        riskRewardRatio: 1.5,
        compatibleIndicators: ['RSI', 'MA'],
      ),
      TradingStrategy(
        id: 'bear_market_clear',
        name: '熊市清仓',
        category: '防守',
        description: '大盘持续走弱且个股破MA60，系统风险，建议清仓观望',
        entryRule: '大盘日均跌>2%+个股破MA60',
        exitRule: '大盘企稳+个股站回MA60',
        stopLossRule: '跌破入场价-2xATR',
        isActive: false,
        signalStrength: 85,
        type: 'sell',
        strategyType: 'long',
        recommendedDuration: 20,
        maxDrawdown: 0.10,
        consecutiveLossLimit: 2,
        minConfidence: 0.70,
        riskRewardRatio: 2.0,
        compatibleIndicators: ['MA', '市场'],
      ),
    ];
  }

  /// v2.30: 检查近期+DI趋势 — 近lookback日内至少ratio比例天数+DI>-DI
  static bool _checkDiRecentTrend(
      List<HistoryKline> data, int lookback, double ratio) {
    if (data.length < lookback + 1) return true; // 数据不足，不限制
    int diUpDays = 0;
    final start = data.length - lookback;
    for (int i = start; i < data.length; i++) {
      if (data[i].plusDi14 > 0 && data[i].plusDi14 > data[i].minusDi14) {
        diUpDays++;
      }
    }
    return diUpDays / lookback >= ratio;
  }
}
