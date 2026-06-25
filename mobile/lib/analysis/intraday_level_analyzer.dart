/// 日内分时图低吸高抛点分析引擎
///
/// 在分时图上检测日内低吸（买入）和高抛（卖出）信号点，
/// 帮助用户进行日内T+0操作。
///
/// 分析流程：
///   1. 判定日内趋势方向 (bullish/bearish/neutral)
///   2. 计算动态振幅基准阈值
///   3. 检测8种信号类型 (4低吸 + 4高抛)
///   4. 应用趋势过滤器
///   5. 多信号共振加成
///   6. 时段可靠性加权
///   7. 去重、排序、限制数量

import 'dart:math';

/// 日内趋势方向
enum IntradayTrend { bullish, bearish, neutral }

/// 分时信号类型
enum IntradaySignalType {
  vwapSupport, // VWAP支撑反弹
  preCloseSupport, // 昨收价支撑
  bottomDivergence, // 量价底背离
  panicRecovery, // 急跌底部+放量
  vwapResistance, // VWAP压力回落
  highResistance, // 日内前高压力
  topDivergence, // 量价顶背离
  spikeExhaustion, // 冲高衰竭+放量
}

/// 信号方向
enum IntradayDirection { buy, sell }

/// 单个分时信号点
///
/// 注意：`confidence` 和 `isHighConfidence` 在分析管道中是可变的
/// （通过 [IntradayLevelAnalyzer.analyze] 的五步管道调整），
/// 消费者（UI层）应将其视为只读。
class IntradayLevelPoint {
  final int minuteOffset;
  final double price;
  final IntradayDirection direction;
  final IntradaySignalType signalType;
  /// 置信度（0.0-1.0），在分析管道中可调整
  double confidence;
  /// confidence >= 0.65 时为高可信度，随 confidence 同步更新
  bool isHighConfidence;
  final String shortLabel;
  final String description;

  IntradayLevelPoint({
    required this.minuteOffset,
    required this.price,
    required this.direction,
    required this.signalType,
    required this.confidence,
    required this.isHighConfidence,
    required this.shortLabel,
    required this.description,
  });
}

/// 分时分析结果
class IntradayLevelResult {
  final IntradayTrend trend;
  final double trendScore; // -5 ~ +5
  final List<IntradayLevelPoint> buySignals; // 低吸信号，置信度降序
  final List<IntradayLevelPoint> sellSignals; // 高抛信号，置信度降序
  final double dailyAmplitude; // 计算得到或传入的动态振幅基准(%)
  final double openingRangeHigh; // 开盘30分钟最高价
  final double openingRangeLow; // 开盘30分钟最低价

  IntradayLevelResult({
    required this.trend,
    required this.trendScore,
    required this.buySignals,
    required this.sellSignals,
    required this.dailyAmplitude,
    required this.openingRangeHigh,
    required this.openingRangeLow,
  });

  /// 按时间交替排列的所有信号
  List<IntradayLevelPoint> get allSignals {
    final merged = <IntradayLevelPoint>[...buySignals, ...sellSignals];
    merged.sort((a, b) => a.minuteOffset.compareTo(b.minuteOffset));
    return merged;
  }
}

/// 分时低吸高抛分析器（静态工具类）
class IntradayLevelAnalyzer {
  IntradayLevelAnalyzer._();

  /// 默认日均振幅（无历史数据时使用）
  static const double _defaultAmplitudePct = 2.0;

  /// 开盘区间计算分钟数
  static const int _openingRangeMinutes = 30;

  /// 分析分时图，返回所有信号
  ///
  /// [prices]: 分钟偏移量 → 价格
  /// [volumes]: 分钟偏移量 → 该分钟成交量(股)
  /// [vwapData]: 分钟偏移量 → 累计VWAP均价
  /// [estimatedAmplitude]: 来自历史数据的预估日均振幅(%)，用于动态阈值
  static IntradayLevelResult analyze({
    required Map<int, double> prices,
    required Map<int, double> volumes,
    required Map<int, double> vwapData,
    required double preClose,
    required double openPrice,
    required double dayHigh,
    required double dayLow,
    required int currentOffset,
    double? estimatedAmplitude,
  }) {
    if (prices.isEmpty) {
      return IntradayLevelResult(
        trend: IntradayTrend.neutral,
        trendScore: 0,
        buySignals: [],
        sellSignals: [],
        dailyAmplitude: estimatedAmplitude ?? _defaultAmplitudePct,
        openingRangeHigh: 0,
        openingRangeLow: 0,
      );
    }

    // 获取排序后的偏移量列表
    final offsets = prices.keys.toList()..sort();

    // 1. 计算动态振幅基准
    final baseAmplitude = _calcBaseAmplitude(
      prices, offsets, preClose, dayHigh, dayLow, estimatedAmplitude,
    );

    // 2. 计算开盘区间
    final openingHigh = _calcOpeningRangeHigh(prices, offsets, _openingRangeMinutes);
    final openingLow = _calcOpeningRangeLow(prices, offsets, _openingRangeMinutes);

    // 3. 判定日内趋势
    final (trend, trendScore) = _determineTrend(
      prices, offsets, vwapData, openPrice, currentOffset, openingHigh, openingLow,
    );

    // 4. 检测所有信号（不考虑趋势，后续过滤）
    final rawSignals = <IntradayLevelPoint>[];
    rawSignals.addAll(_detectVwapSupport(prices, volumes, vwapData, offsets, preClose, baseAmplitude, currentOffset));
    rawSignals.addAll(_detectPreCloseSupport(prices, volumes, offsets, preClose, baseAmplitude, currentOffset));
    rawSignals.addAll(_detectBottomDivergence(prices, volumes, offsets, baseAmplitude, currentOffset));
    rawSignals.addAll(_detectPanicRecovery(prices, volumes, offsets, preClose, baseAmplitude, currentOffset));
    rawSignals.addAll(_detectVwapResistance(prices, volumes, vwapData, offsets, preClose, baseAmplitude, currentOffset));
    rawSignals.addAll(_detectHighResistance(prices, volumes, offsets, dayHigh, baseAmplitude, currentOffset));
    rawSignals.addAll(_detectTopDivergence(prices, volumes, offsets, baseAmplitude, currentOffset));
    rawSignals.addAll(_detectSpikeExhaustion(prices, volumes, offsets, preClose, baseAmplitude, currentOffset));

    // 5. 应用趋势过滤器
    _applyTrendFilter(rawSignals, trend);

    // 6. 应用多信号共振加成
    _applyMultiConfirm(rawSignals, baseAmplitude);

    // 7. 应用时段可靠性
    _applyTimeReliability(rawSignals);

    // 8. 去重、排序、限制
    final filtered = _deduplicateAndSort(rawSignals);

    // 分离买卖信号
    final buySignals = filtered.where((s) => s.direction == IntradayDirection.buy).toList();
    final sellSignals = filtered.where((s) => s.direction == IntradayDirection.sell).toList();

    return IntradayLevelResult(
      trend: trend,
      trendScore: trendScore,
      buySignals: buySignals,
      sellSignals: sellSignals,
      dailyAmplitude: baseAmplitude,
      openingRangeHigh: openingHigh,
      openingRangeLow: openingLow,
    );
  }

  // ============================================================
  // 1. 动态振幅计算
  // ============================================================

  /// 计算动态振幅基准（百分比，如2.0表示2%）
  static double _calcBaseAmplitude(
    Map<int, double> prices,
    List<int> offsets,
    double preClose,
    double dayHigh,
    double dayLow,
    double? estimatedAmplitude,
  ) {
    // 优先使用当日实际振幅
    if (preClose > 0 && dayHigh > 0 && dayLow > 0 && offsets.isNotEmpty) {
      final currentAmplitude = (dayHigh - dayLow) / preClose * 100;
      // 如果当前振幅已接近或超过预估值，使用实际值
      if (currentAmplitude > 0.3) {
        return max(currentAmplitude, 0.3); // 至少0.3%，与上方阈值一致
      }
    }

    // 从已有价格数据估算振幅
    if (offsets.isNotEmpty) {
      double maxP = double.negativeInfinity;
      double minP = double.infinity;
      for (final o in offsets) {
        final p = prices[o]!;
        if (p > maxP) maxP = p;
        if (p < minP) minP = p;
      }
      if (preClose > 0 && maxP > minP) {
        final dataAmplitude = (maxP - minP) / preClose * 100;
        if (dataAmplitude > 0.3) return dataAmplitude;
      }
    }

    // 使用预估值或默认值
    return estimatedAmplitude ?? _defaultAmplitudePct;
  }

  // ============================================================
  // 2. 开盘区间计算
  // ============================================================

  static double _calcOpeningRangeHigh(Map<int, double> prices, List<int> offsets, int minutes) {
    double high = 0;
    for (final o in offsets.where((o) => o < minutes)) {
      if (prices[o]! > high) high = prices[o]!;
    }
    return high;
  }

  static double _calcOpeningRangeLow(Map<int, double> prices, List<int> offsets, int minutes) {
    double low = double.infinity;
    final openingOffsets = offsets.where((o) => o < minutes).toList();
    if (openingOffsets.isEmpty) return 0;
    for (final o in openingOffsets) {
      if (prices[o]! < low) low = prices[o]!;
    }
    return low;
  }

  // ============================================================
  // 3. 日内趋势判定
  // ============================================================

  static (IntradayTrend, double) _determineTrend(
    Map<int, double> prices,
    List<int> offsets,
    Map<int, double> vwapData,
    double openPrice,
    int currentOffset,
    double openingHigh,
    double openingLow,
  ) {
    double score = 0;

    // 3a. 当前价 vs 开盘价
    final currentPrice = prices[offsets.last] ?? 0;
    if (openPrice > 0 && currentPrice > 0) {
      final changeVsOpen = (currentPrice - openPrice) / openPrice;
      if (changeVsOpen > 0.005) {
        score += 2;
      } else if (changeVsOpen < -0.005) {
        score -= 2;
      } else if (changeVsOpen > 0.002) {
        score += 1;
      } else if (changeVsOpen < -0.002) {
        score -= 1;
      }
    }

    // 3b. VWAP斜率（最近30分钟）
    if (vwapData.isNotEmpty) {
      final vwapOffsets = vwapData.keys.where((o) => o <= currentOffset).toList()..sort();
      if (vwapOffsets.length >= 2) {
        final recentStart = max(0, currentOffset - 30);
        final recentVwaps = vwapOffsets.where((o) => o >= recentStart).toList();
        if (recentVwaps.length >= 2) {
          final first = vwapData[recentVwaps.first]!;
          final last = vwapData[recentVwaps.last]!;
          if (last > first * 1.001) {
            score += 1;
          } else if (last < first * 0.999) {
            score -= 1;
          }
        }

        // 3c. 价格在VWAP上方的分钟数占比
        int aboveCount = 0;
        for (final o in offsets.where((o) => o <= currentOffset)) {
          if (vwapData.containsKey(o) && (prices[o] ?? 0) > (vwapData[o] ?? 0)) {
            aboveCount++;
          }
        }
        final totalWithVwap = offsets.where((o) => o <= currentOffset && vwapData.containsKey(o)).length;
        if (totalWithVwap > 10) {
          final ratio = aboveCount / totalWithVwap;
          if (ratio > 0.6) {
            score += 1;
          } else if (ratio < 0.4) {
            score -= 1;
          }
        }
      }
    }

    // 3d. 开盘区间突破
    if (openingHigh > 0 && openingLow > 0 && currentPrice > 0) {
      if (currentPrice > openingHigh) {
        score += 1;
      } else if (currentPrice < openingLow) {
        score -= 1;
      }
    }

    // 判定
    if (score >= 2) return (IntradayTrend.bullish, score.toDouble());
    if (score <= -2) return (IntradayTrend.bearish, score.toDouble());
    return (IntradayTrend.neutral, score.toDouble());
  }

  // ============================================================
  // 4. 信号检测：VWAP支撑反弹 (Signal 1)
  // ============================================================

  static List<IntradayLevelPoint> _detectVwapSupport(
    Map<int, double> prices,
    Map<int, double> volumes,
    Map<int, double> vwapData,
    List<int> offsets,
    double preClose,
    double baseAmplitude,
    int currentOffset,
  ) {
    final results = <IntradayLevelPoint>[];
    final threshold = preClose * baseAmplitude / 100 * 0.25; // baseThreshold × 0.25
    final recoveryThreshold = preClose * baseAmplitude / 100 * 0.1;

    for (int i = 0; i < offsets.length; i++) {
      final o = offsets[i];
      final price = prices[o]!;
      final vwap = vwapData[o];

      if (vwap == null || vwap <= 0) continue;
      // 检查价格是否接近或低于VWAP（在VWAP下方threshold范围内）
      final distanceAboveVwap = price - vwap;
      if (distanceAboveVwap > threshold || distanceAboveVwap < -threshold * 1.5) continue;

      // 寻找3-5分钟后的回升
      final checkEnd = o + 5;
      for (int j = i + 1; j < offsets.length; j++) {
        final futureO = offsets[j];
        if (futureO > checkEnd) break;
        if (futureO - o < 3) continue;

        final futurePrice = prices[futureO]!;
        final recovery = futurePrice - price;
        if (recovery < recoveryThreshold) continue;

        // 检查回升时放量
        final avgVolBefore = _avgVolume(volumes, offsets, o - 5, o);
        final recoveryVol = volumes[futureO] ?? 0;
        if (avgVolBefore > 0 && recoveryVol < avgVolBefore * 1.2) continue;

        // 计算置信度
        final recoveryRatio = (recovery / recoveryThreshold).clamp(0.0, 1.0);
        final volRatio = avgVolBefore > 0 ? ((recoveryVol / avgVolBefore) / 2.0).clamp(0.0, 1.0) : 0.5;
        final confidence = (recoveryRatio * 0.7 + volRatio * 0.3).clamp(0.0, 1.0);

        results.add(IntradayLevelPoint(
          minuteOffset: o,
          price: price,
          direction: IntradayDirection.buy,
          signalType: IntradaySignalType.vwapSupport,
          confidence: confidence,
          isHighConfidence: confidence >= 0.65,
          shortLabel: 'VWAP支撑',
          description: '${price.toStringAsFixed(2)} VWAP支撑反弹',
        ));
        break;
      }
    }
    return results;
  }

  // ============================================================
  // 信号检测：昨收价支撑 (Signal 2)
  // ============================================================

  static List<IntradayLevelPoint> _detectPreCloseSupport(
    Map<int, double> prices,
    Map<int, double> volumes,
    List<int> offsets,
    double preClose,
    double baseAmplitude,
    int currentOffset,
  ) {
    final results = <IntradayLevelPoint>[];
    if (preClose <= 0) return results;

    final threshold = preClose * baseAmplitude / 100 * 0.15;
    final recoveryThreshold = preClose * baseAmplitude / 100 * 0.08;

    for (int i = 0; i < offsets.length; i++) {
      final o = offsets[i];
      final price = prices[o]!;

      // 必须从昨收上方回踩（price > preClose）
      if (price <= preClose) continue;

      final distanceToPreClose = price - preClose;
      if (distanceToPreClose > threshold) continue;

      // 寻找后续反弹
      final checkEnd = o + 5;
      for (int j = i + 1; j < offsets.length; j++) {
        final futureO = offsets[j];
        if (futureO > checkEnd) break;

        final futurePrice = prices[futureO]!;
        final recovery = futurePrice - price;
        if (recovery < recoveryThreshold) continue;

        // 接近时缩量（前几分钟量递减），反弹放量
        final volBefore = _avgVolume(volumes, offsets, o - 3, o);
        final recoveryVol = volumes[futureO] ?? 0;
        if (recoveryVol <= volBefore) continue;

        final recoveryRatio = (recovery / recoveryThreshold).clamp(0.0, 1.0);
        final volRatio = volBefore > 0 ? ((recoveryVol / volBefore) / 2.0).clamp(0.0, 1.0) : 0.5;
        final confidence = (recoveryRatio * 0.6 + volRatio * 0.4).clamp(0.0, 1.0);

        results.add(IntradayLevelPoint(
          minuteOffset: o,
          price: price,
          direction: IntradayDirection.buy,
          signalType: IntradaySignalType.preCloseSupport,
          confidence: confidence,
          isHighConfidence: confidence >= 0.65,
          shortLabel: '昨收支撑',
          description: '${price.toStringAsFixed(2)} 昨收价支撑',
        ));
        break;
      }
    }
    return results;
  }

  // ============================================================
  // 信号检测：量价底背离 (Signal 3) ★★★★★ 首要信号
  // ============================================================

  static List<IntradayLevelPoint> _detectBottomDivergence(
    Map<int, double> prices,
    Map<int, double> volumes,
    List<int> offsets,
    double baseAmplitude,
    int currentOffset,
  ) {
    final results = <IntradayLevelPoint>[];
    if (offsets.length < 10) return results;

    final lookback = 15; // 15分钟窗口
    final minGap = 5; // 两个低点至少间隔5分钟

    for (int i = offsets.length - 1; i >= 0; i--) {
      final currentO = offsets[i];
      if (currentO > currentOffset) continue;

      final currentPrice = prices[currentO]!;

      // 在当前点的前lookback分钟内找另一个低点
      final windowStart = max(0, currentO - lookback);
      double prevLowPrice = double.infinity;
      int prevLowOffset = -1;
      double prevLowVolume = 0;

      for (int j = i - 1; j >= 0; j--) {
        final prevO = offsets[j];
        if (prevO < windowStart) break;

        final prevPrice = prices[prevO]!;
        if (prevPrice < prevLowPrice) {
          prevLowPrice = prevPrice;
          prevLowOffset = prevO;
          prevLowVolume = volumes[prevO] ?? 0;
        }
      }

      if (prevLowOffset < 0) continue;
      if (currentO - prevLowOffset < minGap) continue;

      // 价格创更低低点但成交量更小（背离）
      if (currentPrice >= prevLowPrice) continue;

      final currentVol = volumes[currentO] ?? 0;
      if (prevLowVolume <= 0 || currentVol <= 0) continue;
      if (currentVol >= prevLowVolume * 0.8) continue; // 需成交量减少20%以上

      // 检查背离后的回升
      final priceThreshold = currentPrice * baseAmplitude / 100 * 0.15;

      bool hasRecovery = false;
      double maxRecoveryRatio = 0;
      final checkEnd = currentO + 5;
      for (int k = i + 1; k < offsets.length; k++) {
        final futureO = offsets[k];
        if (futureO > checkEnd) break;
        final futurePrice = prices[futureO]!;
        final recovery = futurePrice - currentPrice;
        if (recovery > priceThreshold) {
          hasRecovery = true;
          maxRecoveryRatio = max(maxRecoveryRatio, recovery / priceThreshold);
        }
      }
      if (!hasRecovery && currentO < currentOffset - 5) continue; // 给最近5分钟一些容忍度

      final divergenceRatio = 1.0 - (currentVol / prevLowVolume).clamp(0.0, 1.0);
      final confidence = (divergenceRatio * 0.5 + maxRecoveryRatio.clamp(0.0, 1.0) * 0.5).clamp(0.0, 1.0);

      results.add(IntradayLevelPoint(
        minuteOffset: currentO,
        price: currentPrice,
        direction: IntradayDirection.buy,
        signalType: IntradaySignalType.bottomDivergence,
        confidence: confidence,
        isHighConfidence: confidence >= 0.65,
        shortLabel: '量价底背离',
        description: '${currentPrice.toStringAsFixed(2)} 量价底背离',
      ));
    }
    return results;
  }

  // ============================================================
  // 信号检测：急跌底部+放量 (Signal 4)
  // ============================================================

  static List<IntradayLevelPoint> _detectPanicRecovery(
    Map<int, double> prices,
    Map<int, double> volumes,
    List<int> offsets,
    double preClose,
    double baseAmplitude,
    int currentOffset,
  ) {
    final results = <IntradayLevelPoint>[];
    final dropThreshold = preClose * baseAmplitude / 100 * 0.4;
    if (dropThreshold <= 0) return results;

    for (int i = 0; i < offsets.length; i++) {
      final o = offsets[i];
      if (o > currentOffset - 5) continue; // 需要后续回升确认

      final price = prices[o]!;

      // 找5分钟内的高点
      double maxBefore = price;
      for (int j = i - 1; j >= 0; j--) {
        final prevO = offsets[j];
        if (o - prevO > 5) break;
        if (prices[prevO]! > maxBefore) {
          maxBefore = prices[prevO]!;
        }
      }

      final drop = maxBefore - price;
      if (drop < dropThreshold) continue;

      // 检查5分钟内是否有回升
      final recoveryTarget = drop * 0.4;
      double maxRecovery = 0;
      for (int k = i + 1; k < offsets.length; k++) {
        final futureO = offsets[k];
        if (futureO - o > 5) break;
        final recovery = prices[futureO]! - price;
        if (recovery > maxRecovery) {
          maxRecovery = recovery;
        }
      }
      if (maxRecovery < recoveryTarget) continue;

      // 最低点附近放量
      final avgVolBefore = _avgVolume(volumes, offsets, o - 10, o);
      final bottomVol = _avgVolume(volumes, offsets, o - 1, o + 2);
      if (avgVolBefore > 0 && bottomVol < avgVolBefore * 1.5) continue;

      final dropRatio = ((drop / dropThreshold) / 2.0).clamp(0.0, 1.0);
      final recoveryRatio = (maxRecovery / recoveryTarget).clamp(0.0, 1.0);
      final volRatio = avgVolBefore > 0 ? ((bottomVol / avgVolBefore) / 3.0).clamp(0.0, 1.0) : 0.5;
      final confidence = (dropRatio * 0.4 + recoveryRatio * 0.3 + volRatio * 0.3).clamp(0.0, 1.0);

      results.add(IntradayLevelPoint(
        minuteOffset: o,
        price: price,
        direction: IntradayDirection.buy,
        signalType: IntradaySignalType.panicRecovery,
        confidence: confidence,
        isHighConfidence: confidence >= 0.65,
        shortLabel: '急跌底部',
        description: '${price.toStringAsFixed(2)} 急跌放量反弹',
      ));
    }
    return results;
  }

  // ============================================================
  // 信号检测：VWAP压力回落 (Signal 5)
  // ============================================================

  static List<IntradayLevelPoint> _detectVwapResistance(
    Map<int, double> prices,
    Map<int, double> volumes,
    Map<int, double> vwapData,
    List<int> offsets,
    double preClose,
    double baseAmplitude,
    int currentOffset,
  ) {
    final results = <IntradayLevelPoint>[];
    final threshold = preClose * baseAmplitude / 100 * 0.25;
    final fallbackThreshold = preClose * baseAmplitude / 100 * 0.1;

    for (int i = 0; i < offsets.length; i++) {
      final o = offsets[i];
      final price = prices[o]!;
      final vwap = vwapData[o];
      if (vwap == null || vwap <= 0) continue;

      // 价格接近或高于VWAP
      final distanceBelowVwap = vwap - price;
      if (distanceBelowVwap > threshold || distanceBelowVwap < -threshold * 1.5) continue;

      // 寻找回落
      final checkEnd = o + 5;
      for (int j = i + 1; j < offsets.length; j++) {
        final futureO = offsets[j];
        if (futureO > checkEnd) break;
        if (futureO - o < 3) continue;

        final drop = price - prices[futureO]!;
        if (drop < fallbackThreshold) continue;

        final avgVolBefore = _avgVolume(volumes, offsets, o - 5, o);
        final dropVol = volumes[futureO] ?? 0;
        if (avgVolBefore > 0 && dropVol < avgVolBefore * 1.2) continue;

        final dropRatio = (drop / fallbackThreshold).clamp(0.0, 1.0);
        final volRatio = avgVolBefore > 0 ? ((dropVol / avgVolBefore) / 2.0).clamp(0.0, 1.0) : 0.5;
        final confidence = (dropRatio * 0.7 + volRatio * 0.3).clamp(0.0, 1.0);

        results.add(IntradayLevelPoint(
          minuteOffset: o,
          price: price,
          direction: IntradayDirection.sell,
          signalType: IntradaySignalType.vwapResistance,
          confidence: confidence,
          isHighConfidence: confidence >= 0.65,
          shortLabel: 'VWAP压力',
          description: '${price.toStringAsFixed(2)} VWAP压力回落',
        ));
        break;
      }
    }
    return results;
  }

  // ============================================================
  // 信号检测：日内前高压力 (Signal 6)
  // ============================================================

  static List<IntradayLevelPoint> _detectHighResistance(
    Map<int, double> prices,
    Map<int, double> volumes,
    List<int> offsets,
    double dayHigh,
    double baseAmplitude,
    int currentOffset,
  ) {
    final results = <IntradayLevelPoint>[];
    if (dayHigh <= 0 || offsets.isEmpty) return results;

    final threshold = dayHigh * baseAmplitude / 100 * 0.15;
    final fallbackThreshold = dayHigh * baseAmplitude / 100 * 0.08;

    for (int i = 0; i < offsets.length; i++) {
      final o = offsets[i];
      if (o > currentOffset - 5) continue;

      final price = prices[o]!;
      if (price <= 0) continue;

      final distanceToHigh = dayHigh - price;
      if (distanceToHigh > threshold) continue;

      // 寻找回落
      final checkEnd = o + 5;
      bool hasFallback = false;
      double maxDrop = 0;
      for (int j = i + 1; j < offsets.length; j++) {
        final futureO = offsets[j];
        if (futureO > checkEnd) break;
        final drop = price - prices[futureO]!;
        if (drop > fallbackThreshold) {
          hasFallback = true;
          maxDrop = max(maxDrop, drop);
        }
      }
      if (!hasFallback) continue;

      // 接近时缩量
      final volAtPoint = volumes[o] ?? 0;
      final avgVolBefore = _avgVolume(volumes, offsets, o - 5, o);
      if (avgVolBefore > 0 && volAtPoint > avgVolBefore) continue;

      final dropRatio = ((maxDrop / fallbackThreshold) / 2.0).clamp(0.0, 1.0);
      final volRatio = avgVolBefore > 0 ? (1.0 - (volAtPoint / avgVolBefore).clamp(0.0, 1.0)) : 0.5;
      double confidence = (dropRatio * 0.6 + volRatio * 0.4).clamp(0.0, 1.0);

      // 多次触及前高 → 加成（仅统计当前信号之前的触及次数）
      final touchesBefore = _countHighTouches(prices, offsets, o, dayHigh, threshold);
      if (touchesBefore >= 2) {
        confidence = (confidence + 0.1).clamp(0.0, 1.0);
      }

      results.add(IntradayLevelPoint(
        minuteOffset: o,
        price: price,
        direction: IntradayDirection.sell,
        signalType: IntradaySignalType.highResistance,
        confidence: confidence,
        isHighConfidence: confidence >= 0.65,
        shortLabel: '前高压力',
        description: '${price.toStringAsFixed(2)} 日内前高压力${touchesBefore >= 2 ? "(多次测试)" : ""}',
      ));
    }
    return results;
  }

  // ============================================================
  // 信号检测：量价顶背离 (Signal 7) ★★★★☆
  // ============================================================

  static List<IntradayLevelPoint> _detectTopDivergence(
    Map<int, double> prices,
    Map<int, double> volumes,
    List<int> offsets,
    double baseAmplitude,
    int currentOffset,
  ) {
    final results = <IntradayLevelPoint>[];
    if (offsets.length < 10) return results;

    final lookback = 15;
    final minGap = 5;

    for (int i = offsets.length - 1; i >= 0; i--) {
      final currentO = offsets[i];
      if (currentO > currentOffset) continue;
      final currentPrice = prices[currentO]!;

      final windowStart = max(0, currentO - lookback);
      double prevHighPrice = 0;
      int prevHighOffset = -1;
      double prevHighVolume = 0;

      for (int j = i - 1; j >= 0; j--) {
        final prevO = offsets[j];
        if (prevO < windowStart) break;
        if (prices[prevO]! > prevHighPrice) {
          prevHighPrice = prices[prevO]!;
          prevHighOffset = prevO;
          prevHighVolume = volumes[prevO] ?? 0;
        }
      }

      if (prevHighOffset < 0) continue;
      if (currentO - prevHighOffset < minGap) continue;
      if (currentPrice <= prevHighPrice) continue;

      // 价格更高但成交量更小（顶背离，更严格：需缩量30%以上）
      final currentVol = volumes[currentO] ?? 0;
      if (prevHighVolume <= 0 || currentVol <= 0) continue;
      if (currentVol >= prevHighVolume * 0.7) continue;

      // 检查回落的幅度
      final priceThreshold = currentPrice * baseAmplitude / 100 * 0.15;
      bool hasFallback = false;
      double maxFallbackRatio = 0;
      final checkEnd = currentO + 5;
      for (int k = i + 1; k < offsets.length; k++) {
        final futureO = offsets[k];
        if (futureO > checkEnd) break;
        final drop = currentPrice - prices[futureO]!;
        if (drop > priceThreshold) {
          hasFallback = true;
          maxFallbackRatio = max(maxFallbackRatio, drop / priceThreshold);
        }
      }
      if (!hasFallback && currentO < currentOffset - 5) continue;

      final divergenceRatio = 1.0 - (currentVol / prevHighVolume).clamp(0.0, 1.0);
      final confidence = (divergenceRatio * 0.5 + maxFallbackRatio.clamp(0.0, 1.0) * 0.5).clamp(0.0, 1.0);

      results.add(IntradayLevelPoint(
        minuteOffset: currentO,
        price: currentPrice,
        direction: IntradayDirection.sell,
        signalType: IntradaySignalType.topDivergence,
        confidence: confidence,
        isHighConfidence: confidence >= 0.65,
        shortLabel: '量价顶背离',
        description: '${currentPrice.toStringAsFixed(2)} 量价顶背离',
      ));
    }
    return results;
  }

  // ============================================================
  // 信号检测：冲高衰竭+放量 (Signal 8)
  // ============================================================

  static List<IntradayLevelPoint> _detectSpikeExhaustion(
    Map<int, double> prices,
    Map<int, double> volumes,
    List<int> offsets,
    double preClose,
    double baseAmplitude,
    int currentOffset,
  ) {
    final results = <IntradayLevelPoint>[];
    final riseThreshold = preClose * baseAmplitude / 100 * 0.4;
    if (riseThreshold <= 0) return results;

    for (int i = 0; i < offsets.length; i++) {
      final o = offsets[i];
      if (o > currentOffset - 5) continue;

      final price = prices[o]!;

      // 找5分钟内的低点
      double minBefore = double.infinity;
      for (int j = i - 1; j >= 0; j--) {
        final prevO = offsets[j];
        if (o - prevO > 5) break;
        if (prices[prevO]! < minBefore) {
          minBefore = prices[prevO]!;
        }
      }
      if (minBefore == double.infinity) continue;

      final rise = price - minBefore;
      if (rise < riseThreshold) continue;

      // 检查5分钟内是否有回落
      final retraceTarget = rise * 0.4;
      double maxRetrace = 0;
      for (int k = i + 1; k < offsets.length; k++) {
        final futureO = offsets[k];
        if (futureO - o > 5) break;
        final retrace = price - prices[futureO]!;
        if (retrace > maxRetrace) maxRetrace = retrace;
      }
      if (maxRetrace < retraceTarget) continue;

      // 最高点附近放量
      final avgVolBefore = _avgVolume(volumes, offsets, o - 10, o);
      final topVol = _avgVolume(volumes, offsets, o - 1, o + 2);
      if (avgVolBefore > 0 && topVol < avgVolBefore * 1.5) continue;

      final riseRatio = ((rise / riseThreshold) / 2.0).clamp(0.0, 1.0);
      final retraceRatio = (maxRetrace / retraceTarget).clamp(0.0, 1.0);
      final volRatio = avgVolBefore > 0 ? ((topVol / avgVolBefore) / 3.0).clamp(0.0, 1.0) : 0.5;
      final confidence = (riseRatio * 0.4 + retraceRatio * 0.3 + volRatio * 0.3).clamp(0.0, 1.0);

      results.add(IntradayLevelPoint(
        minuteOffset: o,
        price: price,
        direction: IntradayDirection.sell,
        signalType: IntradaySignalType.spikeExhaustion,
        confidence: confidence,
        isHighConfidence: confidence >= 0.65,
        shortLabel: '冲高衰竭',
        description: '${price.toStringAsFixed(2)} 冲高放量回落',
      ));
    }
    return results;
  }

  // ============================================================
  // 5. 趋势过滤器
  // ============================================================

  static void _applyTrendFilter(List<IntradayLevelPoint> signals, IntradayTrend trend) {
    const suppressionFactor = 0.6;
    for (final signal in signals) {
      if (trend == IntradayTrend.bullish && signal.direction == IntradayDirection.sell) {
        _updateConfidence(signal, signal.confidence * suppressionFactor);
      } else if (trend == IntradayTrend.bearish && signal.direction == IntradayDirection.buy) {
        _updateConfidence(signal, signal.confidence * suppressionFactor);
      }
    }
  }

  // ============================================================
  // 6. 多信号共振加成
  // ============================================================

  static void _applyMultiConfirm(List<IntradayLevelPoint> signals, double baseAmplitude) {
    // 按方向分组
    final buySignals = signals.where((s) => s.direction == IntradayDirection.buy).toList();
    final sellSignals = signals.where((s) => s.direction == IntradayDirection.sell).toList();

    for (final group in [buySignals, sellSignals]) {
      // 找到价格相近的信号群（价格比价阈值为0.002即0.2%）
      final clustered = <List<IntradayLevelPoint>>[];
      final used = <int>{};

      for (int i = 0; i < group.length; i++) {
        if (used.contains(i)) continue;
        final cluster = <IntradayLevelPoint>[group[i]];
        used.add(i);

        for (int j = i + 1; j < group.length; j++) {
          if (used.contains(j)) continue;
          // 价格是否接近（用绝对比例而非baseAmplitude来保证不同场景的一致性）
          if (group[i].price > 0) {
            final diff = (group[i].price - group[j].price).abs() / group[i].price;
            if (diff < 0.003) {
              // within 0.3%
              cluster.add(group[j]);
              used.add(j);
            }
          }
        }

        if (cluster.length >= 2) {
          clustered.add(cluster);
        }
      }

      // 应用共振加成
      for (final cluster in clustered) {
        double bonus;
        if (cluster.length >= 4) {
          bonus = 0.20;
        } else if (cluster.length >= 3) {
          bonus = 0.15;
        } else {
          bonus = 0.10;
        }

        for (final signal in cluster) {
          _updateConfidence(signal, signal.confidence + bonus);
        }
      }
    }
  }

  // ============================================================
  // 7. 时段可靠性
  // ============================================================

  static void _applyTimeReliability(List<IntradayLevelPoint> signals) {
    for (final signal in signals) {
      final reliability = _getTimeReliability(signal.minuteOffset);
      // 使用加权混合：reliability影响50%, 原始置信度保持50%
      _updateConfidence(signal, signal.confidence * reliability * 0.5 + signal.confidence * 0.5);
    }
  }

  static double _getTimeReliability(int offset) {
    // 9:30-9:45 (0-15): 开盘博弈期，噪声大
    if (offset < 15) return 0.3;
    // 9:45-10:30 (15-60): 方向确认期
    if (offset < 60) return 0.7;
    // 10:30-14:00 (60-150): 稳定交易期，信号最可靠
    if (offset < 150) return 1.0;
    // 14:00-14:45 (150-195): 尾盘博弈期
    if (offset < 195) return 0.8;
    // 14:45-15:00 (195-240): 不建议新开T仓
    return 0.5;
  }

  // ============================================================
  // 8. 去重、排序、限制
  // ============================================================

  static List<IntradayLevelPoint> _deduplicateAndSort(List<IntradayLevelPoint> signals) {
    if (signals.isEmpty) return [];

    // 按时间排序用于去重（复制避免修改调用方列表）
    final sorted = [...signals]..sort((a, b) => a.minuteOffset.compareTo(b.minuteOffset));

    // 同类型信号10分钟窗口去重（保留置信度最高的）
    final deduplicated = <IntradayLevelPoint>[];
    for (int i = 0; i < sorted.length; i++) {
      bool isDuplicate = false;
      for (int j = max(0, deduplicated.length - 5); j < deduplicated.length; j++) {
        if (sorted[i].signalType == deduplicated[j].signalType &&
            (sorted[i].minuteOffset - deduplicated[j].minuteOffset).abs() < 10) {
          // 保留置信度更高的
          if (sorted[i].confidence > deduplicated[j].confidence) {
            deduplicated[j] = sorted[i];
          }
          isDuplicate = true;
          break;
        }
      }
      if (!isDuplicate) {
        deduplicated.add(sorted[i]);
      }
    }

    // 连续同方向信号只保留第一个（交替原则）
    final alternating = <IntradayLevelPoint>[];
    for (final signal in deduplicated) {
      if (alternating.isEmpty) {
        alternating.add(signal);
      } else {
        final last = alternating.last;
        if (last.direction != signal.direction) {
          alternating.add(signal);
        }
        // 同方向：跳过（但保留置信度更高的替换）
        else if (signal.confidence > last.confidence + 0.1) {
          alternating.last = signal;
        }
      }
    }

    // 过滤低置信度（< 0.45）
    final filtered = alternating.where((s) => s.confidence >= 0.45).toList();

    // 按置信度降序排列
    filtered.sort((a, b) => b.confidence.compareTo(a.confidence));

    // 最多保留6个（买卖各3个）
    final buy = filtered.where((s) => s.direction == IntradayDirection.buy).take(3).toList();
    final sell = filtered.where((s) => s.direction == IntradayDirection.sell).take(3).toList();
    return [...buy, ...sell];
  }

  // ============================================================
  // 工具方法
  // ============================================================

  /// 计算指定偏移量之前前高被触及的次数
  static int _countHighTouches(Map<int, double> prices, List<int> offsets, int signalOffset, double dayHigh, double threshold) {
    int count = 0;
    for (final o in offsets) {
      if (o >= signalOffset) break; // 只统计信号之前
      if ((dayHigh - prices[o]!) <= threshold) count++;
    }
    return count;
  }

  /// 计算指定范围内分钟成交量的平均值
  static double _avgVolume(Map<int, double> volumes, List<int> offsets, int start, int end) {
    double sum = 0;
    int count = 0;
    for (final o in offsets) {
      if (o >= start && o < end) {
        sum += volumes[o] ?? 0;
        count++;
      }
    }
    return count > 0 ? sum / count : 0;
  }

  /// 更新信号置信度（管道内部使用）
  static void _updateConfidence(IntradayLevelPoint signal, double newConfidence) {
    signal.confidence = newConfidence.clamp(0.0, 1.0);
    signal.isHighConfidence = signal.confidence >= 0.65;
  }
}
