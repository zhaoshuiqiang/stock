import '../models/stock_models.dart';
import 'backtest_engine.dart';

class LimitUpStock {
  final String code, name, sector, limitUpType;
  final double price, changePct, sealAmount, turnoverRate, volumeRatio;
  final double sealRatio;           // 封成比
  final double limitUpPrice;        // 涨停价
  final double totalValue;          // 总市值
  final double circulationValue;    // 流通市值
  final int consecutiveDays;
  final int zhabanCount;            // 炸板次数
  final bool isZhaBan;              // 是否炸板
  final DateTime? firstLimitTime;   // 首封时间（nullable）
  final DateTime? lastLimitTime;    // 最后封板时间

  LimitUpStock({
    required this.code,
    required this.name,
    this.price = 0,
    this.changePct = 0,
    this.consecutiveDays = 1,
    this.firstLimitTime,
    this.lastLimitTime,
    this.sealAmount = 0,
    this.turnoverRate = 0,
    this.volumeRatio = 1.0,
    this.sector = '',
    this.limitUpType = '',
    this.sealRatio = 0,
    this.limitUpPrice = 0,
    this.totalValue = 0,
    this.circulationValue = 0,
    this.zhabanCount = 0,
    this.isZhaBan = false,
  });

  /// 从东方财富 getTopicZTPool 接口的 pool 元素构造
  factory LimitUpStock.fromEastMoney(Map<String, dynamic> json) {
    return LimitUpStock(
      code: (json['c'] ?? '').toString().padLeft(6, '0'),
      name: (json['n'] ?? '').toString(),
      consecutiveDays: (json['lbc'] ?? 1) as int,
      firstLimitTime: _parseEastMoneyTime(json['fbt']),
      lastLimitTime: _parseEastMoneyTime(json['lbt']),
      sealAmount: ((json['fund'] ?? 0) as num).toDouble() / 10000,  // 元→万元
      turnoverRate: ((json['hs'] ?? 0) as num).toDouble(),
      zhabanCount: (json['zbc'] ?? 0) as int,
      isZhaBan: ((json['zbc'] ?? 0) as int) > 0,
      sector: (json['hybk'] ?? '') as String,
      totalValue: ((json['tshare'] ?? 0) as num).toDouble(),
      circulationValue: ((json['ltsz'] ?? 0) as num).toDouble(),
    );
  }

  /// 解析东财时间格式：整数 92500 → DateTime(09:25:00)
  static DateTime? _parseEastMoneyTime(dynamic val) {
    if (val == null || val == '-' || val == '') return null;
    if (val is int) {
      final s = val.toString().padLeft(6, '0');
      if (s.length != 6) return null;
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day,
          int.parse(s.substring(0, 2)),
          int.parse(s.substring(2, 4)),
          int.parse(s.substring(4, 6)));
    }
    if (val is String && val.contains(':')) {
      final parts = val.split(':');
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day,
          int.parse(parts[0]), int.parse(parts[1]),
          parts.length > 2 ? int.parse(parts[2]) : 0);
    }
    return null;
  }
}

class LimitUpAnalysis {
  final String code, name, quality, timeGrade, boardType, position;
  final int consecutiveDays;
  final double qualityScore, sealRate, premiumProb;
  final List<String> signals;
  LimitUpAnalysis({required this.code, required this.name, this.consecutiveDays=1, this.quality='一般', this.qualityScore=5.0, this.timeGrade='未知', this.sealRate=0, this.boardType='', this.position='', this.premiumProb=0.5, this.signals=const[]});
  Map<String, dynamic> toMap() => {'code':code,'name':name,'consecutive_days':consecutiveDays,'quality':quality,'quality_score':qualityScore,'time_grade':timeGrade,'seal_rate':sealRate,'board_type':boardType,'position':position,'premium_prob':premiumProb,'signals':signals};
}

class LimitUpAnalyzer {
  static const _probByDays = [0.75, 0.65, 0.55, 0.45, 0.40];
  static LimitUpAnalysis analyzeSingle(LimitUpStock stock) {
    double score = 5.0; final signals = <String>[];
    if (stock.consecutiveDays >= 5) { score += 3.0; signals.add('${stock.consecutiveDays}连板，市场龙头'); }
    else if (stock.consecutiveDays >= 3) { score += 2.0; signals.add('${stock.consecutiveDays}连板，板块核心'); }
    else if (stock.consecutiveDays >= 2) { score += 1.0; signals.add('2连板，确认强势'); }

    final tm = (stock.firstLimitTime?.hour ?? 0) * 60 + (stock.firstLimitTime?.minute ?? 0);
    String timeGrade;
    if (tm < 9*60+25) { timeGrade='竞价涨停'; score+=2.0; signals.add('集合竞价即涨停'); }
    else if (tm < 10*60) { timeGrade='早盘秒板'; score+=1.5; signals.add('早盘半小时内封板'); }
    else if (tm < 11*60+30) { timeGrade='上午封板'; score+=0.8; }
    else if (tm < 14*60) { timeGrade='下午封板'; score-=0.3; }
    else if (tm < 14*60+30) { timeGrade='尾盘封板'; score-=0.8; signals.add('尾盘涨停，次日溢价不确定'); }
    else { timeGrade='尾盘偷鸡'; score-=1.5; signals.add('尾盘急拉涨停，次日低开概率高'); }

    final estimatedTurnover = stock.price * stock.turnoverRate * 100;
    final sealRate = estimatedTurnover > 0 ? stock.sealAmount / estimatedTurnover : 0.0;
    if (sealRate > 3.0) { score+=1.5; signals.add('封单充足'); }
    else if (sealRate > 1.0) score+=0.8;
    else if (sealRate > 0.3) score+=0.2;
    else if (sealRate > 0 && sealRate < 0.1) { score-=1.0; signals.add('封单不足，烂板风险高'); }

    String boardType;
    if (stock.limitUpType.contains('一字板')) { boardType='一字板'; score+=1.5; }
    else if (stock.limitUpType.contains('T字')) { boardType='T字板'; score+=0.8; }
    else if (stock.turnoverRate > 15 && stock.limitUpType.contains('回封')) { boardType='烂板回封'; score-=0.5; }
    else { boardType='换手板'; if (stock.consecutiveDays >= 2 && stock.turnoverRate < 5) { score+=0.5; signals.add('低换手锁仓'); } }

    double prob = 0.5;
    if (stock.consecutiveDays == 1) prob = tm < 10*60 ? 0.75 : tm < 13*60 ? 0.65 : 0.45;
    else if (stock.consecutiveDays == 2) prob = tm < 10*60 ? 0.80 : 0.60;
    else prob = _probByDays[stock.consecutiveDays.clamp(3,7)-3];
    if (stock.limitUpType.contains('一字板')) prob += 0.1;

    String quality;
    if (score >= 8.0) quality='优质'; else if (score >= 6.5) quality='良好'; else if (score >= 4.5) quality='一般'; else quality='弱势';
    score = score.clamp(0.0, 10.0);
    return LimitUpAnalysis(code:stock.code, name:stock.name, consecutiveDays:stock.consecutiveDays, quality:quality, qualityScore:score, timeGrade:timeGrade, sealRate:sealRate, boardType:boardType, premiumProb:prob, signals:signals);
  }

  static Map<String, dynamic> analyzeBatch(List<LimitUpStock> stocks) {
    if (stocks.isEmpty) return {'analyses':[], 'total':0, 'leaders':[]};
    final analyses = stocks.map((s) => analyzeSingle(s)).toList();
    final leaders = analyses.where((a) => a.qualityScore >= 8.0).toList();
    final dist = <String,int>{};
    for (final s in stocks) { final k = s.consecutiveDays == 1 ? '首板' : '${s.consecutiveDays}连板'; dist[k] = (dist[k]??0)+1; }
    final avg = analyses.isEmpty ? 0 : double.parse((analyses.map((a)=>a.qualityScore).reduce((a,b)=>a+b)/analyses.length).toStringAsFixed(1));
    return {'analyses':analyses.map((a)=>a.toMap()).toList(), 'total':stocks.length, 'leaders':leaders.map((a)=>a.toMap()).toList(), 'distribution':dist, 'avg_quality':avg};
  }

  /// 从日K线推断打板信息（简化版，无首封时间和封单数据）。
  ///
  /// 用于信号引擎 [generateAnalysis] 流程，识别涨停标的并评估打板质量。
  /// 与 [analyzeSingle] 的区别：跳过首封时间和封单充足率维度（日K线无法获取），
  /// 评分维度调整为连板高度 + 板型 + 量价配合。非涨停日返回 null。
  static LimitUpAnalysis? analyzeFromDaily({
    required String code,
    required String name,
    required List<HistoryKline> klines,
    QuoteData? quote,
  }) {
    if (klines.length < 2) return null;

    final limitPct = BacktestConfig.inferLimitPct(code);
    final last = klines.last;
    final prev = klines[klines.length - 2];

    // 判断最近一日是否涨停（收盘价或最高价触及涨停价）
    if (!KlineValidator.isLimitUp(last, prev, limitPct)) return null;

    // 统计连板天数（往前遍历）
    int consecutiveDays = 1;
    for (int i = klines.length - 2; i >= 1; i--) {
      final k = klines[i];
      final p = klines[i - 1];
      if (KlineValidator.isLimitUp(k, p, limitPct)) {
        consecutiveDays++;
      } else {
        break;
      }
    }

    // 推断板型
    String boardType;
    if (KlineValidator.isYiZiBan(last, prev, limitPct)) {
      boardType = '一字板';
    } else if ((last.open - KlineValidator.limitUpPrice(prev.close, limitPct)).abs() < 0.001) {
      boardType = 'T字板';
    } else {
      boardType = '换手板';
    }

    // 量价信息
    final turnoverRate = quote?.turnover ?? 0;
    final volumeRatio = last.volMa5 > 0 ? last.volume / last.volMa5 : 1.0;

    // 简化版评分（基础5.0，只用日K线可推断的维度）
    double score = 5.0;
    final signals = <String>[];

    // 连板高度
    if (consecutiveDays >= 5) {
      score += 3.0;
      signals.add('$consecutiveDays连板，市场龙头');
    } else if (consecutiveDays >= 3) {
      score += 2.0;
      signals.add('$consecutiveDays连板，板块核心');
    } else if (consecutiveDays >= 2) {
      score += 1.0;
      signals.add('2连板，确认强势');
    } else {
      signals.add('首板涨停');
    }

    // 板型
    if (boardType == '一字板') {
      score += 1.5;
      signals.add('一字板，封板极强');
    } else if (boardType == 'T字板') {
      score += 0.8;
      signals.add('T字板，盘中开板回封');
    } else {
      // 换手板：低换手锁仓加分
      if (consecutiveDays >= 2 && turnoverRate > 0 && turnoverRate < 5) {
        score += 0.5;
        signals.add('低换手锁仓');
      }
    }

    // 量价配合
    if (volumeRatio > 2.0) {
      score += 0.8;
      signals.add('量比${volumeRatio.toStringAsFixed(1)}，放量封板');
    } else if (volumeRatio > 1.5) {
      score += 0.4;
    } else if (volumeRatio < 0.8 && consecutiveDays >= 2) {
      score += 0.3;
      signals.add('缩量封板，筹码锁定');
    }

    // 换手率合理性
    if (turnoverRate > 0) {
      if (turnoverRate >= 5 && turnoverRate <= 15) {
        score += 0.3;
      } else if (turnoverRate > 25) {
        score -= 0.3;
        signals.add('换手率${turnoverRate.toStringAsFixed(1)}%过高，分歧大');
      }
    }

    // 次日溢价概率（简化版：基于连板天数和板型）
    double prob = 0.5;
    if (consecutiveDays == 1) {
      prob = boardType == '一字板' ? 0.75 : 0.60;
    } else if (consecutiveDays == 2) {
      prob = 0.70;
    } else if (consecutiveDays >= 3) {
      prob = 0.55 + (consecutiveDays - 3) * 0.05;
    }
    if (boardType == '一字板') prob += 0.1;
    if (prob > 0.95) prob = 0.95;

    String quality;
    if (score >= 8.0) {
      quality = '优质';
    } else if (score >= 6.5) {
      quality = '良好';
    } else if (score >= 4.5) {
      quality = '一般';
    } else {
      quality = '弱势';
    }
    score = score.clamp(0.0, 10.0);

    return LimitUpAnalysis(
      code: code,
      name: name,
      consecutiveDays: consecutiveDays,
      quality: quality,
      qualityScore: score,
      timeGrade: '日K推断',
      sealRate: 0,
      boardType: boardType,
      premiumProb: prob,
      signals: signals,
    );
  }
}
