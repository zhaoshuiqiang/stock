import '../models/stock_models.dart';

/// 市场结构类型
enum MarketStructure {
  /// 牛市趋势 - ADX>25 且 MA多头排列
  bullTrend,

  /// 熊市趋势 - ADX>25 且 MA空头排列
  bearTrend,

  /// 震荡盘整 - ADX<20
  consolidation,

  /// 底部积累 - ADX 20-25 且 价格在MA60附近 且 成交量萎缩
  accumulation,

  /// 顶部分配 - ADX>25 且 MA排列混合(不完全多头也不完全空头)
  distribution,
}

/// 市场结构分析结果
class MarketStructureResult {
  final MarketStructure structure;
  final double confidence; // 0.0-1.0
  final double adxValue;
  final String maAlignment; // '多头' / '空头' / '混合'
  final String description;
  final List<String> compatibleStrategies; // 该结构下兼容的策略名称列表
  final double structureScore; // 用于综合评分的结构分(0-10)

  MarketStructureResult({
    required this.structure,
    required this.confidence,
    required this.adxValue,
    required this.maAlignment,
    required this.description,
    required this.compatibleStrategies,
    required this.structureScore,
  });

  factory MarketStructureResult.unknown() {
    return MarketStructureResult(
      structure: MarketStructure.consolidation,
      confidence: 0.3,
      adxValue: 0,
      maAlignment: '未知',
      description: '数据不足，默认为盘整结构',
      compatibleStrategies: kConsolidationStrategies,
      structureScore: 5.0,
    );
  }

  /// 从 JSON/Map 反序列化
  factory MarketStructureResult.fromJson(Map<String, dynamic> json) {
    return MarketStructureResult(
      structure: _parseStructure(json['structure'] as String? ?? 'consolidation'),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.3,
      adxValue: (json['adx_value'] as num?)?.toDouble() ?? 0,
      maAlignment: json['ma_alignment'] as String? ?? '未知',
      description: json['description'] as String? ?? '',
      compatibleStrategies: json['compatible_strategies'] != null
          ? List<String>.from(json['compatible_strategies'] as List)
          : [],
      structureScore: (json['structure_score'] as num?)?.toDouble() ?? 5.0,
    );
  }

  /// 序列化为 Map
  Map<String, dynamic> toJson() {
    return {
      'structure': structure.name,
      'confidence': confidence,
      'adx_value': adxValue,
      'ma_alignment': maAlignment,
      'description': description,
      'compatible_strategies': compatibleStrategies,
      'structure_score': structureScore,
    };
  }

  static MarketStructure _parseStructure(String name) {
    switch (name) {
      case 'bullTrend': return MarketStructure.bullTrend;
      case 'bearTrend': return MarketStructure.bearTrend;
      case 'consolidation': return MarketStructure.consolidation;
      case 'accumulation': return MarketStructure.accumulation;
      case 'distribution': return MarketStructure.distribution;
      default: return MarketStructure.consolidation;
    }
  }
}

/// 各市场结构下兼容的策略名称列表
/// 名称必须与 strategy_builder.dart 中 TradingStrategy.name 完全一致
const kBullTrendStrategies = [
  '均线多头排列',
  'MACD零轴上方金叉',
  '趋势强度确认',
  '布林带突破',
  '突破+回踩确认',
  '均线突破',
  '放量突破',
];

const kBearTrendStrategies = <String>[
  // 熊市中保留防守/超卖反弹型策略，捕捉阶段性反弹机会
  'RSI超卖反弹',       // 熊市超卖反弹
  'KDJ超卖金叉',       // 超卖区金叉反弹
  '缩量止跌',          // 卖方力量衰竭
  'MACD底背离短线',    // 底部背离信号，熊市中最佳信号
];

const kConsolidationStrategies = [
  'RSI超卖反弹',
  'KDJ超卖金叉',
  '缩量回调',
  '缩量止跌',
];

const kAccumulationStrategies = [
  'MACD底背离短线',
  'KDJ超卖金叉',
  'RSI超卖反弹',
  '缩量止跌',
  '均线多头排列',
  'RSI中轨支撑',
];

const kDistributionStrategies = [
  '缩量回调',
  '缩量止跌',
  'KDJ超卖金叉',
];

/// 根据市场结构判定哪些策略应禁用
Set<String> getIncompatibleStrategies(MarketStructure structure) {
  final compatList = _getCompatibleList(structure);
  return _getAllStrategyNames().where((s) => !compatList.contains(s)).toSet();
}

List<String> _getCompatibleList(MarketStructure structure) {
  switch (structure) {
    case MarketStructure.bullTrend:
      return kBullTrendStrategies;
    case MarketStructure.bearTrend:
      return kBearTrendStrategies;
    case MarketStructure.consolidation:
      return kConsolidationStrategies;
    case MarketStructure.accumulation:
      return kAccumulationStrategies;
    case MarketStructure.distribution:
      return kDistributionStrategies;
  }
}

Set<String> _getAllStrategyNames() {
  final all = <String>{};
  all.addAll(kBullTrendStrategies);
  all.addAll(kConsolidationStrategies);
  all.addAll(kAccumulationStrategies);
  all.addAll(kDistributionStrategies);
  return all;
}

/// 市场结构分析器
/// 基于已有K线指标(ADX + MA排列)判定当前市场结构
class MarketStructureAnalyzer {
  /// 分析市场结构
  /// 需要至少50条K线数据(ADX需要至少～30条预热)
  static MarketStructureResult analyze(List<HistoryKline> data) {
    if (data.length < 30) return MarketStructureResult.unknown();

    final last = data[data.length - 1];
    final adx = last.adx14;
    final ma5 = last.ma5;
    final ma10 = last.ma10;
    final ma20 = last.ma20;
    final ma60 = last.ma60;

    // 判断MA排列类型
    final maAlignment = _classifyMaAlignment(ma5, ma10, ma20, ma60);
    final isBullAlign = maAlignment == '多头';
    final isBearAlign = maAlignment == '空头';

    // 成交量判断(近5日平均 vs 近20日平均)
    final volRatios = <double>[];
    for (int i = data.length - 5; i < data.length; i++) {
      if (data[i].volMa5 > 0) {
        volRatios.add(data[i].volume / data[i].volMa5);
      }
    }
    final avgVolRatio = volRatios.isNotEmpty
        ? volRatios.reduce((a, b) => a + b) / volRatios.length
        : 1.0;
    final isVolumeContracting = avgVolRatio < 0.7;

    // 判断价格是否在MA60附近(±3%)
    double nearMa60 = 0;
    if (ma60 > 0 && last.close > 0) {
      nearMa60 = (last.close - ma60).abs() / ma60;
    }
    final isNearMA60 = ma60 > 0 && nearMa60 < 0.03;

    // 判断趋势
    MarketStructure structure;
    double confidence;
    String description;
    double structureScore;

    // v2.30: ADX方向检测 — 上升中的ADX趋势更可靠，下降中的ADX趋势可能反转
    final adxRising = _isAdxRising(data);

    if (adx > 25) {
      // 趋势明确
      if (isBullAlign) {
        structure = MarketStructure.bullTrend;
        confidence = 0.85;
        description = '牛市结构 - 均线多头排列+ADX趋势明确';
        structureScore = 8.0;
        // v2.30: ADX下降中趋势减弱
        if (!adxRising) {
          confidence -= 0.15;
          structureScore -= 1.5;
          description += '(ADX回落)';
        }
      } else if (isBearAlign) {
        structure = MarketStructure.bearTrend;
        confidence = 0.85;
        description = '熊市结构 - 均线空头排列+ADX趋势明确';
        structureScore = 2.0;
        if (!adxRising) {
          confidence -= 0.15;
          structureScore -= 1.0;
          description += '(ADX回落)';
        }
      } else {
        // MA混合但ADX高 → 可能是顶部分配或趋势末期
        structure = MarketStructure.distribution;
        confidence = 0.60;
        description = '顶部分配 - 趋势明确但均线排列混乱';
        structureScore = 3.0;
      }
    } else if (adx < 20) {
      // 盘整区间
      structure = MarketStructure.consolidation;
      confidence = 0.75;
      description = '震荡盘整 - ADX低位，趋势不明确';
      structureScore = 5.0;
    } else {
      // ADX 20-25
      if (isNearMA60 && isVolumeContracting) {
        structure = MarketStructure.accumulation;
        confidence = 0.60;
        description = '底部积累 - 价格在均线附近+成交量萎缩';
        structureScore = 7.0;
        if (adxRising) {
          confidence += 0.10;
          description += '(ADX回升)';
        }
      } else if (isBullAlign) {
        structure = MarketStructure.bullTrend;
        confidence = 0.55;
        description = '牛市结构初期 - 均线多头但ADX尚在形成';
        structureScore = 6.5;
        if (adxRising) {
          confidence += 0.10;
          description += '(ADX回升)';
        }
      } else if (isBearAlign) {
        structure = MarketStructure.bearTrend;
        confidence = 0.55;
        description = '熊市趋势初期 - 均线空头但ADX尚在形成';
        structureScore = 3.0;
        if (adxRising) {
          confidence += 0.10;
          description += '(ADX回升)';
        }
      } else {
        structure = MarketStructure.consolidation;
        confidence = 0.50;
        description = '趋势形成中 - 方向尚不明确';
        structureScore = 5.0;
      }
    }

    return MarketStructureResult(
      structure: structure,
      confidence: confidence,
      adxValue: adx,
      maAlignment: maAlignment,
      description: description,
      compatibleStrategies: _getCompatibleList(structure),
      structureScore: structureScore,
    );
  }

  /// 分类MA排列: 多头 / 空头 / 混合
  static String _classifyMaAlignment(double ma5, double ma10, double ma20, double ma60) {
    // 需要至少MA5/MA10/MA20有效
    if (ma5 <= 0 || ma10 <= 0 || ma20 <= 0) return '混合';

    final bool fullBull = ma5 > ma10 && ma10 > ma20 &&
        (ma60 <= 0 || ma20 > ma60);
    final bool fullBear = ma5 < ma10 && ma10 < ma20 &&
        (ma60 <= 0 || ma20 < ma60);

    if (fullBull) return '多头';
    if (fullBear) return '空头';
    return '混合';
  }

  /// 获取结构名称(中文)
  static String getLabel(MarketStructure structure) {
    switch (structure) {
      case MarketStructure.bullTrend:
        return '牛市结构';
      case MarketStructure.bearTrend:
        return '熊市结构';
      case MarketStructure.consolidation:
        return '震荡盘整';
      case MarketStructure.accumulation:
        return '底部积累';
      case MarketStructure.distribution:
        return '顶部分配';
    }
  }

  /// v2.30: 检查ADX是否在上升（比较最近3根vs前3根）
  static bool _isAdxRising(List<HistoryKline> data) {
    if (data.length < 6) return false;
    final recent = data.sublist(data.length - 3).map((k) => k.adx14).toList();
    final earlier = data.sublist(data.length - 6, data.length - 3).map((k) => k.adx14).toList();
    final recentAvg = recent.fold(0.0, (a, b) => a + b) / 3;
    final earlierAvg = earlier.fold(0.0, (a, b) => a + b) / 3;
    return recentAvg > earlierAvg;
  }
}
