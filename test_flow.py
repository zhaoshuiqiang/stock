import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from data_fetcher import _get_sina_quote, get_stock_history
from indicators import calc_all_indicators, get_indicator_summary
from signals import detect_all_signals, get_signal_score
from advisor import generate_advice, assess_risk

quote = _get_sina_quote('002384')
df = get_stock_history('002384', days=180)
df = calc_all_indicators(df)
summary = get_indicator_summary(df)
signals = detect_all_signals(df)
score = get_signal_score(signals)
advice = generate_advice(quote, summary, signals, score)
risk = assess_risk(quote, df)

print('=== Indicator Summary ===')
for k, v in summary.items():
    print(f'  {k}: {v}')

print('\n=== Signal Score ===')
print(f'  Direction: {score["direction"]}, Confidence: {score["confidence"]}%')
print(f'  Buy: {score["buy_score"]}, Sell: {score["sell_score"]}')

print(f'\n=== Signals ({len(signals)}) ===')
for s in signals:
    print(f'  [{s["type"]}] {s["indicator"]} - {s["signal"]}')

print('\n=== Advice ===')
print(f'  Rating: {advice["综合评级"]}')
print(f'  Suggestion: {advice["操作建议"]}')

print('\n=== Risk ===')
print(f'  Level: {risk["风险等级"]}')
print(f'  Volatility: {risk["波动率评估"]}')
