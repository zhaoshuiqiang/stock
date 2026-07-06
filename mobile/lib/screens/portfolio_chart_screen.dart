import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/stock_models.dart';
import '../analysis/portfolio_snapshot_service.dart';

/// 收益率趋势图页面（v3.1）
/// 支持 日/周/月/季/全部 时间区间，展示累计收益率、当日收益率、总资产、市值趋势
class PortfolioChartScreen extends StatefulWidget {
  final Map<String, Position> positionMap;

  const PortfolioChartScreen({
    super.key,
    required this.positionMap,
  });

  @override
  State<PortfolioChartScreen> createState() => _PortfolioChartScreenState();
}

class _PortfolioChartScreenState extends State<PortfolioChartScreen> {
  final PortfolioSnapshotService _snapshotService = PortfolioSnapshotService();

  List<PortfolioSnapshot> _data = [];
  bool _isLoading = true;
  int _selectedDays = 30; // 7(周), 30(月), 90(季), 365(全部)
  int _chartMode = 0; // 0=累计收益率, 1=当日收益率, 2=总资产, 3=持仓市值
  PortfolioSnapshot? _selectedPoint;

  static const _upColor = Color(0xFFE74C3C);
  static const _downColor = Color(0xFF2ECC71);
  static const _accentColor = Color(0xFF58A6FF);
  static const _bgColor = Color(0xFF0D1117);
  static const _cardColor = Color(0xFF161B22);
  static const _textPrimary = Color(0xFFF0F6FC);
  static const _textSecondary = Color(0xFF8B949E);
  static const _borderColor = Color(0xFF30363D);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final data = await _snapshotService.getReturnTrend(
        positionMap: widget.positionMap,
        days: _selectedDays,
      );
      if (mounted) {
        setState(() {
          _data = data;
          _isLoading = false;
          _selectedPoint = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onRangeChanged(int days) {
    if (_selectedDays == days) return;
    _selectedDays = days;
    _loadData();
  }

  void _onModeChanged(int mode) {
    if (_chartMode == mode) return;
    setState(() {
      _chartMode = mode;
      _selectedPoint = null;
    });
  }

  double _getValue(PortfolioSnapshot s) {
    switch (_chartMode) {
      case 0:
        return s.totalPnlPct;
      case 1:
        return s.todayPnlPct;
      case 2:
        return s.totalAssets;
      case 3:
        return s.totalMarketValue;
      default:
        return s.totalPnlPct;
    }
  }

  String _valueLabel(double v) {
    if (_chartMode == 0 || _chartMode == 1) {
      return '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}%';
    }
    return '¥${v.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _cardColor,
        title: const Text('收益率趋势', style: TextStyle(color: _textPrimary)),
        iconTheme: const IconThemeData(color: _textPrimary),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _accentColor))
          : _data.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    _buildRangeSelector(),
                    _buildModeSelector(),
                    _buildSummaryCards(),
                    Expanded(child: _buildChart()),
                    if (_selectedPoint != null) _buildDetailPanel(),
                  ],
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.show_chart, size: 64, color: _textSecondary),
          const SizedBox(height: 16),
          const Text('暂无趋势数据',
              style: TextStyle(color: _textSecondary, fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            '请先添加持仓，系统将在收盘后自动记录每日快照',
            style: TextStyle(color: _textSecondary, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRangeSelector() {
    final ranges = [
      (7, '周'),
      (30, '月'),
      (90, '季'),
      (365, '全部'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: ranges.map((r) {
          final selected = _selectedDays == r.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(r.$2),
              selected: selected,
              onSelected: (_) => _onRangeChanged(r.$1),
              selectedColor: _accentColor.withOpacity(0.3),
              labelStyle: TextStyle(
                color: selected ? _accentColor : _textSecondary,
                fontSize: 13,
              ),
              side: BorderSide(
                color: selected ? _accentColor : _borderColor,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildModeSelector() {
    final modes = [
      (0, '累计收益率', Icons.trending_up),
      (1, '当日收益率', Icons.today),
      (2, '总资产', Icons.account_balance),
      (3, '持仓市值', Icons.account_balance_wallet),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: modes.map((m) {
            final selected = _chartMode == m.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(m.$3, size: 14,
                        color: selected ? _accentColor : _textSecondary),
                    const SizedBox(width: 4),
                    Text(m.$2),
                  ],
                ),
                selected: selected,
                onSelected: (_) => _onModeChanged(m.$1),
                selectedColor: _accentColor.withOpacity(0.2),
                labelStyle: TextStyle(
                  color: selected ? _accentColor : _textSecondary,
                  fontSize: 12,
                ),
                side: BorderSide(
                  color: selected ? _accentColor : _borderColor,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    if (_data.isEmpty) return const SizedBox.shrink();

    final values = _data.map(_getValue).toList();
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final lastVal = values.last;
    final firstVal = values.first;
    final periodChange = lastVal - firstVal;

    final isPct = _chartMode == 0 || _chartMode == 1;
    final color = lastVal >= 0 ? _upColor : _downColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard('最新', _valueLabel(lastVal), color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              '区间变化',
              isPct
                  ? '${periodChange >= 0 ? '+' : ''}${periodChange.toStringAsFixed(2)}%'
                  : '${periodChange >= 0 ? '+' : ''}¥${periodChange.toStringAsFixed(0)}',
              periodChange >= 0 ? _upColor : _downColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              '最高',
              _valueLabel(maxVal),
              _textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              '最低',
              _valueLabel(minVal),
              _textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: _textSecondary, fontSize: 10)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    if (_data.length < 2) {
      return Center(
        child: Text('数据不足，至少需要2个数据点',
            style: TextStyle(color: _textSecondary, fontSize: 13)),
      );
    }

    final spots = _data.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), _getValue(e.value));
    }).toList();

    final values = spots.map((s) => s.y).toList();
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final range = maxVal - minVal;
    final padding = range > 0 ? range * 0.1 : 1.0;

    final isPct = _chartMode == 0 || _chartMode == 1;
    final lineColor = _chartMode == 0
        ? _accentColor
        : _chartMode == 1
            ? Colors.orange
            : _upColor;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      child: LineChart(
        LineChartData(
          minY: minVal - padding,
          maxY: maxVal + padding,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (v) => FlLine(
              color: Colors.white10,
              strokeWidth: 0.5,
            ),
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 55,
                getTitlesWidget: (value, meta) {
                  return Text(
                    isPct
                        ? '${value.toStringAsFixed(1)}%'
                        : '¥${(value / 10000).toStringAsFixed(1)}万',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 10),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: (_data.length / 5).ceil().toDouble(),
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= _data.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      DateFormat('MM/dd').format(_data[idx].date),
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 9),
                    ),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => _cardColor,
              getTooltipItems: (touchedSpots) {
                if (touchedSpots.isEmpty) return [];
                final spot = touchedSpots.first;
                final idx = spot.spotIndex;
                if (idx < 0 || idx >= _data.length) return [];
                final s = _data[idx];
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _selectedPoint = s);
                });
                return [
                  LineTooltipItem(
                    '${DateFormat('MM-dd').format(s.date)}\n${_valueLabel(_getValue(s))}',
                    TextStyle(
                      color: lineColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ];
              },
            ),
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: isPct
                ? [
                    HorizontalLine(
                        y: 0, color: Colors.white24, strokeWidth: 1),
                  ]
                : [],
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: lineColor,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: lineColor.withOpacity(0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailPanel() {
    final s = _selectedPoint!;
    final pnlColor = s.totalPnl >= 0 ? _upColor : _downColor;
    final todayColor = s.todayPnl >= 0 ? _upColor : _downColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        border: Border(top: BorderSide(color: _borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                DateFormat('yyyy-MM-dd').format(s.date),
                style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _borderColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '快照',
                  style: TextStyle(color: _textSecondary, fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildDetailStat('总市值',
                  '¥${s.totalMarketValue.toStringAsFixed(2)}', _textPrimary),
              _buildDetailStat(
                '累计盈亏',
                '${s.totalPnl >= 0 ? '+' : ''}¥${s.totalPnl.toStringAsFixed(2)}',
                pnlColor,
              ),
              _buildDetailStat(
                '累计收益率',
                '${s.totalPnlPct >= 0 ? '+' : ''}${s.totalPnlPct.toStringAsFixed(2)}%',
                pnlColor,
              ),
              _buildDetailStat(
                '当日盈亏',
                '${s.todayPnl >= 0 ? '+' : ''}¥${s.todayPnl.toStringAsFixed(2)}',
                todayColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: _textSecondary, fontSize: 11)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
