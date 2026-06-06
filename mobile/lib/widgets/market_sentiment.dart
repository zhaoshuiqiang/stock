import 'package:flutter/material.dart';
import '../models/stock_models.dart';

class MarketSentimentBar extends StatelessWidget {
  final MarketSentiment sentiment;

  const MarketSentimentBar({super.key, required this.sentiment});

  @override
  Widget build(BuildContext context) {
    final total = sentiment.total;
    final upRatio = sentiment.upRatio;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.show_chart, color: Color(0xFFef5350), size: 20),
                SizedBox(width: 8),
                Text(
                  '市场情绪',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 涨跌比条
            if (total > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 8,
                  child: Row(
                    children: [
                      Flexible(
                        flex: (upRatio * 100).round(),
                        child: Container(color: const Color(0xFFef5350)),
                      ),
                      Flexible(
                        flex: ((1 - upRatio) * 100).round(),
                        child: Container(color: const Color(0xFF26a69a)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 统计数据
            Row(
              children: [
                _buildStatItem(
                  '上涨',
                  '${sentiment.upCount}',
                  const Color(0xFFef5350),
                ),
                _buildStatItem(
                  '下跌',
                  '${sentiment.downCount}',
                  const Color(0xFF26a69a),
                ),
                _buildStatItem(
                  '涨停',
                  '${sentiment.limitUpCount}',
                  const Color(0xFFef5350),
                ),
                _buildStatItem(
                  '跌停',
                  '${sentiment.limitDownCount}',
                  const Color(0xFF26a69a),
                ),
              ],
            ),

            if (sentiment.avgChangePct != 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildStatItem(
                    '平均涨跌',
                    '${sentiment.avgChangePct >= 0 ? '+' : ''}${sentiment.avgChangePct.toStringAsFixed(2)}%',
                    sentiment.avgChangePct >= 0
                        ? const Color(0xFFef5350)
                        : const Color(0xFF26a69a),
                  ),
                  _buildStatItem(
                    '总成交额',
                    _formatAmount(sentiment.totalAmount),
                    Colors.white,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _formatAmount(double val) {
    if (val >= 100000000) {
      return '${(val / 100000000).toStringAsFixed(2)}亿';
    } else if (val >= 10000) {
      return '${(val / 10000).toStringAsFixed(1)}万';
    }
    return val.toStringAsFixed(0);
  }
}