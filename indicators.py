import pandas as pd
import numpy as np


def calc_ma(df: pd.DataFrame, periods=(5, 10, 20, 60)) -> pd.DataFrame:
    for p in periods:
        df[f"ma{p}"] = df["close"].rolling(window=p).mean()
    return df


def calc_ema(series: pd.Series, period: int) -> pd.Series:
    return series.ewm(span=period, adjust=False).mean()


def calc_macd(
    df: pd.DataFrame, fast=12, slow=26, signal=9
) -> pd.DataFrame:
    ema_fast = calc_ema(df["close"], fast)
    ema_slow = calc_ema(df["close"], slow)
    df["dif"] = ema_fast - ema_slow
    df["dea"] = calc_ema(df["dif"], signal)
    df["macd"] = 2 * (df["dif"] - df["dea"])
    return df


def calc_rsi(df: pd.DataFrame, periods=(6, 12, 24)) -> pd.DataFrame:
    delta = df["close"].diff()
    for p in periods:
        gain = delta.where(delta > 0, 0).rolling(window=p).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(window=p).mean()
        rs = gain / loss.replace(0, np.nan)
        df[f"rsi{p}"] = 100 - (100 / (1 + rs))
    return df


def calc_kdj(df: pd.DataFrame, n=9, m1=3, m2=3) -> pd.DataFrame:
    low_min = df["low"].rolling(window=n).min()
    high_max = df["high"].rolling(window=n).max()
    rsv = (df["close"] - low_min) / (high_max - low_min).replace(0, np.nan) * 100
    df["k"] = rsv.ewm(com=m1 - 1, adjust=False).mean()
    df["d"] = df["k"].ewm(com=m2 - 1, adjust=False).mean()
    df["j"] = 3 * df["k"] - 2 * df["d"]
    return df


def calc_boll(df: pd.DataFrame, n=20, k=2) -> pd.DataFrame:
    df["boll_mid"] = df["close"].rolling(window=n).mean()
    std = df["close"].rolling(window=n).std()
    df["boll_upper"] = df["boll_mid"] + k * std
    df["boll_lower"] = df["boll_mid"] - k * std
    return df


def calc_volume_ma(df: pd.DataFrame, periods=(5, 10)) -> pd.DataFrame:
    for p in periods:
        df[f"vol_ma{p}"] = df["volume"].rolling(window=p).mean()
    return df


def calc_all_indicators(df: pd.DataFrame) -> pd.DataFrame:
    if df.empty or len(df) < 2:
        return df
    df = calc_ma(df)
    df = calc_macd(df)
    df = calc_rsi(df)
    df = calc_kdj(df)
    df = calc_boll(df)
    df = calc_volume_ma(df)
    return df


def get_indicator_summary(df: pd.DataFrame) -> dict:
    if df.empty or len(df) < 2:
        return {}
    last = df.iloc[-1]
    prev = df.iloc[-2]
    summary = {}

    if "ma5" in df.columns and pd.notna(last.get("ma5")):
        ma_pos = []
        for p in [5, 10, 20, 60]:
            col = f"ma{p}"
            if col in df.columns and pd.notna(last.get(col)):
                if last["close"] > last[col]:
                    ma_pos.append(f"MA{p}上方")
                else:
                    ma_pos.append(f"MA{p}下方")
        summary["均线位置"] = "、".join(ma_pos)

        ma5_above_ma10 = last.get("ma5", 0) > last.get("ma10", 0)
        prev_ma5_above_ma10 = prev.get("ma5", 0) > prev.get("ma10", 0)
        if ma5_above_ma10 and not prev_ma5_above_ma10:
            summary["均线信号"] = "金叉（MA5上穿MA10）"
        elif not ma5_above_ma10 and prev_ma5_above_ma10:
            summary["均线信号"] = "死叉（MA5下穿MA10）"
        elif ma5_above_ma10:
            summary["均线信号"] = "多头排列"
        else:
            summary["均线信号"] = "空头排列"

    if "dif" in df.columns and pd.notna(last.get("dif")):
        summary["DIF"] = round(last["dif"], 4)
        summary["DEA"] = round(last["dea"], 4)
        summary["MACD柱"] = round(last["macd"], 4)
        if last["dif"] > last["dea"] and prev["dif"] <= prev["dea"]:
            summary["MACD信号"] = "金叉"
        elif last["dif"] < last["dea"] and prev["dif"] >= prev["dea"]:
            summary["MACD信号"] = "死叉"
        elif last["macd"] > prev["macd"] and last["macd"] < 0:
            summary["MACD信号"] = "绿柱缩短（偏多）"
        elif last["macd"] < prev["macd"] and last["macd"] > 0:
            summary["MACD信号"] = "红柱缩短（偏空）"
        elif last["macd"] > 0:
            summary["MACD信号"] = "红柱运行（多头）"
        else:
            summary["MACD信号"] = "绿柱运行（空头）"

    if "rsi6" in df.columns and pd.notna(last.get("rsi6")):
        summary["RSI6"] = round(last["rsi6"], 2)
        summary["RSI12"] = round(last["rsi12"], 2)
        summary["RSI24"] = round(last["rsi24"], 2)
        if last["rsi6"] > 80:
            summary["RSI信号"] = "超买（>80）"
        elif last["rsi6"] < 20:
            summary["RSI信号"] = "超卖（<20）"
        elif last["rsi6"] > 60:
            summary["RSI信号"] = "偏强"
        elif last["rsi6"] < 40:
            summary["RSI信号"] = "偏弱"
        else:
            summary["RSI信号"] = "中性"

    if "k" in df.columns and pd.notna(last.get("k")):
        summary["K"] = round(last["k"], 2)
        summary["D"] = round(last["d"], 2)
        summary["J"] = round(last["j"], 2)
        if last["k"] > last["d"] and prev["k"] <= prev["d"]:
            summary["KDJ信号"] = "金叉"
        elif last["k"] < last["d"] and prev["k"] >= prev["d"]:
            summary["KDJ信号"] = "死叉"
        elif last["j"] > 100:
            summary["KDJ信号"] = "超买区（J>100）"
        elif last["j"] < 0:
            summary["KDJ信号"] = "超卖区（J<0）"
        else:
            summary["KDJ信号"] = "中性"

    if "boll_upper" in df.columns and pd.notna(last.get("boll_upper")):
        summary["BOLL上轨"] = round(last["boll_upper"], 2)
        summary["BOLL中轨"] = round(last["boll_mid"], 2)
        summary["BOLL下轨"] = round(last["boll_lower"], 2)
        boll_width = (last["boll_upper"] - last["boll_lower"]) / last["boll_mid"] * 100
        summary["BOLL带宽%"] = round(boll_width, 2)
        if last["close"] > last["boll_upper"]:
            summary["BOLL信号"] = "突破上轨（强势/超买）"
        elif last["close"] < last["boll_lower"]:
            summary["BOLL信号"] = "跌破下轨（弱势/超卖）"
        elif last["close"] > last["boll_mid"]:
            summary["BOLL信号"] = "中轨上方（偏多）"
        else:
            summary["BOLL信号"] = "中轨下方（偏空）"

    return summary
