import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import 'base_analysis_engine.dart';
import 'indicators.dart';
import 'market_timing.dart';
import 'sector_rotation.dart';
import 'signal_engine.dart';
import '../storage/database_service.dart';

/// 板块精选进度状态
enum SectorPickStatus { idle, analyzing, saving, complete, error, alreadyRunning }

/// 板块精选进度信息
class SectorPickProgress {
  final SectorPickStatus status;
  final int progress;
  final int total;
  final List<Map<String, dynamic>>? picks;
  final String? message;
  final MarketTimingResult? marketTiming;
  final SectorRotationResult? sectorRotation;

  SectorPickProgress({
    required this.status,
    this.progress = 0,
    this.total = 0,
    this.picks,
    this.message,
    this.marketTiming,
    this.sectorRotation,
  });
}

/// 板块精选引擎：后台分析热门板块精选，切换Tab不中断
/// v2.33: 接入 SectorRotation 主线轮动加成（激活孤儿模块）
class SectorPickEngine extends BaseAnalysisEngine<SectorPickProgress> {
  static final SectorPickEngine _instance = SectorPickEngine._();
  static SectorPickEngine get instance => _instance;

  final ApiClient _apiClient;
  final DatabaseService _dbService;

  SectorPickEngine._()
      : _apiClient = ApiClient(),
        _dbService = DatabaseService();

  /// 执行板块精选分析（异步，通过 progressStream 广播进度）
  /// 需要传入当前的热门板块数据
  Future<void> pick(List<SectorInfo> sectors) async {
    if (!tryStart(SectorPickProgress(status: SectorPickStatus.alreadyRunning))) return;

    final topSectors = sectors.take(10).toList();

    try {
      // 获取市场择时（用于UI展示与主线判定参考）
      final marketTiming = await MarketTiming.fetchTiming();

      // 初步主线轮动（仅基于板块涨幅，用于早期UI展示）
      final initialRotation = SectorRotation.analyze(
        sectorList: topSectors
            .map((s) => SectorData(name: s.name, code: s.code, changePct: s.changePct))
            .toList(),
      );

      emit(SectorPickProgress(
        status: SectorPickStatus.analyzing,
        progress: 0,
        total: topSectors.length,
        marketTiming: marketTiming,
        sectorRotation: initialRotation,
      ));

      final List<Map<String, dynamic>> picks = [];
      final Set<String> seenCodes = {};
      // 跟踪每个板块的涨停股数量（用于主线轮动加成判定）
      final Map<String, int> sectorLimitUpCount = {};

      // 分批处理板块，每批5个
      for (int i = 0; i < topSectors.length; i += 5) {
        final batch = topSectors.sublist(i, i + 5 > topSectors.length ? topSectors.length : i + 5);

        // 并发获取板块成分股
        final sectorStocksList = await Future.wait(
          batch.map((sector) => _apiClient.getSectorStocks(sector.code).catchError((_) => <QuoteData>[])),
        );

        for (int j = 0; j < batch.length; j++) {
          final sector = batch[j];
          final stocks = sectorStocksList[j].take(10).toList();

          emit(SectorPickProgress(
            status: SectorPickStatus.analyzing,
            progress: (i + j + 1).clamp(0, topSectors.length),
            total: topSectors.length,
            marketTiming: marketTiming,
            sectorRotation: initialRotation,
          ));

          // 并发分析板块内股票
          final analyses = await Future.wait(
            stocks.map((stock) async {
              try {
                final klineData = await _apiClient.getStockHistory(stock.code);
                if (klineData.length < 20) return null;
                final analysis = generateAnalysis(calcAllIndicators(klineData), stock);
                return {'stock': stock, 'analysis': analysis};
              } catch (_) {
                return null;
              }
            }),
          );

          for (final result in analyses) {
            if (result == null) continue;
            final stock = result['stock'] as QuoteData;
            final analysis = result['analysis'] as AnalysisResult;

            // 统计涨停股（用于板块主线判定）
            if (analysis.limitUpAnalysis != null) {
              sectorLimitUpCount[sector.name] = (sectorLimitUpCount[sector.name] ?? 0) + 1;
            }

            if (!analysis.recommendation.contains('买入')) continue;

            final code = stock.code;
            if (seenCodes.contains(code)) continue;
            seenCodes.add(code);

            picks.add({
              'code': code,
              'name': stock.name,
              'recommendation': analysis.recommendation,
              'score': analysis.score,
              'originalScore': analysis.score,
              'sector': sector.name,
              'sectorCode': sector.code,
              'mainLine': false,
              'bonus': 1.0,
            });
          }
        }
      }

      // 用涨停数增强后的板块数据重新分析主线轮动
      final enrichedRotation = SectorRotation.analyze(
        sectorList: topSectors
            .map((s) => SectorData(
                  name: s.name,
                  code: s.code,
                  changePct: s.changePct,
                  limitUpCount: sectorLimitUpCount[s.name] ?? 0,
                ))
            .toList(),
      );

      // 应用主线加成：主线板块内个股评分 × bonus（上限 10）
      for (final pick in picks) {
        final sectorName = pick['sector'] as String;
        final originalScore = pick['originalScore'] as int;
        final isMainLine = SectorRotation.isInMainLine(sectorName, enrichedRotation.mainLines);
        final bonus = SectorRotation.getMainLineBonus(sectorName, enrichedRotation.mainLines);
        final boostedScore = (originalScore * bonus).clamp(0, 10).round();
        pick['score'] = boostedScore;
        pick['mainLine'] = isMainLine;
        pick['bonus'] = bonus;
      }

      // 按评分降序（主线加成后的分数）
      picks.sort((a, b) => (b['score'] as num).toInt().compareTo((a['score'] as num).toInt()));

      // 保存到数据库
      emit(SectorPickProgress(
        status: SectorPickStatus.saving,
        marketTiming: marketTiming,
        sectorRotation: enrichedRotation,
      ));
      if (picks.isNotEmpty) {
        final now = DateTime.now();
        final maps = picks.map((p) => {
              ...p,
              'analyzed_at': now.millisecondsSinceEpoch,
            }).toList();
        await _dbService.replaceSectorPickResults(maps);
      }

      final mainLineCount = enrichedRotation.mainLines.length;
      final boostedCount = picks.where((p) => p['mainLine'] == true).length;
      debugPrint('SectorPickEngine completed: ${picks.length} picks, '
          '$mainLineCount main-line sectors, $boostedCount boosted stocks');

      emit(SectorPickProgress(
        status: SectorPickStatus.complete,
        picks: picks,
        progress: topSectors.length,
        total: topSectors.length,
        marketTiming: marketTiming,
        sectorRotation: enrichedRotation,
      ));
    } catch (e) {
      debugPrint('SectorPickEngine error: $e');
      emit(SectorPickProgress(status: SectorPickStatus.error, message: '精选出错：$e'));
    } finally {
      markFinished();
    }
  }
}
