import 'dart:convert';

import 'package:flutter/foundation.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import '../data/concept_tag_provider.dart';
import '../core/ai_config.dart';
import '../core/trading_calendar.dart';
import 'market_structure_analyzer.dart';
import 'ai_layer.dart';

/// 推荐快照 - 用于追踪推荐信号的实际表现
/// v2.53: 增加反思存储和Alpha计算字段（决策反馈闭环）
/// v3.2: 增加用户反馈字段（推荐反馈闭环）
class RecommendationSnapshot {
  final int? id;
  final String code;
  final String name;
  final double signalPrice;
  final DateTime signalDate;
  final String marketStructure;
  final String strategy;
  final String conceptTags;
  final double? day5Return;
  final double? day10Return;
  final double? day20Return;
  final double? day20Price;
  final bool isClosed;
  final String? reflection;
  final double? alphaVsMarket;
  final String? confidenceAdjustment;
  final String? feedback;
  final Map<String, double>? dimensionScores;
  final double? score;
  final String direction; // v3.19: bullish/bearish/neutral，修正命中率方向盲

  RecommendationSnapshot({
    this.id,
    required this.code,
    required this.name,
    required this.signalPrice,
    required this.signalDate,
    this.marketStructure = '',
    this.strategy = '',
    this.conceptTags = '',
    this.day5Return,
    this.day10Return,
    this.day20Return,
    this.day20Price,
    this.isClosed = false,
    this.reflection,
    this.alphaVsMarket,
    this.confidenceAdjustment,
    this.feedback,
    this.dimensionScores,
    this.score,
    this.direction = '',
  });

  factory RecommendationSnapshot.fromMap(Map<String, dynamic> map) {
    return RecommendationSnapshot(
      id: map['id'] as int?,
      code: map['code'] as String,
      name: map['name'] as String? ?? '',
      signalPrice: (map['signal_price'] as num).toDouble(),
      signalDate:
          DateTime.fromMillisecondsSinceEpoch(map['signal_date'] as int),
      marketStructure: map['market_structure'] as String? ?? '',
      strategy: map['strategy'] as String? ?? '',
      conceptTags: map['concept_tags'] as String? ?? '',
      day5Return: (map['day5_return'] as num?)?.toDouble(),
      day10Return: (map['day10_return'] as num?)?.toDouble(),
      day20Return: (map['day20_return'] as num?)?.toDouble(),
      day20Price: (map['day20_price'] as num?)?.toDouble(),
      isClosed: (map['is_closed'] as int?) == 1,
      reflection: map['reflection'] as String? ?? '',
      alphaVsMarket: (map['alpha_vs_market'] as num?)?.toDouble(),
      confidenceAdjustment: map['confidence_adjustment'] as String? ?? '',
      feedback: map['feedback'] as String? ?? '',
      score: (map['score'] as num?)?.toDouble(),
      dimensionScores:
          _decodeDimensionScores(map['dimension_scores_json'] as String?),
      direction: (map['direction'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'code': code,
      'name': name,
      'signal_price': signalPrice,
      'signal_date': signalDate.millisecondsSinceEpoch,
      'market_structure': marketStructure,
      'strategy': strategy,
      'concept_tags': conceptTags,
      'day5_price': null,
      'day5_return': day5Return,
      'day10_price': null,
      'day10_return': day10Return,
      'day20_price': day20Price,
      'day20_return': day20Return,
      'last_checked_date': null,
      'is_closed': isClosed ? 1 : 0,
      'reflection': reflection ?? '',
      'alpha_vs_market': alphaVsMarket,
      'confidence_adjustment': confidenceAdjustment ?? '',
      'feedback': feedback ?? '',
      'score': score,
      'direction': direction,
      'dimension_scores_json': _encodeDimensionScores(dimensionScores),
    };
  }
}

/// v3.19: 从推荐文案推导方向，用于修正命中率方向盲问题。
/// 与 archive_reliability_evaluator 的判定口径保持一致。
String directionOf(String recommendation) {
  if (recommendation.contains('买入') ||
      recommendation.contains('看多') ||
      recommendation.contains('偏多观望')) {
    return 'bullish';
  }
  if (recommendation.contains('卖出') ||
      recommendation.contains('回避') ||
      recommendation.contains('减仓') ||
      recommendation.contains('偏空观望')) {
    return 'bearish';
  }
  return 'neutral';
}

/// v3.20: 计算两个日期之间的交易日数（跳过周末 + 法定节假日）。
/// 短线跟踪的"5/10/20日"指交易日而非自然日，用自然日会导致里程碑提前触发、口径失真。
/// v3.19→v3.20: 接入 TradingCalendar 节假日表，修复长假期间提前触发问题。
int tradingDaysBetween(DateTime start, DateTime end) {
  if (!end.isAfter(start)) return 0;
  int count = 0;
  // 从 signal 的次日开始计，得到"自信号起经过的交易日数"
  DateTime cursor =
      DateTime(start.year, start.month, start.day).add(const Duration(days: 1));
  final last = DateTime(end.year, end.month, end.day);
  while (cursor.isBefore(last) || cursor.isAtSameMomentAs(last)) {
    if (TradingCalendar.isTradingDay(cursor)) {
      count++;
    }
    cursor = cursor.add(const Duration(days: 1));
  }
  return count;
}

Map<String, double>? _decodeDimensionScores(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return decoded.map((key, value) {
      if (value is num) return MapEntry(key.toString(), value.toDouble());
      return MapEntry(key.toString(), double.tryParse(value.toString()) ?? 0.0);
    });
  } catch (e) {
    debugPrint('RecommendationSnapshot.dimensionScores decode failed: $e');
    return null;
  }
}

String _encodeDimensionScores(Map<String, double>? scores) {
  if (scores == null || scores.isEmpty) return '';
  return jsonEncode(scores);
}

/// 推荐收益追踪器
/// 记录推荐信号快照并追踪实际收益
class RecommendationTracker {
  static final RecommendationTracker _instance = RecommendationTracker._();
  factory RecommendationTracker() => _instance;
  RecommendationTracker._();

  final _dbService = DatabaseService();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await _dbService.clearOldRecommendations(days: 90);
    _initialized = true;
  }

  /// 记录一个新的推荐快照
  /// 当综合评分 >= 6 (谨慎买入及以上) 时触发
  Future<RecommendationSnapshot?> track(AnalysisResult analysis) async {
    if (!_initialized) await init();

    final quote = analysis.quote;
    if (quote == null || analysis.score < 6) return null;

    // 检查该股票是否已有活跃推荐
    final existing = await _dbService.getRecommendationByCode(quote.code);
    if (existing != null) {
      // 已有活跃推荐，不重复记录
      return null;
    }

    // 获取概念标签
    String conceptTags = '';
    try {
      conceptTags = ConceptTagProvider.instance.getConceptSummary(quote.code);
    } catch (e) {
      debugPrint('RecommendationTracker.track: $e');
    }

    // 获取主力策略名称
    String strategy = '';
    final activeStrategies = [
      ...analysis.shortTermStrategies
          .where((s) => s.isActive)
          .map((s) => s.name),
      ...analysis.longTermStrategies
          .where((s) => s.isActive)
          .map((s) => s.name),
    ];
    if (activeStrategies.isNotEmpty) {
      strategy = activeStrategies.take(3).join(',');
    }

    final snapshot = RecommendationSnapshot(
      code: quote.code,
      name: quote.name,
      signalPrice: quote.price,
      signalDate: DateTime.now(),
      marketStructure: analysis.marketStructure != null
          ? MarketStructureAnalyzer.getLabel(
              analysis.marketStructure!.structure)
          : '',
      strategy: strategy,
      conceptTags: conceptTags,
      dimensionScores: analysis.dimensionScores,
      score: analysis.score.toDouble(),
      direction: directionOf(analysis.recommendation),
    );

    await _dbService.insertRecommendationSnapshot(snapshot.toMap());
    return snapshot;
  }

  /// 批量记录推荐快照（用于探索引擎批量写入）
  /// 一次性获取所有活跃推荐 code 集合，过滤已存在的，事务内批量插入
  Future<List<RecommendationSnapshot>> trackBatch(
      List<AnalysisResult> analyses) async {
    if (!_initialized) await init();

    // 一次性获取所有活跃推荐 code 集合
    final activeCodes = await _dbService.getActiveRecommendationCodes();

    final newSnapshots = <RecommendationSnapshot>[];
    for (final analysis in analyses) {
      final quote = analysis.quote;
      if (quote == null || analysis.score < 6) continue;
      // 已有活跃推荐，跳过
      if (activeCodes.contains(quote.code)) continue;

      // 获取概念标签
      String conceptTags = '';
      try {
        conceptTags = ConceptTagProvider.instance.getConceptSummary(quote.code);
      } catch (e) {
        debugPrint('RecommendationTracker.trackBatch: $e');
      }

      // 获取主力策略名称
      String strategy = '';
      final activeStrategies = [
        ...analysis.shortTermStrategies
            .where((s) => s.isActive)
            .map((s) => s.name),
        ...analysis.longTermStrategies
            .where((s) => s.isActive)
            .map((s) => s.name),
      ];
      if (activeStrategies.isNotEmpty) {
        strategy = activeStrategies.take(3).join(',');
      }

      final snapshot = RecommendationSnapshot(
        code: quote.code,
        name: quote.name,
        signalPrice: quote.price,
        signalDate: DateTime.now(),
        marketStructure: analysis.marketStructure != null
            ? MarketStructureAnalyzer.getLabel(
                analysis.marketStructure!.structure)
            : '',
        strategy: strategy,
        conceptTags: conceptTags,
        dimensionScores: analysis.dimensionScores,
        score: analysis.score.toDouble(),
        direction: directionOf(analysis.recommendation),
      );
      newSnapshots.add(snapshot);
      // 标记为已存在，防止批次内重复添加
      activeCodes.add(quote.code);
    }

    if (newSnapshots.isEmpty) return [];

    // 事务内批量插入
    final db = await _dbService.database;
    await db.transaction((txn) async {
      for (final snapshot in newSnapshots) {
        await txn.insert('recommendation_tracking', snapshot.toMap());
      }
    });

    return newSnapshots;
  }

  /// 更新历史推荐的收益率
  /// 计算从信号价到当前价的N日收益
  Future<void> updateReturns(Map<String, double> pricesByCode) async {
    if (!_initialized) await init();

    final db = await _dbService.database;
    final recent = await db.query('recommendation_tracking',
        where: 'is_closed = 0 AND day20_return IS NULL',
        orderBy: 'signal_date DESC',
        limit: 50);

    // 整个 for 循环用事务包裹，避免每次 update 获取新连接、提升并发性能
    await db.transaction((txn) async {
      for (final row in recent) {
        final code = row['code'] as String;
        final signalPrice = (row['signal_price'] as num).toDouble();
        final signalDate =
            DateTime.fromMillisecondsSinceEpoch(row['signal_date'] as int);
        final id = row['id'] as int;
        final now = DateTime.now();
        // 用交易日替代自然日，确保"5/10/20日"与短线交易口径一致（fix 1.14）
        final tradingDaysSince = tradingDaysBetween(signalDate, now);

        final currentPrice = pricesByCode[code];
        if (currentPrice == null || currentPrice <= 0) continue;

        final returnPct = (currentPrice - signalPrice) / signalPrice * 100;
        final nowMs = now.millisecondsSinceEpoch;

        // 更新对应天数的收益 (独立if确保不会漏掉前序里程碑)
        if (tradingDaysSince >= 5 && row['day5_return'] == null) {
          await txn.update(
              'recommendation_tracking',
              {
                'day5_price': currentPrice,
                'day5_return': returnPct,
                'last_checked_date': nowMs
              },
              where: 'id = ?',
              whereArgs: [id]);
        }
        if (tradingDaysSince >= 10 && row['day10_return'] == null) {
          await txn.update(
              'recommendation_tracking',
              {
                'day10_price': currentPrice,
                'day10_return': returnPct,
                'last_checked_date': nowMs
              },
              where: 'id = ?',
              whereArgs: [id]);
        }
        if (tradingDaysSince >= 20 && row['day20_return'] == null) {
          final name = row['name'] as String? ?? '';
          final strategy = row['strategy'] as String? ?? '';

          await txn.update(
              'recommendation_tracking',
              {
                'day20_price': currentPrice,
                'day20_return': returnPct,
                'last_checked_date': nowMs
              },
              where: 'id = ?',
              whereArgs: [id]);

          _generateReflectionAsync(
            id: id,
            code: code,
            name: name,
            signalPrice: signalPrice,
            signalDate: signalDate,
            realizedReturn: returnPct,
            originalRecommendation: strategy,
          );

          await txn.update('recommendation_tracking', {'is_closed': 1},
              where: 'id = ?', whereArgs: [id]);
        }
      }
    });
  }

  /// 获取某只股票的最新追踪收益
  Future<Map<String, double>> getReturns(String code) async {
    final existing = await _dbService.getRecommendationByCode(code);
    if (existing == null) return {};

    return {
      'day5': (existing['day5_return'] as num?)?.toDouble() ?? 0,
      'day10': (existing['day10_return'] as num?)?.toDouble() ?? 0,
      'day20': (existing['day20_return'] as num?)?.toDouble() ?? 0,
    };
  }

  /// 获取历史决策反思，注入下次分析
  /// 返回该股票的最近3条已关闭的推荐记录及其反思
  Future<List<Map<String, dynamic>>> getHistoricalReflections(
      String code) async {
    if (!_initialized) await init();

    final db = await _dbService.database;
    final rows = await db.query(
      'recommendation_tracking',
      columns: [
        'signal_date',
        'signal_price',
        'strategy',
        'day20_return',
        'alpha_vs_market',
        'reflection'
      ],
      where: 'code = ? AND is_closed = 1 AND day20_return IS NOT NULL',
      orderBy: 'signal_date DESC',
      limit: 3,
    );

    final reflections = <Map<String, dynamic>>[];
    for (final row in rows) {
      final ret = <String, dynamic>{
        'signal_date':
            DateTime.fromMillisecondsSinceEpoch(row['signal_date'] as int),
        'signal_price': (row['signal_price'] as num).toDouble(),
        'strategy': row['strategy'] as String? ?? '',
        'day20_return': (row['day20_return'] as num).toDouble(),
        'alpha_vs_market': (row['alpha_vs_market'] as num?)?.toDouble() ?? 0,
        'reflection': row['reflection'] as String? ?? '',
      };
      reflections.add(ret);
    }
    return reflections;
  }

  /// 存储AI生成的反思
  Future<void> saveReflection(int snapshotId, String reflection) async {
    if (!_initialized) await init();

    final db = await _dbService.database;
    await db.update(
      'recommendation_tracking',
      {'reflection': reflection},
      where: 'id = ?',
      whereArgs: [snapshotId],
    );
  }

  /// v3.2: 用户反馈 — 用户对推荐结果的评价
  /// [feedback] 值为 'helpful' / 'not_helpful'
  Future<void> submitFeedback(int snapshotId, String feedback) async {
    if (!_initialized) await init();
    await _dbService.updateRecommendationFeedback(snapshotId, feedback);
  }

  /// v3.2: 获取反馈统计
  Future<Map<String, int>> getFeedbackStats() async {
    if (!_initialized) await init();
    return _dbService.getFeedbackStats();
  }

  /// 计算相对大盘Alpha
  /// marketReturn: 同期大盘收益率（如沪深300）
  Future<void> saveAlpha(
      int snapshotId, double marketReturn, double stockReturn) async {
    if (!_initialized) await init();

    final alpha = stockReturn - marketReturn;
    final db = await _dbService.database;
    await db.update(
      'recommendation_tracking',
      {'alpha_vs_market': alpha},
      where: 'id = ?',
      whereArgs: [snapshotId],
    );
  }

  /// 生成规则引擎反思（无需LLM）
  /// 根据实际收益与预期的偏差生成反思总结
  String generateRuleBasedReflection(
    RecommendationSnapshot snapshot,
    double marketReturn,
  ) {
    final stockReturn = snapshot.day20Return ?? 0;
    final alpha = stockReturn - marketReturn;
    final signalDate = snapshot.signalDate;

    final buf = StringBuffer();
    buf.write('【${snapshot.name}(${snapshot.code})】');
    buf.write(
        '信号日期: ${signalDate.year}-${signalDate.month.toString().padLeft(2, '0')}-${signalDate.day.toString().padLeft(2, '0')}');
    buf.write(
        ' | 策略: ${snapshot.strategy.isNotEmpty ? snapshot.strategy : '综合评分'}');
    buf.write(' | 信号价: ${snapshot.signalPrice.toStringAsFixed(2)}');

    if (stockReturn > 5) {
      buf.write(' | ✅ 盈利${stockReturn.toStringAsFixed(1)}%');
      if (alpha > 2) buf.write('(跑赢大盘${alpha.toStringAsFixed(1)}%)');
      buf.write(' | 反思: 技术面信号准确，策略有效');
    } else if (stockReturn > 0) {
      buf.write(' | 🟡 微利${stockReturn.toStringAsFixed(1)}%');
      if (alpha < -2) buf.write('(跑输大盘${alpha.abs().toStringAsFixed(1)}%)');
      buf.write(' | 反思: 小幅盈利，需关注大盘环境影响');
    } else if (stockReturn > -5) {
      buf.write(' | 🟡 微亏${stockReturn.abs().toStringAsFixed(1)}%');
      buf.write(' | 反思: 小幅亏损，策略信号可靠性一般');
    } else {
      buf.write(' | ❌ 亏损${stockReturn.abs().toStringAsFixed(1)}%');
      buf.write(' | 反思: 信号失效，需检查市场结构和策略条件');
    }

    return buf.toString();
  }

  Future<List<Map<String, dynamic>>> getHistoricalRecommendationsWithScore(
      String code) async {
    if (!_initialized) await init();

    final db = await _dbService.database;
    final rows = await db.query(
      'recommendation_tracking',
      columns: [
        'signal_date',
        'signal_price',
        'day5_return',
        'dimension_scores_json',
      ],
      where: 'code = ? AND day5_return IS NOT NULL',
      orderBy: 'signal_date DESC',
      limit: 20,
    );

    final results = <Map<String, dynamic>>[];
    for (final row in rows) {
      final dimJson = row['dimension_scores_json'] as String?;
      int score = 0;
      if (dimJson != null && dimJson.isNotEmpty) {
        try {
          final dims = jsonDecode(dimJson) as Map<String, dynamic>;
          final total = dims.values
              .whereType<double>()
              .fold(0.0, (a, b) => a + b);
          score = (total / dims.length).round().clamp(1, 10);
        } catch (_) {
          score = 0;
        }
      }

      results.add({
        'score': score,
        'day5_return': (row['day5_return'] as num?)?.toDouble() ?? 0,
      });
    }
    return results;
  }

  /// 异步生成AI反思（决策反馈闭环）
  /// v2.54: 当20日追踪完成时调用，生成反思并保存到数据库
  void _generateReflectionAsync({
    required int id,
    required String code,
    required String name,
    required double signalPrice,
    required DateTime signalDate,
    required double realizedReturn,
    required String originalRecommendation,
  }) {
    Future(() async {
      try {
        String reflection;
        if (AIConfig.enableAIEnhancement &&
            AILayerProvider.instance.isAvailable) {
          reflection = await AILayerProvider.instance.generateReflection(
            stockCode: code,
            stockName: name,
            signalPrice: signalPrice,
            signalDate: signalDate,
            realizedReturn: realizedReturn,
            alphaVsMarket: 0,
            originalRecommendation: originalRecommendation.isNotEmpty
                ? originalRecommendation
                : '综合评分',
          );
        } else {
          reflection = generateRuleBasedReflection(
            RecommendationSnapshot(
              id: id,
              code: code,
              name: name,
              signalPrice: signalPrice,
              signalDate: signalDate,
              day20Return: realizedReturn,
              strategy: originalRecommendation,
            ),
            0,
          );
        }

        if (reflection.isNotEmpty) {
          await saveReflection(id, reflection);
          debugPrint('[RecommendationTracker] 反思已保存: $code');
        }
      } catch (e) {
        debugPrint('[RecommendationTracker] 生成反思失败: $e');
      }
    }).catchError((e) {
      debugPrint('[RecommendationTracker] 反思异步任务失败: $e');
    });
  }
}
