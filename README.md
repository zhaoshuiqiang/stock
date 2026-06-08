# 股票分析助手

基于 Flutter 开发的 A 股实时监控与技术分析 Android 应用，支持离线数据存储，无需后端服务即可独立运行。

## 功能特性

- **实时行情** — 最新价、涨跌幅、开盘价、最高价、最低价、成交量等，支持多数据源交叉验证
- **K线图表** — 展示价格走势，叠加均线(MA5/MA10/MA20/MA60)
- **技术指标** — MACD、RSI、KDJ、BOLL 等完整技术指标计算
- **买卖信号检测** — 均线金叉/死叉、MACD金叉/死叉、RSI超买/超卖、KDJ金叉/死叉、BOLL突破等
- **操作建议** — 综合评分生成强烈买入/买入/观望/卖出/强烈卖出建议，附带风险评估和机会识别
- **自选股管理** — 本地 SQLite 存储，支持添加/删除自选股
- **盯盘提醒** — 价格突破、涨跌幅阈值提醒规则
- **市场情绪** — 全市场上涨/下跌家数、涨停/跌停数
- **盘中实时更新** — 交易时段自动刷新行情和指标分析
- **数据验证** — 多源交叉验证、异常数据检测、K线完整性校验

## 项目结构

```
stock/
└── mobile/                  # Android 移动客户端（Flutter）
    ├── android/             # Android 原生配置
    ├── pubspec.yaml         # Flutter 依赖配置
    ├── build_release.ps1    # APK 构建脚本
    └── lib/                 # Dart 源码
        ├── main.dart        # 应用入口
        ├── api/             # 数据获取客户端
        │   └── api_client.dart
        ├── analysis/        # 技术分析引擎
        │   ├── indicators.dart    # MA/MACD/RSI/KDJ/BOLL 指标计算
        │   ├── signal_engine.dart # 信号检测引擎
        │   └── strategy_engine.dart # 策略与建议引擎
        ├── models/          # 数据模型
        │   └── stock_models.dart
        ├── screens/         # 页面
        ├── services/        # 业务服务
        ├── storage/         # 本地存储
        ├── validators/      # 数据验证
        └── widgets/         # UI 组件
```

## 快速开始

### 方式一：直接安装 APK

1. 将 APK 传输到 Android 手机
2. 在手机上打开 APK 文件，允许安装未知来源应用
3. 安装完成后打开应用即可使用

### 方式二：自行编译 APK（开发者）

前置要求：
- [Flutter SDK](https://docs.flutter.dev/get-started/install) >= 3.0.0
- JDK 17
- Android SDK（API 36+）

```bash
# 1. 进入项目目录
cd mobile

# 2. 安装依赖
flutter pub get

# 3. 编译 APK
flutter build apk --release
# 产物位于 build/app/outputs/flutter-apk/app-release.apk
```

调试模式可直接运行：
```bash
flutter run
```

## 使用说明

1. **首页** — 查看大盘指数和热门股票实时行情
2. **搜索股票** — 输入股票代码或名称搜索，点击结果查看详情
3. **自选股** — 管理关注的股票，查看实时行情
4. **信号分析** — 查看股票的买卖信号、综合评分和操作建议
5. **盯盘提醒** — 创建价格、涨跌幅等提醒规则

## 技术实现

### 数据来源
- **东方财富 API** — 实时行情、分时线数据
- **腾讯 API** — 实时行情（交叉验证）
- **新浪财经 API** — 股票搜索、历史 K 线数据
- **本地 SQLite** — 自选股、提醒规则存储

### 技术指标
- **均线 (MA)** — MA5、MA10、MA20、MA60
- **MACD** — DIF、DEA、MACD 柱
- **RSI** — RSI6、RSI12、RSI24
- **KDJ** — K、D、J 线
- **BOLL** — 布林带上轨、中轨、下轨

### 信号检测
- 均线金叉/死叉
- MACD 金叉/死叉
- RSI 超买/超卖（>80 / <20）
- KDJ 金叉/死叉、J 值超买/超卖
- BOLL 突破上轨/下轨

## 免责声明

本工具仅供学习研究使用，所有分析结果均基于技术指标，不构成任何投资建议。投资有风险，入市需谨慎。
