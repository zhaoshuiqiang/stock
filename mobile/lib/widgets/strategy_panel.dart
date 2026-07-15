import 'package:flutter/material.dart';
import '../models/stock_models.dart';
import '../analysis/strategy_engine.dart';
import '../analysis/market_structure_analyzer.dart';
import '../screens/strategy_reference_screen.dart';

class StrategyPanel extends StatelessWidget {
  final List<HistoryKline> klines;
  final List<SignalItem> signals;
  final MarketStructureResult? marketStructure;

  const StrategyPanel({
    super.key,
    required this.klines,
    required this.signals,
    this.marketStructure,
  });

  @override
  Widget build(BuildContext context) {
    if (klines.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38)),
              SizedBox(height: 12),
              Text('战法数据加载中...', style: TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final strategies = evaluateStrategies(klines, signals, marketStructure: marketStructure);
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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('战法共振', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StrategyReferenceScreen())),
                    child: const Icon(Icons.help_outline, color: Colors.white38, size: 16),
                  ),
                ],
              ),
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
        if (inactive.isNotEmpty)
          ExpansionTile(
            title: const Text('其他可用战法', style: TextStyle(color: Color(0xFFF0F6FC), fontSize: 13, fontWeight: FontWeight.w600)),
            iconColor: const Color(0xFF8B949E),
            collapsedIconColor: const Color(0xFF8B949E),
            backgroundColor: const Color(0xFF161B22),
            collapsedBackgroundColor: const Color(0xFF21262D),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            children: inactive.map((s) => _buildStrategyCard(s, compact: true)).toList(),
          ),
        if (inactive.isEmpty && active.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text('当前所有战法均处于活跃状态', style: TextStyle(color: Colors.white54, fontSize: 13)),
            ),
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
          // v3.23: 策略风控参数标签
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (s.recommendedDuration > 0)
                _buildMetaChip('持有${s.recommendedDuration}天', Colors.white54),
              if (s.riskRewardRatio > 0)
                _buildMetaChip('盈亏比1:${s.riskRewardRatio.toStringAsFixed(1)}', Colors.orange),
              if (s.maxDrawdown > 0)
                _buildMetaChip('最大回撤${(s.maxDrawdown * 100).toStringAsFixed(0)}%', const Color(0xFFef5350)),
            ],
          ),
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

  // v3.23: 策略元数据标签
  Widget _buildMetaChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 10)),
    );
  }
}

/// Configurable strategy panel that renders a list of [TradingStrategy] with
/// custom title, empty-state text, expansion-tile label, and category colors.
class StrategyPanelConfigured extends StatelessWidget {
  final List<TradingStrategy> strategies;
  final String title;
  final String emptyText;
  final String expansionTitle;
  final Map<String, Color> categoryColors;

  const StrategyPanelConfigured({
    super.key,
    required this.strategies,
    required this.title,
    required this.emptyText,
    required this.expansionTitle,
    required this.categoryColors,
  });

  @override
  Widget build(BuildContext context) {
    final active = strategies.where((s) => s.isActive).toList();
    final inactive = strategies.where((s) => !s.isActive).toList();

    final buyCount = active.where((s) => s.type == 'buy').length;
    final sellCount = active.where((s) => s.type == 'sell').length;

    return Column(
      children: [
        // 策略统计
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
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

        // 活跃策略
        if (active.isNotEmpty)
          ...active.map((s) => _buildStrategyCard(s, compact: false)),
        if (active.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(child: Text(emptyText, style: const TextStyle(color: Colors.white54, fontSize: 13))),
          ),

        const SizedBox(height: 16),

        // 其他可用策略
        if (inactive.isNotEmpty) ...[
          ExpansionTile(
            title: Text(expansionTitle, style: const TextStyle(color: Color(0xFFF0F6FC), fontSize: 13, fontWeight: FontWeight.w600)),
            iconColor: const Color(0xFF8B949E),
            collapsedIconColor: const Color(0xFF8B949E),
            backgroundColor: const Color(0xFF161B22),
            collapsedBackgroundColor: const Color(0xFF21262D),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            children: inactive.map((s) => _buildStrategyCard(s, compact: true)).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildStrategyCard(TradingStrategy s, {bool compact = false}) {
    final catColor = categoryColors[s.category] ?? Colors.grey;
    final isBuy = s.type == 'buy';

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
                    color: isBuy ? const Color(0xFFef5350).withOpacity(0.2) : const Color(0xFF26a69a).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isBuy ? '看多' : '看空',
                    style: TextStyle(
                      color: isBuy ? const Color(0xFFef5350) : const Color(0xFF26a69a),
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
                  if (s.entryPrice != null) _buildPriceItem('入场价', s.entryPrice!),
                  if (s.targetPrice != null) _buildPriceItem('目标价', s.targetPrice!),
                  if (s.stopLossPrice != null) _buildPriceItem('止损价', s.stopLossPrice!),
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
