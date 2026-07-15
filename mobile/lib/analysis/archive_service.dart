import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../analysis/opportunity_engine.dart';
import '../core/stock_code_utils.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import 'decision_tracker.dart';
import 'single_stock_analyzer.dart';

/// 统一「留档」服务。
///
/// 一次用户点击同时写入两条数据：
/// 1. [archive_records]（历史口径）—— 沿用 30 天去重 / 方向反转逻辑。
/// 2. [decision_snapshots]（新模型）—— 跟踪该标的 1/3/5 日命中率。
///
/// 这样「我的留档」成为新模型可靠、可控的主要数据来源，而不再依赖
/// 容易中断的全市场扫描。用户显式留档的快照不会被 [DecisionTracker.purgeOldSnapshots] 清理。
class ArchiveService {
  /// 用户显式留档产生的决策快照来源标识。
  static const String kManualSource = 'archive';

  const ArchiveService._();

  /// 归档一只股票。
  ///
  /// [analysis] 优先使用（如个股详情页已算好的完整 [AnalysisResult]），可零额外开销
  /// 同时完成双写；[opp] 为自选页机会摘要，缺少 [ShortTermDecision]，会触发单只重分析。
  ///
  /// 返回 [ArchiveResult] 供 UI 反馈；任意一步失败仅记录日志，不向上抛异常。
  static Future<ArchiveResult> archiveStock({
    required String code,
    required String name,
    AnalysisResult? analysis,
    OpportunityResult? opp,
    required DatabaseService db,
    bool skipArchiveRecord = false,
  }) async {
    final record = _buildRecord(code, name, analysis, opp);
    var archived = false;
    try {
      archived = skipArchiveRecord ? false : await db.addArchiveIfNotExists(record);
    } catch (e) {
      debugPrint('[留档] 写入 archive_records 失败: $e');
    }

    // 取用于决策快照捕获的完整分析（含 shortTermDecision）
    AnalysisResult? captureAnalysis = analysis;
    if (captureAnalysis == null && opp != null) {
      captureAnalysis = await SingleStockAnalyzer.analyze(
        opp.code,
        name: opp.name,
      );
    }

    var captured = false;
    if (captureAnalysis != null &&
        captureAnalysis.shortTermDecision != null) {
      try {
        await DecisionTracker().capture(
          analysis: captureAnalysis,
          source: kManualSource,
          signalTradeDate: DateTime.now(),
          benchmarkCode: '000300',
        );
        await DecisionTracker().refreshPending(limit: 20);
        captured = true;
      } catch (e) {
        debugPrint('[留档] 决策快照捕获失败: $e');
      }
    }
    return ArchiveResult(archived: archived, captured: captured);
  }

  static ArchiveRecord _buildRecord(
    String code,
    String name,
    AnalysisResult? a,
    OpportunityResult? opp,
  ) {
    final quote = a?.quote;
    return ArchiveRecord(
      code: StockCodeUtils.normalizeForArchive(opp?.code ?? quote?.code ?? code),
      name: opp?.name ?? quote?.name ?? name,
      price: opp?.price ?? quote?.price ?? 0,
      changePct: opp?.changePct ?? quote?.changePct ?? 0,
      score: opp?.score ?? a?.score ?? 0,
      recommendation: opp?.recommendation ?? a?.recommendation ?? '',
      riskLevel: opp?.riskLevel ?? a?.riskLevel ?? '中等',
      buySignalCount: opp?.buySignalCount ?? 0,
      sellSignalCount: opp?.sellSignalCount ?? 0,
      activeStrategyCount: opp?.activeStrategyCount ?? 0,
      confluenceScore: opp?.confluenceScore ?? a?.confluenceScore ?? 0,
      tradeLevelsJson: opp?.tradeLevels != null
          ? jsonEncode(opp!.tradeLevels)
          : (a?.tradeLevels != null ? jsonEncode(a!.tradeLevels) : null),
      topSignals: opp?.topSignals.join('  ') ?? (a?.reasons.join('  ') ?? ''),
      archivedAt: DateTime.now(),
    );
  }
}

/// [ArchiveService.archiveStock] 的执行结果。
class ArchiveResult {
  /// 是否向 [archive_records] 写入了新行（false 表示 30 天内同方向已存在）。
  final bool archived;

  /// 是否成功捕获了决策快照（写入 [decision_snapshots]）。
  final bool captured;

  const ArchiveResult({required this.archived, required this.captured});
}
