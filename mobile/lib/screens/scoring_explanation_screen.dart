import 'package:flutter/material.dart';

class ScoringExplanationScreen extends StatelessWidget {
  const ScoringExplanationScreen({super.key});

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
          _buildSectionTitle('综合评分体系'),
          const SizedBox(height: 8),
          _buildParagraph(
            '评分系统采用7维加权融合算法（短线模式8维），综合技术面、资金面、实时行情、共振信号、市场情绪、基本面、市场结构和板块动量等维度，最终输出1-10分的综合评分。惩罚机制采用3层乘法模型：追高风险因子×市场环境因子×预测修正因子。',
            theme,
          ),
          const SizedBox(height: 16),
          _buildWeightsCard(theme),
          const SizedBox(height: 16),
          _buildSectionTitle('各维度评分详解'),
          const SizedBox(height: 8),
          ..._buildDimensionCards(theme),
          const SizedBox(height: 16),
          _buildSectionTitle('评分调整机制'),
          const SizedBox(height: 8),
          ..._buildAdjustmentCards(theme),
          const SizedBox(height: 16),
          _buildSectionTitle('推荐等级对照表'),
          const SizedBox(height: 8),
          _buildRecommendationTable(theme),
          const SizedBox(height: 16),
          _buildSectionTitle('风险提示'),
          const SizedBox(height: 8),
          _buildParagraph(
            '评分仅供参考，不构成投资建议。市场有风险，投资需谨慎。评分系统基于历史数据和技术指标计算，不保证未来收益。',
            theme,
            isWarning: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildParagraph(String text, ThemeData theme, {bool isWarning = false}) {
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
    final weights = [
      {'name': '技术面', 'weight': 0.33, 'color': const Color(0xFF26a69a), 'desc': '信号强度+趋势+动量+量价+波动率'},
      {'name': '资金面', 'weight': 0.18, 'color': const Color(0xFF4caf50), 'desc': '主力资金净流入/流出'},
      {'name': '实时行情', 'weight': 0.16, 'color': const Color(0xFFff9800), 'desc': '当日涨跌幅+换手率+振幅'},
      {'name': '共振评分', 'weight': 0.12, 'color': const Color(0xFF9c27b0), 'desc': '跨指标多空一致性'},
      {'name': '市场情绪', 'weight': 0.10, 'color': const Color(0xFF03a9f4), 'desc': '新闻情感分析'},
      {'name': '基本面', 'weight': 0.07, 'color': const Color(0xFFe91e63), 'desc': 'PE/PB/市值等估值指标'},
      {'name': '市场结构', 'weight': 0.04, 'color': const Color(0xFF607d8b), 'desc': 'ADX趋势强度+均线对齐'},
      {'name': '板块动量(短线)', 'weight': 0.10, 'color': const Color(0xFF00bcd4), 'desc': '主线加成/退潮折扣/过热检测(仅短线模式)'},
    ];

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
            '7维权重分布',
            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...weights.map((w) => _buildWeightBar(w, theme)),
        ],
      ),
    );
  }

  Widget _buildWeightBar(Map<String, dynamic> w, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(w['name'], style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white)),
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
                      widthFactor: w['weight'],
                      child: Container(
                        decoration: BoxDecoration(
                          color: w['color'] as Color,
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
                  child: Text('${(w['weight'] * 100).round()}%', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(w['desc'] as String, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDimensionCards(ThemeData theme) {
    final dimensions = [
      {
        'title': '技术面评分 (0-10分)',
        'color': const Color(0xFF26a69a),
        'items': [
          '信号评分：买入/卖出信号强度加权，占30%',
          '趋势评分：均线排列+ADX趋势强度，占20%',
          '动量评分：RSI超买超卖+BIAS乖离率，占20%',
          '量价评分：量比+OBV趋势确认，占15%',
          '波动率评分：ATR波动幅度，占15%',
        ],
      },
      {
        'title': '资金面评分 (0-10分)',
        'color': const Color(0xFF4caf50),
        'items': [
          '主力资金净流入率>10%：+1.5分',
          '主力资金净流入率>5%：+1.0分',
          '主力资金净流入率>0%：+0.5分',
          '主力资金净流出率<-6%：-1.5分',
        ],
      },
      {
        'title': '实时行情评分 (0-10分)',
        'color': const Color(0xFFff9800),
        'items': [
          '涨幅2%-5%：最优区间，+2.0分',
          '涨幅5%-8%：中阳线，+1.0分（v2.38降低，避免诱多）',
          '涨幅>8%：大涨，+0.8分（抑制追高）',
          '换手率2%-5%：活跃区间，+0.8分',
          '振幅>8%：高波动，需结合量能判断',
        ],
      },
      {
        'title': '共振评分 (0-10分)',
        'color': const Color(0xFF9c27b0),
        'items': [
          '10个指标维度：MA/MACD/RSI/KDJ/BOLL/量价/WR/CCI/缺口/背离',
          '各指标权重不同：MA/MACD=1.5, VOL=1.2, BOLL=1.0, KDJ/RSI=0.8, WR/CCI=0.6',
          '背离信号权重提升至1.0（强反转预警）',
          '多头指标加权加分（上限+5），空头指标加权减分（下限-5）',
        ],
      },
      {
        'title': '基本面评分 (0-10分)',
        'color': const Color(0xFFe91e63),
        'items': [
          '市盈率(PE)：行业百分位排名',
          '市净率(PB)：行业百分位排名',
          '市值规模：大盘股稳定性加分',
          '熊市时权重提升30%（防守价值更大）',
        ],
      },
      {
        'title': '板块动量评分 (短线模式)',
        'color': const Color(0xFF00bcd4),
        'items': [
          '主线板块个股：加成1.0-1.3倍',
          '板块加速(accelerating)：+0.25分',
          '板块退潮(decelerating+跌>1%)：-0.30分',
          '板块过热：主线加成受限，仅+0.15',
          '板块涨停潮(≥3家涨停)：+0.15分',
          '板块龙头(相对强度>0.8)：+0.10分',
          '板块跟风(相对强度<0.3)：-0.10分',
          '退潮折扣：评分×0.85',
        ],
      },
      {
        'title': '市场结构评分 (0-10分)',
        'color': const Color(0xFF607d8b),
        'items': [
          '牛市结构：顺势做多',
          '熊市结构：防御策略',
          '震荡盘整：低买高卖',
          '吸筹结构：逢低布局',
          '派发结构：防范回落',
        ],
      },
    ];

    return dimensions.map((d) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(color: d['color'] as Color, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              Text(
                d['title'] as String,
                style: theme.textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...(d['items'] as List<String>).map((item) => Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Row(
              children: [
                Icon(Icons.check, size: 14, color: d['color'] as Color),
                const SizedBox(width: 6),
                Text(item, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
              ],
            ),
          )),
        ],
      ),
    )).toList();
  }

  List<Widget> _buildAdjustmentCards(ThemeData theme) {
    final adjustments = [
      {
        'title': '第1层：追高风险因子 [0.40, 1.0]',
        'color': const Color(0xFFef5350),
        'items': [
          '合并原追高惩罚+乖离率惩罚+趋势一致性',
          '涨停(>9.5%)：chaseP=0.65',
          '大涨(8%-9.5%)：chaseP=0.75',
          '连涨3天+涨幅5%：chaseP=0.92',
          'BIAS>8%：biasP=0.88(超买)/0.94(超卖减轻)',
          '近3日跌>5%：trendP=0.70(趋势一致性)',
          '动量保护：ADX>30+多头排列时惩罚减半',
          '三层乘积下限0.40',
        ],
      },
      {
        'title': '第2层：市场环境因子 [0.50, 1.0]',
        'color': const Color(0xFFff9800),
        'items': [
          '合并原大盘调整+下跌折扣+板块过热+金融股折扣',
          '大盘调整：marketAdjustment×0.4+positionFactor×0.6',
          '大盘跌>3%：declineFactor=0.80(逆市跑赢可豁免)',
          '板块过热：heatDiscount折扣',
          '金融股(券商/银行/保险)：×0.88',
          '总乘积clamp到[0.50, 1.0]',
        ],
      },
      {
        'title': '第3层：预测修正因子 [0.85, 1.05]',
        'color': const Color(0xFF4caf50),
        'items': [
          'NextDayPredictor下跌概率>60%：×0.85',
          'NextDayPredictor上涨概率>60%：×1.05',
          'NextSession下行风险>55%且置信度>0.5：×0.90',
          '总惩罚乘积不低于0.40（保底机制）',
        ],
      },
      {
        'title': '板块动量加成/折扣',
        'color': const Color(0xFF00bcd4),
        'items': [
          '主线板块：评分×mainLineBonus(1.0-1.3)',
          '板块退潮：评分×0.85',
          '板块过热：主线加成受限',
          '行业RS排名后30%：评分×0.90',
        ],
      },
    ];

    return adjustments.map((a) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: a['color'] as Color, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            a['title'] as String,
            style: theme.textTheme.titleSmall?.copyWith(color: a['color'] as Color, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          ...(a['items'] as List<String>).map((item) => Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('- $item', style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey)),
          )),
        ],
      ),
    )).toList();
  }

  Widget _buildRecommendationTable(ThemeData theme) {
    final recommendations = [
      {'score': '1', 'level': '强烈卖出', 'action': '坚决卖出，清仓离场'},
      {'score': '2', 'level': '卖出', 'action': '建议卖出，降低仓位'},
      {'score': '3', 'level': '谨慎卖出', 'action': '可考虑卖出，观望为主'},
      {'score': '4', 'level': '偏空观望', 'action': '观望，等待时机'},
      {'score': '5', 'level': '偏多观望', 'action': '观望，关注机会'},
      {'score': '6', 'level': '谨慎买入', 'action': '可少量买入，控制风险'},
      {'score': '7', 'level': '买入', 'action': '建议买入，合理仓位'},
      {'score': '8', 'level': '强烈买入', 'action': '积极买入，把握机会'},
      {'score': '9-10', 'level': '强烈买入', 'action': '积极买入，把握机会'},
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
              _buildTableHeader('评分', theme),
              _buildTableHeader('推荐', theme),
              _buildTableHeader('操作建议', theme),
            ],
          ),
          ...recommendations.map((r) => Row(
            children: [
              _buildTableCell(r['score'] as String, theme, width: 50),
              _buildTableCell(r['level'] as String, theme, width: 80, isLevel: true),
              _buildTableCell(r['action'] as String, theme, width: 0),
            ],
          )),
        ],
      ),
    );
  }

  Widget _buildTableHeader(String text, ThemeData theme) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: const BoxDecoration(color: Color(0xFF21262D)),
        child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildTableCell(String text, ThemeData theme, {int width = 0, bool isLevel = false}) {
    final color = isLevel ? _getLevelColor(text) : Colors.white70;
    return width > 0
        ? SizedBox(
            width: width.toDouble(),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color)),
            ),
          )
        : Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color)),
            ),
          );
  }

  Color _getLevelColor(String level) {
    if (level.contains('买入')) return const Color(0xFFef5350);
    if (level.contains('卖出')) return const Color(0xFF26a69a);
    return Colors.grey;
  }
}
