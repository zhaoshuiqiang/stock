import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// 推荐评分历史趋势图（最近20条记录）
class ScoreTrendChart extends StatelessWidget {
  final List<Map<String, dynamic>> trendData; // [{date: DateTime, score: double}]

  const ScoreTrendChart({super.key, required this.trendData});

  @override
  Widget build(BuildContext context) {
    if (trendData.length < 2) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '推荐记录不足，趋势图需要至少2条历史记录',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      );
    }

    final scores = trendData.map((d) => (d['score'] as num).toDouble()).toList();
    final dataCount = trendData.length;
    final maxScore = scores.reduce((a, b) => a > b ? a : b).clamp(6.0, 10.0);
    final minScore = scores.reduce((a, b) => a < b ? a : b).clamp(0.0, 5.0);
    // 给图表留一点上下边距
    final chartMin = (minScore - 0.5).clamp(0.0, 10.0);
    final chartMax = (maxScore + 0.5).clamp(0.0, 10.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
      height: 130,
      child: LineChart(
        LineChartData(
          minY: chartMin,
          maxY: chartMax,
          gridData: FlGridData(
            show: true,
            drawHorizontalLine: true,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.white.withOpacity(0.05),
              strokeWidth: 0.5,
            ),
            drawVerticalLine: false,
          ),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 2,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    '${value.toInt()}',
                    style: const TextStyle(color: Colors.white30, fontSize: 9),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 18,
                interval: dataCount <= 5 ? 1 : dataCount <= 10 ? 2 : (dataCount / 5).ceilToDouble(),
                getTitlesWidget: (value, meta) {
                  final idx = value.toInt();
                  if (idx < 0 || idx >= dataCount) return const SizedBox.shrink();
                  final date = trendData[idx]['date'] as DateTime;
                  return Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${date.month}/${date.day}',
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
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF21262D),
              tooltipRoundedRadius: 6,
              getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                final idx = spot.x.toInt();
                final date = idx >= 0 && idx < dataCount
                    ? trendData[idx]['date'] as DateTime
                    : null;
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(1)}分\n${date != null ? "${date.month}/${date.day}" : ""}',
                  const TextStyle(color: Colors.white, fontSize: 11),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(dataCount, (i) => FlSpot(i.toDouble(), scores[i])),
              isCurved: true,
              curveSmoothness: 0.3,
              color: const Color(0xFF58A6FF),
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: dataCount <= 15,
                getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                  radius: 3,
                  color: _scoreColor(scores[index]),
                  strokeWidth: 0,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFF58A6FF).withOpacity(0.08),
              ),
            ),
            // 6分参考线
            if (chartMax >= 6 && chartMin <= 6)
              LineChartBarData(
                spots: [
                  FlSpot(0, 6),
                  FlSpot((dataCount - 1).toDouble(), 6),
                ],
                isCurved: false,
                color: Colors.orange.withOpacity(0.4),
                barWidth: 0.8,
                dotData: const FlDotData(show: false),
                dashArray: [4, 4],
              ),
          ],
        ),
      ),
    );
  }

  Color _scoreColor(double score) {
    if (score >= 7) return const Color(0xFFE74C3C); // red: strong
    if (score >= 6) return Colors.orange;
    if (score >= 4) return const Color(0xFF58A6FF); // blue: neutral
    return const Color(0xFF2ECC71); // green: weak
  }
}
