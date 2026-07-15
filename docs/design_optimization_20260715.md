# 设计优化文档：可修复方向与"更准涨跌预测"方案

> 配套分析文档：`code_review_analysis_20260715.md`。
> 性质：仅设计，不改代码。给出优先级、落地路径、验证方法，以及面向短线的涨跌预测增强方案。
> 日期：2026-07-15

---

## 0. 设计原则

1. **先止血后增强**：先修会导致"错误信号/错误数字"的漏洞（1.1–1.7），再做增强。
2. **单一事实来源**：消除三套并行评分/推荐链（综合评分 B 链死代码、ExploreEngine、policy A 链）带来的口径漂移。
3. **短线优先**：把"次日/次 session 方向"做成一等公民，而不是只藏在 `directionScore` 里。
4. **可验证**：每个改动配单测 + 实盘数据核验（尤其金额单位、avgChangePct 口径）。
5. **不引入前视偏差**：所有预测特征只用 t-1 及之前信息。

---

## 1. 必须修复（P0，正确性）

### 1.1 修复 WR14 空值语义（对应 1.1）
- `HistoryKline.fromJson`：`wr14: json['wr14'] == null ? null : _parseDouble(json['wr14'])`（cci14 同理）。
- 同时给 `generateAnalysis` 入口加不变量：若 `data.last.wr14 == 0 && data.length>14` 且原始未算指标，则强制 `calcAllIndicators(data)`（对应 1.2）。
- 验证：用一个"无 wr14 字段"的 JSON K 线跑 `detectAllSignals`，断言不再产生"WR超买"卖信号。

### 1.2 修复命中率方向盲（对应 1.3）
- `recommendation_tracking` 表加 `direction`（`bullish/bearish/neutral`）与 `recommendation_level` 列（迁移 `oldVersion < 9`）。
- `RecommendationTracker.track` 写入时带上 `analysis.recommendationDecision` 的方向。
- `recommendation_stats_screen` 命中率改为按方向分别算：`bullish → dayN_return>0 为赢`，`bearish → dayN_return<0 为赢`。
- 验证：构造一条看空且下跌的记录，断言旧口径算"亏"、新口径算"赢"。

### 1.3 修复 ADX 短历史偏空（对应 1.4）
- `_detectBollSignals`：`adx14 == 0`（未就绪）时视为"未知/中性"，不做趋势判定，或把长度门限对 ADX 相关逻辑提到 ≥30。
- 验证：造 22 根 K 线、明显上升趋势的样本，断言上轨突破不再被判卖。

### 1.4 修复资金流 10 日因子（对应 1.5）
- `capital_flow_analyzer.dart:64-65`：`volFactor10d` 改为 `avgVol10 / 基准`，并复核 `mainNetFlow5d` 的 `*10` 是否真有量纲依据。
- 验证：单测给定 5 日/10 日均量不同，断言两因子不同。

### 1.5 修正 market_context 口径（对应 1.6 / 1.7）
- `avgChangePct`：改为**等权或流通市值加权**的全市场（行业+概念）涨跌幅均值；明确文档与代码一致。
- `indexChange`：要么改为真实上证点差，要么改名 `indexChangePct` 并对齐语义。
- 验证：用一组已知成分股涨跌幅，断言新 `avgChangePct` 与手算等权一致；检查下跌扣分逻辑在"大市值护盘日"下不再被低估。

---

## 2. 应当修复（P1，可信度与一致性）

| 项 | 改动 | 验证 |
|----|------|------|
| 1.8 RSI 越界 | 守卫改 `data.length < period+1` | 长度=period 单测不抛 |
| 1.9 MACD 阈值尺度盲 | `macdHist.abs()/close > k` 归一化 | 不同股价同阈值等价 |
| 1.10 置信度被覆盖 | 让显示值 = `ConfidenceCalculator` 输出，或显式说明二者差异并合并维度 | 单测断言显示值含回测/预测维度 |
| 1.11 双映射矛盾 | 删 `ComprehensiveScorer.recommendation` 文案映射，统一用 policy | grep 确认无遗留引用 |
| 1.12 留档去重/阈值 | `addArchive` 加 `UNIQUE(code, date)` 或写前查重；低于阈值不自动留档 | 重复归档单测 |
| 1.13 方向合理率 | 改为"存档时快照 vs 固定持有期收益"或显式标注"实时浮动" | UI 标注口径 |
| 1.14 里程碑收益 | 用交易日历 + 固定 `signalTradeDate + N 交易日` 索引历史收盘；分轮独立写入 | 稀疏轮询下单 5/10/20 不坍缩 |
| 1.15 新模型恒空 | 在扫票/打开统计页时调用 `DecisionTracker.refreshPending`，或隐藏该 tab | 真机跑后 outcomes 被评估 |
| 1.17/1.18 校验 | 抓行情时填 `updateTime`；校验器对"错但看似合理"数据降级/拒绝 | 冻结行情能被标记 |

---

## 3. 增强方向（P2，短线体验）

1. **7 维评分雷达图上线**：把孤儿 `ScoreRadarChart` 接入 `TradingDashboard`，展示 `dimensionScores` 拆解。
2. **建议/理由回到主决策面**：`suggestions`（操作/仓位）与 `reasons`（引擎理由）至少摘要展示在决策页。
3. **数据时效透明化**：决策页露出 `asOfTradeDate` + "数据陈旧"告警；Discover 卡片显示 `analyzedAt` 与陈旧标记。
4. **Discover 与详情页口径对齐**：统一 `ExploreEngine` 与 `generateAnalysis` 的评分/推荐来源，或明确标注"扫描快照/实时"差异。
5. **结构分析降门槛**：`accumulation` 用可用均線（如 MA20/MA30）替代强制 MA60，避免短历史低估吸筹。

---

## 4. "更准涨跌预测"设计方案（短线方向模型）

### 4.1 目标
把现有分散在 `directionScore` / `NextDayPredictor` / `NextSessionPredictor` 里的"方向判断"整合成一个**显式、可校准、可回测**的短线方向模块，产出：
- `direction`（涨/跌/震荡）
- `directionProbability`（0–1，可排序）
- `horizon`（1/3/5 日）
- `supportingEvidence`（可解释项，供 UI 展示）

### 4.2 特征工程（全部 t-1 及之前，无前视）
| 维度 | 特征 | 来源 |
|------|------|------|
| 趋势 | MA5/MA10/MA20 排列、价格相对 MA、ADX | technical_scorer / indicators |
| 反转 | RSI6/WR14/KDJ/BIAS6 的超买超卖+背离 | directional_evidence._reversalMomentum |
| 量价 | 量能因子、量价背离、换手 | capital_flow + signal_layer |
| 相对强度 | 个股 Alpha（相对 avgChangePct）、行业 RS | percentile + market_context |
| 资金 | 主力净流入加速度、5/10 日净额 | capital_flow_analyzer（修 1.5 后） |
| 共振 | 跨指标同向信号数（真正跨指标，非 1.22 的"同名"） | confluence |
| 结构 | bullTrend/bearTrend/accumulation/distribution | market_structure |
| 市场状态 | avgChangePct（修 1.7 后）、广度、情绪温度 | market_context + sentiment |
| 次日/次session | NextDay/NextSession 现有预测分 | 现有 predictor |

### 4.3 模型形态（推荐从规则加权起步，再上轻量校准）
1. **基线（立即可做）**：把 `directionScore` 的 5 个分量（trend 0.30 / reversal 0.25 / volumeFlow 0.20 / relStrength 0.15 / nextSession 0.10）作为可解释加权分，输出方向 + 概率（用历史分位映射到概率）。
2. **校准（第二步）**：用 `decision_outcomes`（修 1.15 后开始积累）做 **walk-forward 逻辑回归 / 梯度提升**，特征即 4.2，输出 `directionProbability`；禁止用未来标签训练。
3. **评估**：以方向准确率、多空分层收益率、牛市/熊市分别准确率、按 `directionProbability` 分桶的命中率曲线（reliability diagram）为指标。

### 4.4 关键纠偏（提升"准"的核心）
- **去动量偏置**：当前 ADX>30 多头时降低追高惩罚（1.x 动量偏置）会抬高追高风险。新模型对"已大涨+高乖离"样本应**降权或反向**，而不是加赏。
- **市场状态门控**：用修好的 `avgChangePct` 做状态分层，牛/熊/震荡分别校准阈值，避免单一阈值跨市失真。
- **次新股/ST 特殊处理**：短历史（<60）样本在结构维度降级，避免 1.4/1.20 的系统性偏差污染训练。
- **样本与时点**：训练/回测严格按交易日，禁用自然日（修 1.14）。

### 4.5 输出与展示
- 决策页顶部把"方向 + 概率"做成与综合评分并列的一等公民；
- 概率分桶展示历史命中率（reliability diagram），让用户知道"概率 0.7 时历史上真涨了多少"——这比单一"置信度"更可行动。

---

## 5. 实盘数据核验清单（上线前必须做）

| 核验项 | 方法 | 预期 |
|--------|------|------|
| 1.16 金额单位 | 同一标的分别走腾讯/Sina/EM，打印 `amount`，对照 `price*volume` | 三路一致，确认腾讯是否多乘 10000 |
| 1.7 avgChangePct | 取某交易日全市场成分股，手算等权 vs App 输出 | 一致或明确加权口径 |
| 1.6 indexChange | 打印字段，对照上证真实点差 | 语义正确 |
| 1.17 冻结行情 | 断网/改 TTL 后观察 `updateTime`/`isStaleQuote` | 能检测陈旧 |

---

## 6. 落地路线（建议顺序，分批提交）

- **批次 1（P0 正确性）**：1.1 + 1.2 + 1.4 + 1.5 + 1.7（含对应单测与实盘核验）→ 直接提升信号与数字正确性。
- **批次 2（P1 可信度）**：1.8–1.11、1.13–1.15、1.17/1.18 → 让统计/置信度可信。
- **批次 3（P2 体验）**：雷达图、建议回主面、时效透明、口径对齐。
- **批次 4（预测增强）**：4.x 短线方向模块，先基线后校准，配 reliability diagram。

> 每批次独立 PR + 单测 + 跑 `flutter test`（674+ 既有用例需全绿，注意 `hot_sectors_test` 为 API 依赖型既有失败，与本次无关）。

---

## 7. 风险与权衡
- 修 1.2（加 direction 列）涉及 DB 迁移，需保证旧记录兼容（迁移里对旧行 direction 置 neutral 或重推）。
- 修 1.7 改变 `avgChangePct` 会影响既有"下跌扣分"与 `getMarketAdjustmentFactor`，需回归综合评分既有用例。
- 预测增强的校准需足够样本，建议先上线基线（可解释加权），再据 `decision_outcomes` 积累切换校准模型。
