#!/usr/bin/env python3
# -*- coding: gbk -*-
"""历史回测（walk-forward 分档）。

无前视：每个再平衡日只用当日已知的 composite 排序分 N 档，持有 horizon 日，
收益用"可执行口径"（次日开盘进、N 日后收盘出，fwd_exec_ret_N）。

产出：
  - 分档单调性（Q1..QN 平均前瞻收益，越高档收益越高=因子有效）；
  - 多空组合(QN-Q1)平均收益 + t 值；
  - 顶档非重叠净值曲线（扣 A 股成本）+ 年化/回撤/胜率/类Sharpe；
  - 指定决策日（10 个归档日）上的分档表现（Q4 "X 天前决策->X 天后验证"）。
"""

import numpy as np
import pandas as pd

import config

# 单次往返成本：买(佣金+过户+滑点) + 卖(佣金+过户+印花+滑点)
ROUND_TRIP_COST = (2 * config.COMMISSION_RATE + 2 * config.TRANSFER_RATE
                   + 2 * config.SLIPPAGE_RATE + config.STAMP_TAX_RATE)


def _labels(scores: pd.Series, n: int) -> pd.Series:
    """按分数秩分成 1..n 档（n=最高档）；对并列稳健。"""
    r = scores.rank(method='first')
    lab = np.ceil(r / len(scores) * n)
    return lab.clip(1, n).astype(int)


def daily_quantile_returns(panel: pd.DataFrame, horizon: int, n: int,
                           score_col: str = 'composite') -> pd.DataFrame:
    """逐日分档的平均前瞻收益。返回 [date, quantile, ret_exec, ret_cc, count]。

    ret_exec: 可执行口径（次日开盘进、N 日后收盘出）
    ret_cc  : 收盘-收盘口径（与 IC 一致），用于对比入场时机差异
    """
    rc = f'fwd_exec_ret_{horizon}'
    cc = f'fwd_ret_{horizon}'
    need = panel[['date', score_col, rc, cc]].dropna()
    rows = []
    for date, g in need.groupby('date', sort=True):
        if len(g) < n * 3:  # 每档至少约 3 只才有意义
            continue
        lab = _labels(g[score_col], n).to_numpy()
        tmp = pd.DataFrame({'q': lab, 're': g[rc].to_numpy(), 'rcc': g[cc].to_numpy()})
        for q, gg in tmp.groupby('q'):
            rows.append((date, int(q), float(gg['re'].mean()),
                         float(gg['rcc'].mean()), len(gg)))
    return pd.DataFrame(rows, columns=['date', 'quantile', 'ret_exec', 'ret_cc', 'count'])


def quantile_monotonicity(daily_q: pd.DataFrame, n: int) -> pd.DataFrame:
    """各档跨日平均收益（可执行与收盘-收盘两口径）+ 样本天数。"""
    agg = daily_q.groupby('quantile').agg(
        avg_ret=('ret_exec', 'mean'), avg_cc=('ret_cc', 'mean'),
        std_ret=('ret_exec', 'std'), n_days=('ret_exec', 'count'))
    agg['avg_ret_pct'] = agg['avg_ret'] * 100
    agg['avg_cc_pct'] = agg['avg_cc'] * 100
    return agg.reindex(range(1, n + 1))


def long_short_series(daily_q: pd.DataFrame, n: int) -> pd.Series:
    """每日 多空(QN-Q1) 收益序列。"""
    piv = daily_q.pivot(index='date', columns='quantile', values='ret_exec')
    if n not in piv.columns or 1 not in piv.columns:
        return pd.Series(dtype=float)
    return (piv[n] - piv[1]).dropna()


def _tstat(x: pd.Series) -> float:
    x = x.dropna()
    if len(x) < 3 or x.std(ddof=1) == 0:
        return np.nan
    return float(x.mean() / x.std(ddof=1) * np.sqrt(len(x)))


def walk_forward_equity(panel: pd.DataFrame, horizon: int, n: int,
                        score_col: str = 'composite') -> dict:
    """顶档非重叠净值：每 horizon 日再平衡一次，扣往返成本。"""
    rc = f'fwd_exec_ret_{horizon}'
    need = panel[['date', score_col, rc]].dropna()
    all_dates = np.array(sorted(need['date'].unique()))
    step_dates = all_dates[::horizon]  # 非重叠
    top_rets, ls_rets = [], []
    used_dates = []
    for date in step_dates:
        g = need[need['date'] == date]
        if len(g) < n * 3:
            continue
        lab = _labels(g[score_col], n)
        r = g[rc].to_numpy()
        top = float(r[lab.to_numpy() == n].mean())
        bot = float(r[lab.to_numpy() == 1].mean())
        top_rets.append(top - ROUND_TRIP_COST)
        ls_rets.append((top - bot) - 2 * ROUND_TRIP_COST)
        used_dates.append(date)
    top_s = pd.Series(top_rets, index=pd.to_datetime(used_dates))
    ls_s = pd.Series(ls_rets, index=pd.to_datetime(used_dates))
    return {
        'top_net': _equity_metrics(top_s, horizon),
        'ls_net': _equity_metrics(ls_s, horizon),
        'top_series': top_s,
        'ls_series': ls_s,
    }


def _equity_metrics(period_ret: pd.Series, horizon: int) -> dict:
    r = period_ret.dropna()
    n = len(r)
    if n == 0:
        return dict(n_periods=0, total_return=np.nan, annual_return=np.nan,
                    annual_vol=np.nan, sharpe=np.nan, max_drawdown=np.nan,
                    win_rate=np.nan, avg_period_ret=np.nan, t_stat=np.nan)
    equity = (1 + r).cumprod()
    total = float(equity.iloc[-1] - 1)
    ppy = 252.0 / horizon
    annual = float(equity.iloc[-1] ** (ppy / n) - 1) if equity.iloc[-1] > 0 else np.nan
    vol = float(r.std(ddof=1) * np.sqrt(ppy)) if n > 1 else np.nan
    sharpe = float(r.mean() * ppy / vol) if vol and vol > 0 else np.nan
    peak = equity.cummax()
    mdd = float(((equity - peak) / peak).min())
    return dict(n_periods=n, total_return=total, annual_return=annual,
                annual_vol=vol, sharpe=sharpe, max_drawdown=mdd,
                win_rate=float((r > 0).mean()), avg_period_ret=float(r.mean()),
                t_stat=_tstat(r))


def quantile_stats_on_dates(panel: pd.DataFrame, dates, horizon: int, n: int,
                            score_col: str = 'composite') -> pd.DataFrame:
    """仅在给定决策日上的分档表现（用于归档日专项验证）。"""
    dset = pd.to_datetime(pd.Series(list(dates))).dt.normalize().unique()
    sub = panel[panel['date'].isin(dset)]
    dq = daily_quantile_returns(sub, horizon, n, score_col)
    if dq.empty:
        return pd.DataFrame()
    return quantile_monotonicity(dq, n)


def run_backtest(panel_with_comp: pd.DataFrame, horizon: int = None,
                 n_quantiles: int = None, score_col: str = 'composite') -> dict:
    """整合：分档单调性 + 多空 + 顶档净值。"""
    horizon = horizon or config.DEFAULT_HORIZON
    n = n_quantiles or config.N_QUANTILES
    dq = daily_quantile_returns(panel_with_comp, horizon, n, score_col)
    mono = quantile_monotonicity(dq, n) if not dq.empty else pd.DataFrame()
    ls = long_short_series(dq, n)
    equity = walk_forward_equity(panel_with_comp, horizon, n, score_col)
    return {
        'horizon': horizon,
        'n_quantiles': n,
        'monotonicity': mono,
        'long_short_mean_pct': float(ls.mean() * 100) if len(ls) else np.nan,
        'long_short_t': _tstat(ls),
        'long_short_days': int(len(ls)),
        'equity': equity,
        'round_trip_cost_pct': ROUND_TRIP_COST * 100,
    }


def main():
    config.force_utf8_stdout()
    config.add_self_to_path()
    import fetch_kline
    import load_archive
    import factors as F
    import ic as ICM
    import multifactor as MF
    codes = load_archive.get_universe(load_archive.load_archive_panel())
    cached = [c for c in codes if fetch_kline.load_kline(c) is not None]
    panel = F.build_panel(cached)
    ic_summary, _ = ICM.compute_ic_table(panel)
    weights = MF.make_weights(ic_summary)
    pc = MF.build_composite(panel, weights, method='ic')
    res = run_backtest(pc)
    print(f"horizon={res['horizon']} 日 | 往返成本 {res['round_trip_cost_pct']:.3f}%")
    print('\n分档平均前瞻收益(可执行):')
    print(res['monotonicity'][['avg_ret_pct', 'n_days']].to_string())
    print(f"\n多空(QN-Q1) 日均 {res['long_short_mean_pct']:.3f}% "
          f"t={res['long_short_t']:.2f} ({res['long_short_days']} 天)")
    tn = res['equity']['top_net']
    print(f"\n顶档净值(扣成本): 年化 {tn['annual_return']*100:.1f}% "
          f"Sharpe {tn['sharpe']:.2f} 回撤 {tn['max_drawdown']*100:.1f}% "
          f"胜率 {tn['win_rate']*100:.1f}% ({tn['n_periods']} 期)")


if __name__ == '__main__':
    config.add_self_to_path()
    main()
