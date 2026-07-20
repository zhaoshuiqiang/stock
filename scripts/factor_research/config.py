#!/usr/bin/env python3
# -*- coding: gbk -*-
"""因子研究离线管线 —— 共享配置与常量。

所有路径、A股成本模型、前瞻窗口、统计常量集中在此，供其余模块 import。
不依赖 scipy/matplotlib；统计在 ic.py 内用 numpy/pandas 自实现。
"""

import os
import sys

# ---- 路径 ----
# config.py 位于 scripts/factor_research/ 下，仓库根 = 上两级
_THIS_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(_THIS_DIR, '..', '..'))

ARCHIVE_DIR = os.path.join(REPO_ROOT, '留档数据')          # 10 个留档 CSV
CACHE_DIR = os.path.join(_THIS_DIR, 'cache')               # 逐票 K 线本地缓存（gitignore）
OUTPUT_DIR = os.path.join(_THIS_DIR, 'output')             # 中间 CSV 产物（gitignore）
DOCS_DIR = os.path.join(REPO_ROOT, 'docs')                 # 报告落地目录
REPORT_PATH = os.path.join(DOCS_DIR, 'factor_research_report.md')

# ---- A股成本模型（对齐 mobile/lib/analysis/backtest_engine.dart）----
COMMISSION_RATE = 0.00025   # 佣金，双向，万2.5
STAMP_TAX_RATE = 0.001      # 印花税，仅卖出，千1（沿用 App 常量）
TRANSFER_RATE = 0.00002     # 过户费，双向，万0.2
SLIPPAGE_RATE = 0.001       # 滑点估算，双向，0.1%
MIN_COMMISSION = 5.0        # 最低佣金（元）

# ---- 前瞻窗口 / 回测 ----
HORIZONS = [1, 3, 5, 10]     # 未来 N 日收益的 N
DEFAULT_HORIZON = 5          # 报告主口径
N_QUANTILES = 5              # 分档回测档数（Q1..Q5）

# ---- 历史窗口（akshare 拉取范围）----
# 归档日集中在 2026-07；为多日 IC 轨道保留约 2 年历史。
HISTORY_START = '20240101'
HISTORY_END = '20260720'

# 因子最小回看（60 日均线/动量），前瞻最大 10 日 —— 用于 walk-forward 起点保护
MIN_LOOKBACK_BARS = 65

# ---- 统计常量 ----
Z_95 = 1.96                  # 95% 置信 z 值
MIN_CROSS_SECTION = 5        # 单日截面 IC 至少需要的个股数
NEWEY_WEST_MAX_LAG = 10      # Newey-West 自相关修正最大滞后

# ---- 网络抓取 ----
# 本环境 EastMoney(push2his) 被拒，新浪源 stock_zh_a_daily 可用；主用新浪，可回退。
FETCH_SLEEP_SEC = 0.35       # 每票间隔，降低被限频风险
FETCH_MAX_RETRY = 2
FETCH_RETRY_BACKOFF = 1.0     # 秒，指数退避基数
FETCH_TIMEOUT = 12           # socket 全局超时（秒），防止新浪源无超时挂死
FETCH_COOLDOWN_AFTER = 6     # 连续失败达到此数则冷却，缓解限频
FETCH_COOLDOWN_SEC = 25      # 冷却时长（秒）


def ensure_dirs():
    """创建缓存/产物/报告目录（幂等）。"""
    for d in (CACHE_DIR, OUTPUT_DIR, DOCS_DIR):
        os.makedirs(d, exist_ok=True)


def force_utf8_stdout():
    """Windows 控制台默认 gbk；强制 utf-8，避免中文/emoji 打印崩溃。"""
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass


def add_self_to_path():
    """把本目录加入 sys.path，使各模块可直接 `import config` / 互相 import，
    无论从哪个 CWD 以 `python scripts/factor_research/xxx.py` 方式运行。"""
    if _THIS_DIR not in sys.path:
        sys.path.insert(0, _THIS_DIR)
