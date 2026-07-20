#!/usr/bin/env python3
# -*- coding: gbk -*-
"""IC（信息系数）计算与显著性。

对因子长面板做逐日截面 IC：
  - Spearman 秩 IC（主口径）与 Pearson 常规 IC（对照）；
  - 汇总 IC 均值/标准差、IC-IR=均值/std、t=IR*sqrt(N)、IC>0 占比；
  - Newey-West 自相关修正 t 值（前瞻窗口重叠导致 IC 序列自相关）。

纯 numpy/pandas 实现，不依赖 scipy。
"""

import numpy as np
import pandas as pd

import config


def _rank(x: np.ndarray) -> np.ndarray:
    """平均秩（等价 scipy.rankdata 'average'），用 pandas 实现。"""
    return pd.Series(x).rank(method='average').to_numpy()


def _corr(x: np.ndarray, y: np.ndarray) -> float:
    if len(x) < config.MIN_CROSS_SECTION:
        return np.nan
    sx, sy = x.std(), y.std()
    if sx == 0 or sy == 0 or not np.isfinite(sx) or not np.isfinite(sy):
        return np.nan
    return float(np.corrcoef(x, y)[0, 1])


def _pair_ic(fv: np.ndarray, rv: np.ndarray, method: str) -> float:
    """单日单因子截面 IC。fv/rv 已对齐、无 NaN。"""
    if method == 'spearman':
        return _corr(_rank(fv), _rank(rv))
    return _corr(fv, rv)


def newey_west_tstat(x, lag: int) -> float:
    """IC 序列均值的 Newey-West 修正 t 值（HAC 标准误）。"""
    x = np.asarray(x, dtype=float)
    x = x[np.isfinite(x)]
    n = len(x)
    if n < 3:
        return np.nan
    mu = x.mean()
    e = x - mu
    gamma0 = float(e @ e) / n
    var = gamma0
    max_lag = min(lag, n - 1)
    for k in range(1, max_lag + 1):
        w = 1.0 - k / (lag + 1)
        cov = float(e[k:] @ e[:-k]) / n
        var += 2.0 * w * cov
    if var <= 0:
        return np.nan
    se = np.sqrt(var / n)
    return mu / se if se > 0 else np.nan


def compute_ic_series(panel: pd.DataFrame, factors, horizons, method='spearman') -> dict:
    """逐日截面 IC 序列。返回 {(factor, horizon): pd.Series(index=date)}。"""
    ret_cols = {n: f'fwd_ret_{n}' for n in horizons}
    acc = {(f, n): {} for f in factors for n in horizons}
    for date, g in panel.groupby('date', sort=True):
        for n in horizons:
            rv_all = g[ret_cols[n]].to_numpy()
            for f in factors:
                fv_all = g[f].to_numpy()
                mask = np.isfinite(fv_all) & np.isfinite(rv_all)
                if mask.sum() < config.MIN_CROSS_SECTION:
                    continue
                acc[(f, n)][date] = _pair_ic(fv_all[mask], rv_all[mask], method)
    return {key: pd.Series(d).dropna().sort_index() for key, d in acc.items()}


def summarize(series: pd.Series, horizon: int) -> dict:
    """把一条 IC 序列汇总为统计指标。

    t_stat        : IC-IR*sqrt(N)（全量，受重叠窗口自相关影响而偏乐观）
    t_nw          : Newey-West HAC 修正 t（对重叠引起的自相关修正）
    t_nonoverlap  : 非重叠采样 t（每 horizon 日取 1，统计独立）
    cum_ic        : 累计 IC（IC 序列之和）
    """
    s = series.dropna()
    n = len(s)
    if n == 0:
        return dict(n_days=0, mean_ic=np.nan, std_ic=np.nan, icir=np.nan,
                    t_stat=np.nan, t_nw=np.nan, t_nonoverlap=np.nan, cum_ic=np.nan,
                    pos_rate=np.nan, ic_abs_mean=np.nan)
    mean_ic = float(s.mean())
    std_ic = float(s.std(ddof=1)) if n > 1 else np.nan
    icir = mean_ic / std_ic if std_ic and std_ic > 0 else np.nan
    t_stat = icir * np.sqrt(n) if icir == icir else np.nan
    t_nw = newey_west_tstat(s.to_numpy(), lag=min(horizon, config.NEWEY_WEST_MAX_LAG))
    # 非重叠采样：每 horizon 个取 1，规避重叠窗口自相关
    non = s.iloc[::max(1, horizon)]
    n_no = len(non)
    if n_no > 1 and non.std(ddof=1) and non.std(ddof=1) > 0:
        t_nonoverlap = float(non.mean() / non.std(ddof=1) * np.sqrt(n_no))
    else:
        t_nonoverlap = np.nan
    return dict(n_days=n, mean_ic=mean_ic, std_ic=std_ic, icir=icir,
                t_stat=t_stat, t_nw=t_nw, t_nonoverlap=t_nonoverlap,
                cum_ic=float(s.sum()),
                pos_rate=float((s > 0).mean()), ic_abs_mean=float(s.abs().mean()))


def compute_ic_table(panel: pd.DataFrame, factors=None, horizons=None):
    """主入口：返回 (summary_df, spearman_series_dict)。

    summary_df 每行 = (factor, horizon) 的 Spearman 统计 + Pearson 均值对照。
    """
    from factors import FACTOR_COLS
    factors = factors or FACTOR_COLS
    horizons = horizons or config.HORIZONS

    sp = compute_ic_series(panel, factors, horizons, method='spearman')
    pe = compute_ic_series(panel, factors, horizons, method='pearson')

    rows = []
    for f in factors:
        for n in horizons:
            stat = summarize(sp.get((f, n), pd.Series(dtype=float)), n)
            pe_series = pe.get((f, n), pd.Series(dtype=float)).dropna()
            stat.update(dict(
                factor=f, horizon=n,
                mean_ic_pearson=float(pe_series.mean()) if len(pe_series) else np.nan,
            ))
            rows.append(stat)
    cols = ['factor', 'horizon', 'n_days', 'mean_ic', 'std_ic', 'icir',
            't_stat', 't_nw', 't_nonoverlap', 'cum_ic', 'pos_rate',
            'ic_abs_mean', 'mean_ic_pearson']
    summary = pd.DataFrame(rows)[cols].sort_values(
        ['horizon', 'ic_abs_mean'], ascending=[True, False]).reset_index(drop=True)
    return summary, sp


def main():
    config.force_utf8_stdout()
    config.add_self_to_path()
    import fetch_kline
    import load_archive
    import factors as F
    codes = load_archive.get_universe(load_archive.load_archive_panel())
    cached = [c for c in codes if fetch_kline.load_kline(c) is not None]
    print(f'构建面板（{len(cached)} 只已缓存）...')
    panel = F.build_panel(cached)
    print('计算 IC...')
    summary, _ = compute_ic_table(panel)
    out = config.OUTPUT_DIR + '/ic_summary.csv'
    summary.to_csv(out, index=False, encoding='utf-8-sig')
    print(f'IC 汇总已保存: {out}')
    # 打印 horizon=5 前 12 名
    h = config.DEFAULT_HORIZON
    top = summary[summary['horizon'] == h].reindex(
        summary[summary['horizon'] == h]['ic_abs_mean'].sort_values(ascending=False).index).head(12)
    print(f'\nhorizon={h} 日 |IC| 前 12 名:')
    print(top[['factor', 'mean_ic', 'icir', 't_stat', 't_nw', 'pos_rate', 'n_days']].to_string(index=False))


if __name__ == '__main__':
    config.add_self_to_path()
    main()
