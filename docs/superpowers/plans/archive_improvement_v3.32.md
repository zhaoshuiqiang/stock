# 留档页改进方案（v3.32）

> 目标：修复「全市场扫描无数据」问题，并降低「决策命中」模式的操作复杂度。

## 一、现状与根因

### 1. 全市场扫描无数据（两类根因）

**根因 A：默认阶段过滤过严，把盘中扫描快照全部滤掉（主因）**

- 留档「决策命中」模式默认 `signalPhase = preMarket`（`kDefaultDecisionArchiveFilter` = `premarketV3()`，`archive_screen.dart:74-75`、`decision_archive_filter.dart:32-41`）。
- 发现页「市场扫描」（refresh → `ExploreEngine.explore()`）在交易时段运行，快照的 `signalPhase` 由 `TradingDateUtils.signalPhase(now)` 决定：
  - 盘前(<9:30) → `preMarket`
  - 盘中(9:30–15:00) → `intraday`
  - 盘后(>15:00) → `afterClose`（`trading_date_utils.dart:35-47`）
- 过滤 `DecisionArchiveViewFilter.apply` 中 `if (signalPhase != null && snapshot.signalPhase != signalPhase) return false;`（`decision_archive_filter.dart:56-57`）。
- 结果：用户切到「全市场扫描」后阶段仍是 `preMarket`，而扫描快照几乎都是 `intraday/afterClose` → **全部被滤掉 → 显示空**。

**根因 B：决策快照写入链路脆弱、静默失败**

- `ExploreEngine._runDecisionSideEffects`（`explore_engine.dart:246-296`）在结果落库并通知 UI 完成后，用 `unawaited` 异步、fire-and-forget 调用 `captureDecisionBatchForTesting(source: 'explore')`。
- `captureDecisionBatchForTesting`（`decision_tracker.dart:11-27`）对 `analysisList` **逐只 `await tracker.capture(...)` 但无单只 try/catch**。任一 `capture` 抛异常（v3 `evidenceTradeDate` 校验、`saveDecisionSnapshotWithOutcomes` 写库异常等）即中断整个循环，异常被 `explore_engine.dart:258` 的 catch 仅 `debugPrint` 吞掉 → **整批快照可能一条都没存**，用户无感知。

### 2. 操作复杂度过高

「决策命中」模式（`_buildDecisionMode`，`archive_screen.dart:306-420`）单屏堆叠 15+ 交互控件：模式切换、数据源分段、4 个下拉（方向/市场状态/阶段/模型版本）、回溯补录 chip、分组控件（全部/按归档日 + 今日 + 30/60/90 天）、分段分析（按方向/市场状态/阶段 + 柱状图 + 校准）、诊断面板、胜率趋势、自动清理开关、3 个操作按钮。且 App 默认进入即该最复杂模式 → 操作不便。

## 二、改进方案

### A. 修复「全市场扫描无数据」

1. **放宽默认阶段过滤（`archive_screen.dart`）**
   - 初始 `_decisionSignalPhase` 由 `premarketV3().signalPhase`（`preMarket`）改为 `null`（全部阶段）。
   - `_decisionFiltersActive()` 中阶段判定由 `!= DecisionSignalPhase.preMarket` 改为 `!= null`，保证默认（全部阶段）下空状态仍显示引导文案而非「无匹配记录」。
   - 数据源分段 `onSelectionChanged` 中：选 `scan`/`all` → 阶段置 `null`（全部）；选 `manual` → 阶段置 `preMarket`（保留「盘前 V3 留档」语义）。

2. **快照捕获容错（`decision_tracker.dart`）**
   - `captureDecisionBatchForTesting` 增加逐只 try/catch：单只失败跳过并计入 `failedCodes`，不中断其余；返回 `CaptureBatchResult { success, failed, failedCodes }`。
   - `explore_engine.dart`、`opportunity_engine.dart` 接收结果并打印「成功 N 条，失败 M 条」便于排查。

> 效果：发现页扫描后，盘中快照不再被阶段过滤滤掉，且即便个别标的捕获失败也不会整批丢失，留档「全市场扫描」即可见数据。

### B. 降低「决策命中」模式复杂度

重构 `_buildDecisionMode`（`archive_screen.dart`）：

- **始终可见（首屏核心）**：模式切换、数据源分段、汇总卡（`DecisionArchiveSummary`）、列表、底部操作按钮（导出/清空/回溯补录）。
- **默认折叠的进阶区**：把「4 个下拉 + 回溯补录 chip + 分组控件 + 分段分析（柱状图/校准）+ 诊断面板 + 胜率趋势 + 自动清理」收进一个 `ExpansionTile`（标题「高级筛选与分析」，默认 `initiallyExpanded: false`）。
- 拆分 `_buildDecisionFilters` 为：
  - `_buildSourceSegmented()` —— 数据源分段（常驻首屏）。
  - `_buildDecisionSecondaryFilters()` —— 4 下拉 + 回溯 chip（进入折叠区）。

> 效果：首屏只剩模式切换、数据源、汇总、列表；需要深入分析时才展开，显著降低认知负荷，且不丢失任何功能。

### C. 版本与更新日志

- `pubspec.yaml` / `app_version.dart` → `3.32.20260716`
- `update_log_screen.dart` → 新增 v3.32 条目，说明上述修复。

## 三、影响范围与验证

- 改动文件：`archive_screen.dart`、`decision_tracker.dart`、`explore_engine.dart`、`opportunity_engine.dart`、`pubspec.yaml`、`app_version.dart`、`update_log_screen.dart`。
- 不改动数据表结构（无需 DB migration）。
- 单元测试：`decision_tracking_integration_test.dart` 中 `captureDecisionBatchForTesting` 调用改为 await 新返回对象，单只有效分析仍应写入快照 → 测试应通过（返回类型由 `Future<void>` 变为 `Future<CaptureBatchResult>`，await 调用方无需改）。
- 验证：`cd mobile && flutter test` 全量通过；手动在发现页触发市场扫描，切到留档「全市场扫描」确认有数据；确认首屏折叠区默认收起。
