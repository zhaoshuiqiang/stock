import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/stock_models.dart';
import 'indicators.dart';

// âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// åæµéç½®
// âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

/// åæµéç½® â æ§å¶ææ¬æ¨¡åãæ¶¨è·åè§åãæ°æ®æ ¡éªå¼å³
class BacktestConfig {
  /// ä½£éè´¹çï¼é»è®¤ä¸2.5ï¼ååï¼
  final double commissionRate;
  /// å°è±ç¨è´¹çï¼é»è®¤å1ï¼ä»ååºï¼
  final double stampTaxRate;
  /// è¿æ·è´¹çï¼é»è®¤ä¸åä¹0.2ï¼ååï¼
  final double transferRate;
  /// æ»ç¹ä¼°ç®ï¼é»è®¤0.1%ï¼
  final double slippageRate;
  /// æ¶¨è·åå¹åº¦ï¼é»è®¤10% ä¸»æ¿ï¼
  final double limitPct;
  /// æ¯å¦æ£é¤äº¤æææ¬
  final bool deductCost;
  /// æ¯å¦è·³è¿æ¶¨è·åä¸å¯æ§è¡çäº¤æ
  final bool skipLimitTrade;
  /// æ¯å¦è·³è¿èæ°æ®ï¼åç/ä¸å­æ¿ï¼
  final bool skipDirtyData;
  /// æå°ä½£éï¼åï¼ï¼ä½äºæ­¤ææ­¤æ¶å
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

  /// Aè¡ä¸»æ¿é»è®¤éç½®ï¼Â±10%ï¼
  static const aStock = BacktestConfig();

  /// ç§å/åä¸æ¿ï¼Â±20%ï¼
  static const chiNext = BacktestConfig(limitPct: 0.20);

  /// æ§çå¼å®¹æ¨¡å¼ï¼æ ææ¬ãæ éå¶ï¼
  static const legacy = BacktestConfig(
    deductCost: false,
    skipLimitTrade: false,
    skipDirtyData: false,
  );

  /// æ ¹æ®è¡ç¥¨ä»£ç èªå¨æ¨æ­æ¶¨è·åå¹åº¦
  static double inferLimitPct(String? stockCode) {
    if (stockCode == null) return 0.10;
    if (stockCode.startsWith('688') || stockCode.startsWith('300')) return 0.20;
    if (stockCode.startsWith('8') || stockCode.startsWith('4')) return 0.30; // åäº¤æ
    return 0.10; // ä¸»æ¿
  }

  factory BacktestConfig.forCode(String? stockCode) {
    return BacktestConfig(limitPct: inferLimitPct(stockCode));
  }

  /// åè¾¹ä¹°å¥ææ¬ç
  double get buyCostRate => commissionRate + transferRate + slippageRate;
  /// åè¾¹ååºææ¬çï¼å«å°è±ç¨ï¼
  double get sellCostRate => commissionRate + stampTaxRate + transferRate + slippageRate;
  /// å¾è¿æ»ææ¬ç
  double get roundTripCostRate => buyCostRate + sellCostRate;
}

// âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// Kçº¿æ°æ®æ ¡éªå·¥å·
// âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

class KlineValidator {
  /// æ¶¨è·åä»·æ ¼ï¼åºäºåæ¥æ¶çä»·ï¼
  static double limitUpPrice(double prevClose, double limitPct) => prevClose * (1 + limitPct);
  static double limitDownPrice(double prevClose, double limitPct) => prevClose * (1 - limitPct);

  /// æ¯å¦ä¸ºæ¶¨åæ¥ â æ¶çä»·è§¦åæ¶¨åä»·ï¼ä¹°ä¸è¿
  static bool isLimitUp(HistoryKline kline, HistoryKline prev, double limitPct) {
    final upPrice = limitUpPrice(prev.close, limitPct);
    // æ¶çä»·/æé«ä»·æ¥è¿æ¶¨åä»·å³ä¸ºæ¶¨åï¼å®¹å¿ååä¸è¯¯å·®ï¼
    return kline.close >= upPrice * 0.999 || kline.high >= upPrice * 0.999;
  }

  /// æ¯å¦ä¸ºè·åæ¥ â æ¶[çä»·è§¦åè·åä»·ï¼åä¸åº
  static bool isLimitDown(HistoryKline kline, HistoryKline prev, double limitPct) {
    final downPrice = limitDownPrice(prev.close, limitPct);
    return kline.close <= downPrice * 1.001 || kline.low <= downPrice * 1.001;
  }

  /// å¼çå³å°æ¿ â å¼çä»·ç´æ¥æ¶¨å/è·åï¼å¨å¤©æ æ³äº¤æ
  static bool isOpenAtLimit(HistoryKline kline, HistoryKline prev, double limitPct) {
    final upPrice = limitUpPrice(prev.close, limitPct);
    final downPrice = limitDownPrice(prev.close, limitPct);
    return kline.open >= upPrice * 0.999 || kline.open <= downPrice * 1.001;
  }

  /// ä¸å­æ¿ â open==high==low==close ä¸å°æ¿
  static bool isYiZiBan(HistoryKline kline, HistoryKline prev, double limitPct) {
    if (prev.close <= 0) return false;
    final isFlat = kline.open == kline.high &&
        kline.high == kline.low &&
        kline.low == kline.close;
    if (!isFlat) return false;
    final chgPct = (kline.close - prev.close) / prev.close;
    return chgPct.abs() >= limitPct - 0.005;
  }

  /// çä¼¼åç â è¿ç»­æ äº¤æéçéæ­¢Kçº¿
  static bool isSuspension(HistoryKline kline, HistoryKline prev) {
    // æäº¤éå ä¹ä¸º0 æ ä»·æ ¼å®å¨ä¸åä¸æäº¤éæä½
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

  /// æ¯å¦ä¸ºèæ°æ®ï¼åçãä¸å­æ¿ãå¼å¸¸è·³åï¼
  static bool isDirty(HistoryKline kline, HistoryKline prev, double limitPct) {
    if (isSuspension(kline, prev)) return true;
    if (isYiZiBan(kline, prev, limitPct)) return true;
    // åæ¥æ¶¨è·å¹è¶è¿æ¶¨è·åéå¶ï¼å¯è½æ¯æ°æ®éè¯¯æé¤ææªå¤æï¼
    if (prev.close > 0 &&
        (kline.close - prev.close).abs() / prev.close > limitPct + 0.02) {
      return true;
    }
    return false;
  }

  /// æ£æµæ°æ®æ¯å¦ç»è¿åå¤æå¤ç
  /// éè¿æ£æ¥æ¶¨è·å¹ä¸è´æ§æ¥å¤æ­ï¼åå§æ°æ®ç changePct åºç­äº (close-preClose)/preClose
  static bool checkForwardAdjusted(List<HistoryKline> data) {
    if (data.length < 20) return true; // æ°æ®å¤ªå°ï¼æ æ³å¤æ­ï¼åè®¾å·²å¤æ
    final sampleSize = (data.length * 0.3).toInt().clamp(10, 50);
    int mismatchCount = 0;
    for (int i = data.length - sampleSize; i < data.length - 1; i++) {
      final today = data[i];
      final yesterday = data[i - 1];
      if (yesterday.close <= 0) continue;
      final calcChgPct = (today.close - yesterday.close) / yesterday.close * 100;
      final diff = (calcChgPct - today.changePct).abs();
      // å¦æè®¡ç®å¼åAPIè¿åå¼å·®å¼è¶è¿ 1%ï¼è¯´æå¯è½æªå¤æ
      if (diff > 1.0 && today.changePct.abs() < 10) {
        mismatchCount++;
      }
    }
    // è¶è¿ 20% çæ ·æ¬ä¸ä¸è´ -> å¤§æ¦çæªå¤æ
    return mismatchCount / sampleSize <= 0.2;
  }
}

// âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// åæµæ ¡éªåæ°æ®
// âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

/// åæµæ ¡éªè¿ç¨çåæ°æ®
class BacktestValidationMeta {
  final bool lookAheadSafe;           // åè§åå·®å®å¨ï¼T+1æ§è¡ï¼
  final bool limitSimulated;          // æ¶¨è·åæ¨¡æå·²å¯ç¨
  final bool costDeducted;            // äº¤æææ¬å·²æ£é¤
  final bool forwardAdjusted;         // æ°æ®ç¡®è®¤åå¤æ
  final bool dirtySkipped;            // èæ°æ®å·²è·³è¿
  final int skippedSignals;           // å æ ¡éªè·³è¿çä¿¡å·æ°
  final int skippedTrades;            // å æ¶¨è·åè·³è¿çäº¤ææ°
  final List<String> warnings;        // è­¦åä¿¡æ¯

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

// âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// åæµç»æ
// âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

/// åæµç»æ
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
  /// æ°å¢ï¼æ ¡éªåæ°æ®
  final BacktestValidationMeta? validationMeta;
  /// Sharpe æ¯çï¼å¹´åï¼åºäºéç¬äº¤ææ¶ççï¼
  final double? sharpeRatio;
  /// Calmar æ¯çï¼å¹´åæ¶çç / æå¤§åæ¤ï¼
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

// âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// Walk-Forward åæç»æ
// âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

class WalkForwardResult {
  final int totalWindows;
  final int passedWindows;
  final double inSampleAvgReturn;
  final double outOfSampleAvgReturn;
  final double windowStdDev;          // åçªå£OOSæ¶ççæ åå·® (pp)
  final List<double> windowReturns;   // åçªå£OOSæ¶çç
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

// âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
// åæµå¼æ
// âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

class BacktestEngine {
  /// å¨å±é»è®¤éç½®ï¼å¯éè¿ setConfig ä¿®æ¹ï¼
  static BacktestConfig config = BacktestConfig.aStock;

  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  // éç½®
  // ï¿½ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

  static void setConfig(BacktestConfig cfg) {
    config = cfg;
  }

  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  // éç¨åæµæ§è¡å¨ â æ¶é¤ 6 ä¸ªç­ç¥çéå¤ä»£ç 
  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  //
  // æ ¸å¿ä¿®æ­£ï¼
  //   P0-1 åè§åå·®ï¼Tæ¥ä¿¡å· â T+1æ¥ open ä»·æ§è¡
  //   P0-2 æ¶¨è·åï¼ä¹°å¥è·³è¿æ¶¨åæ¥ï¼ååºè·³è¿è·åæ¥
  //   P1-3 äº¤æææ¬ï¼æ£é¤ä½£é + å°è±ç¨ + æ»ç¹
  //   P1-5 èæ°æ®ï¼è·³è¿åç/ä¸å­æ¿
  //
  // å·²ç¥å±éï¼
  //   - èæ°æ®è·³è¿ä»é»æ­¢å½æ¥äº¤æï¼ä½å·²é¢è®¡ç®çææ ï¼MA/MACDç­ï¼
  //     ä»åèæ°æ®æ¥ä»·æ ¼å½±åï¼å¯è½æ±¡æåç»­æ¥çä¿¡å·å¤æ­ã
  //     è¿æ¯é¢è®¡ç®æ¶æçåºæåèââå¦éå®å¨éç¦»éå¨å¾ªç¯åéç®ææ ã
  //
  // åæ°ï¼
  //   [data]  Kçº¿æ°æ®
  //   [minBars] æå°Kçº¿æ°è¦æ±
  //   [prepare] ææ è®¡ç®å½æ°
  //   [isEntry] å¥åºä¿¡å·å¤æ­ (prev, curr) -> bool
  //   [isExit]  åºåºä¿¡å·å¤æ­ (prev, curr) -> bool
  //   [atrMultiplier] ATRæ­¢æåæ°ï¼0 = ä¸å¯ç¨ATRæ­¢æ
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
    double peakCloseSinceEntry = 0; // P1-7: æä»æé´æé«æ¶çä»·ï¼ç¨äºè¿½è¸ªæ­¢æ
    double peakEquity = 1.0;
    double currentEquity = 1.0;
    double maxDrawdown = 0;
    int skippedSignals = 0;
    int skippedTrades = 0;

    // T+1 æ§è¡ä¿®æ­£ï¼éåå° length-2ï¼å ä¸ºéè¦ i+1 (next day) æ¥æ§è¡
    for (int i = 1; i < calcData.length - 1; i++) {
      final prev = calcData[i - 1];
      final curr = calcData[i];
      final next = calcData[i + 1]; // T+1 æ§è¡æ¥

      // ---- èæ°æ®è·³è¿ ----
      if (config.skipDirtyData && KlineValidator.isDirty(curr, prev, config.limitPct)) {
        skippedSignals++;
        continue;
      }

      // ---- å¥åºä¿¡å· ----
      if (isEntry(prev, curr) && buyPrice == null) {
        // æ£æ¥ T+1 æ§è¡æ¥æ¯å¦è½ä¹°å¥ï¼éæ¶¨å/éå¼çå³å°æ¿ï¼
        if (config.skipLimitTrade &&
            (KlineValidator.isLimitUp(next, curr, config.limitPct) ||
             KlineValidator.isOpenAtLimit(next, curr, config.limitPct))) {
          skippedTrades++;
          continue; // ä¹°å¥å¤±è´¥ï¼è·³è¿æ­¤ä¿¡å·
        }
        buyPrice = next.open; // â T+1 å¼çä»·æ§è¡
        peakCloseSinceEntry = next.open; // P1-7: åå§åæä»æé«ä»·
        continue;
      }

      // P1-8: æä»æ¶æ¯æ ¹Kçº¿æ´æ°æçåæ¤ï¼æææ¥åæå¤§åæ¤ï¼
      if (buyPrice != null) {
        if (curr.close > peakCloseSinceEntry) peakCloseSinceEntry = curr.close;
        // ç¨å½åæ¶çä»·è®¡ç®æµ®çæçï¼æ´æ°åæ¤
        final unrealizedEquity = currentEquity * (1 + _safeReturnPct(buyPrice, curr.close));
        if (unrealizedEquity > peakEquity) peakEquity = unrealizedEquity;
        final floatingDd = (peakEquity - unrealizedEquity) / peakEquity;
        if (floatingDd > maxDrawdown) maxDrawdown = floatingDd;
      }

      // ---- åºåºä¿¡å·ï¼ä»æä»æ¶ï¼ ----
      if (isExit(prev, curr) && buyPrice != null) {
        // æ£æ¥ T+1 æ§è¡æ¥æ¯å¦è½ååºï¼éè·åï¼
        if (config.skipLimitTrade &&
            KlineValidator.isLimitDown(next, curr, config.limitPct)) {
          skippedTrades++;
          // ä¸åºåºï¼ç»§ç»­ææï¼ç­ä¸ä¸ä¸ªå¯ååºæ¥ï¼
          continue;
        }
        // åèå¹³ä»é»è¾
        final returnPct = _safeReturnPct(buyPrice, next.open); // â T+1 å¼çä»·æ§è¡
        final netReturn = _applyCost(returnPct);
        tradeReturns.add(netReturn);
        currentEquity *= (1 + netReturn);
        if (currentEquity > peakEquity) peakEquity = currentEquity;
        final dd = (peakEquity - currentEquity) / peakEquity;
        if (dd > maxDrawdown) maxDrawdown = dd;
        buyPrice = null;
        continue;
      }

      // ---- ATR æ­¢æï¼æä»æ¶ï¼ ----
      // P1-7ä¿®å¤ï¼è¿½è¸ªæ­¢æï¼éå®æä»æé´æé«æ¶çä»·èéåºå®buyPrice
      // ATRæ©å¤§æ¶æ­¢æä¸ç§»ï¼è¶è¿peakCloseï¼ï¼é£é©ç®¡çæ­£ç¡®æ¶ç´§
      if (buyPrice != null && atrMultiplier > 0 && curr.atr14 > 0) {
        final atrStop = peakCloseSinceEntry - curr.atr14 * atrMultiplier;
        if (curr.low <= atrStop) {
          // è·åæ¥æ æ³æ­¢æååº
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

    // ä»ææä» â ææåä¸å¤©æ¶çä»·å¹³ä»
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

    // è®¡ç®é£é©ææ ï¼Sharpe / Calmarï¼
    final (sharpe, _, calmar) = _calculateRiskMetrics(tradeReturns);

    // éå æ ¡éªåæ°æ®
    final warnings = <String>[];
    if (!KlineValidator.checkForwardAdjusted(calcData)) {
      warnings.add('æ°æ®å¯è½æªåå¤æï¼å»ºè®®ä½¿ç¨åå¤æKçº¿æ°æ®');
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

  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  // åç­ç¥æ¹æ³ï¼èå°è£ï¼
  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

  /// MACDéåä¹°å¥ / MACDæ­»åååº
  static BacktestResult backtestMACDCross(List<HistoryKline> data) {
    return _runGenericBacktest(
      data: data,
      minBars: 60,
      prepare: (d) => calcMACD(d),
      isEntry: (p, c) => c.macdDif > c.macdDea && p.macdDif <= p.macdDea,
      isExit: (p, c) => c.macdDif < c.macdDea && p.macdDif >= p.macdDea,
    );
  }

  /// MA5ä¸ç©¿MA10 éåç­ç¥
  static BacktestResult backtestMACross(List<HistoryKline> data) {
    return _runGenericBacktest(
      data: data,
      minBars: 30,
      prepare: (d) => calcMA(d, [5, 10]),
      isEntry: (p, c) => c.ma5 > c.ma10 && p.ma5 <= p.ma10,
      isExit: (p, c) => c.ma5 < c.ma10 && p.ma5 >= p.ma10,
    );
  }

  /// KDJè¶åéååæµï¼KDJ<30åºåKä¸ç©¿Dä¹°å¥ï¼æ­»åååº/ATRæ­¢æï¼
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

  /// RSIè¶ååå¼¹åæµï¼RSI6â¤30åå¼¹ä¹°å¥ï¼RSI6<50ååºï¼
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

  /// å¸æå¸¦ä¸è½¨æ¯æåæµï¼è§¦åä¸è½¨åå¼¹ä¹°å¥ï¼åå°ä¸­è½¨ååºï¼
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

  /// åçº¿å¤å¤´æååæµï¼MA5>MA10>MA20å½¢æå¤å¤´æåä¹°å¥ï¼MA5ä¸ç ´MA10ååºï¼
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

  static BacktestResult backtestHammerReversal(List<HistoryKline> data) {
    return _runGenericBacktest(
      data: data, minBars: 30,
      prepare: (d) { var r = calcRSI(d, [6]); return calcATR(r); },
      isEntry: (p, c) {
        final body = (c.close - c.open).abs();
        final lowerShadow = c.open < c.close ? c.open - c.low : c.close - c.low;
        final upperShadow = c.high - c.close > c.high - c.open ? c.high - c.close : c.high - c.open;
        if (lowerShadow < body * 2 || upperShadow > body * 0.5) return false;
        return true;
      },
      isExit: (p, c) => c.rsi6 > 65,
      atrMultiplier: 1.5,
    );
  }

  static BacktestResult backtestBullishEngulfing(List<HistoryKline> data) {
    return _runGenericBacktest(
      data: data, minBars: 30,
      prepare: (d) { var r = calcRSI(d, [6]); return calcATR(r); },
      isEntry: (p, c) => p.close < p.open && c.close > c.open && c.close > p.open && c.open < p.close,
      isExit: (p, c) => c.rsi6 > 65,
      atrMultiplier: 1.5,
    );
  }

  static BacktestResult backtestBearishEngulfing(List<HistoryKline> data) {
    return _runGenericBacktest(
      data: data, minBars: 30,
      prepare: (d) { var r = calcRSI(d, [6]); return calcATR(r); },
      isEntry: (p, c) => p.close > p.open && c.close < c.open && c.close < p.open && c.open > p.close,
      isExit: (p, c) => c.rsi6 < 35,
      atrMultiplier: 1.5,
    );
  }

  static BacktestResult backtestPiercingPattern(List<HistoryKline> data) {
    return _runGenericBacktest(
      data: data, minBars: 30, prepare: (d) => calcATR(d),
      isEntry: (p, c) {
        if (p.close >= p.open || c.close <= c.open) return false;
        return c.close > (p.open + p.close) / 2 && c.open < p.close;
      },
      isExit: (p, c) => c.close > p.high,
      atrMultiplier: 1.5,
    );
  }

  static BacktestResult backtestDarkCloudCover(List<HistoryKline> data) {
    return _runGenericBacktest(
      data: data, minBars: 30, prepare: (d) => calcATR(d),
      isEntry: (p, c) {
        if (p.close <= p.open || c.close >= c.open) return false;
        return c.close < (p.open + p.close) / 2 && c.open > p.close;
      },
      isExit: (p, c) => c.close < p.low,
      atrMultiplier: 1.5,
    );
  }

  static BacktestResult backtestMorningStar(List<HistoryKline> data) {
    return _runGenericBacktest(
      data: data, minBars: 30,
      prepare: (d) { var r = calcRSI(d, [6]); return calcATR(r); },
      isEntry: (p, c) => p.close < p.open && (p.close - p.open).abs() < p.close * 0.01 && c.close > c.open && c.close > p.open,
      isExit: (p, c) => c.rsi6 > 60,
      atrMultiplier: 1.5,
    );
  }

  static BacktestResult backtestEveningStar(List<HistoryKline> data) {
    return _runGenericBacktest(
      data: data, minBars: 30,
      prepare: (d) { var r = calcRSI(d, [6]); return calcATR(r); },
      isEntry: (p, c) => p.close > p.open && (p.close - p.open).abs() < p.close * 0.01 && c.close < c.open && c.close < p.open,
      isExit: (p, c) => c.rsi6 < 40,
      atrMultiplier: 1.5,
    );
  }

  static BacktestResult backtestDojiReversal(List<HistoryKline> data) {
    return _runGenericBacktest(
      data: data, minBars: 30, prepare: (d) => calcATR(d),
      isEntry: (p, c) {
        final body = (c.close - c.open).abs();
        final range = c.high - c.low;
        return range > 0 && body / range < 0.1;
      },
      isExit: (p, c) => c.close > p.high || c.close < p.low,
      atrMultiplier: 1.5,
    );
  }

  static BacktestResult backtestGapUpBuy(List<HistoryKline> data) {
    return _runGenericBacktest(
      data: data, minBars: 30, prepare: (d) => calcATR(d),
      isEntry: (p, c) => p.close > 0 && c.open > p.high && (c.open - p.close) / p.close > 0.02,
      isExit: (p, c) => c.close < p.low,
      atrMultiplier: 1.0,
    );
  }

  static BacktestResult backtestGapDownFill(List<HistoryKline> data) {
    return _runGenericBacktest(
      data: data, minBars: 30, prepare: (d) => calcATR(d),
      isEntry: (p, c) => p.close > 0 && c.open < p.low && (p.close - c.open) / p.close > 0.02,
      isExit: (p, c) => c.close > p.low,
      atrMultiplier: 1.5,
    );
  }

  static BacktestResult backtestWROversold(List<HistoryKline> data) {
    return _runGenericBacktest(
      data: data, minBars: 30,
      prepare: (d) { var r = calcWR(d); return calcATR(r); },
      isEntry: (p, c) => (p.wr14 ?? 0) > 80 && (c.wr14 ?? 0) < (p.wr14 ?? 0),
      isExit: (p, c) => (c.wr14 ?? 0) < 20,
      atrMultiplier: 1.5,
    );
  }

  static BacktestResult backtestCCIOversold(List<HistoryKline> data) {
    return _runGenericBacktest(
      data: data, minBars: 30,
      prepare: (d) { var r = calcCCI(d); return calcATR(r); },
      isEntry: (p, c) => (p.cci14 ?? 0) < -100 && (c.cci14 ?? 0) > (p.cci14 ?? 0),
      isExit: (p, c) => (c.cci14 ?? 0) > 100,
      atrMultiplier: 1.5,
    );
  }

  static BacktestResult backtestCCIBreakout(List<HistoryKline> data) {
    return _runGenericBacktest(
      data: data, minBars: 30,
      prepare: (d) { var r = calcCCI(d); return calcATR(r); },
      isEntry: (p, c) => (p.cci14 ?? 0) < 0 && (c.cci14 ?? 0) > 100,
      isExit: (p, c) => (c.cci14 ?? 0) < 0,
      atrMultiplier: 1.5,
    );
  }

// âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  // äº¤æææ¬è®¡ç®
  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

  /// æ£é¤äº¤æææ¬åçåæ¶ççï¼ä¹æ³æ¨¡åï¼
  /// netReturn = (1 + grossReturn) Ã (1 - costRate) - 1
  /// æ¯åæ³æ¨¡åæ´ç²¾ç¡®ï¼ææ¬ç­æ¯ç¼©æ¾æ¶çï¼èéåºå®æ£é¤
  static double _applyCost(double grossReturn) {
    if (!config.deductCost) return grossReturn;
    return (1 + grossReturn) * (1 - config.roundTripCostRate) - 1;
  }

  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  // ç»¼ååæµä¸ç­ç¥è¯ä¼°
  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

  /// å¨ç­ç¥åæµ
  static Map<String, BacktestResult> megaBacktest(List<HistoryKline> data) {
    if (data.length < 60) return {};

    final results = <String, BacktestResult>{};
    try { results['MACDäº¤å'] = backtestMACDCross(data); } catch (e) { debugPrint('[åæµ] MACDäº¤åç­ç¥å¤±è´¥: $e'); }
    try { results['MAéå'] = backtestMACross(data); } catch (e) { debugPrint('[åæµ] MAéåç­ç¥å¤±è´¥: $e'); }
    try { results['KDJè¶å'] = backtestKDJOversoldCross(data); } catch (e) { debugPrint('[åæµ] KDJè¶åç­ç¥å¤±è´¥: $e'); }
    try { results['RSIè¶å'] = backtestRSIOversoldRecovery(data); } catch (e) { debugPrint('[åæµ] RSIè¶åç­ç¥å¤±è´¥: $e'); }
    try { results['å¸ææ¯æ'] = backtestBollSupport(data); } catch (e) { debugPrint('[åæµ] å¸ææ¯æç­ç¥å¤±è´¥: $e'); }
    try { results['åçº¿å¤å¤´'] = backtestMAMultiHead(data); } catch (e) { debugPrint('[åæµ] åçº¿å¤å¤´ç­ç¥å¤±è´¥: $e'); }

    return results;
  }

  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  // P2-6: Walk-Forward æ»å¨çªå£åæµï¼è¿åº¦æåæ£æµï¼
  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

  /// Walk-Forward æ»å¨çªå£åæµ
  ///
  /// å°æ°æ®åå²ä¸ºå¤ä¸ªæ»å¨çªå£ï¼æ¯çªå£ç¨åNæ¥è®­ç»ï¼æ ·æ¬åï¼ï¼åMæ¥æµè¯ï¼æ ·æ¬å¤ï¿½ï¿½ã
  /// å¦æ OOS æ¶çè¿å°äº IS æ¶çï¼æåå¹´æ åå·®è¿å¤§ â çä¼¼è¿æå
  static WalkForwardResult walkForwardBacktest(
    List<HistoryKline> data, {
    int windowSize = 120,   // æ¯çªå£æ ·æ¬åå¤©æ°
    int testSize = 60,      // æ¯çªå£æ ·æ¬å¤å¤©æ°ï¼é¡»â¥60ä»¥æ¯æmegaBacktestæå°æ°æ®éï¼
  }) {
    if (data.length < windowSize + testSize) {
      return WalkForwardResult(
        totalWindows: 0, passedWindows: 0,
        inSampleAvgReturn: 0, outOfSampleAvgReturn: 0,
        windowStdDev: 0, windowReturns: [],
        isOverfit: false, verdict: 'æ°æ®ä¸è¶³ï¼æ æ³è¿è¡Walk-Forwardåæ(éâ¥${windowSize + testSize}æ ¹Kçº¿)',
      );
    }

    final windowReturns = <double>[];
    double totalIsReturn = 0;
    double totalOosReturn = 0;
    int windowCount = 0;
    int passedWindows = 0;

    // æ»å¨çªå£
    for (int start = 0; start + windowSize + testSize <= data.length; start += testSize) {
      windowCount++;
      final isData = data.sublist(start, start + windowSize);
      final oosData = data.sublist(start + windowSize, start + windowSize + testSize);

      final isResults = megaBacktest(isData);
      if (isResults.isEmpty) continue;
      // ISï¼æ¾åºæ ·æ¬åè¡¨ç°æä½³çç­ç¥ï¼totalSignalsâ¥3ï¼
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
      // OOSï¼è¯ä¼°åä¸ä¸ªç­ç¥å¨æ ·æ¬å¤çè¡¨ç°ï¼ä¸ IS å¯¹ç§°æ¯è¾ï¼
      // è¥è¯¥ç­ç¥å¨ OOS æ ä¿¡å·ï¼è®°ä¸º 0ï¼ç­ç¥ä¸éç¨ï¼
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
        isOverfit: false, verdict: 'Walk-Forwardåæï¿½ï¿½ï¿½è´¥',
      );
    }

    final isAvg = totalIsReturn / windowCount;
    final oosAvg = totalOosReturn / windowCount;
    final oosStd = _calcStdDev(windowReturns);

    // è¿æåå¤æ­ï¼
    // 1. æ ·æ¬å¤æ¶çæ¾èä½äºæ ·æ¬åï¼IS/OOS > 3 åï¼
    // 2. åå¹´æ åå·®è¿å¤§ï¼> 2ppï¼è¡¨ç¤ºè¡¨ç°ä¸ç¨³å®ï¼
    final overfitRatio = isAvg > 0 && oosAvg > 0 ? isAvg / oosAvg : (isAvg > 0 ? 999.0 : 0);
    final isOverfit = overfitRatio > 3.0 || oosStd > 2.0;

    String verdict;
    if (isOverfit && overfitRatio > 3.0) {
      verdict = 'çä¼¼è¿æåï¼æ ·æ¬åæ¶ç(${isAvg.toStringAsFixed(1)}%)è¿è¶æ ·æ¬å¤(${oosAvg.toStringAsFixed(1)}%)ï¼ç­ç¥æ³åè½åä¸è¶³';
    } else if (isOverfit && oosStd > 2.0) {
      verdict = 'çä¼¼è¿æåï¼åå¹´æ åå·®${oosStd.toStringAsFixed(2)}ppè¿å¤§ï¼ç­ç¥è¡¨ç°ä¸ç¨³å®';
    } else if (oosAvg < 0) {
      verdict = 'ç­ç¥æ ·æ¬å¤è¡¨ç°ä¸ä½³(${oosAvg.toStringAsFixed(1)}%)ï¼å»ºè®®ä¼åä¿¡å·æ¡ä»¶';
    } else {
      verdict = 'ç­ç¥ç¨³å¥ï¼æ ·æ¬å${isAvg.toStringAsFixed(1)}% / æ ·æ¬å¤${oosAvg.toStringAsFixed(1)}%ï¼åå¹´æ åå·®${oosStd.toStringAsFixed(2)}pp';
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

  /// åå¹´ç»©æåæï¼ç¨äºè¿åº¦æåæ£æµï¼
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

  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  // ä»ä½ç®¡çæ ¡éªï¼P2-7: é©¬ä¸å ä»æ£æµï¼
  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

  /// ä»ä½åæ â æ£æµæ¯å¦å­å¨é©¬ä¸å ä»ï¼éç¬å ä»ï¼è¡ä¸º
  static String positionAnalysis(Map<String, BacktestResult> results) {
    final buf = StringBuffer();
    for (final entry in results.entries) {
      final trades = entry.value.tradeReturns;
      if (trades.length < 5) continue;

      // æ£æµè¿ç»­äºæå ä»æ¨¡å¼
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
          // è¿ç»­äºæä¸äºæå¹åº¦éå¢ â çä¼¼é©¬ä¸
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
        buf.writeln('${entry.key}: è­¦åâçä¼¼é©¬ä¸å ä»æ¨¡å¼ï¼è¿ç»­äºæå¹åº¦éå¢ï¼');
      }
      if (maxConsecutiveLoss >= 4) {
        buf.writeln('${entry.key}: æå¤§è¿ç»­äºæ$maxConsecutiveLossæ¬¡ï¼éå³æ³¨é£é©æ§å¶');
      }
    }
    if (buf.isEmpty) buf.write('ä»ä½ç®¡çæ­£å¸¸ï¼æªæ£æµå°é©¬ä¸å ä»æ¨¡å¼');
    return buf.toString();
  }

  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  // åæµæ ¡éªæ¥åï¼è¾åºç±»ä¼¼æªå¾ä¸­çéªè¯åè¡¨ï¼
  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

  /// çæåæµæ ¡éªæ¥å
  static String validationReport(Map<String, BacktestResult> results, {
    WalkForwardResult? wfResult,
    String? stockCode,
    List<HistoryKline>? rawData,
  }) {
    if (results.isEmpty) return 'æ åæµæ°æ®ï¼æ æ³çææ ¡éªæ¥å';

    // ä»ä»»ä¸ç»æä¸­è·ååæ°æ®
    final meta = results.values.first.validationMeta;
    final isAdjusted = rawData != null ? KlineValidator.checkForwardAdjusted(rawData) : (meta?.forwardAdjusted ?? true);

    final buf = StringBuffer();
    buf.writeln('ââââââââââââ åæµæ ¡éªæ¥å ââââââââââââ');

    // 01 æªæ¥å½æ°
    if (meta?.lookAheadSafe == true) {
      buf.writeln('â æªæ¥å½æ°  | ç¹å¾ä½¿ç¨Tæ¥æ¶çæ°æ®ï¼ç®æ ä½¿ç¨T+1æ¥å¼çæ§è¡');
    } else {
      buf.writeln('â æªæ¥å½æ°  | è­¦åï¼å¯è½ä½¿ç¨äºæªæ¥æ°æ®');
    }

    // 02 é©¬ä¸å ä»
    if (results.values.any((r) => r.tradeReturns.length >= 5)) {
      final pos = positionAnalysis(results);
      if (pos.contains('æ­£å¸¸')) {
        buf.writeln('â é©¬ä¸å ä»  | éæä»ä½ç®¡çï¼æªæ£æµå°é©¬ä¸å ä»');
      } else {
        buf.writeln('â  é©¬ä¸å ä»  | æ£æµå°çä¼¼å ä»æ¨¡å¼ï¼è¯¦è§ä»ä½åæ');
      }
    } else {
      buf.writeln('â é©¬ä¸å ä»  | éæä»ä½ç®¡çï¼æ¯ç¬ç­ä»ï¼');
    }

    // 03 è¿åº¦æå
    if (wfResult != null) {
      final stdDisplay = (wfResult.windowStdDev > 0
          ? (wfResult.windowStdDev).toStringAsFixed(2)
          : 'N/A');
      buf.writeln('${wfResult.isOverfit ? "â " : "â"} è¿åº¦æå  | '
          'åå¹´æ åå·®${stdDisplay}pp '
          '| IS:${wfResult.inSampleAvgReturn.toStringAsFixed(1)}% '
          'OOS:${wfResult.outOfSampleAvgReturn.toStringAsFixed(1)}%');
      buf.writeln('           | ${wfResult.verdict}');
    } else {
      buf.writeln('â  è¿åº¦æå  | æªæ§è¡Walk-Forwardåæï¼æ æ³è¯ä¼°');
    }

    // 04 å®æ´ææ¬
    if (meta?.costDeducted == true) {
      buf.writeln('â å®æ´ææ¬  | ä½£é${(config.commissionRate * 10000).toStringAsFixed(1)}â± '
          '+ å°è±ç¨${(config.stampTaxRate * 1000).toStringAsFixed(1)}â°(å) '
          '+ è¿æ·è´¹${(config.transferRate * 100000).toStringAsFixed(0)}â± '
          '+ æ»ç¹${(config.slippageRate * 1000).toStringAsFixed(1)}â°');
      buf.writeln('           | æ³¨æï¼æä½ä½£é${config.minCommission.toStringAsFixed(0)}å/ç¬æªå¨ç¾åæ¯æ¨¡åä¸­ä½ç°ï¼å°é¢äº¤æå®éææ¬æ´é«');
    } else {
      buf.writeln('â å®æ´ææ¬  | æªæ£é¤äº¤æææ¬ï¼æ¶çä¸ºæ¯æ¶ç');
    }

    // 05 å¤æé¤æ
    if (isAdjusted) {
      buf.writeln('â å¤æé¤æ  | æ°æ®æ£æµä¸ºåå¤æ / æ é¤æå½±å');
    } else {
      buf.writeln('â å¤æé¤æ  | è­¦åï¼Kçº¿æ°æ®å¯è½æªåå¤æï¼é¤ææ¥ä»·æ ¼è·³ç©ºå½±åä¿¡å·');
    }

    // 06 åè§åå·®
    if (meta?.lookAheadSafe == true) {
      buf.writeln('â åè§åå·®  | Tæ¥æ¶çä¿¡å·âT+1æ¥å¼çæ§è¡ï¼æ look-ahead');
    } else {
      buf.writeln('â åè§åå·®  | Tæ¥æ¶çä¿¡å·âTæ¥æ¶çæ§è¡ï¼å­å¨åè§åå·®');
    }

    // 07 å¹¸å­èåå·®
    buf.writeln('â  å¹¸å­èåå·®  | å½åä¸ºåè¡åæµï¼å¤è¡ç»åæ¶éè¿æ»¤éå¸/ST');

    // 08 æ¶¨è·åæ¨¡æ
    if (meta?.limitSimulated == true) {
      buf.writeln('â æ¶¨è·åæ¨¡æ | æ¶¨å${(config.limitPct * 100).toStringAsFixed(0)}%ä¹°ä¸è¿ '
          '/ è·å${(config.limitPct * 100).toStringAsFixed(0)}%åä¸åº '
          '| è·³è¿${meta?.skippedTrades ?? 0}ç¬ä¸å¯æ§è¡äº¤æ');
    } else {
      buf.writeln('â æ¶¨è·åæ¨¡æ | æªå¯ç¨ï¼ææä»·æ ¼åå¯æäº¤');
    }

    // 09 äº¤ææ¥å
    buf.writeln('â äº¤ææ¥å  | Kçº¿APIä»è¿åäº¤ææ¥æ°æ®ï¼æ å¨æ«ä¿¡å·');

    // 10 èæ°æ®
    if (meta?.dirtySkipped == true) {
      buf.writeln('â èæ°æ®    | åç/ä¸å­æ¿å·²æé¤ '
          '| è·³è¿${meta?.skippedSignals ?? 0}ä¸ªå¼å¸¸Kçº¿');
    } else {
      buf.writeln('â èæ°æ®    | æªå¯ç¨æ°æ®è¿æ»¤ï¼åå«åç/ä¸å­æ¿ä¿¡å·');
    }

    // æ±æ»
    final passes = [
      meta?.lookAheadSafe == true,
      !(wfResult?.isOverfit ?? true),
      meta?.costDeducted == true,
      isAdjusted,
      meta?.limitSimulated == true,
      meta?.dirtySkipped == true,
    ].where((t) => t).length;

    const total = 6; // å6é¡¹ä¸ºå¼æå±é¢å¯æ§
    buf.writeln('ââââââââââââââââââââââââââââââââââââââ');
    buf.writeln('æ ¡éªéè¿: $passes/$total');

    if (meta?.warnings != null && meta!.warnings.isNotEmpty) {
      buf.writeln('è­¦å:');
      for (final w in meta.warnings) {
        buf.writeln('  - $w');
      }
    }

    return buf.toString();
  }

  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  // ç­ç¥ç½®ä¿¡åº¦è°æ´ï¼åæµåé¦é­ç¯ï¼
  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

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

  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  // æ ¼å¼åè¾åº
  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

  static String formatResult(BacktestResult result) {
    if (result.totalSignals == 0) {
      return 'åæµæ°æ®ä¸è¶³ï¼æ æ³çæææç»æ';
    }
    final meta = result.validationMeta;
    final costNote = meta?.costDeducted == true ? '(å·²æ£ææ¬)' : '(æ¯æ¶ç)';
    return 'ä¿¡å·æ»æ°: ${result.totalSignals}\n'
        'èç: ${(result.winRate * 100).toStringAsFixed(1)}%\n'
        'çå©æ¬¡æ°: ${result.winningTrades} | äºææ¬¡æ°: ${result.losingTrades}\n'
        'å¹³åçå©: ${result.avgWinPct.toStringAsFixed(2)}% | å¹³åäºæ: ${result.avgLossPct.toStringAsFixed(2)}%\n'
        'çäºæ¯: ${!result.profitFactor.isFinite ? "å¨è" : (result.profitFactor > 0 ? result.profitFactor.toStringAsFixed(2) : "N/A")}\n'
        'æ»æ¶ç$costNote: ${result.totalReturn.toStringAsFixed(2)}%\n'
        'æå¤§åæ¤: ${(result.maxDrawdown * 100).toStringAsFixed(2)}%';
  }

  static String getBacktestSummary(Map<String, BacktestResult> results) {
    if (results.isEmpty) return 'åæµæ°æ®ä¸è¶³';

    final ranking = getStrategyPerformanceRanking(results);
    if (ranking.isEmpty) return 'æ å¯ä¿¡ç­ç¥åæµç»æ';

    final best = ranking.first;
    final bestResult = results[best.key]!;

    final winRateStr = (bestResult.winRate * 100).toStringAsFixed(0);
    final pfStr = bestResult.profitFactor == double.infinity
        ? 'å¨è'
        : bestResult.profitFactor.toStringAsFixed(2);

    final buf = StringBuffer();
    buf.writeln('æä½³ç­ç¥: ${best.key} (èç$winRateStr% çäºæ¯$pfStr)');
    buf.writeln('åå²åæµ: ${bestResult.totalSignals}ç¬äº¤æ'
        ' | æ»æ¶ç${bestResult.totalReturn.toStringAsFixed(1)}%'
        ' | æå¤§åæ¤${(bestResult.maxDrawdown * 100).toStringAsFixed(1)}%');

    if (ranking.length >= 2) {
      final second = results[ranking[1].key]!;
      buf.write('æ¬¡ä¼: ${ranking[1].key} '
          '(èç${(second.winRate * 100).toStringAsFixed(0)}% '
          'æ»æ¶ç${second.totalReturn.toStringAsFixed(1)}%)');
    }
    return buf.toString();
  }

  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ
  // åé¨å·¥å·æ¹æ³
  // âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

  static BacktestResult _emptyResult() {
    return BacktestResult(
      totalSignals: 0, winningTrades: 0, losingTrades: 0,
      winRate: 0, avgWinPct: 0, avgLossPct: 0, profitFactor: 0,
      maxDrawdown: 0, totalReturn: 0, tradeReturns: [],
    );
  }

  static BacktestResult _buildResult(List<double> tradeReturns, double currentEquity, double maxDrawdown) {
    // åæ¬¡éåè®¡ç®ææç»è®¡éï¼é¿å 4 æ¬¡ where/reduceï¼
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

  /// é£é©ææ è®¡ç®ï¼åºäºéç¬äº¤ææ¶ççè®¡ç® Sharpe / MaxDD / Calmar
  ///
  /// è¿å (sharpeRatio, maxDrawdown, calmarRatio)
  /// - maxDrawdown ä¸ºè´å¼ (e.g. -0.15 = 15% åæ¤)
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
