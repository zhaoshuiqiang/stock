import 'package:flutter/material.dart';
import 'strategy_panel.dart';
import '../analysis/strategy_engine.dart';

/// 长线策略面板（6-8种）
class StrategyPanelLong extends StatelessWidget {
  final List<TradingStrategy> strategies;

  static const _categoryColors = {
    '长线': Color(0xFF26a69a),
    '特殊': Color(0xFFFFC107),
  };

  const StrategyPanelLong({
    super.key,
    required this.strategies,
  });

  @override
  Widget build(BuildContext context) {
    return StrategyPanelConfigured(
      strategies: strategies,
      title: '长线策略（1-4周/1-3个月）',
      emptyText: '当前无长线策略信号',
      expansionTitle: '其他长线策略',
      categoryColors: _categoryColors,
    );
  }
}
