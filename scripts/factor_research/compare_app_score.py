#!/usr/bin/env python3
# -*- coding: gbk -*-
"""与现有 App 评分对比（Q5）+ 归档日专项验证（Q4）。

把 10 个归档日的 App 评分/推荐 与 K 线前瞻收益对齐（避免前视：按 15:00 收盘
规则解析"信息可得的 as-of 交易日"），据此：
  - 计算 App 评分自身的截面 IC（跨归档日汇总）；
  - 在完全相同的样本上计算合成因子 IC，做 head-to-head；
  - 推荐标签 / 评分分箱 的前瞻收益单调性。

注意：归档池偏空/偏观望且仅 10 个日期，显著性有限，仅作 App 专项叠加，
统计权重以 ic.py 的全历史多日轨道为准。
"""

from datetime import time as dtime

import numpy as np
import pandas as pd

import config
import ic as ICM

_MARKET_CLOSE = dtime(15, 0)


def resolve_as_of(archive_time, dates_sorted):
    """归档时刻 -> 信息可得的最近已完成交易日（避免前视）。"""
    T = pd.Timestamp(archive_time)
    if T.time() >= _MARKET_CLOSE:
        cutoff = T.normalize()
    else:
        cutoff = T.normalize() - pd.Timedelta(days=1)
    idx = np.searchsorted(dates_sorted, np.datetime64(cutoff), side='right') - 1
    if idx < 0:
        return None
    return pd.Timestamp(dates_sorted[idx])


def build_join(archive_panel: pd.DataFrame, factor_panel: pd.DataFrame,
               horizons=None) -> pd.DataFrame:
    """归档记录 join 因子面板（按 code + as-of 交易日）。"""
    import fetch_kline
    horizons = horizons or config.HORIZONS
    fp = factor_panel.set_index(['code', 'date'])
    fp = fp[~fp.index.duplicated(keep='last')]
    date_cache = {}
    recs = []
    for _, row in archive_panel.iterrows():
        code = row['code']
        if code not in date_cache:
            kl = fetch_kline.load_kline(code)
            date_cache[code] = None if kl is None else np.sort(kl['date'].to_numpy())
        dates = date_cache[code]
        if dates is None or len(dates) == 0:
            continue
        as_of = resolve_as_of(row['archive_time'], dates)
        if as_of is None or (code, as_of) not in fp.index:
            continue
        fr = fp.loc[(code, as_of)]
        rec = {
            'archive_date': row['archive_date'], 'code': code, 'as_of': as_of,
            'app_score': row.get('app_score'), 'recommendation': row.get('recommendation'),
            'confluence_score': row.get('confluence_score'),
            'composite': float(fr['composite']) if pd.notna(fr['composite']) else np.nan,
        }
        for n in horizons:
            rec[f'fwd_ret_{n}'] = float(fr[f'fwd_ret_{n}']) if pd.notna(fr[f'fwd_ret_{n}']) else np.nan
        recs.append(rec)
    return pd.DataFrame(recs)


def _score_ic_series(join: pd.DataFrame, score_col: str, ret_col: str) -> pd.Series:
    """逐归档日的截面 Spearman IC(score vs fwd_ret)。"""
    out = {}
    for date, g in join.groupby('archive_date'):
        sub = g[[score_col, ret_col]].dropna()
        if len(sub) < config.MIN_CROSS_SECTION:
            continue
        out[date] = ICM._pair_ic(sub[score_col].to_numpy(),
                                 sub[ret_col].to_numpy(), 'spearman')
    return pd.Series(out).dropna().sort_index()


def compare_ic(join: pd.DataFrame, horizon: int = None) -> pd.DataFrame:
    """App 评分 vs 合成因子 在相同样本上的 IC head-to-head。"""
    horizon = horizon or config.DEFAULT_HORIZON
    ret_col = f'fwd_ret_{horizon}'
    rows = []
    for score_col, label in (('app_score', 'App评分'), ('composite', '合成因子'),
                             ('confluence_score', '共振评分')):
        if score_col not in join.columns:
            continue
        s = _score_ic_series(join, score_col, ret_col)
        stat = ICM.summarize(s, horizon)
        stat.update(dict(score=label, horizon=horizon))
        rows.append(stat)
    cols = ['score', 'horizon', 'n_days', 'mean_ic', 'std_ic', 'icir',
            't_stat', 't_nw', 'pos_rate']
    return pd.DataFrame(rows)[cols]


def recommendation_buckets(join: pd.DataFrame, horizon: int = None) -> pd.DataFrame:
    """按 App 推荐标签的前瞻收益。"""
    horizon = horizon or config.DEFAULT_HORIZON
    ret_col = f'fwd_ret_{horizon}'
    g = join.dropna(subset=[ret_col]).groupby('recommendation')[ret_col]
    df = g.agg(['mean', 'median', 'count'])
    df['mean_pct'] = df['mean'] * 100
    df['median_pct'] = df['median'] * 100
    return df.sort_values('mean', ascending=False)[['mean_pct', 'median_pct', 'count']]


def score_buckets(join: pd.DataFrame, horizon: int = None, bins=(0, 4, 5, 6, 7, 11)) -> pd.DataFrame:
    """按 App 评分分箱的前瞻收益（检验分数单调性）。"""
    horizon = horizon or config.DEFAULT_HORIZON
    ret_col = f'fwd_ret_{horizon}'
    sub = join.dropna(subset=[ret_col, 'app_score']).copy()
    sub['bucket'] = pd.cut(sub['app_score'], bins=list(bins), right=False)
    g = sub.groupby('bucket', observed=True)[ret_col]
    df = g.agg(['mean', 'count'])
    df['mean_pct'] = df['mean'] * 100
    return df[['mean_pct', 'count']]


def run_comparison(archive_panel: pd.DataFrame, factor_panel: pd.DataFrame,
                   horizon: int = None) -> dict:
    horizon = horizon or config.DEFAULT_HORIZON
    join = build_join(archive_panel, factor_panel)
    return {
        'horizon': horizon,
        'n_joined': int(len(join)),
        'n_dates': int(join['archive_date'].nunique()) if len(join) else 0,
        'join': join,
        'ic_compare': compare_ic(join, horizon),
        'recommendation_buckets': recommendation_buckets(join, horizon),
        'score_buckets': score_buckets(join, horizon),
    }


def main():
    config.force_utf8_stdout()
    config.add_self_to_path()
    import fetch_kline
    import load_archive
    import factors as F
    import ic as ICM2
    import multifactor as MF
    ap = load_archive.load_archive_panel()
    codes = load_archive.get_universe(ap)
    cached = [c for c in codes if fetch_kline.load_kline(c) is not None]
    panel = F.build_panel(cached)
    ic_summary, _ = ICM2.compute_ic_table(panel)
    weights = MF.make_weights(ic_summary)
    pc = MF.build_composite(panel, weights, method='ic')
    res = run_comparison(ap, pc)
    print(f"归档 join 成功 {res['n_joined']} 行，{res['n_dates']} 个归档日")
    print('\nIC head-to-head:')
    print(res['ic_compare'].to_string(index=False))
    print('\n推荐标签前瞻收益:')
    print(res['recommendation_buckets'].to_string())
    print('\nApp 评分分箱前瞻收益:')
    print(res['score_buckets'].to_string())


if __name__ == '__main__':
    config.add_self_to_path()
    main()
