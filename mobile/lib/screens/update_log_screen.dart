import 'package:flutter/material.dart';

class UpdateLogScreen extends StatelessWidget {
  const UpdateLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    final updates = [
      {
        'version': 'v3.5.20260710',
        'date': '2026-07-10',
        'changes': [
          '新增板块数据概览功能：支持行业板块和概念板块双Tab切换，网格热力图布局展示涨跌',
          '板块卡片支持点击跳转查看板块内个股，支持下拉刷新数据',
          '首页热门板块区域新增「查看全部」按钮，快捷进入板块概览',
          '重构板块API：提取通用_fetchSectors方法，同时支持行业板块(fs=m:90+t:2)和概念板块(fs=m:90+t:3)',
          '移除未使用的新浪板块备用接口代码，精简API实现',
        ],
      },
      {
        'version': 'v3.4.20260710',
        'date': '2026-07-10',
        'changes': [
          '新增动量持续性分析：基于ADX趋势速率(40%)、量能确认(30%)、价格偏离度(30%)评估趋势可持续性',
          '新增次日涨跌概率预测：历史模式匹配算法，基于技术指标特征预测次日上涨概率',
          '新增预警信号检测：MACD/KDJ金叉死叉预警、MACD背离预警，提前捕捉潜在反转信号',
          '置信度计算升级为8维度：新增预测准确率反馈维度(8%)，提升评分可靠性',
          '预警信号权重调整：预警信号仅计50%权重，避免过度依赖未确认信号',
          '修复置信度计算浮点数精度问题，确保空信号场景下置信度精确为0.5',
        ],
      },
      {
        'version': 'v3.3.20260709',
        'date': '2026-07-09',
        'changes': [
          '新增短线交易分：独立评估1-10个交易日操作价值，重点关注短线信号、量价配合、资金流、实时涨跌幅和波动率',
          '强化追高风控：涨停、当日大涨、近5日涨幅过大、主力流出等场景会限制推荐等级，避免综合分高但短线不可追',
          '优化推荐解释：分析理由和操作建议新增短线交易分、短线风控触发原因和等待回踩/分时低吸提示',
          '修复策略分层：短线策略和长线策略现在按周期真实过滤，避免短线操作页面混入中长线策略',
          '优化探索候选池：短线模式下不再用PE/PB硬过滤亏损或高估值标的，改为风险标签和推荐上限处理',
          '新增回归测试：覆盖短线评分、追高封顶、策略周期过滤和探索估值策略',
        ],
      },
      {
        'version': 'v3.2.20260707',
        'date': '2026-07-07',
        'changes': [
          '评分透明化：移除隐性温和系数，评分直接反映真实计算，推荐等级更直观',
          '基本面增强：新增ROE（净资产收益率）因子，支持盈利能力8级评分',
          '评分可解释：分析理由新增维度贡献明细（技术↑X/资金↓Y），一目了然',
          '性能优化：新增4个数据库索引，高频查询提速',
          '全局缓存：K线/行情数据跨页面共享缓存，减少30-50%重复API请求',
          '缓存策略：K线缓存根据交易时段智能调整（盘中2分钟/盘后10分钟）',
          '推荐反馈：新增推荐效果反馈机制，支持用户对推荐结果评价',
        ],
      },
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
                        style:
                            textTheme.bodySmall?.copyWith(color: Colors.grey),
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
                                      style: textTheme.bodyMedium
                                          ?.copyWith(color: Colors.grey[300]),
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
