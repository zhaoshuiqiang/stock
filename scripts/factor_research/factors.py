#!/usr/bin/env python3
# -*- coding: gbk -*-
"""技术因子库。

从日K线计算约 28 个候选因子，命名与口径对齐 App
（mobile/lib/analysis/indicators.dart + next_session_feature_extractor.dart）：
  - MACD: EMA alpha=2/(n+1)、seed=close[0]（pandas ewm span, adjust=False）
  - RSI : Wilder 平滑 alpha=1/period（ewm alpha, adjust=False）
  - KDJ : TDX 口径 RSV -> SMA(,3,1)

因子用于截面 IC（秩相关），故平滑/缩放细节不影响结论；返回的长面板还附带
未来 N 日收益（收盘-收盘）与可执行收益（次日开盘进、N 日后收盘出）。
"""

import numpy as np
import pandas as pd

import config

# ---- 因子清单与中文说明（供报告展示）----
FACTOR_DESC = {
    'mom5': '5日动量(收益)',
    'mom10': '10日动量',
    'mom20': '20日动量',
    'mom60': '60日动量',
    'ret1': '昨日单日收益(短反转)',
    'volratio5': '量比5(量/5日均量)',
    'volratio10': '量比10',
    'turnover': '换手率',
    'vol20': '20日收益波动率',
    'amplitude': '当日振幅%',
    'atr_pct': 'ATR14/收盘',
    'bias6': '乖离率BIAS6',
    'bias10': '乖离率BIAS10',
    'bias20': '乖离率BIAS20',
    'ma_align': '均线多头排列强度(0-3)',
    'adx14': 'ADX14趋势强度',
    'rsi6': 'RSI6',
    'rsi12': 'RSI12',
    'kdj_k': 'KDJ-K',
    'kdj_d': 'KDJ-D',
    'kdj_j': 'KDJ-J',
    'macd_hist': 'MACD柱(2*(DIF-DEA))',
    'macd_dif_dea': 'DIF-DEA',
    'cci14': 'CCI14',
    'wr14': 'WR14(威廉)',
    'close_pos': '当日收盘位置(0-1)',
    'dist_high20': '距20日高%(<=0)',
    'dist_low20': '距20日低%(>=0)',
}
FACTOR_COLS = list(FACTOR_DESC.keys())


def _ema(s: pd.Series, span: int) -> pd.Series:
    return s.ewm(span=span, adjust=False).mean()


def _wilder(s: pd.Series, n: int) -> pd.Series:
    return s.ewm(alpha=1.0 / n, adjust=False).mean()


def _rsi(close: pd.Series, n: int) -> pd.Series:
    delta = close.diff()
    gain = delta.clip(lower=0)
    loss = (-delta).clip(lower=0)
    avg_gain = _wilder(gain, n)
    avg_loss = _wilder(loss, n)
    rs = avg_gain / avg_loss.replace(0, np.nan)
    rsi = 100 - 100 / (1 + rs)
    return rsi.where(avg_loss != 0, 100.0)


def _kdj(high, low, close, n=9):
    llv = low.rolling(n, min_periods=1).min()
    hhv = high.rolling(n, min_periods=1).max()
    rng = (hhv - llv).replace(0, np.nan)
    rsv = ((close - llv) / rng * 100).fillna(50.0)
    k = _wilder(rsv, 3)  # SMA(RSV,3,1)
    d = _wilder(k, 3)
    j = 3 * k - 2 * d
    return k, d, j


def _cci(high, low, close, n=14):
    tp = (high + low + close) / 3.0
    ma = tp.rolling(n, min_periods=n).mean()
    md = (tp - ma).abs().rolling(n, min_periods=n).mean()
    return (tp - ma) / (0.015 * md.replace(0, np.nan))


def _wr(high, low, close, n=14):
    hhv = high.rolling(n, min_periods=n).max()
    llv = low.rolling(n, min_periods=n).min()
    rng = (hhv - llv).replace(0, np.nan)
    return (hhv - close) / rng * 100


def _atr(high, low, close, n=14):
    prev_close = close.shift(1)
    tr = pd.concat([(high - low),
                    (high - prev_close).abs(),
                    (low - prev_close).abs()], axis=1).max(axis=1)
    return _wilder(tr, n)


def _dmi(high, low, close, n=14):
    """返回 (adx, plus_di, minus_di)，供 ADX 值与方向判断复用。"""
    up = high.diff()
    down = -low.diff()
    plus_dm = ((up > down) & (up > 0)) * up
    minus_dm = ((down > up) & (down > 0)) * down
    atr = _atr(high, low, close, n)
    plus_di = 100 * _wilder(plus_dm, n) / atr.replace(0, np.nan)
    minus_di = 100 * _wilder(minus_dm, n) / atr.replace(0, np.nan)
    dx = 100 * (plus_di - minus_di).abs() / (plus_di + minus_di).replace(0, np.nan)
    adx = _wilder(dx.fillna(0), n)
    return adx, plus_di, minus_di


def _adx(high, low, close, n=14):
    return _dmi(high, low, close, n)[0]


def compute_factors(kline: pd.DataFrame) -> pd.DataFrame:
    """单只股票 K 线 -> 因子时间序列（含 open/close 供下游收益计算）。"""
    df = kline.sort_values('date').reset_index(drop=True).copy()
    c, h, l, o = df['close'], df['high'], df['low'], df['open']
    vol = df['volume']
    prev_c = c.shift(1)

    out = pd.DataFrame({'date': df['date'], 'open': o, 'close': c})

    # 动量 / 反转
    out['mom5'] = c / c.shift(5) - 1
    out['mom10'] = c / c.shift(10) - 1
    out['mom20'] = c / c.shift(20) - 1
    out['mom60'] = c / c.shift(60) - 1
    out['ret1'] = c / prev_c - 1

    # 量能
    out['volratio5'] = vol / vol.rolling(5, min_periods=5).mean()
    out['volratio10'] = vol / vol.rolling(10, min_periods=10).mean()
    out['turnover'] = df['turnover']

    # 波动
    ret = c.pct_change()
    out['vol20'] = ret.rolling(20, min_periods=15).std()
    out['amplitude'] = (h - l) / prev_c * 100
    out['atr_pct'] = _atr(h, l, c, 14) / c

    # 均线 / 趋势
    ma5 = c.rolling(5, min_periods=5).mean()
    ma10 = c.rolling(10, min_periods=10).mean()
    ma20 = c.rolling(20, min_periods=20).mean()
    ma60 = c.rolling(60, min_periods=60).mean()
    out['bias6'] = (c - c.rolling(6, min_periods=6).mean()) / c.rolling(6, min_periods=6).mean() * 100
    out['bias10'] = (c - ma10) / ma10 * 100
    out['bias20'] = (c - ma20) / ma20 * 100
    out['ma_align'] = ((ma5 > ma10).astype(float)
                       + (ma10 > ma20).astype(float)
                       + (ma20 > ma60).astype(float))
    out['adx14'] = _adx(h, l, c, 14)

    # 摆动指标
    out['rsi6'] = _rsi(c, 6)
    out['rsi12'] = _rsi(c, 12)
    k, d, j = _kdj(h, l, c, 9)
    out['kdj_k'], out['kdj_d'], out['kdj_j'] = k, d, j
    dif = _ema(c, 12) - _ema(c, 26)
    dea = _ema(dif, 9)
    out['macd_hist'] = 2 * (dif - dea)
    out['macd_dif_dea'] = dif - dea
    out['cci14'] = _cci(h, l, c, 14)
    out['wr14'] = _wr(h, l, c, 14)

    # 位置
    rng = (h - l).replace(0, np.nan)
    out['close_pos'] = ((c - l) / rng).clip(0, 1).fillna(0.5)
    hhv20 = h.rolling(20, min_periods=20).max()
    llv20 = l.rolling(20, min_periods=20).min()
    out['dist_high20'] = c / hhv20 - 1
    out['dist_low20'] = c / llv20 - 1

    return out


def add_forward_returns(fac: pd.DataFrame, horizons=None) -> pd.DataFrame:
    """给单只因子序列附加未来 N 日收益。

    fwd_ret_N     : 收盘->收盘，用于标准 IC
    fwd_exec_ret_N: 次日开盘进、N 日后收盘出，用于回测（可执行口径）
    """
    horizons = horizons or config.HORIZONS
    df = fac.copy()
    c, o = df['close'], df['open']
    for n in horizons:
        df[f'fwd_ret_{n}'] = c.shift(-n) / c - 1
        df[f'fwd_exec_ret_{n}'] = c.shift(-n) / o.shift(-1) - 1
    return df


def build_panel(codes: list, loader=None, horizons=None) -> pd.DataFrame:
    """加载每只缓存 K 线 -> 计算因子 + 未来收益 -> 拼接为长面板。

    列: date, code, <FACTOR_COLS>, open, close, fwd_ret_N, fwd_exec_ret_N
    """
    import fetch_kline
    loader = loader or fetch_kline.load_kline
    horizons = horizons or config.HORIZONS
    frames = []
    missing = 0
    for code in codes:
        kl = loader(code)
        if kl is None or len(kl) < config.MIN_LOOKBACK_BARS:
            missing += 1
            continue
        fac = add_forward_returns(compute_factors(kl), horizons)
        fac['code'] = code
        frames.append(fac)
    if not frames:
        raise RuntimeError('无可用 K 线缓存，请先运行 fetch_kline.py')
    panel = pd.concat(frames, ignore_index=True)
    if missing:
        print(f'[build_panel] 跳过 {missing} 只（无缓存/过短）')
    cols = ['date', 'code'] + FACTOR_COLS + ['open', 'close'] \
        + [f'fwd_ret_{n}' for n in horizons] + [f'fwd_exec_ret_{n}' for n in horizons]
    return panel[cols].sort_values(['date', 'code']).reset_index(drop=True)


def main():
    config.force_utf8_stdout()
    config.add_self_to_path()
    import fetch_kline
    import load_archive
    codes = load_archive.get_universe(load_archive.load_archive_panel())
    # 只用已缓存的
    cached = [c for c in codes if fetch_kline.load_kline(c) is not None]
    print(f'已缓存 {len(cached)}/{len(codes)} 只，构建因子面板...')
    panel = build_panel(cached)
    print(f'因子面板: {panel.shape[0]} 行 x {panel.shape[1]} 列，'
          f'{panel["date"].nunique()} 个交易日，{panel["code"].nunique()} 只股票')
    print('因子列:', FACTOR_COLS)
    out = config.OUTPUT_DIR + '/factor_panel_sample.csv'
    panel.tail(2000).to_csv(out, index=False, encoding='utf-8-sig')
    print('样例已保存:', out)


if __name__ == '__main__':
    config.add_self_to_path()
    main()
