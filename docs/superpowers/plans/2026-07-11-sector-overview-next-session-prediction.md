# Sector Overview And Next Session Prediction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复首页热门板块“查看全部”只展示涨幅前排、布局密度不足的问题，并设计一套可验证的次日/下一次开盘预测评分 POC，避免把滞后的技术强弱评分误用成短线方向预测。

**Architecture:** 板块页只做 API 取数能力和 UI 展示密度调整，不改变首页热门板块卡片的轻量展示定位。评分体系拆成“综合强弱评分”和“次日预测评分”两条链路，先用本地历史数据做 walk-forward POC 验证，再决定是否接入正式推荐。预测逻辑保持纯客户端、可解释、可回测，严禁引入后台服务、LLM 调用或无法解释的黑盒依赖。

**Tech Stack:** Flutter/Dart, existing `ApiClient`, existing analysis modules under `mobile/lib/analysis/`, existing models under `mobile/lib/models/stock_models.dart`, focused Flutter/unit tests under `mobile/test/`.

---

## 0. Approval Gate

本文档是后续开发唯一基准。正式开发前必须由用户确认。

未经用户确认，不允许：

- 修改生产代码。
- 调整现有推荐权重。
- 把 POC 预测结果直接接入买入/卖出推荐。
- 新增数据库表或迁移。
- 大范围重构 `signal_engine.dart`、`api_client.dart` 或 UI 结构。
- 修改版本号、更新日志或构建 APK。

如果开发中发现本文档与真实代码冲突，必须先更新文档并再次确认，不能直接按个人判断扩大范围。

## 1. Current Findings

### 1.1 热门板块查看全部

现有入口和链路：

- 首页入口：`mobile/lib/screens/home_screen.dart` pushes `SectorOverviewScreen`。
- 查看全部页：`mobile/lib/screens/sector_overview_screen.dart`。
- 行业板块取数：`ApiClient.getHotSectors(limit: 60)`。
- 概念板块取数：`ApiClient.getConceptSectors(limit: 60)`。
- 底层请求：`ApiClient._fetchSectors(...)` 使用 EastMoney `fid=f3`，按涨跌幅排序，只取第一页。

根因：

- “查看全部”实际不是全量列表，而是涨幅榜第一页。
- 只取 `limit: 60`，且排序偏向上涨板块，跌幅靠后的板块天然看不到。
- 页面卡片 padding、字体、网格比例偏大，单位屏幕能显示的数据偏少。

### 1.2 现有评分推荐机制

现有链路：

- 主入口：`mobile/lib/analysis/signal_engine.dart` 的 `generateAnalysis()`。
- 主评分：`ComprehensiveScorer.combine(...)`。
- 短线修正：`ShortTermScorer.score(...)` 和 `ShortTermScorer.capRecommendationScore(...)`。
- 已有次日预测：`NextDayPredictor.predict(...)`。
- 展示维度包含：`'次日预测': nextDayPrediction.upProbability * 10`。

关键判断：

- 当前主评分本质是“当前技术面/资金面/趋势强弱评分”。
- 它可以服务于趋势跟踪、观察优先级、强弱排序。
- 它不能直接等价于“下一次开盘上涨概率”或“次日收盘上涨概率”。
- 现有技术指标如 MA、MACD、RSI、KDJ、BOLL 对短线预测存在明显滞后性。
- 今日大涨会抬高强弱评分，但短线 T+1 可能面临回调、兑现、板块退潮或高位分歧。

## 2. Product Requirements

### 2.1 热门板块查看全部

目标体验：

- 用户进入“查看全部”后能看到上涨板块和下跌板块。
- 默认不再只展示涨幅榜前排。
- 页面布局更紧凑，同屏展示更多板块。
- 用户可以快速切换行业/概念、涨幅/跌幅/全部。

必须支持：

- 行业板块。
- 概念板块。
- 涨幅排序。
- 跌幅排序。
- 全部视图。
- 加载失败时保留现有错误提示体验。

不做：

- 不做复杂板块详情页重构。
- 不改首页热门板块的小卡片列表逻辑，除非确认需要。
- 不引入无限滚动的复杂状态管理，第一版优先用足够大的分页取数或双向榜单合并。

### 2.2 次日/下一次开盘预测评分

目标体验：

- 明确区分“当前强弱”和“下一交易时段预测”。
- 给出下一次开盘、次日收盘两个方向概率。
- 给出风险标签，而不是只给一个高分。
- 对“今日大涨但明日可能回调”的场景有明确约束。

必须输出：

- `nextOpenUpProbability`：下一次开盘上涨概率。
- `nextCloseUpProbability`：次日收盘上涨概率。
- `expectedNextCloseReturn`：次日收盘预期收益。
- `downsideRiskProbability`：次日下跌风险概率。
- `confidence`：置信度。
- `sampleCount`：可比历史样本数。
- `scenarioTags`：短线场景标签。
- `riskWarnings`：不追高、回调、板块退潮、放量滞涨等提示。

不做：

- 不承诺预测准确率。
- 不把预测概率伪装成确定性涨跌判断。
- 不引入后台训练服务。
- 不引入 LLM/API 调用。
- 不做黑盒深度学习模型。
- 不在 POC 通过前替换现有推荐体系。

## 3. Design Principles

### 3.1 评分拆分

后续必须拆分两个概念：

- `综合强弱评分`：股票当前技术趋势、资金、结构和相对强度。
- `次日预测评分`：下一次开盘/次日收盘的概率判断。

推荐展示必须遵守：

- 综合强弱高，不等于明天上涨。
- 次日预测高，不等于中期趋势好。
- 今日暴涨后，如果预测回调风险高，推荐文案必须降级为“不追高/等回踩”。
- 如果综合强弱一般但超跌反弹概率高，只能标记为“短线反弹观察”，不能直接强推荐。

### 3.2 可解释优先

POC 第一版采用规则特征 + 历史相似样本校准：

- 每个预测结论必须能解释由哪些特征触发。
- 每个概率必须能追溯到历史样本或规则权重。
- 所有阈值必须有测试覆盖或回测证据。

### 3.3 严禁未来函数

预测第 T+1 日时，只允许使用第 T 日收盘前已经可见的数据。

严禁使用：

- T+1 的开盘、最高、最低、收盘。
- T+1 的成交量。
- T+1 后才知道的板块排序。
- 使用全样本统计后再回填历史预测结果的泄漏做法。

所有 POC 验证必须使用 walk-forward：

- 对每个历史 T 日，只能用 T 日之前的数据校准。
- 再预测 T+1。
- 最后汇总结果。

### 3.4 A 股短线语义

预测逻辑必须显式考虑：

- 追高风险。
- 涨停/接近涨停后的延续与回落分化。
- 长上影线。
- 放量滞涨。
- 缩量上涨。
- 超跌反弹。
- 板块过热与退潮。
- 大盘环境。
- 连续上涨后的兑现压力。

## 4. Hot Sector Page Design

### 4.1 API Design

Modify:

- `mobile/lib/api/api_client.dart`

New internal request capability:

- `page`：页码，默认 `1`。
- `limit`：每页数量。
- `sortField`：默认 `f3`，即涨跌幅。
- `sortDescending`：默认 `true`。

Public methods:

- Keep `getHotSectors({int limit = 30})` backward compatible.
- Keep `getConceptSectors({int limit = 30})` backward compatible.
- Add `getSectorRanking({required SectorCategory category, required SectorSortMode sortMode, int page = 1, int limit = 100})`.

Suggested enums:

```dart
enum SectorCategory {
  industry,
  concept,
}

enum SectorSortMode {
  gainers,
  losers,
  all,
}
```

Implementation rule:

- `gainers` fetches涨幅排序。
- `losers` fetches跌幅排序。
- `all` fetches both涨幅和跌幅，merge by sector code/name, then sort by涨跌幅 descending or use a neutral combined order defined in UI.

If EastMoney sort direction is verified as `po=1` descending and `po=0` ascending, use those values. If verification shows the opposite, code comments and tests must reflect the actual behavior.

### 4.2 UI Design

Modify:

- `mobile/lib/screens/sector_overview_screen.dart`

UI controls:

- Existing行业/概念切换保留。
- Add sort segmented control:
  - `全部`
  - `上涨`
  - `下跌`

Default:

- Category: 行业。
- Sort mode: 全部。

Layout:

- Phone portrait: 2 columns.
- Width >= 520 logical px: 3 columns.
- Card padding: 8 px.
- Border radius: <= 8 px.
- Use compact text hierarchy.
- Preserve A股颜色：红色上涨，绿色下跌。

Data density:

- First version target: 单屏至少比当前多显示 30% 以上板块卡片。
- Card should show:
  - 板块名。
  - 涨跌幅。
  - 领涨股/代表股 if existing data has it.
  - 换手/成交额 only if existing model already exposes it reliably.

Do not add:

- Marketing-style hero.
- Decorative cards around the whole page.
- Nested cards.
- Heavy animations.

### 4.3 Acceptance Criteria

- “全部”视图可以看到上涨和下跌板块。
- “下跌”视图只看跌幅靠前板块。
- “上涨”视图只看涨幅靠前板块。
- 行业/概念切换后排序模式仍生效。
- API 失败时页面不崩溃。
- Existing calls to `getHotSectors()` keep behavior unchanged.

## 5. Next Session Prediction POC Design

### 5.1 New Files

Create:

- `mobile/lib/analysis/next_session_prediction.dart`
- `mobile/lib/analysis/next_session_feature_extractor.dart`
- `mobile/lib/analysis/next_session_predictor.dart`
- `mobile/lib/analysis/next_session_backtest.dart`
- `mobile/test/next_session_feature_extractor_test.dart`
- `mobile/test/next_session_predictor_test.dart`
- `mobile/test/next_session_backtest_test.dart`

Modify only after POC passes:

- `mobile/lib/analysis/signal_engine.dart`
- `mobile/lib/models/stock_models.dart`
- UI files that display recommendation details.

Do not modify initially:

- `mobile/lib/analysis/comprehensive_scorer.dart`
- `mobile/lib/analysis/recommendation_calibrator.dart`
- Database migrations.

### 5.2 Prediction Model

Core output model:

```dart
class NextSessionPrediction {
  final double nextOpenUpProbability;
  final double nextCloseUpProbability;
  final double expectedNextCloseReturn;
  final double downsideRiskProbability;
  final double confidence;
  final int sampleCount;
  final List<String> scenarioTags;
  final List<String> riskWarnings;

  const NextSessionPrediction({
    required this.nextOpenUpProbability,
    required this.nextCloseUpProbability,
    required this.expectedNextCloseReturn,
    required this.downsideRiskProbability,
    required this.confidence,
    required this.sampleCount,
    required this.scenarioTags,
    required this.riskWarnings,
  });
}
```

Probability constraints:

- Every probability is `0.0 <= value <= 1.0`.
- Low sample count must reduce `confidence`.
- Contradictory signals must reduce `confidence`.
- If no enough historical samples exist, return neutral probabilities near `0.5` with low confidence.

### 5.3 Feature Set

Price action:

- 今日涨跌幅。
- 今日振幅。
- 收盘位置：`(close - low) / (high - low)`。
- 上影线占比。
- 下影线占比。
- 3 日、5 日、10 日涨跌幅。
- 连续上涨天数。
- 连续下跌天数。
- 距 MA5、MA10、MA20 的偏离。

Volume:

- 量比。
- 当前成交量相对 5/10/20 日均量。
- 放量上涨。
- 放量滞涨。
- 缩量上涨。
- 缩量下跌。

Momentum:

- RSI。
- KDJ。
- MACD histogram direction.
- MACD cross state.

Limit-up and chase-risk:

- 是否接近涨停。
- 是否涨停。
- 连续涨停近似特征。
- 今日大涨但收盘不强。
- 今日大涨且长上影。

Capital and market context:

- 主力净流入率 if quote data exposes it.
- 板块涨跌幅 if available from current context.
- 大盘环境 if available from `market_context_provider.dart` or existing API.

### 5.4 Scenario Tags

At minimum support:

- `强势延续`
- `高位回调风险`
- `放量滞涨`
- `缩量上涨不追`
- `超跌反弹`
- `长上影分歧`
- `板块退潮风险`
- `弱势延续`

Tag rules must be deterministic and unit tested.

Example expected behavior:

- 今日涨幅 > 7%、上影线明显、收盘位置低于 0.55：must include `高位回调风险` or `长上影分歧`。
- 今日涨幅 > 5%、量能明显放大、但收盘位置弱：must not output high-confidence bullish result。
- 连续下跌后出现下影线和缩量企稳：may include `超跌反弹`，but confidence depends on samples。

### 5.5 Prediction Algorithm

POC algorithm:

1. Extract current day features.
2. Bin or normalize features into comparable buckets.
3. Search historical days before current day only.
4. Score similarity by price action, volume, momentum, chase risk, and market context.
5. Keep top comparable samples.
6. Compute:
   - next open up ratio.
   - next close up ratio.
   - average next close return.
   - downside ratio.
7. Apply Bayesian shrinkage toward neutral when sample count is small.
8. Apply explicit risk caps for chase-risk scenarios.
9. Produce probabilities, confidence, scenario tags, and warnings.

Required risk cap:

- If today change > 8% and close position is weak, `nextCloseUpProbability` cannot exceed `0.55` unless historical comparable samples are strong and sample count is sufficient.
- If today change > 5% with long upper shadow and heavy volume, bullish confidence must be capped.
- If sample count < minimum threshold, confidence must be low and recommendation integration must treat it as informational only.

### 5.6 Backtest Design

Backtest labels:

- `nextOpenReturn = next.open / today.close - 1`
- `nextCloseReturn = next.close / today.close - 1`
- `nextCloseUp = nextCloseReturn > 0`
- `nextOpenUp = nextOpenReturn > 0`
- `downsideHit = nextCloseReturn < -0.005`
- neutral band: `-0.005 <= return <= 0.005`

Walk-forward rule:

- For day index `i`, training/comparison samples may only use days `< i`。
- Day `i + 1` is label only。

Metrics:

- Accuracy for next open direction.
- Accuracy for next close direction.
- Precision for high-confidence bullish bucket.
- Precision for high-risk bearish bucket.
- Average next close return by probability bucket.
- Brier score.
- Calibration by probability bucket.
- Baseline comparison against naive 50/50 and current strong-score ranking.

POC pass criteria for production integration:

- High-confidence bullish bucket beats baseline next-close hit rate by at least 5 percentage points.
- High-confidence bullish bucket has positive average next-close return after simple transaction cost assumption of 0.2%.
- Probability buckets are directionally monotonic: higher predicted up probability should not have lower realized up rate than the next lower bucket in the main validation set.
- High-risk bucket identifies materially worse realized returns than neutral bucket.
- If criteria fail, prediction may only be displayed as a risk/analysis hint and must not drive recommendation upgrades.

## 6. Recommendation Integration Design

This section is not part of POC implementation until validation passes.

Modify after confirmation:

- `mobile/lib/analysis/signal_engine.dart`
- `mobile/lib/models/stock_models.dart`
- UI recommendation detail widgets/screens.

Integration rules:

- Keep `ComprehensiveScorer` as current-strength score.
- Add `NextSessionPrediction` as separate field in `AnalysisResult`.
- Recommendation text must combine both systems:
  - 强弱高 + 次日上涨概率高：短线可关注。
  - 强弱高 + 次日回调风险高：强势股，不追高，等回踩。
  - 强弱一般 + 超跌反弹概率高：短线反弹观察。
  - 强弱低 + 次日下跌风险高：规避。
- Do not increase buy recommendation solely because current day涨幅大。
- If next-session confidence is low, do not let it override current recommendation.

## 7. Development Tasks

### Task 1: Sector API ranking capability

**Files:**

- Modify: `mobile/lib/api/api_client.dart`
- Test: existing API parsing tests or new focused test under `mobile/test/`

- [ ] Add enum definitions for sector category and sort mode in the smallest appropriate location.
- [ ] Add an internal sector request path that accepts `page`, `limit`, `sortField`, and sort direction.
- [ ] Keep `getHotSectors()` and `getConceptSectors()` behavior backward compatible.
- [ ] Add new `getSectorRanking(...)` method.
- [ ] Unit test URL parameter behavior or extraction helper behavior without requiring live network.
- [ ] Run focused test.

### Task 2: Sector overview compact UI

**Files:**

- Modify: `mobile/lib/screens/sector_overview_screen.dart`

- [ ] Add sort segmented control: `全部`、`上涨`、`下跌`。
- [ ] Default sort mode to `全部`。
- [ ] Use compact card spacing and responsive 2/3 column grid.
- [ ] Preserve loading, empty, and error states.
- [ ] Verify manually on phone-sized viewport or emulator.

### Task 3: Next-session model and feature extractor

**Files:**

- Create: `mobile/lib/analysis/next_session_prediction.dart`
- Create: `mobile/lib/analysis/next_session_feature_extractor.dart`
- Test: `mobile/test/next_session_feature_extractor_test.dart`

- [ ] Add immutable prediction and feature models.
- [ ] Implement price action feature extraction.
- [ ] Implement volume feature extraction.
- [ ] Implement deterministic scenario tags.
- [ ] Add tests for large-rise pullback risk, long upper shadow, volume stall, and oversold rebound.
- [ ] Run focused test.

### Task 4: Next-session predictor POC

**Files:**

- Create: `mobile/lib/analysis/next_session_predictor.dart`
- Test: `mobile/test/next_session_predictor_test.dart`

- [ ] Implement historical comparable sample search.
- [ ] Enforce walk-forward input rule in API shape.
- [ ] Add Bayesian shrinkage for small sample counts.
- [ ] Add chase-risk probability caps.
- [ ] Add tests proving today大涨长上影 does not become high-confidence bullish solely due to trend indicators.
- [ ] Run focused test.

### Task 5: Backtest and metrics

**Files:**

- Create: `mobile/lib/analysis/next_session_backtest.dart`
- Test: `mobile/test/next_session_backtest_test.dart`

- [ ] Implement walk-forward evaluator.
- [ ] Compute direction accuracy, precision, bucket return, Brier score, and calibration buckets.
- [ ] Add tests proving future data is not included.
- [ ] Add tests proving monotonic bucket calculation is stable.
- [ ] Run focused test.

### Task 6: POC report before production integration

**Files:**

- Create or update a report under `docs/superpowers/specs/` or `docs/superpowers/plans/` after metrics are available.

- [ ] Run POC on available historical data.
- [ ] Compare against baseline.
- [ ] State whether pass criteria were met.
- [ ] If criteria fail, document why and keep prediction out of recommendation upgrades.
- [ ] Ask user for confirmation before integration.

### Task 7: Optional production integration

Only execute after user confirms POC result.

**Files:**

- Modify: `mobile/lib/analysis/signal_engine.dart`
- Modify: `mobile/lib/models/stock_models.dart`
- Modify: recommendation UI files identified during implementation

- [ ] Add `NextSessionPrediction` to `AnalysisResult` with backward-compatible nullable field or safe default.
- [ ] Display next-session prediction separately from综合评分。
- [ ] Add recommendation gating rules.
- [ ] Add regression tests for recommendation downgrade on high pullback risk.
- [ ] Run focused and broad tests.

## 8. Verification Commands

Focused tests during development:

```powershell
cd mobile
D:\flutter\bin\flutter.bat test test/next_session_feature_extractor_test.dart
D:\flutter\bin\flutter.bat test test/next_session_predictor_test.dart
D:\flutter\bin\flutter.bat test test/next_session_backtest_test.dart
```

Static checks for changed Dart files:

```powershell
cd mobile
D:\flutter\bin\dart.bat analyze lib/analysis/next_session_prediction.dart lib/analysis/next_session_feature_extractor.dart lib/analysis/next_session_predictor.dart lib/analysis/next_session_backtest.dart
```

Before any production integration claim:

```powershell
cd mobile
D:\flutter\bin\flutter.bat test
```

## 9. Drift Control Checklist

Before each development step, verify:

- The step maps to one task in this document.
- The touched files are listed in that task.
- No unrelated formatting churn is included.
- No version bump is included.
- No generated emulator files or archive exports are staged.
- No user work is reverted.
- Tests are added before behavior changes where practical.
- Any prediction claim is backed by POC metrics.

Stop and ask for confirmation if:

- A required change touches database migrations.
- A required change changes public model serialization.
- The API source cannot provide reliable跌幅榜 or pagination.
- POC metrics fail but implementation would still alter recommendations.
- A production integration requires changing more files than listed here.

## 10. Open Confirmation Items

Before development, user should confirm:

- 热门板块“查看全部”默认是否采用 `全部` 视图。
- `全部` 视图是否按涨跌幅从高到低排列，还是上涨和下跌分区展示。
- 次日预测 POC 是否优先做个股级预测，不先做板块级预测。
- POC 通过前，是否只允许展示预测分析，不允许影响正式推荐。
