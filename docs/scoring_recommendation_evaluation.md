# 评分与推荐机制评估报告（三视角）

> 版本：v4.3.20260719 ｜ 数据/代码依据：截至本版本的 mobile/lib 实现
> 配套实测脚本：`scripts/analyze_decision_accuracy.py`（读取真实 v3 决策表）

本报告以**专业股票分析师**、**策略研究专家**、**普通用户**三种视角，对评分机制、
推荐机制与潜在优化点进行评估，并记录本版本已落地的优化与启用方式。

---

## 0. 最关键结论：存在"双评分系统"

- **影子/遗留系统**（历史文档与直觉所指）：`ComprehensiveScorer`（7 维加权、硬编码权重、
  ≥8/≥7/≥6/≥5 阈值）+ `WeightOptimizer` + `RecommendationCalibrator`。
- **真实生效系统（v3）**：`DirectionalEvidenceBuilder`（6 维方向分 directionScore）
  → `RecommendationPolicy`（±12/±20/±35/±55 分档 + 交易质量/风险/证据置信度门控）
  → `DecisionCalibrationService`（Wilson + Beta-Binomial 校准），落库
  `decision_snapshots`/`decision_outcomes`，由 `DecisionStatistics` 产出 Brier/ECE/alpha 命中。

**证据**：`signal_engine.dart:540-541` 展示分与推荐取自 `recommendationDecision.legacyScore/label`
（源自 v3 决策引擎）；`ComprehensiveScorer.combine()` 结果仅作为 `rawComprehensiveScore` 输入之一。
真实 6 维权重见 `directional_evidence_builder.dart:125-132`：
trend 0.25 / reversal_momentum 0.25 / volume_flow 0.20 / relative_strength 0.15 /
sector_momentum 0.10 / next_session 0.05。

---

## 1. 评分机制评估

### 专业分析师视角
- **科学性（较好）**：v3 用带方向证据加权成 directionScore，并有"趋势+量价双确认"守护裁剪；
  校准层采用 Wilson 区间 + Beta-Binomial 后验，采样门槛严格（每桶 ≥100 样本、≥20 个信号日、
  ≥95% 评估率），符合稳健统计做法。
- **短板（本版本已补）**：原本校准仅"描述性"（能算命中率/Brier/ECE），但**无处方性回调**——
  不会据实测命中率调整 6 维权重或分档阈值。本版本新增 `DirectionalWeightOptimizer`（权重）
  与 `RecommendationThresholdCalibrator`（阈值）两个数据驱动校准器。
- **基本面**：原 ROE 缺省 5.0；本版本接入 `QuoteData.roe` 并在 `FundamentalAnalyzer` 生效。

### 策略研究专家视角
- **客观性**：阈值/权重为常量，无逐股主观干预，一致性好；但为经验设定，需用实测收益回测校准
  （本版本提供校准器 + 采样门槛，达标后方偏离默认，`maxAdjustment` 保守夹取）。
- **准确性测量修正**：原 `analyze_scoring_accuracy.py` 读取遗留表，测错了对象。新增
  `scripts/analyze_decision_accuracy.py` 读取真实 v3 表，产出方向×强度带×市场态×horizon 的
  effective_hit / alpha / Wilson / Brier / ECE。

### 普通用户视角
- **可理解性（本版本已提升）**：原评分解释页描述的是影子 7 维路径，与实际不符。已重写
  `scoring_explanation_screen.dart`，从真实引擎常量渲染（6 维权重 + 分档阈值 + 执行门控 + 校准）。
- **透明度（本版本已提升）**：新增 `ScoreBreakdownCard`，在详情页展示 5 维方向证据逐项贡献 +
  1/3/5 日真实校准胜率与 Wilson 区间（受开关控制）。

---

## 2. 推荐机制评估

- **有效性**：v3 用执行门控过滤"方向对但质量差"的信号，方向性设计合理；分档阈值本版本可由
  `RecommendationThresholdCalibrator` 依据分桶实测命中率标定（欠佳则收紧、过好则放宽，保序）。
- **个性化（本版本起步）**：原仅 `preferredDuration` 一个可调项。本版本引入风险偏好档位框架
  （见第 4 节 P3），保守/均衡/激进映射为门控松紧。
- **过度/不足推荐**：需用 `scripts/analyze_decision_accuracy.py` 的实测报告量化（按推荐标签的
  真实命中率与平均收益）；报告脚本已就绪，待真实追踪数据积累。

---

## 3. 潜在优化点（性能/UI/功能/UX）

- **性能**：批量扫描仍在 UI isolate 上串行分析（`explore_engine.dart` 循环），大批量会掉帧——
  建议 isolate 化（P4.1，后续）；DB 索引本版本已补齐 `opportunity_results`/`sector_pick_results`
  排序索引与 `recommendation_tracking(is_closed, signal_date)` 复合索引（DB v25）。
- **UI**：缺骨架屏；`quote_screen.dart`(4008)/`watchlist_screen.dart`(4037) 巨型 build 有重建成本。
- **功能**：ROE 已接入；跨周期（周/月线联动）证据仍缺；回测已较完整。
- **UX**：评分解释与个股明细已透明化；持仓上下文/动态止损/风险货币化仍待完善（P3 后续）。

---

## 4. 本版本已落地的优化（v4.3）

| 阶段 | 内容 | 开关/默认 | 验证 |
|---|---|---|---|
| P0.1 | v3 准确性分析脚本 | 离线脚本 | 可运行（无 DB 时优雅提示） |
| P0.2 | 推荐映射金测 | 常开 | 10 用例 |
| P0.3 | `ScoringConfig` 特性开关+版本打标 | 全默认关 | — |
| P1.1 | 评分解释页改为真实 v3 引擎（常量渲染） | 常开 | 静态分析通过 |
| P1.2/P2.3 | `ScoreBreakdownCard`（5 维贡献 + 校准胜率） | 校准展示受 `showCalibratedProbability` 控 | 4 组件测试 |
| P1.3 | ROE 接入（模型/评分/最佳努力数据源/解析器） | 加法式 | 13 用例 |
| P2.1 | `DirectionalWeightOptimizer`（6 维权重数据驱动） | `useDynamicDirectionWeights`（默认关） | 8 用例 |
| P2.2 | `RecommendationThresholdCalibrator` + 阈值可注入策略 | `useCalibratedThresholds`（默认关） | 6 用例 |
| P2.4 | 删除死代码 `RecommendationCalibrator`；归档 `WeightOptimizer` | — | 全量回归 |
| P4.2 | DB v25 分析表索引 | 幂等迁移 | 全量回归 |

**全量测试**：`flutter test` → 1094 通过 / 6 跳过（网络）/ 0 失败；所有校准开关默认关闭，
关闭态行为与历史一致（金测护栏）。

### 如何启用数据驱动校准（数据积累充足后）
1. `ScoringConfig.useDynamicDirectionWeights = true`：`main.dart` 启动时
   `DirectionalWeightOptimizer.loadAndApply()` 读取 `decision_outcomes` 真实命中，达采样门槛
   （≥100 样本且 ≥20 个交易日）后应用优化权重，否则回退默认。
2. `ScoringConfig.useCalibratedThresholds = true` + 注入
   `RecommendationThresholdCalibrator.optimize(bandStats)` 结果到
   `RecommendationPolicy.applyThresholdOverride(...)`。
3. `ScoringConfig.showCalibratedProbability = true`：详情页展示校准胜率区间。
4. 启用前后各跑一次 `scripts/analyze_decision_accuracy.py` 对比命中率/ECE，确认改善再默认开启。

---

## 5. 预期效果（量化目标，待实测验证）
- 可执行看多档（谨慎买入+）3 日 effective_direction_hit 绝对 +5~8pp（达采样门槛后）。
- 展示分校准误差 ECE 下降 ≥30%。
- 评分解释与真实引擎一致性 100%（本版本已达成）。
- DB 分析表热查询延迟 <10ms（索引命中）。

---

## 6. 后续工作（尚未完成）
- P3.2/3.3：持仓上下文感知、动态止损、风险货币化（详情页 UI 深度集成）。
- P4.1：批量扫描 isolate 化（需保证分析可 isolate 传参）。
- P4.3：骨架屏与巨型页面拆分。
- 风险偏好档位的设置页 UI 与端到端下传（本版本提供后端框架）。
