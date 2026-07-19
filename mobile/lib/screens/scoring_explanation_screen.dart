import 'package:flutter/material.dart';

import '../analysis/directional_evidence_builder.dart';
import '../analysis/recommendation_thresholds.dart';

/// 评分逻辑说明 —— 如实反映线上生效的「短线决策引擎 v3」（P1.1）。
///
/// 权重与阈值均从引擎真实常量渲染
/// （[DirectionalEvidenceBuilder.componentWeights] / [RecommendationThresholds.defaults]），
/// 从根本上避免说明文档与实现漂移（历史上本页描述的是已不生效的 7 维影子路径）。
class ScoringExplanationScreen extends StatelessWidget {
  const ScoringExplanationScreen({super.key});

  static const Map<String, String> _dimLabels = {
    trendComponentKey: '趋势',
    reversalMomentumComponentKey: '反转动量',
    volumeFlowComponentKey: '量价流',
    relativeStrengthComponentKey: '相对强度',
    nextSessionComponentKey: '次交易日预测',
    sectorMomentumComponentKey: '板块动量',
  };
  static const Map<String, String> _dimDesc = {
    trendComponentKey: '均线排列 + ADX 趋势强度',
    reversalMomentumComponentKey: 'RSI / KDJ / BIAS 超买超卖反转',
    volumeFlowComponentKey: '量比 + 主力资金方向',
    relativeStrengthComponentKey: '个股相对大盘强弱',
    nextSessionComponentKey: '次交易日涨跌预测',
    sectorMomentumComponentKey: '板块轮动 / 主线 / 退潮',
  };
  static const List<Color> _dimColors = [
    Color(0xFF26a69a),
    Color(0xFF4caf50),
    Color(0xFFff9800),
    Color(0xFF9c27b0),
    Color(0xFF03a9f4),
    Color(0xFF00bcd4),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: const Text('评分逻辑说明'),
        backgroundColor: const Color(0xFF161B22),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle('评分与推荐如何生成'),
          const SizedBox(height: 8),
          _paragraph(
            '线上展示的评分与推荐来自「短线决策引擎 v3」：先由方向证据构建器把 6 个维度加权成方向分 '
            'directionScore（-100 ~ +100），再按强度分档映射为 9 级推荐，并叠加交易质量 / 风险 / '
            '证据置信度三道执行门控，最终折算成 1-10 分展示。综合评分（技术 / 资金 / 情绪等）作为其中'
            '一个上下文输入参与，不再单独决定推荐。',
            theme,
          ),
          const SizedBox(height: 16),
          _sectionTitle('方向证据维度权重'),
          const SizedBox(height: 8),
          _buildWeightsCard(theme),
          const SizedBox(height: 16),
          _sectionTitle('推荐等级对照（按方向分）'),
          const SizedBox(height: 8),
          _buildRecommendationTable(theme),
          const SizedBox(height: 16),
          _sectionTitle('执行门控（拦截"方向对但质量差"）'),
          const SizedBox(height: 8),
          ..._buildGateCards(theme),
          const SizedBox(height: 16),
          _sectionTitle('胜率校准'),
          const SizedBox(height: 8),
          _paragraph(
            '决策落库后按 1 / 3 / 5 日跟踪真实结果，使用 Wilson 置信区间与 Beta-Binomial 后验，在样本'
            '充足（每桶 ≥ 100 且 ≥ 20 个交易日）时给出该方向分档的真实命中概率区间，用于校准展示分与'
            '实际胜率的偏差（ECE）。',
            theme,
          ),
          const SizedBox(height: 16),
          _sectionTitle('风险提示'),
          const SizedBox(height: 8),
          _paragraph(
            '评分仅供参考，不构成投资建议。市场有风险，投资需谨慎。评分基于历史数据与技术指标计算，不'
            '保证未来收益。',
            theme,
            isWarning: true,
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _paragraph(String text, ThemeData theme, {bool isWarning = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isWarning ? const Color(0xFF3d2929) : const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isWarning ? const Color(0xFFef5350) : const Color(0xFF30363D),
          width: 0.5,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isWarning ? const Color(0xFFef5350) : Colors.white70,
          fontSize: 14,
          height: 1.6,
        ),
      ),
    );
  }

  Widget _buildWeightsCard(ThemeData theme) {
    final entries = DirectionalEvidenceBuilder.componentWeights.entries.toList();
    final maxW = entries.fold<double>(
        0, (m, e) => e.value > m ? e.value : m);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '6 维方向证据（合计 100%）',
            style: TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < entries.length; i++)
            _weightBar(
              _dimLabels[entries[i].key] ?? entries[i].key,
              _dimDesc[entries[i].key] ?? '',
              entries[i].value,
              maxW > 0 ? entries[i].value / maxW : 0,
              _dimColors[i % _dimColors.length],
              theme,
            ),
        ],
      ),
    );
  }

  Widget _weightBar(String name, String desc, double weight, double barFactor,
      Color color, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(name,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.white)),
              ),
              Expanded(
                flex: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Container(
                    height: 20,
                    decoration: BoxDecoration(
                      color: const Color(0xFF21262D),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: barFactor.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text('${(weight * 100).round()}%',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.grey)),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(desc,
                  style:
                      theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendationTable(ThemeData theme) {
    final t = RecommendationThresholds.defaults;
    String f(double v) => v.toStringAsFixed(0);
    final rows = <(String, String, String)>[
      ('≥ +${f(t.strongBullish)}', '强烈买入', '积极参与'),
      ('+${f(t.bullish)} ~ +${f(t.strongBullish)}', '买入', '合理仓位'),
      ('+${f(t.cautiousBullish)} ~ +${f(t.bullish)}', '谨慎买入', '小量参与'),
      ('+12 ~ +${f(t.cautiousBullish)}', '偏多观望', '观望偏多'),
      ('-12 ~ +12', '观望', '中性等待'),
      ('-${f(t.cautiousBullish)} ~ -12', '偏空观望', '观望偏空'),
      ('-${f(t.bullish)} ~ -${f(t.cautiousBullish)}', '谨慎卖出', '减仓'),
      ('-${f(t.strongBullish)} ~ -${f(t.bullish)}', '卖出', '卖出'),
      ('≤ -${f(t.strongBullish)}', '强烈卖出', '清仓'),
    ];
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D), width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _tableHeader('方向分', theme),
              _tableHeader('推荐', theme),
              _tableHeader('操作', theme),
            ],
          ),
          for (final r in rows)
            Row(
              children: [
                _tableCell(r.$1, theme, width: 96),
                _tableCell(r.$2, theme, width: 72, isLevel: true),
                _tableCell(r.$3, theme, width: 0),
              ],
            ),
        ],
      ),
    );
  }

  List<Widget> _buildGateCards(ThemeData theme) {
    final t = RecommendationThresholds.defaults;
    String f(double v) => v.toStringAsFixed(0);
    final cards = <(String, String)>[
      (
        '强烈买入门控',
        '交易质量 ≥ ${f(t.strongBullishQualityMin)} 且 风险 ≤ ${f(t.strongBullishRiskMax)} 且 '
            '证据置信度 ≥ ${f(t.strongBullishConfidenceMin)}，任一不满足则降级为「偏多观望」'
      ),
      (
        '买入门控',
        '交易质量 ≥ ${f(t.bullishQualityMin)} 且 风险 ≤ ${f(t.bullishRiskMax)} 且 '
            '证据置信度 ≥ ${f(t.bullishConfidenceMin)}'
      ),
      (
        '谨慎买入门控',
        '交易质量 ≥ ${f(t.cautiousBullishQualityMin)} 且 风险 ≤ ${f(t.cautiousBullishRiskMax)}'
      ),
      (
        '空头证据门控',
        '证据置信度 ≥ ${f(t.bearishConfidenceMin)} 方可给出可执行的卖出建议，否则降级为「偏空观望」'
      ),
    ];
    return [
      for (final c in cards)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFff9800), width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.$1,
                  style: theme.textTheme.titleSmall?.copyWith(
                      color: const Color(0xFFff9800),
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(c.$2,
                  style:
                      theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
            ],
          ),
        ),
    ];
  }

  Widget _tableHeader(String text, ThemeData theme) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: const BoxDecoration(color: Color(0xFF21262D)),
        child: Text(text,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _tableCell(String text, ThemeData theme,
      {int width = 0, bool isLevel = false}) {
    final color = isLevel ? _levelColor(text) : Colors.white70;
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Text(text,
          style: theme.textTheme.bodySmall?.copyWith(color: color)),
    );
    return width > 0
        ? SizedBox(width: width.toDouble(), child: child)
        : Expanded(child: child);
  }

  Color _levelColor(String level) {
    if (level.contains('买入')) return const Color(0xFFef5350);
    if (level.contains('卖出')) return const Color(0xFF26a69a);
    return Colors.grey;
  }
}
