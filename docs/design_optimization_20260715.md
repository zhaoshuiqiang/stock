# 设计优化方案

> 基于代码评审分析报告 | 优先级: P0 > P1 > P2 | 目标: 提升涨跌预测准确性 + 修复架构缺陷

---

## 一、P0级修复方案（立即执行）

### 1.1 ConfidenceCalculator权重统一

**问题**: `calculate()` 使用29/11/11/11/11/11/8/8权重，`breakdown()` 使用32/12/12/12/12/12/8权重

**修复方案**:
```
文件: mobile/lib/analysis/confidence_calculator.dart
修改: breakdown() 方法
方案: 将 breakdown 的权重与 calculate 统一为 29/11/11/11/11/11/8/8
     补充 prediction_support 维度的 UI 展示
```

**验证方法**: 对比同一组输入下 calculate() 和 breakdown() 各维度的加权结果一致

**实施路径**:
1. 修改 `breakdown()` 权重为 29/11/11/11/11/11/8/8
2. 在 breakdown 返回的 Map 中增加 `'prediction_support'` 键
3. 更新依赖 breakdown 结果的 UI 组件（score_radar_chart 等）
4. 运行现有 confidence_calculator_test.dart 确保不回归

---

### 1.2 交易日计算增加节假日支持

**问题**: `tradingDaysBetween()` 仅跳过周末，不识别法定节假日

**修复方案**:
```
文件: mobile/lib/analysis/recommendation_tracker.dart
新增: mobile/lib/core/trading_calendar.dart (静态节假日表)
方案: 维护当年 + 前年法定节假日集合(Set<String>)
     tradingDaysBetween 在遍历时额外检查是否在节假日集合中
```

**实施路径**:
1. 新建 `trading_calendar.dart`，内含 2025-2026 年节假日 Set
2. 修改 `tradingDaysBetween` 使用 calendar 过滤
3. 同步修改 `TradingSession.isInTradingSession()` 复用 calendar
4. 编写测试覆盖春节/国庆/清明等长假场景

**验证方法**: 测试 2026-01-28(除夕) 到 2026-02-05(初八) 间应为0个交易日

---

### 1.3 Archive去重增加时间维度

**问题**: `addArchiveIfNotExists()` 仅按code去重

**修复方案**:
```
文件: mobile/lib/storage/database_service.dart
方案: 去重逻辑改为: 同一code在30天内不重复留档
     但方向变化时(bullish→bearish)允许重新留档
```

**实施路径**:
1. 修改 `addArchiveIfNotExists` 查询条件: `code=? AND archived_at > ?`（30天前）
2. 增加方向检测：新方向与最近留档方向不同时，允许插入
3. 数据库层增加 `direction` 列到 archive_records（v23迁移）
4. 现有测试扩展覆盖重复+方向变化场景

---

## 二、P1级优化方案（本周完成）

### 2.1 评分口径统一标注

**目标**: 让用户清楚每个评分的计算时间和来源

**方案**:
1. `ExploreResult` 增加 `scoredAt: DateTime` 和 `scoreSource: String` 字段
2. 板块精选的 `originalScore` 和 `score` 在UI中同时展示（已部分实现）
3. 详情页分析完成后，若与列表评分差异≥2分，弹出Toast提示

**实施路径**:
- 修改 `ExploreResult.toMap/fromMap` 增加字段
- 数据库v23迁移增加 `score_source` TEXT 列
- UI层增加差异提示逻辑

---

### 2.2 移除B Chain冗余recommendation

**目标**: 消除双轨推荐标签的维护负担和混淆风险

**方案**:
```
文件: mobile/lib/analysis/comprehensive_scorer.dart
修改: ComprehensiveScoreResult.recommendation 标记为 @Deprecated
     下游所有消费者仅使用 RecommendationPolicy 输出
```

**实施路径**:
1. `ComprehensiveScoreResult.recommendation` 改为始终返回空字符串
2. Grep全项目确认无下游消费此字段（预期仅测试代码引用）
3. 保留字段但标注 deprecated，避免破坏性变更

---

### 2.3 分时扫描候选池实时化

**问题**: 候选池仅来自上次explore扫描结果，可能已过时

**方案**:
```
文件: mobile/lib/analysis/intraday_scan_engine.dart
修改: scan() 方法增加实时候选池补充逻辑
方案:
  1. 优先从 explore_results 取前20只
  2. 额外从涨停池(limit_up_pool)取当日炸板股+首板股前5只
  3. 额外从自选列表取前5只
  4. 合并去重后作为最终候选池(≤30只)
```

**实施路径**:
1. `scan()` 增加 `_buildCandidatePool()` 方法
2. 从三个数据源合并候选
3. 去重后截断到30只
4. 确保分时扫描结果更贴近当日活跃标的

---

### 2.4 全市场Tab自动刷新

**问题**: 切到全市场Tab不触发数据检查/刷新

**方案**:
```
文件: mobile/lib/screens/discover_screen.dart
修改: TabController listener 增加 index==3 时的懒加载检查
逻辑: 若 _exploreResults 为空 或 最近一次扫描>4小时 → 自动触发
```

**实施路径**:
1. 在 `_tabController.addListener` 中增加 `if (index == 3)` 分支
2. 检查 `_exploreResults.isNotEmpty && _exploreResults.first.analyzedAt` 距今时长
3. 超过4小时且在交易时段 → 自动触发 `_exploreEngine.explore()`

---

## 三、预测准确性提升方案

### 3.1 买入信号数量与胜率的逆相关利用

**现有发现**: 代码注释 "买入信号>=5胜率33.3%，>=3胜率38.4%"

**优化方案**:
```
文件: mobile/lib/analysis/technical_scorer.dart (已实现惩罚)
增强: 将此统计反馈到 ConfidenceCalculator
```

具体措施:
1. `ConfidenceCalculator.calculate()` 增加 `buySignalCount` 参数
2. 信号一致性维度内，当buySignals≥5时额外降低0.1
3. 在 `_generateReasons` 中增加"信号过多警告"文案

---

### 3.2 情绪温度计联动评分惩罚

**目标**: 退潮期/冰点期自动降低全市场买入评分

**方案**:
```
文件: mobile/lib/analysis/comprehensive_scorer.dart
修改: combine() 增加市场情绪阶段参数
逻辑:
  - 退潮期(retreat): 所有买入推荐评分 ×0.90
  - 冰点期(freezing): 所有买入推荐评分 ×0.85
  - 启动期/高潮期: 不折扣
```

**实施路径**:
1. `combine()` 增加 `EmotionPhase? currentPhase` 参数
2. 在 `temperedScore` 计算后应用阶段折扣
3. `ExploreEngine` 在分析前获取最新情绪阶段传入
4. 测试覆盖4个阶段的评分输出

---

### 3.3 追高保护强化（连涨天数 + 市场结构联动）

**现有问题**: 牛市结构中追高保护被动量保护因子削弱（×0.5），导致牛市追高风险被低估

**方案**:
```
文件: mobile/lib/analysis/comprehensive_scorer.dart
修改: 动量保护因子增加条件约束
逻辑:
  - 涨幅>8% 时：即使ADX>30+多头排列，惩罚不低于0.85（当前可低至0.80×0.5=0.90不够）
  - 连涨≥5天时：动量保护因子上限0.7（当前0.5导致几乎无惩罚）
```

---

### 3.4 方向预测准确率闭环

**目标**: 利用 `recommendation_tracking` 的历史收益数据反馈到未来预测

**方案**:
```
新增: mobile/lib/analysis/prediction_feedback_loop.dart
逻辑:
  1. 统计最近50条已关闭推荐的方向命中率
  2. 按 marketStructure 分组统计（牛市结构下命中率 vs 熊市结构下命中率）
  3. 将结构化命中率作为 predictionAccuracy 反馈给 ConfidenceCalculator
```

**实施路径**:
1. 新建 `PredictionFeedbackLoop` 静态类
2. `getStructuredAccuracy(marketStructure)` 方法返回该结构下的历史命中率
3. `signal_engine.dart` 中调用此方法替代固定的 `predictionAccuracy=0.5`
4. 冷启动阶段(<20条数据)返回0.5作为默认值

---

### 3.5 板块轮动主线强度优化

**现有问题**: 主线判定依赖单日板块涨幅，缺乏时间维度确认

**方案**:
```
文件: mobile/lib/analysis/sector_rotation.dart
修改: analyze() 增加连续强势天数的实际计算
现状: historyData 参数很少被传入（大部分调用不带此参数）
```

具体措施:
1. `SectorPickEngine.pick()` 调用时传入板块3日涨幅历史
2. 连续强势天数≥3时 strengthScore 额外+1.5
3. 避免"一日游"板块被错误标记为主线

---

## 四、实施优先级排序

| 优先级 | 任务 | 预估工时 | 影响范围 |
|--------|------|---------|---------|
| P0-1 | ConfidenceCalculator权重统一 | 2h | UI展示 |
| P0-2 | 交易日计算+节假日 | 4h | 留档追踪 |
| P0-3 | Archive去重+时间维度 | 3h | 留档完整性 |
| P1-1 | 评分口径标注 | 3h | 用户体验 |
| P1-2 | B Chain recommendation标注废弃 | 1h | 代码维护 |
| P1-3 | 分时扫描候选池实时化 | 4h | 推荐时效性 |
| P1-4 | 全市场Tab自动刷新 | 2h | 用户体验 |
| P2-1 | 情绪阶段联动评分 | 4h | 预测准确性 |
| P2-2 | 预测准确率闭环 | 6h | 预测准确性 |
| P2-3 | 主线强度时间维度 | 3h | 板块推荐质量 |

---

## 五、验证方法总览

### 5.1 单元测试验证

| 模块 | 测试文件 | 验证点 |
|------|---------|--------|
| ConfidenceCalculator | confidence_calculator_test.dart | calculate vs breakdown 输出一致 |
| 交易日计算 | recommendation_tracker_test.dart | 节假日期间返回0 |
| Archive去重 | database_service_test.dart | 30天内同code不重复、方向变化允许 |
| 情绪联动 | comprehensive_scorer_test.dart | 退潮期评分×0.90 |

### 5.2 集成验证

1. 运行全量测试: `cd mobile && flutter test`（674+ tests全部通过）
2. 模拟器验证: 打开Discover页各Tab，确认数据刷新行为
3. 留档验证: 手动留档同一股票两次，确认第二次被正确处理

### 5.3 回归风险控制

- 所有修改限定在analysis层和storage层，UI层仅增加展示
- B Chain recommendation字段保留（标废弃），不删除避免编译错误
- 数据库迁移使用 `oldVersion < N` 模式，向前兼容
