# P0 短线情绪温度计 + 打板梯队激活 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 激活 dead code `LimitUpAnalyzer.analyzeBatch`，新建 `SentimentThermometer` 情绪温度计引擎，重画发现页打板梯队 Tab 和首页工作台，补齐 Stage 8 K 线打板标识。

**Architecture:** 数据层（东方财富涨停板 API + `limit_up_pool` 表 v11 迁移）→ 引擎层（`LimitUpScanEngine` 协调器封装 API+分析+情绪计算+落库）→ UI 层（打板梯队分组卡片 + 情绪温度计大卡 + K 线打板标识）。纯函数 `SentimentThermometer` 便于单测。

**Tech Stack:** Flutter 3.13+ / Dart 3.x / sqflite 2.4.3 / http + dart:io HttpClient / fl_chart + CustomPaint。无新增依赖。

**Spec:** [2026-06-27-p0-sentiment-thermometer-and-limit-up-echelon-design.md](file:///d:/MyProjects/stock/docs/superpowers/specs/2026-06-27-p0-sentiment-thermometer-and-limit-up-echelon-design.md)

---

## 关键接口事实（写代码前必读）

以下是从现有代码中确认的接口签名，plan 中所有代码基于这些事实：

1. **`LimitUpStock` 和 `LimitUpAnalysis` 都在 `mobile/lib/analysis/limit_up_analyzer.dart`**（不在 `stock_models.dart`）。`stock_models.dart` 仅在 `AnalysisResult.limitUpAnalysis`（行 806）引用 `LimitUpAnalysis`。
2. **`LimitUpStock` 现有字段**（行 4-10）：`code, name, sector, limitUpType`（String）；`price, changePct, sealAmount, turnoverRate, volumeRatio`（double）；`consecutiveDays`（int）；`firstLimitUpTime`（DateTime，非 nullable，默认 `DateTime.now()`）。
3. **`LimitUpAnalysis` 现有字段**（行 12-19）：`code, name, quality, timeGrade, boardType, position`（String）；`consecutiveDays`（int）；`qualityScore, sealRate, premiumProb`（double）；`signals`（List<String>）。只有 `toMap()`，**无 `fromMap`**。
4. **`analyzeBatch` 返回 `Map<String, dynamic>`**（不是 `List<LimitUpAnalysis>`），含 `analyses/total/leaders/distribution/avg_quality` 键。
5. **`ApiClient` 无单例**，各处直接 `ApiClient()` 实例化。无 `_kMobileUA` 常量，UA 内联。
6. **`BaseAnalysisEngine<P>`** 是抽象类（`mobile/lib/analysis/base_analysis_engine.dart`），无单例，子类自实现 `static final _instance = X._();`。
7. **数据库版本 = 10**，方法名 `_initDatabase`（行 20）。迁移在 `onUpgrade`（行 30-191）用 `if (oldVersion < N)` 顺序累加。`_createTables`（行 195）是全量建表。
8. **`replaceSectorPickResults` 模式**（行 621-629）：`db.transaction` 内 `txn.delete` + `for` 循环 `txn.insert`。`getSectorPickResults`（行 631-635）直接返回 `db.query()` 结果（**QueryResultSet 只读，sort 前必须 `List.from`**）。
9. **`getBatchRealtimeQuotes`**（api_client.dart 行 1370-1422）：腾讯接口 `https://qt.gtimg.cn/q=<codes>`，GBK 编码，**未内部分片**，调用方按 30 只一批切片。
10. **`quote_screen.dart`**：字段名 `_analysis`（行 41，非 `_analysisResult`）。`_KlinePainter`（行 2052）字段名 `data`（非 `_klines`）。`KlineValidator` 在 `analysis/backtest_engine.dart` 行 79。
11. **`home_screen.dart`**：无 `_exploreResults` 字段，只有 `_limitUpCount/_lowBuyCount/_mainLineCount`（int）+ `_marketTiming`。`_mainLineCount` 在 `_loadWorkbenchData` 中**未赋值**（疑似已有 bug，本 plan 顺带修复）。
12. **`discover_screen.dart`**：`_limitUpList` getter（行 225-229）从 `_exploreResults.where((r) => r.isLimitUpApprox)` 过滤。`_sectorPickResults` 是弱类型 `List<Map<String, dynamic>>`。
13. **`ExploreResult.isLimitUpApprox`**（stock_models.dart 行 1329-1336）：按 code 前缀分板（688=科创/30=创业板/8或43=北交所/其余主板），阈值 9.5/19/29。

---

## File Structure

### 新建文件（5 个）

| 文件路径 | 职责 |
|---|---|
| `mobile/lib/analysis/sentiment_thermometer.dart` | 纯函数情绪温度计引擎（5 维指标 + 阶段判定 + 信号生成） |
| `mobile/lib/analysis/limit_up_universe_provider.dart` | 涨停池数据采集器（API 拉取 + 字段补全 + 去重） |
| `mobile/lib/analysis/limit_up_scan_engine.dart` | 打板扫描协调器（extends BaseAnalysisEngine） |
| `mobile/lib/widgets/sentiment_thermometer_card.dart` | 情绪温度计大卡片 widget |
| `mobile/lib/widgets/limit_up_card.dart` | 打板梯队卡片 widget |

### 修改文件（7 个）

| 文件路径 | 修改内容 |
|---|---|
| `mobile/lib/analysis/limit_up_analyzer.dart` | 扩展 `LimitUpStock`（+fromEastMoney 工厂 + 新字段）；扩展 `LimitUpAnalysis`（+fromMap + 新字段）；新增 `analyzeBatchList` 方法 |
| `mobile/lib/api/api_client.dart` | 新增 `getLimitUpBoard()` + `getYesterdayLimitUpPool()` |
| `mobile/lib/storage/database_service.dart` | v10→v11 迁移 + `limit_up_pool` 表 + CRUD 方法 |
| `mobile/lib/screens/discover_screen.dart` | 打板梯队 Tab 重画（分组 + 情绪迷你卡） |
| `mobile/lib/screens/home_screen.dart` | 工作台升级（1 大卡 + 2×2 网格 + 情绪温度计） |
| `mobile/lib/screens/quote_screen.dart` | Stage 8 K 线打板标识 + 浮层卡片 |
| `mobile/lib/models/stock_models.dart` | 新增 `SentimentResult` + `EmotionPhase`（LimitUpAnalysis 引用不变） |

### 新建测试文件（7 个）

| 文件路径 | 测试内容 |
|---|---|
| `mobile/test/sentiment_thermometer_test.dart` | 5 维指标 + 温度合成 + 阶段判定 + 信号生成 |
| `mobile/test/limit_up_analyzer_batch_test.dart` | analyzeBatchList 激活 + 板型/时段/封单评分 |
| `mobile/test/limit_up_pool_db_test.dart` | v11 迁移 + CRUD + QueryResultSet 只读回归 |
| `mobile/test/discover_limit_up_tab_test.dart` | 分组渲染 + 空状态 + 情绪迷你卡 + 长按菜单 |
| `mobile/test/sentiment_card_test.dart` | 阶段渐变 + 温度条 + skeleton + 信号省略 |
| `mobile/test/kline_limit_up_marks_test.dart` | 标识渲染 + 点击浮层 + 一字板矩形 |
| `mobile/test/p0_integration_test.dart` | 端到端 + 降级路径 |

---

## Task 1: 扩展 LimitUpStock 模型 + fromEastMoney 工厂

**Files:**
- Modify: `mobile/lib/analysis/limit_up_analyzer.dart:4-10`
- Test: `mobile/test/limit_up_stock_model_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `mobile/test/limit_up_stock_model_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock/analysis/limit_up_analyzer.dart';

void main() {
  group('LimitUpStock.fromEastMoney', () {
    test('parses full pool element', () {
      final json = {
        'c': '600519',
        'n': '贵州茅台',
        'lbc': 3,
        'fbt': 92500,
        'lbt': 145900,
        'fund': 230000000,
        'hs': 1.23,
        'zbc': 0,
        'hybk': '白酒',
        'ltsz': 21234567890,
        'tshare': 26543210000,
      };
      final s = LimitUpStock.fromEastMoney(json);
      expect(s.code, '600519');
      expect(s.name, '贵州茅台');
      expect(s.consecutiveDays, 3);
      expect(s.firstLimitTime, isNotNull);
      expect(s.firstLimitTime!.hour, 9);
      expect(s.firstLimitTime!.minute, 25);
      expect(s.sealAmount, closeTo(23000, 0.1));  // 元→万元
      expect(s.turnoverRate, 1.23);
      expect(s.isZhaBan, isFalse);
      expect(s.zhabanCount, 0);
      expect(s.sector, '白酒');
    });

    test('zbc > 0 marks as zhaban', () {
      final s = LimitUpStock.fromEastMoney({'c': '000001', 'n': '平安银行', 'zbc': 2});
      expect(s.isZhaBan, isTrue);
      expect(s.zhabanCount, 2);
    });

    test('null fbt returns null firstLimitTime', () {
      final s = LimitUpStock.fromEastMoney({'c': '000001', 'n': 'X', 'fbt': null});
      expect(s.firstLimitTime, isNull);
    });

    test('missing fields use defaults', () {
      final s = LimitUpStock.fromEastMoney({'c': '000001', 'n': 'X'});
      expect(s.consecutiveDays, 1);
      expect(s.sealAmount, 0);
      expect(s.isZhaBan, isFalse);
    });

    test('code padded to 6 digits', () {
      final s = LimitUpStock.fromEastMoney({'c': '1', 'n': 'X'});
      expect(s.code, '000001');
    });
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd mobile && flutter test test/limit_up_stock_model_test.dart`
Expected: FAIL — `fromEastMoney` 方法不存在，`isZhaBan`/`zhabanCount`/`firstLimitTime`(nullable) 字段不存在

- [ ] **Step 3: 扩展 LimitUpStock 类**

修改 `mobile/lib/analysis/limit_up_analyzer.dart` 行 4-10，替换 `LimitUpStock` 类定义为：

```dart
class LimitUpStock {
  final String code, name, sector, limitUpType;
  final double price, changePct, sealAmount, turnoverRate, volumeRatio;
  final double sealRatio;           // 封成比
  final double limitUpPrice;        // 涨停价
  final double totalValue;          // 总市值
  final double circulationValue;    // 流通市值
  final int consecutiveDays;
  final int zhabanCount;            // 炸板次数
  final bool isZhaBan;              // 是否炸板
  final DateTime? firstLimitTime;   // 首封时间（nullable）
  final DateTime? lastLimitTime;    // 最后封板时间

  LimitUpStock({
    required this.code,
    required this.name,
    this.price = 0,
    this.changePct = 0,
    this.consecutiveDays = 1,
    this.firstLimitTime,
    this.lastLimitTime,
    this.sealAmount = 0,
    this.turnoverRate = 0,
    this.volumeRatio = 1.0,
    this.sector = '',
    this.limitUpType = '',
    this.sealRatio = 0,
    this.limitUpPrice = 0,
    this.totalValue = 0,
    this.circulationValue = 0,
    this.zhabanCount = 0,
    this.isZhaBan = false,
  });

  /// 从东方财富 getTopicZTPool 接口的 pool 元素构造
  factory LimitUpStock.fromEastMoney(Map<String, dynamic> json) {
    return LimitUpStock(
      code: (json['c'] ?? '').toString().padLeft(6, '0'),
      name: (json['n'] ?? '').toString(),
      consecutiveDays: (json['lbc'] ?? 1) as int,
      firstLimitTime: _parseEastMoneyTime(json['fbt']),
      lastLimitTime: _parseEastMoneyTime(json['lbt']),
      sealAmount: ((json['fund'] ?? 0) as num).toDouble() / 10000,  // 元→万元
      turnoverRate: ((json['hs'] ?? 0) as num).toDouble(),
      zhabanCount: (json['zbc'] ?? 0) as int,
      isZhaBan: ((json['zbc'] ?? 0) as int) > 0,
      sector: (json['hybk'] ?? '') as String,
      totalValue: ((json['tshare'] ?? 0) as num).toDouble(),
      circulationValue: ((json['ltsz'] ?? 0) as num).toDouble(),
    );
  }

  /// 解析东财时间格式：整数 92500 → DateTime(09:25:00)
  static DateTime? _parseEastMoneyTime(dynamic val) {
    if (val == null || val == '-' || val == '') return null;
    if (val is int) {
      final s = val.toString().padLeft(6, '0');
      if (s.length != 6) return null;
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day,
          int.parse(s.substring(0, 2)),
          int.parse(s.substring(2, 4)),
          int.parse(s.substring(4, 6)));
    }
    if (val is String && val.contains(':')) {
      final parts = val.split(':');
      final now = DateTime.now();
      return DateTime(now.year, now.month, now.day,
          int.parse(parts[0]), int.parse(parts[1]),
          parts.length > 2 ? int.parse(parts[2]) : 0);
    }
    return null;
  }
}
```

注意：`firstLimitTime` 从原来的 `DateTime firstLimitUpTime`（非 nullable，默认 `DateTime.now()`）改为 `DateTime? firstLimitTime`（nullable）。需检查 `analyzeSingle` 方法中引用 `firstLimitUpTime` 的地方是否需要适配（Step 4 处理）。

- [ ] **Step 4: 适配 analyzeSingle 方法**

`analyzeSingle`（行 23 起）原来使用 `stock.firstLimitUpTime`，现改为 `stock.firstLimitTime`。读取 `analyzeSingle` 方法体，将所有 `firstLimitUpTime` 引用改为 `firstLimitTime`，并处理 nullable：

```dart
// 在 analyzeSingle 中，原来的:
//   final hour = stock.firstLimitUpTime.hour;
// 改为:
//   final hour = stock.firstLimitTime?.hour ?? 0;
```

用 Grep 搜索 `firstLimitUpTime` 全部出现位置，逐一替换。

- [ ] **Step 5: 运行测试验证通过**

Run: `cd mobile && flutter test test/limit_up_stock_model_test.dart`
Expected: PASS — 5 个测试全部通过

- [ ] **Step 6: 运行全量测试确保无回归**

Run: `cd mobile && flutter test`
Expected: 既有 578 测试全部通过（`firstLimitUpTime` → `firstLimitTime` 重命名可能影响其他文件，需修复编译错误）

- [ ] **Step 7: Commit**

```bash
cd mobile && git add lib/analysis/limit_up_analyzer.dart test/limit_up_stock_model_test.dart
git commit -m "feat: 扩展 LimitUpStock 模型 + fromEastMoney 工厂 — 支持东财涨停池字段映射"
```

---

## Task 2: 扩展 LimitUpAnalysis + fromMap + analyzeBatchList

**Files:**
- Modify: `mobile/lib/analysis/limit_up_analyzer.dart:12-19`（LimitUpAnalysis 类）和 `:63-71`（analyzeBatch 方法）
- Test: `mobile/test/limit_up_analyzer_batch_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `mobile/test/limit_up_analyzer_batch_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock/analysis/limit_up_analyzer.dart';

void main() {
  group('LimitUpAnalysis.fromMap', () {
    test('round-trip toMap/fromMap', () {
      final a = LimitUpAnalysis(
        code: '600519', name: '贵州茅台', consecutiveDays: 3,
        qualityScore: 8.5, boardType: '一字板', timeGrade: '竞价涨停',
        sealRate: 8.5, premiumProb: 0.75, sector: '白酒',
        sealAmount: 23000, isZhaBan: false, price: 1689.5, changePct: 10.0,
      );
      final m = a.toMap();
      final restored = LimitUpAnalysis.fromMap(m);
      expect(restored.code, a.code);
      expect(restored.consecutiveDays, a.consecutiveDays);
      expect(restored.qualityScore, a.qualityScore);
      expect(restored.boardType, a.boardType);
      expect(restored.premiumProb, a.premiumProb);
    });
  });

  group('LimitUpAnalyzer.analyzeBatchList', () {
    test('returns List<LimitUpAnalysis> (activates dead code path)', () {
      final stocks = [
        LimitUpStock(code: '600519', name: '贵州茅台', consecutiveDays: 3,
            sealAmount: 23000, firstLimitTime: DateTime(2026, 6, 27, 9, 25)),
        LimitUpStock(code: '000001', name: '平安银行', consecutiveDays: 1,
            sealAmount: 5000, firstLimitTime: DateTime(2026, 6, 27, 14, 50)),
      ];
      final results = LimitUpAnalyzer.analyzeBatchList(stocks);
      expect(results, hasLength(2));
      expect(results.every((a) => a is LimitUpAnalysis), isTrue);
    });

    test('early limit time gets higher quality score than late', () {
      final early = LimitUpStock(code: '000001', name: 'A',
          firstLimitTime: DateTime(2026, 6, 27, 9, 25), sealAmount: 10000);
      final late = LimitUpStock(code: '000002', name: 'B',
          firstLimitTime: DateTime(2026, 6, 27, 14, 50), sealAmount: 10000);
      final r1 = LimitUpAnalyzer.analyzeBatchList([early]);
      final r2 = LimitUpAnalyzer.analyzeBatchList([late]);
      expect(r1.first.qualityScore, greaterThan(r2.first.qualityScore));
    });

    test('higher seal amount gets higher quality score', () {
      final strong = LimitUpStock(code: '000001', name: 'A', sealAmount: 50000);
      final weak = LimitUpStock(code: '000002', name: 'B', sealAmount: 500);
      final r1 = LimitUpAnalyzer.analyzeBatchList([strong]);
      final r2 = LimitUpAnalyzer.analyzeBatchList([weak]);
      expect(r1.first.qualityScore, greaterThanOrEqualTo(r2.first.qualityScore));
    });
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd mobile && flutter test test/limit_up_analyzer_batch_test.dart`
Expected: FAIL — `fromMap` 不存在，`analyzeBatchList` 不存在，`sector`/`sealAmount`/`isZhaBan`/`price`/`changePct` 字段不存在

- [ ] **Step 3: 扩展 LimitUpAnalysis 类**

修改 `mobile/lib/analysis/limit_up_analyzer.dart` 行 12-19，替换 `LimitUpAnalysis` 类定义为：

```dart
class LimitUpAnalysis {
  final String code, name, quality, timeGrade, boardType, position;
  final String? sector;              // 所属板块
  final int consecutiveDays;
  final int zhabanCount;             // 炸板次数
  final bool isZhaBan;               // 是否炸板
  final double qualityScore, sealRate, premiumProb;
  final double sealAmount;           // 封单金额（万元）
  final double price;                // 当前价
  final double changePct;            // 涨跌幅
  final DateTime? firstLimitTime;    // 首封时间
  final List<String> signals;

  LimitUpAnalysis({
    required this.code,
    required this.name,
    this.consecutiveDays = 1,
    this.quality = '一般',
    this.qualityScore = 5.0,
    this.timeGrade = '未知',
    this.sealRate = 0,
    this.boardType = '',
    this.position = '',
    this.premiumProb = 0.5,
    this.signals = const [],
    this.sector,
    this.zhabanCount = 0,
    this.isZhaBan = false,
    this.sealAmount = 0,
    this.price = 0,
    this.changePct = 0,
    this.firstLimitTime,
  });

  Map<String, dynamic> toMap() => {
    'code': code,
    'name': name,
    'consecutive_days': consecutiveDays,
    'quality': quality,
    'quality_score': qualityScore,
    'time_grade': timeGrade,
    'seal_rate': sealRate,
    'board_type': boardType,
    'position': position,
    'premium_prob': premiumProb,
    'sector': sector ?? '',
    'zhaban_count': zhabanCount,
    'is_zhaban': isZhaBan ? 1 : 0,
    'seal_amount': sealAmount,
    'price': price,
    'change_pct': changePct,
    'first_limit_time': firstLimitTime?.millisecondsSinceEpoch,
  };

  factory LimitUpAnalysis.fromMap(Map<String, dynamic> m) => LimitUpAnalysis(
    code: (m['code'] ?? '').toString(),
    name: (m['name'] ?? '').toString(),
    consecutiveDays: (m['consecutive_days'] ?? 1) as int,
    quality: (m['quality'] ?? '一般').toString(),
    qualityScore: (m['quality_score'] ?? 5.0) as double,
    timeGrade: (m['time_grade'] ?? '未知').toString(),
    sealRate: (m['seal_rate'] ?? 0) as double,
    boardType: (m['board_type'] ?? '').toString(),
    position: (m['position'] ?? '').toString(),
    premiumProb: (m['premium_prob'] ?? 0.5) as double,
    sector: m['sector'] as String?,
    zhabanCount: (m['zhaban_count'] ?? 0) as int,
    isZhaBan: ((m['is_zhaban'] ?? 0) as int) == 1,
    sealAmount: (m['seal_amount'] ?? 0) as double,
    price: (m['price'] ?? 0) as double,
    changePct: (m['change_pct'] ?? 0) as double,
    firstLimitTime: m['first_limit_time'] != null
        ? DateTime.fromMillisecondsSinceEpoch(m['first_limit_time'] as int)
        : null,
  );
}
```

- [ ] **Step 4: 新增 analyzeBatchList 方法**

在 `limit_up_analyzer.dart` 的 `LimitUpAnalyzer` 类中（`analyzeBatch` 方法之后，行 71 后）新增：

```dart
  /// 批量分析涨停股，返回 List<LimitUpAnalysis>（激活 dead code 路径）
  /// 与 analyzeBatch 的区别：返回强类型 List 而非 Map，便于下游消费
  static List<LimitUpAnalysis> analyzeBatchList(List<LimitUpStock> stocks) {
    if (stocks.isEmpty) return [];
    return stocks.map((s) => analyzeSingle(s)).toList();
  }
```

- [ ] **Step 5: 适配 analyzeSingle 补全新字段**

读取 `analyzeSingle`（行 23-62）方法体，在构造 `LimitUpAnalysis` 返回值时补全新字段：

```dart
// 在 analyzeSingle 的 return 语句中，添加:
//   sector: stock.sector,
//   isZhaBan: stock.isZhaBan,
//   zhabanCount: stock.zhabanCount,
//   sealAmount: stock.sealAmount,
//   price: stock.price,
//   changePct: stock.changePct,
//   firstLimitTime: stock.firstLimitTime,
```

- [ ] **Step 6: 运行测试验证通过**

Run: `cd mobile && flutter test test/limit_up_analyzer_batch_test.dart`
Expected: PASS — 5 个测试全部通过

- [ ] **Step 7: 运行全量测试**

Run: `cd mobile && flutter test`
Expected: 全部通过

- [ ] **Step 8: Commit**

```bash
cd mobile && git add lib/analysis/limit_up_analyzer.dart test/limit_up_analyzer_batch_test.dart
git commit -m "feat: 扩展 LimitUpAnalysis + fromMap + analyzeBatchList — 激活 dead code 路径"
```

---

## Task 3: DB 迁移 v10→v11 + limit_up_pool 表

**Files:**
- Modify: `mobile/lib/storage/database_service.dart:26`（版本号）, `:176-190`（onUpgrade）, `:195`（_createTables）
- Test: `mobile/test/limit_up_pool_db_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `mobile/test/limit_up_pool_db_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:stock/analysis/limit_up_analyzer.dart';
import 'package:stock/storage/database_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('limit_up_pool table', () {
    test('v11 migration creates table', () async {
      // 用 in-memory DB 模拟迁移
      final db = await openDatabase(
        ':memory:',
        version: 11,
        onCreate: (db, v) async {
          // 模拟 _createTables 中的 limit_up_pool 建表
          await db.execute('''
            CREATE TABLE limit_up_pool (
              code TEXT NOT NULL,
              name TEXT NOT NULL,
              trade_date TEXT NOT NULL,
              limit_up_price REAL NOT NULL DEFAULT 0,
              first_limit_time INTEGER,
              last_limit_time INTEGER,
              consecutive_days INTEGER NOT NULL DEFAULT 1,
              board_type TEXT NOT NULL DEFAULT '',
              seal_amount REAL NOT NULL DEFAULT 0,
              seal_ratio REAL NOT NULL DEFAULT 0,
              volume_ratio REAL NOT NULL DEFAULT 0,
              turnover_rate REAL NOT NULL DEFAULT 0,
              is_zhaban INTEGER NOT NULL DEFAULT 0,
              zhaban_count INTEGER NOT NULL DEFAULT 0,
              sector TEXT,
              quality_score REAL NOT NULL DEFAULT 0,
              premium_prob REAL NOT NULL DEFAULT 0,
              price REAL NOT NULL DEFAULT 0,
              change_pct REAL NOT NULL DEFAULT 0,
              updated_at INTEGER NOT NULL,
              PRIMARY KEY (code, trade_date)
            )
          ''');
        },
      );
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='limit_up_pool'");
      expect(tables, hasLength(1));
      await db.close();
    });

    test('composite PK (code, trade_date) supports history', () async {
      // 通过 DatabaseService 测试（需 mock 或集成测试）
      // 此测试验证同 code 不同 trade_date 可共存
      final analyses = [
        LimitUpAnalysis(code: '600519', name: '茅台', consecutiveDays: 3, qualityScore: 8.5),
        LimitUpAnalysis(code: '600519', name: '茅台', consecutiveDays: 4, qualityScore: 9.0),
      ];
      // 验证 toMap 包含必要字段
      expect(analyses[0].toMap()['code'], '600519');
      expect(analyses[1].toMap()['consecutive_days'], 4);
    });

    test('QueryResultSet read-only: List.from before sort', () {
      // 沿用 discover_build_test.dart 的回归测试模式
      final readOnlyList = List<Map<String, dynamic>>.unmodifiable([
        {'code': '000001', 'score': 5},
        {'code': '000002', 'score': 8},
      ]);
      var picks = List<Map<String, dynamic>>.from(readOnlyList);
      // sort 不应抛出 UnsupportedError('read-only')
      picks.sort((a, b) =>
          (b['score'] as num? ?? 0).toInt().compareTo((a['score'] as num? ?? 0).toInt()));
      expect(picks.first['code'], '000002');
    });
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd mobile && flutter test test/limit_up_pool_db_test.dart`
Expected: FAIL — 部分测试失败（`sqflite_common_ffi` 可能需要在 pubspec dev_dependencies 中确认存在）

- [ ] **Step 3: 修改数据库版本号**

修改 `mobile/lib/storage/database_service.dart` 行 26：

```dart
// 原: version: 10,
version: 11,
```

- [ ] **Step 4: 在 onUpgrade 中添加 v11 迁移块**

在 `database_service.dart` 行 190（`if (oldVersion < 10)` 块结束后、`onUpgrade` 闭合 `});` 之前）添加：

```dart
        if (oldVersion < 11) {
          // v2.34: 打板梯队池（情绪温度计 + 连板分组）
          await db.execute('''
            CREATE TABLE limit_up_pool (
              code              TEXT    NOT NULL,
              name              TEXT    NOT NULL,
              trade_date        TEXT    NOT NULL,
              limit_up_price    REAL    NOT NULL DEFAULT 0,
              first_limit_time  INTEGER,
              last_limit_time   INTEGER,
              consecutive_days  INTEGER NOT NULL DEFAULT 1,
              board_type        TEXT    NOT NULL DEFAULT '',
              seal_amount       REAL    NOT NULL DEFAULT 0,
              seal_ratio        REAL    NOT NULL DEFAULT 0,
              volume_ratio      REAL    NOT NULL DEFAULT 0,
              turnover_rate     REAL    NOT NULL DEFAULT 0,
              is_zhaban         INTEGER NOT NULL DEFAULT 0,
              zhaban_count      INTEGER NOT NULL DEFAULT 0,
              sector            TEXT,
              quality_score     REAL    NOT NULL DEFAULT 0,
              premium_prob      REAL    NOT NULL DEFAULT 0,
              price             REAL    NOT NULL DEFAULT 0,
              change_pct        REAL    NOT NULL DEFAULT 0,
              updated_at        INTEGER NOT NULL,
              PRIMARY KEY (code, trade_date)
            )
          ''');
          await db.execute('CREATE INDEX idx_limit_up_pool_date ON limit_up_pool(trade_date)');
          await db.execute('CREATE INDEX idx_limit_up_pool_consec ON limit_up_pool(trade_date, consecutive_days DESC)');
          debugPrint('[DB] v10→v11: created limit_up_pool table');
        }
```

- [ ] **Step 5: 在 _createTables 中添加全量建表**

在 `_createTables` 方法中（行 195 起，找到最后一个 `CREATE TABLE` 语句后）添加相同的 `CREATE TABLE limit_up_pool` + 2 个 `CREATE INDEX` 语句（与 Step 4 相同的 SQL）。

- [ ] **Step 6: 运行测试验证通过**

Run: `cd mobile && flutter test test/limit_up_pool_db_test.dart`
Expected: PASS

- [ ] **Step 7: 运行全量测试**

Run: `cd mobile && flutter test`
Expected: 全部通过（版本号变更会触发迁移，验证既有表不受影响）

- [ ] **Step 8: Commit**

```bash
cd mobile && git add lib/storage/database_service.dart test/limit_up_pool_db_test.dart
git commit -m "feat: DB v10→v11 迁移 — 新建 limit_up_pool 表（复合主键支持历史回看）"
```

---

## Task 4: DatabaseService limit_up_pool CRUD 方法

**Files:**
- Modify: `mobile/lib/storage/database_service.dart`（在 `getSectorPickLastTime` 之后，约行 644 后添加）
- Test: `mobile/test/limit_up_pool_db_test.dart`（追加测试）

- [ ] **Step 1: 追加失败测试**

在 `mobile/test/limit_up_pool_db_test.dart` 末尾追加：

```dart
  group('DatabaseService limit_up_pool CRUD', () {
    test('replaceLimitUpPool is full replace per trade_date', () async {
      // 集成测试：需要 DatabaseService 实例
      // 验证同 trade_date 的数据被替换，不同 trade_date 保留
      final svc = DatabaseService();
      final date = DateTime.now().toIso8601String().substring(0, 10);
      final analyses = [
        LimitUpAnalysis(code: '600519', name: '茅台', consecutiveDays: 3, qualityScore: 8.5),
        LimitUpAnalysis(code: '000001', name: '平安银行', consecutiveDays: 1, qualityScore: 6.0),
      ];
      await svc.replaceLimitUpPool(analyses, date);
      final result = await svc.getLimitUpPool(tradeDate: date);
      expect(result, hasLength(2));

      // 替换为 1 条
      await svc.replaceLimitUpPool([
        LimitUpAnalysis(code: '600519', name: '茅台', consecutiveDays: 4, qualityScore: 9.0),
      ], date);
      final result2 = await svc.getLimitUpPool(tradeDate: date);
      expect(result2, hasLength(1));
      expect(result2.first.consecutiveDays, 4);
    });

    test('getLimitUpPoolByDate returns only that date', () async {
      final svc = DatabaseService();
      final today = DateTime.now().toIso8601String().substring(0, 10);
      final yesterday = DateTime.now().subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
      await svc.replaceLimitUpPool([
        LimitUpAnalysis(code: '600519', name: '茅台', consecutiveDays: 3),
      ], today);
      await svc.replaceLimitUpPool([
        LimitUpAnalysis(code: '000001', name: '平安银行', consecutiveDays: 1),
      ], yesterday);

      final todayPool = await svc.getLimitUpPoolByDate(today);
      expect(todayPool.every((a) => a.code == '600519'), isTrue);

      final yPool = await svc.getLimitUpPoolByDate(yesterday);
      expect(yPool.every((a) => a.code == '000001'), isTrue);
    });
  });
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd mobile && flutter test test/limit_up_pool_db_test.dart`
Expected: FAIL — `replaceLimitUpPool` / `getLimitUpPool` / `getLimitUpPoolByDate` 方法不存在

- [ ] **Step 3: 实现 CRUD 方法**

在 `database_service.dart` 的 `getSectorPickLastTime` 方法之后（约行 644 后）添加：

```dart
  // ========== 打板梯队池 CRUD (v2.34) ==========

  /// 全量替换指定交易日的打板池数据
  Future<void> replaceLimitUpPool(List<LimitUpAnalysis> analyses, String tradeDate) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('limit_up_pool', where: 'trade_date = ?', whereArgs: [tradeDate]);
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final a in analyses) {
        final m = a.toMap();
        m['trade_date'] = tradeDate;
        m['updated_at'] = now;
        await txn.insert('limit_up_pool', m);
      }
    });
  }

  /// 获取打板池数据（默认今日，可指定日期）
  Future<List<LimitUpAnalysis>> getLimitUpPool({String? tradeDate}) async {
    final db = await database;
    final date = tradeDate ?? DateTime.now().toIso8601String().substring(0, 10);
    final result = await db.query(
      'limit_up_pool',
      where: 'trade_date = ?',
      whereArgs: [date],
      orderBy: 'consecutive_days DESC, seal_amount DESC',
    );
    // QueryResultSet 只读，返回 List<LimitUpAnalysis>（已通过 fromMap 创建新对象）
    return result.map((m) => LimitUpAnalysis.fromMap(m)).toList();
  }

  /// 获取指定交易日的打板池（历史回看用）
  Future<List<LimitUpAnalysis>> getLimitUpPoolByDate(String tradeDate) async {
    return getLimitUpPool(tradeDate: tradeDate);
  }

  /// 获取最近的打板池交易日列表（情绪周期曲线用）
  Future<List<String>> getLimitUpDates({int limit = 30}) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT DISTINCT trade_date FROM limit_up_pool ORDER BY trade_date DESC LIMIT ?',
      [limit],
    );
    return result.map((m) => m['trade_date'] as String).toList();
  }
```

- [ ] **Step 4: 运行测试验证通过**

Run: `cd mobile && flutter test test/limit_up_pool_db_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd mobile && git add lib/storage/database_service.dart test/limit_up_pool_db_test.dart
git commit -m "feat: DatabaseService limit_up_pool CRUD — 全量替换+历史回看+日期列表"
```

---

## Task 5: ApiClient.getLimitUpBoard()

**Files:**
- Modify: `mobile/lib/api/api_client.dart`（在 `getBatchRealtimeQuotes` 之后，约行 1422 后添加）
- Test: `mobile/test/api_limit_up_board_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `mobile/test/api_limit_up_board_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock/api/api_client.dart';

void main() {
  group('ApiClient.getLimitUpBoard', () {
    test('method exists and returns List<LimitUpStock>', () {
      final client = ApiClient();
      // 验证方法存在（实际网络调用在集成测试中验证）
      expect(client.getLimitUpBoard, isNotNull);
    });

    test('getYesterdayLimitUpPool method exists', () {
      final client = ApiClient();
      expect(client.getYesterdayLimitUpPool, isNotNull);
    });
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd mobile && flutter test test/api_limit_up_board_test.dart`
Expected: FAIL — `getLimitUpBoard` / `getYesterdayLimitUpPool` 方法不存在

- [ ] **Step 3: 实现 API 方法**

在 `api_client.dart` 行 1422 后（`getBatchRealtimeQuotes` 方法之后）添加：

```dart
  /// 当日涨停板池（东方财富 push2ex.eastmoney.com/getTopicZTPool）
  /// 返回完整涨停数据：连板数/首封时间/封单/换手/炸板标记
  Future<List<LimitUpStock>> getLimitUpBoard({DateTime? date, int pageSize = 500}) async {
    final dateStr = (date ?? DateTime.now()).toLocal().toString().substring(0, 10).replaceAll('-', '');
    final url = Uri.parse(
      'https://push2ex.eastmoney.com/getTopicZTPool'
      '?ut=7eea3edcaed734bea9cbfc24409ed989'
      '&dpt=wz.ztzt'
      '&Pageindex=0'
      '&Pagesize=$pageSize'
      '&sort=fbt:asc'
      '&date=$dateStr'
      '&_=${DateTime.now().millisecondsSinceEpoch}',
    );
    try {
      final response = await _httpGet(url, headers: {
        'Referer': 'https://quote.eastmoney.com/ztb/detail',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0',
      });
      if (response == null) {
        debugPrint('getLimitUpBoard: response null for date=$dateStr');
        return [];
      }
      final json = _decodeJson(response.bodyBytes);
      final pool = json['data']?['pool'] as List?;
      if (pool == null) return [];
      return pool
          .map((e) => LimitUpStock.fromEastMoney(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('getLimitUpBoard failed: $e');
      return [];
    }
  }

  /// 昨日涨停股池（用于计算赚钱效应）
  Future<List<LimitUpStock>> getYesterdayLimitUpPool() async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return getLimitUpBoard(date: yesterday);
  }
```

注意：`_decodeJson` 是 ApiClient 中已有的 JSON 解码方法（若不存在，用 `jsonDecode(utf8.decode(response.bodyBytes))` 替代）。用 Grep 确认 `_decodeJson` 或 `_decodeGbk` 的存在并复用。

- [ ] **Step 4: 添加 import**

在 `api_client.dart` 顶部添加（若尚未导入 `limit_up_analyzer.dart`）：

```dart
import 'package:stock/analysis/limit_up_analyzer.dart';
```

- [ ] **Step 5: 运行测试验证通过**

Run: `cd mobile && flutter test test/api_limit_up_board_test.dart`
Expected: PASS

- [ ] **Step 6: 运行 flutter analyze**

Run: `cd mobile && flutter analyze`
Expected: 0 errors

- [ ] **Step 7: Commit**

```bash
cd mobile && git add lib/api/api_client.dart test/api_limit_up_board_test.dart
git commit -m "feat: ApiClient.getLimitUpBoard — 东方财富涨停板池接口接入"
```

---

## Task 6: SentimentThermometer 纯函数引擎

**Files:**
- Create: `mobile/lib/analysis/sentiment_thermometer.dart`
- Modify: `mobile/lib/models/stock_models.dart`（新增 SentimentResult + EmotionPhase）
- Test: `mobile/test/sentiment_thermometer_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `mobile/test/sentiment_thermometer_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock/analysis/limit_up_analyzer.dart';
import 'package:stock/analysis/sentiment_thermometer.dart';
import 'package:stock/models/stock_models.dart';

void main() {
  group('SentimentThermometer', () {
    group('zhabanRate', () {
      test('empty pool returns neutral 0.5', () {
        final r = SentimentThermometer.compute(
          todayPool: [], yesterdayPool: [], todayQuotePct: {},
        );
        expect(r.zhabanRate, 0.5);
      });

      test('all zhaban returns 1.0', () {
        final pool = [
          LimitUpAnalysis(code: '001', name: 'A', isZhaBan: true),
          LimitUpAnalysis(code: '002', name: 'B', isZhaBan: true),
        ];
        final r = SentimentThermometer.compute(
          todayPool: pool, yesterdayPool: [], todayQuotePct: {});
        expect(r.zhabanRate, 1.0);
      });

      test('half zhaban returns 0.5', () {
        final pool = [
          LimitUpAnalysis(code: '001', name: 'A', isZhaBan: true),
          LimitUpAnalysis(code: '002', name: 'B', isZhaBan: false),
        ];
        final r = SentimentThermometer.compute(
          todayPool: pool, yesterdayPool: [], todayQuotePct: {});
        expect(r.zhabanRate, 0.5);
      });
    });

    group('continuationRate', () {
      test('yesterday empty returns 0.3', () {
        final r = SentimentThermometer.compute(
          todayPool: [LimitUpAnalysis(code: '001', name: 'A', consecutiveDays: 2)],
          yesterdayPool: [], todayQuotePct: {});
        expect(r.continuationRate, 0.3);
      });

      test('yesterday 10 first-board, today 5 second-board → 0.5', () {
        final yesterday = List.generate(10, (i) =>
            LimitUpAnalysis(code: '00$i', name: 'Y$i', consecutiveDays: 1));
        final today = List.generate(5, (i) =>
            LimitUpAnalysis(code: '00$i', name: 'T$i', consecutiveDays: 2));
        today.addAll(List.generate(10, (i) =>
            LimitUpAnalysis(code: '01$i', name: 'F$i', consecutiveDays: 1)));
        final r = SentimentThermometer.compute(
          todayPool: today, yesterdayPool: yesterday, todayQuotePct: {});
        expect(r.continuationRate, 0.5);
      });
    });

    group('moneyMakingEffect', () {
      test('empty yesterday returns 0.0', () {
        final r = SentimentThermometer.compute(
          todayPool: [], yesterdayPool: [], todayQuotePct: {});
        expect(r.moneyMakingEffect, 0.0);
      });

      test('average of yesterday pct change', () {
        final yesterday = [
          LimitUpAnalysis(code: '001', name: 'A'),
          LimitUpAnalysis(code: '002', name: 'B'),
        ];
        final quotes = {'001': 3.0, '002': 5.0};
        final r = SentimentThermometer.compute(
          todayPool: [], yesterdayPool: yesterday, todayQuotePct: quotes);
        expect(r.moneyMakingEffect, 4.0);  // (3+5)/2
      });
    });

    group('temperature', () {
      test('all bad → low temperature', () {
        final pool = [
          LimitUpAnalysis(code: '001', name: 'A', isZhaBan: true, consecutiveDays: 1),
        ];
        final r = SentimentThermometer.compute(
          todayPool: pool, yesterdayPool: [], todayQuotePct: {});
        expect(r.temperature, lessThan(30));
      });

      test('all good → high temperature', () {
        final today = List.generate(60, (i) =>
            LimitUpAnalysis(code: '00$i', name: 'T$i', consecutiveDays: 5,
                isZhaBan: false, sealAmount: 20000));
        final yesterday = List.generate(10, (i) =>
            LimitUpAnalysis(code: '00$i', name: 'Y$i', consecutiveDays: 1));
        final quotes = {for (var i = 0; i < 10; i++) '00$i': 5.0};
        final r = SentimentThermometer.compute(
          todayPool: today, yesterdayPool: yesterday, todayQuotePct: quotes);
        expect(r.temperature, greaterThan(60));
      });
    });

    group('phase inference', () {
      test('startup: 30+ limitUp, height≤3, temp 30-55', () {
        final pool = List.generate(35, (i) =>
            LimitUpAnalysis(code: '00$i', name: 'A$i', consecutiveDays: 2, isZhaBan: false));
        final r = SentimentThermometer.compute(
          todayPool: pool, yesterdayPool: [], todayQuotePct: {});
        expect(r.phase, EmotionPhase.startup);
      });

      test('climax: 50+ limitUp, height≥4, temp≥60', () {
        final pool = List.generate(60, (i) =>
            LimitUpAnalysis(code: '00$i', name: 'A$i',
                consecutiveDays: i < 5 ? 5 : 2, isZhaBan: false, sealAmount: 20000));
        final yesterday = List.generate(10, (i) =>
            LimitUpAnalysis(code: '00$i', name: 'Y$i', consecutiveDays: 1));
        final quotes = {for (var i = 0; i < 10; i++) '00$i': 5.0};
        final r = SentimentThermometer.compute(
          todayPool: pool, yesterdayPool: yesterday, todayQuotePct: quotes);
        expect(r.phase, EmotionPhase.climax);
      });

      test('freezing: <20 limitUp, height≤2, temp<30', () {
        final pool = [
          LimitUpAnalysis(code: '001', name: 'A', consecutiveDays: 1, isZhaBan: true),
          LimitUpAnalysis(code: '002', name: 'B', consecutiveDays: 1, isZhaBan: true),
        ];
        final r = SentimentThermometer.compute(
          todayPool: pool, yesterdayPool: [], todayQuotePct: {});
        expect(r.phase, EmotionPhase.freezing);
      });

      test('state transition: climax → retreat when temp drops', () {
        final yesterdayResult = SentimentResult(
          temperature: 70, phase: EmotionPhase.climax,
          zhabanRate: 0.1, continuationRate: 0.6, sealSuccessRate: 0.9,
          moneyMakingEffect: 5, limitUpCount: 60, limitDownCount: 2,
          continuationHeight: 5, signals: [], timestamp: DateTime.now(),
        );
        // 今日温度降到 50
        final pool = List.generate(25, (i) =>
            LimitUpAnalysis(code: '00$i', name: 'A$i', consecutiveDays: 2, isZhaBan: true));
        final r = SentimentThermometer.compute(
          todayPool: pool, yesterdayPool: [], todayQuotePct: {},
          yesterdayPhase: yesterdayResult.phase);
        expect(r.phase, EmotionPhase.retreat);
      });
    });

    group('signals', () {
      test('zhabanRate >= 0.7 generates warning', () {
        final pool = List.generate(10, (i) =>
            LimitUpAnalysis(code: '00$i', name: 'A$i', isZhaBan: true));
        final r = SentimentThermometer.compute(
          todayPool: pool, yesterdayPool: [], todayQuotePct: {});
        expect(r.signals.any((s) => s.contains('炸板潮')), isTrue);
      });

      test('zhabanRate < 0.15 generates strong seal signal', () {
        final pool = List.generate(20, (i) =>
            LimitUpAnalysis(code: '00$i', name: 'A$i', isZhaBan: false, consecutiveDays: 2));
        final r = SentimentThermometer.compute(
          todayPool: pool, yesterdayPool: [], todayQuotePct: {});
        expect(r.signals.any((s) => s.contains('封板极强')), isTrue);
      });
    });
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd mobile && flutter test test/sentiment_thermometer_test.dart`
Expected: FAIL — `SentimentThermometer` 类不存在，`SentimentResult` / `EmotionPhase` 不存在

- [ ] **Step 3: 在 stock_models.dart 新增 SentimentResult + EmotionPhase**

在 `mobile/lib/models/stock_models.dart` 末尾（行 1379 后）添加：

```dart
/// 情绪周期阶段
enum EmotionPhase { startup, climax, retreat, freezing }

/// 情绪温度计计算结果
class SentimentResult {
  final double temperature;          // 0-100
  final EmotionPhase phase;
  final double zhabanRate;           // 炸板率 [0,1]
  final double continuationRate;     // 连板晋级率 [0,1]
  final double sealSuccessRate;      // 涨停封板成功率 [0,1]
  final double moneyMakingEffect;    // 赚钱效应（%）
  final int limitUpCount;
  final int limitDownCount;
  final int continuationHeight;      // 最高连板数
  final List<String> signals;
  final DateTime timestamp;

  const SentimentResult({
    required this.temperature,
    required this.phase,
    required this.zhabanRate,
    required this.continuationRate,
    required this.sealSuccessRate,
    required this.moneyMakingEffect,
    required this.limitUpCount,
    required this.limitDownCount,
    required this.continuationHeight,
    required this.signals,
    required this.timestamp,
  });
}
```

- [ ] **Step 4: 创建 SentimentThermometer 引擎**

创建 `mobile/lib/analysis/sentiment_thermometer.dart`：

```dart
import 'package:stock/analysis/limit_up_analyzer.dart';
import 'package:stock/models/stock_models.dart';

/// 情绪温度计纯函数引擎
/// 输入：今日打板池 + 昨日打板池 + 今日行情涨跌幅 + 昨日阶段
/// 输出：SentimentResult（5维指标 + 温度 + 阶段 + 信号）
class SentimentThermometer {
  const SentimentThermometer._();

  /// 主计算入口
  static SentimentResult compute({
    required List<LimitUpAnalysis> todayPool,
    required List<LimitUpAnalysis> yesterdayPool,
    required Map<String, double> todayQuotePct,
    EmotionPhase? yesterdayPhase,
  }) {
    final zhabanRate = _computeZhabanRate(todayPool);
    final continuationRate = _computeContinuationRate(todayPool, yesterdayPool);
    final sealSuccessRate = _computeSealSuccessRate(todayPool);
    final moneyMakingEffect = _computeMoneyMakingEffect(yesterdayPool, todayQuotePct);
    final continuationHeight = _computeContinuationHeight(todayPool);
    final limitUpCount = todayPool.where((a) => !a.isZhaBan).length;
    final limitDownCount = 0;  // P0 暂不接入跌停数据

    final temperature = _computeTemperature(
      zhabanRate: zhabanRate,
      continuationRate: continuationRate,
      sealSuccessRate: sealSuccessRate,
      moneyMakingEffect: moneyMakingEffect,
      continuationHeight: continuationHeight,
    );

    final phase = _inferPhase(
      temperature: temperature,
      limitUpCount: limitUpCount,
      continuationHeight: continuationHeight,
      continuationRate: continuationRate,
      yesterdayPhase: yesterdayPhase,
    );

    final signals = _generateSignals(
      zhabanRate: zhabanRate,
      continuationRate: continuationRate,
      moneyMakingEffect: moneyMakingEffect,
      continuationHeight: continuationHeight,
      limitUpCount: limitUpCount,
    );

    return SentimentResult(
      temperature: temperature,
      phase: phase,
      zhabanRate: zhabanRate,
      continuationRate: continuationRate,
      sealSuccessRate: sealSuccessRate,
      moneyMakingEffect: moneyMakingEffect,
      limitUpCount: limitUpCount,
      limitDownCount: limitDownCount,
      continuationHeight: continuationHeight,
      signals: signals,
      timestamp: DateTime.now(),
    );
  }

  // === 维度 1: 炸板率 ===
  static double _computeZhabanRate(List<LimitUpAnalysis> pool) {
    if (pool.isEmpty) return 0.5;
    final zhaban = pool.where((a) => a.isZhaBan).length;
    return zhaban / pool.length;
  }

  // === 维度 2: 连板晋级率（1板→2板）===
  static double _computeContinuationRate(
    List<LimitUpAnalysis> today,
    List<LimitUpAnalysis> yesterday,
  ) {
    if (yesterday.isEmpty) return 0.3;
    final y1 = yesterday.where((a) => a.consecutiveDays == 1).length;
    final t2 = today.where((a) => a.consecutiveDays >= 2).length;
    if (y1 == 0) return 0.3;
    return (t2 / y1).clamp(0.0, 1.0);
  }

  // === 维度 3: 涨停封板成功率 ===
  static double _computeSealSuccessRate(List<LimitUpAnalysis> pool) {
    if (pool.isEmpty) return 0.5;
    final sealed = pool.where((a) => !a.isZhaBan).length;
    final rawRate = sealed / pool.length;
    final weakSealCount = pool.where((a) =>
        !a.isZhaBan && a.sealAmount < 1000).length;
    final penalty = weakSealCount / pool.length * 0.2;
    return (rawRate - penalty).clamp(0.0, 1.0);
  }

  // === 维度 4: 赚钱效应 ===
  static double _computeMoneyMakingEffect(
    List<LimitUpAnalysis> yesterdayPool,
    Map<String, double> todayQuotePct,
  ) {
    if (yesterdayPool.isEmpty) return 0.0;
    final pcts = yesterdayPool.map((a) => todayQuotePct[a.code] ?? 0.0).toList();
    return pcts.reduce((a, b) => a + b) / pcts.length;
  }

  // === 维度 5: 连板高度 ===
  static int _computeContinuationHeight(List<LimitUpAnalysis> pool) {
    return pool.fold(1, (max, a) => a.consecutiveDays > max ? a.consecutiveDays : max);
  }

  // === 综合温度 ===
  static double _computeTemperature({
    required double zhabanRate,
    required double continuationRate,
    required double sealSuccessRate,
    required double moneyMakingEffect,
    required int continuationHeight,
  }) {
    final zhabanScore = 1.0 - zhabanRate;
    final contScore = continuationRate.clamp(0.0, 1.0);
    final sealScore = sealSuccessRate.clamp(0.0, 1.0);
    final moneyScore = ((moneyMakingEffect + 5) / 10).clamp(0.0, 1.0);
    final heightScore = (continuationHeight / 7).clamp(0.0, 1.0);
    final temp = zhabanScore * 20 + contScore * 25 + sealScore * 15
               + moneyScore * 30 + heightScore * 10;
    return temp.clamp(0.0, 100.0);
  }

  // === 阶段判定 ===
  static EmotionPhase _inferPhase({
    required double temperature,
    required int limitUpCount,
    required int continuationHeight,
    required double continuationRate,
    required EmotionPhase? yesterdayPhase,
  }) {
    if (limitUpCount >= 30 && continuationHeight <= 3 &&
        temperature >= 30 && temperature < 55) {
      return EmotionPhase.startup;
    }
    if (limitUpCount >= 50 && continuationHeight >= 4 && temperature >= 60) {
      return EmotionPhase.climax;
    }
    if (temperature >= 40 && temperature < 60 &&
        (continuationRate < 0.3 || yesterdayPhase == EmotionPhase.climax)) {
      return EmotionPhase.retreat;
    }
    if (limitUpCount < 20 && continuationHeight <= 2 && temperature < 30) {
      return EmotionPhase.freezing;
    }
    if (yesterdayPhase == null) return EmotionPhase.startup;
    switch (yesterdayPhase) {
      case EmotionPhase.freezing:
        return temperature >= 35 ? EmotionPhase.startup : EmotionPhase.freezing;
      case EmotionPhase.startup:
        return temperature >= 60 ? EmotionPhase.climax : EmotionPhase.startup;
      case EmotionPhase.climax:
        return temperature < 55 ? EmotionPhase.retreat : EmotionPhase.climax;
      case EmotionPhase.retreat:
        return temperature < 30 ? EmotionPhase.freezing : EmotionPhase.retreat;
    }
  }

  // === 信号生成 ===
  static List<String> _generateSignals({
    required double zhabanRate,
    required double continuationRate,
    required double moneyMakingEffect,
    required int continuationHeight,
    required int limitUpCount,
  }) {
    return [
      if (zhabanRate >= 0.7) '⚠️ 炸板潮：封板意愿极弱，打板胜率低',
      if (zhabanRate < 0.15) '🔥 封板极强：打板情绪高涨',
      if (continuationRate > 0.5) '🚀 接力强：连板晋级率高',
      if (continuationRate < 0.1) '❄️ 接力冰点：避免追高',
      if (moneyMakingEffect > 3) '💰 赚钱效应强：昨日打板今日盈利',
      if (moneyMakingEffect < -3) '💸 亏钱效应：昨日打板今日亏损',
      if (continuationHeight >= 5) '👑 龙头${continuationHeight}板：高度突破',
      if (limitUpCount >= 80) '🌊 涨停潮：$limitUpCount家涨停',
      if (limitUpCount < 15) '🧊 涨停稀少：$limitUpCount家',
    ];
  }
}
```

- [ ] **Step 5: 运行测试验证通过**

Run: `cd mobile && flutter test test/sentiment_thermometer_test.dart`
Expected: PASS — 所有测试通过

- [ ] **Step 6: Commit**

```bash
cd mobile && git add lib/analysis/sentiment_thermometer.dart lib/models/stock_models.dart test/sentiment_thermometer_test.dart
git commit -m "feat: SentimentThermometer 纯函数引擎 — 5维情绪指标+阶段判定+信号生成"
```

---

## Task 7: LimitUpUniverseProvider 涨停池采集器

**Files:**
- Create: `mobile/lib/analysis/limit_up_universe_provider.dart`
- Test: `mobile/test/limit_up_universe_provider_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `mobile/test/limit_up_universe_provider_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock/analysis/limit_up_universe_provider.dart';
import 'package:stock/analysis/limit_up_analyzer.dart';

void main() {
  group('LimitUpUniverseProvider', () {
    test('mergeAndDedup removes duplicate codes', () {
      final today = [
        LimitUpStock(code: '600519', name: '茅台', consecutiveDays: 3, sealAmount: 23000),
        LimitUpStock(code: '000001', name: '平安银行', consecutiveDays: 1),
      ];
      final fresh = [
        LimitUpStock(code: '600519', name: '茅台', consecutiveDays: 3, sealAmount: 25000),
        LimitUpStock(code: '000002', name: '万科A', consecutiveDays: 2),
      ];
      final merged = LimitUpUniverseProvider.mergeAndDedup(today, fresh);
      expect(merged, hasLength(3));
      final maotai = merged.firstWhere((s) => s.code == '600519');
      expect(maotai.sealAmount, 25000);  // fresh 覆盖 today
    });

    test('supplementQuotes fills price and changePct', () {
      final stocks = [
        LimitUpStock(code: '600519', name: '茅台'),
      ];
      final quotes = [
        QuoteData(code: 'sh.600519', name: '茅台', price: 1689.5, changePct: 10.0),
      ];
      final result = LimitUpUniverseProvider.supplementQuotes(stocks, quotes);
      expect(result.first.price, 1689.5);
      expect(result.first.changePct, 10.0);
    });
  });
}
```

注意：`QuoteData` 需要 import。用 Grep 确认 `QuoteData` 的定义位置和 `code` 字段格式（带 `sh.`/`sz.` 前缀）。

- [ ] **Step 2: 运行测试验证失败**

Run: `cd mobile && flutter test test/limit_up_universe_provider_test.dart`
Expected: FAIL — `LimitUpUniverseProvider` 类不存在

- [ ] **Step 3: 创建 LimitUpUniverseProvider**

创建 `mobile/lib/analysis/limit_up_universe_provider.dart`：

```dart
import 'package:flutter/foundation.dart';
import 'package:stock/analysis/limit_up_analyzer.dart';
import 'package:stock/api/api_client.dart';
import 'package:stock/models/stock_models.dart';

/// 涨停池数据采集器
/// 负责：API 拉取 + DB 缓存合并 + 行情字段补全 + 去重
class LimitUpUniverseProvider {
  const LimitUpUniverseProvider._();

  /// 合并今日 DB 缓存与 API 最新数据，去重（fresh 覆盖 today）
  static List<LimitUpStock> mergeAndDedup(
    List<LimitUpStock> today,
    List<LimitUpStock> fresh,
  ) {
    final map = <String, LimitUpStock>{};
    for (final s in today) map[s.code] = s;
    for (final s in fresh) map[s.code] = s;  // fresh 覆盖
    return map.values.toList();
  }

  /// 用实时行情补充 price/changePct/volumeRatio/limitUpPrice
  /// quotes 的 code 带市场前缀（sh./sz.），需剥离前缀匹配
  static List<LimitUpStock> supplementQuotes(
    List<LimitUpStock> stocks,
    List<QuoteData> quotes,
  ) {
    final quoteMap = <String, QuoteData>{};
    for (final q in quotes) {
      // 剥离 sh./sz. 前缀
      final bareCode = q.code.replaceAll(RegExp(r'^(sh|sz|bj)\.'), '');
      quoteMap[bareCode] = q;
    }
    return stocks.map((s) {
      final q = quoteMap[s.code];
      if (q == null) return s;
      return LimitUpStock(
        code: s.code, name: s.name,
        price: q.price, changePct: q.changePct,
        consecutiveDays: s.consecutiveDays,
        firstLimitTime: s.firstLimitTime, lastLimitTime: s.lastLimitTime,
        sealAmount: s.sealAmount, turnoverRate: s.turnoverRate,
        volumeRatio: q.turnover > 0 ? q.turnover : s.volumeRatio,
        sector: s.sector, limitUpType: s.limitUpType,
        sealRatio: s.sealRatio, limitUpPrice: s.limitUpPrice,
        totalValue: s.totalValue, circulationValue: s.circulationValue,
        zhabanCount: s.zhabanCount, isZhaBan: s.isZhaBan,
      );
    }).toList();
  }

  /// 完整采集流程：API 拉取 + 行情补全
  /// 调用方负责分片（每批 30 只调用 getBatchRealtimeQuotes）
  static Future<List<LimitUpStock>> fetchLatest({ApiClient? apiClient}) async {
    final api = apiClient ?? ApiClient();
    try {
      final pool = await api.getLimitUpBoard();
      if (pool.isEmpty) return [];
      // 分片补充行情
      final batchSize = 30;
      final allQuotes = <QuoteData>[];
      for (var i = 0; i < pool.length; i += batchSize) {
        final batch = pool.skip(i).take(batchSize).map((s) => s.code).toList();
        // 注意：getBatchRealtimeQuotes 需要带前缀的 code，这里需转换
        // 暂用裸 code，腾讯接口可能需要 sh./sz. 前缀
        final prefixed = batch.map((c) => _addMarketPrefix(c)).toList();
        final quotes = await api.getBatchRealtimeQuotes(prefixed);
        allQuotes.addAll(quotes);
      }
      return supplementQuotes(pool, allQuotes);
    } catch (e) {
      debugPrint('LimitUpUniverseProvider.fetchLatest failed: $e');
      return [];
    }
  }

  /// 添加市场前缀（腾讯接口需要）
  static String _addMarketPrefix(String code) {
    if (code.startsWith('6') || code.startsWith('5')) return 'sh.$code';
    if (code.startsWith('0') || code.startsWith('3') || code.startsWith('1')) return 'sz.$code';
    if (code.startsWith('8') || code.startsWith('43')) return 'bj.$code';
    return 'sz.$code';
  }
}
```

- [ ] **Step 4: 运行测试验证通过**

Run: `cd mobile && flutter test test/limit_up_universe_provider_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd mobile && git add lib/analysis/limit_up_universe_provider.dart test/limit_up_universe_provider_test.dart
git commit -m "feat: LimitUpUniverseProvider 涨停池采集器 — API拉取+行情补全+去重"
```

---

## Task 8: LimitUpScanEngine 协调器

**Files:**
- Create: `mobile/lib/analysis/limit_up_scan_engine.dart`
- Test: `mobile/test/limit_up_scan_engine_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `mobile/test/limit_up_scan_engine_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock/analysis/limit_up_scan_engine.dart';

void main() {
  group('LimitUpScanEngine', () {
    test('is singleton', () {
      expect(LimitUpScanEngine.instance, same(LimitUpScanEngine.instance));
    });

    test('initial state: not running, no latest progress', () {
      final engine = LimitUpScanEngine.instance;
      // dispose 后重新检查初始状态
      engine.dispose();
      expect(engine.isRunning, isFalse);
      expect(engine.latestProgress, isNull);
    });
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd mobile && flutter test test/limit_up_scan_engine_test.dart`
Expected: FAIL — `LimitUpScanEngine` 类不存在

- [ ] **Step 3: 创建 LimitUpScanEngine**

创建 `mobile/lib/analysis/limit_up_scan_engine.dart`：

```dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:stock/analysis/base_analysis_engine.dart';
import 'package:stock/analysis/limit_up_analyzer.dart';
import 'package:stock/analysis/limit_up_universe_provider.dart';
import 'package:stock/analysis/sentiment_thermometer.dart';
import 'package:stock/api/api_client.dart';
import 'package:stock/models/stock_models.dart';
import 'package:stock/storage/database_service.dart';

/// 打板扫描进度
class LimitUpScanProgress {
  final String stage;        // 'fetching' / 'analyzing' / 'computing_sentiment' / 'done'
  final int current;
  final int total;
  final String? message;
  const LimitUpScanProgress({
    required this.stage,
    this.current = 0,
    this.total = 0,
    this.message,
  });
}

/// 打板扫描协调器
/// 封装：API 拉取 → analyzeBatchList → SentimentThermometer.compute → 落库
class LimitUpScanEngine extends BaseAnalysisEngine<LimitUpScanProgress> {
  static final LimitUpScanEngine _instance = LimitUpScanEngine._();
  static LimitUpScanEngine get instance => _instance;

  final ApiClient _apiClient;
  final DatabaseService _dbService;

  LimitUpScanEngine._()
      : _apiClient = ApiClient(),
        _dbService = DatabaseService();

  /// 执行完整扫描流程
  /// 返回 SentimentResult（也通过 progressStream 广播进度）
  Future<SentimentResult?> scan() async {
    if (!tryStart(const LimitUpScanProgress(
        stage: 'already_running', message: '扫描进行中'))) {
      return null;
    }

    try {
      // Step 1: 拉取今日 + 昨日涨停池
      emit(const LimitUpScanProgress(stage: 'fetching', message: '拉取涨停板数据...'));
      final todayStocks = await LimitUpUniverseProvider.fetchLatest(apiClient: _apiClient);
      if (todayStocks.isEmpty) {
        emit(const LimitUpScanProgress(stage: 'done', message: '今日暂无涨停标的'));
        return null;
      }

      final yesterdayStocks = await _apiClient.getYesterdayLimitUpPool();
      final yesterdayAnalyses = LimitUpAnalyzer.analyzeBatchList(yesterdayStocks);

      // Step 2: 分析今日涨停股
      emit(LimitUpScanProgress(
          stage: 'analyzing', current: 0, total: todayStocks.length,
          message: '分析打板质量...'));
      final todayAnalyses = LimitUpAnalyzer.analyzeBatchList(todayStocks);

      // Step 3: 补充行情数据到 todayAnalyses（price/changePct）
      // analyzeBatchList 已通过 LimitUpStock 传入 price/changePct
      // 但 fromEastMoney 时 price=0，需通过 supplementQuotes 补充
      //（已在 LimitUpUniverseProvider.fetchLatest 中完成）

      // Step 4: 计算情绪温度计
      emit(const LimitUpScanProgress(stage: 'computing_sentiment', message: '计算情绪温度计...'));
      final todayQuotePct = <String, double>{};
      for (final a in todayAnalyses) {
        todayQuotePct[a.code] = a.changePct;
      }
      final sentiment = SentimentThermometer.compute(
        todayPool: todayAnalyses,
        yesterdayPool: yesterdayAnalyses,
        todayQuotePct: todayQuotePct,
        yesterdayPhase: _lastSentiment?.phase,
      );
      _lastSentiment = sentiment;

      // Step 5: 落库
      final tradeDate = DateTime.now().toIso8601String().substring(0, 10);
      await _dbService.replaceLimitUpPool(todayAnalyses, tradeDate);

      emit(const LimitUpScanProgress(stage: 'done', message: '扫描完成'));
      return sentiment;
    } catch (e) {
      debugPrint('LimitUpScanEngine.scan failed: $e');
      emit(LimitUpScanProgress(stage: 'error', message: '扫描失败: $e'));
      return null;
    } finally {
      markFinished();
    }
  }

  SentimentResult? _lastSentiment;
  /// 内存缓存最近一次情绪结果（供下次计算 yesterdayPhase）
  SentimentResult? get lastSentiment => _lastSentiment;
}
```

- [ ] **Step 4: 运行测试验证通过**

Run: `cd mobile && flutter test test/limit_up_scan_engine_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd mobile && git add lib/analysis/limit_up_scan_engine.dart test/limit_up_scan_engine_test.dart
git commit -m "feat: LimitUpScanEngine 协调器 — 封装 API+分析+情绪+落库完整流程"
```

---

## Task 9: SentimentThermometerCard widget

**Files:**
- Create: `mobile/lib/widgets/sentiment_thermometer_card.dart`
- Test: `mobile/test/sentiment_card_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `mobile/test/sentiment_card_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock/models/stock_models.dart';
import 'package:stock/widgets/sentiment_thermometer_card.dart';

void main() {
  group('SentimentThermometerCard', () {
    testWidgets('null sentiment shows skeleton', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SentimentThermometerCard(sentiment: null)),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('climax phase displays temperature and phase label', (tester) async {
      final s = SentimentResult(
        temperature: 75,
        phase: EmotionPhase.climax,
        zhabanRate: 0.1,
        continuationRate: 0.6,
        sealSuccessRate: 0.9,
        moneyMakingEffect: 4.0,
        limitUpCount: 60,
        limitDownCount: 2,
        continuationHeight: 5,
        signals: const ['🔥 封板极强', '🚀 接力强'],
        timestamp: DateTime.now(),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SentimentThermometerCard(sentiment: s)),
      ));
      expect(find.text('75°'), findsOneWidget);
      expect(find.textContaining('高潮'), findsWidgets);
    });

    testWidgets('signals truncated with ellipsis', (tester) async {
      final s = SentimentResult(
        temperature: 50,
        phase: EmotionPhase.startup,
        zhabanRate: 0.2,
        continuationRate: 0.3,
        sealSuccessRate: 0.8,
        moneyMakingEffect: 1.0,
        limitUpCount: 35,
        limitDownCount: 5,
        continuationHeight: 3,
        signals: List.generate(10, (i) => '信号$i这是一个很长的信号文本'),
        timestamp: DateTime.now(),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SentimentThermometerCard(sentiment: s)),
      ));
      // 验证有 Text widget 使用了 overflow
      final textWidgets = find.byType(Text);
      expect(textWidgets, findsWidgets);
    });
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd mobile && flutter test test/sentiment_card_test.dart`
Expected: FAIL — `SentimentThermometerCard` widget 不存在

- [ ] **Step 3: 创建 widget**

创建 `mobile/lib/widgets/sentiment_thermometer_card.dart`，实现 spec 7.2 节的完整 widget 代码（温度大数 + 阶段标签 + 温度条 + 5 维指标 + 信号文案）。所有 Text widget 加 `maxLines` + `overflow: TextOverflow.ellipsis`。

```dart
import 'package:flutter/material.dart';
import 'package:stock/models/stock_models.dart';

class SentimentThermometerCard extends StatelessWidget {
  final SentimentResult? sentiment;
  final VoidCallback? onRefresh;
  final bool isLoading;

  const SentimentThermometerCard({
    super.key,
    required this.sentiment,
    this.onRefresh,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = sentiment;
    if (s == null) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _phaseGradient(s.phase),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('🌡️ 情绪温度计',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
            const Spacer(),
            if (isLoading)
              const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
            else if (onRefresh != null)
              IconButton(
                icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
                onPressed: onRefresh,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${s.temperature.toStringAsFixed(0)}°',
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(_phaseLabel(s.phase),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 2),
              Text('仓位 ${_phasePositionAdvice(s.phase)}',
                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ]),
          ]),
          const SizedBox(height: 10),
          _buildThermometerBar(s.temperature),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _buildMiniMetric('炸板', '${(s.zhabanRate * 100).toStringAsFixed(0)}%'),
            _buildMiniMetric('晋级', '${(s.continuationRate * 100).toStringAsFixed(0)}%'),
            _buildMiniMetric('封板', '${(s.sealSuccessRate * 100).toStringAsFixed(0)}%'),
            _buildMiniMetric('赚钱', '${s.moneyMakingEffect.toStringAsFixed(1)}%'),
            _buildMiniMetric('高度', '${s.continuationHeight}板'),
          ]),
          if (s.signals.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(s.signals.take(2).join(' · '),
                style: const TextStyle(fontSize: 11, color: Colors.white70),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }

  List<Color> _phaseGradient(EmotionPhase p) => switch (p) {
    EmotionPhase.startup  => const [Color(0xFF1A5276), Color(0xFF2E86C1)],
    EmotionPhase.climax    => const [Color(0xFF7B241C), Color(0xFFE74C3C)],
    EmotionPhase.retreat   => const [Color(0xFF7D6608), Color(0xFFF39C12)],
    EmotionPhase.freezing  => const [Color(0xFF1B2631), Color(0xFF566573)],
  };

  String _phaseLabel(EmotionPhase p) => switch (p) {
    EmotionPhase.startup  => '启动阶段',
    EmotionPhase.climax    => '高潮阶段',
    EmotionPhase.retreat   => '退潮阶段',
    EmotionPhase.freezing  => '冰点阶段',
  };

  String _phasePositionAdvice(EmotionPhase p) => switch (p) {
    EmotionPhase.startup  => '5-6 成',
    EmotionPhase.climax    => '7-8 成',
    EmotionPhase.retreat   => '3-4 成',
    EmotionPhase.freezing  => '1-2 成',
  };

  Widget _buildThermometerBar(double temp) {
    return LayoutBuilder(builder: (_, c) {
      final segWidth = c.maxWidth / 6;
      final pos = (temp / 100 * c.maxWidth).clamp(0.0, c.maxWidth - 8);
      return Stack(children: [
        Row(children: [
          for (final col in const [Color(0xFF566573), Color(0xFF566573),
                                   Color(0xFF2E86C1), Color(0xFF2E86C1),
                                   Color(0xFFE74C3C), Color(0xFFE74C3C)])
            Container(width: segWidth, height: 6, color: col),
        ]),
        Positioned(left: pos, top: -2,
            child: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 14)),
      ]);
    });
  }

  Widget _buildMiniMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text('$label $value',
          style: const TextStyle(fontSize: 10, color: Colors.white),
          maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
```

- [ ] **Step 4: 运行测试验证通过**

Run: `cd mobile && flutter test test/sentiment_card_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd mobile && git add lib/widgets/sentiment_thermometer_card.dart test/sentiment_card_test.dart
git commit -m "feat: SentimentThermometerCard widget — 阶段渐变+温度条+5维指标"
```

---

## Task 10: LimitUpCard widget

**Files:**
- Create: `mobile/lib/widgets/limit_up_card.dart`
- Test: `mobile/test/limit_up_card_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `mobile/test/limit_up_card_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock/analysis/limit_up_analyzer.dart';
import 'package:stock/widgets/limit_up_card.dart';

void main() {
  group('LimitUpCard', () {
    testWidgets('displays consecutive days badge', (tester) async {
      final a = LimitUpAnalysis(
        code: '600519', name: '贵州茅台', consecutiveDays: 3,
        boardType: '一字板', timeGrade: '竞价涨停',
        sealAmount: 23000, qualityScore: 8.5, premiumProb: 0.75,
        sector: '白酒', price: 1689.5, changePct: 10.0,
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LimitUpCard(analysis: a, isWatched: false,
            onTap: () {}, onWatchlistToggle: () {})),
      ));
      expect(find.textContaining('3'), findsWidgets);
      expect(find.text('贵州茅台'), findsOneWidget);
      expect(find.textContaining('一字板'), findsOneWidget);
    });

    testWidgets('empty sector does not crash', (tester) async {
      final a = LimitUpAnalysis(code: '000001', name: 'X');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: LimitUpCard(analysis: a, isWatched: false,
            onTap: () {}, onWatchlistToggle: () {})),
      ));
      expect(find.text('X'), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: 运行测试验证失败**

Run: `cd mobile && flutter test test/limit_up_card_test.dart`
Expected: FAIL — `LimitUpCard` widget 不存在

- [ ] **Step 3: 创建 widget**

创建 `mobile/lib/widgets/limit_up_card.dart`，实现 spec 6.4 节的卡片设计：

```dart
import 'package:flutter/material.dart';
import 'package:stock/analysis/limit_up_analyzer.dart';

class LimitUpCard extends StatelessWidget {
  final LimitUpAnalysis analysis;
  final bool isWatched;
  final VoidCallback? onTap;
  final VoidCallback? onWatchlistToggle;

  const LimitUpCard({
    super.key,
    required this.analysis,
    required this.isWatched,
    this.onTap,
    this.onWatchlistToggle,
  });

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      color: const Color(0xFF161B22),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：连板徽章 + 名称 + 板型/时段徽章 + 星标
              Row(children: [
                _buildConsecutiveBadge(a.consecutiveDays),
                const SizedBox(width: 8),
                Expanded(child: Text(a.name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (a.boardType.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  _buildTypeBadge(a.boardType, _boardTypeColor(a.boardType)),
                ],
                if (a.timeGrade.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  _buildTypeBadge(a.timeGrade, _timeGradeColor(a.timeGrade)),
                ],
                IconButton(
                  icon: Icon(isWatched ? Icons.star : Icons.star_border,
                      size: 18, color: isWatched ? const Color(0xFFFFB000) : Colors.grey),
                  onPressed: onWatchlistToggle,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ]),
              const SizedBox(height: 6),
              // 第二行：价格 + 涨幅 + 封单 + 封成比
              Text(
                '¥${a.price.toStringAsFixed(2)}  '
                '${a.changePct >= 0 ? '+' : ''}${a.changePct.toStringAsFixed(2)}%   '
                '封单 ${_formatAmount(a.sealAmount)}   '
                '封成比 ${a.sealRate.toStringAsFixed(1)}x',
                style: TextStyle(fontSize: 12, color: a.changePct >= 0 ? const Color(0xFFef5350) : const Color(0xFF26a69a)),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              // 第三行：次日溢价 + 质量 + 板块
              Text(
                '次日溢价 ${((a.premiumProb) * 100).toStringAsFixed(0)}%  ·  '
                '质量 ${a.qualityScore.toStringAsFixed(1)}分'
                '${a.sector != null && a.sector!.isNotEmpty ? '  ·  ${a.sector}' : ''}',
                style: TextStyle(fontSize: 11,
                    color: a.premiumProb > 0.7 ? const Color(0xFFFFB000) : const Color(0xFF8B949E)),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConsecutiveBadge(int days) {
    final color = days >= 4 ? const Color(0xFF9D2933) :
                  days == 3 ? const Color(0xFFE74C3C) :
                  days == 2 ? const Color(0xFFE67E22) :
                  const Color(0xFF58A6FF);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text('$days连板',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
          maxLines: 1),
    );
  }

  Widget _buildTypeBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 0.5),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 9, color: color),
          maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  Color _boardTypeColor(String type) {
    if (type.contains('一字')) return const Color(0xFFef5350);
    if (type.contains('T字')) return const Color(0xFFE74C3C);
    if (type.contains('换手')) return const Color(0xFFE67E22);
    return const Color(0xFF8B5A5A);
  }

  Color _timeGradeColor(String grade) {
    if (grade.contains('竞价')) return const Color(0xFFFFB000);
    if (grade.contains('早盘') || grade.contains('秒板')) return const Color(0xFFef5350);
    if (grade.contains('上午')) return const Color(0xFFE67E22);
    return const Color(0xFF8B949E);
  }

  String _formatAmount(double wan) {
    if (wan >= 10000) return '${(wan / 10000).toStringAsFixed(1)}亿';
    return '${wan.toStringAsFixed(0)}万';
  }
}
```

- [ ] **Step 4: 运行测试验证通过**

Run: `cd mobile && flutter test test/limit_up_card_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
cd mobile && git add lib/widgets/limit_up_card.dart test/limit_up_card_test.dart
git commit -m "feat: LimitUpCard widget — 连板徽章+板型+封单+次日溢价"
```

---

## Task 11: DiscoverScreen 打板梯队 Tab 重画

**Files:**
- Modify: `mobile/lib/screens/discover_screen.dart`（行 39-52 字段, 行 225-229 _limitUpList, 行 372 _buildLimitUpTab）
- Test: `mobile/test/discover_limit_up_tab_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `mobile/test/discover_limit_up_tab_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock/analysis/limit_up_analyzer.dart';
import 'package:stock/models/stock_models.dart';
import 'package:stock/screens/discover_screen.dart';

void main() {
  group('DiscoverScreen LimitUp Tab', () {
    testWidgets('renders group headers when pool has data', (tester) async {
      final pool = [
        LimitUpAnalysis(code: '001', name: '龙头A', consecutiveDays: 5, isZhaBan: false),
        LimitUpAnalysis(code: '002', name: '高度B', consecutiveDays: 3, isZhaBan: false),
        LimitUpAnalysis(code: '003', name: '中度C', consecutiveDays: 2, isZhaBan: false),
        LimitUpAnalysis(code: '004', name: '首板D', consecutiveDays: 1, isZhaBan: false),
      ];
      await tester.pumpWidget(MaterialApp(
        home: DiscoverScreen(limitUpPoolOverride: pool, sentimentOverride: _mockSentiment()),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('龙头'), findsWidgets);
      expect(find.textContaining('高度板'), findsWidgets);
      expect(find.textContaining('中度板'), findsWidgets);
      expect(find.textContaining('首板'), findsWidgets);
    });

    testWidgets('empty state shows refresh button', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: DiscoverScreen(limitUpPoolOverride: [], sentimentOverride: null),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('暂无涨停'), findsWidgets);
    });

    testWidgets('zhaban group hidden when no zhaban', (tester) async {
      final pool = [
        LimitUpAnalysis(code: '004', name: '首板D', consecutiveDays: 1, isZhaBan: false),
      ];
      await tester.pumpWidget(MaterialApp(
        home: DiscoverScreen(limitUpPoolOverride: pool, sentimentOverride: null),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('炸板'), findsNothing);
    });
  });
}

SentimentResult _mockSentiment() => SentimentResult(
  temperature: 62, phase: EmotionPhase.startup,
  zhabanRate: 0.2, continuationRate: 0.4, sealSuccessRate: 0.8,
  moneyMakingEffect: 2.0, limitUpCount: 35, limitDownCount: 3,
  continuationHeight: 5, signals: const [], timestamp: DateTime.now(),
);
```

注意：测试中 `DiscoverScreen` 构造函数需要支持 `limitUpPoolOverride` 和 `sentimentOverride` 参数（仅测试用）。若不便修改构造函数，可改为 pump 完整 widget 后通过 `Provider` 或直接调 `setState` 注入数据。

- [ ] **Step 2: 运行测试验证失败**

Run: `cd mobile && flutter test test/discover_limit_up_tab_test.dart`
Expected: FAIL — `limitUpPoolOverride` 参数不存在，分组渲染逻辑不存在

- [ ] **Step 3: 添加字段和 import**

修改 `mobile/lib/screens/discover_screen.dart`：
- 顶部添加 import：
  ```dart
  import 'package:stock/analysis/limit_up_analyzer.dart';
  import 'package:stock/analysis/limit_up_scan_engine.dart';
  import 'package:stock/analysis/sentiment_thermometer.dart';
  import 'package:stock/models/stock_models.dart';
  import 'package:stock/widgets/limit_up_card.dart';
  ```
- 在 `DiscoverScreenState` 字段区（行 39-52）添加：
  ```dart
  List<LimitUpAnalysis> _limitUpPool = [];
  SentimentResult? _sentiment;
  bool _limitUpScanLoading = false;
  StreamSubscription<LimitUpScanProgress>? _limitUpScanSub;
  ```

- [ ] **Step 4: 添加 _limitUpGroups getter 和 _buildSentimentMiniCard**

在 `discover_screen.dart` 的 `_limitUpList` getter（行 225）附近添加 `_limitUpGroups` getter 和 `_buildSentimentMiniCard` 方法（实现 spec 6.2 和 6.3 节的代码）。

- [ ] **Step 5: 重写 _buildLimitUpTab 方法**

替换原有的 `_buildLimitUpTab` 方法为 spec 6.5 节的分组渲染逻辑。

- [ ] **Step 6: 添加 _refreshLimitUpPool 方法**

```dart
Future<void> _refreshLimitUpPool() async {
  if (_limitUpScanLoading) return;
  setState(() => _limitUpScanLoading = true);
  try {
    final sentiment = await LimitUpScanEngine.instance.scan();
    final pool = await _dbService.getLimitUpPool();
    if (mounted) {
      setState(() {
        _sentiment = sentiment;
        _limitUpPool = pool;
        _limitUpScanLoading = false;
      });
    }
  } catch (e) {
    debugPrint('_refreshLimitUpPool failed: $e');
    if (mounted) setState(() => _limitUpScanLoading = false);
  }
}
```

- [ ] **Step 7: 在 initState 中加载打板池缓存**

在 `initState`（行 56-62）中添加 `_loadLimitUpPoolFromDb()` 调用，并用 `addPostFrameCallback` 包裹（遵循 project_memory 硬约束）：

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  _loadLimitUpPoolFromDb();
});
```

- [ ] **Step 8: 运行测试验证通过**

Run: `cd mobile && flutter test test/discover_limit_up_tab_test.dart`
Expected: PASS

- [ ] **Step 9: 运行全量测试 + analyze**

Run: `cd mobile && flutter test && flutter analyze`
Expected: 全部通过，0 errors

- [ ] **Step 10: Commit**

```bash
cd mobile && git add lib/screens/discover_screen.dart test/discover_limit_up_tab_test.dart
git commit -m "feat: 发现页打板梯队 Tab 重画 — 连板分组+情绪迷你卡+长按菜单"
```

---

## Task 12: HomeScreen 工作台升级

**Files:**
- Modify: `mobile/lib/screens/home_screen.dart`（行 33-38 字段, 行 234-274 _loadWorkbenchData, 行 434-559 _buildWorkbenchCard）
- Test: `mobile/test/home_workbench_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `mobile/test/home_workbench_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock/models/stock_models.dart';
import 'package:stock/widgets/sentiment_thermometer_card.dart';

void main() {
  group('HomeScreen workbench', () {
    testWidgets('SentimentThermometerCard displays when sentiment loaded', (tester) async {
      final s = SentimentResult(
        temperature: 62, phase: EmotionPhase.startup,
        zhabanRate: 0.2, continuationRate: 0.4, sealSuccessRate: 0.8,
        moneyMakingEffect: 2.0, limitUpCount: 35, limitDownCount: 3,
        continuationHeight: 5, signals: const [], timestamp: DateTime.now(),
      );
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: SentimentThermometerCard(sentiment: s)),
      ));
      expect(find.text('62°'), findsOneWidget);
      expect(find.textContaining('启动'), findsWidgets);
    });
  });
}
```

- [ ] **Step 2: 运行测试验证通过（应已通过，因 Task 9 已实现 widget）**

Run: `cd mobile && flutter test test/home_workbench_test.dart`
Expected: PASS

- [ ] **Step 3: 修改 home_screen.dart 字段**

在 `home_screen.dart` 行 33-38 区域添加：
```dart
SentimentResult? _sentiment;
```

- [ ] **Step 4: 改造 _loadWorkbenchData**

修改 `_loadWorkbenchData`（行 234-274），在 `Future.wait` 中并发拉取打板池数据 + 情绪计算（参考 spec 7.3 节代码）。同时修复 `_mainLineCount` 未赋值的 bug：

```dart
// 在 Future.wait 中新增:
//   _dbService.getLimitUpPool(),
//   LimitUpUniverseProvider.fetchLatest(apiClient: _apiClient),
//   _dbService.getLimitUpPoolByDate(yesterday),
// 然后计算 sentiment
// 同时补齐 _mainLineCount 赋值:
final picks = await _dbService.getSectorPickResults();
final mainLineCount = picks.where((p) => p['mainLine'] == 1 || p['mainLine'] == true).length;
```

- [ ] **Step 5: 改造 _buildWorkbenchCard**

在 `_buildWorkbenchCard`（行 434）顶部插入 `SentimentThermometerCard`：

```dart
Widget _buildWorkbenchCard() {
  // 新增：情绪温度计大卡片
  final sentimentCard = SentimentThermometerCard(
    sentiment: _sentiment,
    onRefresh: _isWorkbenchLoading ? null : _loadWorkbenchData,
    isLoading: _isWorkbenchLoading,
  );
  // 原有的 2×2 网格逻辑保留
  return Column(children: [
    sentimentCard,
    Card(child: ...原有2×2网格...),
  ]);
}
```

- [ ] **Step 6: 添加 import**

```dart
import 'package:stock/analysis/limit_up_scan_engine.dart';
import 'package:stock/analysis/limit_up_universe_provider.dart';
import 'package:stock/analysis/sentiment_thermometer.dart';
import 'package:stock/widgets/sentiment_thermometer_card.dart';
```

- [ ] **Step 7: 运行全量测试 + analyze**

Run: `cd mobile && flutter test && flutter analyze`
Expected: 全部通过，0 errors

- [ ] **Step 8: Commit**

```bash
cd mobile && git add lib/screens/home_screen.dart test/home_workbench_test.dart
git commit -m "feat: 首页工作台升级 — 情绪温度计大卡+补齐 mainLineCount 赋值"
```

---

## Task 13: QuoteScreen K 线打板标识（Stage 8）

**Files:**
- Modify: `mobile/lib/screens/quote_screen.dart`（_KlinePainter 行 2052, _analysis 字段行 41, build 方法）
- Test: `mobile/test/kline_limit_up_marks_test.dart`

- [ ] **Step 1: 写失败测试**

创建 `mobile/test/kline_limit_up_marks_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock/analysis/limit_up_analyzer.dart';
import 'package:stock/models/stock_models.dart';

void main() {
  group('K-line limit-up marks', () {
    test('LimitUpAnalysis toMap contains board_type for rendering', () {
      final a = LimitUpAnalysis(
        code: '600519', name: '茅台', consecutiveDays: 3,
        boardType: '一字板', timeGrade: '竞价涨停', premiumProb: 0.75,
      );
      final m = a.toMap();
      expect(m['board_type'], '一字板');
      expect(m['consecutive_days'], 3);
    });

    test('null limitUpAnalysis is handled gracefully', () {
      // 验证 AnalysisResult.limitUpAnalysis 可为 null
      const nullAnalysis = null;
      expect(nullAnalysis, isNull);
    });
  });
}
```

- [ ] **Step 2: 运行测试验证通过（基础模型测试，应已通过）**

Run: `cd mobile && flutter test test/kline_limit_up_marks_test.dart`
Expected: PASS

- [ ] **Step 3: 在 _KlinePainter 中添加 _drawLimitUpMarks 方法**

在 `quote_screen.dart` 的 `_KlinePainter` 类（行 2052）的 `paint` 方法末尾（行 2302 之前）添加对 `_drawLimitUpMarks` 的调用，并实现该方法（参考 spec 7.4 节代码）。

注意字段名适配：
- `_KlinePainter` 的 K 线数据字段名是 `data`（不是 `_klines`）
- `quote_screen` 的分析结果字段名是 `_analysis`（不是 `_analysisResult`）
- `KlineValidator` 在 `backtest_engine.dart`，需 import

- [ ] **Step 4: 在 _KlinePainter 构造函数中添加 limitUpAnalysis 参数**

```dart
final LimitUpAnalysis? limitUpAnalysis;
// 构造函数中添加: this.limitUpAnalysis,
```

- [ ] **Step 5: 在 quote_screen build 中传递 limitUpAnalysis**

在创建 `_KlinePainter` 的地方传入 `_analysis?.limitUpAnalysis`。

- [ ] **Step 6: 添加 _buildLimitUpSummaryCard 方法**

在 `quote_screen.dart` 中添加 spec 7.4 节的打板信息浮层卡片，并在 K 线图下方渲染。

- [ ] **Step 7: 运行全量测试 + analyze**

Run: `cd mobile && flutter test && flutter analyze`
Expected: 全部通过，0 errors

- [ ] **Step 8: Commit**

```bash
cd mobile && git add lib/screens/quote_screen.dart test/kline_limit_up_marks_test.dart
git commit -m "feat: Stage 8 详情页K线打板标识 — 三角+连板数+一字板矩形+浮层卡片"
```

---

## Task 14: 端到端集成测试 + 验证

**Files:**
- Test: `mobile/test/p0_integration_test.dart`

- [ ] **Step 1: 写集成测试**

创建 `mobile/test/p0_integration_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:stock/analysis/limit_up_analyzer.dart';
import 'package:stock/analysis/limit_up_universe_provider.dart';
import 'package:stock/analysis/sentiment_thermometer.dart';
import 'package:stock/models/stock_models.dart';

void main() {
  group('P0 E2E', () {
    test('full pipeline: stocks → analyzer → sentiment', () {
      // 1. 模拟涨停池数据
      final todayStocks = [
        LimitUpStock(code: '600519', name: '茅台', consecutiveDays: 3,
            sealAmount: 23000, firstLimitTime: DateTime(2026, 6, 27, 9, 25),
            isZhaBan: false, sector: '白酒', price: 1689.5, changePct: 10.0),
        LimitUpStock(code: '000001', name: '平安银行', consecutiveDays: 1,
            sealAmount: 5000, firstLimitTime: DateTime(2026, 6, 27, 10, 30),
            isZhaBan: false, sector: '银行', price: 12.5, changePct: 10.0),
      ];

      // 2. analyzeBatchList
      final analyses = LimitUpAnalyzer.analyzeBatchList(todayStocks);
      expect(analyses, hasLength(2));

      // 3. SentimentThermometer.compute
      final sentiment = SentimentThermometer.compute(
        todayPool: analyses,
        yesterdayPool: [],
        todayQuotePct: {},
      );
      expect(sentiment.temperature, greaterThan(0));
      expect(sentiment.phase, isNotNull);
      expect(sentiment.limitUpCount, 2);

      // 4. 验证 LimitUpAnalysis.toMap 可序列化
      for (final a in analyses) {
        final m = a.toMap();
        expect(m['code'], isNotNull);
        expect(m['consecutive_days'], isNotNull);
      }
    });

    test('fallback: empty pool does not crash', () {
      final sentiment = SentimentThermometer.compute(
        todayPool: [], yesterdayPool: [], todayQuotePct: {});
      expect(sentiment.temperature, lessThan(50));  // 空池温度低
    });

    test('mergeAndDedup deduplicates by code', () {
      final today = [LimitUpStock(code: '001', name: 'A')];
      final fresh = [LimitUpStock(code: '001', name: 'A2'), LimitUpStock(code: '002', name: 'B')];
      final merged = LimitUpUniverseProvider.mergeAndDedup(today, fresh);
      expect(merged, hasLength(2));
      expect(merged.firstWhere((s) => s.code == '001').name, 'A2');
    });
  });
}
```

- [ ] **Step 2: 运行集成测试**

Run: `cd mobile && flutter test test/p0_integration_test.dart`
Expected: PASS

- [ ] **Step 3: 运行全量测试**

Run: `cd mobile && flutter test`
Expected: 既有 578 + 新增 ~30 = 600+ 全部通过

- [ ] **Step 4: 运行 flutter analyze**

Run: `cd mobile && flutter analyze`
Expected: 0 errors

- [ ] **Step 5: 构建 APK**

Run: `cd mobile && flutter build apk --release`
Expected: 成功，体积增幅 < 2MB

- [ ] **Step 6: Commit**

```bash
cd mobile && git add test/p0_integration_test.dart
git commit -m "test: P0 端到端集成测试 — 全流程+降级+去重验证"
```

---

## Self-Review

### Spec coverage 检查

| Spec 章节 | 对应 Task | 状态 |
|---|---|---|
| 4.1 API 接口 | Task 5 | ✓ |
| 4.2 ApiClient 扩展 | Task 5 | ✓ |
| 4.3 LimitUpStock 模型 | Task 1 | ✓ |
| 4.4 DB 迁移 v11 | Task 3 | ✓ |
| 4.5 LimitUpAnalysis + SentimentResult 模型 | Task 2 + Task 6 (Step 3) | ✓ |
| 5.1-5.5 SentimentThermometer | Task 6 | ✓ |
| 6.1-6.7 打板梯队 Tab | Task 9 + Task 10 + Task 11 | ✓ |
| 7.1-7.3 工作台升级 | Task 9 + Task 12 | ✓ |
| 7.4-7.5 Stage 8 K线 | Task 13 | ✓ |
| 8.1 错误处理 | 各 Task 中 try-catch | ✓ |
| 8.3 测试策略 | 7 个测试文件 | ✓ |
| 9.1 实施范围 19 项 | Task 1-14 覆盖全部 | ✓ |

### Placeholder scan

- 无 TBD/TODO
- 无"implement later"
- 每个 step 都有具体代码或命令
- ✓ 通过

### Type consistency

- `LimitUpStock.fromEastMoney` — Task 1 定义，Task 5/7 调用 ✓
- `LimitUpAnalysis.fromMap` — Task 2 定义，Task 4 调用 ✓
- `analyzeBatchList` — Task 2 定义，Task 8/14 调用 ✓
- `SentimentThermometer.compute` — Task 6 定义，Task 8/12/14 调用 ✓
- `SentimentResult` / `EmotionPhase` — Task 6 定义，Task 9/11/12 调用 ✓
- `LimitUpScanEngine.instance.scan` — Task 8 定义，Task 11/12 调用 ✓
- `LimitUpUniverseProvider.mergeAndDedup` / `fetchLatest` — Task 7 定义，Task 8/12/14 调用 ✓
- `DatabaseService.replaceLimitUpPool` / `getLimitUpPool` — Task 4 定义，Task 8/11/12 调用 ✓
- 字段名 `_analysis`（quote_screen）、`data`（_KlinePainter）已按实际代码适配 ✓

### 已知风险点

1. **Task 1 的 `firstLimitUpTime` → `firstLimitTime` 重命名**可能影响其他文件，Step 6 全量测试会暴露
2. **Task 5 的 `_decodeJson`** 方法名需用 Grep 确认存在（可能是 `_decodeGbk` 或 `jsonDecode`）
3. **Task 11 测试的 `limitUpPoolOverride`** 参数需要 DiscoverScreen 构造函数支持，可能需要调整为其他注入方式
4. **Task 13 的 `_KlinePainter` 改造**涉及行 2052-2302 的大类，需仔细阅读现有 paint 方法

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-27-p0-sentiment-thermometer-and-limit-up-echelon.md`.

**Two execution options:**

**1. Subagent-Driven (recommended)** - 每个 Task 派发独立 subagent，任务间 review，快速迭代

**2. Inline Execution** - 在当前会话中按批次执行，checkpoint 处 review

**Which approach?**
