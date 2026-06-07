import akshare as ak
import pandas as pd
from datetime import datetime, timedelta
import time
import requests
import re
import logging

from server.config import CACHE_TTL_QUOTE, CACHE_TTL_HISTORY, CACHE_TTL_SENTIMENT

logger = logging.getLogger(__name__)

_session = requests.Session()
_session.headers.update({
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
})

_cache: dict = {}


def _get_cached(key: str, ttl: int):
    """从内存缓存中获取值，TTL 过期返回 None"""
    entry = _cache.get(key)
    if entry is None:
        return None
    if time.time() - entry["ts"] > ttl:
        del _cache[key]
        return None
    return entry["value"]


def _set_cache(key: str, value):
    """将值写入内存缓存"""
    _cache[key] = {"value": value, "ts": time.time()}


def _retry_request(func, max_retries=3, delay=2, **kwargs):
    last_error = None
    for i in range(max_retries):
        try:
            result = func(**kwargs)
            return result
        except Exception as e:
            last_error = e
            if i < max_retries - 1:
                time.sleep(delay)
    raise last_error


def search_stock(keyword: str) -> list:
    cache_key = f"search_{keyword}"
    cached = _get_cached(cache_key, 3600)
    if cached is not None:
        return cached

    try:
        df = _retry_request(ak.stock_info_a_code_name)
        mask = df["name"].str.contains(keyword, na=False) | df["code"].str.contains(
            keyword, na=False
        )
        results = df[mask][["code", "name"]].head(20)
        result = [f"{row['code']} - {row['name']}" for _, row in results.iterrows()]
        _set_cache(cache_key, result)
        return result
    except Exception as e:
        logger.error(f"搜索失败：{e}")
        return []


def _get_sina_quote(code: str) -> dict:
    if code.startswith("6"):
        prefix = "sh"
    elif code.startswith("0") or code.startswith("3"):
        prefix = "sz"
    elif code.startswith("8") or code.startswith("4"):
        prefix = "bj"
    else:
        prefix = "sz"

    symbol = f"{prefix}{code}"
    url = f"https://hq.sinajs.cn/list={symbol}"
    headers = {
        "Referer": "https://finance.sina.com.cn",
    }
    resp = _session.get(url, headers=headers, timeout=10)
    resp.encoding = "gbk"
    text = resp.text

    match = re.search(r'="([^"]*)"', text)
    if not match:
        return {}

    fields = match.group(1).split(",")
    if len(fields) < 32:
        return {}

    name = fields[0]
    open_price = float(fields[1]) if fields[1] else 0
    prev_close = float(fields[2]) if fields[2] else 0
    current = float(fields[3]) if fields[3] else 0
    high = float(fields[4]) if fields[4] else 0
    low = float(fields[5]) if fields[5] else 0
    volume = float(fields[8]) if fields[8] else 0
    amount = float(fields[9]) if fields[9] else 0

    change = current - prev_close if prev_close > 0 else 0
    pct_change = (change / prev_close * 100) if prev_close > 0 else 0
    amplitude = ((high - low) / prev_close * 100) if prev_close > 0 else 0

    return {
        "代码": code,
        "名称": name,
        "最新价": round(current, 2),
        "涨跌幅": round(pct_change, 2),
        "涨跌额": round(change, 2),
        "成交量": volume,
        "成交额": amount,
        "振幅": round(amplitude, 2),
        "最高": round(high, 2),
        "最低": round(low, 2),
        "今开": round(open_price, 2),
        "昨收": round(prev_close, 2),
        "量比": 0,
        "换手率": 0,
        "市盈率-动态": 0,
        "市净率": 0,
    }


def _get_all_stocks_spot() -> pd.DataFrame:
    """获取全市场实时行情数据（共享缓存）"""
    cache_key = "all_stocks_spot"
    cached = _get_cached(cache_key, CACHE_TTL_QUOTE)
    if cached is not None:
        return cached
    df = _retry_request(ak.stock_zh_a_spot)
    _set_cache(cache_key, df)
    return df


def get_realtime_quote(code: str) -> dict:
    cache_key = f"quote_{code}"
    cached = _get_cached(cache_key, CACHE_TTL_QUOTE)
    if cached is not None:
        return cached

    quote = None
    try:
        quote = _get_sina_quote(code)
    except Exception:
        pass

    if not quote:
        try:
            df = _get_all_stocks_spot()
            row = df[df["代码"].str.endswith(code, na=False)]
            if row.empty:
                row = df[df["代码"] == code]
            if row.empty:
                return {}
            r = row.iloc[0]
            quote = {
                "代码": code,
                "名称": r.get("名称", ""),
                "最新价": float(r.get("最新价", 0)) if pd.notna(r.get("最新价")) else 0,
                "涨跌幅": float(r.get("涨跌幅", 0)) if pd.notna(r.get("涨跌幅")) else 0,
                "涨跌额": float(r.get("涨跌额", 0)) if pd.notna(r.get("涨跌额")) else 0,
                "成交量": float(r.get("成交量", 0)) if pd.notna(r.get("成交量")) else 0,
                "成交额": float(r.get("成交额", 0)) if pd.notna(r.get("成交额")) else 0,
                "振幅": float(r.get("振幅", 0)) if pd.notna(r.get("振幅")) else 0,
                "最高": float(r.get("最高", 0)) if pd.notna(r.get("最高")) else 0,
                "最低": float(r.get("最低", 0)) if pd.notna(r.get("最低")) else 0,
                "今开": float(r.get("今开", 0)) if pd.notna(r.get("今开")) else 0,
                "昨收": float(r.get("昨收", 0)) if pd.notna(r.get("昨收")) else 0,
                "量比": float(r.get("量比", 0)) if pd.notna(r.get("量比")) else 0,
                "换手率": float(r.get("换手率", 0)) if pd.notna(r.get("换手率")) else 0,
                "市盈率-动态": float(r.get("市盈率-动态", 0)) if pd.notna(r.get("市盈率-动态")) else 0,
                "市净率": float(r.get("市净率", 0)) if pd.notna(r.get("市净率")) else 0,
            }
        except Exception as e:
            logger.error(f"获取实时行情失败：{e}")
            return {}

    # Sina data lacks turnover/PE/PB, supplement from akshare cache
    try:
        df = _get_all_stocks_spot()
        row = df[df["代码"].str.endswith(code, na=False)]
        if row.empty:
            row = df[df["代码"] == code]
        if not row.empty:
            r = row.iloc[0]
            quote["换手率"] = float(r.get("换手率", 0)) if pd.notna(r.get("换手率")) else 0
            quote["市盈率-动态"] = float(r.get("市盈率-动态", 0)) if pd.notna(r.get("市盈率-动态")) else 0
            quote["市净率"] = float(r.get("市净率", 0)) if pd.notna(r.get("市净率")) else 0
            quote["量比"] = float(r.get("量比", 0)) if pd.notna(r.get("量比")) else 0
            if quote.get("振幅", 0) == 0:
                quote["振幅"] = float(r.get("振幅", 0)) if pd.notna(r.get("振幅")) else 0
    except Exception:
        pass

    _set_cache(cache_key, quote)
    return quote


def get_stock_history(code: str, days: int = 180) -> pd.DataFrame:
    cache_key = f"history_{code}_{days}"
    cached = _get_cached(cache_key, CACHE_TTL_HISTORY)
    if cached is not None:
        return cached

    try:
        if code.startswith("6"):
            symbol = f"sh{code}"
        elif code.startswith("0") or code.startswith("3"):
            symbol = f"sz{code}"
        elif code.startswith("8") or code.startswith("4"):
            symbol = f"bj{code}"
        else:
            symbol = f"sz{code}"

        end_date = datetime.now().strftime("%Y%m%d")
        start_date = (datetime.now() - timedelta(days=days)).strftime("%Y%m%d")

        df = _retry_request(
            ak.stock_zh_a_daily,
            symbol=symbol,
            start_date=start_date,
            end_date=end_date,
            adjust="qfq",
        )
        if df is None or df.empty:
            return pd.DataFrame()

        df = df.rename(columns={
            "date": "date", "open": "open", "close": "close",
            "high": "high", "low": "low", "volume": "volume",
            "amount": "amount",
        })
        if "turnover" in df.columns:
            df = df.rename(columns={"turnover": "turnover"})
        else:
            df["turnover"] = 0

        df["date"] = pd.to_datetime(df["date"])
        for col in ["open", "close", "high", "low", "volume"]:
            df[col] = pd.to_numeric(df[col], errors="coerce")

        df["volume"] = df["volume"] / 100

        df["pct_change"] = df["close"].pct_change() * 100
        df["change"] = df["close"].diff()
        df["amplitude"] = 0

        df["pct_change"] = df["pct_change"].fillna(0)
        df["change"] = df["change"].fillna(0)

        if "turnover" in df.columns:
            df["turnover"] = pd.to_numeric(df.get("turnover", 0), errors="coerce")

        result = df.sort_values("date").reset_index(drop=True)
        _set_cache(cache_key, result)
        return result
    except Exception as e:
        logger.error(f"获取历史数据失败：{e}")
        return pd.DataFrame()


def get_market_sentiment() -> dict:
    cache_key = "market_sentiment"
    cached = _get_cached(cache_key, CACHE_TTL_SENTIMENT)
    if cached is not None:
        return cached

    try:
        df = _get_all_stocks_spot()
        up_count = len(df[df["涨跌幅"] > 0])
        down_count = len(df[df["涨跌幅"] < 0])
        flat_count = len(df[df["涨跌幅"] == 0])
        limit_up = len(df[df["涨跌幅"] >= 9.9])
        limit_down = len(df[df["涨跌幅"] <= -9.9])
        avg_change = df["涨跌幅"].mean() if not df.empty else 0
        total_amount = df["成交额"].sum() if not df.empty else 0
        result = {
            "上涨家数": up_count,
            "下跌家数": down_count,
            "平盘家数": flat_count,
            "涨停家数": limit_up,
            "跌停家数": limit_down,
            "平均涨跌幅": round(avg_change, 2),
            "总成交额(亿)": round(total_amount / 1e8, 2),
        }
        _set_cache(cache_key, result)
        return result
    except Exception:
        try:
            codes_df = _retry_request(ak.stock_info_a_code_name)
            total = len(codes_df)
            result = {
                "上涨家数": 0,
                "下跌家数": 0,
                "平盘家数": total,
                "涨停家数": 0,
                "跌停家数": 0,
                "平均涨跌幅": 0,
                "总成交额(亿)": 0,
            }
            _set_cache(cache_key, result)
            return result
        except Exception:
            return {}