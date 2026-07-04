import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/stock_models.dart';

abstract class AISentimentResult {
  double get score;
  int get positiveCount;
  int get negativeCount;
  int get neutralCount;
  List<String> get keyFactors;

  factory AISentimentResult.empty() = _EmptyAISentimentResult;
  factory AISentimentResult.fromNewsSentiment(NewsSentiment news) = _AISentimentResultFromNews;
}

class _EmptyAISentimentResult implements AISentimentResult {
  @override
  double get score => 0;
  @override
  int get positiveCount => 0;
  @override
  int get negativeCount => 0;
  @override
  int get neutralCount => 0;
  @override
  List<String> get keyFactors => [];
}

class _AISentimentResultFromNews implements AISentimentResult {
  final NewsSentiment _news;

  _AISentimentResultFromNews(this._news);

  @override
  double get score => _news.score;
  @override
  int get positiveCount => _news.positiveCount;
  @override
  int get negativeCount => _news.negativeCount;
  @override
  int get neutralCount => _news.neutralCount;
  @override
  List<String> get keyFactors => _news.keyFactors;
}

class DebateResult {
  final String? bullCase;
  final String? bearCase;
  final DebateSynthesis synthesis;
  final double? adjustedConfidence;
  final String? error;

  DebateResult({
    this.bullCase,
    this.bearCase,
    required this.synthesis,
    this.adjustedConfidence,
    this.error,
  });

  factory DebateResult.empty() {
    return DebateResult(
      synthesis: DebateSynthesis(
        conclusion: '',
        confidenceLevel: '',
        reasons: [],
        riskFactors: [],
      ),
    );
  }

  factory DebateResult.withError(String error) {
    return DebateResult(
      synthesis: DebateSynthesis(
        conclusion: '',
        confidenceLevel: '',
        reasons: [],
        riskFactors: [],
      ),
      error: error,
    );
  }
}

class DebateSynthesis {
  final String conclusion;
  final String confidenceLevel;
  final List<String> reasons;
  final List<String> riskFactors;

  DebateSynthesis({
    required this.conclusion,
    required this.confidenceLevel,
    required this.reasons,
    required this.riskFactors,
  });
}

/// AI分析模板枚举
enum AnalysisTemplate {
  debate('多空辩论', '多空双方辩论，给出综合结论'),
  shortTerm('短线分析', 'K线形态、量价关系、买卖点'),
  fundamental('基本面', '估值、行业地位、财务健康'),
  risk('风险评估', '下跌风险、政策风险、仓位建议');

  final String label;
  final String description;
  const AnalysisTemplate(this.label, this.description);
}

/// 自定义问答结果
class AIChatResult {
  final String question;
  final String answer;
  final String? error;

  AIChatResult({
    required this.question,
    required this.answer,
    this.error,
  });

  factory AIChatResult.withError(String question, String error) {
    return AIChatResult(question: question, answer: '', error: error);
  }
}

abstract class AILayer {
  Future<AISentimentResult> analyzeSentiment(List<String> newsTitles);

  Future<DebateResult> runDebate({
    required String stockCode,
    required String stockName,
    required Map<String, dynamic> technicalData,
    required List<String> newsTitles,
    required List<Map<String, dynamic>> historicalReflections,
    void Function(String status, int progress)? onProgress,
  });

  Future<String> generateReflection({
    required String stockCode,
    required String stockName,
    required double signalPrice,
    required DateTime signalDate,
    required double realizedReturn,
    required double alphaVsMarket,
    required String originalRecommendation,
  });

  /// 按预设模板分析
  Future<AIChatResult> analyzeByTemplate({
    required AnalysisTemplate template,
    required String stockCode,
    required String stockName,
    required Map<String, dynamic> technicalData,
    required List<String> newsTitles,
  });

  /// 自定义提问
  Future<AIChatResult> askCustomQuestion({
    required String question,
    required String stockCode,
    required String stockName,
    required Map<String, dynamic> technicalData,
    required List<String> newsTitles,
  });

  bool get isAvailable;

  factory AILayer.nullLayer() = NullAILayer;
}

class NullAILayer implements AILayer {
  @override
  Future<AISentimentResult> analyzeSentiment(List<String> newsTitles) async {
    return AISentimentResult.empty();
  }

  @override
  Future<DebateResult> runDebate({
    required String stockCode,
    required String stockName,
    required Map<String, dynamic> technicalData,
    required List<String> newsTitles,
    required List<Map<String, dynamic>> historicalReflections,
    void Function(String status, int progress)? onProgress,
  }) async {
    return DebateResult.empty();
  }

  @override
  Future<String> generateReflection({
    required String stockCode,
    required String stockName,
    required double signalPrice,
    required DateTime signalDate,
    required double realizedReturn,
    required double alphaVsMarket,
    required String originalRecommendation,
  }) async {
    return '';
  }

  @override
  Future<AIChatResult> analyzeByTemplate({
    required AnalysisTemplate template,
    required String stockCode,
    required String stockName,
    required Map<String, dynamic> technicalData,
    required List<String> newsTitles,
  }) async {
    return AIChatResult.withError(template.label, 'AI层未启用');
  }

  @override
  Future<AIChatResult> askCustomQuestion({
    required String question,
    required String stockCode,
    required String stockName,
    required Map<String, dynamic> technicalData,
    required List<String> newsTitles,
  }) async {
    return AIChatResult.withError(question, 'AI层未启用');
  }

  @override
  bool get isAvailable => false;
}

class AILayerProvider {
  static AILayer? _instance;

  static AILayer get instance => _instance ?? NullAILayer();

  static void set(AILayer layer) {
    reset();
    _instance = layer;
  }

  static void reset() {
    if (_instance is GLM47FlashLayer) {
      (_instance as GLM47FlashLayer).close();
    }
    _instance = null;
  }
}

class GLM47FlashLayer implements AILayer {
  final String _apiKey;
  final String _endpoint;
  final String _model;
  final http.Client _client;
  DateTime? _lastRequestTime;
  int _retryDelaySeconds = 0;

  GLM47FlashLayer({
    required String apiKey,
    String endpoint = 'https://open.bigmodel.cn/api/paas/v4/chat/completions',
    String model = 'glm-4.7-flash',
  })  : _apiKey = apiKey,
        _endpoint = endpoint,
        _model = model,
        _client = http.Client();

  @override
  Future<AISentimentResult> analyzeSentiment(List<String> newsTitles) async {
    if (newsTitles.isEmpty) {
      return AISentimentResult.empty();
    }

    final prompt = '''
你是一个专业的股票新闻情绪分析师。请分析以下新闻标题对股票的影响，并返回结构化的JSON结果：

新闻标题列表：
${newsTitles.join('\n')}

请返回如下JSON格式（不要包含其他文本）：
{
  "score": -10到10之间的数值（正数表示正面，负数表示负面，0表示中性）,
  "positiveCount": 正面新闻数量,
  "negativeCount": 负面新闻数量,
  "neutralCount": 中性新闻数量,
  "keyFactors": ["影响股价的关键因素1", "影响股价的关键因素2"]
}
''';

    try {
      final response = await _callAPI(prompt);
      final json = jsonDecode(response) as Map<String, dynamic>;
      return _parseSentimentResult(json);
    } catch (e) {
      debugPrint('[GLM47Flash] 情绪分析失败: $e');
      return AISentimentResult.empty();
    }
  }

  @override
  Future<DebateResult> runDebate({
    required String stockCode,
    required String stockName,
    required Map<String, dynamic> technicalData,
    required List<String> newsTitles,
    required List<Map<String, dynamic>> historicalReflections,
    void Function(String status, int progress)? onProgress,
  }) async {
    final techDataStr = technicalData.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    final newsStr = newsTitles.join('\n');

    String historyStr = '';
    if (historicalReflections.isNotEmpty) {
      historyStr = '\n历史决策反思：\n';
      for (final r in historicalReflections) {
        historyStr += '- ${r['strategy']}: 收益${r['day20_return']}%, Alpha${r['alpha_vs_market'] ?? 0}%\n';
      }
    }

    final bullPrompt = '''
你是一个专业的股票分析师（看多）。请基于以下数据分析${stockName}(${stockCode})的看多理由：

技术面数据：
${techDataStr}

近期新闻：
${newsStr}

${historyStr}

请列出3-5条看多理由，每条不超过30字。
''';

    final bearPrompt = '''
你是一个专业的股票分析师（看空）。请基于以下数据分析${stockName}(${stockCode})的看空理由：

技术面数据：
${techDataStr}

近期新闻：
${newsStr}

${historyStr}

请列出3-5条看空理由，每条不超过30字。
''';

    try {
      onProgress?.call('分析看多观点...', 0);
      final bullCase = await _callAPI(bullPrompt);

      onProgress?.call('分析看空观点...', 33);
      final bearCase = await _callAPI(bearPrompt);

      onProgress?.call('综合评估中...', 66);
      final synthesisPrompt = '''
你是一个专业的投资决策顾问。请综合看多和看空观点，给出最终投资建议：

股票：${stockName}(${stockCode})

看多观点：
${bullCase}

看空观点：
${bearCase}

请返回如下JSON格式（不要包含其他文本）：
{
  "conclusion": "最终结论（买入/卖出/观望）",
  "confidenceLevel": "高/中/低",
  "reasons": ["支持结论的理由1", "支持结论的理由2"],
  "riskFactors": ["风险因素1", "风险因素2"],
  "adjustedConfidence": 0-1之间的数值
}
''';

      final synthesisStr = await _callAPI(synthesisPrompt);
      onProgress?.call('分析完成', 100);

      final synthesisJson = jsonDecode(synthesisStr) as Map<String, dynamic>;

      return DebateResult(
        bullCase: bullCase,
        bearCase: bearCase,
        synthesis: DebateSynthesis(
          conclusion: synthesisJson['conclusion'] as String? ?? '',
          confidenceLevel: synthesisJson['confidenceLevel'] as String? ?? '',
          reasons: (synthesisJson['reasons'] as List?)?.cast<String>() ?? [],
          riskFactors: (synthesisJson['riskFactors'] as List?)?.cast<String>() ?? [],
        ),
        adjustedConfidence: (synthesisJson['adjustedConfidence'] as num?)?.toDouble(),
      );
    } catch (e) {
      debugPrint('[GLM47Flash] 辩论分析失败: $e');
      return DebateResult.withError(formatAIError(e));
    }
  }

  @override
  Future<String> generateReflection({
    required String stockCode,
    required String stockName,
    required double signalPrice,
    required DateTime signalDate,
    required double realizedReturn,
    required double alphaVsMarket,
    required String originalRecommendation,
  }) async {
    final prompt = '''
你是一个专业的投资反思顾问。请基于以下交易结果生成反思总结：

股票：${stockName}(${stockCode})
信号日期：${signalDate.toIso8601String().split('T')[0]}
信号价格：${signalPrice}
实际收益：${realizedReturn}%
相对大盘Alpha：${alphaVsMarket}%
原始推荐：${originalRecommendation}

请生成一份详细的反思总结（100-200字），包括：
1. 推荐是否有效
2. 主要成功/失败原因
3. 下次类似情况的改进建议
''';

    try {
      return await _callAPI(prompt);
    } catch (e) {
      debugPrint('[GLM47Flash] 反思生成失败: $e');
      return '';
    }
  }

  @override
  Future<AIChatResult> analyzeByTemplate({
    required AnalysisTemplate template,
    required String stockCode,
    required String stockName,
    required Map<String, dynamic> technicalData,
    required List<String> newsTitles,
  }) async {
    final prompt = _buildTemplatePrompt(
      template: template,
      stockCode: stockCode,
      stockName: stockName,
      technicalData: technicalData,
      newsTitles: newsTitles,
    );
    try {
      final answer = await _callAPI(prompt);
      return AIChatResult(question: template.label, answer: answer);
    } catch (e) {
      debugPrint('[GLM47Flash] 模板分析失败($template): $e');
      return AIChatResult.withError(template.label, formatAIError(e));
    }
  }

  @override
  Future<AIChatResult> askCustomQuestion({
    required String question,
    required String stockCode,
    required String stockName,
    required Map<String, dynamic> technicalData,
    required List<String> newsTitles,
  }) async {
    if (question.trim().isEmpty) {
      return AIChatResult.withError(question, '问题不能为空');
    }
    final techDataStr = technicalData.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    final newsSection = newsTitles.isEmpty
        ? '近期新闻：暂无'
        : '近期新闻：\n${newsTitles.take(5).join('\n')}';
    final prompt = '''你是一位专业的A股投资顾问。请基于以下数据回答用户问题。

股票：${stockName}(${stockCode})

技术面数据：
$techDataStr

$newsSection

用户问题：$question

请提供专业、客观的分析回答（200-400字），包括：
1. 针对问题的直接回答
2. 支撑观点的关键依据
3. 需要注意的风险点（如有）

注意：不要给出明确的买卖指令，仅提供分析参考。''';
    try {
      final answer = await _callAPI(prompt);
      return AIChatResult(question: question, answer: answer);
    } catch (e) {
      debugPrint('[GLM47Flash] 自定义提问失败: $e');
      return AIChatResult.withError(question, formatAIError(e));
    }
  }

  /// 构造预设模板的提示词
  String _buildTemplatePrompt({
    required AnalysisTemplate template,
    required String stockCode,
    required String stockName,
    required Map<String, dynamic> technicalData,
    required List<String> newsTitles,
  }) {
    final techDataStr = technicalData.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    final newsSection = newsTitles.isEmpty
        ? '近期新闻：暂无'
        : '近期新闻：\n${newsTitles.take(5).join('\n')}';

    switch (template) {
      case AnalysisTemplate.shortTerm:
        return '''你是专业的A股短线交易分析师。请基于以下数据，从短线交易视角分析${stockName}(${stockCode})：

技术面数据：
$techDataStr

$newsSection

请从以下方面分析（300-500字）：
1. K线形态与量价配合
2. 关键支撑位和压力位
3. 短线买卖点判断
4. 量能变化与资金动向
5. 操作建议与止损位

注意：不要给出明确买卖指令，仅提供分析参考。''';

      case AnalysisTemplate.fundamental:
        return '''你是专业的A股基本面分析师。请基于以下数据，从基本面视角分析${stockName}(${stockCode})：

技术面数据（含估值）：
$techDataStr

$newsSection

请从以下方面分析（300-500字）：
1. 估值水平（PE/PB与行业对比）
2. 行业地位与竞争格局
3. 业绩成长性与盈利质量
4. 财务健康度（负债、现金流）
5. 中长期投资价值

注意：不要给出明确买卖指令，仅提供分析参考。''';

      case AnalysisTemplate.risk:
        return '''你是专业的A股风险评估师。请基于以下数据，评估${stockName}(${stockCode})的投资风险：

技术面数据：
$techDataStr

$newsSection

请从以下方面评估（300-500字）：
1. 技术面风险（趋势破位、超买超卖）
2. 估值风险（高估/低估）
3. 政策与行业风险
4. 流动性与资金风险
5. 建议仓位控制与止损位

注意：不要给出明确买卖指令，仅提供分析参考。''';

      case AnalysisTemplate.debate:
        return '''你是专业的投资决策顾问。请基于以下数据，对${stockName}(${stockCode})进行多空综合分析：

技术面数据：
$techDataStr

$newsSection

请列出3-5条看多理由和3-5条看空理由，并给出综合结论（300-500字）。

注意：不要给出明确买卖指令，仅提供分析参考。''';
    }
  }

  @override
  bool get isAvailable => _apiKey.isNotEmpty;

  Future<String> _callAPI(String prompt, {int maxRetries = 2, Duration timeout = const Duration(seconds: 30)}) async {
    final now = DateTime.now();
    
    if (_lastRequestTime != null) {
      final elapsed = now.difference(_lastRequestTime!);
      if (_retryDelaySeconds > 0 && elapsed.inSeconds < _retryDelaySeconds) {
        throw Exception('API请求过于频繁，请${_retryDelaySeconds - elapsed.inSeconds}秒后重试');
      }
      if (elapsed.inSeconds < 10) {
        throw Exception('请求过于频繁，请${10 - elapsed.inSeconds}秒后重试');
      }
    }

    _lastRequestTime = now;
    _retryDelaySeconds = 0;

    final request = {
      'model': _model,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'temperature': 0.7,
      'max_tokens': 2048,
      'thinking': {'type': 'disabled'},
    };

    Exception? lastError;
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final response = await _client.post(
          Uri.parse(_endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_apiKey',
          },
          body: jsonEncode(request),
        ).timeout(timeout);

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          final choices = json['choices'] as List?;
          if (choices == null || choices.isEmpty) {
            throw Exception('API返回空结果');
          }
          final message = (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
          final content = message?['content'];
          if (content == null || content is! String || content.isEmpty) {
            throw Exception('API返回空结果');
          }
          return content;
        }

        if (response.statusCode == 429) {
          _retryDelaySeconds = (5 * (attempt + 1)).clamp(5, 60);
          lastError = Exception('请求过于频繁，请${_retryDelaySeconds}秒后重试');
          await Future.delayed(Duration(seconds: _retryDelaySeconds));
          continue;
        }

        if (response.statusCode >= 500) {
          lastError = Exception('API服务器错误: ${response.statusCode}');
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          continue;
        }

        throw Exception('API调用失败: ${response.statusCode} ${response.body}');
      } on TimeoutException {
        lastError = Exception('API调用超时');
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      } catch (e) {
        lastError = e is Exception ? e : Exception('API调用异常: $e');
      }
    }

    throw lastError ?? Exception('API调用失败');
  }

  AISentimentResult _parseSentimentResult(Map<String, dynamic> json) {
    return _ParsedAISentimentResult(
      score: (json['score'] as num?)?.toDouble() ?? 0,
      positiveCount: json['positiveCount'] as int? ?? 0,
      negativeCount: json['negativeCount'] as int? ?? 0,
      neutralCount: json['neutralCount'] as int? ?? 0,
      keyFactors: (json['keyFactors'] as List?)?.cast<String>() ?? [],
    );
  }

  void close() {
    _client.close();
  }
}

class _ParsedAISentimentResult implements AISentimentResult {
  @override
  final double score;
  @override
  final int positiveCount;
  @override
  final int negativeCount;
  @override
  final int neutralCount;
  @override
  final List<String> keyFactors;

  _ParsedAISentimentResult({
    required this.score,
    required this.positiveCount,
    required this.negativeCount,
    required this.neutralCount,
    required this.keyFactors,
  });
}

/// 将异常转换为用户友好的 AI 错误信息（顶层函数，解耦具体 AI 实现）
String formatAIError(dynamic e) {
  final msg = e.toString();
  if (msg.contains('请') && msg.contains('秒后重试')) {
    return msg.replaceFirst('Exception:', '').trim();
  }
  if (msg.contains('429') || msg.contains('Too Many Requests') || msg.contains('速率限制')) {
    return '请求过于频繁（429），请稍后再试';
  } else if (msg.contains('401') || msg.contains('Unauthorized')) {
    return 'API Key无效或已过期（401）';
  } else if (msg.contains('403') || msg.contains('Forbidden')) {
    return 'API Key权限不足（403）';
  } else if (msg.contains('Timeout') || msg.contains('超时')) {
    return '请求超时，请检查网络连接';
  } else if (msg.contains('SocketException') || msg.contains('网络') || msg.contains('Connection')) {
    return '网络连接失败，请检查网络';
  } else if (msg.contains('500') || msg.contains('服务器错误')) {
    return 'AI服务器错误（5xx），请稍后再试';
  } else if (msg.contains('API返回空结果')) {
    return 'API返回空结果，可能是模型异常';
  } else if (msg.length > 100) {
    return '调用失败: ${msg.substring(0, 100)}...';
  }
  return '调用失败: $msg';
}