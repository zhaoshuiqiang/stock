# 盘前短线评分 V3 与留档诊断闭环设计

日期：2026-07-16

状态：已逐段确认，待实施计划

应用目标版本：`3.31.20260716`

模型目标版本：`short-term-v3`

## 1. 背景与事实基线

本项目已经完成短线决策 V2、1/3/5 交易日结果追踪、校准概率、留档双写和
留档页可解释性建设。当前真正需要解决的是：评分能否在盘前对后续涨跌形成
稳定、可区分、可复核的预测，而不是只在盘后解释已有结果。

用户的主要工作流已经确认：

1. 盘前生成分析并留档；
2. 当日盘后查看或导出结果；
3. 以当日收盘作为首要 1 日验证；
4. 以 3/5 个交易日验证信号持续性；
5. 根据分数、方向、市场状态和评分分量的历史表现，人工设计下一版本；
6. 不使用少量样本自动修改生产权重。

### 1.1 现有导出数据结论

对以下两份盘前留档、盘后导出的历史口径 CSV 进行只读分析：

- `留档数据/archive_export_20260715_160034.csv`：364 条；
- `留档数据/archive_export_20260716_145941.csv`：400 条。

可确认的现象：

- 评分与实际收益的 Spearman 相关分别约为 `0.02` 和 `0.03`，分数基本没有
  横截面区分力；
- 看多/看空原始方向平衡命中率分别约为 `44.0%` 和 `44.6%`；
- 2026-07-16 的 9 分样本仅 11 条，有效命中率约 `18.2%`，样本虽小，但足以
  证明高分单调性不能被默认成立；
- 2026-07-15 为普涨样本，模型看多命中主要接近市场上涨基准，而看空命中明显
  低于市场下跌基准；
- 2026-07-16 市场转弱后，模型仍有 284/400 条看多、仅 15/400 条看空，存在
  明显的方向偏斜；
- 历史 CSV 的“共振评分”来自旧辅助链，并不直接决定当前最终推荐，因此它与
  最终分数出现反向并不等价于同一评分器内部自相矛盾，但会误导复盘。

这两份 CSV 只能证明现有模型缺乏稳定区分力，不能直接用于拟合新权重。它们缺少
完整 K 线、五维评分分量、市场状态和固定周期结果，且只覆盖两个连续交易日。

### 1.2 代码审计确认的根因

当前生产推荐走以下主链：

```text
SignalEngine.generateAnalysis
  -> ShortTermDecisionEngine
     -> DirectionalEvidenceBuilder
     -> EvidenceConfidenceCalculator
     -> TradeQualityEvaluator
     -> ShortTermRiskEvaluator
     -> RecommendationPolicy
  -> AnalysisResult.score / recommendation
```

`TechnicalScorer`、`RealtimeScorer`、`ConfluenceScorer` 和
`ComprehensiveScorer` 仍会生成解释性数据，但 `rawComprehensiveScore` 只被保存，
不参与 `RecommendationPolicy` 的最终分数映射。因此，单独修改旧综合权重不会修复
最终推荐。

代码层已确认以下问题：

1. 生产 `SignalItem.strength` 使用 `40..90`，方向证据却按 `/10` 归一化，交易
   质量按 `/3` 归一化，绝大多数信号被夹到满值；
2. 对应测试夹具使用 `3..10` 的虚构强度范围，未覆盖生产尺度；
3. `PercentileAnalyzer.industryRSScore` 是估值、RSI、成交量和 5 日涨幅的
   `0..1` 合成值，并不是真实行业相对强弱；
4. 上述 `0..1` 值被直接当作 `-1..1` 方向值，`0.5` 不是中性，而是持续提供
   正向贡献，弱势值也不会产生负贡献；
5. 中文“量价”“资金”“形态”“背离”“缺口”等信号无法被现有英文关键字完整
   识别，大量信号默认落入趋势桶；
6. MA、ADX、RSI、KDJ、WR 等指标既以数值规则进入组件，又以 `SignalItem` 再次
   进入，同一事实会被重复放大；
7. 所谓“共振增强”统计的是同一指标出现次数，不是不同独立指标的一致性，而且
   不区分同指标内的相反方向；
8. 评分和信号规则在 2026-07-15 至 2026-07-16 多次变化，内部模型版本仍一直是
   `short-term-v2`，校准桶无法区分不同公式；
9. 盘前留档把当天写为 `signalTradeDate`，结果评价使用
   `signalIndex + horizon`，导致 1 日结果落到下一交易日收盘；
10. 盘前留档价格实际是上一完整交易日收盘价，现有 1 日评价因此会跨越两个交易
    时段，Alpha、可执行收益和 MFE/MAE 锚点也随之错位；
11. 历史“补录缺失决策”会用当前数据重新分析旧留档，并把当前结论保存成历史
    快照，存在前视污染风险；
12. 留档页尚未实现评分桶单调性、方向分与收益相关性、五维分量预测力、方向偏斜
    和模型调权准备度等诊断。

## 2. 目标

### 2.1 产品目标

- 首要评价盘前决策到当日收盘的方向与可执行表现；
- 同时保留 3/5 个交易日结果，判断信号持续性；
- 让 1 至 10 分重新具备可解释的方向强度含义；
- 让更强且更一致的独立证据产生更强方向分，弱证据不再自动饱和；
- 使用相对大盘表现、Alpha 和多空平衡命中，区分市场贝塔与模型能力；
- 留档页能够回答“哪个分数段、市场状态、方向或评分分量失效”；
- 通过模型版本隔离，为后续人工调权建立可信数据集。

### 2.2 工程目标

- 保持 `ShortTermDecisionEngine` 为唯一生产推荐事实来源；
- 通过新增字段和兼容默认值渐进升级，不改写旧结果；
- 所有评分、评价、统计和导出逻辑保持纯 Dart、确定性和可测试；
- 数据库迁移仅增加字段或索引，沿用 `if (oldVersion < N)`；
- 生产行为变更全部先有失败测试，再实现最小修复；
- 不把现有工作区中的 CSV、模拟器、diff、测试输出等噪音纳入提交。

## 3. 非目标

- 不承诺仅凭本次代码修复即可证明未来真实胜率已经提升；
- 不根据 2026-07-15/16 两个交易日拟合新的五维权重；
- 不启用 `WeightOptimizer` 或其他自动生产调权；
- 不将 PE/PB、所谓基本面分直接用于盘前到当日收盘的方向预测；
- 不回写或重新解释 `short-term-v2` 的历史结果；
- 不把看空建议解释为默认可执行的融券做空交易；
- 不在本次范围内建设后端、云端训练或 LLM 评分。

## 4. 总体架构

生产主链保持单一：

```text
已完成日 K 线 + 盘前行情 + 上一市场环境
          |
          v
SignalLayer / PatternRecognizer
          |
          v
ShortTermDecisionEngine (short-term-v3)
  |-- SignalEvidenceClassifier
  |-- DirectionalEvidenceBuilder
  |-- EvidenceConfidenceCalculator
  |-- TradeQualityEvaluator
  |-- ShortTermRiskEvaluator
          |
          v
RecommendationPolicy
          |
          +--> AnalysisResult / OpportunityResult / ExploreResult
          +--> DecisionTracker
                   |
                   +--> evidenceTradeDate + signalTradeDate + signalPhase
                   +--> 1/3/5 日固定周期结果
                   +--> DecisionStatistics / ScoreDiagnostics
                   +--> 留档页 / 决策 CSV
```

旧辅助链继续用于兼容展示：

```text
TechnicalScorer + RealtimeScorer + ConfluenceScorer
  -> ComprehensiveScorer
  -> rawComprehensiveScore / dimensionScores
```

UI 必须明确旧辅助维度是解释信息，不是最终推荐分的直接加权来源。

## 5. 评分核心 V3

### 5.1 模型版本

`ShortTermDecisionEngine.modelVersion` 更新为：

```dart
static const String modelVersion = 'short-term-v3';
```

以后任何会改变方向分、交易质量、风险、推荐阈值或信号归属的生产变更，都必须
同步更新内部模型版本。应用版本变化但评分公式不变时，可以沿用模型版本。

### 5.2 五维权重

本版本不根据两日样本调权，保留已确认权重：

| 方向组件 | 权重 |
|---|---:|
| 趋势 | 30% |
| 反转/动量 | 25% |
| 量价/资金 | 20% |
| 相对强弱 | 15% |
| 次交易日预测 | 10% |

聚合继续使用：

```text
stockEvidence = 100 * sum(componentValue * componentWeight)
directionScore = clamp(stockEvidence * 0.80 + marketBias * 0.20, -100, 100)
```

市场最多贡献 20%。修复相对强弱中性点后，市场偏置本身最高为正负 10 分，不能
单独越过正负 12 的方向阈值。

### 5.3 信号强度归一化

生产信号强度统一解释为 `0..100`：

```text
signalValue = directionSign
            * clamp(strength / 100, 0, 1)
            * durationWeight
            * clamp(confidence, 0, 1)
```

时长权重沿用短线优先原则：

| 时长 | 权重 |
|---|---:|
| shortTerm | 1.00 |
| mediumTerm | 0.75 |
| longTerm | 0.45 |
| null | 0.75 |

缺失置信度使用 `0.8`，但不再把它最低夹到 `0.4` 后又通过错误分母放大到满值。

`TradeQualityEvaluator` 中的强度同样使用 `/100`，不再使用 `/3`。

### 5.4 信号组件与指标族

新增纯 Dart 分类器 `SignalEvidenceClassifier`，每条信号返回唯一组件和唯一指标族。
分类同时识别指标字段、信号名称和描述中的中英文词汇。

| 组件 | 指标族示例 |
|---|---|
| 趋势 | MA 排列/交叉、ADX/DI、MACD 趋势交叉、趋势型 BOLL 突破 |
| 反转/动量 | RSI、KDJ、WR、CCI、BIAS、MACD 背离、K 线反转形态、反转缺口 |
| 量价/资金 | 放量/缩量、OBV、主力资金、换手、量价背离 |
| 相对强弱 | 个股相对大盘表现；本版本不从普通信号文本生成 |
| 次交易日预测 | NextDayPredictor、NextSessionPredictor；本版本不从普通信号文本生成 |

同一条信号只允许进入一个组件。MACD 趋势交叉和 MACD 背离可以属于不同组件，
因为它们是不同事实；同一条 MACD 信号不能同时进入两个组件。

### 5.5 去重与组件聚合

每个数值规则或 `SignalItem` 先转换为：

```text
component + family + signedValue(-1..1) + source
```

同一组件、同一指标族先按方向去重：同方向只保留绝对有效值最大的一个，不求和。
如果同一指标族同时出现正负证据，则保留最强正值和最强负值并取平均，同时增加
`evidence_family_conflict` 标记，降低证据一致性。例如 MA 数值排列和“均线多头
排列”属于同一 MA 族且方向相同，只能贡献一次；短期下穿与长期多头同时存在时，
必须体现冲突而不是任选一侧。MACD 交叉和 MACD 背离属于不同指标族，可以分别
进入趋势和反转组件。

组件值为保留后各指标族有符号值的算术平均，并夹在 `-1..1`。这样可以保证：

- 同一指标重复发出多周期信号不会无限放大；
- 不同指标族一致时会提高组件稳定性；
- 相反证据会真实抵消；
- 一条弱信号不能因错误分母直接变成满分证据。

### 5.6 共振语义

`SignalDetector` 不再根据“同一 indicator 出现次数”提高置信度。

`signalCount` 只记录同方向的独立组件覆盖数，供 UI 展示；不修改原始
`SignalItem.confidence`。真正的共振由 `EvidenceConfidenceCalculator` 对五个独立
组件的方向一致性和覆盖率计算，不再次进入方向分。

旧 `ConfluenceScorer` 保留为历史辅助展示，但 UI 和 CSV 必须明确它不是 V3 最终
推荐分的直接输入。

### 5.7 相对强弱

`PercentileAnalyzer.industryRSScore` 不再进入 V3 方向分。它仍可在估值/分位说明中
展示，但不得被称为真实行业相对强弱。

V3 相对强弱使用上一完整交易日的个股表现相对市场平均表现：

```text
relativeStrength = clamp(
  (stockLastCompletedChangePct - marketContext.avgChangePct) / 5,
  -1,
  1,
)
```

含义：相对大盘领先或落后 5 个百分点时达到正负满值，完全相同时为 0。

市场环境缺失、无效或退化为空数据时，相对强弱返回 0，并写入数据质量标记；不能
把缺失数据当作大盘震荡或正向证据。

### 5.8 市场环境有效性

以下组合视为不可用市场环境，而不是 `range`：

- 上证、深证、平均涨跌均为 0；
- 上涨/下跌家数均为 0；
- 趋势为 `neutral`；
- 数据来源刚刚走过全失败兜底。

真实平盘但具备有效上涨/下跌家数的数据仍可判定为震荡。

不可用时记录 `market_context_missing` 或 `market_context_invalid`，市场偏置为 0，
相对强弱为 0。

### 5.9 交易质量

`TradeQualityEvaluator.evaluate` 增加明确方向参数。

- 看多：放量上涨为高质量确认，放量下跌为低质量；
- 看空/减仓：放量下跌为高质量方向确认，放量上涨为低质量；
- 中性：量价项返回中性质量，不暗示交易方向；
- 信号强度使用 `strength / 100`；
- 同方向独立信号达到两个以上仍可获得有限的一致性加分，但不按原始信号条数无限
  加分；
- 看空在普通 A 股语义下是回避/减仓，不把多头止盈目标伪装成做空盈亏比。看空的
  支撑盈亏比项使用中性值，方向质量主要来自时效、量价确认和流动性。

### 5.10 风险和数据质量门禁

风险仍只影响是否可执行和推荐强度，不改变方向正负号。

下列关键标记会增加 `critical_data_missing` 门禁：

- 历史数据缺失；
- 市场环境完全缺失或无效；
- 证据交易日缺失；
- 关键行情价格不可用。

存在关键门禁时，强看多、看多、谨慎看多及对应看空级别降为方向观察，保留原始
`directionScore` 供复盘，不输出可执行买卖建议。

## 6. 盘前留档与固定周期评价

### 6.1 两个日期的唯一语义

- `signalTradeDate`：用户实际留档或系统生成快照的交易日期；
- `evidenceTradeDate`：评分所使用的最后一根完整日 K 线日期。

盘前生成时，两者通常相差一个交易日。盘后生成时，两者通常相同。

`ShortTermDecision` 新增可空 `evidenceTradeDate`。V3 引擎始终使用
`input.data.last.date` 填充；旧模型反序列化缺失时保持兼容。

### 6.2 信号阶段

新增枚举：

```dart
enum DecisionSignalPhase {
  preMarket,
  intraday,
  afterClose,
  nonTrading,
  unknown,
}
```

阶段按实际捕获时间和交易日判断：

- 交易日 09:30 前：`preMarket`；
- 09:30 至 15:00：`intraday`；
- 15:00 后：`afterClose`；
- 周末或法定休市日：`nonTrading`；
- 旧数据或无法判断：`unknown`。

阶段用于筛选和统计，不改变方向分。

`signalTime` 保存实际捕获时间。行情对象的 `quote.updateTime` 只表示行情数据时间，
不得用于判断盘前、交易中或盘后阶段。

### 6.3 目标交易日

结果评价以 `evidenceTradeDate` 为锚点：

```text
targetTradeDate = benchmarkTradingDates[
  indexOf(evidenceTradeDate) + horizon
]
```

因此 2026-07-16 盘前留档、证据日为 2026-07-15 时：

- 1 日目标为 2026-07-16 收盘；
- 3 日目标为证据日后的第 3 个真实交易日收盘；
- 5 日目标为证据日后的第 5 个真实交易日收盘。

旧 V2 快照缺少证据日时回退到 `signalTradeDate`，保持原有历史语义，不重新计算。

### 6.4 收益、Alpha 和执行口径

- 方向收益：证据日复权收盘到目标日复权收盘；
- 可执行收益：证据日后的第一个有效交易日开盘到目标日收盘；
- 基准收益：相同证据日与目标日的沪深 300 收盘收益；
- Alpha：方向收益减基准收益；
- MFE/MAE：从可执行入场日至目标日，按方向化复权高低价计算；
- 盘前 1 日因此等价于“上一收盘生成证据、今日开盘可执行、今日收盘验证”。

评价器必须优先读取复权 K 线在证据日的收盘价，不把捕获时的裸价直接当作复权价。
`signalPrice` 继续保存实际观察价，`adjustedSignalPrice` 只有在明确来自同一复权序列
时才可使用。

### 6.5 命中语义

- 看多原始命中：方向收益 `> 0`；
- 看空原始命中：方向收益 `< 0`；
- 看多有效命中：方向收益 `>= 0.5%`；
- 看空有效命中：方向收益 `<= -0.5%`；
- 看多 Alpha 命中：Alpha `> 0`；
- 看空 Alpha 命中：Alpha `< 0`；
- 中性稳定：绝对 Alpha `<= 0.5%`，单独统计，不混入多空平衡命中率。

### 6.6 历史补录隔离

使用当前数据重新分析旧留档不能成为历史预测样本。

保留补录能力，但所有补录快照必须同时满足：

- `source = 'archive_backfill'`；
- `isRetrospective = true`；
- 增加 `retrospective_backfill` 数据质量标记；
- 默认留档统计、校准、模型诊断和决策 CSV 全部排除；
- UI 只在明确开启“回溯补录”筛选时展示。

新的实时双写快照使用 `source = 'archive'` 且 `isRetrospective = false`。

## 7. 数据模型与数据库

SQLite 由 v23 升级至 v24，只增加字段。

### 7.1 decision_snapshots 新字段

```text
evidence_trade_date TEXT
signal_phase TEXT NOT NULL DEFAULT 'unknown'
actionable INTEGER NOT NULL DEFAULT 0
recommendation_gates_json TEXT NOT NULL DEFAULT '[]'
app_version TEXT NOT NULL DEFAULT ''
is_retrospective INTEGER NOT NULL DEFAULT 0
```

同时修复现有写入错误：`recommendation_level` 保存
`RecommendationDecision.level.name`，不能继续保存 `direction.name`。

旧行兼容规则：

- `evidence_trade_date` 缺失时读取为 `signal_trade_date`；
- `signal_phase` 缺失时为 `unknown`；
- `actionable` 缺失时为 `false`；
- gates 缺失时为空列表；
- `is_retrospective` 缺失时为 `false`；
- 不更新旧行的已评价结果。

### 7.2 AnalysisResult 与机会摘要

`DecisionTracker.capture` 优先读取完整 `RecommendationDecision`。

由 `OpportunityResult` 构造捕获分析时，如果机会摘要未直接保存
`RecommendationDecision`，使用同一版本的 `RecommendationPolicy.evaluate` 从已保存
`ShortTermDecision` 重建，保证推荐级别、可执行状态和门禁一致。

市场状态和五维分量继续来自 `ShortTermDecision`。能够取得板块名称时同步保存，缺失
时保持空值，不合成未知板块。

## 8. 决策统计与评分诊断

### 8.1 基础统计

`DecisionStatisticsSummary` 增加或明确区分：

- 看多有效命中率；
- 看空有效命中率；
- 多空平衡命中率；
- 中性稳定率；
- Alpha 命中率；
- 方向化平均/中位收益；
- 方向化平均/中位 Alpha；
- 原始收益和 Alpha 仍可在详情中查看；
- 已评价、待评价、到期仍待评价、无效、覆盖率；
- 每个率对应的样本数，必要时提供 Wilson 区间。

方向化值定义：

```text
bullish:  orientedReturn = forecastReturn
bearish:  orientedReturn = -forecastReturn
neutral:  不进入多空方向化收益
```

方向化 Alpha 同理。

多空平衡命中率仅在看多和看空两侧都有有效样本时计算：

```text
balancedHitRate = (bullishHitRate + bearishHitRate) / 2
```

### 8.2 分数桶

按方向分绝对值划分：

| 桶 | 范围 |
|---|---|
| 观察 | 12..<20 |
| 谨慎 | 20..<35 |
| 明确 | 35..<55 |
| 强烈 | 55..100 |

每个桶分别展示样本数、信号日数、有效命中、Alpha 命中、方向化平均收益和方向化
平均 Alpha。看多和看空分开评价，不能把负方向分按普通数值排序后误判单调性。

### 8.3 评分相关性与单调性

新增纯 Dart `DecisionScoreDiagnostics`：

- 对非中性成熟样本计算 `directionScore` 与 `forecastReturn` 的 Spearman 相关；
- 对五个 `directionComponents` 分别计算组件值与实际收益的 Spearman 相关；
- 相关性少于 30 条成熟样本或少于 10 个信号日时返回“样本不足”，不显示伪精度；
- 看多、看空分别检查强度桶是否随强度增加而改善；
- 只有参与比较的相邻桶均至少 20 条且覆盖至少 5 个信号日时才给出单调性提示；
- 未满足门槛时展示原始桶数据，但状态为“待积累”。

### 8.4 方向偏斜

展示看多、中性、看空占比。任一方向超过 70% 时提示“方向分布明显偏斜”，但该提示
只用于诊断，不自动反转或调低个股方向。

### 8.5 校准指标

校准概率的生产门槛保持：

- 同模型、同周期、同方向、同市场状态、同强度桶；
- 至少 100 条成熟有效样本；
- 至少 20 个信号交易日；
- 覆盖率至少 95%。

Brier/ECE 的展示门槛恢复为：

- 至少 30 条带事前概率的成熟结果；
- 至少 10 个信号交易日。

不足时显示“已收集 X/30 条、Y/10 个信号日”，不提前输出数值。

### 8.6 模型调权准备度

留档页展示只读准备度清单。全部满足后才提示可以单独设计下一版权重：

- 每个核心方向强度桶至少 100 条成熟样本；
- 至少 20 个不同信号日；
- 1/3/5 日标签完整率不低于 95%；
- 覆盖牛市趋势、反弹、震荡、熊市/回调四类市场组；
- 能够按时间切分训练期与验证期；
- 组件相关性和分数桶单调性数据可用。

本版本不根据准备度自动修改权重。

## 9. 留档页面

### 9.1 默认筛选

新模型页继续作为默认模式，并默认选择：

- 来源：我的留档；
- 信号阶段：盘前；
- 模型版本：最新模型；
- 周期：1 日；
- 日期范围：全部。

用户可切换 3/5 日、全市场扫描、交易中/盘后、旧模型和其他市场状态。

### 9.2 页面结构

从上到下展示：

1. 模式、来源、阶段、方向、市场状态、模型版本和日期筛选；
2. 1/3/5 日固定周期切换；
3. 覆盖率与成熟状态；
4. 看多命中、看空命中、多空平衡命中、中性稳定、Alpha 命中；
5. 方向化收益与 Alpha；
6. 方向分布；
7. 分数桶与单调性；
8. 按方向/市场状态/信号阶段的分段表现；
9. 五维组件相关性；
10. Brier/ECE 及样本进度；
11. 按留档日趋势；
12. 模型调权准备度；
13. 决策列表和单条下钻。

趋势图的 50% 线只用于看多/看空二分类参考。包含中性样本时必须展示多空平衡命中
或 Alpha 命中，不把中性稳定率与 50% 随机线直接比较。

### 9.3 历史实时页

历史实时页继续用于“当前价是否符合当时方向”的即时核对，并明确展示：

> 当前价实时核对会随行情变化，不是固定周期命中率，不能用于评分校准。

按钮名称改为“导出实时核对 CSV”，避免和“导出决策 CSV”混淆。

### 9.4 单条下钻

下钻增加：

- 实际推荐级别、是否可执行和门禁原因；
- 实际留档时间、信号阶段、证据日和信号日；
- 五维方向分量；
- 交易质量和风险分量；
- 1/3/5 日目标日期、方向化收益、Alpha、MFE/MAE；
- 事前校准概率及样本区间；
- 数据质量和回溯补录标识。

## 10. 决策 CSV

新模型导出必须遵循当前页面全部筛选：

- 来源；
- 信号阶段；
- 是否回溯；
- 今日/日期范围；
- 方向；
- 市场状态；
- 模型版本。

导出全部 1/3/5 日结果，不受当前显示周期限制；当前周期只影响页面汇总。

新增或修正字段：

```text
app_version
model_version
source
is_retrospective
signal_time
signal_trade_date
evidence_trade_date
signal_phase
direction
direction_score
trade_quality_score
risk_score
evidence_confidence
recommendation_level
recommendation_label
legacy_score
actionable
recommendation_gates
market_regime
market_change_pct
primary_strategy_id
primary_strategy_name
supporting_strategy_ids
direction_components
quality_components
risk_components
data_quality_flags
1/3/5 日的状态、目标日、方向收益、可执行收益、Alpha、MFE、MAE、
原始命中、有效命中、Alpha 命中、事前概率、样本数、Wilson 区间、无效原因
```

导出成功提示使用实际决策快照数，不能继续显示历史留档条数。

## 11. 错误处理

- 市场环境缺失：方向市场项和相对强弱归零、记录标记、阻止高强度可执行建议；
- 证据日缺失：V3 决策先增加关键数据门禁，`DecisionTracker.capture` 随后拒绝保存
  决策快照；历史 `archive_records` 仍可保留，但不能静默生成错误周期结果；
- 证据日不在基准序列：结果标记无效并记录明确原因；
- 目标日尚未成熟：保持 pending，不增加失败次数；
- 股票停牌：延后到下一有效交易日并记录延期天数；
- 下一交易日一字板：方向结果仍评价，可执行收益标记无效；
- 复权与裸价差异明显：记录除权标记；
- JSON 新字段解析失败：保留核心字段、使用兼容默认值并记录日志；
- 回溯补录：默认隔离，不参与任何生产校准；
- 导出筛选无数据：明确提示当前筛选无可导出结果。

## 12. 测试策略

所有生产行为修改使用 TDD，先运行并确认测试因缺失行为而失败。

### 12.1 评分核心测试

- 生产强度 75 的信号贡献大于强度 45，二者都不饱和；
- 同强度下短期贡献大于中期，中期大于长期；
- 置信度变化影响信号贡献；
- 中文量价、资金、背离、K 线形态、缺口、MA、ADX、MACD 正确分桶；
- 同一 MA 族数值证据和文字信号只贡献一次；
- 同指标相反方向不会被错误标记为共振；
- 市场相对表现相同为 0，领先为正，落后为负；
- PE/PB 改变不影响 V3 短线方向分；
- 市场环境失败兜底不再被判为正常震荡；
- 方向分随同方向独立证据增强而单调增加；
- 风险变化不改变方向符号；
- 关键数据缺失会触发不可执行门禁。

### 12.2 交易质量测试

- 强度使用 0..100；
- 看多时放量上涨优于放量下跌；
- 看空时放量下跌优于放量上涨；
- 中性方向不获得多头或空头量价奖励；
- 看空质量不使用多头盈亏比制造虚假高分；
- 所有分量和总分保持 0..100。

### 12.3 盘前评价测试

- 盘前信号日为 T、证据日为 T-1 时，1 日目标为 T；
- 3/5 日目标使用真实基准交易日序列；
- 方向收益使用证据日复权收盘；
- 可执行收益从 T 日开盘计算；
- Alpha 使用证据日到目标日的同周期基准收益；
- MFE/MAE 包含 T 日路径；
- 盘后证据日等于信号日时，1 日目标仍为下一交易日；
- 旧快照缺少证据日时保持旧行为；
- 回溯补录样本不进入默认统计和校准。

### 12.4 数据库和序列化测试

- v23 升级 v24 保留全部旧表和旧数据；
- 新字段默认值正确；
- `recommendation_level` 保存真实级别；
- gates、phase、evidence date、app version、回溯标记可往返；
- V2 与 V3 查询和校准严格隔离；
- 同一来源、同一股票、同一信号日的唯一约束保持有效。

### 12.5 统计和导出测试

- 看多、看空、中性使用独立分母；
- 多空平衡命中率正确；
- 方向化收益和 Alpha 正确；
- Spearman 能处理并列分数、空样本和常量输入；
- 分数桶边界 12/20/35/55/100 正确；
- 单调性样本门槛正确；
- 五维相关性样本不足时不输出伪数值；
- Brier/ECE 恢复 30 条、10 个信号日门槛；
- 决策 CSV 遵循来源、阶段、日期、方向、市场状态、模型版本和回溯筛选；
- CSV 包含证据日、阶段、门禁和完整 1/3/5 日字段；
- 导出数量使用快照数而不是 outcome 行数或历史留档数。

### 12.6 UI 回归测试

- 新模型默认选择盘前 1 日；
- 历史实时页显示非校准警告；
- 中性稳定率不混入多空平衡命中；
- 分数桶、方向分布、组件诊断和准备度在窄屏无溢出；
- 单条下钻展示证据日、阶段、目标日和门禁。

## 13. 验收标准

1. `short-term-v3` 与所有旧模型数据完全隔离；
2. 生产 40..90 强度信号不再饱和，强弱、时长和置信度真实生效；
3. 所有生产信号只进入唯一组件和指标族；
4. 估值合成分不再提供短线多头方向偏置；
5. 相对强弱以个股相对大盘表现为零中心；
6. 盘前留档的 1 日结果在当日盘后成熟；
7. 盘前 1 日收益、Alpha、可执行收益和 MFE/MAE 使用同一正确锚点；
8. 回溯补录样本默认不进入胜率、校准和导出；
9. 留档页能展示多空平衡命中、方向化收益、分数桶、相关性、方向偏斜和五维表现；
10. 决策 CSV 遵循当前筛选并包含完整诊断字段；
11. Brier/ECE 和模型调权准备度不在样本不足时给出误导结论；
12. 新增聚焦测试、评分/留档/数据库回归测试和完整 Flutter 测试通过；
13. 对最终差异执行结构化代码评审并修复所有 Critical 和 Important 问题；
14. `mobile/pubspec.yaml`、`app_version.dart` 和 `update_log_screen.dart` 同步更新为
    `3.31.20260716`；
15. `mobile/build_release.ps1` 构建成功，并在项目根目录生成
    `stock-v3.31.20260716.apk`；
16. Git 只提交本次规格、代码、测试和版本文件，不带入现有工作区噪音。

## 14. 发布后验证

本版本发布后，从 `short-term-v3` 开始重新积累盘前样本。真实准确性判断按以下顺序：

1. 先确认 1 日结果当日盘后正常成熟且覆盖率稳定；
2. 再观察看多/看空平衡命中和 Alpha 命中；
3. 检查方向分与收益相关性是否持续为正；
4. 检查强度桶是否逐步呈现单调性；
5. 检查五维组件是否存在长期反向相关；
6. 样本准备度全部达标后，另立 `short-term-v4` 权重优化设计；
7. 任何后续调权必须使用时间外验证，并同时检查 Alpha、MFE/MAE 和校准质量，
   不能只最大化单一命中率。
