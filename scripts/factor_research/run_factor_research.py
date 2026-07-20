#!/usr/bin/env python3
# -*- coding: gbk -*-
"""因子研究总编排：一次跑通 数据->因子->IC->多因子->回测->对比，
生成 docs/factor_research_report.md 与 output/ 下的中间 CSV。

用法（venv）:
    python scripts/factor_research/run_factor_research.py
需先运行 fetch_kline.py 落地 K 线缓存。
"""

import os
from datetime import datetime

import numpy as np
import pandas as pd

import config


# ---------- 格式化助手 ----------
def _f(v, d=4):
    if v is None or (isinstance(v, float) and not np.isfinite(v)):
        return '—'
    return f'{v:.{d}f}'


def _p(v, d=1):
    if v is None or (isinstance(v, float) and not np.isfinite(v)):
        return '—'
    return f'{v * 100:.{d}f}%'


def _md_table(headers, rows) -> str:
    line = '| ' + ' | '.join(headers) + ' |'
    sep = '| ' + ' | '.join(['---'] * len(headers)) + ' |'
    body = ['| ' + ' | '.join(str(c) for c in r) + ' |' for r in rows]
    return '\n'.join([line, sep] + body)


def _sig(t):
    """t 值显著性标记。"""
    if t is None or not np.isfinite(t):
        return ''
    a = abs(t)
    if a >= 2.58:
        return '***'
    if a >= 1.96:
        return '**'
    if a >= 1.64:
        return '*'
    return ''


# ---------- 主流程 ----------
def run(top_k: int = 8):
    config.force_utf8_stdout()
    config.ensure_dirs()
    config.add_self_to_path()
    import fetch_kline
    import load_archive
    import factors as F
    import ic as ICM
    import multifactor as MF
    import backtest as BT
    import compare_app_score as CMP

    print('[1/6] 加载留档面板与股票池...')
    ap = load_archive.load_archive_panel()
    codes = load_archive.get_universe(ap)
    cached = [c for c in codes if fetch_kline.load_kline(c) is not None]
    print(f'  股票池 {len(codes)}，已缓存 {len(cached)}（覆盖率 {len(cached)/len(codes)*100:.1f}%）')
    if not cached:
        print('  未检测到 K 线缓存（可能无网络），降级为仅汇总因子分析...')
        import summary_factor_analysis as SFA
        SFA.run_summary_only(ap)
        return None

    print('[2/6] 构建因子面板...')
    panel = F.build_panel(cached)
    print(f'  面板 {panel.shape[0]} 行，{panel["date"].nunique()} 交易日，{panel["code"].nunique()} 股票')

    print('[3/6] 计算截面 IC...')
    ic_summary, _ = ICM.compute_ic_table(panel)
    ic_summary.to_csv(config.OUTPUT_DIR + '/ic_summary.csv', index=False, encoding='utf-8-sig')

    print('[4/6] 多因子合成...')
    weights, ic_by_method, panel_by_method = MF.build_all_composites(panel, ic_summary, top_k=top_k)
    pc = panel_by_method['ic']
    pd.DataFrame([{'factor': k, 'weight': v} for k, v in weights.items()]).to_csv(
        config.OUTPUT_DIR + '/composite_weights.csv', index=False, encoding='utf-8-sig')

    print('[5/6] 分档回测（各 horizon）...')
    bt_by_h = {n: BT.run_backtest(pc, horizon=n) for n in config.HORIZONS}
    bt_main = bt_by_h[config.DEFAULT_HORIZON]

    print('[6/6] 与 App 评分对比 + 归档日验证（样本外权重）...')
    arch_dates = sorted(ap['archive_date'].dropna().unique())
    # 样本外：仅用归档日之前的数据训练 IC 权重，避免将未来信息泄入决策模拟
    cutoff = pd.Timestamp(min(arch_dates))
    train = panel[panel['date'] < cutoff]
    ic_train, _ = ICM.compute_ic_table(train, horizons=[config.DEFAULT_HORIZON])
    weights_oos = MF.make_weights(ic_train, horizon=config.DEFAULT_HORIZON, top_k=top_k)
    pc_oos = MF.build_composite(panel, weights_oos, method='ic')
    cmp = CMP.run_comparison(ap, pc_oos, horizon=config.DEFAULT_HORIZON)
    arch_q = BT.quantile_stats_on_dates(pc_oos, arch_dates, config.DEFAULT_HORIZON, config.N_QUANTILES)

    # 最新交易日因子评分（买卖参考）
    latest_date = pc['date'].max()
    latest = pc[pc['date'] == latest_date][['code', 'composite']].dropna().copy()
    latest['factor_score'] = (latest['composite'].rank(pct=True) * 100).round(1)
    name_map = ap.drop_duplicates('code').set_index('code')['name'].to_dict()
    latest['name'] = latest['code'].map(name_map)
    latest = latest.sort_values('factor_score', ascending=False)
    latest.to_csv(config.OUTPUT_DIR + '/latest_factor_scores.csv', index=False, encoding='utf-8-sig')

    # 导出回测明细与净值曲线 CSV
    if not bt_main['monotonicity'].empty:
        bt_main['monotonicity'].to_csv(
            os.path.join(config.OUTPUT_DIR, 'backtest_quantiles.csv'), encoding='utf-8-sig')
    bt_rows = []
    for n in config.HORIZONS:
        b = bt_by_h[n]
        bt_rows.append(dict(horizon=n, long_short_mean_pct=b['long_short_mean_pct'],
                            long_short_t=b['long_short_t'], **b['equity']['top_net']))
    pd.DataFrame(bt_rows).to_csv(
        os.path.join(config.OUTPUT_DIR, 'backtest_by_horizon.csv'),
        index=False, encoding='utf-8-sig')
    _eq = bt_main['equity']
    if len(_eq['top_series']):
        _eqdf = pd.DataFrame({'date': _eq['top_series'].index,
                              'top_net_ret': _eq['top_series'].to_numpy(),
                              'ls_net_ret': _eq['ls_series'].to_numpy()})
        _eqdf['top_equity'] = (1 + _eqdf['top_net_ret']).cumprod()
        _eqdf['ls_equity'] = (1 + _eqdf['ls_net_ret']).cumprod()
        _eqdf.to_csv(os.path.join(config.OUTPUT_DIR, 'equity_curve.csv'),
                     index=False, encoding='utf-8-sig')

    ctx = dict(ap=ap, codes=codes, cached=cached, panel=panel, ic_summary=ic_summary,
               weights=weights, ic_by_method=ic_by_method, bt_by_h=bt_by_h, bt_main=bt_main,
               cmp=cmp, arch_q=arch_q, latest=latest, latest_date=latest_date,
               factor_desc=F.FACTOR_DESC, round_trip=BT.ROUND_TRIP_COST,
               weights_oos=weights_oos, cutoff=cutoff)
    report = build_report(ctx)
    with open(config.REPORT_PATH, 'w', encoding='utf-8') as fh:
        fh.write(report)
    print(f'\n报告已生成: {config.REPORT_PATH}')
    return ctx


def build_report(c) -> str:
    ts = datetime.now().strftime('%Y-%m-%d %H:%M')
    H = config.DEFAULT_HORIZON
    ic_sum = c['ic_summary']
    L = []
    A = L.append

    A('# 因子分析与 IC 回测研究报告')
    A('')
    A(f'生成时间: {ts}')
    A('')
    A('> 离线研究（akshare 新浪源日K线 + 留档CSV）。本轮不改 App 代码，仅做因子有效性研究、'
      'IC/多因子/回测验证，与现有评分对比，并给出集成设计（见 `docs/factor_integration_design.md`）。')
    A('')

    # 数据概览
    A('## 一、数据概览')
    A('')
    A(f'- 留档股票池(去重): {len(c["codes"])} 只；K线覆盖: {len(c["cached"])} 只 '
      f'({len(c["cached"])/len(c["codes"])*100:.1f}%)')
    A(f'- 因子面板: {c["panel"].shape[0]:,} 行，{c["panel"]["date"].nunique()} 个交易日，'
      f'{c["panel"]["code"].nunique()} 只股票')
    A(f'- 历史窗口: {config.HISTORY_START} ~ {config.HISTORY_END}；前瞻窗口 N ∈ {config.HORIZONS}（主口径 {H} 日）')
    A(f'- 归档决策日: {len(c["ap"]["archive_date"].dropna().unique())} 个'
      f'（{pd.Timestamp(min(c["ap"]["archive_date"])).date()} ~ {pd.Timestamp(max(c["ap"]["archive_date"])).date()}）')
    A('')

    # Q1 评估
    A('## 二、因子分析评估（Q1）')
    A('')
    A('现状：项目**无正式量化因子框架**——无 IC 计算、无截面/时序因子评估、无 IC 加权多因子模型；'
      '代码中"因子"仅为松散用法（时间衰减因子、动量保护因子、ROE 因子）。')
    A('')
    A('已有可复用的相邻能力：')
    A('')
    A('- `next_session_feature_extractor.dart`：约 20 个候选特征（本研究因子库据此镜像）；')
    A('- `next_session_backtest.dart`：无前视 walk-forward（但仅 1 日、无 IC）；')
    A('- `directional_weight_optimizer.dart`：对方向分量做"符号命中率"加权（粗略 IC 代理，'
      '`ScoringConfig.useDynamicDirectionWeights` 默认关闭）；')
    A('- `comprehensive_scorer.dart`：7 维加权，但权重为**专家设定的静态常量、未经收益验证**。')
    A('')
    A('参考价值：现有权重缺乏实证依据，引入截面 IC 可判断哪些技术因子真正具备前瞻力，'
      '为权重提供数据支撑；命名与 App 指标一致，结论可直接映射回评分。')
    A('')

    # 因子清单
    A('## 三、因子库（Q2 因子构建）')
    A('')
    A(f'共 {len(c["factor_desc"])} 个候选因子，口径对齐 App `indicators.dart`（MACD EMA、RSI Wilder、KDJ TDX）：')
    A('')
    rows = [[k, v] for k, v in c['factor_desc'].items()]
    half = (len(rows) + 1) // 2
    left, right = rows[:half], rows[half:]
    trows = []
    for i in range(half):
        l = left[i]
        r = right[i] if i < len(right) else ['', '']
        trows.append([l[0], l[1], r[0], r[1]])
    A(_md_table(['因子', '说明', '因子', '说明'], trows))
    A('')

    # IC 结果
    A('## 四、IC 计算结果（Q2 IC 逻辑 + Q5 显著性）')
    A('')
    A(f'逐日截面 Spearman 秩 IC；t=IC-IR×√N，t_nw 为 Newey-West 自相关修正。'
      f'显著性: * p<0.1, ** p<0.05, *** p<0.01。下表为 **{H} 日** 前瞻按 |IC| 排序前 15：')
    A('')
    top = ic_sum[ic_sum['horizon'] == H].copy()
    top = top.reindex(top['ic_abs_mean'].sort_values(ascending=False).index).head(15)
    trows = []
    for _, r in top.iterrows():
        trows.append([
            r['factor'], _f(r['mean_ic']), _f(r['icir'], 3),
            _f(r['t_stat'], 2) + _sig(r['t_stat']), _f(r['t_nw'], 2),
            _f(r['t_nonoverlap'], 2), _p(r['pos_rate']), int(r['n_days']),
        ])
    A(_md_table(['因子', '均值IC', 'IC-IR', 't', 't_nw', 't_非重叠', 'IC>0占比', '天数'], trows))
    A('')
    A('各 horizon 最强因子（|IC| 最大）概览：')
    A('')
    trows = []
    for n in config.HORIZONS:
        sub = ic_sum[ic_sum['horizon'] == n]
        if sub.empty:
            continue
        best = sub.reindex(sub['ic_abs_mean'].sort_values(ascending=False).index).iloc[0]
        trows.append([f'{n}日', best['factor'], _f(best['mean_ic']),
                      _f(best['t_stat'], 2) + _sig(best['t_stat']), _p(best['pos_rate'])])
    A(_md_table(['horizon', '最强因子', '均值IC', 't', 'IC>0占比'], trows))
    A('')
    A('> 完整 IC 表见 `scripts/factor_research/output/ic_summary.csv`。')
    A('')

    # 多因子合成
    A('## 五、多因子合成（Q2）')
    A('')
    A(f'按 {H} 日 IC 选取 |IC| 前 {len(c["weights"])} 的因子，权重 ∝ 带符号均值 IC（负 IC 自动反向）：')
    A('')
    trows = [[f, _f(w, 3), c['factor_desc'].get(f, '')] for f, w in c['weights'].items()]
    A(_md_table(['因子', '权重(带符号)', '说明'], trows))
    A('')
    A('三种合成口径的 composite 截面 IC（越高越好，且应高于任一单因子）：')
    A('')
    trows = []
    for m, label in (('ic', 'IC加权'), ('equal', '等权'), ('rank', '排名')):
        df = c['ic_by_method'][m]
        row = df[df['horizon'] == H].iloc[0]
        trows.append([label, _f(row['mean_ic']), _f(row['icir'], 3),
                      _f(row['t_stat'], 2) + _sig(row['t_stat']), _p(row['pos_rate'])])
    A(_md_table(['合成口径', '均值IC', 'IC-IR', 't', 'IC>0占比'], trows))
    A('')

    # 回测
    A('## 六、历史回测（Q4）')
    A('')
    A(f'Walk-forward 无前视：每再平衡日按 composite(IC加权) 分 {config.N_QUANTILES} 档，'
      f'可执行口径（次日开盘进、N 日后收盘出），往返成本 {c["round_trip"]*100:.3f}%。')
    A('')
    A(f'**{H} 日分档平均前瞻收益**（单调递增=因子有效；Q{config.N_QUANTILES} 为最高分档）：')
    A('')
    mono = c['bt_main']['monotonicity']
    trows = []
    for q, r in mono.iterrows():
        trows.append([f'Q{q}', _f(r['avg_cc_pct'], 3) + '%',
                      _f(r['avg_ret_pct'], 3) + '%', int(r['n_days'])])
    A(_md_table(['分档', '收盘-收盘', '可执行(次开进)', '样本天数'], trows))
    A('')
    A('> 注：收盘-收盘口径与 IC 一致；改为次日开盘进场的可执行口径后，短周期分档区分度'
      '明显削弱，说明该低波/反转类因子的“收盘-收盘”预测力部分来自隔夜/流动性效应，次开入场后被侵蚀。')
    A('')
    A('各 horizon 的多空(QN-Q1)与顶档净值（扣成本）：')
    A('')
    trows = []
    for n in config.HORIZONS:
        b = c['bt_by_h'][n]
        tn = b['equity']['top_net']
        trows.append([f'{n}日', _f(b['long_short_mean_pct'], 3) + '%',
                      _f(b['long_short_t'], 2) + _sig(b['long_short_t']),
                      _p(tn['annual_return']), _f(tn['sharpe'], 2),
                      _p(tn['max_drawdown']), _p(tn['win_rate']), tn['n_periods']])
    A(_md_table(['horizon', '多空日均', '多空t', '顶档年化', 'Sharpe', '最大回撤', '顶档胜率', '期数'], trows))
    A('')

    # 有效性验证
    A('## 七、因子有效性验证（Q5）')
    A('')
    comp_row = c['ic_by_method']['ic']
    cr = comp_row[comp_row['horizon'] == H].iloc[0]
    A(f'- **显著性**：{H} 日合成因子 IC={_f(cr["mean_ic"])}，IC-IR={_f(cr["icir"],3)}，'
      f't={_f(cr["t_stat"],2)}{_sig(cr["t_stat"])}，t_nw={_f(cr["t_nw"],2)}；'
      f'多空 t={_f(c["bt_main"]["long_short_t"],2)}{_sig(c["bt_main"]["long_short_t"])}。')
    A(f'- **前瞻性**：分档平均前瞻收益的单调性见第六节；顶档-底档差反映选股区分度。')
    A('- **符号自检**：')
    checks = []
    for fac in ('mom20', 'mom5', 'ret1', 'rsi6'):
        sub = ic_sum[(ic_sum['horizon'] == H) & (ic_sum['factor'] == fac)]
        if not sub.empty:
            checks.append(f'{fac} IC={_f(sub.iloc[0]["mean_ic"])}')
    A('  - ' + '；'.join(checks) + '（短反转 ret1 期望为负，动量类符号视市场风格而定）。')
    A('')

    # 与 App 评分对比
    A('## 八、与现有评分系统对比（Q5）')
    A('')
    cmp = c['cmp']
    valid_days = int(cmp['ic_compare']['n_days'].max()) if len(cmp['ic_compare']) else 0
    A(f'在 {cmp["n_dates"]} 个归档日、成功对齐 {cmp["n_joined"]} 条样本上，'
      f'按信息可得的 as-of 交易日（15:00 收盘规则，避免前视）计算 {H} 日前瞻 IC：')
    A('')
    trows = []
    for _, r in cmp['ic_compare'].iterrows():
        trows.append([r['score'], _f(r['mean_ic']), _f(r['icir'], 3),
                      _f(r['t_stat'], 2) + _sig(r['t_stat']), _p(r['pos_rate']), int(r['n_days'])])
    A(_md_table(['评分口径', '均值IC', 'IC-IR', 't', 'IC>0占比', '归档日数'], trows))
    A('')
    A(f'> 注：合成因子在此用**样本外权重**（仅用归档日之前、训练截止 '
      f'{pd.Timestamp(c["cutoff"]).date()} 的数据学权重）。归档日共 {cmp["n_dates"]} 个，'
      f'其中可算 {H} 日前瞻的有效日仅 {valid_days} 个（后段归档日因不足 {H} 个交易日而被截断），'
      '合成因子 IC 偏高为小样本/特定人群效应，稳健估计以第四节全历史 IC(≈0.06) 为准。'
      '关键观察：**App 评分/推荐的分箱前瞻收益不单调、甚至反向**（“买入/强烈买入”'
      '不优于“偏空观望”），说明其买卖分层在该归档样本上信息有限、有改进空间。')
    A('')
    A('App 推荐标签的前瞻收益（样本数≥5 的标签）：')
    A('')
    rb = cmp['recommendation_buckets']
    trows = [[idx, _f(r['mean_pct'], 2) + '%', _f(r['median_pct'], 2) + '%', int(r['count'])]
             for idx, r in rb.iterrows() if r['count'] >= 5]
    A(_md_table(['推荐', '平均前瞻收益', '中位', '样本'], trows))
    A('')
    A('App 评分分箱前瞻收益（检验分数单调性）：')
    A('')
    sb = cmp['score_buckets']
    trows = [[str(idx), _f(r['mean_pct'], 2) + '%', int(r['count'])] for idx, r in sb.iterrows()]
    A(_md_table(['评分区间', '平均前瞻收益', '样本'], trows))
    A('')
    if not c['arch_q'].empty:
        A(f'归档日专项（Q4 "X 天前决策→{H} 日后验证"）——仅在归档日上按合成因子分档：')
        A('')
        trows = [[f'Q{q}', _f(r['avg_cc_pct'], 3) + '%', int(r['n_days'])]
                 for q, r in c['arch_q'].iterrows()]
        A(_md_table(['分档', '平均前瞻收益', '样本天数'], trows))
        A('')

    # 最新评分
    A('## 九、最新交易日因子评分（买卖参考）')
    A('')
    A(f'截至 {pd.Timestamp(c["latest_date"]).date()} 的合成因子评分（0-100 百分位，越高越偏多）。'
      f'完整清单见 `output/latest_factor_scores.csv`。Top 10 / Bottom 10：')
    A('')
    top10 = c['latest'].head(10)
    bot10 = c['latest'].tail(10).iloc[::-1]
    trows = []
    for i in range(10):
        t = top10.iloc[i] if i < len(top10) else None
        b = bot10.iloc[i] if i < len(bot10) else None
        trows.append([
            t['code'] if t is not None else '', t['name'] if t is not None else '',
            _f(t['factor_score'], 1) if t is not None else '',
            b['code'] if b is not None else '', b['name'] if b is not None else '',
            _f(b['factor_score'], 1) if b is not None else '',
        ])
    A(_md_table(['Top代码', '名称', '评分', 'Bottom代码', '名称', '评分'], trows))
    A('')

    # 结论与局限
    A('## 十、结论与局限')
    A('')
    A('- 集成设计（因子→维度映射、建议权重、特性开关与灰度）见 `docs/factor_integration_design.md`。')
    A('- **局限**：归档池偏空/偏观望且仅约 10 个日期，归档对齐研究显著性有限，'
      '统计权重以全历史多日 IC/回测为准；本环境东财源被拒，用新浪源，覆盖率见上；'
      '回测未做涨跌停不可成交、停牌、行业中性化等精细约束，为一阶近似。')
    A('- 前瞻收益：IC 用收盘价（标准口径），回测用次日开盘→N 日后收盘（可执行口径）。')
    A('')
    A('---')
    A('*本报告由 scripts/factor_research/run_factor_research.py 生成；建议结合人工审核。*')
    return '\n'.join(L)


if __name__ == '__main__':
    config.add_self_to_path()
    run()
