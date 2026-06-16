class LimitUpStock {
  final String code, name, sector, limitUpType;
  final double price, changePct, sealAmount, turnoverRate, volumeRatio;
  final int consecutiveDays;
  final DateTime firstLimitUpTime;
  LimitUpStock({required this.code, required this.name, this.price=0, this.changePct=0, this.consecutiveDays=1, DateTime? firstLimitUpTime, this.sealAmount=0, this.turnoverRate=0, this.volumeRatio=1.0, this.sector='', this.limitUpType=''}) : firstLimitUpTime = firstLimitUpTime ?? DateTime.now();
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

    final tm = stock.firstLimitUpTime.hour * 60 + stock.firstLimitUpTime.minute;
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
}
