import pandas as pd
import numpy as np
from typing import Optional


def detect_dragon_retreat(df: pd.DataFrame) -> dict:
    """识别龙回头形态"""
    if len(df) < 20:
        return {"found": False}
    
    df = df.copy()
    
    # 1. 找到一段上涨趋势（近20日内涨幅 >= 15%）
    recent_20 = df.tail(20)
    low_20 = recent_20['low'].min()
    high_20 = recent_20['high'].max()
    rise_pct = (high_20 - low_20) / low_20 * 100
    
    if rise_pct < 15:
        return {"found": False}
    
    # 找到上涨起点和峰顶索引
    start_idx = df[df['low'] <= low_20].index[0] if len(df[df['low'] <= low_20]) > 0 else len(df) - 20
    peak_idx_local = recent_20['high'].idxmax()
    peak_idx = df.index.get_loc(peak_idx_local) if hasattr(peak_idx_local, '__len__') or isinstance(peak_idx_local, pd.Index) else peak_idx_local
    peak_idx = df.index.get_loc(peak_idx_local) if isinstance(peak_idx_local, pd.Index) else (df.index.tolist().index(peak_idx_local) if peak_idx_local in df.index else len(df) - 1)
    
    # 2. 找到回调起点之后的回调
    after_peak = df.loc[peak_idx + 1:] if peak_idx < len(df) - 1 else pd.DataFrame()
    if after_peak.empty:
        return {"found": False}
    
    # 计算回调幅度
    pullback_low = after_peak['low'].min()
    peak_price = df.loc[peak_idx, 'high'] if peak_idx < len(df) else recent_20['high'].max()
    pullback_pct = (peak_price - pullback_low) / peak_price * 100
    
    # 回调幅度过滤：10% <= pullback_pct <= 30%
    if pullback_pct < 10 or pullback_pct > 40:
        return {"found": False}
    
    # 回调持续 3-8 天
    pullback_days = len(after_peak[after_peak['low'] <= pullback_low])
    if pullback_days < 3 or pullback_days > 10:
        return {"found": False}
    
    # 3. 最近 2 天内出现止跌信号
    last = df.iloc[-1]
    prev = df.iloc[-2]
    
    # 阳线收盘价 > 回调前最后一天收盘价 × 0.95
    if peak_idx >= 0 and len(df) > peak_idx:
        peak_close = df.loc[df.index[peak_idx], 'close']
        if last['close'] <= peak_close * 0.95:
            return {"found": False}
    
    # 成交量较回调期间平均成交量放大 >= 50%
    pullback_vol_avg = after_peak['volume'].mean()
    if pullback_vol_avg > 0 and last['volume'] < pullback_vol_avg * 1.5:
        return {"found": False}
    
    # 4. 当前价格 > 回调最低价 × 1.03
    if last['close'] <= pullback_low * 1.03:
        return {"found": False}
    
    # 判断形态等级
    if pullback_pct >= 20 and last['volume'] > pullback_vol_avg * 2:
        level = "强势"
    elif pullback_pct >= 15 and last['volume'] > pullback_vol_avg * 1.5:
        level = "一般"
    else:
        level = "弱势"
    
    return {
        "found": True,
        "level": level,
        "start_index": int(start_idx) if isinstance(start_idx, (int, np.integer)) else len(df) - 20,
        "peak_index": int(peak_idx),
        "pullback_pct": round(pullback_pct, 2),
        "signal_date": str(df.index[-1]) if isinstance(df.index[-1], str) else df.iloc[-1].get('date', '')
    }


def calc_fibonacci(df: pd.DataFrame, window: int = 20) -> dict:
    """计算斐波那契回撤位"""
    if len(df) < window:
        return {}
    
    recent = df.tail(window)
    swing_low = recent['low'].min()
    swing_high = recent['high'].max()
    
    levels = {}
    ratios = [0.236, 0.382, 0.5, 0.618, 0.786]
    for ratio in ratios:
        price = swing_low + (swing_high - swing_low) * (1 - ratio)
        levels[f"{ratio*100:.1f}%"] = round(price, 2)
    
    # 当前所处位置
    current_price = df.iloc[-1]['close']
    current_position = "无"
    for ratio in reversed(ratios):
        level_price = swing_low + (swing_high - swing_low) * (1 - ratio)
        if current_price >= level_price:
            current_position = f"{ratio*100:.1f}%阻力位上方"
            break
    
    return {
        "swing_high": round(swing_high, 2),
        "swing_low": round(swing_low, 2),
        "levels": levels,
        "current_position": current_position
    }


def detect_trend_signals(df: pd.DataFrame) -> dict:
    """识别三日趋势信号类型"""
    if len(df) < 20:
        return {"stabilization": [], "top": [], "bottom": []}
    
    last = df.iloc[-1]
    prev = df.iloc[-2]
    
    result = {"stabilization": [], "top": [], "bottom": []}
    
    body = abs(last['open'] - last['close']) if last['open'] != last['close'] else 0.01
    
    # === 企稳信号 ===
    # 1. 止跌阳线：跌幅收窄后出现阳线
    if prev['close'] < prev['open'] and last['close'] > last['open']:
        result["stabilization"].append("止跌阳线")
    
    # 2. 缩量后放量反弹
    if 'vol_ma5' in df.columns:
        if pd.notna(last.get('vol_ma5')) and pd.notna(prev.get('vol_ma5')):
            if last['volume'] > prev['volume'] > df.iloc[-3]['volume']:
                result["stabilization"].append("缩量反弹")
    
    # 3. 回踩关键均线（MA5/MA10）后企稳
    for ma in ['ma5', 'ma10']:
        if ma in df.columns and pd.notna(last.get(ma)):
            if abs(last[ma] - last['close']) / last[ma] < 0.01 and last['close'] > last['open']:
                result["stabilization"].append(f"回踩{ma.upper()}企稳")
    
    # 4. RSI从超卖区回升
    if 'rsi6' in df.columns:
        if pd.notna(df.iloc[-3].get('rsi6')) and pd.notna(last.get('rsi6')):
            if df.iloc[-3]['rsi6'] < 30 and last['rsi6'] > 35:
                result["stabilization"].append("RSI超卖回升")
    
    # === 见顶信号 ===
    # 1. 高位长上影线（上影线 >= 实体 2 倍）
    upper_shadow = last['high'] - max(last['open'], last['close'])
    if upper_shadow >= 2 * body and pd.notna(last.get('ma5')) and last['close'] > last['ma5']:
        result["top"].append("高位长上影线")
    
    # 2. 高位放量滞涨（成交量放大但价格不创新高）
    if 'vol_ma5' in df.columns and pd.notna(last.get('vol_ma5')):
        if (last['volume'] > last['vol_ma5'] * 1.5
            and last['high'] < prev['high']
            and last['close'] < (last['high'] + last['low']) / 2):
            result["top"].append("高位放量滞涨")
    
    # 3. MACD顶背离（价格新高但MACD不创新高）
    if 'macd' in df.columns and len(df) >= 3:
        df_temp = df.copy()
        df_temp['high_20d'] = df_temp['high'].rolling(20).max()
        df_temp['macd_20d'] = df_temp['macd'].rolling(20).max()
        if (pd.notna(df_temp.iloc[-3].get('macd')) and pd.notna(df_temp.iloc[-1].get('macd'))):
            if (last['high'] >= df_temp['high_20d'].iloc[-3]
                and last['macd'] < df_temp['macd_20d'].iloc[-3]):
                result["top"].append("MACD顶背离")
    
    # === 见底信号 ===
    # 1. 低位长下影线
    lower_shadow = min(last['open'], last['close']) - last['low']
    if lower_shadow >= 2 * body and pd.notna(last.get('ma5')) and last['close'] < last['ma5']:
        result["bottom"].append("低位长下影线")
    
    # 2. 缩量后放量阳线
    if 'vol_ma5' in df.columns and pd.notna(last.get('vol_ma5')) and pd.notna(prev.get('vol_ma5')):
        if (last['volume'] > last['vol_ma5'] * 1.2
            and prev['volume'] < df['vol_ma5'].iloc[-2] * 0.8
            and last['close'] > last['open']):
            result["bottom"].append("放量止跌")
    
    # 3. KDJ超卖区金叉
    if 'k' in df.columns and 'd' in df.columns:
        if pd.notna(df.iloc[-3].get('k')) and pd.notna(last.get('k')) and pd.notna(prev.get('k')):
            if (df.iloc[-3]['k'] < 20
                and last['k'] > last['d'] and prev['k'] <= prev['d']):
                result["bottom"].append("KDJ超卖金叉")
    
    # 4. 价跌量缩（下跌末期缩量）
    if last['close'] < prev['close'] and 'vol_ma5' in df.columns and pd.notna(last.get('vol_ma5')):
        if last['volume'] < last['vol_ma5'] * 0.7:
            result["bottom"].append("价跌量缩（空头衰竭）")
    
    return result