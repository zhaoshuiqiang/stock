/// 推荐解释生成器
///
/// 从评分维度、信号、资金流向等数据生成简洁的自然语言推荐理由。
/// 输出格式示例：
///   "技术面强势(3买0卖) + 主力资金净流入 + 板块共振，评分7/10"
///   "MACD金叉 + 均线多头 + 量能放大，但资金略流出，建议逢低关注"
class RecommendationExplainer {
  RecommendationExplainer._();

  /// 从评分明细和信号数据生成推荐解释
  ///
  /// [dimensionScores] - 7维评分 {'技术面': 7.5, '资金面': 6.0, ...}
  /// [topSignals] - 顶部信号列表 ['MACD金叉', '均线多头排列', ...]
  /// [buySignalCount] / [sellSignalCount] - 买卖信号数量
  /// [confluenceScore] - 共振分数 (0-10)
  /// [mainNetFlow] - 主力净流入金额（万元），正=流入，负=流出
  /// [score] - 综合评分 (0-10)
  /// [recommendation] - 推荐等级文本
  static String explain({
    Map<String, double>? dimensionScores,
    List<String> topSignals = const [],
    int buySignalCount = 0,
    int sellSignalCount = 0,
    int confluenceScore = 0,
    double mainNetFlow = 0,
    int score = 0,
    String recommendation = '',
  }) {
    final parts = <String>[];

    // 1. 信号维度：提取最强信号
    final signalPart = _formatSignalPart(
      topSignals: topSignals,
      buyCount: buySignalCount,
      sellCount: sellSignalCount,
    );
    if (signalPart.isNotEmpty) parts.add(signalPart);

    // 2. 资金维度
    final capitalPart = _formatCapitalPart(mainNetFlow, dimensionScores);
    if (capitalPart.isNotEmpty) parts.add(capitalPart);

    // 3. 共振维度
    final confluencePart =
        _formatConfluencePart(confluenceScore, dimensionScores);
    if (confluencePart.isNotEmpty) parts.add(confluencePart);

    // 4. 风险提示（卖出信号多或评分低时）
    if (sellSignalCount >= 3 || (score > 0 && score < 5)) {
      final risks = <String>[];
      if (sellSignalCount >= 3) risks.add('卖信号偏多($sellSignalCount)');
      if (score > 0 && score < 5) risks.add('评分偏低');
      if (risks.isNotEmpty) {
        parts.add('注意：${risks.join('、')}');
      }
    }

    if (parts.isEmpty) {
      // 兜底：用评分和推荐等级
      if (score > 0) {
        if (recommendation.trim().isEmpty) return '综合评分 $score/10';
        return '综合评分 $score/10，$recommendation';
      }
      return '暂无明显驱动因素';
    }

    final explanation = parts.join(' + ');
    // 追加评分摘要
    if (score > 0) {
      return '$explanation（评分$score/10）';
    }
    return explanation;
  }

  /// 格式化信号部分
  static String _formatSignalPart({
    required List<String> topSignals,
    required int buyCount,
    required int sellCount,
  }) {
    final buf = StringBuffer();

    // 取前2个信号作为亮点
    if (topSignals.isNotEmpty) {
      final highlights = topSignals.take(2).toList();
      buf.write(highlights.join('、'));
    }

    // 信号统计
    if (buyCount > 0 || sellCount > 0) {
      if (buf.isNotEmpty) buf.write(' ');
      buf.write('($buyCount买$sellCount卖)');
    }

    return buf.toString();
  }

  /// 格式化资金部分
  static String _formatCapitalPart(
      double mainNetFlow, Map<String, double>? dimScores) {
    // 优先用维度评分
    if (dimScores != null && dimScores.containsKey('资金面')) {
      final score = dimScores['资金面']!;
      if (score >= 7) return '主力资金强势流入';
      if (score >= 5.5) return '资金温和流入';
      if (score >= 4) return '资金略流出';
      if (score > 0) return '资金净流出';
    }

    // 兜底：用净流入金额
    if (mainNetFlow.abs() < 1) return ''; // 数据不足
    if (mainNetFlow > 5000) return '主力资金大幅流入';
    if (mainNetFlow > 500) return '主力资金流入';
    if (mainNetFlow > 0) return '资金小幅流入';
    if (mainNetFlow > -500) return '资金小幅流出';
    if (mainNetFlow > -5000) return '主力资金流出';
    return '主力资金大幅流出';
  }

  /// 格式化共振部分
  static String _formatConfluencePart(
      int confluenceScore, Map<String, double>? dimScores) {
    // 优先用维度评分
    if (dimScores != null && dimScores.containsKey('共振')) {
      final score = dimScores['共振']!;
      if (score >= 7) return '多周期共振';
      if (score >= 5.5) return '周期信号一致';
      if (score > 0) return '共振偏弱';
    }

    // 兜底：用共振分数
    if (confluenceScore == 0) return '';
    if (confluenceScore >= 7) return '多周期共振';
    if (confluenceScore >= 5) return '周期信号一致';
    return '';
  }

  /// 生成简短版解释（用于卡片副标题，限制在30字以内）
  static String explainShort({
    Map<String, double>? dimensionScores,
    List<String> topSignals = const [],
    int buySignalCount = 0,
    int sellSignalCount = 0,
    int confluenceScore = 0,
    double mainNetFlow = 0,
    int score = 0,
    String recommendation = '',
  }) {
    final full = explain(
      dimensionScores: dimensionScores,
      topSignals: topSignals,
      buySignalCount: buySignalCount,
      sellSignalCount: sellSignalCount,
      confluenceScore: confluenceScore,
      mainNetFlow: mainNetFlow,
      score: score,
      recommendation: recommendation,
    );
    // 截断到30字
    if (full.length <= 30) return full;
    return '${full.substring(0, 27)}...';
  }

  /// 按维度强度排序，返回最强的N个维度名称
  static List<String> topDimensions(Map<String, double>? dimScores,
      {int count = 2}) {
    if (dimScores == null || dimScores.isEmpty) return [];
    final entries = dimScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(count).map((e) => e.key).toList();
  }

  /// 生成维度评分文字描述（用于详情页）
  static String describeDimension(String name, double score) {
    final level = score >= 8
        ? '强势'
        : score >= 6.5
            ? '偏强'
            : score >= 5
                ? '中性'
                : score >= 3.5
                    ? '偏弱'
                    : '弱势';
    return '$name$level(${score.toStringAsFixed(1)})';
  }
}
