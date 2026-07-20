#!/usr/bin/env python3
# -*- coding: gbk -*-
"""日K线抓取器（akshare）。

主源：新浪 stock_zh_a_daily（本环境可用，代码形如 sh600519 直接匹配留档格式）。
回退：东方财富 stock_zh_a_hist（本环境被拒，但用户环境可能可用）。

逐票缓存到 cache/{code}.csv（可续跑：已缓存则跳过），失败重试+退避+跳过，
最后输出覆盖率。缓存后分析全程离线可复现。
"""

import argparse
import os
import socket
import time

import pandas as pd

import config

# 标准化后统一列
_STD_COLS = ['date', 'open', 'high', 'low', 'close', 'volume', 'amount', 'turnover']


def _cache_path(code: str) -> str:
    return os.path.join(config.CACHE_DIR, f'{code}.csv')


def _to_6digit(code: str) -> str:
    return ''.join(ch for ch in code if ch.isdigit())


def _normalize_sina(df: pd.DataFrame) -> pd.DataFrame:
    """新浪 stock_zh_a_daily 输出 -> 标准列。"""
    out = pd.DataFrame()
    out['date'] = pd.to_datetime(df['date'])
    for c in ('open', 'high', 'low', 'close', 'volume', 'amount'):
        out[c] = pd.to_numeric(df[c], errors='coerce') if c in df.columns else pd.NA
    # 新浪 turnover = volume/outstanding_share（换手率，分数形式）
    out['turnover'] = pd.to_numeric(df['turnover'], errors='coerce') if 'turnover' in df.columns else pd.NA
    return out[_STD_COLS]


def _normalize_em(df: pd.DataFrame) -> pd.DataFrame:
    """东方财富 stock_zh_a_hist 输出（中文列）-> 标准列。"""
    ren = {'日期': 'date', '开盘': 'open', '收盘': 'close', '最高': 'high',
           '最低': 'low', '成交量': 'volume', '成交额': 'amount', '换手率': 'turnover'}
    d = df.rename(columns=ren)
    out = pd.DataFrame()
    out['date'] = pd.to_datetime(d['date'])
    for c in ('open', 'high', 'low', 'close', 'volume', 'amount'):
        out[c] = pd.to_numeric(d[c], errors='coerce') if c in d.columns else pd.NA
    # 东财换手率是百分比 -> 转分数，口径与新浪一致
    out['turnover'] = pd.to_numeric(d['turnover'], errors='coerce') / 100.0 if 'turnover' in d.columns else pd.NA
    return out[_STD_COLS]


def _fetch_sina(code: str) -> pd.DataFrame:
    import akshare as ak
    df = ak.stock_zh_a_daily(symbol=code, start_date=config.HISTORY_START,
                             end_date=config.HISTORY_END, adjust='qfq')
    if df is None or df.empty:
        raise ValueError('empty')
    return _normalize_sina(df)


def _fetch_em(code: str) -> pd.DataFrame:
    import akshare as ak
    df = ak.stock_zh_a_hist(symbol=_to_6digit(code), period='daily',
                            start_date=config.HISTORY_START, end_date=config.HISTORY_END,
                            adjust='qfq')
    if df is None or df.empty:
        raise ValueError('empty')
    return _normalize_em(df)


def fetch_one(code: str) -> pd.DataFrame | None:
    """抓取单只，Sina 优先、EM 回退，带重试退避。失败返回 None。"""
    last_err = None
    for attempt in range(config.FETCH_MAX_RETRY):
        for fetcher in (_fetch_sina, _fetch_em):
            try:
                df = fetcher(code)
                df = df.dropna(subset=['close']).sort_values('date').reset_index(drop=True)
                if len(df) >= config.MIN_LOOKBACK_BARS:
                    return df
                last_err = f'too_short({len(df)})'
            except Exception as e:  # noqa: BLE001
                last_err = f'{type(e).__name__}:{str(e)[:60]}'
        time.sleep(config.FETCH_RETRY_BACKOFF * (attempt + 1))
    print(f'  [skip] {code}: {last_err}')
    return None


def load_kline(code: str) -> pd.DataFrame | None:
    """从缓存读取单只 K 线；无缓存返回 None。"""
    path = _cache_path(code)
    if not os.path.exists(path):
        return None
    try:
        df = pd.read_csv(path, parse_dates=['date'])
        if df.empty or 'close' not in df.columns:
            return None
        return df.sort_values('date').reset_index(drop=True)
    except Exception:  # noqa: BLE001
        return None


def fetch_universe(codes: list, force: bool = False, limit: int | None = None) -> dict:
    """抓取整个股票池并缓存。返回覆盖率统计。"""
    config.ensure_dirs()
    socket.setdefaulttimeout(config.FETCH_TIMEOUT)  # 防止无超时的新浪连接挂死
    if limit:
        codes = codes[:limit]
    total = len(codes)
    ok, cached, failed = 0, 0, []
    consecutive_fail = 0
    for i, code in enumerate(codes, 1):
        path = _cache_path(code)
        if not force and os.path.exists(path):
            cached += 1
            continue
        df = fetch_one(code)
        if df is not None:
            df.to_csv(path, index=False, encoding='utf-8-sig')
            ok += 1
            consecutive_fail = 0
        else:
            failed.append(code)
            consecutive_fail += 1
            # 连续失败多半是限频，冷却一段时间再继续
            if consecutive_fail >= config.FETCH_COOLDOWN_AFTER:
                print(f'  连续失败 {consecutive_fail} 次，冷却 {config.FETCH_COOLDOWN_SEC}s...')
                time.sleep(config.FETCH_COOLDOWN_SEC)
                consecutive_fail = 0
        time.sleep(config.FETCH_SLEEP_SEC)
        if i % 25 == 0 or i == total:
            print(f'进度 {i}/{total} | 新抓取 {ok} | 已缓存 {cached} | 失败 {len(failed)}', flush=True)
    return {'total': total, 'fetched': ok, 'cached': cached,
            'failed': failed, 'covered': ok + cached}


def main():
    config.force_utf8_stdout()
    config.ensure_dirs()
    parser = argparse.ArgumentParser(description='抓取留档股票池日K线')
    parser.add_argument('--force', action='store_true', help='强制重抓（忽略缓存）')
    parser.add_argument('--limit', type=int, default=None, help='仅抓前 N 只（调试用）')
    args = parser.parse_args()

    import load_archive
    panel = load_archive.load_archive_panel()
    codes = load_archive.get_universe(panel)
    print(f'股票池 {len(codes)} 只，历史 {config.HISTORY_START}~{config.HISTORY_END}')
    stats = fetch_universe(codes, force=args.force, limit=args.limit)
    cov = stats['covered'] / stats['total'] * 100 if stats['total'] else 0
    print(f"\n覆盖率: {stats['covered']}/{stats['total']} ({cov:.1f}%)")
    print(f"新抓取 {stats['fetched']} | 已缓存 {stats['cached']} | 失败 {len(stats['failed'])}")
    if stats['failed']:
        print('失败清单(前20):', stats['failed'][:20])


if __name__ == '__main__':
    config.add_self_to_path()
    main()
