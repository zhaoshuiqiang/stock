import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../analysis/indicators.dart';
import '../analysis/signal_engine.dart';
import '../storage/database_service.dart';
import '../analysis/sector_rotation.dart';
import '../analysis/archive_reliability_evaluator.dart';
import '../services/legacy_archive_csv_exporter.dart';

const _kVeryReasonableColor = Color(0xFF4CAF50);
const _kReasonableColor = Colors.orange;
const _kDeviationColor = Color(0xFF26a69a);
const _kVeryDeviationColor = Color(0xFFef5350);

class ReliabilityInfo {
  final String label;
  final String description;
  final Color color;

  const ReliabilityInfo({
    required this.label,
    required this.description,
    required this.color,
  });
}

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => ArchiveScreenState();
}

class ArchiveScreenState extends State<ArchiveScreen>
    with WidgetsBindingObserver {
  final ApiClient _apiClient = ApiClient();
  final DatabaseService _dbService = DatabaseService();
  List<ArchiveRecord> _archives = [];
  bool _isLoading = true;
  final Map<String, QuoteData> _currentQuotes = {};
  Timer? _refreshTimer;
  bool _tabVisible = false;
  String _sortBy = 'time'; // 'time', 'score', 'change'
  bool _sortAscending = false;
  String _filterType = '全部'; // '全部', '看多', '看空', '观望'
  String _filterReliability = '全部'; // '全部', '非常合理', '合理', '偏差', '非常偏差'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadArchives();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _refreshCurrentPrices();
    });
  }

  Future<void> _loadArchives() async {
    try {
      final archives = await _dbService.getArchives();
      if (!mounted) return;
      setState(() {
        _archives = archives;
      });
      // v3.2: 等待行情数据加载完毕再渲染，避免初始状态全部显示"合理"
      await _refreshCurrentPrices();
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('[留档] 加载留档记录失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 判断留档推荐的可靠性等级（4级）
  ///
  /// v3.2 重新设计：基于时间自适应阈值 + 方向性区分
  ///
  /// 核心原则：
  /// 1. 买入/卖出（score≥6/≤3）：强方向推荐，阈值=√(天数/5)*2%，≥阈值=非常合理
  /// 2. 偏多/偏空观望（score=5/4）：弱方向推荐，阈值=基准*1.3倍，≥阈值=非常合理
  /// 3. 纯观望：非方向性，基于绝对波动大小评判
  /// 4. 时间自适：5天→阈值2%，20天→阈值4%，60天→阈值6.9%
  ///
  /// 买入推荐（含谨慎买入）：
  ///   * 非常合理：涨幅 ≥ 时间阈值（方向正确且收益显著）
  ///   * 合理：     涨幅 0% ~ 阈值（方向正确）
  ///   * 偏差：     跌幅 0% ~ 阈值（方向错误，轻微亏损）
  ///   * 非常偏差：跌幅 < -阈值（方向错误，大幅亏损）
  static ReliabilityLevel _getReliabilityLevel(
      ArchiveRecord record, double currentPrice) {
    return ArchiveReliabilityEvaluator.getReliabilityLevel(
        record, currentPrice);
  }

  /// 获取可靠性等级对应的标签、描述和颜色
  static ReliabilityInfo _getReliabilityInfo(ReliabilityLevel level) {
    switch (level) {
      case ReliabilityLevel.veryReasonable:
        return const ReliabilityInfo(
          label: '非常合理',
          description: '推荐方向正确且收益/跌幅达标',
          color: _kVeryReasonableColor,
        );
      case ReliabilityLevel.reasonable:
        return const ReliabilityInfo(
          label: '合理',
          description: '推荐方向正确但收益/跌幅未达标',
          color: _kReasonableColor,
        );
      case ReliabilityLevel.deviation:
        return const ReliabilityInfo(
          label: '偏差',
          description: '推荐方向错误但亏损/涨幅较小',
          color: _kDeviationColor,
        );
      case ReliabilityLevel.veryDeviation:
        return const ReliabilityInfo(
          label: '非常偏差',
          description: '推荐方向错误且亏损/涨幅较大',
          color: _kVeryDeviationColor,
        );
    }
  }

  List<ArchiveRecord> _getFilteredAndSortedArchives() {
    var items = _archives.toList();

    // 筛选：与顶部看多/看空/观望统计使用同一套方向语义。
    if (_filterType != '全部') {
      items = items
          .where((r) =>
              ArchiveReliabilityEvaluator.matchesTypeFilter(r, _filterType))
          .toList();
    }

    // 可靠性筛选（4级）
    if (_filterReliability != '全部') {
      items = items.where((r) {
        final currentQuote = _currentQuotes[r.code];
        final currentPrice = currentQuote?.price ?? 0;
        final level = _getReliabilityLevel(r, currentPrice);
        switch (_filterReliability) {
          case '非常合理':
            return level == ReliabilityLevel.veryReasonable;
          case '合理':
            return level == ReliabilityLevel.reasonable;
          case '偏差':
            return level == ReliabilityLevel.deviation;
          case '非常偏差':
            return level == ReliabilityLevel.veryDeviation;
          default:
            return true;
        }
      }).toList();
    }

    // 排序
    items.sort((a, b) {
      int cmp;
      switch (_sortBy) {
        case 'score':
          cmp = b.score.compareTo(a.score);
          break;
        case 'change':
          final changeA = _currentQuotes[a.code]?.changePct ?? 0;
          final changeB = _currentQuotes[b.code]?.changePct ?? 0;
          cmp = changeB.compareTo(changeA);
          break;
        default:
          cmp = b.archivedAt.compareTo(a.archivedAt);
      }
      return _sortAscending ? -cmp : cmp;
    });

    return items;
  }

  Future<void> _refreshCurrentPrices() async {
    if (_archives.isEmpty) return;
    try {
      final codes =
          _archives.map((r) => _apiClient.addMarketPrefix(r.code)).toList();
      final batchQuotes = await _apiClient.getBatchRealtimeQuotes(codes);
      final quoteMap = <String, QuoteData>{};
      for (final q in batchQuotes) {
        quoteMap[q.code] = q;
      }
      if (!mounted) return;
      setState(() {
        for (final record in _archives) {
          final prefixedCode = _apiClient.addMarketPrefix(record.code);
          final quote = quoteMap[prefixedCode];
          if (quote != null) {
            _currentQuotes[record.code] = quote;
          }
        }
      });
    } catch (e) {
      debugPrint('[留档] 实时行情刷新失败: $e');
    }
  }

  Future<void> _reanalyze(ArchiveRecord record) async {
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()));

    try {
      final prefixedCode = _apiClient.addMarketPrefix(record.code);
      final klines = await _apiClient.getStockHistory(prefixedCode, days: 120);
      final quote = await _apiClient.getRealtimeQuote(prefixedCode);

      if (klines.isEmpty) {
        if (mounted) Navigator.pop(context);
        if (mounted)
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('无法获取数据')));
        return;
      }

      final calculated = calcAllIndicators(klines);

      final sectorName = await _apiClient.getStockSector(prefixedCode);
      final hotSectors = await _apiClient.getHotSectors();
      final sectorData = hotSectors
          .map((s) => SectorData(
                name: s.name,
                code: s.code,
                changePct: s.changePct,
                limitUpCount: s.stockCount,
                mainNetFlow: 0,
              ))
          .toList();
      final sectorRotationResult =
          SectorRotation.analyze(sectorList: sectorData);

      final analysis = generateAnalysis(
        calculated,
        quote,
        sectorName: sectorName,
        sectorAnalysis: sectorRotationResult.topSectors,
      );

      if (mounted) Navigator.pop(context);

      if (mounted) _showReanalysisDialog(record, analysis, quote);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('分析失败: $e')));
    }
  }

  void _showReanalysisDialog(ArchiveRecord record,
      AnalysisResult currentAnalysis, QuoteData? currentQuote) {
    final currentPrice = currentQuote?.price ?? 0;
    final currentChangePct = currentQuote?.changePct ?? 0;
    final priceChange = currentPrice - record.price;
    final priceChangePct =
        record.price > 0 ? (priceChange / record.price * 100) : 0.0;

    String reliability;
    Color reliabilityColor;
    if (currentPrice > 0 &&
        (record.recommendation.contains('买入') ||
            record.recommendation.contains('卖出') ||
            record.recommendation.contains('观望'))) {
      final level = _getReliabilityLevel(record, currentPrice);
      final info = _getReliabilityInfo(level);
      reliability = info.label;
      reliabilityColor = info.color;
    } else {
      reliability = '推荐合理';
      reliabilityColor = Colors.orange;
    }

    showDialog(
        context: context,
        builder: (context) => Dialog(
              backgroundColor: const Color(0xFF0D1117),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${record.name} 重新分析',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    _buildCompareRow('推荐', record.recommendation,
                        currentAnalysis.recommendation),
                    _buildCompareRow(
                        '评分', '${record.score}', '${currentAnalysis.score}'),
                    _buildCompareRow(
                        '风险', record.riskLevel, currentAnalysis.riskLevel),
                    _buildCompareRow('价格', record.price.toStringAsFixed(2),
                        currentPrice.toStringAsFixed(2)),
                    _buildCompareRow(
                        '涨跌幅',
                        '${record.changePct.toStringAsFixed(2)}%',
                        '${currentChangePct.toStringAsFixed(2)}%'),
                    const Divider(color: Colors.white12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('价格变动',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 13)),
                        Text(
                          '${priceChange >= 0 ? '+' : ''}${priceChange.toStringAsFixed(2)} (${priceChangePct >= 0 ? '+' : ''}${priceChangePct.toStringAsFixed(2)}%)',
                          style: TextStyle(
                              color: priceChange >= 0
                                  ? const Color(0xFFef5350)
                                  : const Color(0xFF26a69a),
                              fontSize: 14,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: reliabilityColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: reliabilityColor.withOpacity(0.5)),
                      ),
                      child: Text(reliability,
                          style: TextStyle(
                              color: reliabilityColor,
                              fontSize: 14,
                              fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('关闭')),
                  ],
                ),
              ),
            ));
  }

  Widget _buildCompareRow(String label, String oldValue, String newValue) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 13)),
          Text(oldValue,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const Icon(Icons.arrow_forward, color: Colors.white24, size: 16),
          Text(newValue,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Future<void> _deleteArchive(ArchiveRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0D1117),
        title: const Text('确认删除', style: TextStyle(color: Colors.white)),
        content: Text('确定要删除 ${record.name} 的留档记录吗？',
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true && record.id != null) {
      await _dbService.deleteArchive(record.id!);
      _loadArchives();
    }
  }

  /// 历史口径选择性清理（替代原先的全删二选一）。
  Future<void> _deleteAll() async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0D1117),
        title: const Text('清理留档记录', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('共 ${_archives.length} 条。盘前清理可选范围，避免误删长期参考。',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 12),
            _cleanupOption(context, '删除 30 天前的留档', 'older30'),
            _cleanupOption(context, '删除 90 天前的留档', 'older90'),
            _cleanupOption(context, '清空全部留档（不可恢复）', 'all', danger: true),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('取消')),
        ],
      ),
    );
    if (action == null) return;
    try {
      int n;
      String msg;
      if (action == 'all') {
        await _dbService.deleteAllArchives();
        n = _archives.length;
        msg = '已删除全部留档记录';
      } else {
        n = await _dbService
            .deleteArchivesOlderThanDays(action == 'older30' ? 30 : 90);
        msg = '已删除 $n 条旧留档';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理失败：$e')),
        );
      }
      return;
    }
    _loadArchives();
  }

  Widget _cleanupOption(BuildContext context, String label, String value,
      {bool danger = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SizedBox(
        width: double.infinity,
        child: TextButton(
          style: TextButton.styleFrom(
            alignment: Alignment.centerLeft,
            foregroundColor: danger ? Colors.red : Colors.white70,
          ),
          onPressed: () => Navigator.pop(context, value),
          child: Text(label),
        ),
      ),
    );
  }

  /// 导出留档数据为 CSV 文件并通过系统分享
  Future<void> _exportToCsv() async {
    final legacyRowsForExport = _getFilteredAndSortedArchives();
    if (legacyRowsForExport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前筛选无可导出结果')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final now = DateTime.now();
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(now);
      final csvContent = buildLegacyArchiveCsv(
        records: legacyRowsForExport,
        quoteOf: (code) => _currentQuotes[code],
        now: now,
      );
      final fileName = 'archive_export_$stamp.csv';
      final exportCount = legacyRowsForExport.length;

      // 保存到临时目录（供分享使用）
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$fileName');
      await tempFile.writeAsString(csvContent);

      // v3.2: 同时保存到应用文档目录，确保即使分享失败也能找到文件
      final docDir = await getApplicationDocumentsDirectory();
      final docFile = File('${docDir.path}/$fileName');
      await docFile.writeAsString(csvContent);

      if (!mounted) return;
      Navigator.pop(context); // 关闭 loading

      // 使用 share_plus 分享文件
      try {
        await Share.shareXFiles(
          [XFile(tempFile.path)],
          subject: '留档数据导出 ($stamp)',
        );
      } catch (_) {
        // 分享失败：文件已保存在文档目录，提示用户手动取用
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已导出 $fileName ($exportCount条)'),
            action: SnackBarAction(
              label: '查看路径',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(docFile.path,
                        style: const TextStyle(fontSize: 12)),
                    duration: const Duration(seconds: 8),
                  ),
                );
              },
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // 关闭 loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                '导出失败: ${e.toString().length > 50 ? '${e.toString().substring(0, 50)}...' : e}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_archives.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bookmark_border, size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            const Text('暂无留档记录',
                style: TextStyle(color: Colors.white38, fontSize: 14)),
            const SizedBox(height: 4),
            const Text('在"自选"页面中点击归档按钮保存推荐',
                style: TextStyle(color: Colors.white24, fontSize: 12)),
          ],
        ),
      );
    }

    final filteredArchives = _getFilteredAndSortedArchives();

    // 统计4级可靠性和方向拆分（基于筛选后的结果）
    final reliabilityStats = ArchiveReliabilityEvaluator.calculateStats(
      records: filteredArchives,
      currentPriceOf: (record) => _currentQuotes[record.code]?.price ?? 0,
    );
    final veryReasonableCount = reliabilityStats.veryReasonableCount;
    final reasonableCount = reliabilityStats.reasonableCount;
    final deviationCount = reliabilityStats.deviationCount;
    final veryDeviationCount = reliabilityStats.veryDeviationCount;
    final total = reliabilityStats.total;
    final directionReasonableRate = reliabilityStats.directionReasonableRate;
    final isFiltered = _filterReliability != '全部' || _filterType != '全部';

    final veryReasonablePct = reliabilityStats.veryReasonablePct;
    final reasonablePct = reliabilityStats.reasonablePct;
    final deviationPct = reliabilityStats.deviationPct;
    final veryDeviationPct = reliabilityStats.veryDeviationPct;

    return RefreshIndicator(
      onRefresh: _loadArchives,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: const Text(
                '当前价实时核对会随行情变化，不是固定周期命中率，不能用于评分校准。',
                style:
                    TextStyle(color: Colors.white30, fontSize: 11, height: 1.5),
              ),
            ),
          ),
          // 顶部方向统计卡片（方向合理率 + 拆分指标 + 分段比例条 + 操作按钮）
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  // 第一行：方向合理率 + 总计
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(isFiltered ? '筛选方向合理率' : '方向合理率',
                                    style: TextStyle(
                                        color: isFiltered
                                            ? const Color(0xFF58A6FF)
                                            : Colors.white54,
                                        fontSize: 12)),
                                const SizedBox(height: 2),
                                const Text('实时浮动（随行情变动）',
                                    style: TextStyle(
                                        color: Colors.white30, fontSize: 10)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${directionReasonableRate.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                  color: Colors.orange,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 40, color: Colors.white12),
                      const SizedBox(width: 16),
                      Column(
                        children: [
                          const Text('总计',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 11)),
                          const SizedBox(height: 2),
                          Text('$total',
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildDirectionMetric(
                        '看多',
                        reliabilityStats.bullishHits,
                        reliabilityStats.bullishTotal,
                        reliabilityStats.bullishHitRate,
                        _kVeryReasonableColor,
                      ),
                      const SizedBox(width: 6),
                      _buildDirectionMetric(
                        '看空',
                        reliabilityStats.bearishHits,
                        reliabilityStats.bearishTotal,
                        reliabilityStats.bearishHitRate,
                        _kDeviationColor,
                      ),
                      const SizedBox(width: 6),
                      _buildDirectionMetric(
                        '观望',
                        reliabilityStats.neutralStable,
                        reliabilityStats.neutralTotal,
                        reliabilityStats.neutralStableRate,
                        _kReasonableColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 第三行：分段比例条 + 标签
                  Column(
                    children: [
                      // 分段比例条
                      Container(
                        height: 12,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: Colors.white10,
                        ),
                        child: Row(
                          children: [
                            // 非常合理（绿）
                            Expanded(
                              flex: veryReasonablePct.ceil(),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: const BorderRadius.horizontal(
                                      left: Radius.circular(6)),
                                  color: _kVeryReasonableColor,
                                ),
                              ),
                            ),
                            // 合理（橙）
                            Expanded(
                              flex: reasonablePct.ceil(),
                              child: Container(
                                color: _kReasonableColor,
                              ),
                            ),
                            // 偏差（青）
                            Expanded(
                              flex: deviationPct.ceil(),
                              child: Container(
                                color: _kDeviationColor,
                              ),
                            ),
                            // 非常偏差（红）
                            Expanded(
                              flex: veryDeviationPct.ceil(),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: const BorderRadius.horizontal(
                                      right: Radius.circular(6)),
                                  color: _kVeryDeviationColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      // 标签行：非常合理/合理/偏差/非常偏差
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStatLabel('非常合理', veryReasonableCount,
                              veryReasonablePct, _kVeryReasonableColor),
                          _buildStatLabel('合理', reasonableCount, reasonablePct,
                              _kReasonableColor),
                          _buildStatLabel('偏差', deviationCount, deviationPct,
                              _kDeviationColor),
                          _buildStatLabel('非常偏差', veryDeviationCount,
                              veryDeviationPct, _kVeryDeviationColor),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 第四行：导出 + 删除按钮（各占一半宽度）
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _exportToCsv,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF58A6FF).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color:
                                      const Color(0xFF58A6FF).withOpacity(0.5)),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.ios_share,
                                    color: Color(0xFF58A6FF), size: 15),
                                SizedBox(width: 4),
                                Text('导出实时核对CSV',
                                    style: TextStyle(
                                        color: Color(0xFF58A6FF),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: _deleteAll,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: Colors.red.withOpacity(0.5)),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.delete_sweep,
                                    color: Colors.red, size: 15),
                                SizedBox(width: 4),
                                Text('一键删除',
                                    style: TextStyle(
                                        color: Colors.red,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 筛选排序栏
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Row(
                children: [
                  // 推荐类型下拉框
                  _buildFilterDropdown(
                    value: _filterType,
                    items: const ['全部', '看多', '看空', '观望'],
                    label: '类型',
                    onChanged: (v) => setState(() => _filterType = v),
                  ),
                  const SizedBox(width: 6),
                  // 状态下拉框
                  _buildReliabilityDropdown(),
                  const Spacer(),
                  // 排序下拉框
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _sortBy,
                      isDense: true,
                      iconEnabledColor: const Color(0xFF8B949E),
                      dropdownColor: const Color(0xFF21262D),
                      style: const TextStyle(
                          color: Color(0xFFF0F6FC), fontSize: 12),
                      items: const [
                        DropdownMenuItem(value: 'time', child: Text('时间')),
                        DropdownMenuItem(value: 'score', child: Text('评分')),
                        DropdownMenuItem(value: 'change', child: Text('涨幅')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _sortBy = v);
                      },
                    ),
                  ),
                  // 升降序切换
                  GestureDetector(
                    onTap: () =>
                        setState(() => _sortAscending = !_sortAscending),
                    child: Icon(
                      _sortAscending
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                      size: 18,
                      color: const Color(0xFF8B949E),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 留档列表
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final record = filteredArchives[index];
                final currentQuote = _currentQuotes[record.code];
                final currentPrice = currentQuote?.price ?? 0;
                final currentChangePct = currentQuote?.changePct ?? 0;

                String reliabilityLabel = '';
                Color reliabilityColor = Colors.transparent;
                if (currentPrice > 0 &&
                    (record.recommendation.contains('买入') ||
                        record.recommendation.contains('卖出') ||
                        record.recommendation.contains('观望'))) {
                  final level = _getReliabilityLevel(record, currentPrice);
                  final info = _getReliabilityInfo(level);
                  reliabilityLabel = info.label;
                  reliabilityColor = info.color;
                }

                final recColor = record.recommendation.contains('买入')
                    ? const Color(0xFFef5350)
                    : record.recommendation.contains('卖出')
                        ? const Color(0xFF26a69a)
                        : Colors.orange;

                return InkWell(
                  onLongPress: () => _deleteArchive(record),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161B22),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: recColor.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(record.name,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold)),
                                      const SizedBox(width: 6),
                                      Text(record.code,
                                          style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 11)),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Text('留档: ',
                                          style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 11)),
                                      Text(record.price.toStringAsFixed(2),
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12)),
                                      const SizedBox(width: 4),
                                      Text(
                                          DateFormat('MM/dd HH:mm')
                                              .format(record.archivedAt),
                                          style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 11)),
                                    ],
                                  ),
                                  if (currentPrice > 0) ...[
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Text('现价: ',
                                            style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 11)),
                                        Text(currentPrice.toStringAsFixed(2),
                                            style: TextStyle(
                                              color: currentChangePct >= 0
                                                  ? const Color(0xFFef5350)
                                                  : const Color(0xFF26a69a),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            )),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${currentChangePct >= 0 ? "+" : ""}${currentChangePct.toStringAsFixed(2)}%',
                                          style: TextStyle(
                                              color: currentChangePct >= 0
                                                  ? const Color(0xFFef5350)
                                                  : const Color(0xFF26a69a),
                                              fontSize: 11),
                                        ),
                                        if (reliabilityLabel.isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: reliabilityColor
                                                  .withOpacity(0.15),
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                            child: Text(reliabilityLabel,
                                                style: TextStyle(
                                                    color: reliabilityColor,
                                                    fontSize: 10,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: recColor.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                        color: recColor.withOpacity(0.5)),
                                  ),
                                  child: Text(record.recommendation,
                                      style: TextStyle(
                                          color: recColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(height: 4),
                                Text('${record.score}分',
                                    style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _buildTag('买${record.buySignalCount}',
                                const Color(0xFFef5350)),
                            const SizedBox(width: 4),
                            _buildTag('卖${record.sellSignalCount}',
                                const Color(0xFF26a69a)),
                            const SizedBox(width: 4),
                            _buildTag('战法${record.activeStrategyCount}',
                                const Color(0xFFFFC107)),
                            const SizedBox(width: 4),
                            _buildTag(
                                '共振${record.confluenceScore}/10', Colors.cyan),
                            const SizedBox(width: 4),
                            _buildTag(
                                '风险${record.riskLevel}',
                                record.riskLevel == '高'
                                    ? Colors.red
                                    : record.riskLevel == '中高'
                                        ? Colors.orange
                                        : Colors.white38),
                            const Spacer(),
                            GestureDetector(
                              onTap: () => _reanalyze(record),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: Colors.blue.withOpacity(0.5)),
                                ),
                                child: const Text('重新分析',
                                    style: TextStyle(
                                        color: Colors.blue,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
              childCount: filteredArchives.length,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String value,
    required List<String> items,
    required String label,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF30363D)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          iconEnabledColor: const Color(0xFF8B949E),
          dropdownColor: const Color(0xFF21262D),
          style: const TextStyle(color: Color(0xFFF0F6FC), fontSize: 12),
          items: items
              .map((item) => DropdownMenuItem(
                    value: item,
                    child: Text(item == '全部' && label == '类型' ? label : item,
                        style: const TextStyle(fontSize: 12)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _buildReliabilityDropdown() {
    final options = ['全部', '非常合理', '合理', '偏差', '非常偏差'];
    final chipColor = _getReliabilityColor(_filterReliability);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(
          color: _filterReliability == '全部'
              ? const Color(0xFF30363D)
              : chipColor.withOpacity(0.5),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _filterReliability,
          isDense: true,
          iconEnabledColor: const Color(0xFF8B949E),
          dropdownColor: const Color(0xFF21262D),
          style: TextStyle(color: chipColor, fontSize: 12),
          selectedItemBuilder: (context) => options
              .map((f) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (f != '全部')
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: _getReliabilityColor(f),
                            shape: BoxShape.circle,
                          ),
                        ),
                      Text(f == '全部' ? '状态' : f,
                          style: TextStyle(color: chipColor, fontSize: 12)),
                    ],
                  ))
              .toList(),
          items: options.map((f) {
            final color = _getReliabilityColor(f);
            return DropdownMenuItem(
              value: f,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (f != '全部')
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 6),
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                  Text(f == '全部' ? '全部' : f,
                      style: TextStyle(color: color, fontSize: 12)),
                ],
              ),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) setState(() => _filterReliability = v);
          },
        ),
      ),
    );
  }

  /// 获取可靠性标签对应的颜色
  static Color _getReliabilityColor(String label) {
    switch (label) {
      case '非常合理':
        return _kVeryReasonableColor;
      case '合理':
        return _kReasonableColor;
      case '偏差':
        return _kDeviationColor;
      case '非常偏差':
        return _kVeryDeviationColor;
      default:
        return const Color(0xFF8B949E);
    }
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  /// 统计标签组件：显示"标签 N(X%)"格式
  Widget _buildStatLabel(String label, int count, double pct, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        Text(
          '$label $count(${pct.toStringAsFixed(0)}%)',
          style: TextStyle(color: color, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildDirectionMetric(
    String label,
    int hits,
    int total,
    double rate,
    Color color,
  ) {
    final value = total > 0 ? '${rate.toStringAsFixed(0)}%' : '--';
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$value  $hits/$total',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      if (_tabVisible) _startAutoRefresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _apiClient.dispose();
    super.dispose();
  }

  void onTabVisible() {
    _tabVisible = true;
    _startAutoRefresh();
    _loadArchives();
  }

  void onTabHidden() {
    _tabVisible = false;
    _refreshTimer?.cancel();
  }
}
