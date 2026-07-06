import 'package:flutter/material.dart';

class UpdateLogScreen extends StatelessWidget {
  const UpdateLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    final updates = [
      {
        'version': 'v3.1.20260707',
        'date': '2026-07-07',
        'changes': [
          '持仓页面盘中3秒实时刷新，行情延迟显著降低',
          '新增交易时段智能感知，非交易时段自动降频节省流量',
          '持仓盈亏汇总卡片化重设计，累计盈亏与当日盈亏视觉区分强化',
          '持仓卡片新增持仓天数显示，信息层级优化',
          '新增收益率趋势图（周/月/季/全部），支持数据钻取',
          '新增持仓每日快照记录，收盘后自动归档',
          '图表采用混合数据源：快照表+K线反算，首日即有历史数据',
          '图表支持累计收益率、当日收益率、总资产、持仓市值四种模式',
        ],
      },
      {
        'version': 'v3.0.20260706',
        'date': '2026-07-06',
        'changes': [
          '全面优化持仓功能：滑动删除、编辑持仓、资产汇总显示',
          '修复持仓Excel导入解析问题，支持动态表头识别和反推成本价',
          '修复回测功能，不依赖留档数据，直接使用持仓股票历史K线',
          '修复持仓卡片导航到个股详情的code格式问题',
          '导入前添加确认对话框，防止误操作清除数据',
          '自选页面持仓标志优化，显示持仓数量和盈亏信息',
          '优化留档页面合理评估逻辑（非对称阈值+手续费缓冲区）',
          '修复发现页面主线龙头显示问题，调整阈值并添加回退展示',
          '评分推荐机制优化：买入信号数量惩罚，降低假阳性',
        ],
      },
      {
        'version': 'v2.59.0',
        'date': '2026-07-06',
        'changes': [
          '自选页面新增持仓管理Tab，支持查看持仓股票及盈亏',
          '支持Excel导入持仓数据（兼容东方财富导出格式）',
          '新增AI持仓分析功能，提供仓位优化和调仓建议',
          '新增策略回测功能，支持6种技术指标策略回测',
          '优化可靠性评估逻辑，采用非对称阈值（买入/卖出方向匹配）',
          '修复发现页面主线龙头显示问题',
        ],
      },
      {
        'version': 'v1.0.0',
        'date': '2026-07-04',
        'changes': [
          'A股股票分析系统正式发布',
          '支持智谱AI、OpenRouter、CliProxyAPI多API切换',
          '技术分析引擎：MACD/KDJ/RSI/BOLL/MA等指标',
          '多空辩论AI分析，支持预设模板和自定义提问',
          '信号检测、策略回测、风险评估完整分析链路',
        ],
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('更新日志', style: textTheme.titleLarge),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: updates.length,
        itemBuilder: (context, index) {
          final update = updates[index];
          return Card(
            color: const Color(0xFF161B22),
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        update['version'] as String,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        update['date'] as String,
                        style: textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: (update['changes'] as List<String>)
                        .map((change) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.check_circle_outline,
                                    size: 16,
                                    color: Colors.green,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      change,
                                      style: textTheme.bodyMedium?.copyWith(color: Colors.grey[300]),
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}