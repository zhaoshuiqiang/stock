"""行情数据 API"""
from fastapi import APIRouter, Query, HTTPException
from typing import List, Optional

from server.models.schemas import StockSearchResult, QuoteData, HistoryKline, MarketSentiment

router = APIRouter()


def _get_data_fetcher():
    """延迟导入 data_fetcher 服务"""
    try:
        from server.services.data_fetcher import (
            search_stock,
            get_realtime_quote,
            get_stock_history,
            get_market_sentiment,
        )
        return search_stock, get_realtime_quote, get_stock_history, get_market_sentiment
    except ImportError:
        return None, None, None, None


@router.get("/search", response_model=List[StockSearchResult])
async def search(keyword: str = Query(..., description="搜索关键词")):
    search_stock_fn, _, _, _ = _get_data_fetcher()
    if search_stock_fn is None:
        return []

    results = search_stock_fn(keyword)
    items = []
    for r in results:
        if isinstance(r, str):
            parts = r.split(" - ", 1)
            code = parts[0].strip()
            name = parts[1].strip() if len(parts) > 1 else code
            items.append(StockSearchResult(code=code, name=name, display=r))
        elif isinstance(r, dict):
            items.append(StockSearchResult(
                code=r.get("code", ""),
                name=r.get("name", ""),
                display=f"{r.get('code', '')} - {r.get('name', '')}",
            ))
    return items


@router.get("/quote/{code}")
async def get_quote(code: str):
    _, get_realtime_quote_fn, _, _ = _get_data_fetcher()
    if get_realtime_quote_fn is None:
        raise HTTPException(status_code=503, detail="行情服务暂不可用")

    quote = get_realtime_quote_fn(code)
    if not quote:
        raise HTTPException(status_code=404, detail=f"未找到股票 {code} 的行情数据")

    return {
        "code": code,
        "name": quote.get("名称", ""),
        "price": quote.get("最新价", 0),
        "change_pct": quote.get("涨跌幅", 0),
        "change": quote.get("涨跌额", 0),
        "volume": quote.get("成交量", 0),
        "amount": quote.get("成交额", 0),
        "amplitude": quote.get("振幅", 0),
        "high": quote.get("最高", 0),
        "low": quote.get("最低", 0),
        "open": quote.get("今开", 0),
        "prev_close": quote.get("昨收", 0),
        "turnover": quote.get("换手率", 0),
        "pe": quote.get("市盈率-动态", 0),
        "pb": quote.get("市净率", 0),
        "volume_ratio": quote.get("量比", 0),
    }


@router.get("/history/{code}", response_model=List[HistoryKline])
async def get_history(code: str, days: int = Query(120, ge=1, le=365)):
    _, _, get_stock_history_fn, _ = _get_data_fetcher()
    if get_stock_history_fn is None:
        return []

    df = get_stock_history_fn(code, days=days)
    if df is None or df.empty:
        return []

    klines = []
    for _, row in df.iterrows():
        klines.append(HistoryKline(
            date=str(row.get("date", ""))[:10],
            open=float(row.get("open", 0) or 0),
            close=float(row.get("close", 0) or 0),
            high=float(row.get("high", 0) or 0),
            low=float(row.get("low", 0) or 0),
            volume=float(row.get("volume", 0) or 0),
            amount=float(row.get("amount", 0) or 0),
            turnover=float(row.get("turnover", 0) or 0),
            pct_change=float(row.get("pct_change", 0) or 0),
            change=float(row.get("change", 0) or 0),
            amplitude=float(row.get("amplitude", 0) or 0),
        ))
    return klines


@router.get("/market_sentiment")
async def market_sentiment():
    _, _, _, get_market_sentiment_fn = _get_data_fetcher()
    if get_market_sentiment_fn is None:
        raise HTTPException(status_code=503, detail="行情服务暂不可用")

    data = get_market_sentiment_fn()
    if not data:
        return MarketSentiment(
            up_count=0, down_count=0, flat_count=0,
            limit_up=0, limit_down=0, avg_change=0, total_amount_yi=0,
        )

    return MarketSentiment(
        up_count=data.get("上涨家数", 0),
        down_count=data.get("下跌家数", 0),
        flat_count=data.get("平盘家数", 0),
        limit_up=data.get("涨停家数", 0),
        limit_down=data.get("跌停家数", 0),
        avg_change=data.get("平均涨跌幅", 0),
        total_amount_yi=data.get("总成交额(亿)", 0),
    )