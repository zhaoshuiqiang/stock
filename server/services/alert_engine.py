import time
import logging
from datetime import datetime, timezone, timedelta

from server.config import ALERT_COOLDOWN

logger = logging.getLogger(__name__)

# 内存冷却记录：{alert_id: last_triggered_timestamp}
_cooldown_tracker: dict = {}


def _is_in_cooldown(alert_id: int, last_triggered: datetime) -> bool:
    """检查警报是否在冷却期内"""
    if alert_id in _cooldown_tracker:
        elapsed = time.time() - _cooldown_tracker[alert_id]
        if elapsed < ALERT_COOLDOWN:
            return True
    # 也检查数据库中的 last_triggered
    if last_triggered is not None:
        if last_triggered.tzinfo is None:
            delta = datetime.now() - last_triggered
        else:
            delta = datetime.now(timezone.utc) - last_triggered
        if delta.total_seconds() < ALERT_COOLDOWN:
            return True
    return False


def _update_cooldown(alert_id: int):
    """更新冷却记录"""
    _cooldown_tracker[alert_id] = time.time()


def check_alerts(alert_rules: list, quotes: dict) -> list:
    """
    检查报警规则。

    Args:
        alert_rules: AlertRule 对象列表
        quotes: {code: quote_dict} 行情数据字典

    Returns:
        list of dict: 触发的报警信息列表
    """
    triggered = []

    for rule in alert_rules:
        if not rule.enabled:
            continue

        code = rule.code
        quote = quotes.get(code)
        if not quote:
            continue

        # 冷却检查
        if _is_in_cooldown(rule.id, rule.last_triggered):
            continue

        alert_info = None

        if rule.alert_type == "price_up":
            price = quote.get("最新价", 0)
            if rule.threshold is not None and price >= rule.threshold:
                alert_info = {
                    "alert_id": rule.id,
                    "code": code,
                    "name": rule.name,
                    "alert_type": "price_up",
                    "message": f"{rule.name}({code}) 最新价 {price} 达到或超过阈值 {rule.threshold}",
                    "current_value": price,
                    "threshold": rule.threshold,
                }

        elif rule.alert_type == "price_down":
            price = quote.get("最新价", 0)
            if rule.threshold is not None and price <= rule.threshold:
                alert_info = {
                    "alert_id": rule.id,
                    "code": code,
                    "name": rule.name,
                    "alert_type": "price_down",
                    "message": f"{rule.name}({code}) 最新价 {price} 达到或低于阈值 {rule.threshold}",
                    "current_value": price,
                    "threshold": rule.threshold,
                }

        elif rule.alert_type == "pct_up":
            change_pct = quote.get("涨跌幅", 0)
            if rule.threshold is not None and change_pct >= rule.threshold:
                alert_info = {
                    "alert_id": rule.id,
                    "code": code,
                    "name": rule.name,
                    "alert_type": "pct_up",
                    "message": f"{rule.name}({code}) 涨幅 {change_pct}% 达到或超过阈值 {rule.threshold}%",
                    "current_value": change_pct,
                    "threshold": rule.threshold,
                }

        elif rule.alert_type == "pct_down":
            change_pct = quote.get("涨跌幅", 0)
            if rule.threshold is not None and change_pct <= -rule.threshold:
                alert_info = {
                    "alert_id": rule.id,
                    "code": code,
                    "name": rule.name,
                    "alert_type": "pct_down",
                    "message": f"{rule.name}({code}) 跌幅 {change_pct}% 达到或超过阈值 {rule.threshold}%",
                    "current_value": change_pct,
                    "threshold": -rule.threshold,
                }

        elif rule.alert_type == "indicator":
            # 指标类型报警需要结合技术分析，由调用方传入预计算的信号
            # 这里仅做占位，实际检测由调用方在传入前完成
            pass

        if alert_info:
            _update_cooldown(rule.id)
            triggered.append(alert_info)

    return triggered


def check_alerts_with_signals(alert_rules: list, quotes: dict, signals_map: dict) -> list:
    """
    检查报警规则（支持指标信号）。

    Args:
        alert_rules: AlertRule 对象列表
        quotes: {code: quote_dict} 行情数据字典
        signals_map: {code: [signal_dict, ...]} 预计算的技术信号

    Returns:
        list of dict: 触发的报警信息列表
    """
    triggered = check_alerts(alert_rules, quotes)

    for rule in alert_rules:
        if not rule.enabled:
            continue

        if rule.alert_type != "indicator":
            continue

        code = rule.code
        if _is_in_cooldown(rule.id, rule.last_triggered):
            continue

        signals = signals_map.get(code, [])
        if not signals:
            continue

        # 检查指标信号是否匹配
        indicator_type = rule.indicator_type
        if not indicator_type:
            continue

        for sig in signals:
            sig_key = f"{sig.get('indicator', '')}_{sig.get('signal', '')}"
            # 匹配规则：indicator_type 可以是 "MACD_MACD金叉" 等形式
            if indicator_type.lower() in sig_key.lower() or sig_key.lower() in indicator_type.lower():
                alert_info = {
                    "alert_id": rule.id,
                    "code": code,
                    "name": rule.name,
                    "alert_type": "indicator",
                    "message": f"{rule.name}({code}) 触发指标信号：{sig.get('indicator', '')} - {sig.get('signal', '')}：{sig.get('desc', '')}",
                    "current_value": sig.get("signal", ""),
                    "threshold": None,
                    "signal_detail": sig,
                }
                _update_cooldown(rule.id)
                triggered.append(alert_info)
                break

    return triggered