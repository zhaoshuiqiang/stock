import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/stock_models.dart';
import 'indicators.dart';

// ═══════════════════════════════════════════════════════════════════
// 回测配置
// ═══════════════════════════════════════════════════════════════════

/// 回测配置 — 控制成本模型、涨跌停规则、数据校验开关
class BacktestConfig {
  /// 佣金费率（默认万2.5，双向）
  final double commissionRate;
  /// 印花税费率（默认千1，仅卖出）
  final double stampTaxRate;
  /// 过户费率（默认万分之0.2，双向）
  final double transferRate;
  /// 滑点估算（默认0.1%）
  final double slippageRate;
  /// 涨跌停幅度（默认10% 主板）
  final double limitPct;
  /// 是否扣除交易成本
  final bool deductCost;
  /// 是否跳过涨跌停不可执行的交易
  final bool skipLimitTrade;
  /// 是否跳过脏数据（停牌/一字板）
  final bool skipDirtyData;
  /// 最小佣金（元），低于此按此收取
  final double minCommission;

  const BacktestConfig({
    this.commissionRate = 0.00025,
    this.stampTaxRate = 0.001,
    this.transferRate = 0.00002,
    this.slippageRate = 0.001,
    this.limitPct = 0.10,
    this.deductCost = true,
    this.skipLimitTrade = true,
    this.skipDirtyData = true,
    this.minCommission = 5.0,
  });

  /// A股主板默认配置（±10%）
  static const aStock = BacktestConfig();

  /// 科创/创业板（±20%）
  static const chiNext = BacktestConfig(limitPct: 0.20);

  /// 旧版兼容模式（无成本、无限制）
  static const legacy = BacktestConfig(
    deductCost: false,
    skipLimitTrade: false,
    skipDirtyData: false,
  );

  /// 根据股票代码自动推断涨跌停幅度
  static double inferLimitPct(String? stockCode) {
    if (stockCode == null) return 0.10;
    if (stockCode.startsWith('688') || stockCode.startsWith('300')) return 0.20;
    if (stockCode.startsWith('8') || stockCode.startsWith('4')) return 0.30; // 北交所
    return 0.10; // 主板
  }

  factory BacktestConfig.forCode(String? stockCode) {
    return BacktestConfig(limitPct: inferLimitPct(stockCode));
  }

  /// 单边买入成本率
  double get buyCostRate => commissionRate + transferRate + slippageRate;
  /// 单边卖出成本率（含印花税）
  double get sellCostRate => commissionRate + stampTaxRate + transferRate + slippageRate;
  /// 往返总成本率
  double get roundTripCostRate => buyCostRate + sellCostRate;
}

// ═══════════════════════════════════════════════════════════════════
// K线数据校验工具
// ═══════════════════════════════════════════════════════════════════

class KlineValidator {
  /// 涨跌停价格（基于前日收盘价）
  static double limitUpPrice(double prevClose, double limitPct) => prevClose * (1 + limitPct);
  static double limitDownPrice(double prevClose, double limitPct) => prevClose * (1 - limitPct);

  /// 是否为涨停日 — 收盘价触及涨停价，买不进
  static bool isLimitUp(HistoryKline kline, HistoryKline prev, double limitPct) {
    final upPrice = limitUpPrice(prev.close, limitPct);
    // 收盘价/最高价接近涨停价即为涨停（容忍千分一误差）
    return kline.close >= upPrice * 0.999 || kline.high >= upPrice * 0.999;
  }

  /// 是否为跌停日 — 收[盘价触及跌停价，卖不出
  static bool isLimitDown(HistoryKline kline, HistoryKline prev, double limitPct) {
    final downPrice = limitDownPrice(prev.close, limitPct);
    return kline.close <= downPrice * 1.001 || kline.low <= downPrice * 1.001;
  }

  /// 开盘即封板 — 开盘价直接涨停/跌停，全天无法交易
  static bool isOpenAtLimit(HistoryKline kline, HistoryKline prev, double limitPct) {
    final upPrice = limitUpPrice(prev.close, limitPct);
    final downPrice = limitDownPrice(prev.close, limitPct);
    return kline.open >= upPrice * 0.999 || kline.open <= downPrice * 1.001;
  }

  /// 一字板 — open==high==low==close 且封板
  static bool isYiZiBan(HistoryKline kline, HistoryKline prev, double limitPct) {
    if (prev.close <= 0) return false;
    final isFlat = kline.open == kline.high &&
        kline.high == kline.low &&
        kline.low == kline.close;
    if (!isFlat) return false;
    final chgPct = (kline.close - prev.close) / prev.close;
    return chgPct.abs() >= limitPct - 0.005;
  }

  /// 疑似停牌 — 连续无交易量的静止K线
  static bool isSuspension(HistoryKline kline, HistoryKline prev) {
    // 成交量几乎为0 或 价格完全不变且成交量极低
    if (kline.volume <= 0) return true;
    if (kline.volume < 100 &&
        kline.open == prev.close &&
        kline.high == kline.open &&
        kline.low == kline.open &&
        kline.close == kline.open) {
      return true;
    }
    return false;
  }

  /// 是否为脏数据（停牌、一字板、异常跳变）
  static bool isDirty(HistoryKline kline, HistoryKline prev, double limitPct) {
    if (isSuspension(kline, prev)) return true;
    if (isYiZiBan(kline, prev, limitPct)) return true;
    // 单日涨跌幅超过涨跌停限制（可能是数据错误或除权未复权）
    if (prev.close > 0 &&
        (kline.close - prev.close).abs() / prev.close > limitPct + 0.02) {
      return true;
    }
    return false;
  }

  /// 检测数据是否经过前复权处理
  /// 通过检查涨跌幅一致性来判断：原始数据的 changePct 应等于 (close-preClose)/preClose
  static bool checkForwardAdjusted(List<HistoryKline> data) {
    if (data.length < 20) return true; // 数据太少，无法判断，假设已复权
    final sampleSize = (data.length * 0.3).toInt().clamp(10, 50);
    int mismatchCount = 0;
    for (int i = data.length - sampleSize; i < data.length - 1; i++) {
      final today = data[i];
      final yesterday = data[i - 1];
      if (yesterday.close <= 0) continue;
      final calcChgPct = (today.close - yesterday.close) / yesterday.close * 100;
      final diff = (calcChgPct - today.changePct).abs();
      // 如果计算值和API返回值差异超过 1%，说明可能未复权
      if (diff > 1.0 && today.changePct.abs() < 10) {
        mismatchCount++;
      }
    }
    // 超过 20% 的样本不一致 -> 大概率未复权
    return mismatchCount / sampleSize <= 0.2;
  }
}

// ═══════════════════════════════════════════════════════════════════
// 回测校验元数据
// ═══════════════════════════════════════════════════════════════════

/// 回测校验过程的元数据
class BacktestValidationMeta {
  final bool lookAheadSafe;           // 前视偏差安全（T+1执行）
  final bool limitSimulated;          // 涨跌停模拟已启用
  final bool costDeducted;            // 交易成本已扣除
  final bool forwardAdjusted;         // 数据确认前复权
  final bool dirtySkipped;            // 脏数据已跳过
  final int skippedSignals;           // 因校验跳过的信号数
  final int skippedTrades;            // 因涨跌停跳过的交易数
  final List<String> warnings;        // 警告信息

  BacktestValidationMeta({
    this.lookAheadSafe = false,
    this.limitSimulated = false,
    this.costDeducted = false,
    this.forwardAdjusted = true,
    this.dirtySkipped = false,
    this.skippedSignals = 0,
    this.skippedTrades = 0,
    this.warnings = const [],
  });

  BacktestValidationMeta copyWith({
    bool? lookAheadSafe,
    bool? limitSimulated,
    bool? costDeducted,
    bool? forwardAdjusted,
    bool? dirtySkipped,
    int? skippedSignals,
    int? skippedTrades,
    List<String>? warnings,
  }) {
    return BacktestValidationMeta(
      lookAheadSafe: lookAheadSafe ?? this.lookAheadSafe,
      limitSimulated: limitSimulated ?? this.limitSimulated,
      costDeducted: costDeducted ?? this.costDeducted,
      forwardAdjusted: forwardAdjusted ?? this.forwardAdjusted,
      dirtySkipped: dirtySkipped ?? this.dirtySkipped,
      skippedSignals: skippedSignals ?? this.skippedSignals,
      skippedTrades: skippedTrades ?? this.skippedTrades,
      warnings: warnings ?? this.warnings,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 回测结果
// ═══════════════════════════════════════════════════════════════════

/// 回测结果
class BacktestResult {
  final int totalSignals;
  final int winningTrades;
  final int losingTrades;
  final double winRate;
  final double avgWinPct;
  final double avgLossPct;
  final double profitFactor;
  final double maxDrawdown;
  final double totalReturn;
  final List<double> tradeReturns;
  /// 新增：校验元数据
  final BacktestValidationMeta? validationMeta;
  /// Sharpe 比率（年化，基于逐笔交易收益率）
  final double? sharpeRatio;
  /// Calmar 比率（年化收益率 / 最大回撤）
  final double? calmarRatio;

  BacktestResult({
    required this.totalSignals,
    required this.winningTrades,
    required this.losingTrades,
    required this.winRate,
    required this.avgWinPct,
    required this.avgLossPct,
    required this.profitFactor,
    required this.maxDrawdown,
    required this.totalReturn,
    required this.tradeReturns,
    this.validationMeta,
    this.sharpeRatio,
    this.calmarRatio,
  });

  factory BacktestResult.fromJson(Map<String, dynamic> json) {
    return BacktestResult(
      totalSignals: json['total_signals'] ?? 0,
      winningTrades: json['winning_trades'] ?? 0,
      losingTrades: json['losing_trades'] ?? 0,
      winRate: (json['win_rate'] as num?)?.toDouble() ?? 0,
      avgWinPct: (json['avg_win_pct'] as num?)?.toDouble() ?? 0,
      avgLossPct: (json['avg_loss_pct'] as num?)?.toDouble() ?? 0,
      profitFactor: (json['profit_factor'] as num?)?.toDouble() ?? 0,
      maxDrawdown: (json['max_drawdown'] as num?)?.toDouble() ?? 0,
      totalReturn: (json['total_return'] as num?)?.toDouble() ?? 0,
      tradeReturns: (json['trade_returns'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [],
      sharpeRatio: (json['sharpe_ratio'] as num?)?.toDouble(),
      calmarRatio: (json['calmar_ratio'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_signals': totalSignals,
      'winning_trades': winningTrades,
      'losing_trades': losingTrades,
      'win_rate': winRate,
      'avg_win_pct': avgWinPct,
      'avg_loss_pct': avgLossPct,
      'profit_factor': profitFactor,
      'max_drawdown': maxDrawdown,
      'total_return': totalReturn,
      'trade_returns': tradeReturns,
      if (sharpeRatio != null) 'sharpe_ratio': sharpeRatio,
      if (calmarRatio != null) 'calmar_ratio': calmarRatio,
    };
  }
}

// ═══════════════════════════════════════════════════════════════════
// Walk-Forward 分析结果
// ═══════════════════════════════════════════════════════════════════

class WalkForwardResult {
  final int totalWindows;
  final int passedWindows;
  final double inSampleAvgReturn;
  final double outOfSampleAvgReturn;
  final double windowStdDev;          // 各窗口OOS收益的标准差 (pp)
  final List<double> windowReturns;   // 各窗口OOS收益率
  final bool isOverfit;
  final String verdict;

  WalkForwardResult({
    required this.totalWindows,
    required this.passedWindows,
    required this.inSampleAvgReturn,
    required this.outOfSampleAvgReturn,
    required this.windowStdDev,
    required this.windowReturns,
    required this.isOverfit,
    required this.verdict,
  });
}

// ═══════════════════════════════════════════════════════════════════
// 回测引擎
// ═══════════════════════════════════════════════════════════════════

class BacktestEngine {
  /// 全局默认配置（可通过 setConfig 修改）
  static BacktestConfig config = BacktestConfig.aStock;

  // ═══════════════════════════════════════════════════════════
  // 配置
  // �══════════════════════════════════════════════════════════

  static void setConfig(BacktestConfig cfg) {
    config = cfg;
  }

  // ═══════════════════════════════════════════════════════════
  // 通用回测执行器 — 消除 6 个策略的重复代码
  // ═══════════════════════════════════════════════════════════
  //
  // 核心修正：
  //   P0-1 前视偏差：T日信号 → T+1日 open 价执行
  //   P0-2 涨跌停：买入跳过涨停日，卖出跳过跌停日
  //   P1-3 交易成本：扣除佣金 + 印花税 + 滑点
  //   P1-5 脏数据：跳过停牌/一字板
  //
  // 已知局限：
  //   - 脏数据跳过仅阻止当日交易，但已预计算的指标（MA/MACD等）
  //     仍受脏数据日价格影响，可能污染后续日的信号判断。
  //     这是预计算架构的固有取舍——如需完全隔离需在循环内重算指标。
  //
  // 参数：
  //   [data]  K线数据
  //   [minBars] 最小K线数要求
  //   [prepare] 指标计算函数
  //   [isEntry] 入场信号判断 (prev, curr) -> bool
  //   [isExit]  出场信号判断 (prev, curr) -> bool
  //   [atrMultiplier] ATR止损倍数，0 = 不启用ATR止损
  //

  static BacktestResult _runGenericBacktest({
    required List<HistoryKline> data,
    required int minBars,
    required List<HistoryKline> Function(List<HistoryKline>) prepare,
    required bool Function(HistoryKline prev, HistoryKline curr) isEntry,
    required bool Function(HistoryKline prev, HistoryKline curr) isExit,
    double atrMultiplier = 0.0,
  }) {
    if (data.length < minBars) return _emptyResult();

    final calcData = prepare(List<HistoryKline>.from(data));
    if (calcData.length < minBars) return _emptyResult();

    final tradeReturns = <double>[];
    double? buyPrice;
    double peakCloseSinceEntry = 0; // P1-7: 持仓期间最高收盘价，用于追踪止损
    double peakEquity = 1.0;
    double currentEquity = 1.0;
    double maxDrawdown = 0;
    int skippedSignals = 0;
    int skippedTrades = 0;

    // T+1 执行修正：遍历到 length-2，因为需要 i+1 (next day) 来执行
    for (int i = 1; i < calcData.length - 1; i++) {
      final prev = calcData[i - 1];
      final curr = calcData[i];
      final next = calcData[i + 1]; // T+1 执行日

      // ---- 脏数据跳过 ----
      if (config.skipDirtyData && KlineValidator.isDirty(curr, prev, config.limitPct)) {
        skippedSignals++;
        continue;
      }

      // ---- 入场信号 ----
      if (isEntry(prev, curr) && buyPrice == null) {
        // 检查 T+1 执行日是否能买入（非涨停/非开盘即封板）
        if (config.skipLimitTrade &&
            (KlineValidator.isLimitUp(next, curr, config.limitPct) ||
             KlineValidator.isOpenAtLimit(next, curr, config.limitPct))) {
          skippedTrades++;
          continue; // 买入失败，跳过此信号
        }
        buyPrice = next.open; // ← T+1 开盘价执行
        peakCloseSinceEntry = next.open; // P1-7: 初始化持仓最高价
        continue;
      }

      // P1-8: 持仓时每根K线更新权益回撤（捕捉日内最大回撤）
      if (buyPrice != null) {
        if (curr.close > peakCloseSinceEntry) peakCloseSinceEntry = curr.close;
        // 用当前收盘价计算浮盈权益，更新回撤
        final unrealizedEquity = currentEquity * (1 + _safeReturnPct(buyPrice, curr.close));
        if (unrealizedEquity > peakEquity) peakEquity = unrealizedEquity;
        final floatingDd = (peakEquity - unrealizedEquity) / peakEquity;
        if (floatingDd > maxDrawdown) maxDrawdown = floatingDd;
      }

      // ---- 出场信号（仅持仓时） ----
      if (isExit(prev, curr) && buyPrice != null) {
        // 检查 T+1 执行日是否能卖出（非跌停）
        if (config.skipLimitTrade &&
            KlineValidator.isLimitDown(next, curr, config.limitPct)) {
          skippedTrades++;
          // 不出场，继续持有（等下一个可卖出日）
          continue;
        }
        // 内联平仓逻辑
        final returnPct = _safeReturnPct(buyPrice, next.open); // ← T+1 开盘价执行
        final netReturn = _applyCost(returnPct);
        tradeReturns.add(netReturn);
        currentEquity *= (1 + netReturn);
        if (currentEquity > peakEquity) peakEquity = currentEquity;
        final dd = (peakEquity - currentEquity) / peakEquity;
        if (dd > maxDrawdown) maxDrawdown = dd;
        buyPrice = null;
        continue;
      }

      // ---- ATR 止损（持仓时） ----
      // P1-7修复：追踪止损，锚定持仓期间最高收盘价而非固定buyPrice
      // ATR扩大时止损上移（趋近peakClose），风险管理正确收紧
      if (buyPrice != null && atrMultiplier > 0 && curr.atr14 > 0) {
        final atrStop = peakCloseSinceEntry - curr.atr14 * atrMultiplier;
        if (curr.low <= atrStop) {
          // 跌停日无法止损卖出
          if (config.skipLimitTrade &&
              KlineValidator.isLimitDown(curr, prev, config.limitPct)) {
            skippedTrades++;
            continue;
          }
          final sellPrice = atrStop;
          final returnPct = _safeReturnPct(buyPrice, sellPrice);
          final netReturn = _applyCost(returnPct);
          tradeReturns.add(netReturn);
          currentEquity *= (1 + netReturn);
          if (currentEquity > peakEquity) peakEquity = currentEquity;
          final dd = (peakEquity - currentEquity) / peakEquity;
          if (dd > maxDrawdown) maxDrawdown = dd;
          buyPrice = null;
          continue;
        }
      }
    }

    // 仍有持仓 → 按最后一天收盘价平仓
    if (buyPrice != null) {
      final last = calcData.last;
      final returnPct = _safeReturnPct(buyPrice, last.close);
      final netReturn = _applyCost(returnPct);
      tradeReturns.add(netReturn);
      currentEquity *= (1 + netReturn);
      if (currentEquity > peakEquity) peakEquity = currentEquity;
      final dd = (peakEquity - currentEquity) / peakEquity;
      if (dd > maxDrawdown) maxDrawdown = dd;
    }

    final result = _buildResult(tradeReturns, currentEquity, maxDrawdown);

    // 计算风险指标（Sharpe / Calmar）
    final (sharpe, _, calmar) = _calculateRiskMetrics(tradeReturns);

    // 附加校验元数据
    final warnings = <String>[];
    if (!KlineValidator.checkForwardAdjusted(calcData)) {
      warnings.add('数据可能未前复权，建议使用前复权K线数据');
    }

    return BacktestResult(
      totalSignals: result.totalSignals,
      winningTrades: result.winningTrades,
      losingTrades: result.losingTrades,
      winRate: result.winRate,
      avgWinPct: result.avgWinPct,
      avgLossPct: result.avgLossPct,
      profitFactor: result.profitFactor,
      maxDrawdown: result.maxDrawdown,
      totalReturn: result.totalReturn,
      tradeReturns: result.tradeReturns,
      sharpeRatio: sharpe,
      calmarRatio: calmar,
      validationMeta: BacktestValidationMeta(
        lookAheadSafe: true,
        limitSimulated: config.skipLimitTrade,
        costDeducted: config.deductCost,
        forwardAdjusted: warnings.isEmpty,
        dirtySkipped: config.skipDirtyData,
        skippedSignals: skippedSignals,
        skippedTrades: skippedTrades,
        warnings: warnings,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 各策略方法（薄封装）
  // ═══════════════════════════════════════════════════════════

  /// MACD金叉买入 / MACD死叉卖出
  static BacktestResult backtestMACDCross(List<HistoryKline> data) {
    return _runGenericBacktest(
      data: data,
      minBars: 60,
      prepare: (d) => calcMACD(d),
      isEntry: (p, c) => c.macdDif > c.macdDea && p.macdDif <= p.macdDea,
      isExit: (p, c) => c.macdDif < c.macdDea && p.macdDif >= p.macdDea,
    );
  }

  /// MA5上穿MA10 金叉策略
  static BacktestResult backtestMACross(List<HistoryKline> data) {
    return _runGenericBacktest(
      data: data,
      minBars: 30,
      prepare: (d) => calcMA(d, [5, 10]),
      isEntry: (p, c) => c.ma5 > c.ma10 && p.ma5 <= p.ma10,
      isExit: (p, c) => c.ma5 < c.ma10 && p.ma5 >= p.ma10,
    );
  }

  /// KDJ超卖金叉回测（KDJ<30区域K上穿D买入，死叉卖出/ATR止损）
  static BacktestResult backtestKDJOversoldCross(List<HistoryKline> data) {
    if (data.length < 30) return _emptyResult();

    var calcData = calcKDJ(List<HistoryKline>.from(data));
    calcData = calcATR(calcData);
    if (calcData.length < 30) return _emptyResult();

    return _runGenericBacktest(
      data: data,
      minBars: 30,
      prepare: (d) {
        var r = calcKDJ(List<HistoryKline>.from(d));
        return calcATR(r);
      },
      isEntry: (p, c) => c.k > c.d && p.k <= p.d && p.k < 30,
      isExit: (p, c) => c.k < c.d && p.k >= p.d,
      atrMultiplier: 1.0,
    );
  }

  /// RSI超卖反弹回测（RSI6≤30反弹买入，RSI6<50卖出）
  static BacktestResult backtestRSIOversoldRecovery(List<HistoryKline> data) {
    return _runGenericBacktest(
      data: data,
      minBars: 30,
      prepare: (d) {
        var r = calcRSI(d, [6]);
        return calcATR(r);
      },
      isEntry: (p, c) => p.rsi6 <= 30 && c.rsi6 > 30,
      isExit: (p, c) => c.rsi6 < 50 && p.rsi6 >= 50,
      atrMultiplier: 1.0,
    );
  }

  /// 布林带下轨支撑回测（触及下轨反弹买入，回到中轨卖出）
  static BacktestResult backtestBollSupport(List<HistoryKline> data) {
    return _runGenericBacktest(
      data: data,
      minBars: 30,
      prepare: (d) {
        var r = calcBOLL(d);
        return calcATR(r);
      },
      isEntry: (p, c) => c.bollLower > 0 && c.low <= c.bollLower * 1.005 && c.close > c.bollLower,
      isExit: (p, c) => c.bollMid > 0 && c.close > c.bollMid,
      atrMultiplier: 1.5,
    );
  }

  /// 均线多头排列回测（MA5>MA10>MA20形成多头排列买入，MA5下破MA10卖出）
  static BacktestResult backtestMAMultiHead(List<HistoryKline> data) {
    return _runGenericBacktest(
      data: data,
      minBars: 30,
      prepare: (d) {
        var r = calcMA(d, [5, 10, 20]);
        return calcATR(r);
      },
      isEntry: (p, c) {
        final head = c.ma5 > c.ma10 && c.ma10 > c.ma20 && c.ma20 > 0;
        final prevHead = p.ma5 > p.ma10 && p.ma10 > p.ma20 && p.ma20 > 0;
        return head && !prevHead;
      },
      isExit: (p, c) => c.ma5 < c.ma10 && p.ma5 >= p.ma10,
      atrMultiplier: 1.5,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 交易成本计算
  // ═══════════════════════════════════════════════════════════

  /// 扣除交易成本后的净收益率（乘法模型）
  /// netReturn = (1 + grossReturn) × (1 - costRate) - 1
  /// 比减法模型更精确：成本等比缩放收益，而非固定扣除
  static double _applyCost(double grossReturn) {
    if (!config.deductCost) return grossReturn;
    return (1 + grossReturn) * (1 - config.roundTripCostRate) - 1;
  }

  // ═══════════════════════════════════════════════════════════
  // 综合回测与策略评估
  // ═══════════════════════════════════════════════════════════

  /// 全策略回测
  static Map<String, BacktestResult> megaBacktest(List<HistoryKline> data) {
    if (data.length < 60) return {};

    final results = <String, BacktestResult>{};
    try { results['MACD交叉'] = backtestMACDCross(data); } catch (e) { debugPrint('[回测] MACD交叉策略失败: $e'); }
    try { results['MA金叉'] = backtestMACross(data); } catch (e) { debugPrint('[回测] MA金叉策略失败: $e'); }
    try { results['KDJ超卖'] = backtestKDJOversoldCross(data); } catch (e) { debugPrint('[回测] KDJ超卖策略失败: $e'); }
    try { results['RSI超卖'] = backtestRSIOversoldRecovery(data); } catch (e) { debugPrint('[回测] RSI超卖策略失败: $e'); }
    try { results['布林支撑'] = backtestBollSupport(data); } catch (e) { debugPrint('[回测] 布林支撑策略失败: $e'); }
    try { results['均线多头'] = backtestMAMultiHead(data); } catch (e) { debugPrint('[回测] 均线多头策略失败: $e'); }
    try { results['锤子线反转'] = backtestHammerReversal(data); } catch (e) { debugPrint('[回测] 锤子线反转策略失败: $e'); }
    try { results['阳包阴'] = backtestBullishEngulfing(data); } catch (e) { debugPrint('[回测] 阳包阴策略失败: $e'); }
    try { results['阴包阳'] = backtestBearishEngulfing(data); } catch (e) { debugPrint('[回测] 阴包阳策略失败: $e'); }
    try { results['刺透形态'] = backtestPiercingPattern(data); } catch (e) { debugPrint('[回测] 刺透形态策略失败: $e'); }
    try { results['乌云盖顶'] = backtestDarkCloudCover(data); } catch (e) { debugPrint('[回测] 乌云盖顶策略失败: $e'); }
    try { results['启明星'] = backtestMorningStar(data); } catch (e) { debugPrint('[回测] 启明星策略失败: $e'); }
    try { results['黄昏星'] = backtestEveningStar(data); } catch (e) { debugPrint('[回测] 黄昏星策略失败: $e'); }
    try { results['十字星反转'] = backtestDojiReversal(data); } catch (e) { debugPrint('[回测] 十字星反转策略失败: $e'); }
    try { results['向上跳空'] = backtestGapUpBuy(data); } catch (e) { debugPrint('[回测] 向上跳空策略失败: $e'); }
    try { results['向下跳空回补'] = backtestGapDownFill(data); } catch (e) { debugPrint('[回测] 向下跳空回补策略失败: $e'); }
    try { results['WR超卖'] = backtestWROversold(data); } catch (e) { debugPrint('[回测] WR超卖策略失败: $e'); }
    try { results['CCI超卖'] = backtestCCIOversold(data); } catch (e) { debugPrint('[回测] CCI超卖策略失败: $e'); }
    try { results['CCI突破'] = backtestCCIBreakout(data); } catch (e) { debugPrint('[回测] CCI突破策略失败: $e'); }

    return results;
  }

  // ═══════════════════════════════════════════════════════════
  // P2-6: Walk-Forward 滚动窗口回测（过度拟合检测）
  // ═══════════════════════════════════════════════════════════

  /// Walk-Forward 滚动窗口回测
  ///
  /// 将数据分割为多个滚动窗口，每窗口用前N日训练（样本内），后M日测试（样本外��。
  /// 如果 OOS 收益远小于 IS 收益，或分年标准差过大 → 疑似过拟合
  static WalkForwardResult walkForwardBacktest(
    List<HistoryKline> data, {
    int windowSize = 120,   // 每窗口样本内天数
    int testSize = 60,      // 每窗口样本外天数（须≥60以支持megaBacktest最小数据量）
  }) {
    if (data.length < windowSize + testSize) {
      return WalkForwardResult(
        totalWindows: 0, passedWindows: 0,
        inSampleAvgReturn: 0, outOfSampleAvgReturn: 0,
        windowStdDev: 0, windowReturns: [],
        isOverfit: false, verdict: '数据不足，无法进行Walk-Forward分析(需≥${windowSize + testSize}根K线)',
      );
    }

    final windowReturns = <double>[];
    double totalIsReturn = 0;
    double totalOosReturn = 0;
    int windowCount = 0;
    int passedWindows = 0;

    // 滚动窗口
    for (int start = 0; start + windowSize + testSize <= data.length; start += testSize) {
      windowCount++;
      final isData = data.sublist(start, start + windowSize);
      final oosData = data.sublist(start + windowSize, start + windowSize + testSize);

      final isResults = megaBacktest(isData);
      if (isResults.isEmpty) continue;
      // IS：找出样本内表现最佳的策略（totalSignals≥3）
      String? isBestStrategyName;
      double isBestReturn = -double.infinity;
      for (final entry in isResults.entries) {
        if (entry.value.totalSignals >= 3 && entry.value.totalReturn > isBestReturn) {
          isBestReturn = entry.value.totalReturn;
          isBestStrategyName = entry.key;
        }
      }
      if (isBestStrategyName == null) continue;

      final oosResults = megaBacktest(oosData);
      if (oosResults.isEmpty) continue;
      // OOS：评估同一个策略在样本外的表现（与 IS 对称比较）
      // 若该策略在 OOS 无信号，记为 0（策略不适用）
      final oosSameStrategy = oosResults[isBestStrategyName];
      final oosReturn = (oosSameStrategy != null && oosSameStrategy.totalSignals > 0)
          ? oosSameStrategy.totalReturn
          : 0.0;

      totalIsReturn += isBestReturn;
      totalOosReturn += oosReturn;
      windowReturns.add(oosReturn);
      if (oosReturn > 0) passedWindows++;
    }

    if (windowCount == 0) {
      return WalkForwardResult(
        totalWindows: 0, passedWindows: 0,
        inSampleAvgReturn: 0, outOfSampleAvgReturn: 0,
        windowStdDev: 0, windowReturns: [],
        isOverfit: false, verdict: 'Walk-Forward分析���败',
      );
    }

    final isAvg = totalIsReturn / windowCount;
    final oosAvg = totalOosReturn / windowCount;
    final oosStd = _calcStdDev(windowReturns);

    // 过拟合判断：
    // 1. 样本外收益显著低于样本内（IS/OOS > 3 倍）
    // 2. 分年标准差过大（> 2pp，表示表现不稳定）
    final overfitRatio = isAvg > 0 && oosAvg > 0 ? isAvg / oosAvg : (isAvg > 0 ? 999.0 : 0);
    final isOverfit = overfitRatio > 3.0 || oosStd > 2.0;

    String verdict;
    if (isOverfit && overfitRatio > 3.0) {
      verdict = '疑似过拟合：样本内收益(${isAvg.toStringAsFixed(1)}%)远超样本外(${oosAvg.toStringAsFixed(1)}%)，策略泛化能力不足';
    } else if (isOverfit && oosStd > 2.0) {
      verdict = '疑似过拟合：分年标准差${oosStd.toStringAsFixed(2)}pp过大，策略表现不稳定';
    } else if (oosAvg < 0) {
      verdict = '策略样本外表现不佳(${oosAvg.toStringAsFixed(1)}%)，建议优化信号条件';
    } else {
      verdict = '策略稳健：样本内${isAvg.toStringAsFixed(1)}% / 样本外${oosAvg.toStringAsFixed(1)}%，分年标准差${oosStd.toStringAsFixed(2)}pp';
    }

    return WalkForwardResult(
      totalWindows: windowCount,
      passedWindows: passedWindows,
      inSampleAvgReturn: isAvg,
      outOfSampleAvgReturn: oosAvg,
      windowStdDev: oosStd,
      windowReturns: windowReturns,
      isOverfit: isOverfit,
      verdict: verdict,
    );
  }

  static double _calcStdDev(List<double> values) {
    if (values.length < 2) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / values.length;
    return sqrt(variance);
  }

  /// 分年绩效分析（用于过度拟合检测）
  static Map<int, double> yearlyPerformance(List<HistoryKline> data) {
    final yearly = <int, List<double>>{};
    for (final k in data) {
      final year = k.date.year;
      yearly.putIfAbsent(year, () => []);
      yearly[year]!.add(k.close);
    }

    final result = <int, double>{};
    for (final entry in yearly.entries) {
      final prices = entry.value;
      if (prices.length < 2) continue;
      result[entry.key] = (prices.last - prices.first) / prices.first * 100;
    }
    return result;
  }

  // ═══════════════════════════════════════════════════════════
  // 仓位管理校验（P2-7: 马丁加仓检测）
  // ═══════════════════════════════════════════════════════════

  /// 仓位分析 — 检测是否存在马丁加仓（逐笔加仓）行为
  static String positionAnalysis(Map<String, BacktestResult> results) {
    final buf = StringBuffer();
    for (final entry in results.entries) {
      final trades = entry.value.tradeReturns;
      if (trades.length < 5) continue;

      // 检测连续亏损加仓模式
      int consecutiveLosses = 0;
      int maxConsecutiveLoss = 0;
      bool martingaleWarning = false;
      double? prevLoss;
      for (final r in trades) {
        if (r < 0) {
          consecutiveLosses++;
          if (consecutiveLosses > maxConsecutiveLoss) {
            maxConsecutiveLoss = consecutiveLosses;
          }
          // 连续亏损且亏损幅度递增 → 疑似马丁
          if (prevLoss != null && r.abs() > prevLoss.abs() * 1.5) {
            martingaleWarning = true;
          }
          prevLoss = r;
        } else {
          consecutiveLosses = 0;
          prevLoss = null;
        }
      }

      if (martingaleWarning) {
        buf.writeln('${entry.key}: 警告—疑似马丁加仓模式（连续亏损幅度递增）');
      }
      if (maxConsecutiveLoss >= 4) {
        buf.writeln('${entry.key}: 最大连续亏损$maxConsecutiveLoss次，需关注风险控制');
      }
    }
    if (buf.isEmpty) buf.write('仓位管理正常：未检测到马丁加仓模式');
    return buf.toString();
  }

  // ═══════════════════════════════════════════════════════════
  // 回测校验报告（输出类似截图中的验证列表）
  // ═══════════════════════════════════════════════════════════

  /// 生成回测校验报告
  static String validationReport(Map<String, BacktestResult> results, {
    WalkForwardResult? wfResult,
    String? stockCode,
    List<HistoryKline>? rawData,
  }) {
    if (results.isEmpty) return '无回测数据，无法生成校验报告';

    // 从任一结果中获取元数据
    final meta = results.values.first.validationMeta;
    final isAdjusted = rawData != null ? KlineValidator.checkForwardAdjusted(rawData) : (meta?.forwardAdjusted ?? true);

    final buf = StringBuffer();
    buf.writeln('════════════ 回测校验报告 ════════════');

    // 01 未来函数
    if (meta?.lookAheadSafe == true) {
      buf.writeln('✔ 未来函数  | 特征使用T日收盘数据，目标使用T+1日开盘执行');
    } else {
      buf.writeln('✘ 未来函数  | 警告：可能使用了未来数据');
    }

    // 02 马丁加仓
    if (results.values.any((r) => r.tradeReturns.length >= 5)) {
      final pos = positionAnalysis(results);
      if (pos.contains('正常')) {
        buf.writeln('✔ 马丁加仓  | 静态仓位管理，未检测到马丁加仓');
      } else {
        buf.writeln('⚠ 马丁加仓  | 检测到疑似加仓模式，详见仓位分析');
      }
    } else {
      buf.writeln('✔ 马丁加仓  | 静态仓位管理（每笔等仓）');
    }

    // 03 过度拟合
    if (wfResult != null) {
      final stdDisplay = (wfResult.windowStdDev > 0
          ? (wfResult.windowStdDev).toStringAsFixed(2)
          : 'N/A');
      buf.writeln('${wfResult.isOverfit ? "⚠" : "✔"} 过度拟合  | '
          '分年标准差${stdDisplay}pp '
          '| IS:${wfResult.inSampleAvgReturn.toStringAsFixed(1)}% '
          'OOS:${wfResult.outOfSampleAvgReturn.toStringAsFixed(1)}%');
      buf.writeln('           | ${wfResult.verdict}');
    } else {
      buf.writeln('⚠ 过度拟合  | 未执行Walk-Forward分析，无法评估');
    }

    // 04 完整成本
    if (meta?.costDeducted == true) {
      buf.writeln('✔ 完整成本  | 佣金${(config.commissionRate * 10000).toStringAsFixed(1)}‱ '
          '+ 印花税${(config.stampTaxRate * 1000).toStringAsFixed(1)}‰(卖) '
          '+ 过户费${(config.transferRate * 100000).toStringAsFixed(0)}‱ '
          '+ 滑点${(config.slippageRate * 1000).toStringAsFixed(1)}‰');
      buf.writeln('           | 注意：最低佣金${config.minCommission.toStringAsFixed(0)}元/笔未在百分比模型中体现，小额交易实际成本更高');
    } else {
      buf.writeln('✘ 完整成本  | 未扣除交易成本，收益为毛收益');
    }

    // 05 复权除权
    if (isAdjusted) {
      buf.writeln('✔ 复权除权  | 数据检测为前复权 / 无除权影响');
    } else {
      buf.writeln('✘ 复权除权  | 警告：K线数据可能未前复权，除权日价格跳空影响信号');
    }

    // 06 前视偏差
    if (meta?.lookAheadSafe == true) {
      buf.writeln('✔ 前视偏差  | T日收盘信号→T+1日开盘执行，无look-ahead');
    } else {
      buf.writeln('✘ 前视偏差  | T日收盘信号→T日收盘执行，存在前视偏差');
    }

    // 07 幸存者偏差
    buf.writeln('⚠ 幸存者偏差  | 当前为单股回测，多股组合时需过滤退市/ST');

    // 08 涨跌停模拟
    if (meta?.limitSimulated == true) {
      buf.writeln('✔ 涨跌停模拟 | 涨停${(config.limitPct * 100).toStringAsFixed(0)}%买不进 '
          '/ 跌停${(config.limitPct * 100).toStringAsFixed(0)}%卖不出 '
          '| 跳过${meta?.skippedTrades ?? 0}笔不可执行交易');
    } else {
      buf.writeln('✘ 涨跌停模拟 | 未启用，所有价格均可成交');
    }

    // 09 交易日历
    buf.writeln('✔ 交易日历  | K线API仅返回交易日数据，无周末信号');

    // 10 脏数据
    if (meta?.dirtySkipped == true) {
      buf.writeln('✔ 脏数据    | 停牌/一字板已排除 '
          '| 跳过${meta?.skippedSignals ?? 0}个异常K线');
    } else {
      buf.writeln('✘ 脏数据    | 未启用数据过滤，包含停牌/一字板信号');
    }

    // 汇总
    final passes = [
      meta?.lookAheadSafe == true,
      !(wfResult?.isOverfit ?? true),
      meta?.costDeducted == true,
      isAdjusted,
      meta?.limitSimulated == true,
      meta?.dirtySkipped == true,
    ].where((t) => t).length;

    const total = 6; // 前6项为引擎层面可控
    buf.writeln('──────────────────────────────────────');
    buf.writeln('校验通过: $passes/$total');

    if (meta?.warnings != null && meta!.warnings.isNotEmpty) {
      buf.writeln('警告:');
      for (final w in meta.warnings) {
        buf.writeln('  - $w');
      }
    }

    return buf.toString();
  }

  // ═══════════════════════════════════════════════════════════
  // 策略置信度调整（回测反馈闭环）
  // ═══════════════════════════════════════════════════════════

  static double getStrategyConfidenceAdjustment(
    String strategyName,
    Map<String, BacktestResult> backtestResults,
  ) {
    final result = backtestResults[strategyName];
    if (result == null || result.totalSignals < 3) return 1.0;

    double winRateScore = result.winRate;
    double pfScore;
    if (result.profitFactor == double.infinity) {
      pfScore = 1.0;
    } else if (result.profitFactor >= 2.0) {
      pfScore = 1.0;
    } else if (result.profitFactor >= 1.5) {
      pfScore = 0.8;
    } else if (result.profitFactor >= 1.0) {
      pfScore = 0.5;
    } else {
      pfScore = 0.2;
    }

    double sampleScore = (result.totalSignals / 10.0).clamp(0.0, 1.0);
    final compositeScore = winRateScore * 0.4 + pfScore * 0.4 + sampleScore * 0.2;
    return 0.7 + compositeScore * 0.6;
  }

  static List<MapEntry<String, double>> getStrategyPerformanceRanking(
    Map<String, BacktestResult> results,
  ) {
    final scores = <String, double>{};
    for (final entry in results.entries) {
      if (entry.value.totalSignals < 3) continue;
      final winRate = entry.value.winRate;
      final pf = entry.value.profitFactor == double.infinity ? 5.0 : entry.value.profitFactor;
      scores[entry.key] = winRate * 0.5 + (pf / 5.0).clamp(0.0, 1.0) * 0.5;
    }
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted;
  }

  // ═══════════════════════════════════════════════════════════
  // 格式化输出
  // ═══════════════════════════════════════════════════════════

  static String formatResult(BacktestResult result) {
    if (result.totalSignals == 0) {
      return '回测数据不足，无法生成有效结果';
    }
    final meta = result.validationMeta;
    final costNote = meta?.costDeducted == true ? '(已扣成本)' : '(毛收益)';
    return '信号总数: ${result.totalSignals}\n'
        '胜率: ${(result.winRate * 100).toStringAsFixed(1)}%\n'
        '盈利次数: ${result.winningTrades} | 亏损次数: ${result.losingTrades}\n'
        '平均盈利: ${result.avgWinPct.toStringAsFixed(2)}% | 平均亏损: ${result.avgLossPct.toStringAsFixed(2)}%\n'
        '盈亏比: ${!result.profitFactor.isFinite ? "全胜" : (result.profitFactor > 0 ? result.profitFactor.toStringAsFixed(2) : "N/A")}\n'
        '总收益$costNote: ${result.totalReturn.toStringAsFixed(2)}%\n'
        '最大回撤: ${(result.maxDrawdown * 100).toStringAsFixed(2)}%';
  }

  static String getBacktestSummary(Map<String, BacktestResult> results) {
    if (results.isEmpty) return '回测数据不足';

    final ranking = getStrategyPerformanceRanking(results);
    if (ranking.isEmpty) return '无可信策略回测结果';

    final best = ranking.first;
    final bestResult = results[best.key]!;

    final winRateStr = (bestResult.winRate * 100).toStringAsFixed(0);
    final pfStr = bestResult.profitFactor == double.infinity
        ? '全胜'
        : bestResult.profitFactor.toStringAsFixed(2);

    final buf = StringBuffer();
    buf.writeln('最佳策略: ${best.key} (胜率$winRateStr% 盈亏比$pfStr)');
    buf.writeln('历史回测: ${bestResult.totalSignals}笔交易'
        ' | 总收益${bestResult.totalReturn.toStringAsFixed(1)}%'
        ' | 最大回撤${(bestResult.maxDrawdown * 100).toStringAsFixed(1)}%');

    if (ranking.length >= 2) {
      final second = results[ranking[1].key]!;
      buf.write('次优: ${ranking[1].key} '
          '(胜率${(second.winRate * 100).toStringAsFixed(0)}% '
          '总收益${second.totalReturn.toStringAsFixed(1)}%)');
    }
    return buf.toString();
  }

  // ═══════════════════════════════════════════════════════════
  // 内部工具方法
  // ═══════════════════════════════════════════════════════════

  static BacktestResult _emptyResult() {
    return BacktestResult(
      totalSignals: 0, winningTrades: 0, losingTrades: 0,
      winRate: 0, avgWinPct: 0, avgLossPct: 0, profitFactor: 0,
      maxDrawdown: 0, totalReturn: 0, tradeReturns: [],
    );
  }

  static BacktestResult _buildResult(List<double> tradeReturns, double currentEquity, double maxDrawdown) {
    // 单次遍历计算所有统计量（避免 4 次 where/reduce）
    int winningTrades = 0;
    int losingTrades = 0;
    double grossProfit = 0;
    double grossLoss = 0;
    for (final r in tradeReturns) {
      if (r > 0) {
        winningTrades++;
        grossProfit += r;
      } else if (r < 0) {
        losingTrades++;
        grossLoss += r.abs();
      }
    }
    final int decisiveTrades = winningTrades + losingTrades;
    final winRate = decisiveTrades > 0 ? winningTrades / decisiveTrades : 0.0;
    final double avgWinPct = winningTrades > 0 ? grossProfit / winningTrades * 100 : 0;
    final double avgLossPct = losingTrades > 0 ? grossLoss / losingTrades * 100 : 0;
    final double profitFactor = grossLoss > 0
        ? grossProfit / grossLoss
        : (grossProfit > 0 ? double.infinity : 0);
    final effectiveSignals = tradeReturns.length;

    return BacktestResult(
      totalSignals: effectiveSignals,
      winningTrades: winningTrades,
      losingTrades: losingTrades,
      winRate: winRate,
      avgWinPct: avgWinPct,
      avgLossPct: avgLossPct,
      profitFactor: profitFactor,
      maxDrawdown: maxDrawdown,
      totalReturn: (currentEquity - 1) * 100,
      tradeReturns: tradeReturns,
    );
  }

  static double _safeReturnPct(double buyPrice, double sellPrice) {
    if (buyPrice <= 0) return 0.0;
    return (sellPrice - buyPrice) / buyPrice;
  }

  /// 风险指标计算：基于逐笔交易收益率计算 Sharpe / MaxDD / Calmar
  ///
  /// 返回 (sharpeRatio, maxDrawdown, calmarRatio)
  /// - maxDrawdown 为负值 (e.g. -0.15 = 15% 回撤)
  static (double?, double?, double?) _calculateRiskMetrics(List<double> returns) {
    if (returns.length < 2) return (null, null, null);

    final meanReturn = returns.reduce((a, b) => a + b) / returns.length;
    final variance = returns
        .map((r) => (r - meanReturn) * (r - meanReturn))
        .reduce((a, b) => a + b) /
        returns.length;
    final stdDev = sqrt(variance);

    if (stdDev == 0) return (null, null, null);

    // Sharpe: (meanReturn - riskFree/252) / stdDev * sqrt(252)
    const dailyRiskFree = 0.02 / 252;
    final sharpeRatio = (meanReturn - dailyRiskFree) / stdDev * sqrt(252);

    // MaxDD: iterate cumulative returns, find peak-to-trough drawdown (negative)
    double cumulative = 1.0;
    double peak = 1.0;
    double maxDD = 0;
    for (final r in returns) {
      cumulative *= (1 + r);
      if (cumulative > peak) peak = cumulative;
      final dd = (cumulative - peak) / peak; // negative value
      if (dd < maxDD) maxDD = dd;
    }

    if (maxDD == 0) return (sharpeRatio, maxDD, null);

    // Calmar: abs(annualizedReturn / maxDrawdown)
    final annualizedReturn = meanReturn * 252;
    final calmarRatio = (annualizedReturn / maxDD).abs();

    return (sharpeRatio, maxDD, calmarRatio);
  }
}
