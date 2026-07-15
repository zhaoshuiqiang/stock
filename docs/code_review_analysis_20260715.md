# 股票分析应用核心模块深度分析报告

> 分析日期: 2026-07-15 | 版本: v2.50+ | 覆盖模块: 10个核心引擎

---

## 一、功能逻辑结构分析

### 1.1 双链推荐架构（A Chain + B Chain）

**A Chain（生产路径）**：`ShortTermDecisionEngine → DirectionalEvidenceBuilder → RecommendationPolicy`
- 5维方向证据加权：trend(30%) + reversal_momentum(25%) + volume_flow(20%) + relative_strength(15%) + next_session(10%)
- 方向分数 = stockEvidence×0.80 + marketBias×0.20
- 方向阈值：bullish≥12, bearish≤-12
- 9级推荐映射 + 多头执行门控（交易质量/风险/置信度三重检验）
- 最终输出：`recommendationDecision.label` 和 `recommendationDecision.legacyScore`

**B Chain（遗留/辅助路径）**：`ComprehensiveScorer.combine()`
- 7维加权评分：技术33% + 资金18% + 实时16% + 共振12% + 情绪10% + 基本面7% + 结构4%
- 动态权重重分配（缺失维度按比例补偿）
- 多重惩罚：追高/乖离率/趋势一致性/板块过热/大盘联动/金融Beta
- 输出 `rawComprehensiveScore` 作为A Chain的输入参数之一

**问题-P1: 双链语义分裂**
- B Chain的 `recommendation` 字段已标注为"遗留映射"但仍在 `ComprehensiveScoreResult` 中产出
- 两套推荐标签阈值不同（B Chain用1-10整数映射，A Chain用方向分数连续映射）
- `ExploreEngine` 的 `_isBuyRecommendation()` 检查的是A Chain产出的标签

### 1.2 信号检测管道

```
generateAnalysis() 流程:
  指标防御性重算 → SignalLayer + SignalDetector + PatternRecognizer
  → MarketStructureAnalyzer → PercentileAnalyzer → LimitUpAnalyzer
  → MomentumPersistenceAnalyzer → NextDayPredictor
  → TechnicalScorer → RealtimeScorer → ConfluenceScorer → CapitalFlowAnalyzer
  → ComprehensiveScorer(B Chain) → ShortTermDecisionEngine(A Chain)
  → ConfidenceCalculator → ReasonGenerator → AI Debate(async)
  → RecommendationTracker(async)
```

**问题-P2: 指标防御性重算条件过窄**
- 仅检查 `data.last.rsi6==0 && macdHist==0 && adx14==0`
- 如果只有部分指标缺失（如仅RSI=0但MACD已计算），不会触发重算
- 可能导致基于不完整指标的信号误判

### 1.3 UI状态管理

- `DiscoverScreen` 使用 `SingleTickerProviderStateMixin` 管理4个Tab
- 数据缓存策略：`_updateCachedLists()` 在每次setState内调用
- Stream订阅管理完善（`_exploreSub` / `_sectorPickSub` / `_limitUpScanSub`）
- `mounted` 检查到位，避免disposed后setState

**问题-P3: 全市场Tab无自动刷新**
- 进入"全市场"Tab不触发数据刷新，仅展示上次探索的DB缓存
- 与"分时低吸"Tab（有 `_maybeRefreshIntradayScan` 懒加载）不一致

---

## 二、评分推荐机制分析

### 2.1 评分口径漂移

| 场景 | 评分路径 | 差异点 |
|------|---------|--------|
| 批量扫描(Explore) | `generateAnalysis(enableAsyncSideEffects=false)` + `calibrationService.enrich()` | 加入了校准服务 |
| 个股详情页(Quote) | `generateAnalysis(enableAsyncSideEffects=true)` + 实时行情 | 无校准，但有实时数据 |
| 板块精选(SectorPick) | `generateAnalysis()` → 主线bonus乘数 | 额外×1.0~1.3倍加成 |

**问题-P4: 扫描快照与实时评分不一致**
- UI已加提示文案"评分为扫描时快照"（L1308-1327），但用户仍可能困惑
- `ExploreResult.score` 是 `int`（round后），精度丢失
- 板块精选的 `score` 经过 `bonus` 乘数后round，与原始评分不同

### 2.2 ConfidenceCalculator权重不一致

**`calculate()` 方法**（实际计算）：
- 信号一致性29% + 基本面11% + 情绪11% + 市场11% + 结构11% + 时效11% + 回测8% + 预测8%

**`breakdown()` 方法**（UI展示）：
- 信号一致性32% + 基本面12% + 情绪12% + 市场12% + 结构12% + 时效12% + 回测8%
- **缺少"预测准确率"维度**（8%被分摊到其他维度）

**问题-P5: UI展示的置信度分解与实际计算不匹配**
- 用户看到的各维度占比与真实计算不同
- `breakdown` 返回8个key但权重和为100%（32+12×5+8=92%，加上prediction_support=100%）

### 2.3 推荐文案映射

A Chain的9级映射：
| 方向分数 | 标签 | legacyScore |
|---------|------|-------------|
| ≥55 | 强烈买入 | 9（例外条件下=10） |
| ≥35 | 买入 | 8 |
| ≥20 | 谨慎买入 | 7 |
| ≥12 | 偏多观望 | 6 |
| (-12,12) | 观望 | 5 |
| ≤-12 | 偏空观望 | 4 |
| ≤-20 | 谨慎卖出 | 3 |
| ≤-35 | 卖出 | 2 |
| ≤-55 | 强烈卖出 | 1 |

门控降级逻辑：
- 多头方向但门控不通过 → 降为"偏多观望"(6分)
- 空头方向但置信度不足 → 降为"偏空观望"(4分)

---

## 三、留档与追踪机制分析

### 3.1 Archive去重机制

**问题-P6: `addArchiveIfNotExists()` 仅按code去重**
- 同一股票在不同时间点（如1月买入建议、3月卖出建议）只保留第一条
- 无法追踪同一股票分析结论的变化轨迹
- 丢失重要的"看多转看空"时间拐点信息

### 3.2 交易日计算缺陷

**问题-P7: `tradingDaysBetween()` 不考虑法定节假日**
- 仅跳过周末，春节/国庆长假期间会提前触发5/10/20日里程碑
- 例：国庆7天假期内，实际仅过了0个交易日，但函数会计算为5个交易日
- 影响范围：所有推荐追踪的收益里程碑判定

### 3.3 方向合理率计算

`ArchiveReliabilityEvaluator` 使用动态阈值：
- `threshold = 2.0 * sqrt(days/5)`，夹在[2.0, 12.0]
- 持有时间越长，允许的波动范围越大（合理设计）
- 但时间维度仅基于自然日，未考虑交易日

### 3.4 方向字段兼容性

**问题-P8: v3.19新增direction字段的旧数据兼容**
- 旧 `recommendation_tracking` 记录 direction 为空字符串
- `calculateStats()` 对 `unknown` 方向直接跳过，不参与统计
- 可能导致早期推荐的命中率统计覆盖不足

---

## 四、指标显示机制分析

### 4.1 K线图实现

- 使用 `fl_chart` 库 + 自定义 `_KlinePainter` (CustomPaint)
- 4区域布局：K线+MA线、成交量柱、MACD柱+DIF/DEA、RSI折线
- 支持60/120/360天切换、斐波那契回撤、支撑阻力位

**问题-P9: K线图触摸交互精度不足**
- `_buildKlineChart` 中的触摸检测使用简化的宽度计算（L173-188）
- `containerWidth` 依赖 `context.findRenderObject()`，首帧可能为null
- bar宽度和gap计算未考虑LineChart的内边距

### 4.2 指标计算正确性

- MA：标准SMA，O(n)滑窗实现 ✓
- MACD：标准EMA差值法(12,26,9) ✓
- RSI：Wilder平滑法(6,12,24)，v3.19修复了边界越界 ✓
- KDJ：标准随机指标(9,3,3) ✓
- BOLL：O(n)滑窗优化，样本标准差 ✓
- ATR：Wilder平滑(14) ✓

### 4.3 实时数据更新

- `QuoteScreen` 使用轮询Timer（`_pollingTimer`）定期刷新行情
- 分时图数据独立获取（`_timeshareData`），支持分时低吸信号叠加
- 分析刷新频率受 `_updateCount` 控制，避免过度计算

---

## 五、股票推荐机制分析

### 5.1 ExploreEngine批量扫描

5阶段流水线：
1. 热门板块(top20) → 2. 成分股(去重+主板过滤+ST过滤)
3. 批量K线(15并发) → 4. 批量行情(50并发) → 5. 逐只分析

筛选逻辑：`_isBuyRecommendation` 仅保留"强烈买入/买入/谨慎买入"

**问题-P10: 估值过滤在shortTermMode下形同虚设**
- `_passValuationFilter(quote, shortTermMode: true)` 仅要求 `price > 0`
- 短线模式下PE/PB过滤完全关闭，可能推荐垃圾股

### 5.2 SectorPickEngine板块精选

- 取前10热门板块 → 每个板块取前10成分股 → 分析 → 筛选买入级 → 主线加成
- 主线判定：`strengthScore >= 5.0 && limitUpCount >= 1`
- 主线bonus：`1.0 + (strengthScore/20.0).clamp(0, 0.3)`，最大1.3倍

**问题-P11: 板块成分股数量硬编码**
- 每个板块只取前10只（L90: `.take(10)`），可能遗漏板块内强势个股
- 热门板块排名靠后的成分股完全不会被分析

### 5.3 IntradayScanEngine分时低吸

- 从explore_results取前30只 → 并发5只获取分时数据 → 分析 → 仅保留高可信度信号
- 信号类型：VWAP支撑/昨收支撑/量价底背离/急跌放量
- 评分：置信度×10 ± 趋势加成

**问题-P12: 分时扫描数据源局限**
- 仅从explore_results取前30只（按score DESC），严重依赖上次全市场扫描的质量
- 如果全市场扫描较旧（如昨天的数据），分时扫描的候选池也是旧的
- 高频短线用户需要的是"当前市场活跃标的"，而非"昨天评分高的标的"

---

## 六、代码评审分析师视角

### 6.1 严重问题（P0级）

| # | 问题 | 影响 | 位置 |
|---|------|------|------|
| P0-1 | ConfidenceCalculator的calculate vs breakdown权重不一致 | UI误导用户 | confidence_calculator.dart L169 vs L233 |
| P0-2 | 交易日计算不含法定节假日 | 长假期间里程碑提前触发 | recommendation_tracker.dart L134-148 |
| P0-3 | Archive去重仅按code无时间维度 | 同股票不同时间分析被跳过 | database_service.dart addArchiveIfNotExists |

### 6.2 高优问题（P1级）

| # | 问题 | 影响 | 位置 |
|---|------|------|------|
| P1-1 | 评分口径漂移（扫描vs实时vs板块） | 用户困惑分数变化 | explore_engine.dart / sector_pick_engine.dart |
| P1-2 | B Chain recommendation字段冗余产出 | 代码维护混淆 | comprehensive_scorer.dart L217-228 |
| P1-3 | 分时扫描候选池依赖旧数据 | 推荐时效性差 | intraday_scan_engine.dart L51 |
| P1-4 | 全市场Tab无自动刷新 | 用户看到过期数据 | discover_screen.dart |

### 6.3 中优问题（P2级）

| # | 问题 | 影响 |
|---|------|------|
| P2-1 | 指标防御性重算条件过窄 | 部分指标缺失时误判 |
| P2-2 | 板块成分股硬编码取10只 | 遗漏强势个股 |
| P2-3 | v3.19 direction字段旧数据兼容 | 命中率统计覆盖不足 |
| P2-4 | K线图触摸交互精度 | 用户体验不佳 |
| P2-5 | shortTermMode估值过滤形同虚设 | 可能推荐垃圾股 |

### 6.4 死代码/冗余实现

1. `ComprehensiveScoreResult.recommendation` — 标注为遗留但仍产出
2. `ComprehensiveScoreResult.positionAdvice/positionLabel` — 未见下游消费
3. `ExploreEngine.passesValuationFilter` (public static) — 仅供测试调用，生产路径走private版本

---

## 七、短线操作用户视角

### 7.1 功能完善性评估

| 功能 | 评分 | 评价 |
|------|------|------|
| 打板梯队 | 8/10 | 分组清晰、情绪温度计有参考价值 |
| 主线龙头 | 7/10 | 主线判定逻辑合理，但无回退时标注不够明显 |
| 分时低吸 | 6/10 | 仅交易时段有效，候选池依赖旧数据 |
| 全市场 | 7/10 | 评分快照机制好，但无实时更新 |
| 留档追踪 | 6/10 | 方向合理率设计合理，但去重问题影响完整性 |

### 7.2 准确性与时效性

- **评分时效**: 批量扫描评分为快照，进入详情页才实时重算
- **分时信号**: 仅交易时段有效，盘后无法回测验证
- **情绪温度计**: 依赖东财涨停池API，数据质量受API限制
- **主线判定**: 需涨停数≥1才能成为主线，冷门板块可能被遗漏

### 7.3 UI体验痛点

1. 全市场Tab加载完后无进度反馈，不知道数据是何时的
2. 板块精选无完成时间戳显示
3. 分时低吸Tab在非交易时段显示空白，无历史参考
4. 评分数字(1-10)对短线用户不够直觉，缺乏"今天能不能买"的明确信号

### 7.4 风险控制评估

- 追高惩罚机制完善（分级+动量保护）
- 大盘联动折扣有效
- 门控降级防止虚假买入信号
- **但缺少**：个股波动率分级、仓位建议量化、止损位自动提醒
