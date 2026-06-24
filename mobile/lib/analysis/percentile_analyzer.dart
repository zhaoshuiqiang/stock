import '../models/stock_models.dart';

/// 分位值分析结果
class PercentileResult {
  /// PE在行业中的分位值 (0-100, 越低估值越低)
  final double pePercentile;

  /// PB在行业中的分位值 (0-100)
  final double pbPercentile;

  /// RSI(14) 数值分位 (0-100)
  final double rsiPercentile;

  /// 近20日成交量分位 (0-100)
  final double volumePercentile;

  /// 综合分位概要
  final String summary;

  /// v2.30: 行业相对强度评分 (0.0-1.0)
  /// 综合低估值+高动量+高活跃度，越高表示在行业中越强
  final double industryRSScore;

  PercentileResult({
    required this.pePercentile,
    required this.pbPercentile,
    required this.rsiPercentile,
    required this.volumePercentile,
    required this.summary,
    this.industryRSScore = 0.5,
  });

  factory PercentileResult.default_() {
    return PercentileResult(
      pePercentile: 50,
      pbPercentile: 50,
      rsiPercentile: 50,
      volumePercentile: 50,
      summary: '分位值数据不足',
      industryRSScore: 0.5,
    );
  }

  factory PercentileResult.fromJson(Map<String, dynamic> json) {
    return PercentileResult(
      pePercentile: (json['pe_percentile'] as num?)?.toDouble() ?? 50,
      pbPercentile: (json['pb_percentile'] as num?)?.toDouble() ?? 50,
      rsiPercentile: (json['rsi_percentile'] as num?)?.toDouble() ?? 50,
      volumePercentile: (json['volume_percentile'] as num?)?.toDouble() ?? 50,
      summary: json['summary'] as String? ?? '',
      industryRSScore: (json['industry_rs_score'] as num?)?.toDouble() ?? 0.5,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'pe_percentile': pePercentile,
      'pb_percentile': pbPercentile,
      'rsi_percentile': rsiPercentile,
      'volume_percentile': volumePercentile,
      'summary': summary,
      'industry_rs_score': industryRSScore,
    };
  }
}

/// 行业PE/PB分位区间 (基于A股市场经验数据)
/// 格式: [低估线, 合理低线, 合理高线, 高估线]
const Map<String, List<double>> _industryPeRanges = {
  '银行': [4, 5, 8, 12],
  '保险': [8, 10, 15, 20],
  '证券': [10, 15, 25, 40],
  '房地产': [5, 8, 15, 25],
  '建筑': [5, 8, 15, 25],
  '煤炭': [5, 8, 15, 25],
  '钢铁': [6, 10, 20, 30],
  '电力': [8, 12, 20, 30],
  '交通运输': [8, 12, 20, 30],
  '白酒': [15, 20, 35, 50],
  '食品饮料': [15, 20, 35, 50],
  '医药': [20, 30, 50, 80],
  '医疗器械': [20, 30, 50, 80],
  '半导体': [25, 40, 70, 100],
  '芯片': [25, 40, 70, 100],
  '计算机': [20, 30, 60, 90],
  '软件': [20, 30, 60, 90],
  '通信': [15, 20, 35, 50],
  '传媒': [15, 20, 40, 60],
  '电子': [20, 30, 50, 80],
  '军工': [25, 40, 70, 100],
  '国防军工': [25, 40, 70, 100],
  '新能源': [15, 25, 45, 70],
  '光伏': [12, 20, 40, 60],
  '汽车': [10, 15, 30, 50],
  '家电': [10, 15, 25, 40],
  '化工': [10, 15, 30, 50],
  '有色金属': [15, 25, 45, 70],
  '农林牧渔': [15, 25, 50, 80],
  '建筑材料': [8, 12, 25, 40],
  '机械设备': [15, 20, 35, 55],
  '石油石化': [8, 12, 25, 40],
  '公用事业': [10, 15, 25, 40],
  '环保': [10, 15, 30, 50],
};

const Map<String, List<double>> _industryPbRanges = {
  '银行': [0.5, 0.6, 1.0, 1.5],
  '保险': [0.8, 1.0, 2.0, 3.0],
  '证券': [1.0, 1.2, 2.5, 4.0],
  '房地产': [0.4, 0.6, 1.0, 1.5],
  '建筑': [0.5, 0.8, 1.5, 2.5],
  '煤炭': [0.6, 0.8, 1.5, 2.5],
  '钢铁': [0.5, 0.8, 1.5, 2.5],
  '电力': [0.6, 0.8, 1.5, 2.5],
  '交通运输': [0.8, 1.0, 2.0, 3.0],
  '白酒': [3, 4, 7, 12],
  '食品饮料': [2, 3, 6, 10],
  '医药': [2, 3, 6, 10],
  '医疗器械': [2, 3, 6, 10],
  '半导体': [2, 3, 6, 10],
  '芯片': [2, 3, 6, 10],
  '计算机': [2, 3, 5, 8],
  '软件': [2, 3, 5, 8],
  '通信': [1, 1.5, 3, 5],
  '传媒': [1, 1.5, 3, 5],
  '电子': [1.5, 2, 4, 7],
  '军工': [2, 3, 5, 8],
  '国防军工': [2, 3, 5, 8],
  '新能源': [1.5, 2, 4, 7],
  '光伏': [1, 1.5, 3, 5],
  '汽车': [1, 1.5, 3, 5],
  '家电': [1.5, 2, 4, 6],
  '化工': [1, 1.5, 3, 5],
  '有色金属': [1.5, 2, 4, 7],
  '农林牧渔': [1.5, 2, 4, 7],
  '建筑材料': [0.8, 1.0, 2.0, 3.5],
  '机械设备': [1.0, 1.5, 3, 5],
  '石油石化': [0.6, 0.8, 1.5, 3],
  '公用事业': [0.8, 1.0, 2.0, 3],
  '环保': [1, 1.5, 2.5, 4],
};

// Default ranges used when industry is unknown
const _defaultPeRange = [12.0, 18.0, 35.0, 60.0];
const _defaultPbRange = [1.0, 1.5, 3.5, 6.0];

/// 分位值分析器
/// 使用行业标准区间 + 技术指标归一化计算各维度分位值
class PercentileAnalyzer {
  /// 分析分位值
  /// [sector] 可选行业名称，用于匹配PE/PB行业区间
  static PercentileResult analyze(
    List<HistoryKline> data,
    QuoteData? quote, {
    String? sector,
  }) {
    // PE分位值
    double pePercentile = 50;
    if (quote != null && quote.pe > 0) {
      final peRange = _matchRange(quote.name, sector, _industryPeRanges, _defaultPeRange);
      pePercentile = _calcPercentile(quote.pe, peRange);
    }

    // PB分位值
    double pbPercentile = 50;
    if (quote != null && quote.pb > 0) {
      final pbRange = _matchRange(quote.name, sector, _industryPbRanges, _defaultPbRange);
      pbPercentile = _calcPercentile(quote.pb, pbRange);
    }

    // RSI分位值: RSI14通常在20-80之间
    double rsiPercentile = 50;
    if (data.isNotEmpty) {
      final rsiVal = data.last.rsi12; // 使用RSI12近似RSI14
      if (rsiVal > 0) {
        rsiPercentile = ((rsiVal - 20) / 60 * 100).clamp(0, 100);
      }
    }

    // 近20日成交量分位值
    double volumePercentile = 50;
    if (data.length >= 20) {
      final recentVolumes = data.sublist(data.length - 20).map((k) => k.volume).toList();
      recentVolumes.sort();
      final currentVol = data.last.volume;
      if (currentVol > 0 && recentVolumes.isNotEmpty) {
        // 计算当前成交量在排序列表中的位置
        int rank = 0;
        for (final v in recentVolumes) {
          if (currentVol >= v) rank++;
        }
        volumePercentile = (rank / recentVolumes.length * 100).clamp(0, 100);
      }
    }

    // 综合概要
    String summary = _buildSummary(pePercentile, pbPercentile, rsiPercentile, volumePercentile);

    // v2.30: 行业相对强度 — 综合低估值+高动量+高活跃度
    final industryRSScore = _calcIndustryRS(data, pePercentile, pbPercentile, rsiPercentile, volumePercentile);

    return PercentileResult(
      pePercentile: pePercentile,
      pbPercentile: pbPercentile,
      rsiPercentile: rsiPercentile,
      volumePercentile: volumePercentile,
      summary: summary,
      industryRSScore: industryRSScore,
    );
  }

  /// 根据行业名称匹配估值区间
  static List<double> _matchRange(
    String stockName,
    String? sector,
    Map<String, List<double>> ranges,
    List<double> defaultRange,
  ) {
    // 先按传入的sector匹配
    if (sector != null) {
      for (final entry in ranges.entries) {
        if (sector.contains(entry.key)) return entry.value;
      }
    }
    // 尝试按股票名称匹配（部分股票名称含行业关键词）
    for (final entry in ranges.entries) {
      if (stockName.contains(entry.key)) return entry.value;
    }
    return defaultRange;
  }

  /// 计算分位值 (0-100)
  /// range: [低估线, 合理低线, 合理高线, 高估线]
  static double _calcPercentile(double value, List<double> range) {
    final low = range[0], fairLow = range[1], fairHigh = range[2], high = range[3];

    if (value <= low) return (value / low * 10).clamp(0, 10);       // 极度低估: 0-10
    if (value <= fairLow) return 10 + (value - low) / (fairLow - low) * 20; // 低估: 10-30
    if (value <= fairHigh) return 30 + (value - fairLow) / (fairHigh - fairLow) * 40; // 合理: 30-70
    if (value <= high) return 70 + (value - fairHigh) / (high - fairHigh) * 20; // 高估: 70-90
    return 90 + ((value - high) / (high * 0.5)).clamp(0, 1) * 10; // 极度高估: 90-100
  }

  static String _buildSummary(double pePct, double pbPct, double rsiPct, double volPct) {
    final parts = <String>[];
    if (pePct <= 30) {
      parts.add('PE低估(${pePct.toInt()}%)');
    } else if (pePct >= 70) {
      parts.add('PE高估(${pePct.toInt()}%)');
    }
    if (pbPct <= 30) {
      parts.add('PB低估(${pbPct.toInt()}%)');
    } else if (pbPct >= 70) {
      parts.add('PB高估(${pbPct.toInt()}%)');
    }
    if (rsiPct >= 80) {
      parts.add('RSI超买(${rsiPct.toInt()}%)');
    } else if (rsiPct <= 20) {
      parts.add('RSI超卖(${rsiPct.toInt()}%)');
    }
    if (volPct >= 80) {
      parts.add('放量(${volPct.toInt()}%)');
    } else if (volPct <= 20) {
      parts.add('缩量(${volPct.toInt()}%)');
    }
    return parts.isEmpty ? '分位正常' : parts.join('·');
  }

  /// v2.30: 行业相对强度
  /// 综合低估值(30%)+高动量(30%)+高活跃度(20%)+低PB(20%)
  /// 返回 0.0-1.0，越高表示在自身历史区间中越强
  static double _calcIndustryRS(
    List<HistoryKline> data,
    double pePercentile,
    double pbPercentile,
    double rsiPercentile,
    double volumePercentile,
  ) {
    // 使用5日涨幅作为动量分位
    double changePercentile = 0.5;
    if (data.length >= 6) {
      final close5ago = data[data.length - 6].close;
      if (close5ago > 0) {
        final change5d = (data.last.close / close5ago - 1) * 100;
        // 5日涨幅归一化: -10%~10% 映射到 0~100
        changePercentile = ((change5d + 10) / 20 * 100).clamp(0, 100) / 100;
      }
    }

    // 低PE=好(反向), 高RSI=强动量, 高量=活跃, 低PB=好(反向)
    final rs = 0.25 * (100 - pePercentile) / 100 +
               0.25 * rsiPercentile / 100 +
               0.20 * volumePercentile / 100 +
               0.20 * (100 - pbPercentile) / 100 +
               0.10 * changePercentile;
    return rs.clamp(0.0, 1.0);
  }
}
