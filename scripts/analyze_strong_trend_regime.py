# coding: gbk
# Follow-up to analyze_strong_trend_guard.py. The unconditional guard failed
# (target population fades under BOTH zero-inclusive and zero-exclusive views).
# Question: is there ANY no-look-ahead-gateable sub-population with a POSITIVE
# forward edge that would justify a *targeted, default-off* rescue?
#
# NOTE (data quality): ~259 broad rows have 留档涨跌幅==0.00 (very likely a
# missing-value-as-zero artifact). We report the target both WITH and WITHOUT
# them, and use explicit None checks (avoid the (0.0 or -99) truthiness trap).
# Data: legacy archive CSVs (价格变动% = realized forward return, floating proxy).
import csv, glob
from collections import defaultdict

files = glob.glob(r'd:\MyProjects\stock\留档数据\*.csv')
rows, seen = [], set()
for p in files:
    with open(p, encoding='utf-8-sig') as f:
        for r in csv.DictReader(f):
            k = (r.get('代码'), r.get('留档时间'))
            if k in seen:
                continue
            seen.add(k)
            rows.append(r)

def fnum(r, k):
    try:
        return float(r[k])
    except Exception:
        return None

def has(r, s):
    return s in (r.get('topSignals') or '')

def datestr(r):
    return (r.get('留档时间') or '').split(' ')[0]

def stats(subset):
    fwd = [fnum(r, '价格变动(%)') for r in subset]
    fwd = [x for x in fwd if x is not None]
    n = len(fwd)
    if n == 0:
        return (0, 'n=0')
    mean = sum(fwd) / n
    win = sum(1 for x in fwd if x > 0) / n * 100
    return (n, 'mean=%+.2f%% win>0=%.1f%% n=%d' % (mean, win, n))

MA, TREND = '均线多头排列', '趋势强度强劲'
broad = [r for r in rows if has(r, MA) or has(r, TREND)]
zeros = sum(1 for r in broad if fnum(r, '留档涨跌幅(%)') == 0.0)

def in_range(r, lo, hi):
    d = fnum(r, '留档涨跌幅(%)')
    return d is not None and lo <= d < hi

tgt = [r for r in broad if in_range(r, 0, 7)]                 # zero-inclusive
tgt_nz = [r for r in broad if in_range(r, 0, 7)
          and fnum(r, '留档涨跌幅(%)') != 0.0]                 # zero-exclusive

print('broad MA/TREND         :', stats(broad)[1])
print('  (data-quality) 留档涨跌幅==0.00 rows in broad:', zeros)
print('target 0<=day<7 (incl0):', stats(tgt)[1])
print('target 0<day<7  (excl0):', stats(tgt_nz)[1])

# regime at DECISION time: per-date mean entry change (known at decision time)
by_date = defaultdict(list)
for r in rows:
    v = fnum(r, '留档涨跌幅(%)')
    if v is not None:
        by_date[datestr(r)].append(v)
regime_mean = {d: sum(v) / len(v) for d, v in by_date.items() if v}

def regime_of(r):
    m = regime_mean.get(datestr(r))
    if m is None:
        return 'unknown'
    return ('strong_up' if m > 1.0 else 'up' if m > 0.2
            else 'flat' if m > -0.2 else 'down')

print('\n[a] target(incl0) by DECISION-TIME market regime:')
for reg in ['strong_up', 'up', 'flat', 'down', 'unknown']:
    sub = [r for r in tgt if regime_of(r) == reg]
    if sub:
        print('   %-10s %s' % (reg, stats(sub)[1]))

print('\n[b] target(incl0) by confirming vs contradicting co-signal:')
confirm = ['MACD金叉', '放量上涨', '底背离', '缩量蓄势突破', '涨停回封']
contra = ['MACD死叉', '顶背离', '放量滞涨', '缩量上涨', '尾盘急拉', '涨停打开']
print('   +confirming', stats([r for r in tgt if any(has(r, s) for s in confirm)])[1])
print('   +contra    ', stats([r for r in tgt if any(has(r, s) for s in contra)])[1])

print('\n[c] target(incl0) by comprehensive score band:')
for lo, hi in [(1, 4), (4, 6), (6, 7), (7, 11)]:
    sub = [r for r in tgt if lo <= (fnum(r, '评分') or -1) < hi]
    if sub:
        print('   score[%d,%d) %s' % (lo, hi, stats(sub)[1]))

print('\n[best] sub-slice with n>=50 AND mean>0 AND win>52 (candidate for future validation):')
found = False
for reg in ['strong_up', 'up', 'flat', 'down']:
    sub = [r for r in tgt if regime_of(r) == reg]
    n, _ = stats(sub)
    fwd = [x for x in (fnum(r, '价格变动(%)') for r in sub) if x is not None]
    if len(fwd) >= 50:
        mean = sum(fwd) / len(fwd)
        win = sum(1 for x in fwd if x > 0) / len(fwd) * 100
        if mean > 0 and win > 52:
            print('   CANDIDATE regime=%s mean=%+.2f%% win=%.1f%% n=%d' % (reg, mean, win, len(fwd)))
            found = True
if not found:
    print('   none at n>=50 -> not actionable now; needs fixed-horizon (1/3/5d) validation.')
