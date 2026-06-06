import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../api/api_client.dart';
import '../models/stock_models.dart';

class ChartScreen extends StatefulWidget {
  final String code;

  const ChartScreen({super.key, required this.code});

  @override
  State<ChartScreen> createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  final _api = ApiClient();
  List<HistoryKline> _data = [];
  bool _isLoading = false;
  int _selectedRange = 120; // 60, 120, 360 (全部)

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final data = await _api.getHistory(widget.code, days: _selectedRange);
    if (mounted) {
      setState(() {
        _data = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _data.isEmpty
            ? const Center(child: Text('暂无K线数据', style: TextStyle(color: Colors.white38)))
            : Column(
                children: [
                  // Range selector
                  _buildRangeSelector(),
                  // K-line chart
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _buildKlineChart(),
                          const SizedBox(height: 8),
                          _buildVolumeChart(),
                          const SizedBox(height: 8),
                          _buildMacdChart(),
                          const SizedBox(height: 8),
                          _buildRsiChart(),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              );
  }

  Widget _buildRangeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _rangeButton('60天', 60),
          const SizedBox(width: 12),
          _rangeButton('120天', 120),
          const SizedBox(width: 12),
          _rangeButton('全部', 360),
        ],
      ),
    );
  }

  Widget _rangeButton(String label, int range) {
    final isSelected = _selectedRange == range;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedRange = range);
        _loadData();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFef5350) : const Color(0xFF16213e),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white54,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildKlineChart() {
    if (_data.isEmpty) return const SizedBox.shrink();

    final chartData = _data;
    final prices = chartData.expand((d) => [d.high, d.low]).toList();
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final priceRange = maxPrice - minPrice;

    return Container(
      height: 300,
      padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
      child: LineChart(
        LineChartData(
          minY: minPrice - priceRange * 0.05,
          maxY: maxPrice + priceRange * 0.05,
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
                reservedSize: 56,
                getTitlesWidget: (value, meta) => Text(
                  value.toStringAsFixed(2),
                  style: const TextStyle(color: Colors.white38, fontSize: 10),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                interval: (chartData.length / 4).ceil().toDouble(),
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= chartData.length) return const SizedBox.shrink();
                  return Text(
                    DateFormat('MM/dd').format(chartData[idx].date),
                    style: const TextStyle(color: Colors.white38, fontSize: 9),
                  );
                },
              ),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (spots) {
                return spots.map((spot) {
                  final idx = spot.x.toInt();
                  if (idx < 0 || idx >= chartData.length) return null;
                  final d = chartData[idx];
                  return LineTooltipItem(
                    '${DateFormat('MM/dd').format(d.date)}\nO:${d.open} H:${d.high}\nL:${d.low} C:${d.close}',
                    const TextStyle(color: Colors.white, fontSize: 11),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: [
            // K-line bar (simulated with line segments - each candle as vertical line)
            _buildCandleLine(chartData, minPrice, maxPrice),
            // MA5
            if (chartData.any((d) => d.ma5 > 0))
              _maLine(chartData, (d) => d.ma5, Colors.yellow, 'MA5'),
            // MA10
            if (chartData.any((d) => d.ma10 > 0))
              _maLine(chartData, (d) => d.ma10, Colors.orange, 'MA10'),
            // MA20
            if (chartData.any((d) => d.ma20 > 0))
              _maLine(chartData, (d) => d.ma20, Colors.purpleAccent, 'MA20'),
          ],
        ),
      ),
    );
  }

  LineChartBarData _buildCandleLine(List<HistoryKline> data, double minPrice, double maxPrice) {
    final spots = <FlSpot>[];

    for (int i = 0; i < data.length; i++) {
      spots.add(FlSpot(i.toDouble(), data[i].close));
    }

    return LineChartBarData(
      spots: spots,
      isCurved: false,
      color: Colors.white24,
      barWidth: 1,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    );
  }

  LineChartBarData _maLine(
    List<HistoryKline> data,
    double Function(HistoryKline) getter,
    Color color,
    String label,
  ) {
    final spots = <FlSpot>[];
    for (int i = 0; i < data.length; i++) {
      final val = getter(data[i]);
      if (val > 0) {
        spots.add(FlSpot(i.toDouble(), val));
      }
    }

    return LineChartBarData(
      spots: spots,
      isCurved: false,
      color: color,
      barWidth: 1,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(show: false),
    );
  }

  Widget _buildVolumeChart() {
    if (_data.isEmpty) return const SizedBox.shrink();

    final chartData = _data;
    final maxVol = chartData.map((d) => d.volume).reduce((a, b) => a > b ? a : b);

    return Container(
      height: 100,
      padding: const EdgeInsets.fromLTRB(0, 0, 8, 0),
      child: BarChart(
        BarChartData(
          maxY: maxVol * 1.1,
          barGroups: chartData.asMap().entries.map((entry) {
            final idx = entry.key;
            final d = entry.value;
            final isUp = d.close >= d.open;
            return BarChartGroupData(
              x: idx,
              barRods: [
                BarChartRodData(
                  toY: d.volume,
                  color: isUp ? const Color(0xFFef5350) : const Color(0xFF26a69a),
                  width: _barWidth(),
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
                reservedSize: 42,
                getTitlesWidget: (value, meta) => Text(
                  _formatVolume(value),
                  style: const TextStyle(color: Colors.white38, fontSize: 9),
                ),
              ),
            ),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  Widget _buildMacdChart() {
    if (_data.isEmpty) return const SizedBox.shrink();

    final chartData = _data.where((d) => d.macdDif != 0 || d.macdDea != 0).toList();
    if (chartData.isEmpty) return const SizedBox.shrink();

    final allVals = chartData.expand((d) => [d.macdDif, d.macdDea, d.macdHist]).toList();
    final minV = allVals.reduce((a, b) => a < b ? a : b);
    final maxV = allVals.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs();

    return Container(
      height: 120,
      padding: const EdgeInsets.fromLTRB(0, 0, 8, 0),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(left: 48, bottom: 4),
              child: Text('MACD', style: TextStyle(color: Colors.white54, fontSize: 11)),
            ),
          ),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: minV - range * 0.1,
                maxY: maxV + range * 0.1,
                lineBarsData: [
                  // MACD histogram
                  _histLine(chartData),
                  // DIF
                  _macdLine(chartData, (d) => d.macdDif, Colors.white),
                  // DEA
                  _macdLine(chartData, (d) => d.macdDea, Colors.yellow),
                ],
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
                      reservedSize: 42,
                      getTitlesWidget: (value, meta) => Text(
                        value.toStringAsFixed(2),
                        style: const TextStyle(color: Colors.white38, fontSize: 9),
                      ),
                    ),
                  ),
                  bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  LineChartBarData _macdLine(
    List<HistoryKline> data,
    double Function(HistoryKline) getter,
    Color color,
  ) {
    final spots = data.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), getter(e.value)))
        .toList();
    return LineChartBarData(
      spots: spots,
      isCurved: false,
      color: color,
      barWidth: 1,
      dotData: const FlDotData(show: false),
    );
  }

  LineChartBarData _histLine(List<HistoryKline> data) {
    return LineChartBarData(
      spots: data.asMap().entries.map((e) {
        return FlSpot(e.key.toDouble(), e.value.macdHist);
      }).toList(),
      isCurved: false,
      color: Colors.transparent,
      barWidth: 2,
      dotData: const FlDotData(show: false),
      belowBarData: BarAreaData(
        show: true,
        cutOffY: 0,
        applyCutOffY: true,
        color: const Color(0xFFef5350).withOpacity(0.3),
        spotsLine: BarAreaSpotsLine(
          show: true,
        ),
      ),
    );
  }

  Widget _buildRsiChart() {
    if (_data.isEmpty) return const SizedBox.shrink();

    final chartData = _data.where((d) => d.rsi6 > 0).toList();
    if (chartData.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 120,
      padding: const EdgeInsets.fromLTRB(0, 0, 8, 0),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(left: 48, bottom: 4),
              child: Text('RSI', style: TextStyle(color: Colors.white54, fontSize: 11)),
            ),
          ),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 100,
                lineBarsData: [
                  _rsiLine(chartData, (d) => d.rsi6, Colors.purpleAccent),
                  _rsiLine(chartData, (d) => d.rsi12, Colors.cyanAccent),
                  _rsiLine(chartData, (d) => d.rsi24, Colors.orangeAccent),
                ],
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) {
                    if (value == 30 || value == 70) {
                      return const FlLine(color: Colors.white24, strokeWidth: 1, dashArray: [5, 5]);
                    }
                    return FlLine(color: Colors.white10, strokeWidth: 0.5);
                  },
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      getTitlesWidget: (value, meta) => Text(
                        value.toInt().toString(),
                        style: const TextStyle(color: Colors.white38, fontSize: 9),
                      ),
                    ),
                  ),
                  bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  LineChartBarData _rsiLine(
    List<HistoryKline> data,
    double Function(HistoryKline) getter,
    Color color,
  ) {
    final spots = data.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), getter(e.value)))
        .toList();
    return LineChartBarData(
      spots: spots,
      isCurved: false,
      color: color,
      barWidth: 1,
      dotData: const FlDotData(show: false),
    );
  }

  double _barWidth() {
    if (_data.length <= 60) return 4;
    if (_data.length <= 120) return 2;
    return 1;
  }

  String _formatVolume(double vol) {
    if (vol >= 100000000) {
      return '${(vol / 100000000).toStringAsFixed(1)}亿';
    } else if (vol >= 10000) {
      return '${(vol / 10000).toStringAsFixed(1)}万';
    }
    return vol.toInt().toString();
  }
}