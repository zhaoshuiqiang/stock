# 代码评审分析文档（短线操作用户视角）

> 评审范围：决策页面功能逻辑、评分推荐机制、指标显示机制、留档分析机制、股票推荐机制，以及支撑这些功能的所有指标与数据层代码。
> 评审方式：以代码评审分析师角度查找代码漏洞；以短线操作用户角度分析功能的完善性 / 准确性 / 时效性 / UI 排布合理性。
> 结论性质：仅分析，不改代码。配套设计文档见 `design_optimization_20260715.md`。
> 日期：2026-07-15

---

## 0. 总览

整套引擎是纯客户端规则引擎，`generateAnalysis()`（`signal_engine.dart:284-714`）按 16 步串起信号检测 → 结构/分位分析 → 6 个打分器 → 风险/机会 → 回测 → 策略 → 短线决策 → 置信度 → 理由/建议。

但代码实际存在 **两套并行的"推荐"驱动链**：
- **A 链（生产真实生效）**：`ShortTermDecisionEngine.evaluate()` → `RecommendationPolicy.evaluate()` 产出 `recommendationDecision.label`（最终 `recommendation`）+ `recommendationDecision.legacyScore`（最终 `totalScore`）。
- **B 链（遗留/死代码）**：`ComprehensiveScorer.combine()` 的 1–10→文案映射，仅被旧 plan 文件引用，不在生产渲染路径。

此外还有 **Discover 批量扫描用的第三套打分路径**（`ExploreEngine`），与单股 `generateAnalysis` 不保证一致。

> 这是后续大量"显示值不一致""评分口径漂移"问题的根源。

---

## 1. 代码漏洞（按严重度排序）

### 1.1 【严重】WR14 序列化丢空值，导致假"WR超买"卖出信号
- `HistoryKline.fromJson`（`stock_models.dart:924`）：`wr14: QuoteData._parseDouble(json['wr14'])`，键缺失时返回 **`0`（非 null）**。
- `_detectWRSignals`（`signal_detector.dart:209-234`）：看到 `wr14 != null` 且 `0 < 20` → 对**任何缺少 wr14 的缓存 K 线** 都发出"WR超买"**卖**信号。
- 根因：`wr14`/`cci14` 在模型里是 `double?`，但序列化把 null 塌缩成 0.0，丢失了空/有值语义。
- CCI 免疫（0 不算极端）；`directional_evidence_builder._reversalMomentum`（line 337）有 `wr14 > 0` 守卫所以安全——只有信号检测器误触发。
- 影响：缓存/历史 JSON 路径下的 WR 信号整体失真，且方向与真实超买相反（把无数据当成深度超买卖出）。

### 1.2 【严重】`generateAnalysis` 强依赖调用方先算指标，但无断言
- `generateAnalysis`（`signal_engine.dart:313-319`）直接 `SignalLayer.detectAllSignals(data)` + `getIndicatorSummary(data)`，**自己不调用 `calcAllIndicators`**。
- 现场路径（quote_screen 等）确实会先 `calcAllIndicators`，但**任何把缓存 JSON K 线直接喂给 `generateAnalysis` 的路径**都会让所有指标字段停在默认值（0.0 / null）→ 全部基于指标的信号静默失效或乱触发（与 1.1 叠加）。
- 建议方向：在入口加 `assert` 或强制重算；或文档化不变量。

### 1.3 【严重】推荐命中率"方向盲"
- `recommendation_stats_screen.dart:275`：`wins = records.where((r) => r['day20_return'] > 0)`；`hitRate = wins/total`。
- `recommendation_tracking` 表（`database_service.dart:527-551`）**没有 direction / recommendation_level 列**。
- 后果：看空（卖出）且正确下跌的标的，`day20_return < 0` → 被算成**亏损**。熊市下系统性低估胜率，该指标只对看多标的"成立"。
- 无法在不改 schema 的前提下修正。

### 1.4 【高】ADX 门限在短历史下系统性偏空
- `_detectBollSignals`（`signal_detector.dart:277-311`）：`isTrending = last.adx14 > 25`。
- ADX(14) 需要约 29 根 K 线才稳定（`calcDMI`），但信号入口门限是 `data.length < 20 → []`（line 8）。
- 后果：20–28 根 K 线的股票 ADX 往往还是 0 → 上轨突破被判**卖（超买）**、下轨突破判**买**，与趋势无关 → 系统性偏空偏差。

### 1.5 【高】资金流分析器 `volFactor10d` 复制粘贴错误
- `capital_flow_analyzer.dart:64-65`：`volFactor5d` 与 `volFactor10d` 计算式完全相同（都是 `avgVol5/avgVol10`）。
- `mainNetFlow5d` 缩放（line 66）是随意的 `*10`。
- 影响：10 日量能因子实际等于 5 日，10 日维度分析失真。

### 1.6 【高】`indexChange` 语义写错
- `market_context_provider.dart`：把 `(shIndexPct + szIndexPct)/2`（两个**百分比**的平均）赋给 `indexChange`，而 `MarketContext` 模型注释称其为"上证指数**涨跌额**"（点差）。
- 当前仅用于 `.isFinite` 校验（`market_regime_classifier.dart:144`），影响有限，但字段语义错误，易在后续改动中被误用。

### 1.7 【高】market_context 的 `avgChangePct` 不是等权市场均值
- `market_context_provider.dart:180-186`：用**行业成分股数加权**的行业涨跌幅均值（且只覆盖行业板块、排除概念板块）。
- 后果：大盘股集中的行业被过度加权，可能**低估**小盘/概念普涨的真实广度。该值直接喂给 `getMarketAdjustmentFactor`（模型 L1208）与综合评分的"下跌扣分"逻辑 → 大市值护盘日可能被低估为"未下跌"，从而少扣分。

### 1.8 【中】`calcRSI` 潜在越界
- `indicators.dart:137` 守卫 `if (data.length < period) continue;`，但种子循环 `for(i=1;i<=period;i++)`（line 152）读取 `gains[period]`，需要 `length >= period+1`。
- `length == period` 时抛 `RangeError`。当前被 `detectLayeredSignals` 的 ≥20 门限掩盖，但独立调用（如单测/特殊路径）会触发。

### 1.9 【中】MACD 置信度阈值对价格尺度盲
- `signal_detector.dart:141`：`if (last.macdHist.abs() > 1) confidence += 0.05`。`macdHist` 是价格单位，¥5 与 ¥50 股票阈值含义完全不同。

### 1.10 【中】置信度"显示值 ≠ 计算器输出"
- `signal_engine.dart:494`：`confidenceScore = shortTermDecision.evidenceConfidence/100`，**覆盖了** `:476` `ConfidenceCalculator.calculate` 的结果。
- `confResult` 仅用于 `validatedSignals`/`confidenceBreakdown`，不进入最终显示的"置信度"。
- 后果：展示的置信度忽略了回测胜率、预测准确率、对抗性校验这些最该影响可信度的维度——而这些恰恰是 `ConfidenceCalculator` 设计来衡量的。

### 1.11 【中】两套文案映射互相矛盾
- `ComprehensiveScorer.combine`（214-226）与 `RecommendationPolicy._legacyScoreOf`（190-211）的 1–10→文案不一致：同为 7 分，前者给"买入"，后者给"谨慎买入"；前者无"观望"档。
- 生产用的是 policy 映射，combine 的映射是误导性的遗留代码。建议统一为单一来源并删除 `compResult.recommendation`。

### 1.12 【中】数据库层面：留档无去重、无阈值
- 留档创建仅在 `watchlist_screen.dart`（`_archiveOppItem` 579-595 / `_batchArchiveSelected` 641-658 / `_oneClickArchive` 720-737），直接 `ArchiveRecord(recommendation: r.recommendation, score: r.score, …, archivedAt: DateTime.now())`，**无评分阈值、无按 code 去重**。
- 后果：同一只票可反复留档，放大后续统计；且 `archive_records` 无 `direction` 列，方向靠事后 `recommendation.contains(...)` 字符串匹配重推（详见 1.13）。

### 1.13 【中】留档"方向合理率"是实时盈亏快照，不是命中率
- `archive_reliability_evaluator.dart`：`getReliabilityLevel`（124-167）对看多：`reasonable`(命中) = `priceChangePct >= 0`（line 143），`veryReasonable` = `>= threshold`（line 142）；对看空：命中 = `priceChangePct <= 0`（line 152）。
- `archive_screen.dart:757-760` 用**当前实时价** `currentPrice` 每次刷新重算。
- 后果：① 这是一个会随行情波动的 P/L 快照，不是固定命中率；② 在上涨市系统性偏高（任何"平/涨"的买入留档都算命中）；③ 老留档只需 `>=0` 即算 reasonable，而 `veryReasonable` 阈值随天数变大（line 77），老票据进一步虚高。

### 1.14 【中】`updateReturns` 里程碑收益坍缩 + 用自然日
- `recommendation_tracker.dart:302-336`：
  - day5/day10/day20 三个 `if` 互相独立，同一轮调用可同时写入**同一最新实时价**；若 5→10 日之间 App 没被轮询，day5/day10/day20 会坍缩成同一个"较晚日"的收益。
  - `daysSince = now.difference(signalDate).inDays`（自然日），与 `recommendation_stats_screen.dart:206` 声称的"20交易日"矛盾。
  - 收益取实时价而非收盘，含盘中噪声。
- 后果：里程碑收益不可信，回测/统计意义受损。

### 1.15 【中】新模型可靠性在生产中是"死"的
- `decision_tracker.dart:86-122` `refreshPending`（唯一会评估 pending outcome 的调用）**从不被生产代码调用**（全仓 grep 仅在 `test/decision_tracker_test.dart:71` 出现）。
- 后果：`decision_outcomes` 永远 `pending`，"新模型"标签页恒为空（`recommendation_stats_screen.dart` 的"新模型" tab）。

### 1.16 【中】行情层金额单位疑似放大 10000 倍
- `api_client.dart:316`：`amount: _parseDouble(parts[37]) * 10000`（腾讯路径）；
- 同文件 Sina 回退 `parts[9]` **没有 ×10000**（line 396）。
- `data_validator.dart:98-110` 假设 `amount ≈ price × volume × 100`（元）。Sina 吻合；腾讯的 ×10000 会使 `ratio ≈ 10000`，触发 `suspiciousUnit` 警告（severity 0.6，非致命 → 不修正）。
- 高度疑似腾讯 `parts[37]` 本身已是元，L316 多乘了 10000。需对照实盘 API 核实（见设计文档验证项）。

### 1.17 【中】`isStaleQuote` 是死代码 → 冻结行情不可检测
- `data_validator.dart:282-292` 用 `updateTime` 判新鲜度，但**所有行情抓取路径都不设置 `updateTime`**（默认 null）。
- 后果：新鲜度只能靠缓存 TTL（5 秒报价）；若数据源冻结/返回陈旧值，App 无感知。

### 1.18 【中】校验器只"标记"不"纠正/拒绝"
- `validateQuote`（40-163）对异常只设 `confidence` 不修正或拒绝。10000× 金额等"错但看似合理"的数据以警告形式流入分析。

### 1.19 【低】分位分析器文档与代码权重不符 + 脆弱匹配
- `percentile_analyzer.dart`：注释（line 271）写行业 RS = 低估30%+动量30%+活跃20%+低PB20%，代码（292-296）是 0.25+0.25+0.20+0.20+0.10。
- `rsi12` 被当作 "RSI14近似"（line 174）。
- 行业匹配按股票名子串（line 227），脆弱。

### 1.20 【低】结构分析对短历史低估"吸筹"
- `market_structure_analyzer.dart:202-203`：`accumulation` 需 `data.length >= 60` 才有 MA60，否则默认 consolidation（score 5），对 <60 根 K 线静默低估吸筹结构。

### 1.21 【低】置信度计算器注释/代码权重错位 + 双重 clamp
- `confidence_calculator.dart`：注释信号一致性的 35%（line 47）/ 拆解 32%（line 233）/ 代码 29%（line 169）三处不一致；基本面"13%"注释 vs 11% 代码；最终 0.3–0.95 再 0.2–0.95 双重 clamp（178/200）。

### 1.22 【低】展示层小问题
- `TradeLevels` 风险回报显示为 `"1:${rr}"`（":479"）→ "1:3.0" 略误导；`ShortTermDecisionPanel` 的"方向强度"裸 double 无量纲。
- RSI 检测器用 70/30，而 `getIndicatorSummary`（633/635）用 80/20，阈值口径不一致。
- `_detectConfluenceSignals`（474-504）"resonance"命名误导：只在**同一指标名内**计数 boost，多数指标只发 ≤1 信号，几乎不触发；真正的跨指标共振由别处处理。

---

## 2. 指标显示机制

- 指标公式本身（`indicators.dart` 的 MACD/RSI/KDJ/WR14/CCI14/BIAS/BOLL/MA/EMA/ATR/OBV/DMI）**均符合教科书标准**，无公式错误（BOLL 用样本 std `/(n-1)` 与多数平台 `/(n)` 的微小差异不算 bug）。
- **无前视偏差**：所有指标只用过去+当根收盘，回测之外不存在未来函数。
- 显示侧问题：
  - `ScoreRadarChart`（`score_radar_chart.dart`）**孤儿组件**：7 维 `dimensionScores`（`signal_engine.dart:513-527`）已计算但**从未可视化**，决策页看不到评分拆解。
  - `AnalysisResult.suggestions` / `reasons` **不在 TradingDashboard 渲染**，只出现在 `signals_screen` / AI tab——可执行交易计划与理由被移出主决策面。
  - 指标阈值口径不一致（RSI 70/30 vs 80/20）。

---

## 3. 评分推荐机制（短线用户视角）

### 3.1 准确性 / 相关性
- 综合评分（技术 33% / 资金流 18% / 实时 16% / 共振 12% / 情绪 10% / 基本面 7% / 结构 4%）技术上稳健，但**对短线时效性的权重偏低**：
  - 基本面 7%、结构 4% 对 1–20 日交易意义有限；
  - **前向预测（next-session）只进入 `directionScore` 分支，不进入展示的综合评分**。
- 动量偏置：MA 多头排列在 技术趋势 / 共振(MA/MACD) / 结构 三处同时加分；且 `momentumProtectionFactor`（244-258）在 ADX>30 且多头排列时**降低追高/乖离惩罚** → 强趋势被加赏且轻罚，抬高追高风险。
- 行业 RS、次日均线/次日预测优势几乎不进入头条数字。

### 3.2 完善性
- 置信度展示值被 `evidenceConfidence/100` 覆盖（见 1.10），丢掉了回测/预测/对抗维度。
- Discover 批量路径（`ExploreEngine`）与单股 `generateAnalysis` 双套评分，**同一票在发现页与详情页的 recommendation/score 可能不一致**。

### 3.3 时效性
- 实时报价 TTL 5 秒、K 线 2/10 分（TDX）或固定 5 分（回退）——基本满足盘中介入。
- 但决策页只显示"更新: HH:mm:ss"（手机本地分析时间），**不展示底层 K 线交易日 `asOfTradeDate`**（`:561` 已抓取但未露出），周末/休市后无陈旧告警。
- Discover 全市场 `ExploreResult.analyzedAt`（扫描时间戳）**每张卡片不显示**，陈旧扫描无告警。

---

## 4. 留档分析机制（用户信任视角）

- 留档"方向合理率"是会随行情漂移的实时 P/L 快照（1.13），在上涨市偏高、老票据虚高 → **用户看到的"靠谱率"不可信**。
- 无去重/阈值（1.12）→ 重复留档放大统计。
- 推荐统计"命中率"方向盲（1.3）+ 里程碑收益坍缩（1.14）+ 新模型恒空（1.15）→ 整个"复盘/可信度"面给出的数字存在系统性偏差，**不应作为用户决策依据**。

---

## 5. UI 排布合理性

### 5.1 决策页（`quote_screen` → `trading_dashboard` + `short_term_decision_panel`）
- 整体逻辑合理：顶部 recommendation + 评分，交易位/次日预测突出，信号列表精简。
- 缺点：
  - 可执行建议（`suggestions`）与理由（`reasons`）不在主决策面；
  - 7 维评分雷达图孤儿，看不到拆解；
  - 置信度标签在面板内被省略（仅显示数值）。

### 5.2 发现页（`discover_screen`）
- 4 个 tab（打板梯队/主线龙头/分时低吸/全市场）信息密度合理，`StockCard` 含 score/推荐/价/涨跌/PE-PB/共振/结构/概念/20 日收益。
- 缺点：每张卡片无扫描时间戳与陈旧告警；与详情页评分口径可能不一致（双路径）。

### 5.3 推荐统计页（`recommendation_stats_screen`）
- 命中率/平均收益/Alpha/分维度表现/策略胜率/近期记录齐全，含每记录时间戳。
- 缺点：命中率方向盲（1.3）、新模型恒空（1.15），数字需打折扣看待。

---

## 6. 漏洞清单速查表

| 编号 | 严重度 | 子系统 | 一句话问题 |
|------|--------|--------|-----------|
| 1.1 | 严重 | 信号/模型 | WR14 fromJson 丢空值→假"WR超买"卖信号 |
| 1.2 | 严重 | 引擎 | generateAnalysis 不强制算指标，缓存路径静默失效 |
| 1.3 | 严重 | 统计 | 命中率方向盲，看空正确被算亏损 |
| 1.4 | 高 | 信号 | ADX 门限在短历史系统性偏空 |
| 1.5 | 高 | 资金流 | volFactor10d 复制粘贴=volFactor5d |
| 1.6 | 高 | 行情 | indexChange 语义写错（百分比均值当点差） |
| 1.7 | 高 | 行情 | avgChangePct 行业加权≠等权，可误导扣分 |
| 1.8 | 中 | 指标 | calcRSI 长度=period 时越界 |
| 1.9 | 中 | 信号 | MACD 置信度阈值对价格尺度盲 |
| 1.10 | 中 | 引擎 | 显示置信度覆盖计算器输出，丢回测/预测维度 |
| 1.11 | 中 | 评分 | 两套 1-10→文案映射矛盾 |
| 1.12 | 中 | 留档 | 留档无去重无阈值 |
| 1.13 | 中 | 留档 | 方向合理率=实时P/L快照，上涨市虚高 |
| 1.14 | 中 | 跟踪 | 里程碑收益坍缩+用自然日 |
| 1.15 | 中 | 跟踪 | 新模型 refreshPending 生产未调用→恒空 |
| 1.16 | 中 | 行情 | 腾讯 amount 疑似多乘 10000 |
| 1.17 | 中 | 行情 | isStaleQuote 死代码，冻结行情不可检 |
| 1.18 | 中 | 校验 | 校验只标记不纠正 |
| 1.19 | 低 | 分位 | 注释/代码权重不符+脆弱匹配 |
| 1.20 | 低 | 结构 | 短历史吸筹被低估 |
| 1.21 | 低 | 置信度 | 注释/代码权重错位+双重clamp |
| 1.22 | 低 | 展示 | R:R/量纲/共振命名等小问题 |

---

## 7. 下一篇
优化方向与"更准涨跌预测"的设计见 `design_optimization_20260715.md`。
