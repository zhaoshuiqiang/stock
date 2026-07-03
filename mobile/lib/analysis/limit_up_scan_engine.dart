import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:stock_analyzer/analysis/base_analysis_engine.dart';
import 'package:stock_analyzer/analysis/limit_up_analyzer.dart';
import 'package:stock_analyzer/analysis/limit_up_universe_provider.dart';
import 'package:stock_analyzer/analysis/sentiment_thermometer.dart';
import 'package:stock_analyzer/api/api_client.dart';
import 'package:stock_analyzer/models/stock_models.dart';
import 'package:stock_analyzer/storage/database_service.dart';

/// 打板扫描进度
class LimitUpScanProgress {
  final String stage;        // 'fetching' / 'analyzing' / 'computing_sentiment' / 'done'
  final int current;
  final int total;
  final String? message;
  final String? tradeDate;   // 数据所属交易日
  final bool isHistorical;   // 是否为历史数据（非今日数据）
  const LimitUpScanProgress({
    required this.stage,
    this.current = 0,
    this.total = 0,
    this.message,
    this.tradeDate,
    this.isHistorical = false,
  });
}

/// 打板扫描协调器
/// 封装：API 拉取 → analyzeBatchList → SentimentThermometer.compute → 落库
class LimitUpScanEngine extends BaseAnalysisEngine<LimitUpScanProgress> {
  static final LimitUpScanEngine _instance = LimitUpScanEngine._();
  static LimitUpScanEngine get instance => _instance;

  final ApiClient _apiClient;
  final DatabaseService _dbService;

  String? _currentTradeDate;
  bool _isCurrentDataHistorical = false;

  LimitUpScanEngine._()
      : _apiClient = ApiClient(),
        _dbService = DatabaseService();

  String? get currentTradeDate => _currentTradeDate;
  bool get isCurrentDataHistorical => _isCurrentDataHistorical;

  /// 执行完整扫描流程
  /// 返回 SentimentResult（也通过 progressStream 广播进度）
  Future<SentimentResult?> scan() async {
    if (!tryStart(const LimitUpScanProgress(
        stage: 'already_running', message: '扫描进行中'))) {
      return null;
    }

    try {
      // Step 1: 拉取今日 + 昨日涨停池
      emit(const LimitUpScanProgress(stage: 'fetching', message: '拉取涨停板数据...'));
      final todayStocks = await LimitUpUniverseProvider.fetchLatest(apiClient: _apiClient);

      if (todayStocks.isEmpty) {
        final shanghaiNow = DateTime.now().toUtc().add(const Duration(hours: 8));
        final todayDate = shanghaiNow.toIso8601String().substring(0, 10);

        final dbPool = await _dbService.getLimitUpPool();
        if (dbPool.isEmpty) {
          final dates = await _dbService.getLimitUpDates();
          if (dates.isNotEmpty) {
            final latestDate = dates.first;
            final latestPool = await _dbService.getLimitUpPool(tradeDate: latestDate);
            if (latestPool.isNotEmpty) {
              _currentTradeDate = latestDate;
              _isCurrentDataHistorical = latestDate != todayDate;
              final todayAnalyses = latestPool;
              final sentiment = SentimentThermometer.compute(
                todayPool: todayAnalyses,
                yesterdayPool: [],
                todayQuotePct: {},
                yesterdayPhase: _lastSentiment?.phase,
              );
              _lastSentiment = sentiment;
              emit(LimitUpScanProgress(
                stage: 'done',
                message: '使用缓存数据计算情绪',
                tradeDate: latestDate,
                isHistorical: true,
              ));
              return sentiment;
            }
          }
          _currentTradeDate = null;
          _isCurrentDataHistorical = false;
          emit(const LimitUpScanProgress(stage: 'done', message: '暂无涨停数据'));
          return null;
        }

        _currentTradeDate = todayDate;
        _isCurrentDataHistorical = true;
        final sentiment = SentimentThermometer.compute(
          todayPool: dbPool,
          yesterdayPool: [],
          todayQuotePct: {},
          yesterdayPhase: _lastSentiment?.phase,
        );
        _lastSentiment = sentiment;
        emit(LimitUpScanProgress(
          stage: 'done',
          message: '使用缓存数据计算情绪',
          tradeDate: todayDate,
          isHistorical: true,
        ));
        return sentiment;
      }

      final yesterdayStocks = await _apiClient.getYesterdayLimitUpPool();
      // 为昨日涨停池补充今日实时行情（计算赚钱效应需要今日涨跌幅）
      final yesterdayQuotes = <QuoteData>[];
      for (var i = 0; i < yesterdayStocks.length; i += 30) {
        try {
          final batch = yesterdayStocks.skip(i).take(30).map((s) => s.code).toList();
          final prefixed = batch.map((c) => _apiClient.addMarketPrefix(c)).toList();
          final quotes = await _apiClient.getBatchRealtimeQuotes(prefixed);
          yesterdayQuotes.addAll(quotes);
        } catch (e) {
          debugPrint('LimitUpScanEngine: 昨日池行情批次 $i 失败: $e');
        }
      }
      final supplementedYesterday = LimitUpUniverseProvider.supplementQuotes(yesterdayStocks, yesterdayQuotes);
      final yesterdayAnalyses = LimitUpAnalyzer.analyzeBatchList(supplementedYesterday);

      // Step 2: 分析今日涨停股
      emit(LimitUpScanProgress(
          stage: 'analyzing', current: 0, total: todayStocks.length,
          message: '分析打板质量...'));
      final todayAnalyses = LimitUpAnalyzer.analyzeBatchList(todayStocks);

      // Step 3: 计算情绪温度计
      emit(const LimitUpScanProgress(stage: 'computing_sentiment', message: '计算情绪温度计...'));
      // 赚钱效应 = 昨日涨停股今日涨跌幅的均值，因此 todayQuotePct 必须以昨日 code 为键
      final todayQuotePct = <String, double>{};
      for (final a in yesterdayAnalyses) {
        todayQuotePct[a.code] = a.changePct;
      }
      final sentiment = SentimentThermometer.compute(
        todayPool: todayAnalyses,
        yesterdayPool: yesterdayAnalyses,
        todayQuotePct: todayQuotePct,
        yesterdayPhase: _lastSentiment?.phase,
      );
      _lastSentiment = sentiment;

      // Step 5: 落库
      // A股交易日按上海时区计算，避免海外/出差用户日期偏移
      final shanghaiNow = DateTime.now().toUtc().add(const Duration(hours: 8));
      final tradeDate = shanghaiNow.toIso8601String().substring(0, 10);
      _currentTradeDate = tradeDate;
      _isCurrentDataHistorical = false;
      await _dbService.replaceLimitUpPool(todayAnalyses, tradeDate);

      emit(LimitUpScanProgress(
        stage: 'done',
        message: '扫描完成',
        tradeDate: tradeDate,
        isHistorical: false,
      ));
      return sentiment;
    } catch (e) {
      debugPrint('LimitUpScanEngine.scan failed: $e');
      emit(const LimitUpScanProgress(stage: 'error', message: '扫描失败，请稍后重试'));
      return null;
    } finally {
      markFinished();
    }
  }

  SentimentResult? _lastSentiment;
  /// 内存缓存最近一次情绪结果（供下次计算 yesterdayPhase）
  SentimentResult? get lastSentiment => _lastSentiment;
}
