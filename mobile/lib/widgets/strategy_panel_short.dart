import 'package:flutter/material.dart';
import 'strategy_panel.dart';
import '../analysis/strategy_engine.dart';

/// 短线策略面板（6-8种）
class StrategyPanelShort extends StatelessWidget {
  final List<TradingStrategy> strategies;

  static const _categoryColors = {
    '短线': Color(0xFFef5350),
    '特殊': Color(0xFFFFC107),
  };

  const StrategyPanelShort({
    super.key,
    required this.strategies,
  });

  @override
  Widget build(BuildContext context) {
    return StrategyPanelConfigured(
      strategies: strategies,
      title: '短线策略（1-5天）',
      emptyText: '当前无短线策略信号',
      expansionTitle: '其他短线策略',
      categoryColors: _categoryColors,
    );
  }
}
