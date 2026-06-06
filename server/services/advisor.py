import pandas as pd
import numpy as np


def generate_score(df: pd.DataFrame) -> dict:
    """综合评分，返回多空方向和置信度"""
    if df.empty or len(df) < 2:
        return {"direction": "中性", "confidence": 0, "buy_score": 0, "sell_score": 0}

    last = df.iloc[-1]
    prev = df.iloc[-2]

    buy_score = 0
    sell_score = 0

    # 均线多头/空头评分
    if all(col in df.columns for col in ["ma5", "ma10", "ma20", "ma60"]):
        if pd.notna(last["ma5"]) and pd.notna(last["ma10"]):
            if last["ma5"] > last["ma10"]:
                buy_score += 10
            else:
                sell_score += 10
        if pd.notna(last["ma10"]) and pd.notna(last["ma20"]):
            if last["ma10"] > last["ma20"]:
                buy_score += 10
            else:
                sell_score += 10
        if last["close"] > last.get("ma20", 0):
            buy_score += 5
        else:
            sell_score += 5

    # MACD 评分
    if "dif" in df.columns and pd.notna(last.get("dif")):
        if last["dif"] > last.get("dea", 0):
            buy_score += 10
        else:
            sell_score += 10
        if last.get("macd", 0) > 0:
            buy_score += 5
        elif last.get("macd", 0) < 0:
            sell_score += 5

    # RSI 评分
    rsi6 = last.get("rsi6", 50)
    if pd.notna(rsi6):
        if rsi6 < 30:
            buy_score += 15
        elif rsi6 > 70:
            sell_score += 15
        elif rsi6 > 50:
            buy_score += 5
        else:
            sell_score += 5

    # KDJ 评分
    k = last.get("k", 50)
    d = last.get("d", 50)
    if pd.notna(k) and pd.notna(d):
        if k > d:
            buy_score += 5
        else:
            sell_score += 5
        if k < 20:
            buy_score += 10
        elif k > 80:
            sell_score += 10

    # BOLL 评分
    if "boll_lower" in df.columns and pd.notna(last.get("boll_lower")):
        if last["close"] <= last["boll_lower"]:
            buy_score += 10
        elif last["close"] >= last.get("boll_upper", 0):
            sell_score += 10

    total = buy_score + sell_score
    if total == 0:
        direction = "中性"
        confidence = 0
    elif buy_score > sell_score:
        direction = "偏多"
        confidence = round((buy_score - sell_score) / total * 100, 1)
    elif sell_score > buy_score:
        direction = "偏空"
        confidence = round((sell_score - buy_score) / total * 100, 1)
    else:
        direction = "中性"
        confidence = 0

    return {
        "direction": direction,
        "confidence": confidence,
        "buy_score": buy_score,
        "sell_score": sell_score,
    }


def generate_advice(quote: dict, indicator_summary: dict, signals: list, score: dict) -> dict:
    advice = {
        "操作建议": "",
        "建议详情": [],
        "机会分析": [],
        "风险提示": [],
        "综合评级": "",
    }

    direction = score.get("direction", "中性")
    confidence = score.get("confidence", 0)
    buy_score = score.get("buy_score", 0)
    sell_score = score.get("sell_score", 0)

    if not quote:
        advice["操作建议"] = "数据获取失败，无法生成建议"
        return advice

    pct = quote.get("涨跌幅", 0)
    turnover = quote.get("换手率", 0)
    pe = quote.get("市盈率-动态", 0)
    pb = quote.get("市净率", 0)

    if direction == "偏多" and confidence >= 60:
        advice["操作建议"] = "建议关注/逢低介入"
        advice["建议详情"].append(f"技术面偏多信号较强（多头得分{buy_score}，置信度{confidence}%），可考虑逢低布局")
    elif direction == "偏多" and confidence >= 30:
        advice["操作建议"] = "可轻仓关注"
        advice["建议详情"].append(f"技术面偏多信号一般（多头得分{buy_score}，置信度{confidence}%），建议轻仓试探")
    elif direction == "偏空" and confidence >= 60:
        advice["操作建议"] = "建议减仓/回避"
        advice["建议详情"].append(f"技术面偏空信号较强（空头得分{sell_score}，置信度{confidence}%），建议减仓或回避")
    elif direction == "偏空" and confidence >= 30:
        advice["操作建议"] = "谨慎观望"
        advice["建议详情"].append(f"技术面偏空信号一般（空头得分{sell_score}，置信度{confidence}%），建议谨慎操作")
    else:
        advice["操作建议"] = "观望为主"
        advice["建议详情"].append("多空信号均衡，方向不明，建议观望等待明确信号")

    buy_signals = [s for s in signals if s["type"] == "buy"]
    sell_signals = [s for s in signals if s["type"] == "sell"]

    for s in buy_signals:
        advice["机会分析"].append(f"【{s['indicator']}】{s['signal']}：{s['desc']}")

    for s in sell_signals:
        advice["风险提示"].append(f"【{s['indicator']}】{s['signal']}：{s['desc']}")

    if turnover > 10:
        advice["风险提示"].append(f"换手率高达{turnover:.1f}%，交投过于活跃，需警惕短期波动风险")
    elif turnover > 5:
        advice["机会分析"].append(f"换手率{turnover:.1f}%，市场关注度较高，流动性良好")

    if pe > 0:
        if pe > 100:
            advice["风险提示"].append(f"动态市盈率{pe:.1f}倍，估值偏高，需注意估值风险")
        elif pe < 15:
            advice["机会分析"].append(f"动态市盈率{pe:.1f}倍，估值较低，可能存在价值低估")
        else:
            advice["建议详情"].append(f"动态市盈率{pe:.1f}倍，估值处于中等水平")

    if pb > 0:
        if pb > 10:
            advice["风险提示"].append(f"市净率{pb:.1f}倍，估值偏高")
        elif pb < 1:
            advice["机会分析"].append(f"市净率{pb:.1f}倍，破净股，可能存在安全边际")
        else:
            advice["建议详情"].append(f"市净率{pb:.1f}倍，估值处于中等水平")

    if pct > 5:
        advice["风险提示"].append(f"当日涨幅{pct:.2f}%，涨幅较大，追高需谨慎")
    elif pct < -5:
        advice["机会分析"].append(f"当日跌幅{pct:.2f}%，跌幅较大，可能存在超跌反弹机会")

    if confidence >= 60 and direction == "偏多":
        advice["综合评级"] = "★★★★☆ 看多"
    elif confidence >= 30 and direction == "偏多":
        advice["综合评级"] = "★★★☆☆ 偏多"
    elif confidence >= 60 and direction == "偏空":
        advice["综合评级"] = "★☆☆☆☆ 看空"
    elif confidence >= 30 and direction == "偏空":
        advice["综合评级"] = "★★☆☆☆ 偏空"
    else:
        advice["综合评级"] = "★★★☆☆ 中性"

    return advice


def assess_risk(quote: dict, df: pd.DataFrame) -> dict:
    risk = {
        "风险等级": "",
        "风险因素": [],
        "安全因素": [],
        "波动率评估": "",
    }

    if df.empty or len(df) < 20 or not quote:
        risk["风险等级"] = "数据不足"
        return risk

    close = df["close"]
    returns = close.pct_change().dropna()

    if len(returns) < 10:
        risk["风险等级"] = "数据不足"
        return risk

    daily_vol = returns.std()
    annual_vol = daily_vol * np.sqrt(252)
    max_drawdown = (close / close.cummax() - 1).min()

    if annual_vol > 0.5:
        risk["波动率评估"] = f"年化波动率{annual_vol:.1%}，波动极大"
        risk["风险因素"].append(f"年化波动率高达{annual_vol:.1%}，价格波动剧烈，风险极高")
    elif annual_vol > 0.35:
        risk["波动率评估"] = f"年化波动率{annual_vol:.1%}，波动较大"
        risk["风险因素"].append(f"年化波动率{annual_vol:.1%}，价格波动较大")
    elif annual_vol > 0.2:
        risk["波动率评估"] = f"年化波动率{annual_vol:.1%}，波动适中"
        risk["安全因素"].append(f"年化波动率{annual_vol:.1%}，波动处于正常水平")
    else:
        risk["波动率评估"] = f"年化波动率{annual_vol:.1%}，波动较小"
        risk["安全因素"].append(f"年化波动率仅{annual_vol:.1%}，价格相对稳定")

    if max_drawdown < -0.3:
        risk["风险因素"].append(f"近期最大回撤{max_drawdown:.1%}，回撤幅度较大，需注意下行风险")
    elif max_drawdown < -0.15:
        risk["风险因素"].append(f"近期最大回撤{max_drawdown:.1%}，回撤幅度中等")
    else:
        risk["安全因素"].append(f"近期最大回撤{max_drawdown:.1%}，回撤控制较好")

    recent_5d_change = (close.iloc[-1] / close.iloc[-6] - 1) * 100 if len(close) >= 6 else 0
    recent_20d_change = (close.iloc[-1] / close.iloc[-21] - 1) * 100 if len(close) >= 21 else 0

    if abs(recent_5d_change) > 15:
        risk["风险因素"].append(f"近5日涨跌幅{recent_5d_change:.1f}%，短期波动剧烈")
    if recent_20d_change > 30:
        risk["风险因素"].append(f"近20日涨幅{recent_20d_change:.1f}%，短期涨幅过大，回调风险增加")
    elif recent_20d_change < -30:
        risk["风险因素"].append(f"近20日跌幅{recent_20d_change:.1f}%，短期跌幅较大，但可能存在超跌反弹")

    turnover = quote.get("换手率", 0)
    if turnover > 15:
        risk["风险因素"].append(f"换手率{turnover:.1f}%，投机氛围浓厚，短期波动风险大")
    elif turnover < 1:
        risk["风险因素"].append(f"换手率仅{turnover:.1f}%，流动性不足，可能影响买卖操作")

    risk_count = len(risk["风险因素"])
    safety_count = len(risk["安全因素"])

    if risk_count >= 3:
        risk["风险等级"] = "高风险"
    elif risk_count >= 2:
        risk["风险等级"] = "中高风险"
    elif risk_count >= 1:
        risk["风险等级"] = "中等风险"
    elif safety_count >= 2:
        risk["风险等级"] = "低风险"
    else:
        risk["风险等级"] = "中低风险"

    return risk