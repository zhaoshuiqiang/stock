#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
v3 决策引擎准确性分析脚本 (Phase 0.1)

区别于遗留脚本 analyze_scoring_accuracy.py：
  - 遗留脚本读取 archive_records + recommendation_tracking（影子/遗留 7 维路径）；
  - 本脚本读取 decision_snapshots + decision_outcomes（真实生效的 v3 决策引擎），
    这才是 App 展示分数与推荐的实际来源。

产出按 方向(direction) × 强度带(strength_band) × 市场态(market_regime) × horizon(1/3/5)
分组的：样本数 / 有效方向命中率(effective_hit) / alpha 命中率 / 平均·中位收益 /
Wilson 95% 区间 / Brier 分数 / ECE(期望校准误差)，并给出整体概览、按推荐标签概览、
以及"分数-真实概率"标定诊断，落地到 docs/scoring_analysis_report_v3.md。

统计口径与 App 内 DecisionStatistics / DecisionCalibrator 对齐：
  - strength_band: |directionScore| <12 或 >100 视为无效; <20→0, <35→1, <55→2, 否则 3
  - Wilson 区间 z=1.96; Brier=mean((p-y)^2); ECE=按预测概率分箱的|acc-conf|加权
"""

import os
import sys
import sqlite3
import math
import statistics
from datetime import datetime
from collections import defaultdict

# Windows console defaults to gbk; force utf-8 so Chinese/emoji prints won't crash
try:
    sys.stdout.reconfigure(encoding='utf-8')
except Exception:
    pass

DB_PATH = os.path.join(os.path.dirname(__file__), '..', 'mobile', 'stock_analysis.db')
REPORT_PATH = os.path.join(os.path.dirname(__file__), '..', 'docs', 'scoring_analysis_report_v3.md')

Z = 1.96  # 95% 置信


def get_conn():
    if not os.path.exists(DB_PATH):
        raise FileNotFoundError(f"数据库文件不存在: {DB_PATH}")
    return sqlite3.connect(DB_PATH)


def strength_band(direction_score):
    """与 decision_calibrator.dart strengthBand 对齐。"""
    if direction_score is None:
        return None
    s = abs(direction_score)
    if s < 12 or s > 100:
        return None
    if s < 20:
        return 0
    if s < 35:
        return 1
    if s < 55:
        return 2
    return 3


BAND_LABEL = {0: '弱(12-20)', 1: '中(20-35)', 2: '强(35-55)', 3: '极强(55+)'}


def wilson_interval(hits, n):
    """Wilson 95% 区间。返回 (lower, upper)。"""
    if n <= 0:
        return (0.0, 0.0)
    p = hits / n
    denom = 1 + Z * Z / n
    center = (p + Z * Z / (2 * n)) / denom
    margin = (Z * math.sqrt(p * (1 - p) / n + Z * Z / (4 * n * n))) / denom
    return (max(0.0, center - margin), min(1.0, center + margin))


def brier_score(pairs):
    """pairs: list of (predicted_prob, actual_hit 0/1)。返回 Brier 或 None。"""
    vals = [(p, y) for (p, y) in pairs if p is not None and y is not None]
    if not vals:
        return None
    return sum((p - y) ** 2 for (p, y) in vals) / len(vals)


def expected_calibration_error(pairs, bins=10):
    """ECE: 按预测概率分箱, 加权平均 |准确率-平均置信度|。"""
    vals = [(p, y) for (p, y) in pairs if p is not None and y is not None]
    if not vals:
        return None
    n = len(vals)
    buckets = defaultdict(list)
    for p, y in vals:
        idx = min(bins - 1, int(p * bins))
        buckets[idx].append((p, y))
    ece = 0.0
    for items in buckets.values():
        conf = sum(p for p, _ in items) / len(items)
        acc = sum(y for _, y in items) / len(items)
        ece += (len(items) / n) * abs(acc - conf)
    return ece


def fetch_rows(conn):
    """联表读取快照 + 结局。每条 (snapshot, horizon-outcome) 一行。"""
    cur = conn.cursor()
    # 校验表是否存在
    cur.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN "
        "('decision_snapshots','decision_outcomes')")
    tables = {r[0] for r in cur.fetchall()}
    if 'decision_snapshots' not in tables or 'decision_outcomes' not in tables:
        return []

    query = """
    SELECT
        s.code, s.name, s.direction, s.direction_score,
        s.recommendation_label, s.legacy_score, s.market_regime,
        s.model_version, s.signal_trade_date, s.actionable,
        o.horizon, o.status,
        o.effective_direction_hit, o.raw_direction_hit, o.alpha_hit,
        o.executable_return, o.alpha_return,
        o.predicted_probability
    FROM decision_snapshots s
    JOIN decision_outcomes o ON o.snapshot_id = s.id
    ORDER BY s.signal_trade_date DESC
    """
    cur.execute(query)
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def summarize(rows, predicate):
    """对满足 predicate 且已评估的行做统计汇总。"""
    subset = [r for r in rows if predicate(r)]
    evaluated = [r for r in subset
                 if r['status'] == 'evaluated' and r['effective_direction_hit'] is not None]
    n = len(evaluated)
    if n == 0:
        return {
            'total': len(subset), 'evaluated': 0, 'eff_hit': None, 'alpha_hit': None,
            'avg_ret': None, 'med_ret': None, 'wilson': (None, None),
            'brier': None, 'ece': None,
        }
    eff_hits = sum(1 for r in evaluated if r['effective_direction_hit'] == 1)
    alpha_eval = [r for r in evaluated if r['alpha_hit'] is not None]
    alpha_hits = sum(1 for r in alpha_eval if r['alpha_hit'] == 1)
    rets = [r['executable_return'] for r in evaluated if r['executable_return'] is not None]
    pairs = [(r['predicted_probability'], r['effective_direction_hit']) for r in evaluated]
    lo, hi = wilson_interval(eff_hits, n)
    return {
        'total': len(subset),
        'evaluated': n,
        'eff_hit': eff_hits / n,
        'alpha_hit': (alpha_hits / len(alpha_eval)) if alpha_eval else None,
        'avg_ret': (sum(rets) / len(rets)) if rets else None,
        'med_ret': (statistics.median(rets)) if rets else None,
        'wilson': (lo, hi),
        'brier': brier_score(pairs),
        'ece': expected_calibration_error(pairs),
    }


def fmt_pct(v):
    return f"{v * 100:.1f}%" if v is not None else "—"


def fmt_num(v, digits=2):
    return f"{v:.{digits}f}" if v is not None else "—"


def build_report(rows):
    ts = datetime.now().strftime('%Y-%m-%d %H:%M')
    total_snap = len({(r['code'], r['signal_trade_date'], r['model_version']) for r in rows})
    lines = []
    lines.append("# v3 决策引擎准确性分析报告")
    lines.append("")
    lines.append(f"生成时间: {ts}")
    lines.append("")
    lines.append("> 数据源: `decision_snapshots` + `decision_outcomes`（真实生效的 v3 决策引擎）。")
    lines.append("> 注意: 遗留脚本 `analyze_scoring_accuracy.py` 分析的是影子 7 维路径，"
                 "不反映实际展示分数/推荐，仅供对照。")
    lines.append("")
    lines.append("## 数据概览")
    lines.append("")
    lines.append(f"- 决策快照数(去重): {total_snap}")
    lines.append(f"- 快照×horizon 结局行数: {len(rows)}")
    evaluated_rows = [r for r in rows if r['status'] == 'evaluated']
    pending_rows = [r for r in rows if r['status'] == 'pending']
    lines.append(f"- 已评估结局行: {len(evaluated_rows)}；待定: {len(pending_rows)}")
    lines.append("")

    if not rows:
        lines.append("⚠️ 未找到 v3 决策追踪数据（decision_snapshots/decision_outcomes 为空或不存在）。")
        lines.append("")
        lines.append("请先在 App 内进行扫描/分析以积累决策快照，或通过应用内『决策导出』"
                     "导出 CSV 后再运行本脚本。")
        return "\n".join(lines)

    # 整体概览（按 horizon）
    lines.append("## 一、整体表现（按 horizon）")
    lines.append("")
    lines.append("| Horizon | 样本 | 有效命中率 | Wilson区间 | Alpha命中率 | 平均收益 | 中位收益 | Brier | ECE |")
    lines.append("|---|---|---|---|---|---|---|---|---|")
    for h in (1, 3, 5):
        s = summarize(rows, lambda r, h=h: r['horizon'] == h)
        wl, wh = s['wilson']
        wilson_str = f"[{fmt_pct(wl)}, {fmt_pct(wh)}]" if wl is not None else "—"
        lines.append(
            f"| {h}日 | {s['evaluated']} | {fmt_pct(s['eff_hit'])} | {wilson_str} | "
            f"{fmt_pct(s['alpha_hit'])} | {fmt_num(s['avg_ret'])}% | {fmt_num(s['med_ret'])}% | "
            f"{fmt_num(s['brier'], 3)} | {fmt_num(s['ece'], 3)} |")
    lines.append("")

    # 方向 × 强度带（3日为主）
    lines.append("## 二、方向 × 强度带表现（horizon=3日）")
    lines.append("")
    lines.append("| 方向 | 强度带 | 样本 | 有效命中率 | Wilson区间 | 平均收益 |")
    lines.append("|---|---|---|---|---|---|")
    for direction in ('bullish', 'bearish'):
        for band in (0, 1, 2, 3):
            s = summarize(
                rows,
                lambda r, d=direction, b=band: (
                    r['horizon'] == 3 and r['direction'] == d
                    and strength_band(r['direction_score']) == b))
            if s['total'] == 0:
                continue
            wl, wh = s['wilson']
            wilson_str = f"[{fmt_pct(wl)}, {fmt_pct(wh)}]" if wl is not None else "—"
            lines.append(
                f"| {direction} | {BAND_LABEL[band]} | {s['evaluated']} | "
                f"{fmt_pct(s['eff_hit'])} | {wilson_str} | {fmt_num(s['avg_ret'])}% |")
    lines.append("")

    # 市场态（3日）
    lines.append("## 三、市场态表现（horizon=3日）")
    lines.append("")
    lines.append("| 市场态 | 样本 | 有效命中率 | Alpha命中率 | 平均收益 |")
    lines.append("|---|---|---|---|---|")
    regimes = sorted({r['market_regime'] for r in rows if r['market_regime']})
    for regime in regimes:
        s = summarize(
            rows, lambda r, g=regime: r['horizon'] == 3 and r['market_regime'] == g)
        if s['total'] == 0:
            continue
        lines.append(
            f"| {regime} | {s['evaluated']} | {fmt_pct(s['eff_hit'])} | "
            f"{fmt_pct(s['alpha_hit'])} | {fmt_num(s['avg_ret'])}% |")
    lines.append("")

    # 推荐标签（3日）—— 检验"过度/不足推荐"
    lines.append("## 四、按推荐标签表现（horizon=3日）")
    lines.append("")
    lines.append("| 推荐标签 | 样本 | 有效命中率 | Wilson区间 | 平均收益 |")
    lines.append("|---|---|---|---|---|")
    label_order = ['强烈买入', '买入', '谨慎买入', '偏多观望', '观望',
                   '偏空观望', '谨慎卖出', '卖出', '强烈卖出']
    present = {r['recommendation_label'] for r in rows}
    for label in label_order:
        if label not in present:
            continue
        s = summarize(
            rows, lambda r, lb=label: r['horizon'] == 3 and r['recommendation_label'] == lb)
        if s['total'] == 0:
            continue
        wl, wh = s['wilson']
        wilson_str = f"[{fmt_pct(wl)}, {fmt_pct(wh)}]" if wl is not None else "—"
        lines.append(
            f"| {label} | {s['evaluated']} | {fmt_pct(s['eff_hit'])} | {wilson_str} | "
            f"{fmt_num(s['avg_ret'])}% |")
    lines.append("")

    # 分数-真实概率 标定诊断
    lines.append("## 五、展示分(legacy_score) 与真实命中概率标定（horizon=3日）")
    lines.append("")
    lines.append("理想情况下 legacy_score 越高，真实有效命中率应单调越高；若否则说明分数虚高/虚低。")
    lines.append("")
    lines.append("| legacy_score | 样本 | 有效命中率 | 平均收益 |")
    lines.append("|---|---|---|---|")
    for score in range(1, 11):
        s = summarize(
            rows, lambda r, sc=score: r['horizon'] == 3 and r['legacy_score'] == sc)
        if s['total'] == 0:
            continue
        lines.append(
            f"| {score} | {s['evaluated']} | {fmt_pct(s['eff_hit'])} | {fmt_num(s['avg_ret'])}% |")
    lines.append("")

    # 结论
    lines.append("## 六、结论与优化提示")
    lines.append("")
    overall3 = summarize(rows, lambda r: r['horizon'] == 3)
    if overall3['eff_hit'] is None:
        lines.append("- 3日样本尚不足以给出稳定结论，建议继续积累（每桶目标 ≥100 样本 / ≥20 个信号日）。")
    else:
        hit = overall3['eff_hit']
        verdict = '优秀' if hit >= 0.6 else ('良好但需优化' if hit >= 0.5 else '需重点改进')
        lines.append(f"- 3日整体有效命中率 {fmt_pct(hit)}（{verdict}）。")
        if overall3['ece'] is not None and overall3['ece'] > 0.1:
            lines.append(f"- ECE={fmt_num(overall3['ece'], 3)} 偏高，展示分与真实概率存在偏差，"
                         "建议启用 Phase 2.3 概率标定。")
        lines.append("- 若某强度带/市场态命中率与其强度语义不匹配，优先纳入 Phase 2.1/2.2 权重与阈值标定。")
    lines.append("")
    lines.append("---")
    lines.append("*本报告由 analyze_decision_accuracy.py 生成，反映真实 v3 引擎；建议结合人工审核。*")
    return "\n".join(lines)


def main():
    print("开始分析 v3 决策引擎准确性...")
    try:
        conn = get_conn()
        print(f"✓ 数据库连接成功: {DB_PATH}")
        rows = fetch_rows(conn)
        print(f"✓ 读取 {len(rows)} 条 快照×horizon 结局行")
        report = build_report(rows)
        os.makedirs(os.path.dirname(REPORT_PATH), exist_ok=True)
        with open(REPORT_PATH, 'w', encoding='utf-8') as f:
            f.write(report)
        print(f"✓ 报告已保存: {REPORT_PATH}")
        conn.close()
        print("分析完成！")
    except FileNotFoundError as e:
        print(f"⚠️ {e}")
        print("提示: 该 DB 为 App 运行期生成，开发机上可能不存在；"
              "可在真机运行后 adb pull，或使用应用内『决策导出』CSV。")
    except Exception as e:  # noqa: BLE001
        print(f"❌ 分析失败: {e}")
        import traceback
        traceback.print_exc()


if __name__ == '__main__':
    main()
