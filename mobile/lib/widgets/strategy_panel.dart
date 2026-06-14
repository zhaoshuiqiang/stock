import 'package:flutter/material.dart';
import '../models/stock_models.dart';
import '../analysis/strategy_engine.dart';

class StrategyPanel extends StatelessWidget {
  final List<HistoryKline> klines;
  final List<SignalItem> signals;

  const StrategyPanel({
    super.key,
    required this.klines,
    required this.signals,
  });

  @override
  Widget build(BuildContext context) {
    if (klines.isEmpty) {
      return const Center(child: Text('暂无分析数据', style: TextStyle(color: Colors.white54)));
    }

    final strategies = evaluateStrategies(klines, signals);
    final active = strategies.where((s) => s.isActive).toList();
    final inactive = strategies.where((s) => !s.isActive).toList();

    final buyCount = active.where((s) => s.type == 'buy').length;
    final sellCount = active.where((s) => s.type == 'sell').length;

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('战法共振', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Text('$buyCount看多', style: const TextStyle(color: Color(0xFFef5350), fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 12),
                  Text('$sellCount看空', style: const TextStyle(color: Color(0xFF26a69a), fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (active.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text('活跃战法', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          ...active.map((s) => _buildStrategyCard(s)),
        ],
        if (active.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text('当前无活跃战法信号', style: TextStyle(color: Colors.white54, fontSize: 13)),
            ),
          ),
        const SizedBox(height: 16),
        ExpansionTile(
          title: const Text('其他可用战法', style: TextStyle(color: Colors.white54, fontSize: 13)),
          backgroundColor: const Color(0xFF161B22),
          collapsedBackgroundColor: const Color(0xFF161B22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          children: inactive.map((s) => _buildStrategyCard(s, compact: true)).toList(),
        ),
      ],
    );
  }

  Widget _buildStrategyCard(TradingStrategy s, {bool compact = false}) {
    final categoryColors = {
      '趋势': const Color(0xFFef5350),
      '反转': const Color(0xFF26a69a),
      '量价': const Color(0xFFFFC107),
      '震荡': const Color(0xFF9C27B0),
    };
    final catColor = categoryColors[s.category] ?? Colors.grey;

    if (compact) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: catColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: catColor.withOpacity(0.5)),
              ),
              child: Text(s.category, style: TextStyle(color: catColor, fontSize: 10)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(s.name, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: catColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: catColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: catColor.withOpacity(0.5)),
                ),
                child: Text(s.category, style: TextStyle(color: catColor, fontSize: 10)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s.name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              if (s.signalStrength > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: s.type == 'buy' ? const Color(0xFFef5350).withOpacity(0.2) : const Color(0xFF26a69a).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    s.type == 'buy' ? '看多' : '看空',
                    style: TextStyle(
                      color: s.type == 'buy' ? const Color(0xFFef5350) : const Color(0xFF26a69a),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(s.description, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4)),
          const SizedBox(height: 8),
          _buildRuleRow('入场', s.entryRule, const Color(0xFFef5350)),
          const SizedBox(height: 4),
          _buildRuleRow('离场', s.exitRule, const Color(0xFFFFC107)),
          const SizedBox(height: 4),
          _buildRuleRow('止损', s.stopLossRule, const Color(0xFF26a69a)),
          if (s.entryPrice != null || s.targetPrice != null || s.stopLossPrice != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  if (s.entryPrice != null)
                    _buildPriceItem('入场价', s.entryPrice!),
                  if (s.targetPrice != null)
                    _buildPriceItem('目标价', s.targetPrice!),
                  if (s.stopLossPrice != null)
                    _buildPriceItem('止损价', s.stopLossPrice!),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRuleRow(String label, String text, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          alignment: Alignment.centerLeft,
          child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white54, fontSize: 11))),
      ],
    );
  }

  Widget _buildPriceItem(String label, double price) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        Text(price.toStringAsFixed(2), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
