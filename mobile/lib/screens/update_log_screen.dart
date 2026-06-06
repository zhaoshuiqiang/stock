import 'package:flutter/material.dart';

class UpdateLogScreen extends StatelessWidget {
  const UpdateLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    final updates = [
      {
        'version': 'v2.0.6',
        'date': '2026-06-07',
        'changes': [
          '新增实时行情功能，支持WebSocket推送',
          '股票详情页面显示"实时"标签和更新时间',
          '新增成交量和成交额显示',
          '支持实时价格变动更新',
        ],
      },
      {
        'version': 'v2.0.5',
        'date': '2026-06-07',
        'changes': [
          '修复搜索功能，支持中文搜索（如"东山精密"）',
          '修复搜索页面底部文字颜色，确保清晰可见',
          '修复K线图显示，绘制真实蜡烛图',
          '修复首页股票名称乱码问题',
          '修复API GBK编码解码问题',
        ],
      },
      {
        'version': 'v2.0.4',
        'date': '2026-06-07',
        'changes': [
          '修复界面白色问题，使用深色主题',
          '修复实时行情API URL构建错误',
          '修复历史K线API URL构建错误',
          '修复自选/信号/提醒页面主题适配',
        ],
      },
      {
        'version': 'v2.0.3',
        'date': '2026-06-07',
        'changes': [
          '优化搜索页面主题颜色适配',
          '优化设置页面主题颜色适配',
          '优化K线图主题颜色适配',
        ],
      },
      {
        'version': 'v2.0.2',
        'date': '2026-06-06',
        'changes': [
          '添加实时行情数据展示',
          '添加K线图展示',
          '添加MACD指标',
          '添加RSI指标',
        ],
      },
      {
        'version': 'v2.0.1',
        'date': '2026-06-06',
        'changes': [
          '添加股票搜索功能',
          '添加自选股票功能',
          '添加价格提醒功能',
        ],
      },
      {
        'version': 'v2.0.0',
        'date': '2026-06-05',
        'changes': [
          '全新版本发布',
          '支持沪深两市股票查询',
          '支持技术指标分析',
          '支持信号提醒',
        ],
      },
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('更新日志', style: textTheme.titleLarge),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: updates.map((update) {
          return Card(
            color: const Color(0xFF16213e),
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        update['version']!,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFef5350),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        update['date']!,
                        style: textTheme.bodySmall?.copyWith(color: Colors.grey[400]),
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
                                children: [
                                  const Icon(Icons.check_circle, size: 14, color: Colors.green),
                                  const SizedBox(width: 8),
                                  Text(change, style: textTheme.bodyMedium),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}