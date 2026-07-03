import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/stock_models.dart';
import '../core/ai_config.dart';

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

  DebateResult({
    this.bullCase,
    this.bearCase,
    required this.synthesis,
    this.adjustedConfidence,
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

abstract class AILayer {
  Future<AISentimentResult> analyzeSentiment(List<String> newsTitles);

  Future<DebateResult> runDebate({
    required String stockCode,
    required String stockName,
    required Map<String, dynamic> technicalData,
    required List<String> newsTitles,
    required List<Map<String, dynamic>> historicalReflections,
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
      final bullCase = await _callAPI(bullPrompt);
      final bearCase = await _callAPI(bearPrompt);

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
      return DebateResult.empty();
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
  bool get isAvailable => _apiKey.isNotEmpty;

  Future<String> _callAPI(String prompt, {int maxRetries = 2, Duration timeout = const Duration(seconds: 30)}) async {
    final request = {
      'model': _model,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'temperature': 0.7,
      'max_tokens': 1024,
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
          return (choices.first as Map<String, dynamic>)['message']['content'] as String;
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