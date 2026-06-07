# 技术指标分析增强 v2.3.0 - 设计文档

## 📐 系统架构设计

### 1. 整体架构图

```
┌─────────────────────────────────────────────────────┐
│                  QuoteScreen (个股详情页)              │
├─────────────────────────────────────────────────────┤
│  TabController (length: 5)                           │
│  ┌────────┬────────┬────────┬────────┬────────┐    │
│  │ 实时   │ K线    │ 信号   │ 分析   │ 指标   │    │
│  └────────┴────────┴────────┴────────┴────────┘    │
├─────────────────────────────────────────────────────┤
│  TabBarView                                          │
│  ├─ _buildRealtimeChart()                            │
│  ├─ _buildKlineChart()                               │
│  │   └─ CustomPaint(_KlinePainter) ← 价格标签绘制     │
│  ├─ _buildSignalList()                              │
│  ├─ _buildAnalysis()                                │
│  └─ TechnicalIndicatorsPanel(klines) ← 新增组件      │
└─────────────────────────────────────────────────────┘
```

### 2. 数据流设计

```
数据源: HistoryKline[] (_klines)
  ↓
┌──────────────────────────────────────┐
│   本地计算层 (indicators.dart)        │
├──────────────────────────────────────┤
│ • calcSupportResistance(data)        │
│   → {support[], resistance[], ...}   │
│ • calcFibonacci(data)                │
│   → {levels{}, swing_high, ...}      │
└──────────────────────────────────────┘
  ↓
┌──────────────────────────────────────┐
│   展示层                              │
├──────────────────────────────────────┤
│ • _KlinePainter.paint()              │
│   → 绘制虚线 + 价格标签               │
│ • TechnicalIndicatorsPanel           │
│   → 渲染指标卡片                      │
└──────────────────────────────────────┘
```

## 🎨 UI组件设计

### 1. K线图绘制层 (_KlinePainter)

#### 类结构
```dart
class _KlinePainter extends CustomPainter {
  // 输入参数
  final List<HistoryKline> data;
  final int? selectedIndex;
  final List<double> supportLevels;
  final List<double> resistanceLevels;
  final Map<String, double>? fibonacciLevels;
  final double minPrice;
  final double maxPrice;
  
  // 绘制方法
  void paint(Canvas canvas, Size size);
  void _drawDashedLine(...);
  void _drawPriceLabel(...);        // ← 新增
  void _drawFibonacciLabel(...);    // ← 新增
  
  // 更新检测
  bool shouldRepaint(_KlinePainter oldDelegate);
}
```

#### 绘制流程
```
paint() 执行顺序:
1. 计算priceRange和坐标映射
2. 绘制支撑位虚线 → 调用_drawPriceLabel()
3. 绘制压力位虚线 → 调用_drawPriceLabel()
4. 绘制斐波那契虚线 → 调用_drawFibonacciLabel()
5. 处理停牌情况(priceRange=0)
6. 绘制K线主体
7. 绘制选中高亮
```

#### 价格标签绘制算法
```dart
_drawPriceLabel(canvas, size, price, y, color):
  1. 创建TextPainter对象
     - text: price.toStringAsFixed(2)
     - style: fontSize=10, fontWeight=bold, color=color
  2. layout()计算文本尺寸
  3. 计算位置: x = size.width - textWidth - 8
  4. 绘制背景Rect (黑色半透明)
  5. paint()绘制文本到canvas
```

#### 斐波那契标签绘制算法
```dart
_drawFibonacciLabel(canvas, size, price, ratio, y, color):
  1. 创建TextPainter对象
     - text: '$ratio ${price.toStringAsFixed(2)}'
     - style: fontSize=9, fontWeight=w600, color=color
  2. layout()计算文本尺寸
  3. 计算位置: x = 60.0 (padding右侧)
  4. 绘制背景Rect (黑色半透明)
  5. paint()绘制文本到canvas
```

### 2. 技术指标面板 (TechnicalIndicatorsPanel)

#### 组件层次结构
```
TechnicalIndicatorsPanel (StatelessWidget)
│
├─ SingleChildScrollView
│  └─ Column
│     ├─ Section 1: 支撑压力位
│     │  ├─ _buildSectionTitle('支撑压力位')
│     │  └─ _buildSupportResistanceCard(sr)
│     │     ├─ Card (color: grey[900])
│     │     │  ├─ 当前价格行
│     │     │  ├─ Divider
│     │     │  ├─ 最近支撑位 + 距离%
│     │     │  ├─ 最近压力位 + 距离%
│     │     │  ├─ 所有支撑位Chip列表
│     │     │  └─ 所有压力位Chip列表
│     │
│     ├─ Section 2: 斐波那契回撤
│     │  ├─ _buildSectionTitle('斐波那契回撤')
│     │  └─ _buildFibonacciCard(fib)
│     │     ├─ Card (color: grey[900])
│     │     │  ├─ 区间高点/低点
│     │     │  ├─ 当前位置描述
│     │     │  ├─ Divider
│     │     │  └─ 回撤位列表
│     │     │     └─ [⭐] 61.8% → 价格 (金色)
│     │     │     └─ 其他回撤位 → 价格
│     │
│     └─ Section 3: 技术分析建议
│        ├─ _buildSectionTitle('技术分析建议')
│        └─ _buildTradingAdvice(sr, fib)
│           └─ Card (color: blue[900].opacity(0.3))
│              └─ 动态建议列表
```

#### 核心算法

**距离计算**:
```dart
double distancePct(double current, double level, bool isSupport) {
  if (isSupport) {
    return (current - level) / current * 100;
  } else {
    return (level - current) / current * 100;
  }
}
```

**交易建议生成**:
```dart
List<String> generateAdvices(sr, fib):
  advices = []
  
  // 支撑压力位建议
  if nearestSupport exists:
    dist = distancePct(current, nearestSupport, true)
    if dist < 2%:
      advices.add("接近支撑位，可考虑逢低买入")
  
  if nearestResistance exists:
    dist = distancePct(current, nearestResistance, false)
    if dist < 2%:
      advices.add("接近压力位，可考虑逢高减仓")
  
  // 斐波那契建议
  if currentPosition contains '61.8':
    advices.add("处于黄金分割位附近，是关键支撑/阻力区域")
  else if currentPosition contains '38.2' or '50.0':
    advices.add("处于重要回撤位，关注价格方向选择")
  
  if advices.isEmpty:
    advices.add("当前无明显明显交易信号，建议观望")
  
  return advices
```

## 🔧 技术实现细节

### 1. 坐标映射系统

#### 价格→Y轴映射
```dart
double priceToY(double price, double minPrice, double maxPrice, double chartHeight) {
  final priceRange = maxPrice - minPrice;
  if (priceRange == 0) return chartHeight / 2;
  return chartHeight - ((price - minPrice) / priceRange) * chartHeight;
}
```

#### 索引→X轴映射
```dart
double indexToX(int index, double padding, double chartWidth, int dataLength) {
  final barWidth = chartWidth / dataLength * 0.6;
  final gap = chartWidth / dataLength * 0.4;
  return padding + index * (barWidth + gap) + barWidth / 2;
}
```

### 2. 性能优化策略

#### shouldRepaint优化
```dart
bool shouldRepaint(_KlinePainter oldDelegate) => 
  oldDelegate.data != data || 
  oldDelegate.selectedIndex != selectedIndex ||
  oldDelegate.supportLevels != supportLevels || 
  oldDelegate.resistanceLevels != resistanceLevels || 
  oldDelegate.fibonacciLevels != fibonacciLevels;
```

**优化点**:
- ✅ 精确比对所有相关字段
- ✅ 避免不必要的重绘
- ✅ 提升滚动流畅度

#### TextPainter复用
```dart
// 每次绘制创建新的TextPainter（Flutter最佳实践）
// 避免状态污染，确保线程安全
final textPainter = TextPainter(...)
textPainter.layout();
textPainter.paint(canvas, offset);
```

### 3. 响应式设计

#### 自适应布局
```dart
SingleChildScrollView // 外层滚动
  └─ Column
     └─ Cards (固定内边距16px)
        └─ Wrap (Chip自动换行)
```

#### 屏幕适配
- **小屏幕** (<360px): 字体缩小10%，间距缩小20%
- **中屏幕** (360-480px): 标准布局
- **大屏幕** (>480px): 字体放大10%，最大宽度限制

## 📊 数据结构设计

### 1. 支撑压力位数据结构
```dart
Map<String, dynamic> calcSupportResistance(List<HistoryKline> data) {
  return {
    'support': [10.5, 10.2, 9.8],          // 支撑位列表
    'resistance': [11.2, 11.5, 11.8],      // 压力位列表
    'current_price': 10.85,                 // 当前价格
    'nearest_support': 10.5,                // 最近支撑
    'nearest_resistance': 11.2,             // 最近压力
  };
}
```

### 2. 斐波那契数据结构
```dart
Map<String, dynamic> calcFibonacci(List<HistoryKline> data) {
  return {
    'swing_high': 12.5,                     // 区间高点
    'swing_low': 9.5,                       // 区间低点
    'levels': {                             // 回撤位映射
      '23.6%': 11.79,
      '38.2%': 11.35,
      '50.0%': 11.0,
      '61.8%': 10.65,
      '78.6%': 10.14,
    },
    'current_position': '61.8阻力位上方',    // 位置描述
  };
}
```

### 3. 技术指标面板Props
```dart
class TechnicalIndicatorsPanel extends StatelessWidget {
  final List<HistoryKline> klines;  // 输入：K线数据
  
  // 内部计算
  final Map<String, dynamic> supportResistance;
  final Map<String, dynamic> fibonacci;
  
  // 输出：UI组件树
  Widget build(BuildContext context);
}
```

## 🎯 交互设计

### 1. 用户操作流程

```
用户打开个股详情页
  ↓
点击"指标"标签
  ↓
加载TechnicalIndicatorsPanel
  ↓
显示三个卡片:
  ├─ 支撑压力位卡片 (立即显示)
  ├─ 斐波那契卡片 (立即显示)
  └─ 建议卡片 (立即显示)
  ↓
用户可上下滚动查看
  ↓
返回K线图可查看价格标签
```

### 2. 视觉反馈

| 场景 | 反馈方式 |
|------|---------|
| 距离<2% | 橙色警示色 |
| 61.8%位 | ⭐图标 + 金色 |
| 空数据 | 灰色提示文案 |
| 加载中 | 无（本地计算即时显示）|

### 3. 错误处理

```dart
if (klines.length < 20) {
  return Center(
    child: Text('数据不足，需要至少20根K线'),
  );
}

if (sr.isEmpty) {
  return _buildEmptyCard('暂无支撑压力位数据');
}
```

## 🔒 安全性设计

### 1. 数据安全
- ✅ 所有计算本地化，不上传服务器
- ✅ 不涉及用户隐私数据
- ✅ 无网络请求依赖

### 2. 内存安全
- ✅ TextPainter及时释放
- ✅ 避免闭包引用泄漏
- ✅ shouldRepaint防止无限循环

### 3. 异常处理
```dart
try {
  final sr = calcSupportResistance(klines);
} catch (e) {
  // 降级处理：显示空卡片
  return _buildEmptyCard('计算失败');
}
```

## 📈 性能指标

### 1. 渲染性能
| 指标 | 目标值 | 测量方法 |
|------|--------|---------|
| K线图帧率 | ≥50fps | Flutter DevTools |
| 面板滚动FPS | ≥60fps | Performance Overlay |
| 首屏渲染时间 | <200ms | Timeline |

### 2. 计算性能
| 指标 | 目标值 | 测量方法 |
|------|--------|---------|
| 支撑压力位计算 | <5ms | Stopwatch |
| 斐波那契计算 | <3ms | Stopwatch |
| 总计算耗时 | <10ms | 累加 |

### 3. 内存占用
| 指标 | 目标值 | 测量方法 |
|------|--------|---------|
| 单页面内存 | <50MB | Android Profiler |
| TextPainter峰值 | <1MB | 估算 |
| 总体增量 | <5MB | 对比测试 |

## 🧪 测试策略

### 1. 单元测试
```dart
test('calcSupportResistance returns correct levels', () {
  final data = generateMockKlines(30);
  final result = calcSupportResistance(data);
  expect(result['support'].length, greaterThan(0));
  expect(result['resistance'].length, greaterThan(0));
});

test('calcFibonacci calculates correct ratios', () {
  final data = generateMockKlines(30);
  final result = calcFibonacci(data);
  expect(result['levels'].containsKey('61.8%'), true);
});
```

### 2. Widget测试
```dart
testWidgets('TechnicalIndicatorsPanel renders correctly', () {
  final klines = generateMockKlines(30);
  await tester.pumpWidget(
    MaterialApp(
      home: TechnicalIndicatorsPanel(klines: klines),
    ),
  );
  expect(find.text('支撑压力位'), findsOneWidget);
  expect(find.text('斐波那契回撤'), findsOneWidget);
});
```

### 3. 集成测试
```dart
test('Full user flow: open quote → switch to indicators', () async {
  await app.main();
  await tester.tap(find.text('某股票'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('指标'));
  await tester.pumpAndSettle();
  expect(find.byType(TechnicalIndicatorsPanel), findsOneWidget);
});
```

## 🚀 部署方案

### 1. 版本管理
```
v2.2.0 (当前版本)
  ↓
v2.3.0 (本次更新)
  ├─ 新增: 价格标签显示
  ├─ 新增: 技术指标面板
  └─ 优化: TabBar扩展
  
v2.4.0 (规划中)
  └─ 待定
```

### 2. 灰度发布
- **阶段1**: 内部测试 (10用户)
- **阶段2**: 小范围公测 (100用户)
- **阶段3**: 全量发布 (所有用户)

### 3. 回滚方案
```bash
# 回滚到v2.2.0
git checkout v2.2.0
flutter build apk --release
```

## 📝 维护指南

### 1. 代码规范
- ✅ 遵循Effective Dart规范
- ✅ 所有公共API添加文档注释
- ✅ 使用const构造函数提升性能

### 2. 扩展性设计
```dart
// 未来可扩展的指标类型
enum IndicatorType {
  supportResistance,
  fibonacci,
  movingAverage,  // TODO
  bollingerBands, // TODO
  rsi,            // TODO
}
```

### 3. 常见问题排查

**问题1**: 价格标签不显示
- 检查: supportLevels/resistanceLevels是否为空
- 检查: minPrice/maxPrice是否正确
- 检查: Canvas绘制顺序

**问题2**: 面板数据不准确
- 检查: klines数据是否最新
- 检查: calcSupportResistance/calcFibonacci返回值
- 检查: 数据格式转换是否正确

**问题3**: 滚动卡顿
- 检查: shouldRepaint逻辑
- 检查: 是否有不必要的setState
- 检查: DevTools性能分析

---

**文档版本**: v1.0  
**最后更新**: 2026-06-07  
**设计者**: AI Assistant  
**审核人**: 待定
