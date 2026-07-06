import '../analysis/strategy_engine.dart';
import '../analysis/backtest_engine.dart';
import '../analysis/market_structure_analyzer.dart';
import '../analysis/percentile_analyzer.dart';
import '../analysis/limit_up_analyzer.dart';

enum DataConfidence { high, medium, low }

enum SignalDuration {
  shortTerm,    // 短期：2-5天
  mediumTerm,   // 中期：5-20天
  longTerm,     // 长期：20-60天
}

class ValidatedQuoteData {
  final QuoteData quote;
  final DataConfidence confidence;
  final String? validationNote;

  ValidatedQuoteData({
    required this.quote,
    this.confidence = DataConfidence.high,
    this.validationNote,
  });
}

class StockInfo {
  final String code;
  final String name;
  final String display;

  StockInfo({
    required this.code,
    required this.name,
    required this.display,
  });

  factory StockInfo.fromJson(Map<String, dynamic> json) {
    return StockInfo(
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      display: json['display'] ?? '${json['name'] ?? ''}(${json['code'] ?? ''})',
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'display': display,
  };
}

class QuoteData {
  final String code;
  final String name;
  final double price;
  final double change;
  final double changePct;
  final double open;
  final double high;
  final double low;
  final double preClose;
  final double volume;
  final double amount;
  final double amplitude;
  final double turnover;
  final double pe;
  final double pb;
  final double totalMarketCap;
  final double circulatingMarketCap;
  double mainInflow;
  double mainOutflow;
  double mainNetFlow;
  double mainNetFlowRate;
  final double volumeRatio;
  final DateTime? updateTime;
  final String confidence;
  final String sectorName;

  QuoteData({
    required this.code,
    this.name = '',
    this.price = 0,
    this.change = 0,
    this.changePct = 0,
    this.open = 0,
    this.high = 0,
    this.low = 0,
    this.preClose = 0,
    this.volume = 0,
    this.amount = 0,
    this.amplitude = 0,
    this.turnover = 0,
    this.pe = 0,
    this.pb = 0,
    this.totalMarketCap = 0,
    this.circulatingMarketCap = 0,
    this.mainInflow = 0,
    this.mainOutflow = 0,
    this.mainNetFlow = 0,
    this.mainNetFlowRate = 0,
    this.volumeRatio = 0,
    this.updateTime,
    this.confidence = 'high',
    this.sectorName = '',
  });

  factory QuoteData.fromJson(Map<String, dynamic> json) {
    return QuoteData(
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      price: _parseDouble(json['price']),
      change: _parseDouble(json['change']),
      changePct: _parseDouble(json['change_pct']),
      open: _parseDouble(json['open']),
      high: _parseDouble(json['high']),
      low: _parseDouble(json['low']),
      preClose: _parseDouble(json['pre_close']),
      volume: _parseDouble(json['volume']),
      amount: _parseDouble(json['amount']),
      amplitude: _parseDouble(json['amplitude']),
      turnover: _parseDouble(json['turnover']),
      pe: _parseDouble(json['pe']),
      pb: _parseDouble(json['pb']),
      totalMarketCap: _parseDouble(json['total_market_cap']),
      circulatingMarketCap: _parseDouble(json['circulating_market_cap']),
      mainInflow: _parseDouble(json['main_inflow']),
      mainOutflow: _parseDouble(json['main_outflow']),
      mainNetFlow: _parseDouble(json['main_net_flow']),
      mainNetFlowRate: _parseDouble(json['main_net_flow_rate']),
      updateTime: json['update_time'] != null ? DateTime.tryParse(json['update_time']) : null,
      confidence: json['confidence'] ?? 'high',
      sectorName: json['sector_name'] ?? '',
    );
  }

  static double parseDouble(dynamic value) => _parseDouble(value);

  static double _parseDouble(dynamic value) {
    if (value == null) return 0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0;
    return 0;
  }

  static QuoteData empty() {
    return QuoteData(code: '', name: '');
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'price': price,
      'change': change,
      'change_pct': changePct,
      'open': open,
      'high': high,
      'low': low,
      'pre_close': preClose,
      'volume': volume,
      'amount': amount,
      'amplitude': amplitude,
      'turnover': turnover,
      'pe': pe,
      'pb': pb,
      'total_market_cap': totalMarketCap,
      'circulating_market_cap': circulatingMarketCap,
      'main_inflow': mainInflow,
      'main_outflow': mainOutflow,
      'main_net_flow': mainNetFlow,
      'main_net_flow_rate': mainNetFlowRate,
      'update_time': updateTime?.toIso8601String(),
      'confidence': confidence,
    };
  }

  QuoteData copyWith({
    String? code,
    String? name,
    double? price,
    double? change,
    double? changePct,
    double? open,
    double? high,
    double? low,
    double? preClose,
    double? volume,
    double? amount,
    double? amplitude,
    double? turnover,
    double? pe,
    double? pb,
    double? totalMarketCap,
    double? circulatingMarketCap,
    double? mainInflow,
    double? mainOutflow,
    double? mainNetFlow,
    double? mainNetFlowRate,
    double? volumeRatio,
    DateTime? updateTime,
    String? confidence,
    String? sectorName,
  }) {
    return QuoteData(
      code: code ?? this.code,
      name: name ?? this.name,
      price: price ?? this.price,
      change: change ?? this.change,
      changePct: changePct ?? this.changePct,
      open: open ?? this.open,
      high: high ?? this.high,
      low: low ?? this.low,
      preClose: preClose ?? this.preClose,
      volume: volume ?? this.volume,
      amount: amount ?? this.amount,
      amplitude: amplitude ?? this.amplitude,
      turnover: turnover ?? this.turnover,
      pe: pe ?? this.pe,
      pb: pb ?? this.pb,
      totalMarketCap: totalMarketCap ?? this.totalMarketCap,
      circulatingMarketCap: circulatingMarketCap ?? this.circulatingMarketCap,
      mainInflow: mainInflow ?? this.mainInflow,
      mainOutflow: mainOutflow ?? this.mainOutflow,
      mainNetFlow: mainNetFlow ?? this.mainNetFlow,
      mainNetFlowRate: mainNetFlowRate ?? this.mainNetFlowRate,
      volumeRatio: volumeRatio ?? this.volumeRatio,
      updateTime: updateTime ?? this.updateTime,
      confidence: confidence ?? this.confidence,
      sectorName: sectorName ?? this.sectorName,
    );
  }
}

class HistoryKline {
  final DateTime date;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
  final double amount;
  final double amplitude;
  final double changePct;
  final double change;
  final double turnover;
  final double ma5;
  final double ma10;
  final double ma20;
  final double ma60;
  final double volMa5;
  final double volMa10;
  final double macdDif;
  final double macdDea;
  final double macdHist;
  final double rsi6;
  final double rsi12;
  final double rsi24;
  final double k;
  final double d;
  final double j;
  final double bollUpper;
  final double bollMid;
  final double bollLower;
  final double ema5;
  final double ema10;
  final double ema20;
  final double ema60;
  final double atr14;
  final double obv;
  final double bias6;
  final double bias12;
  final double bias24;
  final double plusDi14;
  final double minusDi14;
  final double dx;
  final double adx14;
  final double? wr14;
  final double? cci14;

  HistoryKline({
    required this.date,
    this.open = 0,
    this.high = 0,
    this.low = 0,
    this.close = 0,
    this.volume = 0,
    this.amount = 0,
    this.amplitude = 0,
    this.changePct = 0,
    this.change = 0,
    this.turnover = 0,
    this.ma5 = 0,
    this.ma10 = 0,
    this.ma20 = 0,
    this.ma60 = 0,
    this.volMa5 = 0,
    this.volMa10 = 0,
    this.macdDif = 0,
    this.macdDea = 0,
    this.macdHist = 0,
    this.rsi6 = 0,
    this.rsi12 = 0,
    this.rsi24 = 0,
    this.k = 0,
    this.d = 0,
    this.j = 0,
    this.bollUpper = 0,
    this.bollMid = 0,
    this.bollLower = 0,
    this.ema5 = 0,
    this.ema10 = 0,
    this.ema20 = 0,
    this.ema60 = 0,
    this.atr14 = 0,
    this.obv = 0,
    this.bias6 = 0,
    this.bias12 = 0,
    this.bias24 = 0,
    this.plusDi14 = 0,
    this.minusDi14 = 0,
    this.dx = 0,
    this.adx14 = 0,
    this.wr14,
    this.cci14,
  });

  HistoryKline copyWith({
    DateTime? date,
    double? open,
    double? high,
    double? low,
    double? close,
    double? volume,
    double? amount,
    double? amplitude,
    double? changePct,
    double? change,
    double? turnover,
    double? ma5,
    double? ma10,
    double? ma20,
    double? ma60,
    double? volMa5,
    double? volMa10,
    double? macdDif,
    double? macdDea,
    double? macdHist,
    double? rsi6,
    double? rsi12,
    double? rsi24,
    double? k,
    double? d,
    double? j,
    double? bollUpper,
    double? bollMid,
    double? bollLower,
    double? ema5,
    double? ema10,
    double? ema20,
    double? ema60,
    double? atr14,
    double? obv,
    double? bias6,
    double? bias12,
    double? bias24,
    double? plusDi14,
    double? minusDi14,
    double? dx,
    double? adx14,
    double? wr14,
    double? cci14,
  }) {
    return HistoryKline(
      date: date ?? this.date,
      open: open ?? this.open,
      high: high ?? this.high,
      low: low ?? this.low,
      close: close ?? this.close,
      volume: volume ?? this.volume,
      amount: amount ?? this.amount,
      amplitude: amplitude ?? this.amplitude,
      changePct: changePct ?? this.changePct,
      change: change ?? this.change,
      turnover: turnover ?? this.turnover,
      ma5: ma5 ?? this.ma5,
      ma10: ma10 ?? this.ma10,
      ma20: ma20 ?? this.ma20,
      ma60: ma60 ?? this.ma60,
      volMa5: volMa5 ?? this.volMa5,
      volMa10: volMa10 ?? this.volMa10,
      macdDif: macdDif ?? this.macdDif,
      macdDea: macdDea ?? this.macdDea,
      macdHist: macdHist ?? this.macdHist,
      rsi6: rsi6 ?? this.rsi6,
      rsi12: rsi12 ?? this.rsi12,
      rsi24: rsi24 ?? this.rsi24,
      k: k ?? this.k,
      d: d ?? this.d,
      j: j ?? this.j,
      bollUpper: bollUpper ?? this.bollUpper,
      bollMid: bollMid ?? this.bollMid,
      bollLower: bollLower ?? this.bollLower,
      ema5: ema5 ?? this.ema5,
      ema10: ema10 ?? this.ema10,
      ema20: ema20 ?? this.ema20,
      ema60: ema60 ?? this.ema60,
      atr14: atr14 ?? this.atr14,
      obv: obv ?? this.obv,
      bias6: bias6 ?? this.bias6,
      bias12: bias12 ?? this.bias12,
      bias24: bias24 ?? this.bias24,
      plusDi14: plusDi14 ?? this.plusDi14,
      minusDi14: minusDi14 ?? this.minusDi14,
      dx: dx ?? this.dx,
      adx14: adx14 ?? this.adx14,
      wr14: wr14 ?? this.wr14,
      cci14: cci14 ?? this.cci14,
    );
  }

  factory HistoryKline.fromJson(Map<String, dynamic> json) {
    DateTime date = DateTime.now();
    if (json['date'] != null) {
      if (json['date'] is String) {
        date = DateTime.tryParse(json['date']) ?? DateTime.now();
      }
    }

    return HistoryKline(
      date: date,
      open: QuoteData._parseDouble(json['open']),
      high: QuoteData._parseDouble(json['high']),
      low: QuoteData._parseDouble(json['low']),
      close: QuoteData._parseDouble(json['close']),
      volume: QuoteData._parseDouble(json['volume']),
      amount: QuoteData._parseDouble(json['amount']),
      amplitude: QuoteData._parseDouble(json['amplitude']),
      changePct: QuoteData._parseDouble(json['change_pct']),
      change: QuoteData._parseDouble(json['change']),
      turnover: QuoteData._parseDouble(json['turnover']),
      ma5: QuoteData._parseDouble(json['ma5']),
      ma10: QuoteData._parseDouble(json['ma10']),
      ma20: QuoteData._parseDouble(json['ma20']),
      ma60: QuoteData._parseDouble(json['ma60']),
      volMa5: QuoteData._parseDouble(json['volMa5']),
      volMa10: QuoteData._parseDouble(json['volMa10']),
      macdDif: QuoteData._parseDouble(json['macd_dif']),
      macdDea: QuoteData._parseDouble(json['macd_dea']),
      macdHist: QuoteData._parseDouble(json['macd_hist']),
      rsi6: QuoteData._parseDouble(json['rsi6']),
      rsi12: QuoteData._parseDouble(json['rsi12']),
      rsi24: QuoteData._parseDouble(json['rsi24']),
      k: QuoteData._parseDouble(json['k']),
      d: QuoteData._parseDouble(json['d']),
      j: QuoteData._parseDouble(json['j']),
      bollUpper: QuoteData._parseDouble(json['boll_upper']),
      bollMid: QuoteData._parseDouble(json['boll_mid']),
      bollLower: QuoteData._parseDouble(json['boll_lower']),
      ema5: QuoteData._parseDouble(json['ema5']),
      ema10: QuoteData._parseDouble(json['ema10']),
      ema20: QuoteData._parseDouble(json['ema20']),
      ema60: QuoteData._parseDouble(json['ema60']),
      atr14: QuoteData._parseDouble(json['atr14']),
      obv: QuoteData._parseDouble(json['obv']),
      bias6: QuoteData._parseDouble(json['bias6']),
      bias12: QuoteData._parseDouble(json['bias12']),
      bias24: QuoteData._parseDouble(json['bias24']),
      plusDi14: QuoteData._parseDouble(json['plus_di14']),
      minusDi14: QuoteData._parseDouble(json['minus_di14']),
      dx: QuoteData._parseDouble(json['dx']),
      adx14: QuoteData._parseDouble(json['adx14']),
      wr14: QuoteData._parseDouble(json['wr14']),
      cci14: QuoteData._parseDouble(json['cci14']),
    );
  }
}

class SignalItem {
  final String type;
  final String indicator;
  final String signal;
  final String description;
  final String desc;
  final int strength;
  final DateTime? timestamp;

  // 新增字段
  final SignalDuration? duration;           // 短期/中期/长期
  final double? confidence;           // 推荐可信度（0.0-1.0）
  final int signalCount;              // 共振信号数量（多指标共振度）
  final DateTime? freshTime;          // 指标新鲜度（最近3-5天）

  SignalItem({
    required this.type,
    this.indicator = '',
    this.signal = '',
    this.description = '',
    this.desc = '',
    this.strength = 0,
    this.timestamp,
    this.duration,
    this.confidence,
    this.signalCount = 1,
    this.freshTime,
  });

  factory SignalItem.fromJson(Map<String, dynamic> json) {
    final descValue = json['desc'] ?? json['description'] ?? '';
    return SignalItem(
      type: json['type'] ?? 'buy',
      indicator: json['indicator'] ?? '',
      signal: json['signal'] ?? '',
      description: descValue,
      desc: descValue,
      strength: json['strength'] is int ? json['strength'] : 0,
      timestamp: json['timestamp'] != null ? DateTime.tryParse(json['timestamp']) : null,
      duration: json['duration'] != null
          ? _parseDuration(json['duration'])
          : null,
      confidence: json['confidence'] is num ? (json['confidence'] as num).toDouble() : null,
      signalCount: json['signal_count'] is int ? json['signal_count'] : 1,
      freshTime: json['fresh_time'] != null ? DateTime.tryParse(json['fresh_time']) : null,
    );
  }

  static SignalDuration? _parseDuration(dynamic value) {
    if (value == null) return null;
    if (value is int) {
      switch (value) {
        case 0: return SignalDuration.shortTerm;
        case 1: return SignalDuration.mediumTerm;
        case 2: return SignalDuration.longTerm;
        default: return null;
      }
    }
    if (value is String) {
      if (value.startsWith('short')) return SignalDuration.shortTerm;
      if (value.startsWith('medium')) return SignalDuration.mediumTerm;
      if (value.startsWith('long')) return SignalDuration.longTerm;
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'indicator': indicator,
      'signal': signal,
      'description': description,
      'desc': desc,
      'strength': strength,
      'timestamp': timestamp?.toIso8601String(),
      'duration': duration != null ? duration!.index.toString() : null,
      'confidence': confidence?.toDouble(),
      'signal_count': signalCount,
      'fresh_time': freshTime?.toIso8601String(),
    };
  }

  SignalItem copyWith({
    String? type,
    String? indicator,
    String? signal,
    String? description,
    String? desc,
    int? strength,
    DateTime? timestamp,
    SignalDuration? duration,
    double? confidence,
    int? signalCount,
    DateTime? freshTime,
  }) {
    return SignalItem(
      type: type ?? this.type,
      indicator: indicator ?? this.indicator,
      signal: signal ?? this.signal,
      description: description ?? this.description,
      desc: desc ?? this.desc,
      strength: strength ?? this.strength,
      timestamp: timestamp ?? this.timestamp,
      duration: duration ?? this.duration,
      confidence: confidence ?? this.confidence,
      signalCount: signalCount ?? this.signalCount,
      freshTime: freshTime ?? this.freshTime,
    );
  }
}

/// 基本面评分 - 参考 TradingAgents Fundamental Analyst
class FundamentalScore {
  final double valuationScore;    // 估值评分(0-10): PE + PB
  final double capitalFlowScore;  // 资金评分(0-10): 主力净流入率
  final double liquidityScore;    // 流动性评分(0-10): 换手率 + 成交额
  final double totalScore;        // 总分(0-10): 估值40% + 资金35% + 流动性25%
  final List<String> factors;     // 评分因素说明

  FundamentalScore({
    required this.valuationScore,
    required this.capitalFlowScore,
    required this.liquidityScore,
    required this.totalScore,
    required this.factors,
  });

  Map<String, dynamic> toJson() => {
    'valuation_score': valuationScore,
    'capital_flow_score': capitalFlowScore,
    'liquidity_score': liquidityScore,
    'total_score': totalScore,
    'factors': factors,
  };

  factory FundamentalScore.fromJson(Map<String, dynamic> json) {
    return FundamentalScore(
      valuationScore: (json['valuation_score'] as num?)?.toDouble() ?? 5.0,
      capitalFlowScore: (json['capital_flow_score'] as num?)?.toDouble() ?? 5.0,
      liquidityScore: (json['liquidity_score'] as num?)?.toDouble() ?? 5.0,
      totalScore: (json['total_score'] as num?)?.toDouble() ?? 5.0,
      factors: (json['factors'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}

/// 对抗验证信号 - 参考 TradingAgents Bull/Bear Researcher
class ValidatedSignal {
  final SignalItem signal;
  final List<String> counterPoints;   // 反向视角论点（买入→Bear反对，卖出→Bull支撑）
  final double adjustedConfidence;    // 调整后置信度

  ValidatedSignal({
    required this.signal,
    required this.counterPoints,
    required this.adjustedConfidence,
  });

  Map<String, dynamic> toJson() => {
    'signal': signal.toJson(),
    'counter_points': counterPoints,
    'adjusted_confidence': adjustedConfidence,
  };

  factory ValidatedSignal.fromJson(Map<String, dynamic> json) {
    return ValidatedSignal(
      signal: SignalItem.fromJson(json['signal'] as Map<String, dynamic>),
      counterPoints: (json['counter_points'] as List?)?.map((e) => e.toString()).toList() ?? [],
      adjustedConfidence: (json['adjusted_confidence'] as num?)?.toDouble() ?? 0.5,
    );
  }
}

/// 新闻情绪评分 - 参考 TradingAgents Sentiment/News Analyst
class NewsSentiment {
  final double score;              // 情绪评分(-10 ~ +10)
  final int positiveCount;         // 利好新闻数
  final int negativeCount;         // 利空新闻数
  final int neutralCount;          // 中性新闻数
  final List<String> keyFactors;   // 关键影响因素

  NewsSentiment({
    required this.score,
    required this.positiveCount,
    required this.negativeCount,
    required this.neutralCount,
    required this.keyFactors,
  });

  /// 情绪方向: positive / negative / neutral
  String get direction {
    if (score > 2) return 'positive';
    if (score < -2) return 'negative';
    return 'neutral';
  }

  Map<String, dynamic> toJson() => {
    'score': score,
    'positive_count': positiveCount,
    'negative_count': negativeCount,
    'neutral_count': neutralCount,
    'key_factors': keyFactors,
  };

  factory NewsSentiment.fromJson(Map<String, dynamic> json) {
    return NewsSentiment(
      score: (json['score'] as num?)?.toDouble() ?? 0,
      positiveCount: (json['positive_count'] as num?)?.toInt() ?? 0,
      negativeCount: (json['negative_count'] as num?)?.toInt() ?? 0,
      neutralCount: (json['neutral_count'] as num?)?.toInt() ?? 0,
      keyFactors: (json['key_factors'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}

class MarketContext {
  final double shIndexPct;          // 上证指数涨跌幅
  final double szIndexPct;          // 深证成指涨跌幅
  final double indexChange;         // 上证指数涨跌额
  final String marketTrend;         // 大盘趋势（'strong_up' / 'up' / 'neutral' / 'down' / 'strong_down'）
  final int upCount;                // 涨停家数
  final int downCount;              // 跌停家数
  final double avgChangePct;        // 平均涨跌幅
  final DateTime updateTime;

  MarketContext({
    required this.shIndexPct,
    required this.szIndexPct,
    required this.indexChange,
    required this.marketTrend,
    required this.upCount,
    required this.downCount,
    required this.avgChangePct,
    required this.updateTime,
  });

  factory MarketContext.fromJson(Map<String, dynamic> json) {
    return MarketContext(
      shIndexPct: QuoteData._parseDouble(json['sh_index_pct'] ?? json['上证指数'] ?? 0),
      szIndexPct: QuoteData._parseDouble(json['sz_index_pct'] ?? json['深证成指'] ?? 0),
      indexChange: QuoteData._parseDouble(json['index_change'] ?? 0),
      marketTrend: json['market_trend'] ?? 'neutral',
      upCount: json['up_count'] ?? 0,
      downCount: json['down_count'] ?? 0,
      avgChangePct: QuoteData.parseDouble(json['avg_change_pct'] ?? 0),
      updateTime: json['update_time'] != null
          ? (DateTime.tryParse(json['update_time']) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  /// 获取市场调节系数（大盘上涨时，个股评分适当提高；大盘下跌时，评分降低）
  /// 极端普涨日（市场宽度 >= 3:1 且涨幅 > 1%）：中性化，避免追涨式推荐
  double getMarketAdjustmentFactor() {
    final total = upCount + downCount;
    final breadth = total > 0 ? upCount / total : 0.5;

    // 极端普涨日：涨跌比 >= 3:1 且平均涨幅 > 1%，中性化
    if (breadth >= 0.75 && avgChangePct > 1.0) {
      return 1.0;
    }

    if (avgChangePct > 1.5) return 1.04;    // 强势上涨：+4%（原+8%）
    if (avgChangePct > 0.5) return 1.02;    // 上涨：+2%（原+4%）
    if (avgChangePct > -0.5) return 1.00;   // 震荡：0%
    if (avgChangePct > -1.5) return 0.96;   // 下跌：-4%
    return 0.92;                             // 强势下跌：-8%
  }

  Map<String, dynamic> toJson() {
    return {
      'sh_index_pct': shIndexPct,
      'sz_index_pct': szIndexPct,
      'index_change': indexChange,
      'market_trend': marketTrend,
      'up_count': upCount,
      'down_count': downCount,
      'avg_change_pct': avgChangePct,
      'update_time': updateTime?.toIso8601String(),
    };
  }
}

class RecommendationReason {
  final String title;
  final String description;
  final double confidence;
  final String duration;

  RecommendationReason({
    required this.title,
    required this.description,
    required this.confidence,
    required this.duration,
  });

  factory RecommendationReason.fromJson(Map<String, dynamic> json) {
    return RecommendationReason(
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      confidence: json['confidence'] is num ? (json['confidence'] as num).toDouble() : 0.5,
      duration: json['duration'] ?? '未知',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'confidence': confidence,
      'duration': duration,
    };
  }
}

class TechnicalAnalysisData {
  final String code;
  final String name;
  final List<double> supportLevels;
  final List<double> resistanceLevels;
  final double? nearestSupport;
  final double? nearestResistance;
  final Map<String, dynamic>? dragonRetreat;
  final Map<String, dynamic>? fibonacci;
  final Map<String, dynamic> trendSignals;

  TechnicalAnalysisData({
    required this.code,
    required this.name,
    this.supportLevels = const [],
    this.resistanceLevels = const [],
    this.nearestSupport,
    this.nearestResistance,
    this.dragonRetreat,
    this.fibonacci,
    this.trendSignals = const {},
  });

  factory TechnicalAnalysisData.fromJson(Map<String, dynamic> json) {
    return TechnicalAnalysisData(
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      supportLevels: (json['support_levels'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [],
      resistanceLevels: (json['resistance_levels'] as List<dynamic>?)?.map((e) => (e as num).toDouble()).toList() ?? [],
      nearestSupport: json['nearest_support'] != null ? (json['nearest_support'] as num).toDouble() : null,
      nearestResistance: json['nearest_resistance'] != null ? (json['nearest_resistance'] as num).toDouble() : null,
      dragonRetreat: json['dragon_retreat'] as Map<String, dynamic>?,
      fibonacci: json['fibonacci'] as Map<String, dynamic>?,
      trendSignals: json['trend_signals'] as Map<String, dynamic>? ?? {},
    );
  }
}

class AnalysisResult {
  final QuoteData? quote;
  final Map<String, dynamic> indicators;
  final List<SignalItem> signals;
  final int score;
  final String recommendation;
  final String riskLevel;
  final List<String> riskFactors;
  final List<String> suggestions;
  final Map<String, dynamic>? tradeLevels;
  final int confluenceScore;
  final List<Map<String, dynamic>> confluenceDetails;
  final List<String> reasons;
  final List<Map<String, String>> opportunities;

  // 新增字段
  final List<TradingStrategy> shortTermStrategies;   // 短线策略列表
  final List<TradingStrategy> longTermStrategies;     // 长线策略列表
  final MarketContext? marketContext;               // 市场环境
  final double confidenceScore;                     // 推荐可信度（0.0-1.0）
  final List<RecommendationReason> detailedReasons;  // 详细推荐理由
  final Map<String, BacktestResult>? backtestResults; // 回测结果
  final String? backtestSummary; // 回测综合摘要

  // 多维分析新增字段 - 参考 TradingAgents
  final FundamentalScore? fundamentalScore;          // 基本面评分
  final NewsSentiment? newsSentiment;                // 新闻情绪
  final List<ValidatedSignal>? validatedSignals;     // 对抗验证信号
  final Map<String, double>? confidenceBreakdown;    // 置信度分项明细

  // 市场结构 + 概念 + 分位值 (Phase 1-4)
  final MarketStructureResult? marketStructure;      // 市场结构分析结果
  final Map<String, List<String>>? conceptTags;       // 概念标签 {'long': [...], 'short': [...]}
  final PercentileResult? percentile;                 // 分位值分析结果

  // 打板分析 (Phase 激活孤儿模块)
  final LimitUpAnalysis? limitUpAnalysis;             // 涨停/连板分析结果

  AnalysisResult({
    this.quote,
    this.indicators = const {},
    this.signals = const [],
    this.score = 0,
    this.recommendation = '',
    this.riskLevel = '中等',
    this.riskFactors = const [],
    this.suggestions = const [],
    this.tradeLevels,
    this.confluenceScore = 0,
    this.confluenceDetails = const [],
    this.reasons = const [],
    this.opportunities = const [],
    this.shortTermStrategies = const [],
    this.longTermStrategies = const [],
    this.marketContext,
    this.confidenceScore = 0.5,
    this.detailedReasons = const [],
    this.backtestResults,
    this.backtestSummary,
    this.fundamentalScore,
    this.newsSentiment,
    this.validatedSignals,
    this.confidenceBreakdown,
    this.marketStructure,
    this.conceptTags,
    this.percentile,
    this.limitUpAnalysis,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    List<SignalItem> signals = [];
    if (json['signals'] != null && json['signals'] is List) {
      signals = (json['signals'] as List)
          .map((s) => SignalItem.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    List<TradingStrategy> shortTermStrategies = [];
    if (json['short_term_strategies'] != null && json['short_term_strategies'] is List) {
      shortTermStrategies = (json['short_term_strategies'] as List)
          .map((s) => TradingStrategy.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    List<TradingStrategy> longTermStrategies = [];
    if (json['long_term_strategies'] != null && json['long_term_strategies'] is List) {
      longTermStrategies = (json['long_term_strategies'] as List)
          .map((s) => TradingStrategy.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    List<ValidatedSignal>? validatedSignals;
    if (json['validated_signals'] != null && json['validated_signals'] is List) {
      validatedSignals = (json['validated_signals'] as List)
          .map((s) => ValidatedSignal.fromJson(s as Map<String, dynamic>))
          .toList();
    }

    Map<String, double>? confidenceBreakdown;
    if (json['confidence_breakdown'] != null && json['confidence_breakdown'] is Map) {
      confidenceBreakdown = (json['confidence_breakdown'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble()));
    }

    return AnalysisResult(
      quote: json['quote'] != null
          ? QuoteData.fromJson(json['quote'] as Map<String, dynamic>)
          : null,
      indicators: json['indicators'] as Map<String, dynamic>? ?? {},
      signals: signals,
      score: json['score'] ?? 0,
      recommendation: json['recommendation'] ?? json['advice'] ?? '',
      riskLevel: json['risk_level'] ?? json['risk'] ?? '中等',
      riskFactors: json['risk_factors'] != null ? List<String>.from(json['risk_factors']) : [],
      suggestions: json['suggestions'] != null ? List<String>.from(json['suggestions']) : [],
      reasons: json['reasons'] != null ? List<String>.from(json['reasons']) : [],
      opportunities: json['opportunities'] != null
          ? (json['opportunities'] as List).map((e) => Map<String, String>.from(e as Map)).toList()
          : [],
      shortTermStrategies: shortTermStrategies,
      longTermStrategies: longTermStrategies,
      marketContext: json['market_context'] != null
          ? MarketContext.fromJson(json['market_context'] as Map<String, dynamic>)
          : null,
      confidenceScore: json['confidence_score'] is num ? (json['confidence_score'] as num).toDouble() : 0.5,
      detailedReasons: json['detailed_reasons'] != null
          ? (json['detailed_reasons'] as List).map((e) => RecommendationReason.fromJson(e as Map<String, dynamic>)).toList()
          : [],
      backtestResults: json['backtest_results'] != null
          ? (json['backtest_results'] as Map<String, dynamic>).map((k, v) => MapEntry(k, BacktestResult.fromJson(v as Map<String, dynamic>)))
          : null,
      backtestSummary: json['backtest_summary'] as String?,
      fundamentalScore: json['fundamental_score'] != null
          ? FundamentalScore.fromJson(json['fundamental_score'] as Map<String, dynamic>)
          : null,
      newsSentiment: json['news_sentiment'] != null
          ? NewsSentiment.fromJson(json['news_sentiment'] as Map<String, dynamic>)
          : null,
      validatedSignals: validatedSignals,
      confidenceBreakdown: confidenceBreakdown,
      marketStructure: json['market_structure'] != null
          ? MarketStructureResult.fromJson(json['market_structure'] as Map<String, dynamic>)
          : null,
      conceptTags: json['concept_tags'] != null
          ? (json['concept_tags'] as Map<String, dynamic>).map(
              (k, v) => MapEntry(k, List<String>.from(v as List)))
          : null,
      percentile: json['percentile'] != null
          ? PercentileResult.fromJson(json['percentile'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'quote': quote?.toJson(),
      'indicators': indicators,
      'signals': signals.map((s) => s.toJson()).toList(),
      'score': score,
      'recommendation': recommendation,
      'risk_level': riskLevel,
      'risk_factors': riskFactors,
      'suggestions': suggestions,
      'trade_levels': tradeLevels,
      'confluence_score': confluenceScore,
      'confluence_details': confluenceDetails,
      'reasons': reasons,
      'opportunities': opportunities,
      'short_term_strategies': shortTermStrategies.map((s) => s.toJson()).toList(),
      'long_term_strategies': longTermStrategies.map((s) => s.toJson()).toList(),
      'market_context': marketContext?.toJson(),
      'confidence_score': confidenceScore,
      'detailed_reasons': detailedReasons.map((r) => {
        'title': r.title,
        'description': r.description,
        'confidence': r.confidence,
        'duration': r.duration,
      }).toList(),
      'backtest_results': backtestResults?.map((k, v) => MapEntry(k, v.toJson())),
      'backtest_summary': backtestSummary,
      'fundamental_score': fundamentalScore?.toJson(),
      'news_sentiment': newsSentiment?.toJson(),
      'validated_signals': validatedSignals?.map((s) => s.toJson()).toList(),
      'confidence_breakdown': confidenceBreakdown,
      'market_structure': marketStructure?.toJson(),
      'concept_tags': conceptTags,
      'percentile': percentile?.toJson(),
    };
  }
}

class AlertRule {
  final int id;
  final String code;
  final String name;
  final String conditionType;
  final double thresholdValue;
  final DateTime createdAt;
  final bool enabled;
  final DateTime? lastTriggeredAt;
  final String alertType;
  final double? threshold;
  final String indicatorType;

  AlertRule({
    this.id = 0,
    required this.code,
    this.name = '',
    this.conditionType = '',
    this.thresholdValue = 0,
    DateTime? createdAt,
    this.enabled = true,
    this.lastTriggeredAt,
    this.alertType = '',
    this.threshold,
    this.indicatorType = '',
  }) : createdAt = createdAt ?? DateTime.now();

  AlertRule copyWith({
    int? id,
    String? code,
    String? name,
    String? conditionType,
    double? thresholdValue,
    DateTime? createdAt,
    bool? enabled,
    DateTime? lastTriggeredAt,
    String? alertType,
    double? threshold,
    String? indicatorType,
  }) {
    return AlertRule(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      conditionType: conditionType ?? this.conditionType,
      thresholdValue: thresholdValue ?? this.thresholdValue,
      createdAt: createdAt ?? this.createdAt,
      enabled: enabled ?? this.enabled,
      lastTriggeredAt: lastTriggeredAt ?? this.lastTriggeredAt,
      alertType: alertType ?? this.alertType,
      threshold: threshold ?? this.threshold,
      indicatorType: indicatorType ?? this.indicatorType,
    );
  }

  factory AlertRule.fromJson(Map<String, dynamic> json) {
    return AlertRule(
      id: json['id'] is int ? json['id'] : 0,
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      conditionType: json['condition_type'] ?? json['alert_type'] ?? '',
      thresholdValue: QuoteData._parseDouble(json['threshold_value'] ?? json['threshold']),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      enabled: json['enabled'] ?? true,
      alertType: json['alert_type'] ?? json['condition_type'] ?? '',
      threshold: json['threshold'] != null ? QuoteData._parseDouble(json['threshold']) : null,
      indicatorType: json['indicator_type'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'condition_type': conditionType,
    'threshold_value': thresholdValue,
    'created_at': createdAt.millisecondsSinceEpoch,
    'enabled': enabled,
    'alert_type': alertType,
    'threshold': threshold,
    'indicator_type': indicatorType,
  };
}

class WatchlistItem {
  final String code;
  final String name;
  final DateTime addedAt;
  final bool isPinned;

  WatchlistItem({
    required this.code,
    required this.name,
    DateTime? addedAt,
    this.isPinned = false,
  }) : addedAt = addedAt ?? DateTime.now();

  factory WatchlistItem.fromJson(Map<String, dynamic> json) {
    return WatchlistItem(
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      addedAt: json['added_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['added_at'] as int)
          : (json['addedAt'] != null
              ? DateTime.fromMillisecondsSinceEpoch(json['addedAt'] as int)
              : DateTime.now()),
      isPinned: (json['is_pinned'] as int?) == 1,
    );
  }
}

/// 持仓记录（v2.33: 短线持仓管理）
class Position {
  final int? id;
  final String code;       // 不带前缀的6位代码
  final String name;
  final int quantity;       // 持仓股数
  final double avgPrice;   // 持仓均价
  final double floatPnl;   // 浮动盈亏（来自Excel）
  final double pnlPct;     // 盈亏比例（来自Excel）
  final double marketValue; // 市值（来自Excel）
  final DateTime? buyDate; // 买入日期
  final String notes;       // 备注
  final DateTime createdAt;

  Position({
    this.id,
    required this.code,
    required this.name,
    required this.quantity,
    required this.avgPrice,
    this.floatPnl = 0.0,
    this.pnlPct = 0.0,
    this.marketValue = 0.0,
    this.buyDate,
    this.notes = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 持仓市值（按均价计算的投入成本）
  double get cost => quantity * avgPrice;

  /// 计算当前盈亏（按现价）
  ({double marketValue, double pnl, double pnlPct}) computePnl(double currentPrice) {
    final marketValue = quantity * currentPrice;
    final pnl = marketValue - cost;
    final pnlPct = cost > 0 ? pnl / cost * 100 : 0.0;
    return (marketValue: marketValue, pnl: pnl, pnlPct: pnlPct);
  }

  factory Position.fromMap(Map<String, dynamic> map) {
    return Position(
      id: map['id'] as int?,
      code: map['code'] as String? ?? '',
      name: map['name'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      avgPrice: (map['avg_price'] as num?)?.toDouble() ?? 0.0,
      floatPnl: (map['float_pnl'] as num?)?.toDouble() ?? 0.0,
      pnlPct: (map['pnl_pct'] as num?)?.toDouble() ?? 0.0,
      marketValue: (map['market_value'] as num?)?.toDouble() ?? 0.0,
      buyDate: map['buy_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['buy_date'] as int)
          : null,
      notes: map['notes'] as String? ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'code': code,
      'name': name,
      'quantity': quantity,
      'avg_price': avgPrice,
      'float_pnl': floatPnl,
      'pnl_pct': pnlPct,
      'market_value': marketValue,
      'buy_date': buyDate?.millisecondsSinceEpoch,
      'notes': notes,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }
}

class MarketSentiment {
  final int upCount;
  final int downCount;
  final int flatCount;
  final int limitUpCount;
  final int limitDownCount;
  final double avgChangePct;
  final double totalVolume;
  final double totalAmount;
  final double totalAmountYi;
  final DateTime? updateTime;

  MarketSentiment({
    this.upCount = 0,
    this.downCount = 0,
    this.flatCount = 0,
    this.limitUpCount = 0,
    this.limitDownCount = 0,
    this.avgChangePct = 0,
    this.totalVolume = 0,
    this.totalAmount = 0,
    this.totalAmountYi = 0,
    this.updateTime,
  });

  factory MarketSentiment.fromJson(Map<String, dynamic> json) {
    return MarketSentiment(
      upCount: json['up_count'] ?? 0,
      downCount: json['down_count'] ?? 0,
      flatCount: json['flat_count'] ?? 0,
      limitUpCount: json['limit_up_count'] ?? 0,
      limitDownCount: json['limit_down_count'] ?? 0,
      avgChangePct: QuoteData._parseDouble(json['avg_change_pct']),
      totalVolume: QuoteData._parseDouble(json['total_volume']),
      totalAmount: QuoteData._parseDouble(json['total_amount']),
      totalAmountYi: QuoteData._parseDouble(json['total_amount_yi']),
      updateTime: json['update_time'] != null
          ? DateTime.tryParse(json['update_time'])
          : null,
    );
  }

  int get total => upCount + downCount + flatCount;

  double get upRatio => total > 0 ? upCount / total : 0;
}

class ArchiveRecord {
  final int? id;
  final String code;
  final String name;
  final double price;
  final double changePct;
  final int score;
  final String recommendation;
  final String riskLevel;
  final int buySignalCount;
  final int sellSignalCount;
  final int activeStrategyCount;
  final int confluenceScore;
  final String? tradeLevelsJson;
  final String topSignals;
  final DateTime archivedAt;

  ArchiveRecord({
    this.id,
    required this.code,
    required this.name,
    required this.price,
    required this.changePct,
    required this.score,
    required this.recommendation,
    required this.riskLevel,
    required this.buySignalCount,
    required this.sellSignalCount,
    required this.activeStrategyCount,
    required this.confluenceScore,
    this.tradeLevelsJson,
    this.topSignals = '',
    required this.archivedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'price': price,
      'change_pct': changePct,
      'score': score,
      'recommendation': recommendation,
      'risk_level': riskLevel,
      'buy_signal_count': buySignalCount,
      'sell_signal_count': sellSignalCount,
      'active_strategy_count': activeStrategyCount,
      'confluence_score': confluenceScore,
      'trade_levels_json': tradeLevelsJson,
      'top_signals': topSignals,
      'archived_at': archivedAt.millisecondsSinceEpoch,
    };
  }

  factory ArchiveRecord.fromMap(Map<String, dynamic> map) {
    return ArchiveRecord(
      id: map['id'] as int?,
      code: map['code'] as String,
      name: map['name'] as String,
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      changePct: (map['change_pct'] as num?)?.toDouble() ?? 0.0,
      score: (map['score'] as num?)?.toInt() ?? 0,
      recommendation: map['recommendation'] as String,
      riskLevel: map['risk_level'] as String,
      buySignalCount: (map['buy_signal_count'] as num?)?.toInt() ?? 0,
      sellSignalCount: (map['sell_signal_count'] as num?)?.toInt() ?? 0,
      activeStrategyCount: (map['active_strategy_count'] as num?)?.toInt() ?? 0,
      confluenceScore: (map['confluence_score'] as num?)?.toInt() ?? 0,
      tradeLevelsJson: map['trade_levels_json'] as String?,
      topSignals: map['top_signals'] as String? ?? '',
      archivedAt: DateTime.fromMillisecondsSinceEpoch((map['archived_at'] as num?)?.toInt() ?? 0),
    );
  }
}

class SectorInfo {
  final String name;
  final String code;
  final double changePct;
  final String leadStockName;
  final String leadStockCode;
  final int stockCount;

  SectorInfo({
    required this.name,
    required this.code,
    this.changePct = 0,
    this.leadStockName = '',
    this.leadStockCode = '',
    this.stockCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'code': code,
    'change_pct': changePct,
    'lead_stock_name': leadStockName,
    'lead_stock_code': leadStockCode,
    'stock_count': stockCount,
  };

  factory SectorInfo.fromJson(Map<String, dynamic> json) => SectorInfo(
    name: json['name'] ?? '',
    code: json['code'] ?? '',
    changePct: (json['change_pct'] as num?)?.toDouble() ?? 0,
    leadStockName: json['lead_stock_name'] ?? '',
    leadStockCode: json['lead_stock_code'] ?? '',
    stockCount: (json['stock_count'] as num?)?.toInt() ?? 0,
  );
}

class ExploreResult {
  final String code;
  final String name;
  final double price;
  final double changePct;
  final double pe;
  final double pb;
  final int score;
  final String recommendation;
  final String sector;
  final int confluenceScore;
  final DateTime analyzedAt;
  // Phase 2-3: 概念标签 + 收益追踪
  final String? conceptSummary;
  final double? day5Return;
  final double? day10Return;
  final double? day20Return;
  final String? marketStructure;

  ExploreResult({
    required this.code,
    required this.name,
    this.price = 0,
    this.changePct = 0,
    this.pe = 0,
    this.pb = 0,
    this.score = 0,
    this.recommendation = '',
    this.sector = '',
    this.confluenceScore = 0,
    required this.analyzedAt,
    this.conceptSummary,
    this.day5Return,
    this.day10Return,
    this.day20Return,
    this.marketStructure,
  });

  /// 涨停近似判定：主板≥9.5%, 创业板/科创板≥19%, 北交所≥29%
  bool get isLimitUpApprox {
    final isStar = code.startsWith('688');
    final isChiNext = code.startsWith('30');
    final isBse = code.startsWith('8') || code.startsWith('43');
    final threshold = isBse ? 29.0 : (isStar || isChiNext ? 19.0 : 9.5);
    return changePct >= threshold;
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'name': name,
      'price': price,
      'change_pct': changePct,
      'pe': pe,
      'pb': pb,
      'score': score,
      'recommendation': recommendation,
      'sector': sector,
      'confluence_score': confluenceScore,
      'analyzed_at': analyzedAt.millisecondsSinceEpoch,
      'concept_summary': conceptSummary,
      'day5_return': day5Return,
      'day10_return': day10Return,
      'day20_return': day20Return,
      'market_structure': marketStructure,
    };
  }

  factory ExploreResult.fromMap(Map<String, dynamic> map) {
    return ExploreResult(
      code: map['code'] as String,
      name: map['name'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      changePct: (map['change_pct'] as num?)?.toDouble() ?? 0,
      pe: (map['pe'] as num?)?.toDouble() ?? 0,
      pb: (map['pb'] as num?)?.toDouble() ?? 0,
      score: (map['score'] as num?)?.toInt() ?? 0,
      recommendation: map['recommendation'] as String? ?? '',
      sector: map['sector'] as String? ?? '',
      confluenceScore: (map['confluence_score'] as num?)?.toInt() ?? 0,
      analyzedAt: DateTime.fromMillisecondsSinceEpoch((map['analyzed_at'] as num?)?.toInt() ?? 0),
      conceptSummary: map['concept_summary'] as String?,
      day5Return: (map['day5_return'] as num?)?.toDouble(),
      day10Return: (map['day10_return'] as num?)?.toDouble(),
      day20Return: (map['day20_return'] as num?)?.toDouble(),
      marketStructure: map['market_structure'] as String?,
    );
  }
}

/// 情绪周期阶段
enum EmotionPhase { startup, climax, retreat, freezing }

/// 情绪温度计计算结果
class SentimentResult {
  final double temperature;          // 0-100
  final EmotionPhase phase;
  final double zhabanRate;           // 炸板率 [0,1]
  final double continuationRate;     // 连板晋级率 [0,1]
  final double sealSuccessRate;      // 涨停封板成功率 [0,1]
  final double moneyMakingEffect;    // 赚钱效应（%）
  final int limitUpCount;
  final int limitDownCount;
  final int continuationHeight;      // 最高连板数
  final List<String> signals;
  final DateTime timestamp;

  const SentimentResult({
    required this.temperature,
    required this.phase,
    required this.zhabanRate,
    required this.continuationRate,
    required this.sealSuccessRate,
    required this.moneyMakingEffect,
    required this.limitUpCount,
    required this.limitDownCount,
    required this.continuationHeight,
    required this.signals,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
    'temperature': temperature,
    'phase': phase.name,
    'zhaban_rate': zhabanRate,
    'continuation_rate': continuationRate,
    'seal_success_rate': sealSuccessRate,
    'money_making_effect': moneyMakingEffect,
    'limit_up_count': limitUpCount,
    'limit_down_count': limitDownCount,
    'continuation_height': continuationHeight,
    'signals': signals,
    'timestamp': timestamp.millisecondsSinceEpoch,
  };

  factory SentimentResult.fromMap(Map<String, dynamic> map) => SentimentResult(
    temperature: (map['temperature'] as num?)?.toDouble() ?? 50.0,
    phase: EmotionPhase.values.firstWhere(
      (e) => e.name == (map['phase'] as String?),
      orElse: () => EmotionPhase.freezing,
    ),
    zhabanRate: (map['zhaban_rate'] as num?)?.toDouble() ?? 0.0,
    continuationRate: (map['continuation_rate'] as num?)?.toDouble() ?? 0.0,
    sealSuccessRate: (map['seal_success_rate'] as num?)?.toDouble() ?? 0.0,
    moneyMakingEffect: (map['money_making_effect'] as num?)?.toDouble() ?? 0.0,
    limitUpCount: (map['limit_up_count'] as int?) ?? 0,
    limitDownCount: (map['limit_down_count'] as int?) ?? 0,
    continuationHeight: (map['continuation_height'] as int?) ?? 0,
    signals: (map['signals'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    timestamp: map['timestamp'] != null
        ? DateTime.fromMillisecondsSinceEpoch((map['timestamp'] as num).toInt())
        : DateTime.now(),
  );
}

/// 全球主要股指（美股/港股/亚太/欧洲）
class GlobalIndex {
  final String code;        // NDX / SPX / DJIA / HSI ...
  final String name;        // 纳斯达克综合指数
  final double price;       // 最新价
  final double changePct;   // 涨跌幅 %
  final double changePoint; // 涨跌点
  final String market;      // US / HK / JP / EU / KR
  final DateTime? tradeTime;

  const GlobalIndex({
    required this.code,
    required this.name,
    required this.price,
    required this.changePct,
    required this.changePoint,
    required this.market,
    this.tradeTime,
  });

  /// 计算一组指数的综合趋势：返回 (trendLabel, avgChangePct, upCount, downCount)
  /// trendLabel: 偏多(avg>0.5) / 偏空(avg<-0.5) / 中性
  static ({String trend, double avg, int upCount, int downCount}) calculateTrend(List<GlobalIndex> indices) {
    if (indices.isEmpty) {
      return (trend: '中性', avg: 0.0, upCount: 0, downCount: 0);
    }
    final upCount = indices.where((i) => i.changePct > 0).length;
    final downCount = indices.where((i) => i.changePct < 0).length;
    final avg = indices.map((i) => i.changePct).reduce((a, b) => a + b) / indices.length;
    String trend;
    if (avg > 0.5) {
      trend = '偏多';
    } else if (avg < -0.5) {
      trend = '偏空';
    } else {
      trend = '中性';
    }
    return (trend: trend, avg: avg, upCount: upCount, downCount: downCount);
  }
}
