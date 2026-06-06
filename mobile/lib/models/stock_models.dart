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
  final DateTime? updateTime;

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
    this.updateTime,
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
      updateTime: json['update_time'] != null ? DateTime.tryParse(json['update_time']) : null,
    );
  }

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

  SignalItem({
    required this.type,
    this.indicator = '',
    this.signal = '',
    this.description = '',
    this.desc = '',
    this.strength = 0,
    this.timestamp,
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

  AnalysisResult({
    this.quote,
    this.indicators = const {},
    this.signals = const [],
    this.score = 0,
    this.recommendation = '',
    this.riskLevel = '中等',
    this.riskFactors = const [],
    this.suggestions = const [],
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    List<SignalItem> signals = [];
    if (json['signals'] != null && json['signals'] is List) {
      signals = (json['signals'] as List)
          .map((s) => SignalItem.fromJson(s as Map<String, dynamic>))
          .toList();
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
    );
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
      createdAt: DateTime.now(),
      enabled: json['enabled'] ?? true,
      alertType: json['alert_type'] ?? json['condition_type'] ?? '',
      threshold: json['threshold'] != null ? QuoteData._parseDouble(json['threshold']) : null,
      indicatorType: json['indicator_type'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'condition_type': conditionType,
    'threshold_value': thresholdValue,
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

  WatchlistItem({
    required this.code,
    required this.name,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  factory WatchlistItem.fromJson(Map<String, dynamic> json) {
    return WatchlistItem(
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      addedAt: DateTime.now(),
    );
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
