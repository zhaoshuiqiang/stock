#!/usr/bin/env python3
# -*- coding: gbk -*-
"""汇总级因子分析（零联网降级路径）。

当 K 线缓存不可用（无网络）时，仅用 10 个留档 CSV 自身的字段做"汇总级因子"IC：
  - 因子：App评分 / 共振评分 / 买入信号数 / 卖出信号数 / 活跃战法数 / 净信号(买-卖)
  - 目标：`price_change_pct`（留档价 -> 导出价 的已实现涨跌，CSV 自带，无需联网）
  - 方法：逐归档日截面 Spearman IC -> ic.summarize 汇总

对应计划"假设：网络完全不可用时降级为仅汇总因子分析"。也可独立运行。
"""

import os

import numpy as np
import pandas as pd

import config
import ic as ICM

SUMMARY_FACTORS = {
    'app_score': 'App评分',
    'confluence_score': '共振评分',
    'buy_signals': '买入信号数',
    'sell_signals': '卖出信号数',
    'active_strategies': '活跃战法数',
    'net_signal': '净信号(买-卖)',
}

TARGET = 'price_change_pct'  # 留档->导出 已实现涨跌%（CSV 自带）


def compute(archive_panel: pd.DataFrame) -> pd.DataFrame:
    """逐归档日截面 IC(汇总因子 vs price_change_pct) 的汇总表。"""
    ap = archive_panel.copy()
    if 'buy_signals' in ap.columns and 'sell_signals' in ap.columns:
        ap['net_signal'] = ap['buy_signals'].fillna(0) - ap['sell_signals'].fillna(0)
    rows = []
    for col, label in SUMMARY_FACTORS.items():
        if col not in ap.columns or TARGET not in ap.columns:
            continue
        series = {}
        for date, g in ap.groupby('archive_date'):
            sub = g[[col, TARGET]].dropna()
            if len(sub) < config.MIN_CROSS_SECTION:
                continue
            series[date] = ICM._pair_ic(sub[col].to_numpy(),
                                        sub[TARGET].to_numpy(), 'spearman')
        s = pd.Series(series).dropna().sort_index()
        stat = ICM.summarize(s, horizon=1)
        stat.update(dict(factor=label))
        rows.append(stat)
    if not rows:
        return pd.DataFrame()
    cols = ['factor', 'n_days', 'mean_ic', 'std_ic', 'icir', 't_stat',
            't_nonoverlap', 'cum_ic', 'pos_rate']
    return pd.DataFrame(rows)[cols].sort_values(
        'mean_ic', key=lambda s: s.abs(), ascending=False).reset_index(drop=True)


def report_lines(summary: pd.DataFrame, ap: pd.DataFrame) -> list:
    """生成降级报告的 markdown 行。"""
    from datetime import datetime

    def _f(v, d=4):
        return '—' if v is None or (isinstance(v, float) and not np.isfinite(v)) else f'{v:.{d}f}'

    L = ['# 因子分析研究报告（汇总因子降级版）', '',
         f'生成时间: {datetime.now().strftime("%Y-%m-%d %H:%M")}', '',
         '> 未检测到 K 线缓存（可能网络不可用），已降级为**仅汇总因子分析**：仅用留档 CSV '
         '自带字段，以 `price_change_pct`（留档->导出已实现涨跌）为目标做逐归档日截面 IC。',
         '> 恢复网络并运行 `fetch_kline.py` 后，重跑 `run_factor_research.py` 即得完整技术因子研究。',
         '',
         f'- 归档记录: {len(ap)} 行，{ap["archive_date"].nunique()} 个归档日', '',
         '## 汇总因子 IC（Spearman，逐归档日截面）', '',
         '| 因子 | 均值IC | IC-IR | t | t_非重叠 | IC>0占比 | 归档日数 |',
         '| --- | --- | --- | --- | --- | --- | --- |']
    for _, r in summary.iterrows():
        L.append(f"| {r['factor']} | {_f(r['mean_ic'])} | {_f(r['icir'],3)} | "
                 f"{_f(r['t_stat'],2)} | {_f(r['t_nonoverlap'],2)} | "
                 f"{_f(r['pos_rate']*100,1)}% | {int(r['n_days'])} |")
    L += ['', '> 注：归档日仅约 10 个、且为偏空/偏观望人群，显著性有限；此为无网络时的保底口径，'
          '完整技术因子 IC/回测请在有网络时运行完整管线。', '',
          '---', '*本报告由 scripts/factor_research/summary_factor_analysis.py 生成。*']
    return L


def run_summary_only(archive_panel: pd.DataFrame = None) -> pd.DataFrame:
    import load_archive
    config.ensure_dirs()
    ap = archive_panel if archive_panel is not None else load_archive.load_archive_panel()
    summary = compute(ap)
    out_csv = os.path.join(config.OUTPUT_DIR, 'summary_factor_ic.csv')
    summary.to_csv(out_csv, index=False, encoding='utf-8-sig')
    with open(config.REPORT_PATH, 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(report_lines(summary, ap)))
    print(f'汇总因子 IC 已保存: {out_csv}')
    print(f'降级报告已生成: {config.REPORT_PATH}')
    return summary


def main():
    config.force_utf8_stdout()
    config.add_self_to_path()
    summary = run_summary_only()
    if not summary.empty:
        print(summary.to_string(index=False))


if __name__ == '__main__':
    config.add_self_to_path()
    main()
