import 'package:flutter/material.dart';

class UpdateLogScreen extends StatelessWidget {
  const UpdateLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    final updates = [
      {
        'version': 'v3.0.20260706',
        'date': '2026-07-06',
        'changes': [
          '修复持仓Excel导入解析问题，支持动态表头识别',
          '优化留档页面合理评估逻辑（非对称阈值+手续费缓冲区）',
          '修复发现页面主线龙头显示问题，调整阈值并添加回退展示',
          '持仓Tab关联自选分析数据，显示推荐等级和评分',
          '主线龙头回退展示时标注【非主线精选】避免混淆',
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