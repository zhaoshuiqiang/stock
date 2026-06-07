# 修复 K 线成交量和成交额单位显示

## 问题分析

当前成交量和成交额存在以下问题：

1. **数据源单位不一致**：
   - 服务端通过 akshare 获取的 K 线数据：成交量单位为 **股**（shares）
   - 移动端腾讯 API：成交量单位为 **手**（lots，1手=100股）
   - 移动端新浪 K 线 API：成交量单位为 **手**
   - 前端通过服务端接口获取：间接获得 akshare 的**股**单位数据

2. **显示逻辑混乱**：
   - `quote_screen.dart`（移动端行情页）：`_formatVolume` 将值乘以 100（手→股）后再格式化，但实际传入的已是腾讯 API 的"手"数据，导致放大 100 倍
   - `chart_screen.dart`（移动端 K 线页）：`_formatVolume` 不转换单位，直接以原始值格式化，与行情页显示不一致
   - `KLineChart.jsx`（桌面端）：`formatVolume` 不转换单位，直接以原始值格式化；且 tooltip 中"额"也用 `formatVolume` 格式化成交额，语义不清晰

3. **用户需求**：成交量统一以 **万手** 为显示单位

## 修复方案

### 1. 服务端统一数据单位
在 `server/services/data_fetcher.py` 的 `get_stock_history` 中，将 akshare 返回的成交量（单位：股）转换为 **手**：
```python
df["volume"] = df["volume"] / 100  # 股 → 手
```
成交额（amount）保持 **元** 不变。

### 2. 移动端 `quote_screen.dart` 修复 `_formatVolume`
```dart
String _formatVolume(double volumeInShou) {
  // 现在统一为"手"（1手=100股），转换为万手
  final volumeInWanShou = volumeInShou / 10000;
  if (volumeInWanShou.abs() >= 10000) {
    return '${(volumeInWanShou / 10000).toStringAsFixed(2)}亿手';
  } else if (volumeInWanShou.abs() >= 1) {
    return '${volumeInWanShou.toStringAsFixed(2)}万手';
  }
  return '${(volumeInShou * 100).toStringAsFixed(0)}股';
}
```

### 3. 移动端 `quote_screen.dart` 修复 `_formatAmount`
成交额保持为元，显示为 亿/万：
```dart
String _formatAmount(double amount) {
  if (amount.abs() >= 1e8) {
    return '${(amount / 1e8).toStringAsFixed(2)}亿';
  } else if (amount.abs() >= 1e4) {
    return '${(amount / 1e4).toStringAsFixed(0)}万';
  }
  return amount.toStringAsFixed(0);
}
```
并在调用处显示单位为"元"。

### 4. 移动端 `chart_screen.dart` 修复 `_formatVolume`
与 `quote_screen.dart` 保持一致，转换为万手：
```dart
String _formatVolume(double vol) {
  final volInWanShou = vol / 10000;
  if (volInWanShou.abs() >= 10000) {
    return '${(volInWanShou / 10000).toStringAsFixed(1)}亿手';
  } else if (volInWanShou.abs() >= 1) {
    return '${volInWanShou.toStringAsFixed(1)}万手';
  }
  return '${(vol * 100).toStringAsFixed(0)}股';
}
```

### 5. 桌面端 `KLineChart.jsx` 修复 `formatVolume`
转换为万手：
```javascript
function formatVolume(num) {
  if (num === null || num === undefined) return '-';
  const value = Number(num) / 10000; // 手 → 万手
  if (value >= 1e8) return (value / 1e8).toFixed(2) + '亿手';
  if (value >= 1e4) return (value / 1e4).toFixed(2) + '万手';
  return value.toFixed(2) + '万手';
}
```

同时修复 tooltip 中"额"的显示，区分成交额格式化：
```javascript
// 成交额保持元为单位，用 amountFormatting
function formatAmount(num) {
  if (num === null || num === undefined) return '-';
  const value = Number(num);
  if (value >= 1e8) return (value / 1e8).toFixed(2) + '亿';
  if (value >= 1e4) return (value / 1e4).toFixed(2) + '万';
  return value.toFixed(0);
}
```
tooltip 中 `额: ${formatVolume(d.amount)}` 改为 `额: ${formatAmount(d.amount)}`。

### 6. 移动端 K 线 Y 轴标签
`chart_screen.dart` 中 `getTitlesWidget` 调用 `_formatVolume(value)`，修改后 Y 轴刻度会正确显示 万手。

## 修改文件清单

| 文件 | 修改内容 |
|------|----------|
| `server/services/data_fetcher.py` | `get_stock_history` 中 `volume` 列除以 100（股→手） |
| `mobile/lib/screens/quote_screen.dart` | 修复 `_formatVolume` 和 `_formatAmount` 函数 |
| `mobile/lib/screens/chart_screen.dart` | 修复 `_formatVolume` 函数 |
| `desktop/src/components/KLineChart.jsx` | 修复 `formatVolume` 函数，新增 `formatAmount` 函数 |

## 注意事项

- 服务端修改后，桌面端和移动端通过接口获取的历史 K 线数据单位会从"股"变为"手"，前端显示逻辑相应调整为万手
- 移动端直接调用腾讯/新浪 API 的行情页（非服务器），其返回数据单位已是"手"，不再重复转换
- 成交额（amount/成交额）保持 **元** 为单位，显示为"亿"或"万"，不改变数值和单位
 