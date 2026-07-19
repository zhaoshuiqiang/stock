import 'dart:convert';
import 'dart:math' as math;
import '../storage/database_service.dart';

/// 动态权重优化器
///
/// 基于历史推荐命中率数据，自动调整7维评分的权重分配。
/// 核心逻辑：表现好的维度权重上调，表现差的维度权重下调。
/// 数据来源：recommendation_tracking 表中已关闭的推荐记录及其 dimension_scores_json。
// NOTE (v4.3 / P2.4): Superseded by DirectionalWeightOptimizer, which targets the
// live 5-dim direction engine. This 7-dim optimizer is retained ONLY for the
// recommendation_stats_screen display and is NOT wired into live scoring. Do not
// use it in new code.
class WeightOptimizer {
  static final WeightOptimizer _instance = WeightOptimizer._();
  factory WeightOptimizer() => _instance;
  WeightOptimizer._();

  final DatabaseService _dbService = DatabaseService();

  /// 默认权重（与 ComprehensiveScorer 一致）
  static const Map<String, double> kDefaultWeights = {
    '技术面': 0.33,
    '资金面': 0.18,
    '实时行情': 0.16,
    '共振': 0.12,
    '情绪': 0.10,
    '基本面': 0.07,
    '结构': 0.04,
  };

  /// 维度名称映射（处理不同数据源的命名差异）
  static const Map<String, String> kDimensionAliases = {
    '技术': '技术面',
    '资金': '资金面',
    '实时': '实时行情',
    '资金面评分': '资金面',
    '技术面评分': '技术面',
  };

  /// 获取优化后的权重（基于历史命中率）
  ///
  /// [minSamples] - 最小样本数，低于此值返回默认权重（防止数据不足时过度调整）
  /// [maxAdjustment] - 单次调整幅度上限（0.0-0.15，防止权重波动过大）
  /// [decayFactor] - 时间衰减因子（0.0-1.0，旧数据权重较低）
  Future<Map<String, double>> getOptimizedWeights({
    int minSamples = 50,
    double maxAdjustment = 0.08,
    double decayFactor = 0.95,
  }) async {
    final stats = await _calculateDimensionStats(
      minSamples: minSamples,
      decayFactor: decayFactor,
    );
    if (stats.isEmpty) return Map.from(kDefaultWeights);
    final maxSampleCount = stats.values
        .map((stat) => stat['count'] as int)
        .fold<int>(0, (max, count) => count > max ? count : max);
    if (maxSampleCount < minSamples) return Map.from(kDefaultWeights);

    final adjusted = <String, double>{};

    // 计算每个维度的调整系数
    for (final dim in kDefaultWeights.keys) {
      final stat = stats[dim];
      if (stat == null) {
        adjusted[dim] = kDefaultWeights[dim]!;
        continue;
      }

      // 命中率偏离基准（50%）的程度决定调整方向和幅度
      final hitRate = stat['hit_rate'] as double;
      final sampleCount = stat['count'] as int;

      // 调整幅度与样本量正相关，与命中率偏离幅度正相关
      final deviation = (hitRate - 0.5).abs();
      final confidence = _min(1.0, sampleCount / minSamples);
      final rawAdjustment = deviation * confidence * 2;

      // 应用上限
      var adjustment = rawAdjustment.clamp(-maxAdjustment, maxAdjustment);

      // 命中率高于50% → 上调权重；低于50% → 下调权重
      if (hitRate < 0.5) adjustment = -adjustment.abs();

      adjusted[dim] = (kDefaultWeights[dim]! + adjustment).clamp(0.02, 0.5);
    }

    // 归一化：确保所有权重总和为1.0
    final normalized = _normalizeWeights(adjusted);
    return normalized;
  }

  /// 获取每个维度的命中率统计
  Future<Map<String, Map<String, dynamic>>> _calculateDimensionStats({
    int minSamples = 50,
    double decayFactor = 0.95,
  }) async {
    final db = await _dbService.database;
    final rows = await db.query(
      'recommendation_tracking',
      columns: ['day20_return', 'dimension_scores_json', 'signal_date'],
      where:
          'is_closed = 1 AND day20_return IS NOT NULL AND dimension_scores_json IS NOT NULL AND dimension_scores_json != ""',
      orderBy: 'signal_date DESC',
      limit: 500,
    );

    final dimStats = <String, Map<String, dynamic>>{};
    for (final dim in kDefaultWeights.keys) {
      dimStats[dim] = {
        'total': 0,
        'wins': 0,
        'count': 0,
        'weighted_total': 0.0,
        'weighted_wins': 0.0,
        'hit_rate': 0.0,
        'avg_dim_score': 0.0,
        'avg_return': 0.0,
      };
    }

    final now = DateTime.now();

    for (final row in rows) {
      final returnPct = (row['day20_return'] as num).toDouble();
      final isWin = returnPct > 0;
      final signalDate =
          DateTime.fromMillisecondsSinceEpoch(row['signal_date'] as int);
      final daysAgo = now.difference(signalDate).inDays;
      final weight = _timeWeight(daysAgo, decayFactor);

      try {
        final dimJson = row['dimension_scores_json'] as String?;
        if (dimJson == null || dimJson.isEmpty) continue;
        final dimScores = jsonDecode(dimJson) as Map<String, dynamic>;

        for (final entry in dimScores.entries) {
          var dimName = entry.key;
          // 映射别名
          if (kDimensionAliases.containsKey(dimName)) {
            dimName = kDimensionAliases[dimName]!;
          }
          if (!dimStats.containsKey(dimName)) continue;

          final dimScore = (entry.value as num).toDouble();
          if (dimScore <= 0) continue;

          final stat = dimStats[dimName]!;
          stat['total'] = (stat['total'] as int) + 1;
          if (isWin) stat['wins'] = (stat['wins'] as int) + 1;
          stat['count'] = (stat['count'] as int) + 1;
          stat['weighted_total'] = (stat['weighted_total'] as double) + weight;
          if (isWin) {
            stat['weighted_wins'] = (stat['weighted_wins'] as double) + weight;
          }
          stat['avg_dim_score'] =
              (stat['avg_dim_score'] as double) + dimScore * weight;
          stat['avg_return'] =
              (stat['avg_return'] as double) + returnPct * weight;
        }
      } catch (e) {
        // 解析失败跳过
        continue;
      }
    }

    // 计算命中率
    for (final dim in kDefaultWeights.keys) {
      final stat = dimStats[dim]!;
      final count = stat['count'] as int;
      if (count > 0) {
        final weightedTotal = stat['weighted_total'] as double;
        if (weightedTotal > 0) {
          stat['hit_rate'] = (stat['weighted_wins'] as double) / weightedTotal;
          stat['avg_dim_score'] =
              (stat['avg_dim_score'] as double) / weightedTotal;
          stat['avg_return'] = (stat['avg_return'] as double) / weightedTotal;
        } else {
          stat['hit_rate'] = (stat['wins'] as int) / count;
          stat['avg_dim_score'] = 0.0;
          stat['avg_return'] = 0.0;
        }
      }
    }

    return dimStats;
  }

  /// 归一化权重，确保总和为1.0
  Map<String, double> _normalizeWeights(Map<String, double> weights) {
    final total = weights.values.reduce((a, b) => a + b);
    if (total <= 0) return Map.from(kDefaultWeights);
    return {
      for (final entry in weights.entries) entry.key: entry.value / total,
    };
  }

  /// 获取维度表现报告（用于UI展示）
  Future<List<Map<String, dynamic>>> getDimensionPerformanceReport({
    int minSamples = 30,
  }) async {
    final stats = await _calculateDimensionStats(minSamples: minSamples);
    final optimizedWeights = stats.isEmpty
        ? Map<String, double>.from(kDefaultWeights)
        : await getOptimizedWeights(minSamples: minSamples);
    final report = <Map<String, dynamic>>[];

    for (final dim in kDefaultWeights.keys) {
      final stat = stats[dim];
      final hasEnoughData = stat != null && stat['count'] >= minSamples;
      report.add({
        'name': dim,
        'default_weight': kDefaultWeights[dim],
        'current_weight':
            hasEnoughData ? optimizedWeights[dim] : kDefaultWeights[dim],
        'hit_rate': stat?['hit_rate'] ?? 0,
        'sample_count': stat?['count'] ?? 0,
        'avg_return': stat?['avg_return'] ?? 0,
        'has_enough_data': hasEnoughData,
      });
    }

    return report;
  }

  /// 重置为默认权重（清除所有优化状态）
  void reset() {
    // 权重优化是纯内存计算，无需持久化状态
    // 调用 getOptimizedWeights 时会重新计算
  }

  /// 辅助函数：取最小值
  double _min(double a, double b) => a < b ? a : b;

  double _timeWeight(int daysAgo, double decayFactor) {
    if (daysAgo <= 0) return 1.0;
    final boundedDecay = decayFactor.clamp(0.0, 1.0).toDouble();
    return math.pow(boundedDecay, daysAgo).toDouble();
  }
}
