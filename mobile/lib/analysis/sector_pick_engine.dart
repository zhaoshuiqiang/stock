import 'dart:async';

import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../analysis/indicators.dart';
import '../analysis/signal_engine.dart';
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

  SectorPickProgress({
    required this.status,
    this.progress = 0,
    this.total = 0,
    this.picks,
    this.message,
  });
}

/// 板块精选引擎：后台分析热门板块精选，切换Tab不中断
class SectorPickEngine {
  static final SectorPickEngine _instance = SectorPickEngine._();
  static SectorPickEngine get instance => _instance;

  final ApiClient _apiClient;
  final DatabaseService _dbService;
  bool _isRunning = false;

  StreamController<SectorPickProgress> _progressController =
      StreamController<SectorPickProgress>.broadcast();

  SectorPickEngine._()
      : _apiClient = ApiClient(),
        _dbService = DatabaseService();

  bool get isRunning => _isRunning;
  Stream<SectorPickProgress> get progressStream => _ensureController().stream;

  /// 释放资源并重置内部状态，允许单例后续继续使用
  void dispose() {
    _progressController.close();
  }

  /// 获取或重建 StreamController（dispose后自动重建）
  StreamController<SectorPickProgress> _ensureController() {
    if (_progressController.isClosed) {
      _progressController = StreamController<SectorPickProgress>.broadcast();
    }
    return _progressController;
  }

  SectorPickProgress? _latestProgress;
  SectorPickProgress? get latestProgress => _latestProgress;

  /// 执行板块精选分析（异步，通过 progressStream 广播进度）
  /// 需要传入当前的热门板块数据
  Future<void> pick(List<SectorInfo> sectors) async {
    if (_isRunning) {
      _emit(SectorPickProgress(status: SectorPickStatus.alreadyRunning));
      return;
    }

    _isRunning = true;
    final topSectors = sectors.take(10).toList();

    try {
      _emit(SectorPickProgress(
        status: SectorPickStatus.analyzing,
        progress: 0,
        total: topSectors.length,
      ));

      final List<Map<String, dynamic>> picks = [];
      final Set<String> seenCodes = {};

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

          _emit(SectorPickProgress(
            status: SectorPickStatus.analyzing,
            progress: (i + j + 1).clamp(0, topSectors.length),
            total: topSectors.length,
          ));

          // 并发分析板块内股票
          final analyses = await Future.wait(
            stocks.map((stock) async {
              try {
                final klineData = await _apiClient.getStockHistory(stock.code);
                if (klineData.length < 20) return null;
                final analysis = generateAnalysis(calcAllIndicators(klineData), stock);
                if (analysis.recommendation.contains('买入')) {
                  return {
                    'code': stock.code,
                    'name': stock.name,
                    'recommendation': analysis.recommendation,
                    'score': analysis.score,
                    'sector': sector.name,
                  };
                }
                return null;
              } catch (_) {
                return null;
              }
            }),
          );

          for (final result in analyses) {
            if (result != null) {
              final code = result['code'] as String;
              if (!seenCodes.contains(code)) {
                seenCodes.add(code);
                picks.add(result);
              }
            }
          }
        }
      }

      // 按评分降序
      picks.sort((a, b) => (b['score'] as num).toInt().compareTo((a['score'] as num).toInt()));

      // 保存到数据库
      _emit(SectorPickProgress(status: SectorPickStatus.saving));
      if (picks.isNotEmpty) {
        final now = DateTime.now();
        final maps = picks.map((p) => {
          ...p,
          'analyzed_at': now.millisecondsSinceEpoch,
        }).toList();
        await _dbService.replaceSectorPickResults(maps);
      }

      debugPrint('SectorPickEngine completed: ${picks.length} picks');
      _emit(SectorPickProgress(
        status: SectorPickStatus.complete,
        picks: picks,
        progress: topSectors.length,
        total: topSectors.length,
      ));
    } catch (e) {
      debugPrint('SectorPickEngine error: $e');
      _emit(SectorPickProgress(status: SectorPickStatus.error, message: '精选出错：$e'));
    } finally {
      _isRunning = false;
    }
  }

  void _emit(SectorPickProgress progress) {
    _latestProgress = progress;
    _ensureController().add(progress);
  }
}
