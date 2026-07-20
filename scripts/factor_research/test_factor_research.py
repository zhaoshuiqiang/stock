#!/usr/bin/env python3
# -*- coding: gbk -*-
"""因子研究管线的数学自检。

可用 pytest 运行，也可直接 `python test_factor_research.py`（无需安装 pytest）。
全部使用合成数据，不依赖网络/缓存。
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np
import pandas as pd

import ic as ICM
import factors as F
import multifactor as MF
import backtest as BT
import compare_app_score as CMP
import summary_factor_analysis as SFA


def test_pair_ic_spearman_monotone():
    # 完全同序 -> +1；完全反序 -> -1
    x = np.array([1., 2, 3, 4, 5, 6])
    y = np.array([10., 20, 30, 40, 50, 60])
    assert abs(ICM._pair_ic(x, y, 'spearman') - 1.0) < 1e-9
    assert abs(ICM._pair_ic(x, y[::-1], 'spearman') + 1.0) < 1e-9


def test_pair_ic_nonlinear_spearman_beats_pearson():
    # 单调非线性：spearman=1，pearson<1
    x = np.array([1., 2, 3, 4, 5, 6])
    y = x ** 3
    assert abs(ICM._pair_ic(x, y, 'spearman') - 1.0) < 1e-9
    assert ICM._pair_ic(x, y, 'pearson') < 1.0


def test_newey_west_constant_is_nan():
    assert not np.isfinite(ICM.newey_west_tstat(np.ones(30), lag=5))


def test_newey_west_positive_mean_positive_t():
    rng = np.random.default_rng(0)
    x = rng.normal(0.05, 0.1, 200)  # 正均值
    t = ICM.newey_west_tstat(x, lag=5)
    assert np.isfinite(t) and t > 2


def test_cross_sectional_ic_perfect():
    # 构造两日，每日因子与未来收益完全同序 -> IC=1
    rows = []
    for d in ('2026-01-05', '2026-01-06'):
        for i in range(6):
            rows.append(dict(date=pd.Timestamp(d), code=f'sh60000{i}',
                             fac=float(i), fwd_ret_5=float(i) * 0.01))
    panel = pd.DataFrame(rows)
    sp = ICM.compute_ic_series(panel, ['fac'], [5], 'spearman')
    series = sp[('fac', 5)]
    assert len(series) == 2
    assert (series - 1.0).abs().max() < 1e-9


def test_factor_momentum_and_ret1():
    n = 70
    dates = pd.date_range('2024-01-01', periods=n, freq='B')
    close = pd.Series(np.linspace(10, 24, n))  # 单调上涨
    kl = pd.DataFrame(dict(date=dates, open=close, high=close * 1.01,
                           low=close * 0.99, close=close,
                           volume=np.full(n, 1e6), amount=close * 1e6,
                           turnover=np.full(n, 0.01)))
    fac = F.compute_factors(kl)
    # 上涨序列：mom5>0, ret1>0
    assert fac['mom5'].iloc[-1] > 0
    assert fac['ret1'].iloc[-1] > 0
    # close_pos 在 [0,1]
    assert 0.0 <= fac['close_pos'].iloc[-1] <= 1.0


def test_forward_returns_alignment():
    n = 30
    dates = pd.date_range('2024-01-01', periods=n, freq='B')
    close = pd.Series(np.arange(1, n + 1), dtype=float)
    kl = pd.DataFrame(dict(date=dates, open=close, high=close, low=close,
                           close=close, volume=np.full(n, 1.0),
                           amount=close, turnover=np.full(n, 0.01)))
    fac = F.add_forward_returns(F.compute_factors(kl), horizons=[1])
    # close 从 t 到 t+1: (t+2)/(t+1)-1，验证首行
    expected = close.iloc[1] / close.iloc[0] - 1
    assert abs(fac['fwd_ret_1'].iloc[0] - expected) < 1e-9


def test_make_weights_signs():
    ic_summary = pd.DataFrame([
        dict(factor='mom20', horizon=5, mean_ic=0.05, ic_abs_mean=0.05),
        dict(factor='ret1', horizon=5, mean_ic=-0.04, ic_abs_mean=0.04),
        dict(factor='noise', horizon=5, mean_ic=0.001, ic_abs_mean=0.001),
    ])
    w = MF.make_weights(ic_summary, horizon=5, top_k=8, min_abs_ic=0.015)
    assert w['mom20'] > 0 and w['ret1'] < 0
    assert 'noise' not in w  # 低于 min_abs_ic 被剔除
    assert abs(sum(abs(v) for v in w.values()) - 1.0) < 1e-9


def test_labels_quantiles():
    s = pd.Series(np.arange(100, dtype=float))
    lab = BT._labels(s, 5)
    assert lab.min() == 1 and lab.max() == 5
    # 最大值应在最高档
    assert lab.iloc[-1] == 5 and lab.iloc[0] == 1


def test_equity_metrics_known():
    r = pd.Series([0.1, 0.1, 0.1], index=pd.date_range('2024-01-01', periods=3, freq='B'))
    m = BT._equity_metrics(r, horizon=5)
    assert abs(m['total_return'] - (1.1 ** 3 - 1)) < 1e-9
    assert m['win_rate'] == 1.0
    assert m['n_periods'] == 3


def test_resolve_as_of_1500_rule():
    dates = np.array(['2026-07-15', '2026-07-16', '2026-07-17', '2026-07-20'],
                     dtype='datetime64[D]').astype('datetime64[ns]')
    # 07-16 14:59（盘中，未收盘）-> as-of 应为 07-15
    assert CMP.resolve_as_of(pd.Timestamp('2026-07-16 14:59:00'), dates) == pd.Timestamp('2026-07-15')
    # 07-20 19:29（收盘后）-> as-of 07-20
    assert CMP.resolve_as_of(pd.Timestamp('2026-07-20 19:29:00'), dates) == pd.Timestamp('2026-07-20')
    # 07-17 10:49（盘中）-> as-of 07-16
    assert CMP.resolve_as_of(pd.Timestamp('2026-07-17 10:49:00'), dates) == pd.Timestamp('2026-07-16')


def test_summarize_extra_fields():
    # cum_ic == 序列之和；t_nonoverlap 字段存在
    s = pd.Series([0.1, -0.05, 0.2, 0.0, 0.15, 0.05],
                  index=pd.date_range('2024-01-01', periods=6, freq='B'))
    stat = ICM.summarize(s, horizon=2)
    assert abs(stat['cum_ic'] - float(s.sum())) < 1e-9
    assert 't_nonoverlap' in stat
    # 非重叠采样(每2日取1)共 3 个，均为正 -> t_nonoverlap 为正
    assert np.isfinite(stat['t_nonoverlap'])


def test_summary_factor_ic_perfect():
    # app_score 与 price_change_pct 完全同序 -> 汇总因子 IC=1
    rows = []
    for d in ('2026-07-02', '2026-07-03'):
        for i in range(6):
            rows.append(dict(archive_date=pd.Timestamp(d), code=f'sh60000{i}',
                             app_score=float(i), confluence_score=float(i),
                             buy_signals=float(i), sell_signals=0.0,
                             active_strategies=1.0, price_change_pct=float(i)))
    ap = pd.DataFrame(rows)
    summary = SFA.compute(ap)
    row = summary[summary['factor'] == 'App评分'].iloc[0]
    assert abs(row['mean_ic'] - 1.0) < 1e-9
    assert int(row['n_days']) == 2


def test_direction_proxy_recal_lowers_overheated():
    # overheated (surge + high vol + MA-bull + up-volume) -> recal score < current
    import validate_direction_recalibration as VD
    row = dict(bull=True, bear=False, change3d=13.0, mom5=30.0, amp=10.0,
               adx14=30.0, adx_bull=True, rsi6=78.0, k=80.0, d=85.0,
               wr14=10.0, bias6=10.0, volratio=2.2, up=True,
               close=130.0, open=118.0)
    p = pd.DataFrame([row])
    cur = float(VD._fold(p, recal=False).iloc[0])
    rec = float(VD._fold(p, recal=True).iloc[0])
    assert rec < cur


def _run_all():
    fns = [v for k, v in sorted(globals().items())
           if k.startswith('test_') and callable(v)]
    passed, failed = 0, 0
    for fn in fns:
        try:
            fn()
            print(f'  PASS {fn.__name__}')
            passed += 1
        except AssertionError as e:
            print(f'  FAIL {fn.__name__}: {e}')
            failed += 1
        except Exception as e:  # noqa: BLE001
            print(f'  ERROR {fn.__name__}: {type(e).__name__}: {e}')
            failed += 1
    print(f'\n{passed} passed, {failed} failed (共 {len(fns)})')
    return failed == 0


if __name__ == '__main__':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass
    ok = _run_all()
    sys.exit(0 if ok else 1)
