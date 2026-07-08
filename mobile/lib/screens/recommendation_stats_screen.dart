import 'package:flutter/material.dart';
import '../analysis/recommendation_tracker.dart';
import '../analysis/weight_optimizer.dart';

/// 推荐命中率统计页
///
/// 展示推荐系统的历史表现：总推荐数、命中率、平均收益、Alpha分布、按策略分组胜率。
/// 数据源：recommendation_tracking 表中已关闭（day20_return不为空）的推荐记录。
class RecommendationStatsScreen extends StatefulWidget {
  const RecommendationStatsScreen({super.key});

  @override
  State<RecommendationStatsScreen> createState() =>
      _RecommendationStatsScreenState();
}

class _RecommendationStatsScreenState extends State<RecommendationStatsScreen> {
  final RecommendationTracker _tracker = RecommendationTracker();
  final WeightOptimizer _weightOptimizer = WeightOptimizer();
  List<Map<String, dynamic>> _allRecords = [];
  List<Map<String, dynamic>> _dimensionReport = [];
  bool _isLoading = true;
  int _periodDays = 0; // 0=全部, 30/60/90

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final recordsFuture = _tracker.getMarketWideReflections(limit: 500);
      final reportFuture = _loadDimensionReport();
      final records = await recordsFuture;
      final dimensionReport = await reportFuture;
      if (!mounted) return;
      setState(() {
        _allRecords = records;
        _dimensionReport = dimensionReport;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      debugPrint('[推荐统计] 加载失败: $e');
    }
  }

  Future<List<Map<String, dynamic>>> _loadDimensionReport() async {
    try {
      return _weightOptimizer.getDimensionPerformanceReport(minSamples: 30);
    } catch (e) {
      debugPrint('[推荐统计] 维度表现加载失败: $e');
      return [];
    }
  }

  List<Map<String, dynamic>> get _filteredRecords {
    if (_periodDays == 0) return _allRecords;
    final cutoff = DateTime.now().subtract(Duration(days: _periodDays));
    return _allRecords.where((r) {
      final date = r['signal_date'] as DateTime;
      return date.isAfter(cutoff);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: const Text('推荐效果统计'),
        backgroundColor: const Color(0xFF161B22),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF58A6FF)))
          : _allRecords.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  color: const Color(0xFF58A6FF),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildPeriodFilter(),
                      const SizedBox(height: 16),
                      _buildSummaryCards(),
                      const SizedBox(height: 16),
                      _buildDimensionPerformance(),
                      const SizedBox(height: 16),
                      _buildStrategyStats(),
                      const SizedBox(height: 16),
                      _buildRecentRecords(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.insights_outlined,
              size: 64, color: Color(0xFF30363D)),
          const SizedBox(height: 16),
          const Text(
            '暂无推荐追踪数据',
            style: TextStyle(color: Color(0xFF8B949E), fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            '推荐系统会在评分≥6时记录追踪\n20交易日后自动计算命中率',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: Color(0xFF484F58), fontSize: 12, height: 1.6),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadData,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF58A6FF),
              foregroundColor: Colors.white,
            ),
            child: const Text('刷新'),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodFilter() {
    final periods = [
      {'label': '全部', 'days': 0},
      {'label': '近30天', 'days': 30},
      {'label': '近60天', 'days': 60},
      {'label': '近90天', 'days': 90},
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: periods.map((p) {
          final days = p['days'] as int;
          final selected = _periodDays == days;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(p['label'] as String),
              selected: selected,
              selectedColor: const Color(0xFF58A6FF),
              labelStyle: TextStyle(
                color: selected ? Colors.white : const Color(0xFF8B949E),
                fontSize: 13,
              ),
              onSelected: (_) {
                setState(() => _periodDays = days);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final records = _filteredRecords;
    if (records.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        child: const Center(
          child: Text('该时间段内无数据', style: TextStyle(color: Color(0xFF8B949E))),
        ),
      );
    }

    final total = records.length;
    final wins = records.where((r) => (r['day20_return'] as double) > 0).length;
    final hitRate = total > 0 ? wins / total * 100 : 0.0;
    final avgReturn = records
            .map((r) => r['day20_return'] as double)
            .reduce((a, b) => a + b) /
        total;
    final avgAlpha = records
            .map((r) => (r['alpha_vs_market'] as num).toDouble())
            .reduce((a, b) => a + b) /
        total;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.2,
      children: [
        _buildStatCard('总推荐数', '$total', '只', const Color(0xFF58A6FF)),
        _buildStatCard(
            '命中率',
            hitRate.toStringAsFixed(1),
            '%',
            hitRate >= 60
                ? const Color(0xFF26a69a)
                : hitRate >= 40
                    ? const Color(0xFFff9800)
                    : const Color(0xFFef5350)),
        _buildStatCard(
            '平均收益',
            avgReturn >= 0
                ? '+${avgReturn.toStringAsFixed(2)}'
                : avgReturn.toStringAsFixed(2),
            '%',
            avgReturn >= 0 ? const Color(0xFFE74C3C) : const Color(0xFF2ECC71)),
        _buildStatCard(
            '平均Alpha',
            avgAlpha >= 0
                ? '+${avgAlpha.toStringAsFixed(2)}'
                : avgAlpha.toStringAsFixed(2),
            '%',
            avgAlpha >= 0 ? const Color(0xFFE74C3C) : const Color(0xFF2ECC71)),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, String unit, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                    color: color, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 2),
              Text(unit,
                  style:
                      const TextStyle(color: Color(0xFF8B949E), fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDimensionPerformance() {
    if (_dimensionReport.isEmpty) return const SizedBox.shrink();

    final enoughCount = _dimensionReport
        .where((r) => (r['has_enough_data'] as bool?) ?? false)
        .length;
    final hasAnyData = _dimensionReport
        .any((r) => ((r['sample_count'] as num?)?.toInt() ?? 0) > 0);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '维度表现 / 建议权重',
            style: TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            enoughCount > 0
                ? '基于20日闭环收益与时间衰减计算，当前有 $enoughCount 个维度样本充足；建议权重仅供调参参考。'
                : hasAnyData
                    ? '历史样本仍不足，暂沿用默认权重；继续积累推荐闭环后再评估调权。'
                    : '暂无维度评分样本，后续推荐记录会自动补充 dimension_scores_json。',
            style: const TextStyle(
                color: Color(0xFF8B949E), fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 12),
          ..._dimensionReport.map(_buildDimensionRow),
        ],
      ),
    );
  }

  Widget _buildDimensionRow(Map<String, dynamic> row) {
    final name = row['name'] as String? ?? '';
    final sampleCount = ((row['sample_count'] as num?)?.toInt() ?? 0);
    final hasEnoughData = (row['has_enough_data'] as bool?) ?? false;
    final hitRate = ((row['hit_rate'] as num?)?.toDouble() ?? 0) * 100;
    final avgReturn = (row['avg_return'] as num?)?.toDouble() ?? 0;
    final defaultWeight = (row['default_weight'] as num?)?.toDouble() ?? 0;
    final currentWeight =
        (row['current_weight'] as num?)?.toDouble() ?? defaultWeight;
    final deltaPct = (currentWeight - defaultWeight) * 100;

    final hitColor = !hasEnoughData
        ? const Color(0xFF8B949E)
        : hitRate >= 60
            ? const Color(0xFF26a69a)
            : hitRate >= 45
                ? const Color(0xFFff9800)
                : const Color(0xFFef5350);
    final returnColor =
        avgReturn >= 0 ? const Color(0xFFE74C3C) : const Color(0xFF2ECC71);
    final deltaText = !hasEnoughData || deltaPct.abs() < 0.05
        ? '默认'
        : '${deltaPct > 0 ? '+' : ''}${deltaPct.toStringAsFixed(1)}pp';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF30363D), width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  name,
                  style: const TextStyle(
                      color: Color(0xFFF0F6FC),
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '样本 $sampleCount',
                style: TextStyle(
                  color: hasEnoughData
                      ? const Color(0xFF58A6FF)
                      : const Color(0xFF8B949E),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildDimensionMetric(
                  '命中率',
                  hasEnoughData ? '${hitRate.toStringAsFixed(0)}%' : '--',
                  hitColor,
                ),
              ),
              Expanded(
                child: _buildDimensionMetric(
                  '平均收益',
                  hasEnoughData
                      ? '${avgReturn >= 0 ? '+' : ''}${avgReturn.toStringAsFixed(1)}%'
                      : '--',
                  returnColor,
                ),
              ),
              Expanded(
                child: _buildDimensionMetric(
                  '建议权重',
                  '${(currentWeight * 100).toStringAsFixed(1)}%',
                  const Color(0xFFF0F6FC),
                  helper: deltaText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDimensionMetric(String label, String value, Color color,
      {String? helper}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Color(0xFF8B949E), fontSize: 10)),
        const SizedBox(height: 3),
        Row(
          children: [
            Text(
              value,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            if (helper != null) ...[
              const SizedBox(width: 4),
              Text(helper,
                  style:
                      const TextStyle(color: Color(0xFF8B949E), fontSize: 10)),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildStrategyStats() {
    final records = _filteredRecords;
    if (records.isEmpty) return const SizedBox.shrink();

    // 按策略分组统计胜率
    final strategyStats = <String, List<double>>{};
    for (final r in records) {
      final strategy = (r['strategy'] as String).isNotEmpty
          ? r['strategy'] as String
          : '综合评分';
      // 策略字段是逗号分隔的，拆分统计
      final parts = strategy
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (parts.isEmpty) parts.add('综合评分');
      final ret = r['day20_return'] as double;
      for (final p in parts) {
        strategyStats.putIfAbsent(p, () => []);
        strategyStats[p]!.add(ret);
      }
    }

    // 按样本量降序排列，取前10
    final sorted = strategyStats.entries.toList()
      ..sort((a, b) => b.value.length.compareTo(a.value.length));
    final top = sorted.take(10).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '策略胜率排行',
            style: TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...top.map((entry) {
            final name = entry.key;
            final returns = entry.value;
            final count = returns.length;
            final wins = returns.where((r) => r > 0).length;
            final winRate = count > 0 ? wins / count * 100 : 0.0;
            final avgRet = returns.reduce((a, b) => a + b) / count;
            final color = winRate >= 60
                ? const Color(0xFF26a69a)
                : winRate >= 40
                    ? const Color(0xFFff9800)
                    : const Color(0xFFef5350);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(name,
                        style: const TextStyle(
                            color: Color(0xFFF0F6FC), fontSize: 13)),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text('$count次',
                        style: const TextStyle(
                            color: Color(0xFF8B949E), fontSize: 12),
                        textAlign: TextAlign.center),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      '${winRate.toStringAsFixed(0)}%',
                      style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: Text(
                      '${avgRet >= 0 ? '+' : ''}${avgRet.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: avgRet >= 0
                            ? const Color(0xFFE74C3C)
                            : const Color(0xFF2ECC71),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRecentRecords() {
    final records = _filteredRecords.take(20).toList();
    if (records.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '近期推荐记录',
            style: TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...records.map((r) {
            final name = r['name'] as String;
            final code = r['code'] as String;
            final date = r['signal_date'] as DateTime;
            final ret = r['day20_return'] as double;
            final alpha = (r['alpha_vs_market'] as num).toDouble();
            final reflection = r['reflection'] as String;
            final isWin = ret > 0;

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color:
                      isWin ? const Color(0xFF26a69a) : const Color(0xFFef5350),
                  width: 0.5,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(width: 6),
                      Text(code,
                          style: const TextStyle(
                              color: Color(0xFF8B949E), fontSize: 11)),
                      const Spacer(),
                      Text(
                        '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                        style: const TextStyle(
                            color: Color(0xFF484F58), fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '20日收益: ${ret >= 0 ? '+' : ''}${ret.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: isWin
                              ? const Color(0xFFE74C3C)
                              : const Color(0xFF2ECC71),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Alpha: ${alpha >= 0 ? '+' : ''}${alpha.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: alpha >= 0
                              ? const Color(0xFFE74C3C)
                              : const Color(0xFF2ECC71),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  if (reflection.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      reflection,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFF8B949E), fontSize: 11, height: 1.4),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
