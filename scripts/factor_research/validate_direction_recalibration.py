#!/usr/bin/env python3
# -*- coding: gbk -*-
"""方向引擎循证校准的离线验证（Plan B，上线门槛）。

在 540x615 面板上用 Python 复刻 v3 directionScore 的"数值证据子集"
(trend: MA排列+近3日动量+ADX / reversal_momentum: RSI/WR/KDJ/bias(+校准 fade)
 / volume_flow: 量价)，对 current vs recalibrated 两版计算 5 日截面 IC 与分档单调性，
检验校准是否消除"高分档前瞻收益反而更低"的倒挂。

口径与 mobile/lib/analysis/directional_evidence_builder.dart 对齐：
  - 组件内按"已触发家族"求均值并 clamp[-1,1]；
  - directionScore(proxy) = trend*0.25 + reversal*0.25 + volume*0.20（其余分量两版相同=0，
    在对比中抵消，故省略；亦省略 chase/oversold 护栏，仅比较证据本身）。
局限：不含信号/资金流/相对强弱/板块动量/次日预测（离线不可得），为主因子子集近似。
"""

import os
import warnings

import numpy as np
import pandas as pd

import config
import factors as F
import ic as ICM
import backtest as BT

warnings.filterwarnings('ignore', category=RuntimeWarning)  # nanmean 全 NaN

TREND_W, REV_W, VOL_W = 0.25, 0.25, 0.20


def _nanmean_clip(cols: list) -> np.ndarray:
    """按行对若干家族列求均值(忽略 NaN=未触发家族)，clamp 到 [-1,1]；全 NaN->0。"""
    stacked = np.vstack([c.to_numpy(dtype=float) for c in cols])
    with np.errstate(invalid='ignore'):
        m = np.nanmean(stacked, axis=0)
    m = np.where(np.isfinite(m), m, 0.0)
    return np.clip(m, -1.0, 1.0)


def _compute_pieces(kl: pd.DataFrame) -> pd.DataFrame:
    """从单只 K 线计算方向证据所需的原始片段。"""
    df = kl.sort_values('date').reset_index(drop=True)
    c, h, l, o, vol = df['close'], df['high'], df['low'], df['open'], df['volume']
    prev = c.shift(1)
    out = pd.DataFrame({'date': df['date']})
    ma5 = c.rolling(5, min_periods=5).mean()
    ma10 = c.rolling(10, min_periods=10).mean()
    ma20 = c.rolling(20, min_periods=20).mean()
    out['bull'] = (ma5 > ma10) & (ma10 > ma20)
    out['bear'] = (ma5 < ma10) & (ma10 < ma20)
    out['change3d'] = (c / c.shift(3) - 1) * 100
    out['mom5'] = (c / c.shift(5) - 1) * 100
    out['amp'] = (h - l) / prev * 100
    out['adx14'] = F._adx(h, l, c, 14)
    out['adx_bull'] = ma5 > ma20
    out['rsi6'] = F._rsi(c, 6)
    k, d, _ = F._kdj(h, l, c, 9)
    out['k'], out['d'] = k, d
    out['wr14'] = F._wr(h, l, c, 14)
    ma6 = c.rolling(6, min_periods=6).mean()
    out['bias6'] = (c - ma6) / ma6 * 100
    volma5 = vol.rolling(5, min_periods=5).mean()
    out['volratio'] = vol / volma5
    out['up'] = c >= o
    out['close'] = c
    out['open'] = o
    return out


def _fold(p: pd.DataFrame, recal: bool) -> pd.Series:
    """把片段折算为 directionScore(proxy)，对齐 Dart 家族均值口径。"""
    n = len(p)
    nan = pd.Series(np.full(n, np.nan))

    # trend 家族: ma / price_momentum / adx
    ma_mag = 0.35 if recal else 0.45
    t_ma = pd.Series(np.where(p['bull'], ma_mag, np.where(p['bear'], -ma_mag, np.nan)))
    if recal:
        # 校准：移除追涨贡献（近3日涨跌两个方向短期 IC 均与反转相左）
        t_mom = pd.Series(np.full(n, np.nan))
    else:
        t_mom = pd.Series(np.where(p['change3d'] >= 3, 0.20,
                                   np.where(p['change3d'] <= -3, -0.20, np.nan)))
    adx_ok = p['adx14'] >= 25
    t_adx = pd.Series(np.where(adx_ok & p['adx_bull'], 0.20,
                               np.where(adx_ok & ~p['adx_bull'], -0.20, np.nan)))
    trend = _nanmean_clip([t_ma, t_mom, t_adx])

    # reversal_momentum 家族: rsi / wr / kdj / bias (+ 校准 fade: amp / mom)
    r_rsi = pd.Series(np.where(p['rsi6'] <= 30, 0.30,
                               np.where(p['rsi6'] >= 70, -0.30, np.nan)))
    r_wr = pd.Series(np.where(p['wr14'] >= 80, 0.20,
                              np.where(p['wr14'] <= 20, -0.20, np.nan)))
    r_kdj = pd.Series(np.where((p['k'] <= 25) & (p['k'] > p['d']), 0.20,
                               np.where((p['k'] >= 75) & (p['k'] < p['d']), -0.20, np.nan)))
    r_bias = pd.Series(np.where(p['bias6'] <= -6, 0.15,
                                np.where(p['bias6'] >= 8, -0.15, np.nan)))
    rev_families = [r_rsi, r_wr, r_kdj, r_bias]
    if recal:
        r_amp = pd.Series(np.where(p['amp'] >= 9, -0.30,
                                   np.where(p['amp'] >= 6, -0.15, np.nan)))
        r_mom = pd.Series(np.where(p['mom5'] >= 15, -0.30,
                                   np.where(p['mom5'] >= 9, -0.15,
                                            np.where(p['mom5'] <= -12, 0.18, np.nan))))
        rev_families += [r_amp, r_mom]
    reversal = _nanmean_clip(rev_families)

    # volume_flow 家族: 量价
    up_mag = 0.30 if recal else 0.55
    v_vp = pd.Series(np.where(p['up'] & (p['volratio'] >= 1.4), up_mag,
                              np.where(~p['up'] & (p['volratio'] >= 1.3), -0.65,
                                       np.where(p['up'] & (p['volratio'] < 0.7), -0.20, np.nan))))
    volume = _nanmean_clip([v_vp])

    score = (trend * TREND_W + reversal * REV_W + volume * VOL_W) * 100.0 * 0.8
    return pd.Series(score, index=p.index)


def build_direction_panel(codes: list, loader=None) -> pd.DataFrame:
    import fetch_kline
    loader = loader or fetch_kline.load_kline
    frames = []
    for code in codes:
        kl = loader(code)
        if kl is None or len(kl) < config.MIN_LOOKBACK_BARS:
            continue
        p = _compute_pieces(kl)
        p['dir_current'] = _fold(p, recal=False)
        p['dir_recal'] = _fold(p, recal=True)
        c = p['close']
        p['fwd_ret_5'] = c.shift(-5) / c - 1
        p['fwd_exec_ret_5'] = c.shift(-5) / p['open'].shift(-1) - 1
        p['code'] = code
        frames.append(p[['date', 'code', 'dir_current', 'dir_recal',
                         'fwd_ret_5', 'fwd_exec_ret_5', 'open', 'close']])
    if not frames:
        raise RuntimeError('无 K 线缓存，请先运行 fetch_kline.py')
    return pd.concat(frames, ignore_index=True).sort_values(['date', 'code']).reset_index(drop=True)


def _evaluate(panel: pd.DataFrame, col: str) -> dict:
    sp = ICM.compute_ic_series(panel, [col], [5], method='spearman')
    stat = ICM.summarize(sp.get((col, 5), pd.Series(dtype=float)), 5)
    dq = BT.daily_quantile_returns(panel, 5, config.N_QUANTILES, score_col=col)
    mono = BT.quantile_monotonicity(dq, config.N_QUANTILES) if not dq.empty else pd.DataFrame()
    q_cc = mono['avg_cc_pct'].tolist() if not mono.empty else []
    # 单调性：分档平均收益的秩相关(与档位序)；顶-底档差
    monotonic = np.nan
    top_minus_bottom = np.nan
    if len(q_cc) == config.N_QUANTILES and all(np.isfinite(q_cc)):
        ranks = np.arange(1, config.N_QUANTILES + 1)
        monotonic = float(ICM._pair_ic(ranks.astype(float), np.array(q_cc), 'spearman'))
        top_minus_bottom = float(q_cc[-1] - q_cc[0])
    return dict(mean_ic=stat['mean_ic'], t_stat=stat['t_stat'],
                pos_rate=stat['pos_rate'], q_cc=q_cc,
                monotonic=monotonic, top_minus_bottom=top_minus_bottom)


def run(write_report: bool = True) -> dict:
    config.force_utf8_stdout()
    config.ensure_dirs()
    config.add_self_to_path()
    import fetch_kline
    import load_archive
    codes = load_archive.get_universe(load_archive.load_archive_panel())
    cached = [c for c in codes if fetch_kline.load_kline(c) is not None]
    panel = build_direction_panel(cached)
    cur = _evaluate(panel, 'dir_current')
    rec = _evaluate(panel, 'dir_recal')
    result = {'current': cur, 'recal': rec,
              'n_rows': len(panel), 'n_stocks': panel['code'].nunique(),
              'n_days': panel['date'].nunique()}
    panel.to_csv(os.path.join(config.OUTPUT_DIR, 'direction_proxy_panel.csv'),
                 index=False, encoding='utf-8-sig')
    if write_report:
        _write_report(result)
    return result


def _write_report(r: dict):
    from datetime import datetime

    def f(v, d=4):
        return '—' if v is None or (isinstance(v, float) and not np.isfinite(v)) else f'{v:.{d}f}'

    def qrow(q):
        return ' | '.join(f'{x:.3f}%' for x in q) if q else '—'

    cur, rec = r['current'], r['recal']
    improved = (np.isfinite(rec['monotonic']) and np.isfinite(cur['monotonic'])
                and rec['monotonic'] > cur['monotonic']
                and rec['top_minus_bottom'] >= cur['top_minus_bottom'])
    L = [
        '# 方向引擎循证校准 · 离线验证', '',
        f'生成时间: {datetime.now().strftime("%Y-%m-%d %H:%M")}', '',
        '> directionScore 数值证据子集(trend/reversal/volume) current vs recalibrated 的 5 日'
        '截面 IC 与分档(Q1..Q5)前瞻收益对比。校准目标：提升分档单调性、消除高分档收益倒挂。',
        f'> 面板 {r["n_rows"]:,} 行 / {r["n_stocks"]} 股 / {r["n_days"]} 交易日。'
        '局限：不含信号/资金流/相对强弱/板块/次日预测，为主因子子集近似。', '',
        '## IC 与单调性对比', '',
        '| 口径 | 均值IC | t | IC>0占比 | 分档单调性(秩相关) | 顶-底档差 |',
        '| --- | --- | --- | --- | --- | --- |',
        f"| current(现状) | {f(cur['mean_ic'])} | {f(cur['t_stat'],2)} | "
        f"{f(cur['pos_rate']*100,1)}% | {f(cur['monotonic'],3)} | {f(cur['top_minus_bottom'],3)}% |",
        f"| recalibrated(校准) | {f(rec['mean_ic'])} | {f(rec['t_stat'],2)} | "
        f"{f(rec['pos_rate']*100,1)}% | {f(rec['monotonic'],3)} | {f(rec['top_minus_bottom'],3)}% |",
        '',
        '## 分档平均前瞻收益(收盘-收盘, Q1→Q5)', '',
        f'- current : {qrow(cur["q_cc"])}',
        f'- recal   : {qrow(rec["q_cc"])}',
        '',
        '## 结论', '',
        f'- 校准后分档单调性{"改善且顶-底档差不降" if improved else "未见明确改善"}；'
        f'{"建议在 App 打开 useRecalibratedDirection 开关灰度观察。" if improved else "建议进一步调参或谨慎，暂不默认开启。"}',
        '- 说明：directionScore 越高应对应越高前瞻收益；单调性(秩相关)越接近 +1 越好，倒挂则为负。',
        '',
        '---', '*本报告由 scripts/factor_research/validate_direction_recalibration.py 生成。*',
    ]
    path = os.path.join(config.DOCS_DIR, 'direction_recalibration_validation.md')
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(L))
    print(f'验证报告已生成: {path}')


def main():
    r = run()
    print(f"current : IC={r['current']['mean_ic']:.4f} 单调={r['current']['monotonic']:.3f} "
          f"顶-底={r['current']['top_minus_bottom']:.3f}%")
    print(f"recal   : IC={r['recal']['mean_ic']:.4f} 单调={r['recal']['monotonic']:.3f} "
          f"顶-底={r['recal']['top_minus_bottom']:.3f}%")


if __name__ == '__main__':
    config.add_self_to_path()
    main()
