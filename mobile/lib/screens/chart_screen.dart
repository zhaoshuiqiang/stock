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
  HistoryKline? _selectedKline;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final data = await _api.getStockHistory(widget.code, days: _selectedRange);
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
            ? Center(child: Text('暂无K线数据', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white38)))
            : Column(
                children: [
                  _buildRangeSelector(),
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
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                  _buildSelectedInfo(),
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

    return GestureDetector(
      onTapDown: (details) {
        final containerWidth = (context.findRenderObject() as RenderBox?)?.size.width ?? 300;
        final padding = 56.0;
        final chartWidth = containerWidth - padding;
        final barWidth = chartWidth / chartData.length * 0.6;
        final gap = chartWidth / chartData.length * 0.4;
        
        final x = details.localPosition.dx - padding;
        if (x >= 0) {
          final idx = (x / (barWidth + gap)).floor();
          if (idx >= 0 && idx < chartData.length) {
            setState(() {
              _selectedKline = chartData[idx];
            });
          }
        }
      },
      child: Container(
        height: 300,
        padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
        child: Stack(
          children: [
            LineChart(
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
                lineTouchData: LineTouchData(enabled: true),
                lineBarsData: [
                  if (chartData.any((d) => d.ma5 > 0))
                    _maLine(chartData, (d) => d.ma5, Colors.yellow, 'MA5'),
                  if (chartData.any((d) => d.ma10 > 0))
                    _maLine(chartData, (d) => d.ma10, Colors.orange, 'MA10'),
                  if (chartData.any((d) => d.ma20 > 0))
                    _maLine(chartData, (d) => d.ma20, Colors.purpleAccent, 'MA20'),
                ],
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _KlinePainter(chartData),
              ),
            ),
          ],
        ),
      ),
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

  Widget _buildSelectedInfo() {
    if (_selectedKline == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: const Color(0xFF0f3460),
        child: const Text('点击K线查看详情', style: TextStyle(color: Colors.grey, fontSize: 13)),
      );
    }

    final kline = _selectedKline!;
    final isUp = kline.close >= kline.open;
    final color = isUp ? const Color(0xFFef5350) : const Color(0xFF26a69a);
    final change = kline.close - kline.open;
    final changePct = kline.open > 0 ? (change / kline.open * 100) : 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF0f3460),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat('yyyy-MM-dd').format(kline.date),
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('开盘', style: TextStyle(color: Colors.grey, fontSize: 11)),
                  Text(kline.open.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('收盘', style: TextStyle(color: Colors.grey, fontSize: 11)),
                  Text(kline.close.toStringAsFixed(2), style: TextStyle(color: color, fontSize: 13)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('最高', style: TextStyle(color: Colors.grey, fontSize: 11)),
                  Text(kline.high.toStringAsFixed(2), style: const TextStyle(color: Color(0xFFef5350), fontSize: 13)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('最低', style: TextStyle(color: Colors.grey, fontSize: 11)),
                  Text(kline.low.toStringAsFixed(2), style: const TextStyle(color: Color(0xFF26a69a), fontSize: 13)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('成交量', style: TextStyle(color: Colors.grey, fontSize: 11)),
                  Text(_formatVolume(kline.volume), style: const TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('涨跌额', style: TextStyle(color: Colors.grey, fontSize: 11)),
                  Text('${isUp ? '+' : ''}${change.toStringAsFixed(2)}', style: TextStyle(color: color, fontSize: 13)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('涨跌幅', style: TextStyle(color: Colors.grey, fontSize: 11)),
                  Text('${isUp ? '+' : ''}${changePct.toStringAsFixed(2)}%', style: TextStyle(color: color, fontSize: 13)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('换手率', style: TextStyle(color: Colors.grey, fontSize: 11)),
                  Text('${kline.turnover.toStringAsFixed(2)}%', style: const TextStyle(color: Colors.white, fontSize: 13)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KlinePainter extends CustomPainter {
  final List<HistoryKline> data;
  final Paint upPaint = Paint()..color = const Color(0xFFef5350);
  final Paint downPaint = Paint()..color = const Color(0xFF26a69a);
  final Paint linePaint = Paint()..strokeWidth = 1;

  _KlinePainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final prices = data.expand((d) => [d.high, d.low]).toList();
    final minPrice = prices.reduce((a, b) => a < b ? a : b);
    final maxPrice = prices.reduce((a, b) => a > b ? a : b);
    final priceRange = maxPrice - minPrice;
    final padding = 56.0;
    final chartWidth = size.width - padding;
    final chartHeight = size.height;
    final barWidth = chartWidth / data.length * 0.6;
    final gap = chartWidth / data.length * 0.4;

    for (int i = 0; i < data.length; i++) {
      final d = data[i];
      final isUp = d.close >= d.open;
      final paint = isUp ? upPaint : downPaint;
      linePaint.color = paint.color;

      final x = padding + i * (barWidth + gap) + barWidth / 2;
      final highY = chartHeight - ((d.high - minPrice) / priceRange) * chartHeight;
      final lowY = chartHeight - ((d.low - minPrice) / priceRange) * chartHeight;
      final openY = chartHeight - ((d.open - minPrice) / priceRange) * chartHeight;
      final closeY = chartHeight - ((d.close - minPrice) / priceRange) * chartHeight;

      canvas.drawLine(Offset(x, highY), Offset(x, lowY), linePaint);

      final bodyTop = isUp ? closeY : openY;
      final bodyBottom = isUp ? openY : closeY;
      final bodyLeft = x - barWidth / 2;

      if (isUp) {
        canvas.drawRect(
          Rect.fromLTWH(bodyLeft, bodyTop, barWidth, bodyBottom - bodyTop),
          paint,
        );
      } else {
        paint.style = PaintingStyle.stroke;
        paint.strokeWidth = 1;
        canvas.drawRect(
          Rect.fromLTWH(bodyLeft, bodyTop, barWidth, bodyBottom - bodyTop),
          paint,
        );
        paint.style = PaintingStyle.fill;
      }
    }
  }

  @override
  bool shouldRepaint(_KlinePainter oldDelegate) => oldDelegate.data != data;
}