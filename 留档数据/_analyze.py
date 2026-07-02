import csv
from collections import defaultdict

path = r'd:\MyProjects\stock\留档数据\archive_export_20260702_195915.csv'
rows = []
with open(path, encoding='utf-8-sig') as f:
    reader = csv.DictReader(f)
    for r in reader:
        rows.append(r)

total = len(rows)
dev = sum(1 for r in rows if r['是否偏差'] == '是')
ok = sum(1 for r in rows if r['是否偏差'] == '否')
print(f'Total: {total}, Deviation: {dev}, OK: {ok}, WinRate: {round(ok*100/total,1)}%')
print()

print('--- By Score ---')
by_score = defaultdict(lambda: [0,0])  # [ok, dev]
for r in rows:
    s = int(r['评分'])
    if r['是否偏差'] == '是':
        by_score[s][1] += 1
    else:
        by_score[s][0] += 1
for s in sorted(by_score.keys()):
    o, d = by_score[s]
    t = o + d
    wr = round(o*100/t, 1) if t else 0
    print(f'  Score {s}: total={t}, ok={o}, dev={d}, winrate={wr}%')

print()
print('--- By Recommendation ---')
by_rec = defaultdict(lambda: [0,0])
for r in rows:
    rec = r['推荐']
    if r['是否偏差'] == '是':
        by_rec[rec][1] += 1
    else:
        by_rec[rec][0] += 1
for rec in sorted(by_rec.keys()):
    o, d = by_rec[rec]
    t = o + d
    wr = round(o*100/t, 1) if t else 0
    print(f'  {rec}: total={t}, ok={o}, dev={d}, winrate={wr}%')

print()
print('--- 留档涨跌幅 distribution ---')
lim_up = sum(1 for r in rows if abs(float(r['留档涨跌幅(%)']) - 10) < 0.5)
lim_dn = sum(1 for r in rows if abs(float(r['留档涨跌幅(%)']) + 10) < 0.5)
up58 = sum(1 for r in rows if 5 < float(r['留档涨跌幅(%)']) < 9.5)
dn58 = sum(1 for r in rows if -9.5 < float(r['留档涨跌幅(%)']) < -5)
print(f'  Limit up (≈+10%): {lim_up}, Limit down (≈-10%): {lim_dn}')
print(f'  Strong up (+5~9%): {up58}, Strong down (-5~-9%): {dn58}')

print()
print('--- Score 6-8 stocks that hit limit down next day ---')
buy_dev_limdn = sum(1 for r in rows if int(r['评分']) >= 6 and float(r['现涨跌幅(%)']) < -9.5)
buy_total = sum(1 for r in rows if int(r['评分']) >= 6)
print(f'  Score 6-8 total: {buy_total}, hit limit down: {buy_dev_limdn}, pct={round(buy_dev_limdn*100/buy_total,1)}%')

print()
print('--- Conflicting signal pattern: ▲均线多头排列 + ▼趋势强度强劲 ---')
conflict = sum(1 for r in rows if '均线多头排列' in r['topSignals'] and '趋势强度强劲' in r['topSignals'])
conflict_dev = sum(1 for r in rows if '均线多头排列' in r['topSignals'] and '趋势强度强劲' in r['topSignals'] and r['是否偏差'] == '是')
print(f'  Total: {conflict}, Deviation: {conflict_dev}, dev rate={round(conflict_dev*100/conflict,1) if conflict else 0}%')

print()
print('--- 证券板块聚集 ---')
sec_keywords = ['证券', '保险', '银行']
sec_rows = [r for r in rows if any(k in r['名称'] for k in sec_keywords)]
sec_dev = sum(1 for r in sec_rows if r['是否偏差'] == '是')
print(f'  金融板块 total: {len(sec_rows)}, dev: {sec_dev}, dev rate={round(sec_dev*100/len(sec_rows),1) if sec_rows else 0}%')
sec_buy = [r for r in sec_rows if int(r['评分']) >= 6]
sec_buy_dev = sum(1 for r in sec_buy if r['是否偏差'] == '是')
print(f'  金融板块 score>=6: {len(sec_buy)}, dev: {sec_buy_dev}, dev rate={round(sec_buy_dev*100/len(sec_buy),1) if sec_buy else 0}%')

print()
print('--- MACD顶背离 but score >= 6 ---')
top_div = [r for r in rows if 'MACD顶背离' in r['topSignals'] and int(r['评分']) >= 6]
top_div_dev = sum(1 for r in top_div if r['是否偏差'] == '是')
print(f'  Total: {len(top_div)}, Deviation: {top_div_dev}')

print()
print('--- Limit up then limit down (留档+10% then 现-10%) ---')
rev = [r for r in rows if float(r['留档涨跌幅(%)']) > 9.5 and float(r['现涨跌幅(%)']) < -9.5]
print(f'  Total: {len(rev)}, all are 偏差 by definition')
