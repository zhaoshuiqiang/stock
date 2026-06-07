import 'package:flutter/material.dart';
import '../analysis/indicators.dart';
import '../models/stock_models.dart';

/// 技术指标分析面板组件
/// 显示支撑压力位、斐波那契回撤等关键技术指标
class TechnicalIndicatorsPanel extends StatelessWidget {
  final List<HistoryKline> klines;
  
  const TechnicalIndicatorsPanel({
    Key? key,
    required this.klines,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (klines.length < 20) {
      return const Center(
        child: Text(
          '数据不足，需要至少20根K线',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    // 计算各项技术指标
    final supportResistance = calcSupportResistance(klines);
    final fibonacci = calcFibonacci(klines);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(context, '支撑压力位'),
          _buildSupportResistanceCard(supportResistance),
          const SizedBox(height: 16),
          _buildSectionTitle(context, '斐波那契回撤'),
          _buildFibonacciCard(fibonacci),
          const SizedBox(height: 16),
          _buildSectionTitle(context, '技术分析建议'),
          _buildTradingAdvice(supportResistance, fibonacci),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSupportResistanceCard(Map<String, dynamic> sr) {
    if (sr.isEmpty) {
      return _buildEmptyCard('暂无支撑压力位数据');
    }

    final currentPrice = sr['current_price'] ?? 0.0;
    final supports = (sr['support'] as List<dynamic>?)?.cast<double>() ?? [];
    final resistances = (sr['resistance'] as List<dynamic>?)?.cast<double>() ?? [];
    final nearestSupport = sr['nearest_support'] as double?;
    final nearestResistance = sr['nearest_resistance'] as double?;

    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('当前价格', '${currentPrice.toStringAsFixed(2)}', Colors.white),
            const Divider(color: Colors.grey),
            if (nearestSupport != null) ...[
              _buildInfoRow(
                '最近支撑',
                '${nearestSupport.toStringAsFixed(2)}',
                const Color(0xFF26a69a),
                icon: Icons.arrow_downward,
              ),
              _buildDistanceInfo(currentPrice, nearestSupport, true),
            ],
            if (nearestResistance != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                '最近压力',
                '${nearestResistance.toStringAsFixed(2)}',
                const Color(0xFFef5350),
                icon: Icons.arrow_upward,
              ),
              _buildDistanceInfo(currentPrice, nearestResistance, false),
            ],
            if (supports.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('所有支撑位:', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: supports.map((s) => _buildLevelChip(s.toStringAsFixed(2), const Color(0xFF26a69a))).toList(),
              ),
            ],
            if (resistances.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('所有压力位:', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: resistances.map((r) => _buildLevelChip(r.toStringAsFixed(2), const Color(0xFFef5350))).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFibonacciCard(Map<String, dynamic> fib) {
    if (fib.isEmpty) {
      return _buildEmptyCard('暂无斐波那契数据');
    }

    final swingHigh = fib['swing_high'] as double? ?? 0.0;
    final swingLow = fib['swing_low'] as double? ?? 0.0;
    final levels = fib['levels'] as Map<String, dynamic>? ?? {};
    final currentPosition = fib['current_position'] as String? ?? '无';

    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('区间高点', swingHigh.toStringAsFixed(2), Colors.white),
            _buildInfoRow('区间低点', swingLow.toStringAsFixed(2), Colors.white),
            const SizedBox(height: 8),
            _buildInfoRow('当前位置', currentPosition, Colors.amber),
            const Divider(color: Colors.grey),
            const Text('回撤位:', style: TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 8),
            ...levels.entries.map((entry) {
              final ratio = entry.key;
              final price = entry.value as double;
              final isGolden = ratio == '61.8%';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        if (isGolden)
                          const Icon(Icons.star, size: 14, color: Color(0xFFFFD700)),
                        const SizedBox(width: 4),
                        Text(
                          ratio,
                          style: TextStyle(
                            color: isGolden ? const Color(0xFFFFD700) : Colors.white70,
                            fontWeight: isGolden ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      price.toStringAsFixed(2),
                      style: TextStyle(
                        color: isGolden ? const Color(0xFFFFD700) : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildTradingAdvice(Map<String, dynamic> sr, Map<String, dynamic> fib) {
    final advices = <String>[];
    
    // 基于支撑压力位的建议
    if (sr.isNotEmpty) {
      final currentPrice = sr['current_price'] ?? 0.0;
      final nearestSupport = sr['nearest_support'] as double?;
      final nearestResistance = sr['nearest_resistance'] as double?;

      if (nearestSupport != null && nearestResistance != null) {
        final distToSupport = (currentPrice - nearestSupport) / currentPrice * 100;
        final distToResistance = (nearestResistance - currentPrice) / currentPrice * 100;

        if (distToSupport < 2) {
          advices.add('• 接近支撑位(${nearestSupport.toStringAsFixed(2)})，可考虑逢低买入');
        } else if (distToResistance < 2) {
          advices.add('• 接近压力位(${nearestResistance.toStringAsFixed(2)})，可考虑逢高减仓');
        }
      }
    }

    // 基于斐波那契的建议
    if (fib.isNotEmpty) {
      final currentPosition = fib['current_position'] as String? ?? '';
      if (currentPosition.contains('61.8')) {
        advices.add('• 处于黄金分割位附近，是关键支撑/阻力区域');
      } else if (currentPosition.contains('38.2') || currentPosition.contains('50.0')) {
        advices.add('• 处于重要回撤位，关注价格方向选择');
      }
    }

    if (advices.isEmpty) {
      advices.add('• 当前无明显明显交易信号，建议观望');
    }

    return Card(
      color: Colors.blue[900]?.withOpacity(0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: advices.map((advice) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(advice, style: const TextStyle(color: Colors.white70)),
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color valueColor, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              if (icon != null) Icon(icon, size: 16, color: valueColor),
              if (icon != null) const SizedBox(width: 4),
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistanceInfo(double current, double level, bool isSupport) {
    final distance = isSupport 
        ? (current - level) / current * 100 
        : (level - current) / current * 100;
    
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 2),
      child: Text(
        '距离: ${distance.toStringAsFixed(2)}%',
        style: TextStyle(
          color: distance < 2 ? Colors.orange : Colors.grey[600],
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildLevelChip(String price, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        price,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildEmptyCard(String message) {
    return Card(
      color: Colors.grey[900],
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(message, style: const TextStyle(color: Colors.grey)),
        ),
      ),
    );
  }
}
