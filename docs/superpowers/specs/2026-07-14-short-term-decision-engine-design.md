# 短线决策与评价体系重构设计

日期：2026-07-14

状态：已确认，待实施计划

初始模型版本：`short-term-v2`

## 1. 背景

当前留档 `archive_export_20260714_210422.csv` 共 363 条记录，全部在
2026-07-13 23:23 留档，并在下一个交易日收盘后导出。看多命中率为
77.06%，看空命中率为 26.94%，但同一股票池当天涨或平的基准比例为
75.76%，跌或平的基准比例为 25.90%。去除平盘后，方向平衡准确率仅
51.63%，MCC 为 0.028，当前结果主要反映 2026-07-14 的普涨市场状态，
不能证明现有评分具有稳定的方向区分能力。

代码审计同时确认以下结构性问题：

1. 5 分在推荐、置信度、预测支持、回测反馈和留档评价中的方向语义不一致。
2. 看空侧的反弹保护校准会返回更高分，但集成链路只接受降分，导致保护失效。
3. 自选机会池留档路径没有把已获取的大盘环境传入分析引擎。
4. 风险、方向、交易质量被压缩为同一个 1 至 10 分，风险扣分会被误读为看空预测。
5. 技术、共振、结构、资金、实时和所谓基本面重复使用相同价量变量。
6. 短线目标定义为 1 至 10 个交易日，但追踪器按日历日记录 5/10/20 日结果，
   且只追踪 6 分以上多头推荐。
7. 当前置信度是启发式证据一致性指数，并非经过校准的上涨或下跌概率。
8. 留档使用未复权裸价差，除权除息会造成方向误判。

本设计重构短线决策、推荐、追踪和评价体系。历史接口继续兼容，但不再作为
新体系的事实来源。

## 2. 目标

### 2.1 产品目标

- 面向 1、3、5 个交易日的 A 股短线决策。
- 明确区分方向预测、交易质量、风险和证据一致性。
- 推荐、置信度、回测、追踪和留档使用唯一方向语义。
- 同时评价绝对收益、相对指数 Alpha 和可执行收益。
- 使用真实交易日和复权行情，避免日历日回填及除权污染。
- 在数据充分前保持固定权重，不用少量样本自动调权。

### 2.2 工程目标

- 通过新增模型和兼容适配器渐进迁移，不破坏已有页面和历史数据。
- 数据库迁移只新增表和索引，不删除旧表或改写历史记录。
- 每条决策保存模型版本、来源和完整评分明细，结果可复核。
- 关键策略规则保持纯 Dart、确定性和可单元测试。

## 3. 非目标

- 本阶段不引入后端服务、LLM 或云端训练。
- 本阶段不根据 2026-07-14 单日数据重调指标权重。
- 本阶段不把看空建议解释为默认可执行的融券做空交易。
- 本阶段不自动回填旧留档缺失的市场环境、复权价格或固定周期结果。
- 本阶段不以单一命中率替代收益、Alpha、MFE、MAE 和校准指标。

## 4. 术语与唯一方向语义

新增统一枚举：

```dart
enum RecommendationDirection {
  bullish,
  neutral,
  bearish,
}
```

所有推荐、预测支持、置信度、回测反馈、留档评价和统计筛选必须调用同一个
方向解析器，不允许再通过字符串包含关系或不同分数边界各自判断方向。

- `bullish`：预期目标周期收益为正。
- `bearish`：预期目标周期收益为负；对普通 A 股用户主要表示回避、减仓或
  暂不参与，不默认表示建立空头仓位。
- `neutral`：方向证据不足或预期波动落在中性区间。

兼容展示分中的 5 分只代表中性。旧的“偏多观望”不再映射为 5 分。

## 5. 总体架构

采用双轨兼容迁移：

```text
K线/行情/资金/板块/大盘
          |
          v
ShortTermDecisionEngine
  |-- DirectionalEvidenceBuilder
  |-- TradeQualityEvaluator
  |-- RiskEvaluator
  |-- EvidenceConfidenceCalculator
          |
          v
ShortTermDecision
          |
          +--> RecommendationPolicy --> RecommendationDecision
          |
          +--> LegacyDecisionAdapter --> totalScore/recommendation
          |
          +--> DecisionTracker --> 1/3/5日结果
          |
          +--> DecisionCalibrator --> 有条件的校准概率
```

建议新增文件：

```text
mobile/lib/analysis/short_term_decision_engine.dart
mobile/lib/analysis/directional_evidence_builder.dart
mobile/lib/analysis/trade_quality_evaluator.dart
mobile/lib/analysis/short_term_risk_evaluator.dart
mobile/lib/analysis/evidence_confidence_calculator.dart
mobile/lib/analysis/recommendation_policy.dart
mobile/lib/analysis/decision_calibrator.dart
mobile/lib/analysis/decision_outcome_evaluator.dart
mobile/lib/analysis/legacy_decision_adapter.dart
mobile/lib/analysis/decision_tracker.dart
```

现有 `generateAnalysis()` 继续作为聚合入口，但内部生成 `ShortTermDecision`，
再通过适配器填充历史字段。

## 6. 核心数据模型

### 6.1 ShortTermDecision

```dart
class ShortTermDecision {
  final double directionScore;       // -100..100
  final double tradeQualityScore;    // 0..100
  final double riskScore;            // 0..100, 越高风险越高
  final double evidenceConfidence;   // 0..100, 非概率
  final double? calibratedProbability;
  final int calibratedSampleCount;
  final RecommendationDirection direction;
  final MarketRegime marketRegime;
  final Map<String, double> directionComponents;
  final Map<String, double> qualityComponents;
  final Map<String, double> riskComponents;
  final List<String> dataQualityFlags;
  final String modelVersion;
}
```

`directionScore` 只表达方向，风险变化不得直接改变其正负号。

### 6.2 RecommendationDecision

```dart
class RecommendationDecision {
  final RecommendationDirection direction;
  final RecommendationLevel level;
  final String label;
  final int legacyScore;
  final bool actionable;
  final List<String> gates;
}
```

`actionable=false` 表示方向判断存在，但交易质量、风险或数据质量不允许形成
可执行建议。

### 6.3 市场状态

```dart
enum MarketRegime {
  bullishTrend,
  bearishTrend,
  rebound,
  pullback,
  range,
  highVolatility,
  unknown,
}
```

市场状态必须随决策快照保存。缺失时使用 `unknown` 并增加数据质量标记，
不能静默按中性市场处理。

## 7. 方向评分

### 7.1 独立证据桶

方向证据先归一化为 `-1..1`，每个原始指标只能进入一个主证据桶：

| 证据桶 | 初始权重 | 主要输入 |
|---|---:|---|
| 趋势 | 30% | MA 排列、ADX、趋势持续性 |
| 反转/动量 | 25% | RSI、KDJ、WR、BIAS、反转K线形态 |
| 量价/资金 | 20% | 成交量、OBV、主力流、换手 |
| 相对强弱 | 15% | 个股相对大盘及行业表现 |
| 次交易日预测 | 10% | 现有 next-day/next-session 预测支持 |

MACD 的趋势部分归入趋势桶，超买超卖或背离解释归入反转/动量桶，但同一信号
不能在两个桶重复贡献。共振只计算五个桶之间的一致性，不重新读取指标。

初始实现复用现有单项指标的阈值和方向解释，不在本次重构中同时改变 RSI、KDJ、
WR、MA、ADX 等指标公式。重构只负责指标归属、归一化、去重和聚合；后续若调整
单项阈值，必须使用独立数据验证和单独版本号。

### 7.2 聚合公式

```text
stockEvidence = 100 * sum(componentValue * componentWeight)
directionScore = clamp(stockEvidence * 0.80 + marketBias * 0.20, -100, 100)
```

`marketBias` 由统一市场状态提供，范围 `-100..100`。市场贡献最多 20%，不再
同时执行市场乘数和大盘额外扣分。

初始映射固定为：

| MarketRegime | marketBias |
|---|---:|
| bullishTrend | 50 |
| rebound | 25 |
| range | 0 |
| highVolatility | 0，同时增加风险分 |
| pullback | -20 |
| bearishTrend | -50 |
| unknown | 0，同时增加数据质量标记 |

### 7.3 反转与追涨保护

满足以下任一跌幅条件，并存在超卖或反转证据时，触发反弹保护：

- 当日跌幅不高于 -5%；
- 最近 3 个交易日跌幅不高于 -5%；
- 最近 5 个交易日跌幅不高于 -8%。

超卖或反转证据包括 RSI6 < 35、WR14 > 80、BIAS6 < -3、有效看多反转形态，
或归一化反转桶不低于 0.35。除非趋势和量价两个独立桶都不高于 -0.45，
否则最终 `directionScore` 不得低于 -19，即最多输出弱看空观察。

上涨侧执行对称保护：当日涨幅不低于 8% 或 3 日涨幅不低于 12%，且动量出现
超买/背离时，若趋势和量价不能同时确认，`directionScore` 不得高于 34。

## 8. 交易质量与风险

### 8.1 TradeQualityScore

交易质量不表达涨跌方向，由以下部分构成：

| 分项 | 权重 |
|---|---:|
| 信号时效与入场位置 | 30% |
| 量价确认 | 25% |
| 流动性与换手质量 | 20% |
| 支撑阻力和盈亏比 | 15% |
| 主策略独立支持 | 10% |

现有 `ShortTermScorer` 的有效逻辑迁移到这些分项。短线质量既能提高也能降低
参与级别，不再只是对综合分设置上限。

### 8.2 RiskScore

风险分由以下部分构成：

| 分项 | 权重 |
|---|---:|
| ATR 与近期波动 | 25% |
| 跳空、涨跌停及成交约束 | 25% |
| 追高或超跌执行风险 | 20% |
| 流动性风险 | 15% |
| ST、事件和数据质量风险 | 15% |

风险只能改变 `actionable`、仓位级别和推荐强度，不能把看多方向直接改成看空。

## 9. 推荐策略

### 9.1 方向区间

| directionScore | 基础方向级别 |
|---:|---|
| >= 55 | 强看多 |
| 35..54.99 | 看多 |
| 20..34.99 | 谨慎看多 |
| 12..19.99 | 偏多观察 |
| -11.99..11.99 | 中性观察 |
| -19.99..-12 | 偏空观察 |
| -34.99..-20 | 谨慎看空/减仓 |
| -54.99..-35 | 看空/回避 |
| < -55 | 强看空/强回避 |

### 9.2 多头执行门槛

- 强看多：质量 >= 70、风险 <= 45、证据一致性 >= 65。
- 看多：质量 >= 60、风险 <= 60、证据一致性 >= 55。
- 谨慎看多：质量 >= 55、风险 <= 70。
- 未通过门槛时保留方向，但降为“偏多观察”，不改变方向分。

### 9.3 看空语义

看空级别表示已有持仓的减仓优先级或未持仓时的回避级别。反弹保护生效、
证据一致性低于 55 或数据质量存在关键缺失时，强看空/看空必须降为偏空观察。

### 9.4 兼容评分

兼容分只用于旧页面：

| 新级别 | 兼容分 |
|---|---:|
| 强看空 | 1 |
| 看空 | 2 |
| 谨慎看空 | 3 |
| 偏空观察 | 4 |
| 中性观察 | 5 |
| 偏多观察 | 6 |
| 谨慎看多 | 7 |
| 看多 | 8 |
| 强看多 | 9 |
| 强看多且质量>=85、风险<=30、证据>=80 | 10 |

## 10. 证据一致性与校准概率

### 10.1 EvidenceConfidence

证据一致性指数由以下部分组成：

- 独立证据桶方向一致性：40%。
- 输入数据覆盖率和质量：25%。
- 信号时效性：20%。
- 已成熟历史样本的稳定性：15%。

该值只表示当前证据是否完整、独立且一致。UI 不使用“上涨概率”描述它。

### 10.2 CalibratedProbability

校准概率按以下维度分桶：

- 目标周期：1、3、5 个交易日；
- 方向：看多、看空；
- 方向强度区间；
- 市场状态；
- 模型版本。

满足以下条件才输出：

- 至少 100 条成熟有效样本；
- 至少覆盖 20 个不同信号交易日；
- 行情覆盖率不低于 95%；
- 全局基准率和分桶样本必须来自同一模型版本。

命中率使用 Beta-Binomial 收缩，默认先验为同周期、同方向的全局基准率，
先验等效样本量固定为 20：

```text
posteriorProbability = (hits + globalBaseRate * 20) / (sampleCount + 20)
```

`calibratedProbability` 表示对应周期的“有效方向命中”概率，不表示预期收益率。
输出同时包含样本数和 Wilson 区间。概率必须在信号生成时写入快照，历史快照不得
根据已知结果反向补写概率。Brier 使用逐条、信号时已保存的概率计算，ECE 使用
10 个等宽概率区间计算；空区间不进入加权汇总。冷启动阶段达到样本门槛后可以为
后续新快照生成概率；当同桶至少 30 条带预测概率的结果成熟且覆盖至少 10 个交易日
后，才展示 Brier 和 ECE，它们不作为首个校准概率的准入条件。

## 11. 数据持久化

数据库由版本 20 升级至 21，新增两张表。

### 11.1 decision_snapshots

主要字段：

```text
id, code, name, source, signal_time, signal_trade_date,
signal_price, adjusted_signal_price, benchmark_code, sector_name,
direction, direction_score, trade_quality_score, risk_score,
evidence_confidence, calibrated_probability, calibrated_sample_count,
recommendation_level, recommendation_label, legacy_score,
market_regime, market_change_pct, model_version,
direction_components_json, quality_components_json,
risk_components_json, data_quality_flags_json, created_at
```

唯一约束：`code + source + signal_trade_date + model_version`。同一股票不同来源可以
分别追踪，同一来源同一交易日不得被刷新操作重复写入。

### 11.2 decision_outcomes

主要字段：

```text
id, snapshot_id, horizon, status, due_trade_date, evaluated_at,
entry_open_price, target_close_price, adjusted_target_close_price,
forecast_return, executable_return, benchmark_return, alpha_return,
mfe, mae, raw_direction_hit, effective_direction_hit, alpha_hit,
corporate_action_detected, invalid_reason
```

唯一约束：`snapshot_id + horizon`。`horizon` 仅允许 1、3、5。

旧 `archive_records` 和 `recommendation_tracking` 保留，不自动混入新统计。

## 12. 结果评价

### 12.1 价格口径

- 方向预测收益：信号日复权收盘价到目标日复权收盘价。
- 可执行收益：下一交易日开盘价到目标日收盘价。
- MFE/MAE：从可执行入场日至目标日，使用复权高低价计算。
- 基准收益：同周期基准指数收盘收益。
- Alpha：方向预测收益减基准收益。

行情评价必须使用实际 K 线日期。延迟刷新时分别读取各到期交易日价格，不能用
同一个当前价回填多个周期。

### 12.2 命中口径

- 原始方向命中：看多收益 > 0，看空收益 < 0。
- 有效方向命中：方向化收益超过 0.5%，用于过滤噪声和基本交易成本。
- Alpha 命中：看多 Alpha > 0，看空 Alpha < 0。
- 中性稳定：绝对 Alpha <= 0.5%。
- 收益恰好为 0 不计入看多或看空命中，只能归入中性稳定。

### 12.3 除权、停牌和不可交易

- 统一使用前复权 K 线计算结果。
- 裸价变动与交易所涨跌幅明显冲突时标记 `corporate_action_detected`。
- 目标日停牌则保持待评价，直到出现下一个有效交易日，并记录延期。
- 下一交易日一字涨停无法买入或一字跌停无法卖出时，方向预测仍评价，
  可执行收益标记为无效。

## 13. 调用链迁移

### 13.1 SignalEngine

`generateAnalysis()` 新增或构造统一输入对象，包含必需的大盘和板块上下文。
生成 `ShortTermDecision` 后：

1. 保存到 `AnalysisResult.shortTermDecision`；
2. 通过 `LegacyDecisionAdapter` 生成旧字段；
3. 所有推荐理由使用新模型分项；
4. 不再调用旧的单向分数封顶和方向不一致的置信度逻辑。

### 13.2 OpportunityEngine

已获取的市场状态必须转换为 `MarketContext/MarketRegime` 并传入分析。若获取失败，
保存 `unknown` 和数据质量标记，不允许调用方无感知地继续按完整数据输出高置信推荐。

### 13.3 推荐跟踪

所有 bullish、neutral、bearish 决策均可追踪。新追踪器不使用“已有活跃代码”阻止
后续交易日的新决策，只按快照唯一约束去重。

现有 `WeightOptimizer` 停止参与新模型。统计页可以继续读取旧数据，但明确标记为
历史实验数据。

## 14. UI 与导出

### 14.1 个股决策页

展示四个独立指标：

- 方向；
- 交易质量；
- 风险；
- 证据一致性。

达到校准门槛时额外显示校准概率、样本数和周期。未达门槛时不显示百分比占位值。

### 14.2 留档页

- 增加 1/3/5 日切换。
- 主指标为 Alpha 命中和有效方向命中。
- 原始方向命中作为辅助指标。
- 显示成熟样本数、待评价数、无效数和行情覆盖率。
- 支持按方向、市场状态、模型版本和来源筛选。
- 旧记录单独显示“历史口径”，不与新版指标合计。

### 14.3 推荐统计页

按周期、方向、市场状态和方向强度展示：

- 样本数和交易日数；
- 命中率及 Wilson 区间；
- 平均/中位收益和 Alpha；
- MFE、MAE；
- Brier、ECE；
- 分数桶单调性。

### 14.4 CSV 导出

新增字段至少包括：

```text
模型版本, 来源, 信号交易日, 方向, 方向分, 交易质量分, 风险分,
证据一致性, 校准概率, 校准样本数, 市场状态, 基准指数,
趋势证据, 反转动量证据, 量价资金证据, 相对强弱证据, 次日预测证据,
1日状态, 1日收益, 1日Alpha, 1日MFE, 1日MAE,
3日状态, 3日收益, 3日Alpha, 3日MFE, 3日MAE,
5日状态, 5日收益, 5日Alpha, 5日MFE, 5日MAE, 除权标记
```

其中 MFE/MAE 必须按周期分别导出为 `1日MFE/1日MAE`、`3日MFE/3日MAE`、
`5日MFE/5日MAE`，不能用单一列混合不同持有周期。

## 15. 错误处理

- 市场、板块、资金或复权行情缺失时记录具体数据质量标记。
- 数据覆盖不足会降低证据一致性，并阻止输出高强度可执行推荐。
- 结果评价失败保持 `pending`，记录错误，不写入虚假 0 收益。
- JSON 明细解析失败时保留主字段并记录日志，兼容旧版本。
- 数据库迁移使用 `if (oldVersion < 21)`，创建表和索引前检查存在性。

## 16. 测试策略

### 16.1 单元测试

- 唯一方向解析及 4/5/6 兼容边界。
- 五个方向证据桶归一化、去重和聚合。
- 市场贡献最多 20%，无双重扣分。
- 大跌超卖反弹保护及上涨侧对称保护。
- 风险变化不改变方向正负号。
- 推荐门槛和兼容分映射。
- EvidenceConfidence 不被解释为概率。
- 校准最小样本、交易日覆盖、Beta-Binomial、Wilson、Brier 和 ECE。

### 16.2 集成测试

- OpportunityEngine 把市场上下文传入决策引擎。
- 旧看空向上校准场景在完整链路生效。
- `generateAnalysis()` 同时返回新决策和兼容字段。
- 同一输入在详情页、自选页和留档页得到一致方向。
- 延迟刷新分别使用 1/3/5 到期交易日价格。
- 除权除息样本不再被裸价差误判。

### 16.3 数据库测试

- v20 到 v21 升级保留旧表和旧数据。
- 新表唯一约束、外键和索引有效。
- 同一股票可跨交易日保存多个决策。
- 同一快照只生成 1、3、5 三个结果槽位。

### 16.4 回归验证

- 先运行新增聚焦测试。
- 再运行评分、信号、留档、追踪、数据库相关测试。
- 最后运行完整 Flutter 测试和静态分析。
- 使用现有导出数据作为只读基准，验证旧统计不会被误混入新版结果。

## 17. 实施阶段

### 阶段一：核心语义与决策引擎

- 新增核心模型、方向证据、质量、风险、置信度和推荐策略。
- 修复校准集成和 Opportunity 市场上下文传递。
- 增加 LegacyDecisionAdapter。

### 阶段二：持久化与结果追踪

- 数据库升级至 v21。
- 新增快照、结果模型和追踪器。
- 使用实际交易日和复权 K 线完成 1/3/5 日评价。

### 阶段三：页面和导出迁移

- 个股决策页展示新四维指标。
- 留档页和推荐统计页切换新口径。
- CSV 导出新字段，历史导出保持可读。

### 阶段四：校准和验证

- 实现校准器和验证指标。
- 停用新体系中的自动权重优化。
- 完成全量测试、静态分析和人工数据复核。

## 18. 验收标准

1. 5 分在所有模块中只表示中性。
2. 看空反弹保护可以在完整分析链路中降低看空强度。
3. 风险分升高不会将正方向预测改成负方向预测。
4. 自选机会池留档包含市场状态和模型版本。
5. 新追踪覆盖全部方向并生成独立的 1/3/5 交易日结果。
6. 延迟刷新不会使用同一价格回填多个周期。
7. 除权除息不再造成方向误判。
8. 未达到样本门槛时不显示校准概率。
9. 新统计同时提供绝对收益、Alpha、MFE、MAE 和覆盖率。
10. 旧数据可读取但不与新口径混算。
11. 新增测试、相关回归测试和完整测试通过。

## 19. 后续权重调整准入条件

只有同时满足以下条件，才能进入权重优化设计：

- 每个核心方向强度桶至少 100 条成熟样本；
- 样本覆盖至少 20 个不同交易日，并包含上涨、下跌、震荡和反弹状态；
- 1/3/5 日标签完整率不低于 95%；
- 通过时间切分验证，不使用随机打乱替代时间外验证；
- 完成证据桶相关矩阵和留一消融；
- 新权重在 Alpha、MFE/MAE、Brier/ECE 中至少两类指标改善，且无关键市场状态显著退化。

在满足上述条件前，固定权重是正式生产配置。
