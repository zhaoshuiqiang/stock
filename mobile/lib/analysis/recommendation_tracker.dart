import 'package:flutter/foundation.dart';
import '../models/stock_models.dart';
import '../storage/database_service.dart';
import '../data/concept_tag_provider.dart';
import 'market_structure_analyzer.dart';

/// 推荐快照 - 用于追踪推荐信号的实际表现
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
  });

  factory RecommendationSnapshot.fromMap(Map<String, dynamic> map) {
    return RecommendationSnapshot(
      id: map['id'] as int?,
      code: map['code'] as String,
      name: map['name'] as String? ?? '',
      signalPrice: (map['signal_price'] as num).toDouble(),
      signalDate: DateTime.fromMillisecondsSinceEpoch(map['signal_date'] as int),
      marketStructure: map['market_structure'] as String? ?? '',
      strategy: map['strategy'] as String? ?? '',
      conceptTags: map['concept_tags'] as String? ?? '',
      day5Return: (map['day5_return'] as num?)?.toDouble(),
      day10Return: (map['day10_return'] as num?)?.toDouble(),
      day20Return: (map['day20_return'] as num?)?.toDouble(),
      day20Price: (map['day20_price'] as num?)?.toDouble(),
      isClosed: (map['is_closed'] as int?) == 1,
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
    };
  }
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
    } catch (e) { debugPrint('RecommendationTracker.track: $e'); }

    // 获取主力策略名称
    String strategy = '';
    final activeStrategies = [
      ...analysis.shortTermStrategies.where((s) => s.isActive).map((s) => s.name),
      ...analysis.longTermStrategies.where((s) => s.isActive).map((s) => s.name),
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
          ? MarketStructureAnalyzer.getLabel(analysis.marketStructure!.structure)
          : '',
      strategy: strategy,
      conceptTags: conceptTags,
    );

    await _dbService.insertRecommendationSnapshot(snapshot.toMap());
    return snapshot;
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

    for (final row in recent) {
      final code = row['code'] as String;
      final signalPrice = (row['signal_price'] as num).toDouble();
      final signalDate = DateTime.fromMillisecondsSinceEpoch(row['signal_date'] as int);
      final id = row['id'] as int;
      final now = DateTime.now();
      final daysSince = now.difference(signalDate).inDays;

      final currentPrice = pricesByCode[code];
      if (currentPrice == null || currentPrice <= 0) continue;

      final returnPct = (currentPrice - signalPrice) / signalPrice * 100;

      // 更新对应天数的收益 (独立if确保不会漏掉前序里程碑)
      if (daysSince >= 5 && row['day5_return'] == null) {
        await _dbService.updateRecommendationReturn(id, 5, currentPrice, returnPct);
      }
      if (daysSince >= 10 && row['day10_return'] == null) {
        await _dbService.updateRecommendationReturn(id, 10, currentPrice, returnPct);
      }
      if (daysSince >= 20 && row['day20_return'] == null) {
        await _dbService.updateRecommendationReturn(id, 20, currentPrice, returnPct);
        await _dbService.closeRecommendation(id); // 20日追踪完成
      }
    }
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
}
