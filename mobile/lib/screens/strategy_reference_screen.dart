import 'package:flutter/material.dart';
import '../analysis/strategy_builder.dart';
import '../analysis/strategy_engine.dart';

/// 战法说明页 — 展示全部13个战法的名称、描述和规则
class StrategyReferenceScreen extends StatelessWidget {
  const StrategyReferenceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final allStrategies = StrategyBuilder.getAllStrategyDefinitions();
    final theme = Theme.of(context);

    final shortTerm = allStrategies.where((s) => s.category == '短线').toList();
    final longTerm = allStrategies.where((s) => s.category == '长线').toList();
    final special = allStrategies.where((s) => s.category == '特殊').toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('战法说明（共${allStrategies.length}个）'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCategorySection(context, theme, '短线战法（1-5天，共${shortTerm.length}个）', shortTerm, Colors.orange),
          const SizedBox(height: 8),
          _buildCategorySection(context, theme, '长线战法（1-4周/1-3个月，共${longTerm.length}个）', longTerm, Colors.blue),
          const SizedBox(height: 8),
          _buildCategorySection(context, theme, '特殊战法（共${special.length}个）', special, Colors.purple),
        ],
      ),
    );
  }

  Widget _buildCategorySection(BuildContext context, ThemeData theme,
      String title, List<TradingStrategy> strategies, Color color) {
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: Container(
          width: 4, height: 32,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        title: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Text('${strategies.length}个战法', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
        children: strategies.map((s) => _buildStrategyItem(context, theme, s, color)).toList(),
      ),
    );
  }

  Widget _buildStrategyItem(BuildContext context, ThemeData theme,
      TradingStrategy s, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行：名称 + 强度
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                child: Text(s.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: color)),
              ),
              const SizedBox(width: 8),
              _buildStrengthBar(s.signalStrength),
              Text(' ${s.signalStrength}分', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 6),
          // 描述
          Text(s.description, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          // 关键信息行
          Row(
            children: [
              _buildInfoChip(theme, '周期', '${s.recommendedDuration}天', Colors.teal),
              const SizedBox(width: 6),
              _buildInfoChip(theme, '盈亏比', '${s.riskRewardRatio}', Colors.green),
              const SizedBox(width: 6),
              _buildInfoChip(theme, '回撤', '${(s.maxDrawdown * 100).toInt()}%', Colors.red),
              const SizedBox(width: 6),
              _buildInfoChip(theme, '连亏', '${s.consecutiveLossLimit}次', Colors.orange),
            ],
          ),
          const SizedBox(height: 8),
          // 规则
          _buildRuleRow(theme, '入场', s.entryRule, Colors.green),
          _buildRuleRow(theme, '离场', s.exitRule, Colors.red),
          _buildRuleRow(theme, '止损', s.stopLossRule, Colors.orange),
          const Divider(height: 16),
        ],
      ),
    );
  }

  Widget _buildStrengthBar(int strength) {
    final fraction = strength / 100.0;
    final color = fraction > 0.7 ? Colors.green : fraction > 0.5 ? Colors.orange : Colors.red;
    return Container(
      width: 60, height: 6,
      decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(3)),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: fraction,
        child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
      ),
    );
  }

  Widget _buildInfoChip(ThemeData theme, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text('$label:$value', style: theme.textTheme.bodySmall?.copyWith(color: color, fontSize: 11)),
    );
  }

  Widget _buildRuleRow(ThemeData theme, String label, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
            child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade800))),
        ],
      ),
    );
  }
}
