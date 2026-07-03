import 'package:flutter/foundation.dart';
import '../models/stock_models.dart';
import 'ai_layer.dart';

/// 新闻情绪分析器 - 参考 TradingAgents Sentiment/News Analyst
/// 基于关键词规则分析新闻标题情绪，支持AI替换
class NewsSentimentAnalyzer {
  static AILayer? _aiLayer;

  static void setAILayer(AILayer layer) {
    _aiLayer = layer;
  }

  static void clearAILayer() {
    _aiLayer = null;
  }

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
    // v2.30: 新增预期偏差关键词
    '低于预期': 2, '不及预期': 2, '弱于预期': 2,
  };

  // 否定词列表：出现这些词且紧邻关键词时，该关键词应反转
  static const List<String> _negationWords = [
    '未及', '不及', '低于', '差于', '没有', '未能', '不再', '不会',
    '并非', '并非是', '不是', '无望', '难以',
  ];

  // v2.30: 上下文修饰词 — 关键词后面的语境词可反转/弱化/强化情感
  static const Map<String, String> _contextModifiers = {
    '出尽': '反转',
    '完毕': '反转',
    '完成': '反转',
    '结束': '反转',
    '低于预期': '弱化',
    '不及预期': '弱化',
    '弱于预期': '弱化',
    '超预期': '强化',
  };

  /// 分析新闻列表的情绪（同步版本）
  /// newsList: 新闻列表，每条需包含 'title' 字段
  /// v2.54: 使用关键词规则分析，AI分析通过 analyzeAsync 异步执行
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

  /// 分析单条新闻标题 (v2.30: 增加上下文语境检测)
  static _TitleAnalysisResult _analyzeTitle(String title) {
    double positiveScore = 0;
    double negativeScore = 0;
    String matchedKeyword = '';

    for (final entry in _positiveKeywords.entries) {
      final idx = title.indexOf(entry.key);
      if (idx >= 0) {
        final isNegated = _isNegatedBefore(title, idx);
        final contextMod = _getContextModifier(title, idx, entry.key.length);
        if (isNegated) {
          negativeScore += entry.value.toDouble();
          if (matchedKeyword.isEmpty || entry.value > _currentKeywordWeight(matchedKeyword, _positiveKeywords)) {
            matchedKeyword = '未${entry.key}';
          }
        } else if (contextMod == '反转') {
          negativeScore += entry.value.toDouble() * 0.5;
          if (matchedKeyword.isEmpty) matchedKeyword = '${entry.key}(语境反转)';
        } else if (contextMod == '弱化') {
          positiveScore += entry.value * 0.5;
          if (matchedKeyword.isEmpty) matchedKeyword = '${entry.key}(弱化)';
        } else if (contextMod == '强化') {
          positiveScore += entry.value * 1.5;
          if (matchedKeyword.isEmpty) matchedKeyword = '${entry.key}(超预期)';
        } else {
          positiveScore += entry.value.toDouble();
          if (matchedKeyword.isEmpty || entry.value > _currentKeywordWeight(matchedKeyword, _positiveKeywords)) {
            matchedKeyword = entry.key;
          }
        }
      }
    }

    for (final entry in _negativeKeywords.entries) {
      final idx = title.indexOf(entry.key);
      if (idx >= 0) {
        final isNegated = _isNegatedBefore(title, idx);
        final contextMod = _getContextModifier(title, idx, entry.key.length);
        if (isNegated) {
          positiveScore += entry.value.toDouble();
          if (matchedKeyword.isEmpty || entry.value > _currentKeywordWeight(matchedKeyword, _negativeKeywords)) {
            matchedKeyword = '未${entry.key}';
          }
        } else if (contextMod == '反转') {
          positiveScore += entry.value.toDouble() * 0.5;
          if (matchedKeyword.isEmpty) matchedKeyword = '${entry.key}(语境反转)';
        } else if (contextMod == '弱化') {
          negativeScore += entry.value * 0.5;
          if (matchedKeyword.isEmpty) matchedKeyword = '${entry.key}(弱化)';
        } else if (contextMod == '强化') {
          negativeScore += entry.value * 1.5;
          if (matchedKeyword.isEmpty) matchedKeyword = '${entry.key}(强化)';
        } else {
          negativeScore += entry.value.toDouble();
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
  static bool _isNegatedBefore(String title, int keywordIndex) {
    final prefixStart = keywordIndex > 4 ? keywordIndex - 4 : 0;
    final prefix = title.substring(prefixStart, keywordIndex);
    for (final negWord in _negationWords) {
      if (prefix.endsWith(negWord)) {
        return true;
      }
    }
    return false;
  }

  /// v2.30: 检查关键词后面的语境修饰词
  /// 返回 null 表示无修饰，'反转'/'弱化'/'强化' 表示修饰类型
  static String? _getContextModifier(String title, int keywordIndex, int keywordLen) {
    final afterStart = keywordIndex + keywordLen;
    final afterEnd = (afterStart + 6).clamp(0, title.length);
    if (afterStart >= title.length) return null;
    final afterText = title.substring(afterStart, afterEnd);
    for (final entry in _contextModifiers.entries) {
      if (afterText.startsWith(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  /// 分析新闻列表的情绪（异步版本 - AI增强）
  /// v2.54: 当AILayer可用时使用AI分析，否则回退到规则模式
  static Future<NewsSentiment> analyzeAsync(List<dynamic> newsList) async {
    if (newsList.isEmpty) {
      return NewsSentiment(
        score: 0,
        positiveCount: 0,
        negativeCount: 0,
        neutralCount: 0,
        keyFactors: [],
      );
    }

    if (_aiLayer != null && _aiLayer!.isAvailable) {
      final titles = newsList.map((news) {
        if (news is Map<String, dynamic>) {
          return (news['title'] ?? news['title_ch'] ?? '').toString();
        }
        return news.toString();
      }).where((t) => t.isNotEmpty).toList();

      try {
        final aiResult = await _aiLayer!.analyzeSentiment(titles);
        return NewsSentiment(
          score: aiResult.score,
          positiveCount: aiResult.positiveCount,
          negativeCount: aiResult.negativeCount,
          neutralCount: aiResult.neutralCount,
          keyFactors: aiResult.keyFactors,
        );
      } catch (e) {
        debugPrint('[NewsSentimentAnalyzer] AI分析失败，回退到规则模式: $e');
      }
    }

    return analyze(newsList);
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
