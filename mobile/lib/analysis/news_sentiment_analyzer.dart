import '../models/stock_models.dart';

/// 新闻情绪分析器 - 参考 TradingAgents Sentiment/News Analyst
/// 基于关键词规则分析新闻标题情绪，无需LLM
class NewsSentimentAnalyzer {
  // 利好关键词及权重
  static const Map<String, int> _positiveKeywords = {
    '业绩增长': 3, '净利增长': 3, '营收增长': 2, '利润增长': 3,
    '中标': 2, '签约': 2, '订单': 2, '合同': 2,
    '回购': 3, '增持': 3, '分红': 2, '派息': 2,
    '突破': 2, '创新高': 3, '涨停': 2, '大涨': 2,
    '利好': 3, '利好消息': 3, '政策利好': 3,
    '获批': 2, '获批文': 2, '通过审核': 2,
    '投产': 2, '量产': 2, '扩产': 2,
    '并购': 2, '重组': 2, '注入': 2,
    '业绩预增': 3, '扭亏': 3, '盈利': 2,
    '上涨': 1, '反弹': 1, '回升': 1,
    '机构买入': 3, '北向资金': 2, '外资增持': 2,
  };

  // 利空关键词及权重
  static const Map<String, int> _negativeKeywords = {
    '亏损': 3, '净利下降': 3, '营收下降': 2, '利润下滑': 3,
    '减持': 3, '清仓': 3, '套现': 2,
    '违规': 3, '处罚': 3, '警示': 2, '监管': 2,
    '下跌': 1, '破位': 2, '暴跌': 3, '大跌': 2,
    '风险': 1, '退市': 3, 'ST': 3, '*ST': 3,
    '质押': 2, '强平': 3, '爆仓': 3,
    '诉讼': 2, '仲裁': 2, '纠纷': 1,
    '爆雷': 3, '违约': 3, '逾期': 2,
    '业绩预降': 3, '业绩亏损': 3, '商誉减值': 2,
    '机构卖出': 2, '外资减持': 2,
    '停牌': 1, '被查': 3, '立案': 3,
  };

  // 否定词列表：出现这些词且紧邻关键词时，该关键词应反转
  // 仅使用多字否定词，避免单字词误匹配（如"不断"中的"不"）
  static const List<String> _negationWords = [
    '未及', '不及', '低于', '差于', '没有', '未能', '不再', '不会',
    '并非', '并非是', '不是', '无望', '难以',
  ];

  /// 分析新闻列表的情绪
  /// newsList: 新闻列表，每条需包含 'title' 字段
  static NewsSentiment analyze(List<dynamic> newsList) {
    if (newsList.isEmpty) {
      return NewsSentiment(
        score: 0,
        positiveCount: 0,
        negativeCount: 0,
        neutralCount: 0,
        keyFactors: [],
      );
    }

    int positiveCount = 0;
    int negativeCount = 0;
    int neutralCount = 0;
    double totalScore = 0;
    final keyFactors = <String>[];
    int effectiveCount = 0;

    for (final news in newsList) {
      final title = (news is Map<String, dynamic>)
          ? (news['title'] ?? news['title_ch'] ?? '').toString()
          : news.toString();

      if (title.isEmpty) continue;
      effectiveCount++;

      final result = _analyzeTitle(title);
      totalScore += result.score;

      if (result.score > 0) {
        positiveCount++;
        if (result.score >= 2 && keyFactors.length < 5) {
          keyFactors.add('[利好] ${result.matchedKeyword}: $title');
        }
      } else if (result.score < 0) {
        negativeCount++;
        if (result.score <= -2 && keyFactors.length < 5) {
          keyFactors.add('[利空] ${result.matchedKeyword}: $title');
        }
      } else {
        neutralCount++;
      }
    }

    // 归一化到 [-10, +10]，使用有效新闻数而非总新闻数
    final normalizedScore = effectiveCount > 0
        ? (totalScore / effectiveCount * 2).clamp(-10.0, 10.0)
        : 0.0;

    return NewsSentiment(
      score: normalizedScore,
      positiveCount: positiveCount,
      negativeCount: negativeCount,
      neutralCount: neutralCount,
      keyFactors: keyFactors,
    );
  }

  /// 分析单条新闻标题
  static _TitleAnalysisResult _analyzeTitle(String title) {
    double positiveScore = 0;
    double negativeScore = 0;
    String matchedKeyword = '';

    for (final entry in _positiveKeywords.entries) {
      final idx = title.indexOf(entry.key);
      if (idx >= 0) {
        // 检查关键词前面2个字符内是否有否定词紧邻
        final isNegated = _isNegatedBefore(title, idx);
        if (isNegated) {
          negativeScore += entry.value;
          if (matchedKeyword.isEmpty || entry.value > _currentKeywordWeight(matchedKeyword, _negativeKeywords)) {
            matchedKeyword = '未${entry.key}';
          }
        } else {
          positiveScore += entry.value;
          if (matchedKeyword.isEmpty || entry.value > _currentKeywordWeight(matchedKeyword, _positiveKeywords)) {
            matchedKeyword = entry.key;
          }
        }
      }
    }

    for (final entry in _negativeKeywords.entries) {
      final idx = title.indexOf(entry.key);
      if (idx >= 0) {
        // 检查关键词前面2个字符内是否有否定词紧邻
        final isNegated = _isNegatedBefore(title, idx);
        if (isNegated) {
          positiveScore += entry.value;
          if (matchedKeyword.isEmpty || entry.value > _currentKeywordWeight(matchedKeyword, _positiveKeywords)) {
            matchedKeyword = '未${entry.key}';
          }
        } else {
          negativeScore += entry.value;
          if (matchedKeyword.isEmpty || entry.value > _currentKeywordWeight(matchedKeyword, _negativeKeywords)) {
            matchedKeyword = entry.key;
          }
        }
      }
    }

    final netScore = positiveScore - negativeScore;

    return _TitleAnalysisResult(
      score: netScore.clamp(-5.0, 5.0),
      matchedKeyword: matchedKeyword,
    );
  }

  /// 检查关键词位置前面是否有否定词紧邻（前4个字符范围内）
  /// 避免全局匹配导致误反转，如"不断突破新高"中的"不"不应反转"突破"
  static bool _isNegatedBefore(String title, int keywordIndex) {
    // 取关键词前面的文本（最多取4个字符用于匹配多字否定词）
    final prefixStart = keywordIndex > 4 ? keywordIndex - 4 : 0;
    final prefix = title.substring(prefixStart, keywordIndex);
    for (final negWord in _negationWords) {
      if (prefix.endsWith(negWord)) {
        return true;
      }
    }
    return false;
  }
}

class _TitleAnalysisResult {
  final double score;
  final String matchedKeyword;

  _TitleAnalysisResult({required this.score, required this.matchedKeyword});
}

/// 获取关键词在字典中的权重，未找到返回0
int _currentKeywordWeight(String keyword, Map<String, int> dict) {
  return dict[keyword] ?? 0;
}
