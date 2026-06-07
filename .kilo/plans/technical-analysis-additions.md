# 技术分析功能开发计划

## 目标调整：APK独立运行 (移除服务端/桌面依赖)

## 当前状态
- [x] Server-side Python implementations (indicators.py, patterns.py)
- [x] TechnicalAnalysisData model in stock_models.dart
- [x] API client methods (call server endpoints)
- [x] Chart screen with Fibonacci toggle (but calls API)
- [x] TrendSignalScreen and DragonRetreatScreen (stub UI waiting for data)

## 待办事项

### Phase 1: 添加本地计算函数到 indicators.dart

添加4个函数到 `mobile/lib/analysis/indicators.dart`:

```dart
Map<String, dynamic> calcSupportResistance(List<HistoryKline> data, {int window = 20})
Map<String, dynamic> calcFibonacci(List<HistoryKline> data, {int window = 20})
Map<String, dynamic> detectDragonRetreat(List<HistoryKline> data)
Map<String, dynamic> detectTrendSignals(List<HistoryKline> data)
```

### Phase 2: 更新 chart_screen.dart

修改 `_loadData()` 方法：
- 计算完成后调用 `calcAllIndicators()` 补全 MA/VOL/RSI/KDJ/MACD
- 调用 `calcSupportResistance()` 获取支撑压力位
- 调用 `calcFibonacci()` 获取斐波那契位
- 不再调用 `_api.getTechnicalAnalysis()`

### Phase 3: 更新 trend_signal_screen.dart

接收 `List<HistoryKline>` 数据和 `name` 参数：
- 接收数据后立即调用 `detectTrendSignals()` 本地计算
- 显示企稳/见顶/见底信号列表

### Phase 4: 更新 dragon_retreat_screen.dart

接收 `List<HistoryKline>` 和 `name` 参数：
- 接收数据后立即调用 `detectDragonRetreat()` 本地计算
- 显示形态状态、回调幅度等信息

### Phase 5: 移除服务端依赖

可选：保留 API 方法作为备用，或标记为废弃

## 修改文件列表

| 文件 | 操作 | 说明 |
|------|------|------|
| `mobile/lib/analysis/indicators.dart` | 修改 | 新增4个技术分析计算函数 |
| `mobile/lib/screens/chart_screen.dart` | 修改 | 改为本地计算，绘制支撑压力线 |
| `mobile/lib/screens/trend_signal_screen.dart` | 修改 | 接收数据参数，本地计算趋势信号 |
| `mobile/lib/screens/dragon_retreat_screen.dart` | 修改 | 接收数据参数，本地计算龙回头 |

## 实现细节

### calcSupportResistance 算法
- 遍历 window 内数据，寻找局部极值点（high/low）
- 局部高点：前后2天都低于当前 high
- 局部低点：前后2天都高于当前 low
- 返回最近3个阻力位和支撑位，及最近价位
- 颜色：阻力位红色虚线(#ef5350)，支撑位绿色虚线(#26a69a)

### calcFibonacci 算法
- 在 window 内找 swing_low, swing_high
- 计算 23.6%, 38.2%, 50%, 61.8%, 78.6% 回撤位
- 61.8% 用金色粗线标记（#FFD700）

### detectDragonRetreat 算法
- 近20日涨幅 >= 15%
- 回调幅度 10%-40%，持续3-10天
- 最近阳线收盘 > 回调前收盘 × 0.95
- 成交量放大 >= 50%
- 当前价格 > 回调最低价 × 1.03
- 返回 level: "强势"/"一般"/"弱势"

### detectTrendSignals 算法
- 企稳：止跌阳线、缩量反弹、回踩MA5/MA10、RSI超卖回升
- 见顶：高位长上影线、高位放量滞涨、MACD顶背离
- 见底：低位长下影线、放量止跌、KDJ超卖金叉、价跌量缩

## 已知问题

### 已修复
- `detectTrendSignals` 中的 MACD顶背离检测逻辑已修正：从历史20日(-3到-20)内寻找 MACD柱最大值进行比较
- `_KlinePainter.shouldRepaint` 已更新以检查 `supportLevels`, `resistanceLevels`, `fibonacciLevels` 字段变化，以确保斐波那契开关能触发重绘