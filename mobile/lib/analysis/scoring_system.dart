import '../models/stock_models.dart';
import 'signal_engine.dart';

/// 10级评分计算系统
/// 委托给 signal_engine.dart 的 generateAnalysis 统一处理
class ScoringSystem {
  /// 生成10级评分的分析结果（委托给统一的 generateAnalysis）
  static AnalysisResult generateAnalysisWith10LevelScore(
    List<HistoryKline> data,
    QuoteData? quote,
    MarketContext? marketContext, {
    List<dynamic>? newsList,
  }) {
    return generateAnalysis(data, quote, marketContext: marketContext, newsList: newsList);
  }
}
