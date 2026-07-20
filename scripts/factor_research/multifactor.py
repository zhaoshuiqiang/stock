#!/usr/bin/env python3
# -*- coding: gbk -*-
"""多因子合成。

流程：
  1. 逐日截面标准化（z-score，winsorize 到 +-3；或 rank 百分位）；
     （行业/市值中性化为**可选**，默认关闭——本管线未接入行业/市值数据，见 neutralize()）；
  2. 因子方向对齐：权重带符号（来自 IC），负 IC 因子自动反向；
  3. 三种合成口径：IC 加权 / 等权 / 排名；
  4. 输出带 composite 列的面板，供 ic.py 复算合成 IC、backtest.py 分档。
"""

import numpy as np
import pandas as pd

import config


def make_weights(ic_summary: pd.DataFrame, horizon: int = None,
                 top_k: int = 8, min_abs_ic: float = 0.015) -> dict:
    """从 IC 汇总挑因子并给带符号权重（权重 ∝ 均值 IC，绝对值归一化）。"""
    horizon = horizon or config.DEFAULT_HORIZON
    sub = ic_summary[ic_summary['horizon'] == horizon].copy()
    sub = sub[sub['mean_ic'].abs() >= min_abs_ic]
    sub = sub.dropna(subset=['mean_ic'])
    sub = sub.reindex(sub['mean_ic'].abs().sort_values(ascending=False).index).head(top_k)
    if sub.empty:
        return {}
    denom = sub['mean_ic'].abs().sum()
    if denom <= 0:
        return {}
    return {row['factor']: float(row['mean_ic'] / denom) for _, row in sub.iterrows()}


def _standardize(panel: pd.DataFrame, factors: list, method: str):
    """逐日截面标准化。返回 (base_df, coverage) —— base 列与 factors 对应。"""
    g = panel.groupby('date')
    if method == 'rank':
        base = g[factors].rank(pct=True) - 0.5
    else:  # z-score
        mean = g[factors].transform('mean')
        std = g[factors].transform('std')
        base = ((panel[factors] - mean) / std).clip(-3, 3)
    coverage = base.notna().sum(axis=1)
    return base.fillna(0.0), coverage


def neutralize(base: pd.DataFrame, panel: pd.DataFrame, group_col: str) -> pd.DataFrame:
    """可选：行业/市值中性化——在给定分组(如行业/市值档)内、逐日对标准化因子去均值。

    默认不启用（本管线未接入行业/市值数据）；若 panel 含 group_col 即按
    (date, group) 去均值，剥离行业/市值风格暴露。
    """
    if group_col not in panel.columns:
        return base
    keys = [panel['date'], panel[group_col]] if 'date' in panel.columns else [panel[group_col]]
    return base.sub(base.groupby(keys).transform('mean'))


def build_composite(panel: pd.DataFrame, weights: dict,
                    method: str = 'ic', min_coverage: float = 0.5,
                    neutralize_group_col: str = None) -> pd.DataFrame:
    """按权重合成 composite 列。method: 'ic'|'equal'|'rank'。

    min_coverage: 单只当日至少覆盖多少比例的入选因子，否则 composite 置 NaN。
    neutralize_group_col: 可选，提供则先做行业/市值中性化（默认 None=不启用）。
    """
    factors = list(weights.keys())
    if not factors:
        out = panel.copy()
        out['composite'] = np.nan
        return out
    base_method = 'rank' if method == 'rank' else 'z'
    base, coverage = _standardize(panel, factors, base_method)
    if neutralize_group_col:  # 可选中性化
        base = neutralize(base, panel, neutralize_group_col)

    if method == 'equal':
        wvec = pd.Series({f: float(np.sign(weights[f])) / len(factors) for f in factors})
    else:  # 'ic' or 'rank' 都用带符号 IC 权重
        wvec = pd.Series(weights)

    comp = base.mul(wvec, axis=1).sum(axis=1)
    # 覆盖不足置 NaN（避免全缺失股票被当中性分参与排序）
    need = max(1, int(np.ceil(min_coverage * len(factors))))
    comp = comp.where(coverage >= need, np.nan)

    out = panel.copy()
    out['composite'] = comp
    return out


def composite_ic(panel_with_comp: pd.DataFrame, horizons=None):
    """复算 composite 的截面 IC 汇总（复用 ic 模块）。"""
    import ic as ICM
    horizons = horizons or config.HORIZONS
    sp = ICM.compute_ic_series(panel_with_comp, ['composite'], horizons, method='spearman')
    rows = []
    for n in horizons:
        stat = ICM.summarize(sp.get(('composite', n), pd.Series(dtype=float)), n)
        stat.update(dict(factor='composite', horizon=n))
        rows.append(stat)
    cols = ['factor', 'horizon', 'n_days', 'mean_ic', 'std_ic', 'icir',
            't_stat', 't_nw', 'pos_rate', 'ic_abs_mean']
    return pd.DataFrame(rows)[cols]


def build_all_composites(panel: pd.DataFrame, ic_summary: pd.DataFrame,
                         horizon: int = None, top_k: int = 8):
    """一次性产出三种口径的合成 IC 对比 + 入选权重。

    返回 (weights, {method: composite_ic_df}, {method: panel_with_comp})。
    """
    horizon = horizon or config.DEFAULT_HORIZON
    weights = make_weights(ic_summary, horizon, top_k=top_k)
    ic_by_method, panel_by_method = {}, {}
    for method in ('ic', 'equal', 'rank'):
        p = build_composite(panel, weights, method=method)
        panel_by_method[method] = p
        ic_by_method[method] = composite_ic(p)
    return weights, ic_by_method, panel_by_method


def main():
    config.force_utf8_stdout()
    config.add_self_to_path()
    import fetch_kline
    import load_archive
    import factors as F
    import ic as ICM
    codes = load_archive.get_universe(load_archive.load_archive_panel())
    cached = [c for c in codes if fetch_kline.load_kline(c) is not None]
    panel = F.build_panel(cached)
    ic_summary, _ = ICM.compute_ic_table(panel)
    weights, ic_by_method, _ = build_all_composites(panel, ic_summary)
    print('入选因子与权重(带符号):')
    for f, w in weights.items():
        print(f'  {f:14s} {w:+.3f}')
    print('\n各口径合成因子 IC:')
    for m, df in ic_by_method.items():
        row = df[df['horizon'] == config.DEFAULT_HORIZON].iloc[0]
        print(f"  {m:6s} mean_ic={row['mean_ic']:+.4f} icir={row['icir']:+.3f} "
              f"t={row['t_stat']:+.2f} pos={row['pos_rate']:.2f}")


if __name__ == '__main__':
    config.add_self_to_path()
    main()
