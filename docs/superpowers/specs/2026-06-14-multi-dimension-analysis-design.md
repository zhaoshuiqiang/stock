# 多维度分析优化设计 - 参考 TradingAgents

## 背景

参考 GitHub TradingAgents 项目的多智能体分析架构，从炒股用户角度优化本项目。
核心借鉴：多维度分析融合、信号对抗验证、分层决策、增强置信度。

## 约束

- 纯客户端架构，无后端服务器，无 LLM API 调用
- 所有分析基于规则引擎，利用已有 API 数据
- 不破坏现有功能，增量改造

## 新增模块

### 1. 基本面分析器 `analysis/fundamental_analyzer.dart`

输入：`QuoteData`（PE/PB/市值/主力资金/换手率）
输出：`FundamentalScore`

评分体系（0-10分）：
- 估值评分(40%): PE分位(0-10) + PB分位(0-10)
  - PE: <8→9, 8-15→7, 15-30→5, 30-50→3, 50-80→2, >80→1, 负值→3
  - PB: <0.8→9, 0.8-1.5→7, 1.5-3→5, 3-5→3, 5-10→2, >10→1, 负值→2
- 资金评分(35%): 主力净流入率 + 大单占比
  - 净流入率>10%→9, 5-10%→7, 0-5%→5, -5~0%→3, <-10%→1
- 流动性评分(25%): 换手率 + 成交额
  - 换手率1-5%→8, 5-10%→6, >10%→4, <1%→3

### 2. 信号对抗验证器 `analysis/signal_validator.dart`

输入：`List<SignalItem>` + `QuoteData` + `HistoryKline`
输出：`List<ValidatedSignal>`

对每个信号生成反向视角：
- 买入信号 → Bear反对理由（RSI超买? 量价背离? 均线空头? PE过高? 主力流出?）
- 卖出信号 → Bull支撑理由（RSI超卖? 估值偏低? 主力流入? 均线多头?）

置信度调整：
- 0条反对 → confidence不变
- 1条弱反对 → confidence -0.05
- 1条强反对 → confidence -0.10
- 2+条反对 → confidence -0.15

### 3. 新闻情绪分析器 `analysis/news_sentiment_analyzer.dart`

输入：新闻标题列表（来自 `ApiClient.getStockNews()`）
输出：`NewsSentiment`

关键词规则：
- 利好(+1~+3): 业绩增长/中标/回购/增持/分红/突破/创新高/涨停/利好/签约/订单
- 利空(-1~-3): 亏损/减持/违规/处罚/下跌/破位/风险/退市/质押/诉讼/爆雷/警示
- 中性(0): 其他

情绪评分 = sum(关键词权重) / max(新闻数, 1)，归一化到 [-10, +10]

### 4. 多维融合评分（改造 signal_engine.dart）

当前：技术50% + 实时30% + 共振20%
新权重：技术35% + 基本面20% + 情绪15% + 实时15% + 共振15%

当基本面/情绪数据缺失时，权重自动重分配给技术面和实时行情。

### 5. 增强置信度（改造 signal_engine.dart）

当前：信号比例 + PE/PB微调
新公式：
- 信号一致性(30%): 买卖信号比例偏离度
- 基本面支撑(25%): 基本面评分与推荐方向一致时加分
- 情绪面确认(20%): 新闻情绪与推荐方向一致时加分
- 市场环境(15%): 大盘趋势与推荐方向一致时加分
- 信号新鲜度(10%): 近期信号权重高于远期

## 数据模型扩展

`AnalysisResult` 新增字段：
- `fundamentalScore`: FundamentalScore? 基本面评分详情
- `newsSentiment`: NewsSentiment? 新闻情绪
- `validatedSignals`: List<ValidatedSignal> 对抗验证后的信号
- `confidenceBreakdown`: Map<String, double> 置信度分项

新增模型：
- `FundamentalScore`: valuationScore, capitalFlowScore, liquidityScore, totalScore, factors
- `ValidatedSignal`: signal, bearPoints/bullPoints, adjustedConfidence
- `NewsSentiment`: score(-10~+10), positiveCount, negativeCount, neutralCount, keyFactors

## 文件变更清单

| 文件 | 操作 | 说明 |
|------|------|------|
| analysis/fundamental_analyzer.dart | 新增 | 基本面分析器 |
| analysis/signal_validator.dart | 新增 | 信号对抗验证器 |
| analysis/news_sentiment_analyzer.dart | 新增 | 新闻情绪分析器 |
| analysis/signal_engine.dart | 修改 | 多维融合评分+增强置信度 |
| models/stock_models.dart | 修改 | 新增数据模型 |
| core/app_version.dart | 修改 | 版本号 2.18.0 → 2.19.0 |
| screens/update_log_screen.dart | 修改 | 更新日志 |
