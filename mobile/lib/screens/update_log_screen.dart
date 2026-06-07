import 'package:flutter/material.dart';

class UpdateLogScreen extends StatelessWidget {
  const UpdateLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    final updates = [
      {
        'version': 'v2.3.0',
        'date': '2026-06-07',
        'changes': [
          'K线图新增BOLL布林带叠加显示（青色上下轨+白色中轨+半透明填充）',
          'K线图新增成交量柱状子图（红绿柱+VolMA5/MA10均线）',
          'K线图新增KDJ随机指标子图（K/D/J三线+超买超卖参考线）',
          '新增MACD背离检测（顶背离/底背离，30日窗口极值对比算法）',
          '新增量价背离检测（放量滞涨/缩量上涨/缩量止跌信号）',
          '新增布林带收口突破检测（带宽收窄+方向突破确认）',
          '新增8大核心战法分析（MACD金叉/背离、KDJ超卖、均线多头、布林突破等）',
          '新增"战法"标签页，展示活跃战法详情（入场/离场/止损规则+价位）',
          '新增7维多指标共振评分（MA/MACD/RSI/KDJ/BOLL/量价/背离）',
          '新增交易计划卡片（入场区间/目标价/止损价/盈亏比）',
          '新增"机会与风险"首页菜单，综合分析自选股买卖方向',
          '个股详情页新增股票快速切换功能（搜索+自选股快捷列表）',
          '分析Tab新增多指标共振可视化（进度条+各指标看多/看空标签）',
          '修复RSI6圆点过多、MACD缺少柱状图等问题',
          '修复买卖力度条文本溢出、MACD/RSI图表对齐等UI问题',
        ],
      },
      {
        'version': 'v2.2.0',
        'date': '2026-06-07',
        'changes': [
          '✨ 新增斐波那契回撤工具，支持5个关键回撤位（23.6%、38.2%、50%、61.8%、78.6%）',
          '🎯 优化斐波那契位置判断逻辑，准确区分阻力位和支撑位语义',
          '📊 修复78.6%回撤位错误显示为"阻力位上方"的问题（应为支撑位下方）',
          '💡 新增智能位置提示：突破新高/跌破新低/区间内精确判断',
          '🎨 优化技术指标可视化：价格标签带黑色半透明背景，清晰易读',
          '📈 支撑压力位：红色虚线(阻力) + 绿色虚线(支撑)，右侧显示价格',
          '📉 斐波那契线：白色虚线，61.8%黄金分割位金色突出显示',
          '🔧 修正斐波那契计算公式：swingHigh - (swingHigh - swingLow) × ratio',
          '📱 新增"指标"标签页，集中展示详细技术分析数据',
          '⚡ 完全本地化计算，零延迟实时分析，离线可用',
          '🛠️ 重构_KlinePainter，支持多层技术指标绘制',
          '📦 APK优化：MaterialIcons字体从1.6MB压缩至4KB（99.7%减少）',
        ],
      },
      {
        'version': 'v2.1.0',
        'date': '2026-06-07',
        'changes': [
          '修复总市值/流通市值显示偏差10000倍（单位万元→元转换）',
          '修复振幅始终显示为0的问题',
          '修复WebSocket轮询不获取PE/PB/市值数据',
          '修复WebSocket数据解析层级不匹配问题',
          '添加PB/PE数据合理性校验和调试日志',
          '修复预警对话框默认类型值不匹配的崩溃',
          '修复K线图价格范围为0时的渲染崩溃',
          '新增技术指标单元测试覆盖',
        ],
      },
      {
        'version': 'v2.0.9',
        'date': '2026-06-07',
        'changes': [
          '修复首页股票名称乱码问题（GBK编码解码）',
          '修复关于按钮点击无反应',
          '修复主力流入流出数据显示为0',
          '优化主力资金数据计算逻辑',
        ],
      },
      {
        'version': 'v2.0.8',
        'date': '2026-06-07',
        'changes': [
          '修复APK版本号一直显示2.0.0的问题',
          '修复腾讯API字段映射错误，市盈率市净率数据正常显示',
          '替换失效的新浪主力资金API为东方财富API',
          '修复自选页预警弹窗下拉选项初始值不匹配问题',
          '修复HTTP轮询获取实时行情数据功能',
          '修复K线历史数据涨跌额和涨跌幅为0的问题',
          '修复市场情绪API类型转换错误',
          '关于菜单移到首页右上角',
        ],
      },
      {
        'version': 'v2.0.7',
        'date': '2026-06-07',
        'changes': [
          '新增实时行情图，显示最近30个价格点走势',
          '新增估值分析和资金流向分析',
          '新增市盈率、市净率、主力流入流出数据',
          '优化K线图MACD和RSI子图显示',
          '预警条件显示中文和单位',
          '关于按钮移到首页右上角',
        ],
      },
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
                        update['version'] as String,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFef5350),
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