import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';
import '../analysis/indicators.dart';
import '../analysis/signal_engine.dart';
import '../storage/database_service.dart';
import '../analysis/sector_rotation.dart';
import '../analysis/archive_reliability_evaluator.dart';
import '../services/legacy_archive_csv_exporter.dart';
import '../services/decision_csv_exporter.dart';
import '../analysis/decision_statistics.dart';
import '../analysis/decision_tracker.dart';
import '../analysis/archive_service.dart';
import '../analysis/trading_date_utils.dart';
import '../models/short_term_decision.dart';
import '../widgets/decision_archive_summary.dart';
import '../widgets/decision_calibration_summary.dart';
import '../widgets/score_radar_chart.dart';

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
  Map<String, QuoteData> _currentQuotes = {};
  Timer? _refreshTimer;
  Timer? _pendingTimer;
  bool _tabVisible = false;
  String _sortBy = 'time'; // 'time', 'score', 'change'
  bool _sortAscending = false;
  bool _showNewModel = true;
  int _decisionHorizon = 3;
  List<DecisionStatisticsRow> _decisionRows = [];
  RecommendationDirection? _decisionDirection;
  MarketRegime? _decisionMarketRegime;
  String? _decisionModelVersion;
  String _decisionSourceGroup = 'mine'; // 'mine' | 'scan' | 'all'
  String _decisionGroupBy = 'all'; // 'all' | 'day'
  bool _decisionTodayOnly = false;
  String _decisionSegmentBy = 'direction'; // 'direction' | 'regime' (P1-2)
  int _decisionPeriodDays = 0; // 0=全部, 30, 60, 90 (P1-2)
  bool _decisionHasError = false; // P2-3: 加载失败标记
  bool _archivesHasError = false; // P2-3
  bool _autoCleanEnabled = false; // P2-4: 自动清理过期决策数据（默认关）
  int _autoCleanDays = 90; // P2-4: 清理早于 N 天的数据
  bool _autoCleanRan = false; // P2-4: 本会话是否已执行过自动清理
  final Set<String> _decisionModelVersions = <String>{};
  String _filterType = '全部'; // '全部', '看多', '看空', '观望'
  String _filterReliability = '全部'; // '全部', '非常合理', '合理', '偏差', '非常偏差'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAutoCleanPrefs();
    _loadArchives();
    _loadDecisionRows();
    // v3.30: 定时器仅在 Tab 可见时运行（见 onTabVisible/onTabHidden），
    // 避免 IndexedStack 下后台永久拉行情/评估。
  }

  /// P2-4: 读取自动清理偏好（默认关闭）。
  Future<void> _loadAutoCleanPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _autoCleanEnabled = prefs.getBool('archive_auto_clean_enabled') ?? false;
        _autoCleanDays = prefs.getInt('archive_auto_clean_days') ?? 90;
      });
    } catch (e) {
      debugPrint('[留档] 读取自动清理偏好失败: $e');
    }
  }

  /// P2-4: 开启自动清理后，每个会话首次打开留档时清理早于 N 天的决策数据
  /// （默认排除手动留档 source='archive'，仅清过期扫描/自动数据）。
  Future<void> _maybeAutoClean() async {
    if (!_autoCleanEnabled || _autoCleanRan) return;
    _autoCleanRan = true;
    try {
      final removed = await _dbService.deleteDecisionDataOlderThanDays(
        _autoCleanDays,
        excludeSources: const ['archive'],
      );
      if (removed > 0) {
        debugPrint('[留档] 自动清理过期决策数据 $removed 条');
        await _loadDecisionRows();
      }
    } catch (e) {
      debugPrint('[留档] 自动清理失败: $e');
    }
  }

  Future<void> _loadDecisionRows() async {
    try {
      final rows = await _dbService.getDecisionStatisticsRows(
        filter: DecisionStatisticsFilter(
          horizon: _decisionHorizon,
          direction: _decisionDirection,
          marketRegime: _decisionMarketRegime,
          modelVersion: _decisionModelVersion,
        ),
      );
      if (mounted) {
        setState(() {
          _decisionRows = rows;
          _decisionHasError = false;
          _decisionModelVersions.addAll(
            rows.map((row) => row.snapshot.modelVersion),
          );
        });
      }
    } catch (e) {
      debugPrint('[留档] 加载决策统计行失败: $e');
      if (mounted) setState(() => _decisionHasError = true);
    }
  }

  /// 为缺少决策快照的留档记录补录决策信息（联网重分析回填）。
  Future<void> _backfillDecision() async {
    final summary = await showDialog<BackfillSummary>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BackfillDecisionDialog(db: _dbService),
    );
    // 回填后刷新「新模型」与「历史口径」数据。
    await _loadDecisionRows();
    await _loadArchives();
    if (mounted && summary != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(summary.total == 0
              ? '没有需要补录的留档'
              : '补录完成：成功 ${summary.success} 条，失败 ${summary.failed} 条'),
          backgroundColor: const Color(0xFF58A6FF),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildModeSwitch() => SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: true, label: Text('决策命中')),
          ButtonSegment(value: false, label: Text('实时合理')),
        ],
        selected: {_showNewModel},
        showSelectedIcon: false,
        onSelectionChanged: (value) =>
            setState(() => _showNewModel = value.first),
      );

  /// P2-3: 当前是否启用了非默认筛选（用于区分"空"与"无匹配"）。
  bool _decisionFiltersActive() =>
      _decisionDirection != null ||
      _decisionMarketRegime != null ||
      _decisionModelVersion != null ||
      _decisionSourceGroup != 'mine';

  /// P2-3: 决策数据加载失败时显示错误态 + 重试按钮。
  Widget _buildDecisionErrorIfNeeded() {
    if (!_decisionHasError) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF3d1d1d),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('决策数据加载失败',
                style: TextStyle(color: Colors.red, fontSize: 13)),
          ),
          TextButton(
            onPressed: () {
              setState(() => _decisionHasError = false);
              _loadDecisionRows();
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  /// P2-4: 自动清理开关 + 天数选择（持久化，默认关闭）。
  Widget _buildAutoCleanControl() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('自动清理过期决策数据', style: TextStyle(fontSize: 13)),
                  Text(
                    _autoCleanEnabled
                        ? '清理早于 ${_autoCleanDays} 天的非留档数据'
                        : '关闭（默认）',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (_autoCleanEnabled)
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 30, label: Text('30天')),
                  ButtonSegment(value: 60, label: Text('60天')),
                  ButtonSegment(value: 90, label: Text('90天')),
                  ButtonSegment(value: 180, label: Text('180天')),
                ],
                selected: {_autoCleanDays},
                showSelectedIcon: false,
                onSelectionChanged: (v) => _setAutoCleanDays(v.first),
              ),
            Switch(
              value: _autoCleanEnabled,
              activeColor: const Color(0xFF58A6FF),
              onChanged: (v) => _setAutoCleanEnabled(v),
            ),
          ],
        ),
      );

  Future<void> _setAutoCleanEnabled(bool value) async {
    setState(() => _autoCleanEnabled = value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('archive_auto_clean_enabled', value);
    } catch (e) {
      debugPrint('[留档] 保存自动清理开关失败: $e');
    }
    if (value) {
      _autoCleanRan = false; // 允许立即执行一次
      await _maybeAutoClean();
    }
  }

  Future<void> _setAutoCleanDays(int days) async {
    setState(() => _autoCleanDays = days);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('archive_auto_clean_days', days);
    } catch (e) {
      debugPrint('[留档] 保存自动清理天数失败: $e');
    }
    _autoCleanRan = false;
    await _maybeAutoClean();
  }

  Widget _buildDecisionMode() {
    var rows = _filterDecisionRows(_decisionRows);
    if (_decisionTodayOnly) {
      final today = TradingDateUtils.normalizeToTradeDate(DateTime.now());
      rows = rows
          .where((r) => _sameDay(r.snapshot.signalTradeDate, today))
          .toList();
    }
    final summary = DecisionStatistics.summarize(rows);
    return RefreshIndicator(
      onRefresh: _loadDecisionRows,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildDecisionErrorIfNeeded(),
          _buildModeSwitch(),
          const SizedBox(height: 12),
          _buildDecisionFilters(),
          const SizedBox(height: 8),
          _buildDecisionGroupControls(),
          const SizedBox(height: 12),
          DecisionArchiveSummary(
            summary: summary,
            horizon: _decisionHorizon,
            onHorizonChanged: (horizon) {
              setState(() => _decisionHorizon = horizon);
              _loadDecisionRows();
            },
          ),
          const SizedBox(height: 8),
          const Text(
            '决策命中：事后回溯 1/3/5 交易日方向命中率，用于判断评分合理性、优化评分逻辑。',
            style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
          ),
          const SizedBox(height: 12),
          _buildDecisionAnalysis(rows),
          const SizedBox(height: 12),
          const Text(
            '胜率趋势：按归档日的有效命中率变化，50% 为随机基准；优化评分后应收敛并稳定高于基准。',
            style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
          ),
          const SizedBox(height: 8),
          _buildWinRateTrend(rows),
          const SizedBox(height: 12),
          _buildAutoCleanControl(),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: _exportToCsv,
                icon: const Icon(Icons.ios_share, size: 16),
                label: const Text('导出决策CSV'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _deleteAllDecision,
                icon: const Icon(Icons.delete_sweep, size: 16),
                label: const Text('清空决策数据'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: BorderSide(color: Colors.red.withOpacity(0.5)),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _backfillDecision,
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('补录缺失决策'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 60),
              child: Column(
                children: [
                  Icon(
                      _decisionFiltersActive()
                          ? Icons.filter_alt_off_outlined
                          : Icons.insights_outlined,
                      size: 48, color: const Color(0xFF30363D)),
                  const SizedBox(height: 12),
                  Text(
                    _decisionFiltersActive()
                        ? '无匹配记录，试试调整筛选条件'
                        : (_decisionSourceGroup == 'mine'
                            ? '尚未留档任何股票'
                            : '暂无新模型评估数据'),
                    style: const TextStyle(color: Colors.white54, fontSize: 14)),
                  if (!_decisionFiltersActive())
                    const SizedBox(height: 8),
                  if (!_decisionFiltersActive())
                    const Text(
                      '在个股详情页点“留档”，或在自选页点“归档”，\n'
                      '系统自动加入并跟踪 1/3/5 日命中率。\n'
                      '（也可在“发现”页“刷新探索”生成全市场扫描数据）',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white38, fontSize: 12, height: 1.6),
                    ),
                ],
              ),
            )
          else if (_decisionGroupBy == 'day')
            _buildGroupedDecisionList(rows)
          else
            ...rows.map(_buildDecisionRow),
        ],
      ),
    );
  }

  /// 分组 / 今日筛选控制行。
  Widget _buildDecisionGroupControls() {
    final today = TradingDateUtils.normalizeToTradeDate(DateTime.now());
    final todayCount = _filterDecisionRows(_decisionRows)
        .where((r) => _sameDay(r.snapshot.signalTradeDate, today))
        .length;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'all', label: Text('全部')),
            ButtonSegment(value: 'day', label: Text('按归档日')),
          ],
          selected: {_decisionGroupBy},
          showSelectedIcon: false,
          onSelectionChanged: (value) =>
              setState(() => _decisionGroupBy = value.first),
        ),
        FilterChip(
          label: Text(_decisionTodayOnly ? '今日归档 ✓' : '今日归档'),
          selected: _decisionTodayOnly,
          onSelected: (v) => setState(() => _decisionTodayOnly = v),
          backgroundColor: const Color(0xFF161B22),
          selectedColor: const Color(0xFF58A6FF).withOpacity(0.25),
          labelStyle: TextStyle(
            color: _decisionTodayOnly
                ? const Color(0xFF58A6FF)
                : Colors.white70,
            fontSize: 12,
          ),
          visualDensity: VisualDensity.compact,
        ),
        Text('今日 $todayCount 只',
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ],
    );
  }

  /// 按归档日分组，每组显示该日有效命中率与小计，便于盘后看「当天批次」胜率。
  Widget _buildGroupedDecisionList(List<DecisionStatisticsRow> rows) {
    final groups = <String, List<DecisionStatisticsRow>>{};
    for (final r in rows) {
      final key = _dateKey(r.snapshot.signalTradeDate);
      groups.putIfAbsent(key, () => []).add(r);
    }
    final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    final todayKey = _dateKey(
        TradingDateUtils.normalizeToTradeDate(DateTime.now()));
    final children = <Widget>[];
    for (final key in keys) {
      final group = groups[key]!;
      final s = DecisionStatistics.summarize(group);
      final isToday = key == todayKey;
      final hit = s.effectiveHitRate;
      children.add(
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isToday
                ? const Color(0xFF58A6FF).withOpacity(0.12)
                : const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(8),
            border: isToday
                ? Border.all(color: const Color(0xFF58A6FF).withOpacity(0.5))
                : null,
          ),
          child: Row(
            children: [
              Text(key,
                  style: TextStyle(
                      color: isToday
                          ? const Color(0xFF58A6FF)
                          : Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              if (isToday) ...[
                const SizedBox(width: 6),
                const Text('今日',
                    style: TextStyle(color: Color(0xFF58A6FF), fontSize: 11)),
              ],
              const Spacer(),
              Text(
                '有效命中 ${hit == null ? "--" : "${(hit * 100).toStringAsFixed(1)}%"}'
                ' · ${group.length} 只',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      );
      for (final r in group) {
        children.add(_buildDecisionRow(r));
      }
    }
    return Column(children: children);
  }

  /// P1-2: 按方向 / 市场状态分段展示有效命中率（柱状图）+ 校准摘要（Brier/ECE），
  /// 支持 30/60/90 天周期过滤。用于判断"哪类行情下评分更准"，是优化评分逻辑的依据。
  Widget _buildDecisionAnalysis(List<DecisionStatisticsRow> rows) {
    final period = _decisionPeriodDays;
    var filtered = rows;
    if (period > 0) {
      final cutoff = TradingDateUtils.normalizeToTradeDate(DateTime.now())
          .subtract(Duration(days: period));
      filtered = rows
          .where((r) => !r.snapshot.signalTradeDate.isBefore(cutoff))
          .toList();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'direction', label: Text('按方向')),
                ButtonSegment(value: 'regime', label: Text('按市场状态')),
              ],
              selected: {_decisionSegmentBy},
              showSelectedIcon: false,
              onSelectionChanged: (v) =>
                  setState(() => _decisionSegmentBy = v.first),
            ),
            ...<int>[0, 30, 60, 90].map(
              (d) => FilterChip(
                label: Text(d == 0 ? '全部' : '$d天'),
                selected: _decisionPeriodDays == d,
                onSelected: (_) => setState(() => _decisionPeriodDays = d),
                backgroundColor: const Color(0xFF161B22),
                selectedColor: const Color(0xFF58A6FF).withOpacity(0.25),
                labelStyle: TextStyle(
                  color: _decisionPeriodDays == d
                      ? const Color(0xFF58A6FF)
                      : Colors.white70,
                  fontSize: 12,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('当前周期/筛选下无足够数据',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          )
        else ...[
          _buildSegmentedHitRateBar(filtered),
          const SizedBox(height: 12),
          DecisionCalibrationSummary(
            summary: DecisionStatistics.summarize(filtered),
          ),
        ],
      ],
    );
  }

  /// 分段有效命中率柱状图：按方向或市场状态分组，每根柱显示该段有效命中率与样本数。
  Widget _buildSegmentedHitRateBar(List<DecisionStatisticsRow> rows) {
    final groups = <String, List<DecisionStatisticsRow>>{};
    for (final r in rows) {
      final key = _decisionSegmentBy == 'direction'
          ? _directionLabel(r.snapshot.direction)
          : _marketRegimeLabel(r.snapshot.marketRegime);
      groups.putIfAbsent(key, () => []).add(r);
    }
    final data = groups.entries
        .map((e) =>
            (e.key, DecisionStatistics.summarize(e.value).effectiveHitRate, e.value.length))
        .where((d) => d.$3 > 0)
        .toList();
    if (data.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 200,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: BarChart(
        BarChartData(
          maxY: 1.0,
          minY: 0.0,
          barGroups: data.asMap().entries.map((entry) {
            final i = entry.key;
            final d = entry.value;
            final hit = d.$2 ?? 0.0;
            final color = hit >= 0.5
                ? const Color(0xFF4caf50)
                : const Color(0xFFef5350);
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: hit,
                  color: color,
                  width: 28,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          }).toList(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.white10,
              strokeWidth: 0.5,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 38,
                getTitlesWidget: (value, meta) => Text(
                  '${(value * 100).toInt()}%',
                  style: const TextStyle(color: Colors.white38, fontSize: 9),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= data.length) return const Text('');
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(data[i].$1,
                        style: const TextStyle(color: Colors.white54, fontSize: 10)),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  /// P1-3: 有效命中率按归档日(信号日)的趋势折线图，帮助判断评分准确性是否随时间改善
  /// （优化评分逻辑后胜率应上行）。尊重当前方向/模型版本/周期筛选。50% 为随机基准参考线。
  Widget _buildWinRateTrend(List<DecisionStatisticsRow> rows) {
    final byDate = <String, List<DecisionStatisticsRow>>{};
    for (final r in rows) {
      final key = _dateKey(r.snapshot.signalTradeDate);
      byDate.putIfAbsent(key, () => []).add(r);
    }
    final entries = byDate.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final points = entries
        .map((e) => (
              e.key,
              DecisionStatistics.summarize(e.value).effectiveHitRate,
              e.value.length
            ))
        .where((d) => d.$2 != null)
        .toList();
    if (points.length < 2) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('按日趋势需要至少 2 个有命中结果的归档日',
            style: TextStyle(color: Colors.white54, fontSize: 12)),
      );
    }
    final dataCount = points.length;
    final values = points.map((d) => (d.$2! * 100)).toList();
    final spots = List.generate(
        dataCount, (i) => FlSpot(i.toDouble(), values[i]));
    return Container(
      height: 170,
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: 100,
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF21262D),
              tooltipRoundedRadius: 6,
              getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                final idx = spot.x.toInt();
                final date = idx >= 0 && idx < dataCount ? points[idx].$1 : '';
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(1)}%  ($date)',
                  const TextStyle(color: Colors.white, fontSize: 11),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.3,
              color: const Color(0xFF58A6FF),
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: dataCount <= 15,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                  radius: 3,
                  color: const Color(0xFF58A6FF),
                  strokeWidth: 0,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFF58A6FF).withOpacity(0.08),
              ),
            ),
            // 随机基准 50% 参考线
            LineChartBarData(
              spots: [
                FlSpot(0, 50),
                FlSpot((dataCount - 1).toDouble(), 50),
              ],
              isCurved: false,
              color: Colors.white24,
              barWidth: 0.8,
              dotData: const FlDotData(show: false),
              dashArray: const [4, 4],
            ),
          ],
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.white.withOpacity(0.05),
              strokeWidth: 0.5,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) => Text(
                  '${value.toInt()}%',
                  style: const TextStyle(color: Colors.white38, fontSize: 9),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 18,
                interval: dataCount <= 5
                    ? 1
                    : dataCount <= 10
                        ? 2
                        : (dataCount / 5).ceilToDouble(),
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= dataCount) {
                    return const SizedBox.shrink();
                  }
                  final date = points[idx].$1; // YYYY-MM-DD
                  return Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      date.substring(5),
                      style: const TextStyle(color: Colors.white24, fontSize: 8),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  Widget _buildDecisionFilters() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'mine', label: Text('我的留档')),
            ButtonSegment(value: 'scan', label: Text('全市场扫描')),
            ButtonSegment(value: 'all', label: Text('全部')),
          ],
          selected: {_decisionSourceGroup},
          showSelectedIcon: false,
          onSelectionChanged: (value) =>
              setState(() => _decisionSourceGroup = value.first),
        ),
        _buildDecisionFilterDropdown<RecommendationDirection>(
          value: _decisionDirection,
          hint: '方向',
          items: RecommendationDirection.values,
          labelOf: (value) => _directionLabel(value),
          onChanged: (value) {
            setState(() => _decisionDirection = value);
            _loadDecisionRows();
          },
        ),
        _buildDecisionFilterDropdown<MarketRegime>(
          value: _decisionMarketRegime,
          hint: '市场状态',
          items: MarketRegime.values,
          labelOf: (value) => _marketRegimeLabel(value),
          onChanged: (value) {
            setState(() => _decisionMarketRegime = value);
            _loadDecisionRows();
          },
        ),
        _buildDecisionFilterDropdown<String>(
          value: _decisionModelVersion,
          hint: '模型版本',
          items: _decisionModelVersions.toList()..sort(),
          labelOf: (value) => _modelVersionLabel(value),
          onChanged: (value) {
            setState(() => _decisionModelVersion = value);
            _loadDecisionRows();
          },
        ),
      ],
    );
  }

  /// 按来源分组（我的留档 / 全市场扫描 / 全部）在内存中过滤决策行。
  List<DecisionStatisticsRow> _filterDecisionRows(
    List<DecisionStatisticsRow> rows,
  ) {
    switch (_decisionSourceGroup) {
      case 'mine':
        return rows
            .where((r) => r.snapshot.source == ArchiveService.kManualSource)
            .toList();
      case 'scan':
        return rows
            .where((r) =>
                r.snapshot.source == 'explore' ||
                r.snapshot.source == 'opportunity')
            .toList();
      default:
        return rows;
    }
  }

  Widget _buildDecisionFilterDropdown<T>({
    required T? value,
    required String hint,
    required List<T> items,
    required String Function(T value) labelOf,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButton<T>(
      value: value,
      hint: Text(hint),
      items: [
        DropdownMenuItem<T>(value: null, child: Text('全部$hint')),
        ...items.map(
          (item) => DropdownMenuItem<T>(
            value: item,
            child: Text(labelOf(item)),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }

  /// 方向枚举 → 中文标签
  static String _directionLabel(RecommendationDirection value) {
    switch (value) {
      case RecommendationDirection.bullish:
        return '看多';
      case RecommendationDirection.neutral:
        return '观望';
      case RecommendationDirection.bearish:
        return '看空';
    }
  }

  /// 市场状态枚举 → 中文标签
  static String _marketRegimeLabel(MarketRegime value) {
    switch (value) {
      case MarketRegime.bullishTrend:
        return '牛市趋势';
      case MarketRegime.bearishTrend:
        return '熊市趋势';
      case MarketRegime.rebound:
        return '反弹';
      case MarketRegime.pullback:
        return '回调';
      case MarketRegime.range:
        return '震荡';
      case MarketRegime.highVolatility:
        return '高波动';
      case MarketRegime.unknown:
        return '未知';
    }
  }

  /// 数据来源 → 中文标签（动态值，未知来源回退原始字符串）
  static String _sourceLabel(String value) {
    switch (value) {
      case 'explore':
        return '探索扫描';
      case 'opportunity':
        return '机会扫描';
      case 'test':
        return '测试';
      default:
        return value;
    }
  }

  /// 模型版本 → 中文标签（动态值，未知版本回退原始字符串）
  static String _modelVersionLabel(String value) {
    switch (value) {
      case 'short-term-v2':
        return '短线决策V2';
      case 'direction-v1':
        return '方向模型V1';
      default:
        return value;
    }
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _buildDecisionRow(DecisionStatisticsRow row) {
    final snapshot = row.snapshot;
    final outcome = row.outcome;
    String value(double? number) =>
        number == null ? '--' : '${number.toStringAsFixed(2)}%';
    return GestureDetector(
      onTap: () => _showDecisionDetail(row),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${snapshot.name} ${snapshot.code}')),
          Text(outcome.status.name,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
        const SizedBox(height: 2),
        Text(_dateKey(snapshot.signalTradeDate),
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 6),
        Text('${_sourceLabel(snapshot.source)}  ${_modelVersionLabel(snapshot.modelVersion)}',
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 6),
        Text(
          '${_directionLabel(snapshot.direction)}  方向 ${snapshot.directionScore.toStringAsFixed(0)}  '
          '质量 ${snapshot.tradeQualityScore.toStringAsFixed(0)}  '
          '风险 ${snapshot.riskScore.toStringAsFixed(0)}  '
          '证据 ${snapshot.evidenceConfidence.toStringAsFixed(0)}',
          style: const TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 6),
        Text(
          '收益 ${value(outcome.forecastReturn)}  Alpha ${value(outcome.alphaReturn)}  '
          'MFE ${value(outcome.mfe)}  MAE ${value(outcome.mae)}',
          style: const TextStyle(color: Color(0xFF8B949E), fontSize: 12),
        ),
      ]),
      ),
    );
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _refreshCurrentPrices();
    });
    // vX.Y.Z: 周期评估 pending 决策快照的命中率，使「新模型」数据逐步更新，
    // 避免只刷行情、快照永远停留在 pending。
    _pendingTimer?.cancel();
    _pendingTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _refreshPendingDecisions();
    });
  }

  /// 评估仍处于 pending 的决策快照（命中率），失败仅记录日志。
  Future<void> _refreshPendingDecisions() async {
    try {
      await DecisionTracker().refreshPending(limit: 200);
    } catch (e) {
      debugPrint('[留档] 命中率评估刷新失败: $e');
    }
  }

  /// P1-1: 点击决策行 → 下钻明细，展示评分构成、预测概率(Wilson)、各周期命中与结果，
  /// 帮助用户理解"为什么这么推荐"以及"事后是否兑现"，用于评估评分合理性。
  Future<void> _showDecisionDetail(DecisionStatisticsRow row) async {
    final snapshot = row.snapshot;
    // 同快照的 1/3/5 日全部周期结果（getDecisionStatisticsRows 不传 horizon 即返回全部）。
    List<DecisionStatisticsRow> horizonRows = [];
    if (snapshot.id != null) {
      try {
        horizonRows = await _dbService.getDecisionStatisticsRows(
          snapshotId: snapshot.id,
        );
      } catch (e) {
        debugPrint('[留档] 加载同快照多周期结果失败: $e');
      }
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0D1117),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _buildDetailHeader(snapshot, row.outcome),
            const SizedBox(height: 16),
            _buildDetailRadar(snapshot),
            const SizedBox(height: 16),
            _buildComponentSection('方向成分', snapshot.directionComponents),
            _buildComponentSection('质量成分', snapshot.qualityComponents),
            _buildComponentSection('风险成分', snapshot.riskComponents),
            const SizedBox(height: 16),
            _buildDetailPrediction(row.outcome),
            const SizedBox(height: 16),
            _buildPerHorizonTable(horizonRows),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailHeader(
    DecisionSnapshotRecord snapshot,
    DecisionOutcomeRecord outcome,
  ) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('${snapshot.name} ${snapshot.code}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF58A6FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(outcome.status.name,
                  style: const TextStyle(color: Color(0xFF58A6FF), fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            '${_dateKey(snapshot.signalTradeDate)}  '
            '${_directionLabel(snapshot.direction)} · ${snapshot.recommendationLabel}  '
            '评分 ${snapshot.legacyScore}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            '${_sourceLabel(snapshot.source)}  ${_modelVersionLabel(snapshot.modelVersion)}  '
            '${_marketRegimeLabel(snapshot.marketRegime)}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      );

  /// 4 维雷达：方向 / 质量 / 风险 / 证据（由对应成分聚合而来）。
  Widget _buildDetailRadar(DecisionSnapshotRecord snapshot) => Center(
        child: ScoreRadarChart(
          scores: <String, double>{
            '方向': snapshot.directionScore,
            '质量': snapshot.tradeQualityScore,
            '风险': snapshot.riskScore,
            '证据': snapshot.evidenceConfidence,
          },
          dimensions: const ['方向', '质量', '风险', '证据'],
          dimensionColors: const [
            Color(0xFF26a69a),
            Color(0xFF4caf50),
            Color(0xFFef5350),
            Color(0xFF03a9f4),
          ],
          totalScore: snapshot.legacyScore,
          size: 240,
        ),
      );

  Widget _buildComponentSection(
    String title,
    Map<String, double> components,
  ) {
    if (components.isEmpty) return const SizedBox.shrink();
    final entries = components.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white70)),
        const SizedBox(height: 6),
        ...entries.map(
          (e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Expanded(
                    child: Text(e.key,
                        style: const TextStyle(fontSize: 12, color: Colors.white54))),
                Text(e.value.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 12, color: Colors.white)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// 预测概率 + Wilson 区间（来自 outcome 的事前校准估计）。
  Widget _buildDetailPrediction(DecisionOutcomeRecord outcome) {
    final p = outcome.predictedProbability;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('事前预测',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (p == null)
            const Text('无预测概率', style: TextStyle(color: Colors.white54, fontSize: 12))
          else ...[
            Row(children: [
              const Text('命中概率'),
              const SizedBox(width: 8),
              Text('${(p * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF58A6FF))),
              const Spacer(),
              if (outcome.predictedSampleCount > 0)
                Text('样本 ${outcome.predictedSampleCount}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
            if (outcome.predictedWilsonLower != null &&
                outcome.predictedWilsonUpper != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Wilson 95%: ${(outcome.predictedWilsonLower! * 100).toStringAsFixed(1)}%'
                  ' ~ ${(outcome.predictedWilsonUpper! * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// 同快照 1/3/5 日各周期的事后结果对比。
  Widget _buildPerHorizonTable(List<DecisionStatisticsRow> horizonRows) {
    if (horizonRows.isEmpty) return const SizedBox.shrink();
    String hit(bool? v) => v == null ? '--' : (v ? '✓' : '✗');
    String num(double? v) => v == null ? '--' : '${v.toStringAsFixed(2)}%';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('各周期结果',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: const [
              Expanded(flex: 2, child: Text('周期', style: _kDetailTableHeader)),
              Expanded(child: Text('状态', style: _kDetailTableHeader)),
              Expanded(child: Text('方向', style: _kDetailTableHeader)),
              Expanded(child: Text('收益', style: _kDetailTableHeader)),
              Expanded(child: Text('Alpha', style: _kDetailTableHeader)),
            ],
          ),
          const Divider(color: Color(0xFF30363D)),
          for (final r in horizonRows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                      flex: 2,
                      child: Text('${r.outcome.horizon}日',
                          style: const TextStyle(fontSize: 12))),
                  Expanded(
                      child: Text(r.outcome.status.name,
                          style: const TextStyle(fontSize: 12, color: Colors.white54))),
                  Expanded(
                      child: Text(hit(r.outcome.effectiveDirectionHit),
                          style: const TextStyle(fontSize: 12))),
                  Expanded(
                      child: Text(num(r.outcome.forecastReturn),
                          style: const TextStyle(fontSize: 12))),
                  Expanded(
                      child: Text(num(r.outcome.alphaReturn),
                          style: const TextStyle(fontSize: 12))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static const TextStyle _kDetailTableHeader = TextStyle(
    fontSize: 11,
    color: Colors.white38,
  );

  Future<void> _loadArchives() async {
    try {
      final archives = await _dbService.getArchives();
      if (!mounted) return;
      setState(() {
        _archives = archives;
        _archivesHasError = false;
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
          _archivesHasError = true;
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
            _cleanupOption(context, '清空全部留档（不可恢复）', 'all',
                danger: true),
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
        n = await _dbService.deleteArchivesOlderThanDays(
            action == 'older30' ? 30 : 90);
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

  /// 新模型选择性清理：保留已评估作参考，只清 pending/无效，或按天/全清。
  Future<void> _deleteAllDecision() async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF0D1117),
        title: const Text('清理决策评估数据', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('「保留已评估作参考」可只清待评估/无效，不丢评分样本。',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 12),
            _cleanupOption(context, '仅清待评估(pending)', 'pending'),
            _cleanupOption(context, '仅清无效(invalid)', 'invalid'),
            _cleanupOption(context, '删除 90 天前(留档除外)', 'older90'),
            _cleanupOption(context, '清空全部（不可恢复）', 'all', danger: true),
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
      if (action == 'all') {
        await _dbService.deleteAllDecisionData();
      } else if (action == 'pending' || action == 'invalid') {
        final n = await _dbService.deleteDecisionDataByStatus(action);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已清理 $n 条$action 数据')),
          );
        }
      } else if (action == 'older90') {
        final n = await _dbService.deleteDecisionDataOlderThanDays(90);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已删除 $n 条 90 天前决策数据(留档除外)')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清理失败：$e')),
        );
      }
      return;
    }
    _loadDecisionRows();
  }

  /// 导出留档数据为 CSV 文件并通过系统分享
  Future<void> _exportToCsv() async {
    final hasRows =
        _showNewModel ? _decisionRows.isNotEmpty : _archives.isNotEmpty;
    if (!hasRows) {
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
      final now = DateTime.now();

      // 使用专用导出服务生成 CSV（含 BOM 和可靠性评估）
      final decisionRowsForExport = _showNewModel
          ? await _dbService.getDecisionStatisticsRows(
              filter: DecisionStatisticsFilter(
                direction: _decisionDirection,
                marketRegime: _decisionMarketRegime,
                modelVersion: _decisionModelVersion,
              ),
            )
          : const <DecisionStatisticsRow>[];
      final stamp = DateFormat('yyyyMMdd_HHmmss').format(now);
      final csvContent = _showNewModel
          ? buildDecisionCsv(buildDecisionExportRows(decisionRowsForExport))
          : buildLegacyArchiveCsv(
              records: _archives,
              quoteOf: (code) => _currentQuotes[code],
              now: now,
            );
      final fileName = _showNewModel
          ? decisionExportFileName(now)
          : 'archive_export_$stamp.csv';

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
            content: Text('已导出 $fileName (${_archives.length}条)'),
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

    if (_showNewModel) return _buildDecisionMode();

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
              padding: const EdgeInsets.all(8),
              child: _buildModeSwitch(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: const Text(
                '实时合理：以当前价对比归档时推荐方向，实时浮动，非命中率，不用于评分准确性判断。',
                style: TextStyle(color: Colors.white30, fontSize: 11, height: 1.5),
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
                                Text('导出CSV',
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
      _pendingTimer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      // v3.30: 仅当留档 Tab 当前可见时才恢复定时器（IndexedStack 不 dispose）。
      if (_tabVisible) _startAutoRefresh();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _pendingTimer?.cancel();
    _apiClient.dispose();
    super.dispose();
  }

  /// v3.2: 切回留档tab时自动刷新数据。
  /// v3.30: 标记可见并启动定时器；额外触发一次 pending 命中率评估，
  /// 保证次日打开 App 即回填昨日已成熟的 pending 快照（无需等 5 分钟定时器）。
  void onTabVisible() {
    _tabVisible = true;
    _startAutoRefresh();
    _loadArchives();
    _loadDecisionRows();
    _refreshPendingDecisions();
    _maybeAutoClean();
  }

  /// v3.30: 切离留档 Tab 时停止后台定时器，避免 IndexedStack 下永久运行。
  void onTabHidden() {
    _tabVisible = false;
    _refreshTimer?.cancel();
    _pendingTimer?.cancel();
  }
}

/// 补录缺失决策信息的进度对话框。
///
/// 进入即开始 [ArchiveService.backfillMissingDecisionSnapshots]，按批次
/// 联网重分析并捕获决策快照；支持取消（当前批次结束后中止）。完成或取消后
/// pop 出 [BackfillSummary] 供调用方刷新界面。
class _BackfillDecisionDialog extends StatefulWidget {
  const _BackfillDecisionDialog({required this.db});
  final DatabaseService db;

  @override
  State<_BackfillDecisionDialog> createState() =>
      _BackfillDecisionDialogState();
}

class _BackfillDecisionDialogState extends State<_BackfillDecisionDialog> {
  int _done = 0;
  int _total = 0;
  bool _cancelled = false;
  BackfillSummary? _summary;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final summary = await ArchiveService.backfillMissingDecisionSnapshots(
      db: widget.db,
      shouldCancel: () => _cancelled,
      onProgress: (done, total) {
        if (mounted) setState(() {
          _done = done;
          _total = total;
        });
      },
    );
    if (!mounted) return;
    setState(() => _summary = summary);
    // 短暂停留让用户看到结果，再自动关闭。
    await Future.delayed(const Duration(milliseconds: 900));
    if (mounted) Navigator.of(context).pop(summary);
  }

  @override
  Widget build(BuildContext context) {
    final finished = _summary != null;
    return AlertDialog(
      backgroundColor: const Color(0xFF161B22),
      title: const Text('补录缺失决策',
          style: TextStyle(color: Color(0xFFF0F6FC))),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!finished) ...[
            Text(
              _total == 0 ? '正在准备...' : '已处理 $_done / $_total',
              style: const TextStyle(color: Color(0xFF8B949E)),
            ),
            const SizedBox(height: 12),
            if (_total > 0)
              LinearProgressIndicator(value: _done / _total),
          ] else
            Text(
              _summary!.total == 0
                  ? '没有需要补录的留档'
                  : '补录完成\n成功 ${_summary!.success} 条，失败 ${_summary!.failed} 条',
              style: const TextStyle(color: Color(0xFF8B949E)),
            ),
        ],
      ),
      actions: [
        if (!finished)
          TextButton(
            onPressed: () => setState(() => _cancelled = true),
            child: const Text('取消',
                style: TextStyle(color: Color(0xFF8B949E))),
          ),
      ],
    );
  }
}
