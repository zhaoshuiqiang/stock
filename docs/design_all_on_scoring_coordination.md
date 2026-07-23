# 设计文档：全开场景评分修正协调（P0-1 强势趋势护栏）

> 版本：v4.19.20260723 ｜ 状态：设计已评审待实现 ｜ 作者：AI 协作
> 关联记忆：`评分引擎13个实验开关全开状态下的功能实现问题`、`评分引擎实验开关的风险耦合与配置约束`

## 1. 背景与问题

13 个实验开关**全部开启**时，属于一个**未经联合验证的修正叠加态**：每个开关的留档验证都是"单开关单独验证"（`scoring_config.dart` 注释均标注 byte-identical when off）。其中 5 个"抑制趋势/追高"开关会在多层重复扣分：

| 层 | 文件 | 全开动作 |
|---|---|---|
| 信号层 | signal_detector.dart | 趋势强度 75→50、突破 75→50 |
| 技术评分 | technical_scorer.dart | MA 多头 1.4→1.0、ADX 加成 0.5→0.3 |
| 共振 | confluence_scorer.dart | MA 权重 1.5→1.0 |
| 方向证据 | directional_evidence_builder.dart | MA 幅度 0.45→0.35、去 3 日动量、放量 0.55→0.30、加过热惩罚 |
| 实时 | realtime_scorer.dart | 3-5% 由 +0.3 变 -0.3 |

**后果**：真正健康的强势上升趋势股被跨层重复压制，可能被拖出"看多带"（方向分 < +12），与"打板梯队/主线龙头"选强势股的产品目标自相矛盾。

## 2. 本次增量范围（P0-1a）

仅实现 **强势趋势护栏 `strongTrendGuard`**，复用本文件已有的 `oversoldReboundGuard`/`chaseGuard` 护栏范式，最小侵入、可单测、可回退。

**明确不在本次范围（后续增量）**：
- P0-1b 综合评分侧（1-10 分）对称护栏；
- P0-2 `DirectionalWeightOptimizer` 增加 `model_version` 过滤（避免循证校准与动态权重跨版本样本污染）；
- P0-3 超跌反弹侧过度上拉封顶；
- P1 前瞻权重上调、复盘指标（MFE/MAE/Alpha）回流 UI、系统级推送；
- P2 数据源补齐（龙虎榜/竞价/真实成交额）。

## 3. 详细设计

### 3.1 触发条件（全部满足才生效）
1. `ScoringConfig.activeTrendDampenerCount >= 2`：至少 2 个抑制趋势开关同时开（叠加条件；<2 时护栏永不触发，保证与单开关验证结果字节等价）。
2. 确认"健康强势上升趋势" `_hasStrongHealthyUptrend`：
   - 均线多头 `ma5>ma10>ma20>0`；
   - 收盘价在 `ma5` 上方；
   - `adx14>=25` 且 `+DI>-DI`（趋势强且向上）；
   - **排除抛物线/追高**（这是追高惩罚的职责，不重复救援）：当日涨幅 <7%、`bias6<8`、`rsi6<80`、连涨 <4 天、非日内跳水(收/开跌幅 >-3%)。
3. `0 <= 方向分 < +12`：叠加抑制把强势股拖入"弱中性带"。仅从 [0,12) 救援；若已 <0 说明存在足够强的反向证据，不覆盖。

### 3.2 动作
将 `guardedDirectionScore` 下限抬到 `kDirectionBullishThreshold`(+12)，追加 `guardReasons.add(strongTrendGuard)`。仅上抬、不下压。抬到 +12（"刚好看多"）而非强多，属**保守修复**，不使用任何魔法数（复用既有阈值常量）。

### 3.3 不变量与回退
- `activeTrendDampenerCount < 2` 时护栏不触发 → 与现网**字节等价**，单开关留档结论不受影响。
- 与 `chaseGuard`（上限 34）互斥：触发条件排除追高，二者不会同时命中。
- 与 `oversoldReboundGuard`（下限 -19，作用于空头）方向相反、场景互斥。
- 关闭全部开关或仅开 1 个即可完全回退。

## 4. 测试计划（新增 test/all_on_trend_guard_test.dart）
1. 全关：强势趋势股，护栏不触发，方向分与基线一致（字节等价）。
2. 全开(>=2 抑制)：强势趋势股方向分被抬到 >= +12，`guardReasons` 含 `strong_trend_guard`。
3. 反例：全开但为抛物线/追高股，护栏不触发（不与追高惩罚打架）。
4. 反例：全开但已明确空头(方向分<0)，护栏不触发。

## 5. 验证与发布
- `flutter analyze` 无新增告警；
- `flutter test`：新增用例 + directional_evidence_builder_test + release_ritual_guard_test 全绿；
- 版本三件套同步 4.19.20260723；
- 后续用留档脚本对"全开 vs 默认"做强势股子样本命中率联合验证，据此决定是否推进 P0-1b/P0-2。
