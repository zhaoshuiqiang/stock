# P0 — 短线情绪温度计 + 打板梯队激活 设计规格

- **日期**：2026-06-27
- **状态**：待审核
- **作者**：Brainstorming Session
- **关联项目**：stock (Flutter 短线工作台 v2.33.0)
- **优先级**：P0（5 个子项目中的第一个）

---

## 一、背景与目标

### 1.1 背景

v2.33.0 短线工作台升级已激活三大孤儿模块 + 持仓管理 + 4-Tab 发现页，但短线核心数据仍有重大缺口：

- **打板梯队 Tab 名不副实**：仅按涨幅 ≥9.5% 过滤 `ExploreResult`，无连板数 / 板型 / 封板时间 / 封单强度
- **分时低吸 Tab 是伪分时**：复用日 K 级数据筛选
- **市场择时仅 5 维**：无炸板率 / 连板晋级率 / 赚钱效应 / 情绪周期阶段
- **`LimitUpAnalyzer.analyzeSingle/analyzeBatch` 是 dead code**：完整的连板 / 板型 / 首封时间 / 封单 / 次日溢价算法已实现但 0 调用方
- **`AnalysisResult.limitUpAnalysis` 字段是孤儿**：详情页 K 线未渲染（Stage 8 延后）

### 1.2 目标

激活 dead code，补齐短线核心数据，从用户视角和专业投资者视角双重提升：

1. 激活 `LimitUpAnalyzer.analyzeBatch`，接入真实涨停板数据
2. 新建 `SentimentThermometer` 引擎，输出 5 维情绪指标 + 情绪周期阶段
3. 重画发现页"打板梯队"Tab，按连板梯队分组展示
4. 重画首页工作台，新增情绪温度计大卡片
5. 顺手做 Stage 8：详情页 K 线打板标识

### 1.3 非目标

- P1 真分时低吸引擎（IntradayScanEngine）— 独立 spec
- P2 持仓风控升级 — 独立 spec
- P3 择时历史回看 + 复盘留档 — 独立 spec
- P4 龙虎榜 / 资金流分时 — 独立 spec

---

## 二、子项目分解（5 个，按优先级）

| 优先级 | 子项目 | 依赖 | 状态 |
|---|---|---|---|
| **P0** | 短线情绪温度计 + 打板梯队激活 | 无 | 本 spec |
| P1 | 真分时低吸引擎 (IntradayScanEngine) | P0 扫描池基础设施 | 待启动 |
| P2 | 持仓风控升级 + 独立持仓屏幕 | 独立可并行 | 待启动 |
| P3 | 择时历史回看 + 复盘留档 | P0 落盘数据 | 待启动 |
| P4 | 龙虎榜 + 资金流分时 | 外部 API | 待启动 |

---

## 三、整体架构

### 3.1 新增 / 修改模块清单

```
mobile/lib/
├── api/
│   └── api_client.dart                          [扩展] +getLimitUpBoard() +getYesterdayLimitUpPool()
├── analysis/
│   ├── limit_up_universe_provider.dart          [新增] 涨停池数据采集器
│   ├── limit_up_analyzer.dart                   [激活] analyzeBatch 从 dead code 变为活路径
│   ├── sentiment_thermometer.dart               [新增] 情绪温度计引擎（5维指标+周期阶段）
│   ├── limit_up_scan_engine.dart                [新增] extends BaseAnalysisEngine
│   └── base_analysis_engine.dart                [复用] 提供进度流 / 单例模式
├── models/
│   └── stock_models.dart                        [扩展] +LimitUpStock +SentimentResult +EmotionPhase
├── storage/
│   └── database_service.dart                    [迁移] v10→v11，新建 limit_up_pool 表
├── screens/
│   ├── discover_screen.dart                     [重画] 打板梯队 Tab 分组卡片
│   ├── home_screen.dart                         [扩展] 工作台 1大卡+2×2 网格
│   └── quote_screen.dart                        [扩展] Stage 8 K线打板标识
└── widgets/
    ├── limit_up_card.dart                       [新增] 打板梯队卡片
    ├── sentiment_thermometer_card.dart          [新增] 情绪温度计大卡片
    └── (quote_screen内 _KlinePainter)            [扩展] K线打板标识
```

### 3.2 数据流

`LimitUpScanEngine` 是协调器，封装"API 拉取 → 分析 → 情绪计算 → 落库"完整流程，对外暴露 `scan()` 入口和 `progressStream`：

```
LimitUpScanEngine.scan()  ←─ DiscoverScreen._refreshLimitUpPool / HomeScreen._loadWorkbenchData
  │
  ├─ ApiClient.getLimitUpBoard()             ─┐
  ├─ ApiClient.getYesterdayLimitUpPool()     ─┤  并发拉取
  ├─ ApiClient.getBatchRealtimeQuotes()      ─┘  补充 price/changePct/volumeRatio
  │
  ├─ LimitUpUniverseProvider.fetch()         合并去重 + 字段补全
  │     ↓
  ├─ LimitUpAnalyzer.analyzeBatch()          激活 dead code
  │     ↓
  │  List<LimitUpAnalysis> (consecutiveDays/boardType/sealRate/premiumProb)
  │     ↓
  ├─ SentimentThermometer.compute()          纯函数计算
  │     ↓
  │  SentimentResult (5维指标 + emotionPhase)
  │     ↓
  ├─ DatabaseService.replaceLimitUpPool()    落库 limit_up_pool 表
  │
  └─ progressStream 广播完成
        ↓
  DiscoverScreen._limitUpGroups (按连板数分组) → Tab 1 渲染
  HomeScreen._sentiment → 工作台情绪温度计卡片
```

注：`HomeScreen._loadWorkbenchData` 也可直接读取 DB 缓存（`getLimitUpPool` + `getLimitUpPoolByDate`）而不调 `scan()`，避免重复请求；仅在数据为空或用户主动刷新时才触发 `scan()`。

### 3.3 关键架构决策

1. **新建独立 `LimitUpScanEngine`** 而非复用 `ExploreEngine`：避免 ExploreEngine 扫描逻辑被污染，扫描频率独立（打板数据需要盘中实时刷新，与日 K 扫描解耦）
2. **`LimitUpScanEngine` 与 `ExploreEngine` 并行运行**：发现页 Tab 1 由 `LimitUpScanEngine` 供数，Tab 3/4 继续由 `ExploreEngine` 供数
3. **`SentimentThermometer` 是纯函数引擎**（无状态、无 IO），输入 `List<LimitUpAnalysis> + MarketSentiment + 前一交易日 SentimentResult`，输出 `SentimentResult`，便于单测
4. **打板数据全量入库** `limit_up_pool` 表：支持跨日查询（情绪周期曲线需要历史），且避免重复 API 调用

---

## 四、数据层设计

### 4.1 API 接口（已验证字段映射）

**接口 1：当日涨停板池**

```
GET https://push2ex.eastmoney.com/getTopicZTPool
  ?ut=7eea3edcaed734bea9cbfc24409ed989
  &dpt=wz.ztzt
  &Pageindex=0
  &Pagesize=500
  &sort=fbt:asc
  &date=YYYYMMDD
  &_={timestampMs}

Response:
{
  "data": {
    "pool": [
      {
        "n":     "贵州茅台",        // 股票名称
        "c":     "600519",          // 股票代码
        "ltsz":  21234567890,       // 流通市值（元）
        "tshare":26543210000,       // 总市值（元）
        "hs":    1.23,              // 换手率（%）
        "fund":  230000000,         // 封板资金（元）
        "fbt":   92500,             // 首次封板时间（整数 92500 = 09:25:00）
        "lbt":   145900,            // 最后封板时间
        "zbc":   0,                 // 炸板次数（0=未炸板）
        "zttj":  {"days":3,"ct":3}, // 涨停统计：连板3天/最近3日涨停3次
        "lbc":   3,                 // 连板数
        "hybk":  "白酒"             // 所属行业
      },
      ...
    ]
  }
}
```

**接口 2：昨日涨停股池**（用于计算赚钱效应）

```
GET https://push2ex.eastmoney.com/getTopicZTPool
  ?...&date={yesterdayYYYYMMDD}&sort=fbt:asc
  // 字段同上，额外需要 type=zrzt（昨日涨停）参数
```

注：实际请求时需带上 `Referer: https://quote.eastmoney.com/ztb/detail` 头部，否则可能被拒。

### 4.2 ApiClient 扩展（api_client.dart）

```dart
/// 当日涨停板池
/// 数据源：东方财富 push2ex.eastmoney.com/getTopicZTPool
/// 返回 LimitUpStock 列表，含连板数/首封时间/封单/换手/炸板标记
Future<List<LimitUpStock>> getLimitUpBoard({
  DateTime? date,
  int pageSize = 500,
}) async {
  final dateStr = (date ?? DateTime.now()).toLocal4DigitDate();  // YYYYMMDD
  final url = 'https://push2ex.eastmoney.com/getTopicZTPool'
      '?ut=7eea3edcaed734bea9cbfc24409ed989'
      '&dpt=wz.ztzt'
      '&Pageindex=0'
      '&Pagesize=$pageSize'
      '&sort=fbt:asc'
      '&date=$dateStr'
      '&_=${DateTime.now().millisecondsSinceEpoch}';

  // 复用现有 _httpGet + _httpGetFallback 重试机制
  final json = await _httpGet(url, headers: {
    'Referer': 'https://quote.eastmoney.com/ztb/detail',
    'User-Agent': _kMobileUA,
  });
  final pool = json['data']?['pool'] as List?;
  if (pool == null) return [];
  return pool.map((e) => LimitUpStock.fromEastMoney(e as Map<String, dynamic>)).toList();
}

/// 昨日涨停股池（用于赚钱效应计算）
Future<List<LimitUpStock>> getYesterdayLimitUpPool() async {
  final yesterday = DateTime.now().subtract(const Duration(days: 1));
  return getLimitUpBoard(date: yesterday);
}
```

### 4.3 LimitUpStock 模型（stock_models.dart 新增）

```dart
class LimitUpStock {
  final String code;              // 6位代码
  final String name;
  final double price;             // 当前价（从实时行情补充，东财涨停池无）
  final double changePct;         // 涨跌幅（同上）
  final double limitUpPrice;      // 涨停价
  final DateTime? firstLimitTime; // 首封时间
  final DateTime? lastLimitTime;  // 最后封板时间
  final int consecutiveDays;      // 连板数（东财 lbc 字段）
  final double sealAmount;        // 封单金额（万元，东财 fund 字段 / 10000）
  final double volumeRatio;       // 量比（需另调行情接口补充）
  final double turnoverRate;      // 换手率（东财 hs 字段）
  final bool isZhaBan;            // 是否炸板（zbc > 0）
  final int zhabanCount;          // 炸板次数
  final String? sector;           // 所属行业（东财 hybk 字段）
  final double sealRatio;         // 封成比 = 封单/成交额（需计算）
  final double totalValue;        // 总市值
  final double circulationValue;  // 流通市值

  /// 从东方财富 pool 元素构造
  factory LimitUpStock.fromEastMoney(Map<String, dynamic> json) {
    return LimitUpStock(
      code: (json['c'] ?? '').toString().padLeft(6, '0'),
      name: (json['n'] ?? '').toString(),
      consecutiveDays: (json['lbc'] ?? 1) as int,
      firstLimitTime: _parseEastMoneyTime(json['fbt']),
      lastLimitTime: _parseEastMoneyTime(json['lbt']),
      sealAmount: ((json['fund'] ?? 0) as num).toDouble() / 10000,  // 元→万元
      turnoverRate: ((json['hs'] ?? 0) as num).toDouble(),
      isZhaBan: ((json['zbc'] ?? 0) as int) > 0,
      zhabanCount: (json['zbc'] ?? 0) as int,
      sector: json['hybk'] as String?,
      totalValue: ((json['tshare'] ?? 0) as num).toDouble(),
      circulationValue: ((json['ltsz'] ?? 0) as num).toDouble(),
      // price/changePct/volumeRatio/sealRatio/limitUpPrice 由 LimitUpUniverseProvider 后续补充
      price: 0, changePct: 0, volumeRatio: 0, sealRatio: 0, limitUpPrice: 0,
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

### 4.4 数据库迁移 v10 → v11

新建 `limit_up_pool` 表：

```sql
CREATE TABLE limit_up_pool (
  code              TEXT    NOT NULL,
  name              TEXT    NOT NULL,
  trade_date        TEXT    NOT NULL,              -- 'YYYY-MM-DD'
  limit_up_price    REAL    NOT NULL DEFAULT 0,
  first_limit_time  INTEGER,                       -- 分钟级时间戳
  last_limit_time   INTEGER,
  consecutive_days  INTEGER NOT NULL DEFAULT 1,
  board_type        TEXT    NOT NULL DEFAULT '',   -- 一字板/T字板/换手板/烂板回封
  seal_amount       REAL    NOT NULL DEFAULT 0,    -- 封单（万元）
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
);
CREATE INDEX idx_limit_up_pool_date ON limit_up_pool(trade_date);
CREATE INDEX idx_limit_up_pool_consec ON limit_up_pool(trade_date, consecutive_days DESC);
```

**迁移逻辑**（database_service.dart `onUpgrade`）：

```dart
if (oldVersion < 11) {
  await db.execute('''CREATE TABLE limit_up_pool (...)''');
  await db.execute('CREATE INDEX idx_limit_up_pool_date ON limit_up_pool(trade_date)');
  await db.execute('CREATE INDEX idx_limit_up_pool_consec ON limit_up_pool(trade_date, consecutive_days DESC)');
  debugPrint('[DB] v10→v11: created limit_up_pool table');
}
```

**CRUD 方法**：

```dart
Future<void> replaceLimitUpPool(List<LimitUpAnalysis> analyses, String tradeDate);
Future<List<LimitUpAnalysis>> getLimitUpPool({String? tradeDate});
Future<List<LimitUpAnalysis>> getLimitUpPoolByDate(String tradeDate);
Future<List<String>> getLimitUpDates({int limit = 30});  // 历史日期列表
```

**遵循 sqflite 只读约束**：所有 `db.query()` 返回的 list 在 sort 前必须 `List.from()` 创建可变副本（沿用 v2.33 修复的 read-only bug 模式）。

### 4.5 模型新增汇总

```dart
class LimitUpAnalysis {              // 升级现有 LimitUpAnalysis 类
  final String code, name;
  final int consecutiveDays;
  final String boardType;            // 一字板/T字板/换手板/烂板回封
  final String timeGrade;            // 竞价涨停/早盘秒板/上午封板/...
  final double qualityScore;         // 0-10
  final double? premiumProb;         // 0-1，次日溢价概率
  final double sealRatio;            // 封成比
  final double sealAmount;           // 封单金额（万元）
  final DateTime? firstLimitTime;
  final bool isZhaBan;
  final int zhabanCount;
  final String? sector;
  final double price;
  final double changePct;
  // fromMap/toMap 兼容 SQLite 列名
}

class SentimentResult {
  final double temperature;          // 0-100
  final EmotionPhase phase;          // 启动/高潮/退潮/冰点
  final double zhabanRate;           // 炸板率 [0,1]
  final double continuationRate;     // 连板晋级率 [0,1]
  final double sealSuccessRate;      // 涨停封板成功率 [0,1]
  final double moneyMakingEffect;    // 赚钱效应（%）
  final int limitUpCount;
  final int limitDownCount;
  final int continuationHeight;      // 最高连板数
  final List<String> signals;
  final DateTime timestamp;
}

enum EmotionPhase { startup, climax, retreat, freezing }
```

---

## 五、SentimentThermometer 引擎

### 5.1 设计原则

- **纯函数引擎**（无状态、无 IO）
- 输入：`List<LimitUpAnalysis> todayPool + List<LimitUpAnalysis> yesterdayPool + Map<String,double> todayQuotePct + MarketSentiment + EmotionPhase? yesterdayPhase`
- 输出：`SentimentResult`
- 零外部依赖，便于单测
- 所有阈值作为 `static const`，避免魔法数字

### 5.2 五维情绪指标算法

```dart
class SentimentThermometer {
  // === 维度 1: 炸板率 ===
  // 炸板率 = 炸板数 / (涨停数 + 炸板数)
  static double _computeZhabanRate(List<LimitUpAnalysis> pool) {
    if (pool.isEmpty) return 0.5;
    final zhaban = pool.where((a) => a.isZhaBan).length;
    return zhaban / pool.length;
  }

  // === 维度 2: 连板晋级率 ===
  // 1板→2板 的晋级率（最具代表性）
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
  // 修正：弱封板（封单<1000万）按 0.2 系数打折
  static double _computeSealSuccessRate(List<LimitUpAnalysis> pool) {
    if (pool.isEmpty) return 0.5;
    final sealed = pool.where((a) => !a.isZhaBan).length;
    final rawRate = sealed / pool.length;
    final weakSealCount = pool.where((a) =>
        !a.isZhaBan && a.sealAmount < 1000).length;
    final penalty = weakSealCount / pool.length * 0.2;
    return (rawRate - penalty).clamp(0.0, 1.0);
  }

  // === 维度 4: 赚钱效应（昨日涨停今日表现均值）===
  static double _computeMoneyMakingEffect(
    List<LimitUpAnalysis> yesterdayPool,
    Map<String, double> todayQuotePct,
  ) {
    if (yesterdayPool.isEmpty) return 0.0;
    final pcts = yesterdayPool
        .map((a) => todayQuotePct[a.code] ?? 0.0)
        .toList();
    return pcts.reduce((a, b) => a + b) / pcts.length;
  }

  // === 维度 5: 连板高度 ===
  static int _computeContinuationHeight(List<LimitUpAnalysis> pool) {
    return pool.fold(1, (max, a) => a.consecutiveDays > max ? a.consecutiveDays : max);
  }
}
```

### 5.3 综合情绪温度（0-100）

```dart
static double _computeTemperature({
  required double zhabanRate,
  required double continuationRate,
  required double sealSuccessRate,
  required double moneyMakingEffect,
  required int continuationHeight,
}) {
  // 归一化到 [0, 1]
  final zhabanScore = 1.0 - zhabanRate;                                    // 反向
  final contScore = continuationRate.clamp(0.0, 1.0);
  final sealScore = sealSuccessRate.clamp(0.0, 1.0);
  final moneyScore = ((moneyMakingEffect + 5) / 10).clamp(0.0, 1.0);       // [-5,5]→[0,1]
  final heightScore = (continuationHeight / 7).clamp(0.0, 1.0);

  // 权重：赚钱效应(0.30) > 连板晋级率(0.25) > 炸板率(0.20) > 封板成功率(0.15) > 连板高度(0.10)
  final temp = zhabanScore * 20 + contScore * 25 + sealScore * 15
             + moneyScore * 30 + heightScore * 10;
  return temp.clamp(0.0, 100.0);
}
```

**权重设计依据**：
- 赚钱效应权重最高（0.30）：游资短线"昨日打板今日盈亏"是最直接的赚钱/亏钱信号
- 连板晋级率次之（0.25）：决定接力意愿，是情绪延续性的核心指标
- 炸板率（0.20）：衡量封板意愿，反向指标
- 封板成功率（0.15）：与炸板率部分重叠，权重较低
- 连板高度（0.10）：辅助指标，避免单一龙头股拉高分数

### 5.4 情绪周期阶段判定（状态机 + 规则引擎混合）

```dart
static EmotionPhase _inferPhase({
  required double temperature,
  required int limitUpCount,
  required int continuationHeight,
  required double continuationRate,
  required EmotionPhase? yesterdayPhase,
}) {
  // 启动：涨停数 ≥30，连板高度 ≤3，温度 30-55
  if (limitUpCount >= 30 && continuationHeight <= 3 &&
      temperature >= 30 && temperature < 55) {
    return EmotionPhase.startup;
  }

  // 高潮：涨停数 ≥50，连板高度 ≥4，温度 ≥60
  if (limitUpCount >= 50 && continuationHeight >= 4 && temperature >= 60) {
    return EmotionPhase.climax;
  }

  // 退潮：温度 40-60 且接力率<0.3 或昨日为高潮
  if (temperature >= 40 && temperature < 60 &&
      (continuationRate < 0.3 || yesterdayPhase == EmotionPhase.climax)) {
    return EmotionPhase.retreat;
  }

  // 冰点：涨停数 <20，连板高度 ≤2，温度 <30
  if (limitUpCount < 20 && continuationHeight <= 2 && temperature < 30) {
    return EmotionPhase.freezing;
  }

  // 兜底：基于昨日阶段的状态转移
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
```

### 5.5 信号文案生成

```dart
static List<String> _generateSignals(SentimentResult r) {
  return [
    if (r.zhabanRate >= 0.7) '⚠️ 炸板潮：封板意愿极弱，打板胜率低',
    if (r.zhabanRate < 0.15) '🔥 封板极强：打板情绪高涨',
    if (r.continuationRate > 0.5) '🚀 接力强：连板晋级率高',
    if (r.continuationRate < 0.1) '❄️ 接力冰点：避免追高',
    if (r.moneyMakingEffect > 3) '💰 赚钱效应强：昨日打板今日盈利',
    if (r.moneyMakingEffect < -3) '💸 亏钱效应：昨日打板今日亏损',
    if (r.continuationHeight >= 5) '👑 龙头${r.continuationHeight}板：高度突破',
    if (r.limitUpCount >= 80) '🌊 涨停潮：${r.limitUpCount}家涨停',
    if (r.limitUpCount < 15) '🧊 涨停稀少：${r.limitUpCount}家',
  ];
}
```

### 5.6 阶段-仓位建议映射

| 阶段 | 仓位建议 | 操作策略 |
|---|---|---|
| 启动 | 5-6 成 | 跟随首板/2板，避免追高 |
| 高潮 | 7-8 成 | 龙头接力，控制单票仓位 |
| 退潮 | 3-4 成 | 减仓兑现，避免新打板 |
| 冰点 | 1-2 成或空仓 | 观望为主，等待启动信号 |

与现有 `MarketTiming.getPositionAdjustment()` 协同：择时引擎输出整体仓位，情绪温度计输出阶段建议，**两者取较低值（保守优先）**。

---

## 六、打板梯队 Tab UI 重画

### 6.1 重画前后对比

| 维度 | 现状 | 重画后 |
|---|---|---|
| 数据源 | `_exploreResults` 涨幅过滤 | `limit_up_pool` 表（完整打板数据） |
| 视图 | 平铺列表，按涨幅降序 | 按连板梯队分组（龙头 / 高度板 / 中度板 / 首板 / 炸板） |
| 卡片信息 | 名称+价格+涨幅+评分 | + 连板数徽章 + 板型徽章 + 首封时间 + 封单 + 次日溢价概率 |
| 顶部信息 | 仅"X只"计数 | 情绪温度计迷你卡（温度+阶段+5维指标） |
| 交互 | 点击跳详情页 | + 长按弹出操作菜单（加自选/加持仓/查看板块/打板预警） |

### 6.2 分组数据结构

```dart
class _LimitUpGroup {
  final String title;        // '👑 龙头'
  final String subtitle;     // '≥4连板'
  final Color accentColor;
  final List<LimitUpAnalysis> items;
}

List<_LimitUpGroup> get _limitUpGroups {
  final pool = _limitUpPool;
  if (pool.isEmpty) return [];

  return [
    _LimitUpGroup(
      title: '👑 龙头',
      subtitle: '≥4连板',
      accentColor: const Color(0xFF9D2933),
      items: pool.where((a) => a.consecutiveDays >= 4).toList()
        ..sort((a, b) => b.consecutiveDays.compareTo(a.consecutiveDays)),
    ),
    _LimitUpGroup(
      title: '🔥 高度板',
      subtitle: '3连板',
      accentColor: const Color(0xFFE74C3C),
      items: pool.where((a) => a.consecutiveDays == 3).toList()
        ..sort((a, b) => b.sealAmount.compareTo(a.sealAmount)),
    ),
    _LimitUpGroup(
      title: '⚡ 中度板',
      subtitle: '2连板',
      accentColor: const Color(0xFFE67E22),
      items: pool.where((a) => a.consecutiveDays == 2).toList()
        ..sort((a, b) => b.sealAmount.compareTo(a.sealAmount)),
    ),
    _LimitUpGroup(
      title: '🌱 首板',
      subtitle: '今日首封',
      accentColor: const Color(0xFF58A6FF),
      items: pool.where((a) => a.consecutiveDays == 1 && !a.isZhaBan).toList()
        ..sort((a, b) {
          // 首封时间早的排前（早盘秒板优于尾盘偷鸡）
          final aT = a.firstLimitTime?.millisecondsSinceEpoch ?? 0;
          final bT = b.firstLimitTime?.millisecondsSinceEpoch ?? 0;
          return aT.compareTo(bT);
        }),
    ),
    if (pool.any((a) => a.isZhaBan))
      _LimitUpGroup(
        title: '💥 炸板',
        subtitle: '曾封后开',
        accentColor: const Color(0xFF8B5A5A),
        items: pool.where((a) => a.isZhaBan).toList()
          ..sort((a, b) => b.sealAmount.compareTo(a.sealAmount)),
      ),
  ].where((g) => g.items.isNotEmpty).toList();
}
```

### 6.3 Tab 1 顶部：情绪温度计迷你卡

```dart
Widget _buildSentimentMiniCard() {
  final s = _sentiment;
  if (s == null) return const SizedBox.shrink();

  return Container(
    margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF161B22),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFF30363D)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _buildPhaseChip(s.phase),
          const SizedBox(width: 8),
          Text('温度 ${s.temperature.toStringAsFixed(0)}°',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          const Spacer(),
          Text('涨停 ${s.limitUpCount} · 跌停 ${s.limitDownCount}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF8B949E))),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: [
          _buildMetricChip('炸板率', '${(s.zhabanRate * 100).toStringAsFixed(0)}%',
              s.zhabanRate < 0.15 ? const Color(0xFF2ECC71) : (s.zhabanRate > 0.5 ? const Color(0xFFE74C3C) : const Color(0xFFFFB000))),
          _buildMetricChip('晋级率', '${(s.continuationRate * 100).toStringAsFixed(0)}%',
              s.continuationRate > 0.3 ? const Color(0xFF2ECC71) : const Color(0xFFFFB000)),
          _buildMetricChip('封板成功率', '${(s.sealSuccessRate * 100).toStringAsFixed(0)}%',
              s.sealSuccessRate > 0.7 ? const Color(0xFF2ECC71) : const Color(0xFFFFB000)),
          _buildMetricChip('赚钱效应', '${s.moneyMakingEffect.toStringAsFixed(1)}%',
              s.moneyMakingEffect > 1 ? const Color(0xFF2ECC71) : (s.moneyMakingEffect < -1 ? const Color(0xFFE74C3C) : const Color(0xFFFFB000))),
          _buildMetricChip('连板高度', '${s.continuationHeight}',
              s.continuationHeight >= 4 ? const Color(0xFF2ECC71) : const Color(0xFFFFB000)),
        ]),
      ],
    ),
  );
}
```

### 6.4 打板卡片设计（新增 `widgets/limit_up_card.dart`）

```
┌─────────────────────────────────────────────────────────────┐
│ [3连板] 贵州茅台          [一字板] [早盘秒板]      ★     │
│ 600519                                                     │
│                                                            │
│ ¥1689.50  +10.00%   封单 2.3亿   封成比 8.5x             │
│                                                            │
│ 次日溢价概率 75%  ·  质量 8.5分  ·  白酒板块              │
└─────────────────────────────────────────────────────────────┘
```

- **左侧徽章**：连板数（紫金渐变，3+板放大字号）
- **板型徽章**：一字板（红填充）/ T字板（红描边）/ 换手板（橙）/ 烂板回封（灰）
- **时段徽章**：竞价涨停（金）/ 早盘秒板（红）/ 上午封板（橙）/ 尾盘偷鸡（灰）
- **封单/封成比**：核心打板指标
- **次日溢价概率**：LimitUpAnalyzer 输出，>70% 高亮金色
- **右侧星标**：加入自选

### 6.5 渲染结构

```dart
Widget _buildLimitUpTab() {
  if (_limitUpScanLoading) return _buildLoadingIndicator();
  if (_limitUpPool.isEmpty) return _buildEmptyState(
    text: '今日暂无涨停标的',
    actionText: '刷新打板池',
    onAction: _refreshLimitUpPool,
  );

  return ListView(
    children: [
      _buildSentimentMiniCard(),
      const SizedBox(height: 4),
      for (final group in _limitUpGroups) ...[
        _buildGroupHeader(group),
        for (final item in group.items)
          LimitUpCard(
            analysis: item,
            isWatched: _watchlistCodes.contains(item.code),
            onTap: () => _navigateToQuote(item.code, item.name),
            onWatchlistToggle: () => _toggleWatchlistByCode(item.code, item.name),
          ),
        const SizedBox(height: 8),
      ],
    ],
  );
}
```

### 6.6 长按操作菜单

```dart
showModalBottomSheet(
  context: context,
  builder: (_) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(leading: const Icon(Icons.star), title: const Text('加入自选'),
            onTap: () => _toggleWatchlistByCode(code, name)),
        ListTile(leading: const Icon(Icons.work), title: const Text('加入持仓'),
            onTap: () => _showPositionDialog(code, name)),
        ListTile(leading: const Icon(Icons.layers), title: const Text('查看所属板块'),
            onTap: () => _navigateToSector(sectorCode)),
        ListTile(leading: const Icon(Icons.notifications), title: const Text('设置打板预警'),
            onTap: () => _addLimitUpAlert(code, name)),
      ],
    ),
  ),
);
```

### 6.7 配色常量

```dart
const _kDragonColor   = 0xFF9D2933;  // 龙头金紫
const _kHeightColor   = 0xFFE74C3C;  // 高度板红
const _kMidColor      = 0xFFE67E22;  // 中度板橙
const _kFirstColor    = 0xFF58A6FF;  // 首板蓝
const _kZhabanColor   = 0xFF8B5A5A;  // 炸板灰红
const _kGoodColor     = 0xFF2ECC71;  // 良性绿
const _kBadColor      = 0xFFE74C3C;  // 风险红
const _kWarnColor     = 0xFFFFB000;  // 警告金
```

---

## 七、工作台 UI 升级 + Stage 8 K 线打板标识

### 7.1 工作台布局变更：2×2 → 1 大卡 + 2×2 网格

```
┌─────────────────────────────────────────────────┐
│ 🌡️ 情绪温度计                            刷新  │
│                                                 │
│  ╔═══════════╗  启动阶段                        │
│  ║   62°     ║  仓位建议 5-6 成                 │
│  ╚═══════════╝  接力强 · 赚钱效应+2.3%          │
│                                                 │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ 情绪温度条 │
│  冰点 ●─────●─────●─────●─────●─────● 高潮     │
│              ▲ 当前                              │
│                                                 │
│  信号：🔥 封板极强 · 🚀 接力强 · 💰 赚钱效应强  │
└─────────────────────────────────────────────────┘

┌──────────────┐ ┌──────────────┐
│ 📊 市场择时  │ │ 🎯 主线板块  │
│ 偏多仓位     │ │ 3 个         │
└──────────────┘ └──────────────┘
┌──────────────┐ ┌──────────────┐
│ 🔥 涨停梯队  │ │ ⚡ 分时低吸  │
│ 32 家        │ │ 8 只         │
└──────────────┘ └──────────────┘
```

### 7.2 情绪温度计大卡（新增 `widgets/sentiment_thermometer_card.dart`）

关键实现要点：

```dart
class SentimentThermometerCard extends StatelessWidget {
  final SentimentResult? sentiment;
  final VoidCallback? onRefresh;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final s = sentiment;
    if (s == null) return _buildSkeleton();

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
          // 标题行
          Row(children: [
            const Text('🌡️ 情绪温度计',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
            const Spacer(),
            if (isLoading)
              const SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
            else
              IconButton(icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
                  onPressed: onRefresh),
          ]),
          const SizedBox(height: 10),

          // 温度大数 + 阶段标签
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${s.temperature.toStringAsFixed(0)}°',
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              _buildPhaseLabel(s.phase),
              const SizedBox(height: 2),
              Text('仓位 ${_phasePositionAdvice(s.phase)}',
                  style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ]),
          ]),
          const SizedBox(height: 10),

          _buildThermometerBar(s.temperature),
          const SizedBox(height: 8),

          // 5 维指标横排
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

  // 阶段渐变色
  List<Color> _phaseGradient(EmotionPhase p) => switch (p) {
    EmotionPhase.startup  => const [Color(0xFF1A5276), Color(0xFF2E86C1)],
    EmotionPhase.climax    => const [Color(0xFF7B241C), Color(0xFFE74C3C)],
    EmotionPhase.retreat   => const [Color(0xFF7D6608), Color(0xFFF39C12)],
    EmotionPhase.freezing  => const [Color(0xFF1B2631), Color(0xFF5665733)],
  };

  // 温度条
  Widget _buildThermometerBar(double temp) {
    return LayoutBuilder(builder: (_, c) {
      final segWidth = c.maxWidth / 6;
      final pos = (temp / 100 * c.maxWidth).clamp(0.0, c.maxWidth - 8);
      return Stack(children: [
        Row(children: [
          for (final col in const [Color(0xFF5665733), Color(0xFF5665733),
                                   Color(0xFF2E86C1), Color(0xFF2E86C1),
                                   Color(0xFFE74C3C), Color(0xFFE74C3C)])
            Container(width: segWidth, height: 6, color: col),
        ]),
        Positioned(left: pos, top: -2,
            child: const Icon(Icons.arrow_drop_down, color: Colors.white, size: 14)),
      ]);
    });
  }
}
```

### 7.3 工作台数据加载改造

```dart
// home_screen.dart _loadWorkbenchData() 改造
Future<void> _loadWorkbenchData() async {
  setState(() => _workbenchLoading = true);
  try {
    final results = await Future.wait([
      MarketTiming.fetchTiming(),
      DatabaseService.instance.getExploreResults(),
      DatabaseService.instance.getLimitUpPool(),
      LimitUpUniverseProvider.instance.fetchLatest(),
      DatabaseService.instance.getLimitUpPoolByDate(
        DateTime.now().subtract(const Duration(days: 1)).toIso8601String().substring(0, 10)),
    ]);

    final timing = results[0] as MarketTimingResult;
    final explore = results[1] as List<ExploreResult>;
    final todayPool = results[2] as List<LimitUpAnalysis>;
    final freshPool = results[3] as List<LimitUpAnalysis>;
    final yesterdayPool = results[4] as List<LimitUpAnalysis>;

    // 取并集（DB 缓存 + API 最新）
    final mergedMap = <String, LimitUpAnalysis>{};
    for (final a in todayPool) mergedMap[a.code] = a;
    for (final a in freshPool) mergedMap[a.code] = a;
    final mergedPool = mergedMap.values.toList();

    // 计算赚钱效应
    final todayQuotePct = <String, double>{};
    for (final a in mergedPool) {
      todayQuotePct[a.code] = a.changePct;
    }

    final sentiment = SentimentThermometer.compute(
      todayPool: mergedPool,
      yesterdayPool: yesterdayPool,
      todayQuotePct: todayQuotePct,
      marketSentiment: timing.marketSentiment,
      // yesterdayPhase 来源说明：
      // - P0 阶段：仅 App 本次运行期间的内存缓存（首次启动为 null，走纯规则路径兜底）
      // - P3 阶段（择时历史回看）：从 market_timing_history 表读取昨日 SentimentResult.phase
      yesterdayPhase: _lastSentiment?.phase,
    );
    _lastSentiment = sentiment;  // 缓存供下次刷新使用

    final limitUpCount = mergedPool.where((a) => !a.isZhaBan).length;
    final lowBuyCount = explore.where((r) =>
        r.recommendation.contains('买入') &&
        r.changePct >= -3 && r.changePct <= 5 && r.score >= 6).length;
    final mainLineCount = (await DatabaseService.instance.getSectorPickResults())
        .where((p) => p['mainLine'] == 1 || p['mainLine'] == true).length;

    setState(() {
      _marketTiming = timing;
      _sentiment = sentiment;
      _limitUpCount = limitUpCount;
      _lowBuyCount = lowBuyCount;
      _mainLineCount = mainLineCount;
      _workbenchLoading = false;
    });
  } catch (e) {
    debugPrint('Workbench load failed: $e');
    setState(() => _workbenchLoading = false);
  }
}
```

### 7.4 Stage 8：详情页 K 线打板标识

**改造目标**：在 `quote_screen.dart` 的 `_KlinePainter` 中渲染打板标记，激活 `AnalysisResult.limitUpAnalysis` 孤儿字段。

**标识设计**（K 线上方）：

```
价格轴
  │
  │         ╔═══╗  ← 涨停日：金色实心三角▲ + 连板数
  │         ║▲3 ║     一字板：金色填充矩形
  │         ╚═══╝
  │       │
  │       │      ← 炸板日：红色空心△ + "炸"字
  │
  │  ▲2          ← 2板：橙色实心三角
  │
  └────────────────── 时间轴
```

**`_KlinePainter` 扩展**：

```dart
void _drawLimitUpMarks(Canvas canvas, Size size) {
  final analysis = _analysisResult?.limitUpAnalysis;
  // 即使 analysis 为 null，也要识别历史涨停日绘制基础标记
  for (var i = 0; i < _klines.length; i++) {
    final k = _klines[i];
    if (!KlineValidator.isLimitUp(k, _klines, code: _code)) continue;

    final x = _xForIndex(i);
    final color = _limitUpMarkColor(k, analysis, i);

    // 三角标识（K 线上方 4px）
    final y = _yForPrice(k.high) - 8;
    final path = Path()
      ..moveTo(x, y - 6)
      ..lineTo(x - 5, y + 2)
      ..lineTo(x + 5, y + 2)
      ..close();
    canvas.drawPath(path, Paint()..color = color..style = PaintStyle.fill);

    // 连板数文字（仅 2 板及以上）
    final consec = _inferConsecutiveDays(i);
    if (consec >= 2) {
      final tp = TextPainter(
        text: TextSpan(text: '$consec',
            style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, y - 18));
    }

    // 一字板特殊标记
    if (KlineValidator.isYiZiBan(k, _klines)) {
      canvas.drawRect(
        Rect.fromCenter(center: Offset(x, y - 14), width: 14, height: 8),
        Paint()..color = const Color(0xFFFFB000)..style = PaintStyle.fill,
      );
    }
  }
}

Color _limitUpMarkColor(HistoryKline k, LimitUpAnalysis? analysis, int i) {
  if (_isZhabanDay(i)) return const Color(0xFFE74C3C);  // 炸板红
  if (analysis == null) return const Color(0xFFE67E22);  // 无分析数据：橙
  if (analysis.consecutiveDays >= 4) return const Color(0xFFFFB000);  // 龙头金
  if (analysis.consecutiveDays == 3) return const Color(0xFFE74C3C);  // 高度红
  return const Color(0xFFE67E22);                                    // 中度/首板橙
}
```

**详情页打板信息浮层**（K 线图下方）：

```dart
Widget _buildLimitUpSummaryCard() {
  final a = _analysisResult?.limitUpAnalysis;
  if (a == null) return const SizedBox.shrink();

  return Container(
    margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFF161B22),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFFFB000), width: 0.5),
    ),
    child: Row(children: [
      _buildLimitUpBadge('${a.consecutiveDays}连板', const Color(0xFFFFB000)),
      const SizedBox(width: 8),
      _buildLimitUpBadge(a.boardType, _boardTypeColor(a.boardType)),
      const SizedBox(width: 8),
      _buildLimitUpBadge(a.timeGrade, _timeGradeColor(a.timeGrade)),
      const Spacer(),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('次日溢价 ${((a.premiumProb ?? 0) * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 12, color: Color(0xFFFFB000), fontWeight: FontWeight.w600)),
        Text('质量 ${a.qualityScore.toStringAsFixed(1)}',
            style: const TextStyle(fontSize: 10, color: Color(0xFF8B949E))),
      ]),
    ]),
  );
}
```

### 7.5 交互：点击打板标识查看详情

```dart
void _showLimitUpDayDetail(int dayIndex) {
  final k = _klines[dayIndex];
  final a = _analysisResult?.limitUpAnalysis;
  showModalBottomSheet(
    context: context,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${k.date} 打板详情',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Divider(),
            _buildRow('连板数', '${a?.consecutiveDays ?? 1}'),
            _buildRow('板型', a?.boardType ?? '-'),
            _buildRow('首封时间', a?.firstLimitTime != null ? _formatTime(a!.firstLimitTime!) : '-'),
            _buildRow('封单金额', a != null ? '${a.sealAmount.toStringAsFixed(0)}万' : '-'),
            _buildRow('次日溢价概率', a != null ? '${((a.premiumProb ?? 0) * 100).toStringAsFixed(0)}%' : '-'),
            _buildRow('质量评分', a?.qualityScore.toStringAsFixed(1) ?? '-'),
          ],
        ),
      ),
    ),
  );
}
```

---

## 八、错误处理 + 测试策略

### 8.1 错误处理矩阵

| 场景 | 处理策略 | 用户反馈 |
|---|---|---|
| `ApiClient.getLimitUpBoard()` 全部源失败 | 返回空列表 + debugPrint 错误堆栈 | 工作台/打板 Tab 显示"打板数据获取失败" + 重试按钮 |
| 涨停池为空（盘前/早盘） | 视为合法状态，不报错 | 显示"今日暂无涨停标的，盘后将更新" |
| `LimitUpAnalyzer.analyzeBatch` 单股异常 | try-catch 单股，跳过继续 | 该股不进入榜单，不影响其他 |
| `SentimentThermometer.compute` 输入异常（昨日池为空） | 使用兜底中性值 0.3，不抛异常 | 静默处理，温度计仍显示（基于今日数据） |
| DB 迁移 v10→v11 失败 | 抛 `DatabaseException`，App 启动提示 | "数据库升级失败，请重启或联系开发者" |
| `limit_up_pool` 表读取异常 | 返回空列表 + debugPrint | 降级到旧逻辑：DiscoverScreen Tab 1 回退到 `_exploreResults.where((r) => r.isLimitUpApprox)` 平铺列表（v2.33 行为），不显示连板数/板型/封单等新字段；工作台情绪温度计卡片显示 skeleton |
| 并发刷新冲突（用户连点刷新） | `_limitUpScanLoading` 状态锁 + 防抖 500ms | 按钮禁用 + 进度条显示 |
| 情绪周期阶段判定无昨日阶段 | `yesterdayPhase = null`，走纯规则路径 | 静默 |
| K 线打板标识渲染异常 | try-catch 包裹 `_drawLimitUpMarks`，失败不影响 K 线本身 | 静默 |
| API 返回字段缺失（如 firstLimitTime=null） | 模型字段全部 nullable，UI 按需展示 | 缺失字段不显示，不报错 |

### 8.2 关键防错设计（遵循 project_memory 硬约束）

1. **`setState()` 不在 `initState` 同步调用**：`discover_screen.initState` 中 `LimitUpScanEngine` 状态恢复改用 `WidgetsBinding.instance.addPostFrameCallback`
2. **`TabBar` 不混用 `isScrollable` + `tabAlignment: fill`**：打板梯队分组用 `ListView` 滚动，TabBar 维持 `isScrollable: false` + `tabAlignment: fill`
3. **sqflite `QueryResultSet` 只读**：所有 `db.query()` 返回的 list 在 sort 前必须 `List.from()` 创建可变副本
4. **Text 动态内容溢出保护**：所有新增 Text widget 必须加 `maxLines` + `overflow: TextOverflow.ellipsis`
5. **ErrorWidget.builder 沿用 v2.33 修复**：不修改 main.dart 的 ErrorWidget 配置

### 8.3 测试策略

#### 8.3.1 单元测试（核心算法 100% 覆盖）

**新增 `test/sentiment_thermometer_test.dart`**：
- `zhabanRate`：空池/全炸板/半炸板
- `continuationRate`：昨日空/10→5 晋级/封顶 1.0
- `sealSuccessRate`：全封板/弱封板惩罚
- `moneyMakingEffect`：昨日空/均值计算
- `temperature`：边界值（全好/全差）
- `phase inference`：4 阶段触发条件 + 状态转移（freezing→startup / climax→retreat / retreat→freezing）
- `signals generation`：阈值触发 + 多信号组合

**新增 `test/limit_up_analyzer_batch_test.dart`**（激活 dead code 回归）：
- `analyzeBatch` 调用方存在（激活 dead code 路径）
- `firstLimitTime` 影响 `timeGrade`（早盘 vs 尾盘偷鸡）
- `sealAmount` 影响 `qualityScore`
- 一字板检测
- 炸板检测

**新增 `test/limit_up_pool_db_test.dart`**：
- v10 → v11 迁移成功
- `replaceLimitUpPool` 全量替换
- 复合主键 `(code, trade_date)` 支持历史
- `getLimitUpPoolByDate` 仅返回指定日期
- `QueryResultSet` 只读回归（`List.from` 后 sort 不抛异常）

#### 8.3.2 Widget 测试

**新增 `test/discover_limit_up_tab_test.dart`**：
- 分组按连板数渲染（4 个分组标题）
- 空状态显示刷新按钮
- 情绪迷你卡显示阶段 + 5 维指标
- 长按显示操作表
- 无炸板时不显示炸板组

**新增 `test/sentiment_card_test.dart`**：
- climax 阶段显示红色渐变
- 温度条位置正确
- null sentiment 显示骨架
- signals 文本省略号截断

**新增 `test/kline_limit_up_marks_test.dart`**（Stage 8 回归）：
- 涨停日渲染标记
- 点击标记显示详情 sheet
- null limitUpAnalysis 隐藏浮层
- 一字板显示金色矩形

#### 8.3.3 集成测试

**新增 `test/p0_integration_test.dart`**：
- 端到端：API mock → analyzer → sentiment → DB → UI 数据
- 降级路径：API 失败 → 降级到 ExploreEngine + isLimitUpApprox

### 8.4 验证清单

```bash
# 静态分析
cd mobile && flutter analyze
# 期望: 0 errors

# 全量测试
flutter test
# 期望: 既有 578 + 新增 ~30 = 600+ tests 全部通过

# 关键回归
flutter test test/discover_build_test.dart \
             test/sentiment_thermometer_test.dart \
             test/limit_up_analyzer_batch_test.dart \
             test/limit_up_pool_db_test.dart

# APK 构建
flutter build apk --release
# 期望: 成功，体积增幅 < 2MB（无新依赖）
```

### 8.5 性能预算

| 指标 | 预算 | 监控点 |
|---|---|---|
| `getLimitUpBoard()` 耗时 | < 1.5s（含 GBK 解码 + 重试） | ApiClient._httpGet 计时 |
| `analyzeBatch` 100 只 | < 200ms | LimitUpScanEngine 进度上报 |
| `SentimentThermometer.compute` | < 10ms | 纯函数，无 IO |
| 工作台首屏渲染 | < 500ms（DB 缓存优先） | `_loadWorkbenchData` 计时 |
| 打板 Tab 滚动 FPS | ≥ 55 | Profile 模式验证 |
| K 线打板标识绘制增量 | < 5ms | `_KlinePainter.paint` 计时 |

### 8.6 无新增依赖

P0 子项目**不引入任何新第三方库**：
- API：复用现有 `http` + `dart:io HttpClient` fallback
- GBK 解码：复用 `charset_converter`
- 图表：复用 `fl_chart` + 现有 `CustomPaint`
- DB：复用 `sqflite`

避免 pubspec.yaml 变更带来的依赖冲突风险。

---

## 九、实施范围与验收标准

### 9.1 实施范围（必做项）

- [ ] 9.1.1 数据层：`ApiClient.getLimitUpBoard()` + `getYesterdayLimitUpPool()` 实现
- [ ] 9.1.2 数据层：`LimitUpStock` 模型 + `fromEastMoney` 工厂
- [ ] 9.1.3 数据层：DB 迁移 v10→v11 + `limit_up_pool` 表 + CRUD 方法
- [ ] 9.1.4 引擎层：`LimitUpUniverseProvider` 涨停池采集器
- [ ] 9.1.5 引擎层：激活 `LimitUpAnalyzer.analyzeBatch`（从 dead code 变活路径）
- [ ] 9.1.6 引擎层：`SentimentThermometer` 纯函数引擎（5 维指标 + 阶段判定）
- [ ] 9.1.7 引擎层：`LimitUpScanEngine extends BaseAnalysisEngine`
- [ ] 9.1.8 UI 层：`SentimentThermometerCard` 大卡片 widget
- [ ] 9.1.9 UI 层：`LimitUpCard` 打板卡片 widget
- [ ] 9.1.10 UI 层：发现页打板梯队 Tab 重画（分组 + 情绪迷你卡）
- [ ] 9.1.11 UI 层：首页工作台升级（1 大卡 + 2×2 网格）
- [ ] 9.1.12 UI 层：详情页 K 线打板标识（Stage 8）+ 浮层卡片
- [ ] 9.1.13 测试：sentiment_thermometer_test.dart
- [ ] 9.1.14 测试：limit_up_analyzer_batch_test.dart
- [ ] 9.1.15 测试：limit_up_pool_db_test.dart
- [ ] 9.1.16 测试：discover_limit_up_tab_test.dart
- [ ] 9.1.17 测试：sentiment_card_test.dart
- [ ] 9.1.18 测试：kline_limit_up_marks_test.dart
- [ ] 9.1.19 测试：p0_integration_test.dart

### 9.2 验收标准

1. `flutter analyze` 0 errors
2. `flutter test` 全量通过（既有 578 + 新增 ~30 = 600+）
3. `flutter build apk --release` 成功，体积增幅 < 2MB
4. 真机验证：发现页打板梯队 Tab 显示分组卡片 + 情绪迷你卡
5. 真机验证：首页工作台显示情绪温度计大卡片 + 4 个计数小卡
6. 真机验证：详情页 K 线显示打板三角标识 + 连板数文字 + 浮层卡片
7. 真机验证：长按打板卡片显示操作菜单（加自选/加持仓/查看板块/打板预警）
8. 真机验证：API 失败时降级到 ExploreEngine + isLimitUpApprox 旧逻辑，不白屏

---

## 十、风险与缓解

| 风险 | 概率 | 影响 | 缓解措施 |
|---|---|---|---|
| 东方财富接口变更字段 | 中 | 高 | `LimitUpStock.fromEastMoney` 容错（null/缺字段），失败降级到 ExploreEngine |
| 接口被风控限流 | 中 | 中 | 复用现有 `_httpGet` 2 次重试 + `dart:io HttpClient` fallback；用户感知为"获取失败请重试" |
| `LimitUpAnalyzer.analyzeBatch` 算法 bug | 低 | 中 | 单股 try-catch，回归测试覆盖核心场景 |
| DB 迁移失败 | 低 | 高 | 迁移在事务内执行，失败回滚；启动时检测表是否存在 |
| 情绪周期阶段判定不准 | 中 | 中 | 阶段判定是建议性输出，不影响交易；后续 P3 子项目接入历史数据可校准 |
| 工作台首屏渲染变慢 | 低 | 低 | DB 缓存优先，API 异步刷新；温度计卡片 skeleton 占位 |

---

## 十一、后续子项目预告

P0 完成后，后续子项目将依次启动：

- **P1 真分时低吸引擎**：基于 `IntradayLevelAnalyzer` 全市场扫描，复用 P0 的 `LimitUpScanEngine` 基础设施
- **P2 持仓风控升级**：Position 模型加 stopLossPrice/takeProfitPrice 字段，独立持仓屏幕
- **P3 择时历史回看**：market_timing_history 表，情绪周期曲线（依赖 P0 的 limit_up_pool 历史数据）
- **P4 龙虎榜 + 资金流分时**：东方财富龙虎榜 API + 个股分时主力资金流图

---

## 附录 A：东方财富涨停板接口字段映射表

| 东财字段 | 含义 | LimitUpStock 字段 | 单位转换 |
|---|---|---|---|
| `n` | 股票名称 | `name` | - |
| `c` | 股票代码 | `code` | padLeft(6, '0') |
| `lbc` | 连板数 | `consecutiveDays` | - |
| `fbt` | 首次封板时间 | `firstLimitTime` | 整数 92500 → DateTime(09:25:00) |
| `lbt` | 最后封板时间 | `lastLimitTime` | 同上 |
| `fund` | 封板资金 | `sealAmount` | 元 → 万元（/ 10000） |
| `hs` | 换手率 | `turnoverRate` | % |
| `zbc` | 炸板次数 | `zhabanCount` / `isZhaBan` | >0 即炸板 |
| `hybk` | 所属行业 | `sector` | - |
| `zttj` | 涨停统计 | （参考） | `{days, ct}` |
| `ltsz` | 流通市值 | `circulationValue` | 元 |
| `tshare` | 总市值 | `totalValue` | 元 |

**未提供字段**（需另调行情接口补充）：
- `price` / `changePct`：通过 `getBatchRealtimeQuotes` 批量补充
- `volumeRatio`（量比）：同上
- `limitUpPrice`（涨停价）：本地计算 `yesterdayClose × (1 + limitPct)`，limitPct 按 code 前缀推断
- `sealRatio`（封成比）：`sealAmount / turnoverAmount`，turnoverAmount 从行情接口获取

---

## 附录 B：与现有模块的协同关系

| 现有模块 | P0 协同方式 |
|---|---|
| `MarketTiming` | 情绪温度计输出阶段仓位建议，与 `MarketTiming.getPositionAdjustment()` 取较低值（保守优先） |
| `ExploreEngine` | P0 后 Tab 1 不再依赖 ExploreEngine，但 Tab 3/4 仍依赖；ExploreEngine 结果用于"分时低吸"计数 |
| `SectorPickEngine` | 主线判定可复用 P0 的连板高度数据（后续 P3 优化） |
| `OpportunityEngine` | 不变（自选股分析独立） |
| `MarketTiming.fetchTiming()` | 工作台 `_loadWorkbenchData` 并发调用，提供 `MarketSentiment` |
| `AnalysisResult.limitUpAnalysis` | Stage 8 激活，详情页 K 线渲染 |
| `BaseAnalysisEngine` | `LimitUpScanEngine` 继承，复用进度流 + 单例模式 |
| `DatabaseService` | 新增 v11 迁移 + `limit_up_pool` 表 CRUD |

---

**Spec 结束**。请审核后转入 writing-plans 生成实施计划。
