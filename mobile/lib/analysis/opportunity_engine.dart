import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../analysis/indicators.dart';
import '../analysis/signal_layer.dart';
import '../analysis/signal_engine.dart';
import '../analysis/market_timing.dart';
import '../api/market_context_provider.dart';
import '../storage/database_service.dart';

/// 机会分析结果
class OpportunityResult {
  final String code;
  final String name;
  final double price;
  final double changePct;
  final int score;
  final String recommendation;
  final String riskLevel;
  final int buySignalCount;
  final int sellSignalCount;
  final int activeStrategyCount;
  final int confluenceScore;
  final Map<String, dynamic>? tradeLevels;
  final List<String> topSignals;

  OpportunityResult({
    required this.code,
    required this.name,
    required this.price,
    required this.changePct,
    required this.score,
    required this.recommendation,
    required this.riskLevel,
    required this.buySignalCount,
    required this.sellSignalCount,
    required this.activeStrategyCount,
    required this.confluenceScore,
    this.tradeLevels,
    this.topSignals = const [],
  });

  Map<String, dynamic> toMap([DateTime? analyzedAt]) {
    return {
      'code': code,
      'name': name,
      'price': price,
      'change_pct': changePct,
      'score': score,
      'recommendation': recommendation,
      'risk_level': riskLevel,
      'buy_signal_count': buySignalCount,
      'sell_signal_count': sellSignalCount,
      'active_strategy_count': activeStrategyCount,
      'confluence_score': confluenceScore,
      'trade_levels_json': tradeLevels != null ? jsonEncode(tradeLevels) : null,
      'top_signals': topSignals.join('  '),
      'analyzed_at': (analyzedAt ?? DateTime.now()).millisecondsSinceEpoch,
    };
  }

  static OpportunityResult fromMap(Map<String, dynamic> map) {
    Map<String, dynamic>? tradeLevels;
    if (map['trade_levels_json'] != null && (map['trade_levels_json'] as String).isNotEmpty) {
      try {
        tradeLevels = jsonDecode(map['trade_levels_json'] as String);
      } catch (_) {}
    }
    List<String> topSignals = [];
    if (map['top_signals'] != null && (map['top_signals'] as String).isNotEmpty) {
      topSignals = (map['top_signals'] as String).split('  ').where((s) => s.isNotEmpty).toList();
    }
    return OpportunityResult(
      code: map['code'] as String,
      name: map['name'] as String,
      price: (map['price'] as num?)?.toDouble() ?? 0,
      changePct: (map['change_pct'] as num?)?.toDouble() ?? 0,
      score: (map['score'] as num?)?.toInt() ?? 0,
      recommendation: map['recommendation'] as String? ?? '',
      riskLevel: map['risk_level'] as String? ?? '',
      buySignalCount: (map['buy_signal_count'] as num?)?.toInt() ?? 0,
      sellSignalCount: (map['sell_signal_count'] as num?)?.toInt() ?? 0,
      activeStrategyCount: (map['active_strategy_count'] as num?)?.toInt() ?? 0,
      confluenceScore: (map['confluence_score'] as num?)?.toInt() ?? 0,
      tradeLevels: tradeLevels,
      topSignals: topSignals,
    );
  }
}

/// 机会分析进度状态
enum OpportunityStatus { idle, fetching, analyzing, saving, complete, error, alreadyRunning }

/// 机会分析进度信息
class OpportunityProgress {
  final OpportunityStatus status;
  final int completedCount;
  final int totalCount;
  final List<OpportunityResult>? results;
  final String? message;

  OpportunityProgress({
    required this.status,
    this.completedCount = 0,
    this.totalCount = 0,
    this.results,
    this.message,
  });
}

/// 机会分析引擎：后台分析自选股机会与风险，切换Tab不中断
class OpportunityEngine {
  static final OpportunityEngine _instance = OpportunityEngine._();
  static OpportunityEngine get instance => _instance;

  final ApiClient _apiClient;
  final DatabaseService _dbService;
  bool _isRunning = false;

  StreamController<OpportunityProgress> _progressController =
      StreamController<OpportunityProgress>.broadcast();

  OpportunityEngine._()
      : _apiClient = ApiClient(),
        _dbService = DatabaseService();

  bool get isRunning => _isRunning;
  Stream<OpportunityProgress> get progressStream => _ensureController().stream;

  /// 释放资源并重置内部状态，允许单例后续继续使用
  void dispose() {
    _isRunning = false;
    _progressController.close();
  }

  /// 获取或重建 StreamController（dispose后自动重建）
  StreamController<OpportunityProgress> _ensureController() {
    if (_progressController.isClosed) {
      _progressController = StreamController<OpportunityProgress>.broadcast();
    }
    return _progressController;
  }

  OpportunityProgress? _latestProgress;
  OpportunityProgress? get latestProgress => _latestProgress;

  /// 执行机会分析（优化版：MarketTiming仅计算一次，并发度提升，K线天数缩减）
  Future<void> analyze() async {
    if (_isRunning) {
      _emit(OpportunityProgress(status: OpportunityStatus.alreadyRunning));
      return;
    }
    _isRunning = true;

    try {
      // 1. 获取自选列表
      _emit(OpportunityProgress(status: OpportunityStatus.fetching));
      final watchlist = await _dbService.getWatchlist();
      if (watchlist.isEmpty) {
        _emit(OpportunityProgress(status: OpportunityStatus.complete, results: [], totalCount: 0));
        _isRunning = false;
        return;
      }
      final totalCount = watchlist.length;

      // 2. 批量获取行情 + 市场环境（并行）
      final prefixedCodes = watchlist.map((item) => _apiClient.addMarketPrefix(item.code)).toList();
      final futures = <Future>[
        _apiClient.getBatchRealtimeQuotes(prefixedCodes).catchError((_) => <QuoteData>[]),
        _fetchMarketTiming(),
      ];
      final results_futures = await Future.wait(futures);
      final batchQuotes = results_futures[0] as List<QuoteData>;

      final quoteMap = <String, QuoteData>{};
      for (final q in batchQuotes) {
        quoteMap[q.code] = q;
      }

      final marketTimingResult = results_futures[1] as MarketTimingResult?;
      final positionFactor = marketTimingResult != null ? MarketTiming.getPositionAdjustment(marketTimingResult) : null;

      _emit(OpportunityProgress(status: OpportunityStatus.analyzing, totalCount: totalCount, completedCount: 0));

      // 3. 分批分析，并发10（与发现页一致使用120天K线）
      const batchSize = 10;
      const klineDays = 120;
      final results = <OpportunityResult?>[];
      int completedCount = 0;

      for (int i = 0; i < watchlist.length; i += batchSize) {
        final batch = watchlist.sublist(i, (i + batchSize).clamp(0, watchlist.length));
        final batchResults = await Future.wait(batch.map((item) async {
          try {
            final prefixedCode = _apiClient.addMarketPrefix(item.code);
            QuoteData? quote = quoteMap[prefixedCode];
            if (quote == null) {
              try { quote = await _apiClient.getRealtimeQuote(prefixedCode); } catch (_) {}
            }

            final klines = await _apiClient.getStockHistory(prefixedCode, days: klineDays);
            if (klines.isEmpty) return null;

            final calculated = calcAllIndicators(klines);
            final analysis = generateAnalysis(calculated, quote);

            final signals = analysis.signals;
            final last = calculated.last;
            final topSignals = signals.take(2).map((s) =>
                '${s.type == 'buy' ? '▲' : '▼'}${s.signal}').toList();

            return OpportunityResult(
              code: item.code, name: item.name,
              price: quote?.price ?? last.close,
              changePct: quote?.changePct ?? last.changePct,
              score: analysis.score, recommendation: analysis.recommendation,
              riskLevel: analysis.riskLevel,
              buySignalCount: signals.where((s) => s.type == 'buy').length,
              sellSignalCount: signals.where((s) => s.type == 'sell').length,
              activeStrategyCount: analysis.shortTermStrategies.length + analysis.longTermStrategies.length,
              confluenceScore: analysis.confluenceScore,
              tradeLevels: analysis.tradeLevels,
              topSignals: topSignals,
            );
          } catch (_) { return null; }
        }));

        results.addAll(batchResults);
        completedCount += batch.length;
        _emit(OpportunityProgress(status: OpportunityStatus.analyzing,
            totalCount: totalCount, completedCount: completedCount.clamp(0, totalCount)));
      }

      // 4. 排序并保存
      final opportunities = results.whereType<OpportunityResult>().toList();
      opportunities.sort((a, b) => b.score.compareTo(a.score));

      _emit(OpportunityProgress(status: OpportunityStatus.saving));
      await _dbService.replaceOpportunityResults(
          opportunities.map((o) => o.toMap(DateTime.now())).toList());

      _emit(OpportunityProgress(status: OpportunityStatus.complete,
          results: opportunities, totalCount: totalCount, completedCount: totalCount));
    } catch (e) {
      _emit(OpportunityProgress(status: OpportunityStatus.error, message: '分析出错：$e'));
    } finally {
      _isRunning = false;
    }
  }

  /// 获取市场择时结果（仅调用一次，含情绪数据）
  static Future<MarketTimingResult?> _fetchMarketTiming() async {
    try {
      final results = await Future.wait([
        MarketContextProvider.getMarketContext(),
        ApiClient().getMarketSentiment(),
      ]);
      return MarketTiming.analyze(
        marketContext: results[0] as MarketContext?,
        marketSentiment: results[1] as MarketSentiment?,
      );
    } catch (_) { return null; }
  }

  void _emit(OpportunityProgress progress) {
    _latestProgress = progress;
    _ensureController().add(progress);
  }
}
