import 'package:flutter/material.dart';
import '../data/indicator_reference.dart';

class IndicatorReferenceScreen extends StatelessWidget {
  const IndicatorReferenceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = ['评分', '趋势', '震荡', '波动', '量能'];

    return Scaffold(
      appBar: AppBar(
        title: const Text('指标说明'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '常用技术指标详解',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '以下为系统使用的主要技术指标，包含计算公式、使用方法、解读和风险提示。',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ...categories.map((category) => _buildCategorySection(context, theme, category)),
        ],
      ),
    );
  }

  Widget _buildCategorySection(BuildContext context, ThemeData theme, String category) {
    final indicators = IndicatorReference.getByCategory(category);
    if (indicators.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _getCategoryColor(category).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: _getCategoryColor(category),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                category,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: _getCategoryColor(category),
                ),
              ),
              const Spacer(),
              Text('${indicators.length}个指标', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ...indicators.map((indicator) => _buildIndicatorCard(context, theme, indicator)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildIndicatorCard(BuildContext context, ThemeData theme, IndicatorInfo indicator) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        initiallyExpanded: false,
        title: Row(
          children: [
            Text(indicator.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getCategoryColor(indicator.category).withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(indicator.category, style: theme.textTheme.bodySmall?.copyWith(color: _getCategoryColor(indicator.category))),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoSection(theme, '计算公式', indicator.formula, Colors.blue),
                const SizedBox(height: 12),
                _buildInfoSection(theme, '指标简介', indicator.description, Colors.grey),
                const SizedBox(height: 12),
                _buildInfoSection(theme, '使用方法', indicator.usage, Colors.green),
                const SizedBox(height: 12),
                _buildInfoSection(theme, '指标解读', indicator.interpretation, Colors.teal),
                const SizedBox(height: 12),
                _buildInfoSection(theme, '风险提示', indicator.riskTips, Colors.orange),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(ThemeData theme, String title, String content, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
              child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          content,
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade800, height: 1.5),
        ),
      ],
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case '评分': return const Color(0xFFE67E22);
      case '趋势': return const Color(0xFF26a69a);
      case '震荡': return const Color(0xFF4caf50);
      case '波动': return const Color(0xFFff9800);
      case '量能': return const Color(0xFF9c27b0);
      default: return const Color(0xFF607d8b);
    }
  }
}