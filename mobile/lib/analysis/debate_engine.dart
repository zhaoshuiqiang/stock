import 'package:flutter/foundation.dart';
import 'ai_layer.dart';

class DebateEngine {
  final AILayer _aiLayer;

  DebateEngine(this._aiLayer);

  Future<DebateResult> debate({
    required String stockCode,
    required String stockName,
    required double totalScore,
    required Map<String, dynamic> dimensionScores,
    required List<String> newsTitles,
    required List<Map<String, dynamic>> historicalReflections,
  }) async {
    if (!_aiLayer.isAvailable) {
      return DebateResult.empty();
    }

    final techData = {
      '综合评分': totalScore,
      ...dimensionScores,
    };

    try {
      return await _aiLayer.runDebate(
        stockCode: stockCode,
        stockName: stockName,
        technicalData: techData,
        newsTitles: newsTitles,
        historicalReflections: historicalReflections,
      );
    } catch (e) {
      debugPrint('[DebateEngine] 辩论失败: $e');
      return DebateResult.empty();
    }
  }
}