import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../analysis/indicators.dart';
import '../analysis/signal_engine.dart';
import '../storage/database_service.dart';
import '../core/trading_session.dart';
import '../analysis/sector_rotation.dart';

enum ReliabilityLevel {
  veryReasonable,
  reasonable,
  deviation,
  veryDeviation,
}

const _kVeryReasonableColor = Color(0xFF4CAF50);
const _kReasonableColor = Colors.orange;
const _kDeviationColor = Color(0xFF26a69a);
const _kVeryDeviationColor = Color(0xFFef5350);


class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> with WidgetsBindingObserver {
  final ApiClient _apiClient = ApiClient();
  final DatabaseService _dbService = DatabaseService();
  List<ArchiveRecord> _archives = [];
  bool _isLoading = true;
  Map<String, QuoteData> _currentQuotes = {};
  Timer? _refreshTimer;
  String _sortBy = 'time'; // 'time', 'score', 'change'
  bool _sortAscending = false;
  String _filterType = '全部'; // '全部', '买入', '卖出', '观望'
  String _filterReliability = '全部'; // '全部', '非常合理', '合理', '偏差', '非常偏差'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadArchives();
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (TradingSession.isInTradingSession()) {
        _refreshCurrentPrices();
      }
    });
  }

  Future<void> _loadArchives() async {
    final archives = await _dbService.getArchives();
    setState(() {
      _archives = archives;
      _isLoading = false;
    });
    _refreshCurrentPrices();
  }

  /// 计算时间自适应阈值
  /// 
  /// 基准阈值 ±2%（5天），按 sqrt(天数/5) 缩放：
  ///   1天→2.0%, 5天→2.0%, 20天→4.0%, 60天→6.9%
  /// v2.38.0: 1天窗口最小阈值从1.0提升至2.0，与A股日常波动匹配
  /// 观望推荐的基准阈值为 ±8%，同样按时间缩放
  static (double threshold, double neutralThreshold) _calculateThresholds(ArchiveRecord record) {
    final daysSince = DateTime.now().difference(record.archivedAt).inDays.clamp(0, 365);
    final timeScale = max(daysSince, 1) / 5.0;
    final timeFactor = sqrt(timeScale);
    return ((2.0 * timeFactor).clamp(2.0, 12.0), (8.0 * timeFactor).clamp(4.0, 24.0));
  }

  /// 判断留档推荐的可靠性等级（4级）
  /// 
  /// 基于 priceChangePct 与阈值的比值判定：
  /// - veryReasonable（非常合理）：方向对且幅度超过2倍阈值
  /// - reasonable（合理）：方向对但幅度不够2倍阈值
  /// - deviation（偏差）：方向反但幅度小于2倍阈值
  /// - veryDeviation（非常偏差）：方向反且幅度超过2倍阈值
  /// 
  /// 观望类特殊处理：价格变动极小(绝对值<0.5×阈值)才算非常合理
  static ReliabilityLevel _getReliabilityLevel(ArchiveRecord record, double currentPrice) {
    if (currentPrice <= 0 || record.price <= 0) return ReliabilityLevel.reasonable;

    final priceChangePct = (currentPrice - record.price) / record.price * 100;
    final (threshold, neutralThreshold) = _calculateThresholds(record);

    final wasBuy = record.recommendation.contains('买入');
    final wasSell = record.recommendation.contains('卖出');
    final wasNeutral = record.recommendation.contains('观望');

    if (wasBuy) {
      if (priceChangePct >= 2 * threshold) {
        return ReliabilityLevel.veryReasonable;
      } else if (priceChangePct >= -threshold) {
        return ReliabilityLevel.reasonable;
      } else if (priceChangePct >= -2 * threshold) {
        return ReliabilityLevel.deviation;
      } else {
        return ReliabilityLevel.veryDeviation;
      }
    } else if (wasSell) {
      if (priceChangePct <= -2 * threshold) {
        return ReliabilityLevel.veryReasonable;
      } else if (priceChangePct <= threshold) {
        return ReliabilityLevel.reasonable;
      } else if (priceChangePct <= 2 * threshold) {
        return ReliabilityLevel.deviation;
      } else {
        return ReliabilityLevel.veryDeviation;
      }
    } else if (wasNeutral) {
      if (priceChangePct.abs() < 0.5 * neutralThreshold) {
        return ReliabilityLevel.veryReasonable;
      } else if (priceChangePct.abs() <= neutralThreshold) {
        return ReliabilityLevel.reasonable;
      } else if (priceChangePct.abs() <= 2 * neutralThreshold) {
        return ReliabilityLevel.deviation;
      } else {
        return ReliabilityLevel.veryDeviation;
      }
    }
    return ReliabilityLevel.reasonable;
  }

  /// 获取可靠性等级对应的标签和颜色
  static (String label, Color color) _getReliabilityInfo(ReliabilityLevel level) {
    switch (level) {
      case ReliabilityLevel.veryReasonable:
        return ('非常合理', _kVeryReasonableColor);
      case ReliabilityLevel.reasonable:
        return ('合理', _kReasonableColor);
      case ReliabilityLevel.deviation:
        return ('偏差', _kDeviationColor);
      case ReliabilityLevel.veryDeviation:
        return ('非常偏差', _kVeryDeviationColor);
    }
  }

  List<ArchiveRecord> _getFilteredAndSortedArchives() {
    var items = _archives.toList();

    // 筛选
    if (_filterType == '买入') {
      items = items.where((r) => r.recommendation.contains('买入')).toList();
    } else if (_filterType == '卖出') {
      items = items.where((r) => r.recommendation.contains('卖出')).toList();
    } else if (_filterType == '观望') {
      items = items.where((r) => r.recommendation.contains('观望')).toList();
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
      final codes = _archives.map((r) => _apiClient.addMarketPrefix(r.code)).toList();
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
      // ignore
    }
  }

  Future<void> _reanalyze(ArchiveRecord record) async {
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

    try {
      final prefixedCode = _apiClient.addMarketPrefix(record.code);
      final klines = await _apiClient.getStockHistory(prefixedCode, days: 120);
      final quote = await _apiClient.getRealtimeQuote(prefixedCode);

      if (klines.isEmpty) {
        if (mounted) Navigator.pop(context);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法获取数据')));
        return;
      }

      final calculated = calcAllIndicators(klines);

      final sectorName = await _apiClient.getStockSector(prefixedCode);
      final hotSectors = await _apiClient.getHotSectors();
      final sectorData = hotSectors.map((s) => SectorData(
        name: s.name, code: s.code, changePct: s.changePct,
        limitUpCount: s.stockCount, mainNetFlow: 0,
      )).toList();
      final sectorRotationResult = SectorRotation.analyze(sectorList: sectorData);

      final analysis = generateAnalysis(calculated, quote,
        sectorName: sectorName,
        sectorAnalysis: sectorRotationResult.topSectors,
      );

      if (mounted) Navigator.pop(context);

      if (mounted) _showReanalysisDialog(record, analysis, quote);
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('分析失败: $e')));
    }
  }

  void _showReanalysisDialog(ArchiveRecord record, AnalysisResult currentAnalysis, QuoteData? currentQuote) {
    final currentPrice = currentQuote?.price ?? 0;
    final currentChangePct = currentQuote?.changePct ?? 0;
    final priceChange = currentPrice - record.price;
    final priceChangePct = record.price > 0 ? (priceChange / record.price * 100) : 0.0;

    String reliability;
    Color reliabilityColor;
    if (currentPrice > 0 && (record.recommendation.contains('买入') ||
        record.recommendation.contains('卖出') ||
        record.recommendation.contains('观望'))) {
      final level = _getReliabilityLevel(record, currentPrice);
      final info = _getReliabilityInfo(level);
      reliability = info.$1;
      reliabilityColor = info.$2;
    } else {
      reliability = '推荐合理';
      reliabilityColor = Colors.orange;
    }

    showDialog(context: context, builder: (context) => Dialog(
      backgroundColor: const Color(0xFF0D1117),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${record.name} 重新分析', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _buildCompareRow('推荐', record.recommendation, currentAnalysis.recommendation),
            _buildCompareRow('评分', '${record.score}', '${currentAnalysis.score}'),
            _buildCompareRow('风险', record.riskLevel, currentAnalysis.riskLevel),
            _buildCompareRow('价格', record.price.toStringAsFixed(2), currentPrice.toStringAsFixed(2)),
            _buildCompareRow('涨跌幅', '${record.changePct.toStringAsFixed(2)}%', '${currentChangePct.toStringAsFixed(2)}%'),
            const Divider(color: Colors.white12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('价格变动', style: TextStyle(color: Colors.white54, fontSize: 13)),
                Text(
                  '${priceChange >= 0 ? '+' : ''}${priceChange.toStringAsFixed(2)} (${priceChangePct >= 0 ? '+' : ''}${priceChangePct.toStringAsFixed(2)}%)',
                  style: TextStyle(color: priceChange >= 0 ? const Color(0xFFef5350) : const Color(0xFF26a69a), fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: reliabilityColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: reliabilityColor.withOpacity(0.5)),
              ),
              child: Text(reliability, style: TextStyle(color: reliabilityColor, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
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
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
          Text(oldValue, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const Icon(Icons.arrow_forward, color: Colors.white24, size: 16),
          Text(newValue, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
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
        content: Text('确定要删除 ${record.name} 的留档记录吗？', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true && record.id != null) {
      await _dbService.deleteArchive(record.id!);
      _loadArchives();
    }
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0D1117),
        title: const Text('一键删除', style: TextStyle(color: Colors.white)),
        content: Text('确定要删除全部 ${_archives.length} 条留档记录吗？此操作不可恢复。', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('全部删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final record in _archives) {
      if (record.id != null) {
        await _dbService.deleteArchive(record.id!);
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已删除全部留档记录')),
      );
    }
    _loadArchives();
  }

  /// CSV 字段转义：包含逗号/引号/换行时用双引号包裹，内部双引号双写
  String _csvEscape(String? value) {
    if (value == null) return '';
    final v = value.replaceAll('\r', ' ').replaceAll('\n', ' ');
    if (v.contains(',') || v.contains('"')) {
      return '"${v.replaceAll('"', '""')}"';
    }
    return v;
  }

  /// 导出留档数据为 CSV 文件并通过系统分享
  Future<void> _exportToCsv() async {
    if (_archives.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无留档数据可导出')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // CSV 表头：留档元数据 + 推荐字段 + 实时行情 + 可靠性判定
      final headers = [
        '代码', '名称', '留档价格', '留档涨跌幅(%)', '评分', '推荐', '风险等级',
        '买入信号数', '卖出信号数', '活跃战法数', '共振评分',
        '留档时间',
        '现价', '现涨跌幅(%)', '价格变动(%)', '是否偏差', '可靠性',
        'topSignals',
      ];

      final now = DateTime.now();
      final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

      final lines = <String>[];
      lines.add(headers.map(_csvEscape).join(','));

      for (final record in _archives) {
        final quote = _currentQuotes[record.code];
        final currentPrice = quote?.price ?? 0;
        final currentChangePct = quote?.changePct ?? 0;
        final priceChangePct = record.price > 0 && currentPrice > 0
            ? (currentPrice - record.price) / record.price * 100
            : 0.0;
        String reliability = '未知';
        bool isDeviation = false;
        if (currentPrice > 0 && (record.recommendation.contains('买入') ||
            record.recommendation.contains('卖出') ||
            record.recommendation.contains('观望'))) {
          final level = _getReliabilityLevel(record, currentPrice);
          reliability = _getReliabilityInfo(level).$1;
          isDeviation = level == ReliabilityLevel.deviation || level == ReliabilityLevel.veryDeviation;
        }

        final row = [
          record.code,
          record.name,
          record.price.toStringAsFixed(4),
          record.changePct.toStringAsFixed(2),
          record.score.toString(),
          record.recommendation,
          record.riskLevel,
          record.buySignalCount.toString(),
          record.sellSignalCount.toString(),
          record.activeStrategyCount.toString(),
          record.confluenceScore.toString(),
          dateFormat.format(record.archivedAt),
          currentPrice > 0 ? currentPrice.toStringAsFixed(4) : '',
          currentPrice > 0 ? currentChangePct.toStringAsFixed(2) : '',
          currentPrice > 0 ? priceChangePct.toStringAsFixed(2) : '',
          currentPrice > 0 ? (isDeviation ? '是' : '否') : '',
          reliability,
          record.topSignals,
        ];
        lines.add(row.map(_csvEscape).join(','));
      }

      // 添加 BOM 防止 Excel 打开 CSV 时中文乱码
      final csvContent = '\uFEFF${lines.join('\n')}';

      final dir = await getTemporaryDirectory();
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(now);
      final file = File('${dir.path}/archive_export_$stamp.csv');
      await file.writeAsString(csvContent);

      if (!mounted) return;
      Navigator.pop(context); // 关闭 loading

      // 使用 share_plus 分享文件
      final shareResult = await Share.shareXFiles(
        [XFile(file.path)],
        subject: '留档数据导出 ($stamp)',
      );

      if (mounted && shareResult.status == ShareResultStatus.unavailable) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('分享功能不可用，请检查系统分享组件')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // 关闭 loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败: $e')),
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
            const Text('暂无留档记录', style: TextStyle(color: Colors.white38, fontSize: 14)),
            const SizedBox(height: 4),
            const Text('在"自选"页面中点击归档按钮保存推荐', style: TextStyle(color: Colors.white24, fontSize: 12)),
          ],
        ),
      );
    }

    final filteredArchives = _getFilteredAndSortedArchives();

    // 统计4级可靠性条数（基于筛选后的结果）
    int veryReasonableCount = 0;
    int reasonableCount = 0;
    int deviationCount = 0;
    int veryDeviationCount = 0;
    for (final record in filteredArchives) {
      final currentQuote = _currentQuotes[record.code];
      final currentPrice = currentQuote?.price ?? 0;
      if (currentPrice > 0 && (record.recommendation.contains('买入') ||
          record.recommendation.contains('卖出') ||
          record.recommendation.contains('观望'))) {
        final level = _getReliabilityLevel(record, currentPrice);
        switch (level) {
          case ReliabilityLevel.veryReasonable:
            veryReasonableCount++;
            break;
          case ReliabilityLevel.reasonable:
            reasonableCount++;
            break;
          case ReliabilityLevel.deviation:
            deviationCount++;
            break;
          case ReliabilityLevel.veryDeviation:
            veryDeviationCount++;
            break;
        }
      }
    }
    final total = veryReasonableCount + reasonableCount + deviationCount + veryDeviationCount;
    final winRate = total > 0 ? ((veryReasonableCount + reasonableCount) / total * 100) : 0.0;
    final isFiltered = _filterReliability != '全部' || _filterType != '全部';

    final veryReasonablePct = total > 0 ? (veryReasonableCount / total * 100) : 0.0;
    final reasonablePct = total > 0 ? (reasonableCount / total * 100) : 0.0;
    final deviationPct = total > 0 ? (deviationCount / total * 100) : 0.0;
    final veryDeviationPct = total > 0 ? (veryDeviationCount / total * 100) : 0.0;

    return RefreshIndicator(
      onRefresh: _loadArchives,
      child: CustomScrollView(
        slivers: [
          // 顶部胜率统计卡片（三行布局：胜率 + 分段比例条 + 操作按钮）
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
                  // 第一行：胜率 + 总计
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(isFiltered ? '筛选胜率' : '推荐胜率', style: TextStyle(color: isFiltered ? const Color(0xFF58A6FF) : Colors.white54, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text(
                              '${winRate.toStringAsFixed(1)}%',
                              style: const TextStyle(color: Colors.orange, fontSize: 28, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 40, color: Colors.white12),
                      const SizedBox(width: 16),
                      Column(
                        children: [
                          const Text('总计', style: TextStyle(color: Colors.white38, fontSize: 11)),
                          const SizedBox(height: 2),
                          Text('$total', style: const TextStyle(color: Colors.white70, fontSize: 22, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 第二行：分段比例条 + 标签
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
                            Container(
                              width: veryReasonablePct * 0.01 * double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.horizontal(left: Radius.circular(6)),
                                color: _kVeryReasonableColor,
                              ),
                            ),
                            // 合理（橙）
                            Container(
                              width: reasonablePct * 0.01 * double.infinity,
                              color: _kReasonableColor,
                            ),
                            // 偏差（青）
                            Container(
                              width: deviationPct * 0.01 * double.infinity,
                              color: _kDeviationColor,
                            ),
                            // 非常偏差（红）
                            Container(
                              width: veryDeviationPct * 0.01 * double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
                                color: _kVeryDeviationColor,
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
                          _buildStatLabel('非常合理', veryReasonableCount, veryReasonablePct, _kVeryReasonableColor),
                          _buildStatLabel('合理', reasonableCount, reasonablePct, _kReasonableColor),
                          _buildStatLabel('偏差', deviationCount, deviationPct, _kDeviationColor),
                          _buildStatLabel('非常偏差', veryDeviationCount, veryDeviationPct, _kVeryDeviationColor),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 第三行：导出 + 删除按钮（各占一半宽度）
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
                              border: Border.all(color: const Color(0xFF58A6FF).withOpacity(0.5)),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.ios_share, color: Color(0xFF58A6FF), size: 15),
                                SizedBox(width: 4),
                                Text('导出CSV', style: TextStyle(color: Color(0xFF58A6FF), fontSize: 12, fontWeight: FontWeight.w600)),
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
                              border: Border.all(color: Colors.red.withOpacity(0.5)),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.delete_sweep, color: Colors.red, size: 15),
                                SizedBox(width: 4),
                                Text('一键删除', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600)),
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
                    items: const ['全部', '买入', '卖出', '观望'],
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
                      style: const TextStyle(color: Color(0xFFF0F6FC), fontSize: 12),
                      items: const [
                        DropdownMenuItem(value: 'time', child: Text('时间')),
                        DropdownMenuItem(value: 'score', child: Text('评分')),
                        DropdownMenuItem(value: 'change', child: Text('涨幅')),
                      ],
                      onChanged: (v) { if (v != null) setState(() => _sortBy = v); },
                    ),
                  ),
                  // 升降序切换
                  GestureDetector(
                    onTap: () => setState(() => _sortAscending = !_sortAscending),
                    child: Icon(
                      _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
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
          final priceChange = currentPrice > 0 ? currentPrice - record.price : 0.0;

          String reliabilityLabel = '';
          Color reliabilityColor = Colors.transparent;
          if (currentPrice > 0 && (record.recommendation.contains('买入') ||
              record.recommendation.contains('卖出') ||
              record.recommendation.contains('观望'))) {
            final level = _getReliabilityLevel(record, currentPrice);
            final info = _getReliabilityInfo(level);
            reliabilityLabel = info.$1;
            reliabilityColor = info.$2;
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
                                Text(record.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 6),
                                Text(record.code, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text('留档: ', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                Text(record.price.toStringAsFixed(2), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                                const SizedBox(width: 4),
                                Text(DateFormat('MM/dd HH:mm').format(record.archivedAt), style: const TextStyle(color: Colors.white38, fontSize: 11)),
                              ],
                            ),
                            if (currentPrice > 0) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text('现价: ', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                  Text(currentPrice.toStringAsFixed(2), style: TextStyle(
                                    color: currentChangePct >= 0 ? const Color(0xFFef5350) : const Color(0xFF26a69a),
                                    fontSize: 12, fontWeight: FontWeight.bold,
                                  )),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${currentChangePct >= 0 ? "+" : ""}${currentChangePct.toStringAsFixed(2)}%',
                                    style: TextStyle(color: currentChangePct >= 0 ? const Color(0xFFef5350) : const Color(0xFF26a69a), fontSize: 11),
                                  ),
                                  if (reliabilityLabel.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: reliabilityColor.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: Text(reliabilityLabel, style: TextStyle(color: reliabilityColor, fontSize: 10, fontWeight: FontWeight.w600)),
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
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: recColor.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: recColor.withOpacity(0.5)),
                            ),
                            child: Text(record.recommendation, style: TextStyle(color: recColor, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(height: 4),
                          Text('${record.score}分', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildTag('买${record.buySignalCount}', const Color(0xFFef5350)),
                      const SizedBox(width: 4),
                      _buildTag('卖${record.sellSignalCount}', const Color(0xFF26a69a)),
                      const SizedBox(width: 4),
                      _buildTag('战法${record.activeStrategyCount}', const Color(0xFFFFC107)),
                      const SizedBox(width: 4),
                      _buildTag('共振${record.confluenceScore}/10', Colors.cyan),
                      const SizedBox(width: 4),
                      _buildTag('风险${record.riskLevel}', record.riskLevel == '高' ? Colors.red : record.riskLevel == '中高' ? Colors.orange : Colors.white38),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _reanalyze(record),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.blue.withOpacity(0.5)),
                          ),
                          child: const Text('重新分析', style: TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.w600)),
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
          items: items.map((item) => DropdownMenuItem(
            value: item,
            child: Text(item == '全部' && label == '类型' ? label : item,
              style: const TextStyle(fontSize: 12)),
          )).toList(),
          onChanged: (v) { if (v != null) onChanged(v); },
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
          color: _filterReliability == '全部' ? const Color(0xFF30363D)
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
          selectedItemBuilder: (context) => options.map((f) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (f != '全部')
                Container(
                  width: 6, height: 6,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: _getReliabilityColor(f),
                    shape: BoxShape.circle,
                  ),
                ),
              Text(f == '全部' ? '状态' : f,
                style: TextStyle(color: chipColor, fontSize: 12)),
            ],
          )).toList(),
          items: options.map((f) {
            final color = _getReliabilityColor(f);
            return DropdownMenuItem(
              value: f,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (f != '全部')
                    Container(
                      width: 6, height: 6,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                  Text(f == '全部' ? '全部' : f,
                    style: TextStyle(color: color, fontSize: 12)),
                ],
              ),
            );
          }).toList(),
          onChanged: (v) { if (v != null) setState(() => _filterReliability = v); },
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
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  /// 统计标签组件：显示"标签 N(X%)"格式
  Widget _buildStatLabel(String label, int count, double pct, Color color) {
    return Container(
      child: Row(
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
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _startAutoRefresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _apiClient.dispose();
    super.dispose();
  }
}
