# 股票分析助手

基于 Flutter 开发的 A 股实时监控与技术分析 Android 应用，支持离线数据存储，无需后端服务即可独立运行。

## 功能特性

- **实时行情** — 最新价、涨跌幅、开盘价、最高价、最低价、成交量等
- **K线图表** — 展示价格走势，叠加均线(MA5/MA10/MA20/MA60)
- **技术指标** — MACD、RSI、KDJ、BOLL 等完整技术指标计算
- **买卖信号检测** — 均线金叉/死叉、MACD金叉/死叉、RSI超买/超卖、KDJ金叉/死叉、BOLL突破等
- **操作建议** — 综合评分生成买入/卖出/观望等建议，附带风险评估
- **自选股管理** — 本地 SQLite 存储，支持添加/删除自选股
- **盯盘提醒** — 价格突破、涨跌幅阈值提醒规则
- **市场情绪** — 全市场上涨/下跌家数、涨停/跌停数

## 项目结构

```
stock/
├── mobile/                  # Android 移动客户端（Flutter）
│   ├── android/             # Android 原生配置
│   ├── pubspec.yaml         # Flutter 依赖配置
│   └── lib/                 # Dart 源码
│       ├── main.dart        # 应用入口
│       ├── api/             # 新浪财经 API 客户端
│       │   └── api_client.dart
│       ├── analysis/        # 技术分析引擎
│       │   ├── indicators.dart    # MA/MACD/RSI/KDJ/BOLL 指标计算
│       │   └── signal_engine.dart # 信号检测和分析引擎
│       ├── models/          # 数据模型
│       │   └── stock_models.dart
│       ├── screens/         # 页面
│       │   ├── home_screen.dart       # 首页
│       │   ├── search_screen.dart     # 搜索页面
│       │   ├── watchlist_screen.dart  # 自选股页面
│       │   ├── signals_screen.dart    # 信号分析页面
│       │   ├── alerts_screen.dart     # 盯盘提醒页面
│       │   └── quote_screen.dart      # 股票详情页面
│       ├── storage/         # 本地存储
│       │   └── database_service.dart  # SQLite 数据库服务
│       └── widgets/         # UI 组件
│           ├── signal_card.dart       # 信号卡片
│           └── alert_dialog.dart      # 提醒对话框
│
├── server/                  # 后端 API 服务（可选，保留）
├── desktop/                 # PC 桌面客户端（可选，保留）
├── app-release.apk          # 预构建的 APK 文件
└── README.md                # 项目说明
```

## 快速开始

### 方式一：直接安装 APK

1. 将 `app-release.apk` 传输到 Android 手机（微信/数据线/U盘均可）
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

# 4. 传输到手机安装
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
- **新浪财经 API** — 股票搜索、实时行情、历史 K 线数据
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

## 环境配置

### Windows 环境变量

```powershell
# 设置 ANDROID_HOME
$env:ANDROID_HOME = "D:\MyProjects\stock\android-sdk"

# 设置 JAVA_HOME（JDK 17）
$env:JAVA_HOME = "D:\Java\jdk-17.0.13+11"

# 配置 PATH（确保 flutter 命令可用）
$env:PATH += ";D:\flutter\bin"
```

### Gradle 配置

项目使用国内镜像加速 Gradle 下载：
- 腾讯云镜像：`https://mirrors.cloud.tencent.com/gradle/`
- 清华镜像：`https://mirrors.tuna.tsinghua.edu.cn/`

## 依赖说明

| 包 | 用途 |
|---|---|
| flutter | 移动端框架 |
| http | HTTP 请求 |
| sqflite | SQLite 本地存储 |
| path_provider | 文件路径管理 |
| fl_chart | 图表库 |
| flutter_local_notifications | 本地通知 |
| shared_preferences | 偏好设置 |

## 免责声明

本工具仅供学习研究使用，所有分析结果均基于技术指标，不构成任何投资建议。投资有风险，入市需谨慎。
