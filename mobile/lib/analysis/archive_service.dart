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
  /// 同时完成双写；[opp] 为自选页机会摘要，其已携带扫描期算出的 [ShortTermDecision]，
  /// 直接据此构建捕获所需的 [AnalysisResult]，无需重新发起网络分析。仅当 [opp] 缺少
  /// [ShortTermDecision]（旧数据/未持久化）时才回退到 [SingleStockAnalyzer] 单只重分析。
  ///
  /// [skipRefreshPending] 为 true 时不在每次捕获后调用 [DecisionTracker.refreshPending]，
  /// 由调用方在批量归档结束后统一刷新一次，避免 N 次网络拉取。
  ///
  /// 返回 [ArchiveResult] 供 UI 反馈；任意一步失败仅记录日志，不向上抛异常。
  static Future<ArchiveResult> archiveStock({
    required String code,
    required String name,
    AnalysisResult? analysis,
    OpportunityResult? opp,
    required DatabaseService db,
    bool skipArchiveRecord = false,
    bool skipRefreshPending = false,
  }) async {
    final record = _buildRecord(code, name, analysis, opp);
    var archived = false;
    try {
      archived = skipArchiveRecord ? false : await db.addArchiveIfNotExists(record);
    } catch (e) {
      debugPrint('[留档] 写入 archive_records 失败: $e');
    }

    // 取用于决策快照捕获的完整分析（含 shortTermDecision）。
    // 优先复用已有 analysis；其次由 opp 直接构建（零网络开销）；最后回退单只重分析。
    AnalysisResult? captureAnalysis = analysis;
    if (captureAnalysis == null && opp != null) {
      if (opp.shortTermDecision != null) {
        captureAnalysis = _analysisFromOpportunity(opp);
      } else {
        captureAnalysis = await SingleStockAnalyzer.analyze(
          opp.code,
          name: opp.name,
        );
      }
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
        if (!skipRefreshPending) {
          await DecisionTracker().refreshPending(limit: 20);
        }
        captured = true;
      } catch (e) {
        debugPrint('[留档] 决策快照捕获失败: $e');
      }
    }
    return ArchiveResult(archived: archived, captured: captured);
  }

  /// 由 [OpportunityResult] 直接构建捕获所需的 [AnalysisResult]。
  ///
  /// 仅填入 [DecisionTracker.capture] 实际读取的字段（quote / recommendation /
  /// score / shortTermDecision），其余沿用默认值。这样留档双写不再依赖联网重算，
  /// 复用机会扫描期已算好的 [ShortTermDecision]。
  static AnalysisResult _analysisFromOpportunity(OpportunityResult opp) {
    return AnalysisResult(
      quote: QuoteData(
        code: opp.code,
        name: opp.name,
        price: opp.price,
        changePct: opp.changePct,
        updateTime: DateTime.now(),
      ),
      score: opp.score,
      recommendation: opp.recommendation,
      shortTermDecision: opp.shortTermDecision,
    );
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

  /// 为「仅有历史口径、缺少决策快照」的留档记录补录决策信息。
  ///
  /// 留档记录本身不持久化 [ShortTermDecision]（方向评分/市场状态/模型版本等），
  /// 无法本地重建，因此对本批次中每只缺失记录重新联网分析
  /// （[SingleStockAnalyzer]）后捕获决策快照。[signalTradeDate] 取留档时间，
  /// 使命中率从该留档点起算。已存在 `source='archive'` 快照的标的会被跳过，
  /// 不会重复写入（[decision_snapshots] 有唯一约束）。
  ///
  /// [concurrency] 控制并发分析数，避免瞬间打满行情接口；[shouldCancel]
  /// 返回 true 时在当前批次结束后中止。进度通过 [onProgress] 回调（done/total）。
  static Future<BackfillSummary> backfillMissingDecisionSnapshots({
    required DatabaseService db,
    required void Function(int done, int total) onProgress,
    bool Function()? shouldCancel,
    int concurrency = 5,
  }) async {
    final archives = await db.getArchives();
    final existingRaw =
        await db.getDecisionSnapshotCodes(source: kManualSource);
    final have = existingRaw.map(StockCodeUtils.normalizeForArchive).toSet();
    final need = archives
        .where((a) => !have.contains(StockCodeUtils.normalizeForArchive(a.code)))
        .toList();
    if (need.isEmpty) {
      return const BackfillSummary(total: 0, done: 0, success: 0, failed: 0);
    }
    var done = 0;
    var success = 0;
    var failed = 0;
    for (var i = 0; i < need.length; i += concurrency) {
      if (shouldCancel?.call() == true) break;
      final end = (i + concurrency > need.length) ? need.length : i + concurrency;
      final batch = need.sublist(i, end);
      final results = await Future.wait(batch.map((record) async {
        try {
          final raw = StockCodeUtils.stripMarketPrefix(record.code);
          final analysis = await SingleStockAnalyzer.analyze(
            raw,
            name: record.name,
          );
          if (analysis == null || analysis.shortTermDecision == null) {
            return false;
          }
          await DecisionTracker().capture(
            analysis: analysis,
            source: kManualSource,
            signalTradeDate: record.archivedAt,
            benchmarkCode: '000300',
          );
          return true;
        } catch (e) {
          debugPrint('[留档] 回填决策失败 ${record.code}: $e');
          return false;
        }
      }));
      for (final ok in results) {
        done++;
        if (ok) success++;
        if (!ok) failed++;
      }
      onProgress(done, need.length);
    }
    return BackfillSummary(
      total: need.length,
      done: done,
      success: success,
      failed: failed,
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

/// 批量回填结果的汇总。
class BackfillSummary {
  /// 需要回填的留档记录数（缺少 source='archive' 决策快照）。
  final int total;

  /// 已处理数。
  final int done;

  /// 成功生成决策快照数。
  final int success;

  /// 失败数（分析失败 / 无 shortTermDecision / 写入冲突）。
  final int failed;

  const BackfillSummary({
    required this.total,
    required this.done,
    required this.success,
    required this.failed,
  });
}

