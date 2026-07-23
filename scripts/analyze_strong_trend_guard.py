# coding: gbk
# P0-2 verification: does the strongTrendGuard's target population (MA multi-head
# / trend-strength, NON-parabolic uptrend) actually have a positive forward edge?
# The dampeners exist because broad MA-multihead fades (-2%); the guard only
# fires for the narrow "healthy, non-extended" subset, so that subset must NOT
# fade or the guard re-inflates losers. Data: legacy archive CSVs (价格变动% =
# realized forward return from archive price). Approximation: CSV lacks ADX/bias/
# rsi, so the slice is a SUPERSET of the guard population (a loose lower bound).
import csv, glob

files = glob.glob(r'd:\MyProjects\stock\留档数据\*.csv')
rows = []
seen = set()
for p in files:
    with open(p, encoding='utf-8-sig') as f:
        for r in csv.DictReader(f):
            key = (r.get('代码'), r.get('留档时间'))
            if key in seen:
                continue
            seen.add(key)
            rows.append(r)

def fnum(r, k):
    try:
        return float(r[k])
    except Exception:
        return None

def has(r, sig):
    return sig in (r.get('topSignals') or '')

MA = '均线多头排列'
TREND = '趋势强度强劲'

def stats(subset):
    fwd = [fnum(r, '价格变动(%)') for r in subset]
    fwd = [x for x in fwd if x is not None]
    n = len(fwd)
    if n == 0:
        return 'n=0'
    mean = sum(fwd) / n
    winpos = sum(1 for x in fwd if x > 0) / n * 100
    win1 = sum(1 for x in fwd if x > 1) / n * 100
    med = sorted(fwd)[n // 2]
    return 'n=%d mean=%+.2f%% median=%+.2f%% win>0=%.1f%% win>1=%.1f%%' % (
        n, mean, med, winpos, win1)

print('files:', len(files), '| deduped rows:', len(rows))
print('BASELINE  all                :', stats(rows))

broad = [r for r in rows if has(r, MA) or has(r, TREND)]
print('BROAD     MA/TREND any        :', stats(broad))

def day(r):
    return fnum(r, '留档涨跌幅(%)')

tgt = [r for r in broad if day(r) is not None and 0 <= day(r) < 7]
print('GUARD~    MA/TREND +up[0,7)    :', stats(tgt))

mild = [r for r in broad if day(r) is not None and 0 <= day(r) < 3]
print('  tighter MA/TREND +up[0,3)    :', stats(mild))

para = [r for r in broad if day(r) is not None and day(r) >= 7]
print('EXCLUDED  MA/TREND +para>=7    :', stats(para))

# Cross-check: rows that carry a bullish recommendation already (context only).
buyish = [r for r in tgt if (r.get('推荐') or '').find('买') >= 0]
print('  of GUARD~, already-buy rec   :', stats(buyish),
      '(guard only matters for the NON-buy remainder)')
nonbuy = [r for r in tgt if (r.get('推荐') or '').find('买') < 0]
print('  of GUARD~, NON-buy (guard target) :', stats(nonbuy))
