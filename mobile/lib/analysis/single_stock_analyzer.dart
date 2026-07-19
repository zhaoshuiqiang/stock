import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/market_context_provider.dart';
import '../models/stock_models.dart';
import '../analysis/indicators.dart';
import '../analysis/signal_engine.dart';
import '../analysis/sector_rotation.dart';
import '../analysis/decision_calibration_service.dart';

/// 单只股票的完整分析管线。
///
/// 提取自 [QuoteScreen._loadData]，供「留档」等需要在列表/详情之外
/// 单独分析一只股票并拿到完整 [AnalysisResult]（含 [ShortTermDecision]）的场景复用。
class SingleStockAnalyzer {
  SingleStockAnalyzer._();

  /// 分析单只股票，返回含 [AnalysisResult.shortTermDecision] 的完整结果。
  ///
  /// 仅在行情/K线获取成功且 [generateAnalysis] 产出有效结果时返回非 null；
  /// 任一前置步骤失败时返回 null（不抛异常），调用方据此降级。
  static Future<AnalysisResult?> analyze(String code, {String? name}) async {
    try {
      final results = await Future.wait([
        ApiClient().getRealtimeQuoteWithValidation(code),
        ApiClient().getStockHistory(code, days: 120),
        ApiClient().getStockSector(code),
        ApiClient().getHotSectors(),
        MarketContextProvider.getMarketContext(),
        ApiClient().getRoe(code),
      ]);

      var quote = (results[0] as ValidatedQuoteData?)?.quote;
      final roe = results[5] as double?;
      if (quote != null && roe != null) {
        quote = quote.copyWith(roe: roe);
      }
      final klines = results[1] as List<HistoryKline>?;
      final sectorName = results[2] as String?;
      final hotSectors = results[3] as List<SectorInfo>?;
      final marketContext = results[4] as MarketContext?;

      if (quote == null || klines == null || klines.length < 20) return null;

      final calculated = calcAllIndicators(klines);

      final sectorData = (hotSectors ?? [])
          .map((s) => SectorData(
                name: s.name,
                code: s.code,
                changePct: s.changePct,
                limitUpCount: s.stockCount,
                mainNetFlow: 0,
              ))
          .toList();
      final sectorRotationResult = SectorRotation.analyze(sectorList: sectorData);

      var analysis = generateAnalysis(
        calculated,
        quote,
        marketContext: marketContext,
        sectorName: sectorName,
        sectorAnalysis: sectorRotationResult.topSectors,
        enableAsyncSideEffects: false,
      );
      try {
        analysis = await DecisionCalibrationService().enrich(
          analysis,
          asOfTradeDate: calculated.last.date,
        );
      } catch (e) {
        debugPrint('SingleStockAnalyzer.calibration: $e');
      }
      return analysis;
    } catch (e) {
      debugPrint('SingleStockAnalyzer.analyze($code) 失败: $e');
      return null;
    }
  }
}
