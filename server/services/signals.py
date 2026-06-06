import pandas as pd
import numpy as np


def detect_ma_signals(df: pd.DataFrame) -> list:
    signals = []
    if len(df) < 2:
        return signals
    last = df.iloc[-1]
    prev = df.iloc[-2]

    if all(col in df.columns for col in ["ma5", "ma10", "ma20", "ma60"]):
        if pd.notna(last["ma5"]) and pd.notna(last["ma10"]):
            if last["ma5"] > last["ma10"] and prev["ma5"] <= prev["ma10"]:
                signals.append({
                    "type": "buy", "strength": "中",
                    "indicator": "均线", "signal": "MA5上穿MA10金叉",
                    "desc": f"MA5({last['ma5']:.2f})上穿MA10({last['ma10']:.2f})，短期趋势转强",
                })
            elif last["ma5"] < last["ma10"] and prev["ma5"] >= prev["ma10"]:
                signals.append({
                    "type": "sell", "strength": "中",
                    "indicator": "均线", "signal": "MA5下穿MA10死叉",
                    "desc": f"MA5({last['ma5']:.2f})下穿MA10({last['ma10']:.2f})，短期趋势转弱",
                })

        if pd.notna(last["ma10"]) and pd.notna(last["ma20"]):
            if last["ma10"] > last["ma20"] and prev["ma10"] <= prev["ma20"]:
                signals.append({
                    "type": "buy", "strength": "强",
                    "indicator": "均线", "signal": "MA10上穿MA20金叉",
                    "desc": "MA10上穿MA20，中期趋势转强",
                })
            elif last["ma10"] < last["ma20"] and prev["ma10"] >= prev["ma20"]:
                signals.append({
                    "type": "sell", "strength": "强",
                    "indicator": "均线", "signal": "MA10下穿MA20死叉",
                    "desc": "MA10下穿MA20，中期趋势转弱",
                })

        if all(pd.notna(last[f"ma{p}"]) for p in [5, 10, 20, 60]):
            if (last["ma5"] > last["ma10"] > last["ma20"] > last["ma60"]):
                signals.append({
                    "type": "buy", "strength": "强",
                    "indicator": "均线", "signal": "多头排列",
                    "desc": "MA5>MA10>MA20>MA60，均线多头排列，趋势向好",
                })
            elif (last["ma5"] < last["ma10"] < last["ma20"] < last["ma60"]):
                signals.append({
                    "type": "sell", "strength": "强",
                    "indicator": "均线", "signal": "空头排列",
                    "desc": "MA5<MA10<MA20<MA60，均线空头排列，趋势向淡",
                })

    return signals


def detect_macd_signals(df: pd.DataFrame) -> list:
    signals = []
    if len(df) < 2 or "dif" not in df.columns:
        return signals
    last = df.iloc[-1]
    prev = df.iloc[-2]

    if last["dif"] > last["dea"] and prev["dif"] <= prev["dea"]:
        strength = "强" if last["dif"] < 0 else "中"
        signals.append({
            "type": "buy", "strength": strength,
            "indicator": "MACD", "signal": "MACD金叉",
            "desc": f"DIF上穿DEA形成金叉，DIF={last['dif']:.4f}，{'零轴下方金叉信号更强' if last['dif'] < 0 else '零轴上方金叉'}",
        })
    elif last["dif"] < last["dea"] and prev["dif"] >= prev["dea"]:
        strength = "强" if last["dif"] > 0 else "中"
        signals.append({
            "type": "sell", "strength": strength,
            "indicator": "MACD", "signal": "MACD死叉",
            "desc": f"DIF下穿DEA形成死叉，DIF={last['dif']:.4f}，{'零轴上方死叉风险更大' if last['dif'] > 0 else '零轴下方死叉'}",
        })

    if last["macd"] > prev["macd"] and last["macd"] < 0:
        signals.append({
            "type": "buy", "strength": "弱",
            "indicator": "MACD", "signal": "绿柱缩短",
            "desc": "MACD绿柱缩短，空头力量减弱",
        })
    elif last["macd"] < prev["macd"] and last["macd"] > 0:
        signals.append({
            "type": "sell", "strength": "弱",
            "indicator": "MACD", "signal": "红柱缩短",
            "desc": "MACD红柱缩短，多头力量减弱",
        })

    if "macd" in df.columns and len(df) >= 5:
        recent_macd = df["macd"].tail(5).values
        if all(v < 0 for v in recent_macd[:-1]) and recent_macd[-1] > 0:
            signals.append({
                "type": "buy", "strength": "强",
                "indicator": "MACD", "signal": "绿转红",
                "desc": "MACD柱由绿转红，趋势可能反转向上",
            })
        elif all(v > 0 for v in recent_macd[:-1]) and recent_macd[-1] < 0:
            signals.append({
                "type": "sell", "strength": "强",
                "indicator": "MACD", "signal": "红转绿",
                "desc": "MACD柱由红转绿，趋势可能反转向下",
            })

    return signals


def detect_rsi_signals(df: pd.DataFrame) -> list:
    signals = []
    if len(df) < 2 or "rsi6" not in df.columns:
        return signals
    last = df.iloc[-1]
    prev = df.iloc[-2]

    if last["rsi6"] > 80:
        signals.append({
            "type": "sell", "strength": "强",
            "indicator": "RSI", "signal": "严重超买",
            "desc": f"RSI6={last['rsi6']:.1f}，超过80，严重超买，注意回调风险",
        })
    elif last["rsi6"] > 70:
        signals.append({
            "type": "sell", "strength": "中",
            "indicator": "RSI", "signal": "超买",
            "desc": f"RSI6={last['rsi6']:.1f}，超过70，进入超买区域",
        })
    elif last["rsi6"] < 20:
        signals.append({
            "type": "buy", "strength": "强",
            "indicator": "RSI", "signal": "严重超卖",
            "desc": f"RSI6={last['rsi6']:.1f}，低于20，严重超卖，可能存在反弹机会",
        })
    elif last["rsi6"] < 30:
        signals.append({
            "type": "buy", "strength": "中",
            "indicator": "RSI", "signal": "超卖",
            "desc": f"RSI6={last['rsi6']:.1f}，低于30，进入超卖区域",
        })

    if prev["rsi6"] < 30 and last["rsi6"] >= 30:
        signals.append({
            "type": "buy", "strength": "中",
            "indicator": "RSI", "signal": "RSI回升突破30",
            "desc": "RSI6从超卖区回升突破30，可能出现反弹",
        })
    elif prev["rsi6"] > 70 and last["rsi6"] <= 70:
        signals.append({
            "type": "sell", "strength": "中",
            "indicator": "RSI", "signal": "RSI回落跌破70",
            "desc": "RSI6从超买区回落跌破70，上涨动能减弱",
        })

    return signals


def detect_kdj_signals(df: pd.DataFrame) -> list:
    signals = []
    if len(df) < 2 or "k" not in df.columns:
        return signals
    last = df.iloc[-1]
    prev = df.iloc[-2]

    if last["k"] > last["d"] and prev["k"] <= prev["d"]:
        strength = "强" if last["k"] < 20 else "中"
        signals.append({
            "type": "buy", "strength": strength,
            "indicator": "KDJ", "signal": "KDJ金叉",
            "desc": f"K上穿D形成金叉，K={last['k']:.1f}，{'低位金叉信号更强' if last['k'] < 20 else '中位金叉'}",
        })
    elif last["k"] < last["d"] and prev["k"] >= prev["d"]:
        strength = "强" if last["k"] > 80 else "中"
        signals.append({
            "type": "sell", "strength": strength,
            "indicator": "KDJ", "signal": "KDJ死叉",
            "desc": f"K下穿D形成死叉，K={last['k']:.1f}，{'高位死叉风险更大' if last['k'] > 80 else '中位死叉'}",
        })

    if last["j"] > 100:
        signals.append({
            "type": "sell", "strength": "中",
            "indicator": "KDJ", "signal": "J值超买",
            "desc": f"J值={last['j']:.1f}，超过100，极度超买",
        })
    elif last["j"] < 0:
        signals.append({
            "type": "buy", "strength": "中",
            "indicator": "KDJ", "signal": "J值超卖",
            "desc": f"J值={last['j']:.1f}，低于0，极度超卖",
        })

    return signals


def detect_boll_signals(df: pd.DataFrame) -> list:
    signals = []
    if len(df) < 2 or "boll_upper" not in df.columns:
        return signals
    last = df.iloc[-1]
    prev = df.iloc[-2]

    if last["close"] < last["boll_lower"] and prev["close"] >= prev["boll_lower"]:
        signals.append({
            "type": "buy", "strength": "中",
            "indicator": "BOLL", "signal": "跌破下轨",
            "desc": "股价跌破布林下轨，可能超卖反弹",
        })
    elif last["close"] > last["boll_upper"] and prev["close"] <= prev["boll_upper"]:
        signals.append({
            "type": "sell", "strength": "中",
            "indicator": "BOLL", "signal": "突破上轨",
            "desc": "股价突破布林上轨，短期可能回调",
        })

    boll_width = (last["boll_upper"] - last["boll_lower"]) / last["boll_mid"] * 100
    if boll_width < 5:
        signals.append({
            "type": "buy", "strength": "弱",
            "indicator": "BOLL", "signal": "布林带收窄",
            "desc": f"布林带宽度仅{boll_width:.1f}%，波动率极低，可能即将变盘",
        })

    return signals


def detect_volume_signals(df: pd.DataFrame) -> list:
    signals = []
    if len(df) < 2 or "vol_ma5" not in df.columns:
        return signals
    last = df.iloc[-1]
    prev = df.iloc[-2]

    if pd.notna(last["vol_ma5"]) and last["volume"] > last["vol_ma5"] * 2:
        if last["close"] > prev["close"]:
            signals.append({
                "type": "buy", "strength": "中",
                "indicator": "量价", "signal": "放量上涨",
                "desc": f"成交量是5日均量的{last['volume']/last['vol_ma5']:.1f}倍，且股价上涨，量价配合良好",
            })
        else:
            signals.append({
                "type": "sell", "strength": "中",
                "indicator": "量价", "signal": "放量下跌",
                "desc": f"成交量是5日均量的{last['volume']/last['vol_ma5']:.1f}倍，但股价下跌，放量下跌需警惕",
            })

    if pd.notna(last["vol_ma5"]) and last["volume"] < last["vol_ma5"] * 0.5:
        signals.append({
            "type": "buy", "strength": "弱",
            "indicator": "量价", "signal": "缩量",
            "desc": "成交量显著萎缩，市场观望情绪浓厚",
        })

    return signals


def detect_all_signals(df: pd.DataFrame) -> list:
    if df.empty or len(df) < 2:
        return []
    all_signals = []
    all_signals.extend(detect_ma_signals(df))
    all_signals.extend(detect_macd_signals(df))
    all_signals.extend(detect_rsi_signals(df))
    all_signals.extend(detect_kdj_signals(df))
    all_signals.extend(detect_boll_signals(df))
    all_signals.extend(detect_volume_signals(df))
    return all_signals


def get_signal_score(signals: list) -> dict:
    buy_score = 0
    sell_score = 0
    strength_map = {"强": 3, "中": 2, "弱": 1}

    for s in signals:
        score = strength_map.get(s["strength"], 1)
        if s["type"] == "buy":
            buy_score += score
        else:
            sell_score += score

    total = buy_score + sell_score
    if total == 0:
        return {"buy_score": 0, "sell_score": 0, "direction": "中性", "confidence": 0}

    direction = "偏多" if buy_score > sell_score else ("偏空" if sell_score > buy_score else "中性")
    confidence = round(abs(buy_score - sell_score) / total * 100, 1)

    return {
        "buy_score": buy_score,
        "sell_score": sell_score,
        "direction": direction,
        "confidence": confidence,
    }