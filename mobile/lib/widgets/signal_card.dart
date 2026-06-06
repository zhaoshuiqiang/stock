import 'package:flutter/material.dart';
import '../models/stock_models.dart';

class SignalCard extends StatelessWidget {
  final SignalItem signal;

  const SignalCard({super.key, required this.signal});

  @override
  Widget build(BuildContext context) {
    final isBuy = signal.type == 'buy';
    final color = isBuy ? const Color(0xFF26a69a) : const Color(0xFFef5350);
    final bgColor = isBuy ? const Color(0xFF1b3a1b) : const Color(0xFF3a1b1b);

    return Card(
      color: bgColor,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 类型图标
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isBuy ? Icons.trending_up : Icons.trending_down,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),

            // 信号内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 类型和强度
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isBuy ? '买入' : '卖出',
                          style: TextStyle(
                            color: color,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildStrengthBadge(signal.strength),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // 指标和信号名
                  Text(
                    signal.indicator.isNotEmpty
                        ? '${signal.indicator} - ${signal.signal}'
                        : signal.signal,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  // 描述
                  if (signal.desc.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      signal.desc,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStrengthBadge(int strength) {
    Color color;
    IconData icon;
    String label;

    if (strength >= 80) {
      color = const Color(0xFF26a69a);
      icon = Icons.signal_cellular_alt;
      label = '强';
    } else if (strength >= 50) {
      color = Colors.orange;
      icon = Icons.signal_cellular_alt_2_bar;
      label = '中';
    } else {
      color = Colors.white54;
      icon = Icons.signal_cellular_alt_1_bar;
      label = '弱';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(color: color, fontSize: 12),
        ),
      ],
    );
  }
}