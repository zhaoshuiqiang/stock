"""Pydantic 请求/响应模型"""
from pydantic import BaseModel, Field
from typing import Optional, List
from datetime import datetime


class StockSearchResult(BaseModel):
    code: str
    name: str
    display: str  # "code - name"


class QuoteData(BaseModel):
    code: str
    name: str
    price: float = Field(alias="最新价")
    change_pct: float = Field(alias="涨跌幅")
    change: float = Field(alias="涨跌额")
    volume: float = Field(alias="成交量")
    amount: float = Field(alias="成交额")
    amplitude: float = Field(alias="振幅")
    high: float = Field(alias="最高")
    low: float = Field(alias="最低")
    open: float = Field(alias="今开")
    prev_close: float = Field(alias="昨收")
    turnover: float = Field(alias="换手率")
    pe: float = Field(alias="市盈率-动态")
    pb: float = Field(alias="市净率")
    volume_ratio: float = Field(alias="量比")

    class Config:
        populate_by_name = True


class HistoryKline(BaseModel):
    date: str
    open: float
    close: float
    high: float
    low: float
    volume: float
    amount: float
    turnover: float
    pct_change: float
    change: float
    amplitude: float
    ma5: Optional[float] = None
    ma10: Optional[float] = None
    ma20: Optional[float] = None
    ma60: Optional[float] = None
    dif: Optional[float] = None
    dea: Optional[float] = None
    macd: Optional[float] = None
    rsi6: Optional[float] = None
    rsi12: Optional[float] = None
    rsi24: Optional[float] = None
    k: Optional[float] = None
    d: Optional[float] = None
    j: Optional[float] = None
    boll_upper: Optional[float] = None
    boll_mid: Optional[float] = None
    boll_lower: Optional[float] = None
    vol_ma5: Optional[float] = None
    vol_ma10: Optional[float] = None


class SignalItem(BaseModel):
    type: str       # buy / sell
    strength: str   # 强 / 中 / 弱
    indicator: str
    signal: str
    desc: str


class AnalysisResult(BaseModel):
    code: str
    name: str
    quote: dict
    indicator_summary: dict
    signals: List[SignalItem]
    score: dict
    advice: dict
    risk: dict


class WatchlistItem(BaseModel):
    code: str
    name: str
    added_at: Optional[datetime] = None


class WatchlistCreate(BaseModel):
    code: str
    name: str


class AlertRuleCreate(BaseModel):
    code: str
    name: str
    alert_type: str
    threshold: Optional[float] = None
    indicator_type: Optional[str] = None


class AlertRuleUpdate(BaseModel):
    enabled: Optional[bool] = None
    threshold: Optional[float] = None


class AlertRuleResponse(BaseModel):
    id: int
    code: str
    name: str
    alert_type: str
    threshold: Optional[float] = None
    indicator_type: Optional[str] = None
    enabled: bool
    last_triggered: Optional[datetime] = None
    created_at: datetime


class TechnicalAnalysis(BaseModel):
    """技术分析结果"""
    code: str
    name: str
    support_levels: List[float] = []
    resistance_levels: List[float] = []
    nearest_support: Optional[float] = None
    nearest_resistance: Optional[float] = None
    dragon_retreat: Optional[dict] = None
    fibonacci: Optional[dict] = None
    trend_signals: dict = {}
    chart_annotation: Optional[dict] = None


class MarketSentiment(BaseModel):
    up_count: int
    down_count: int
    flat_count: int
    limit_up: int
    limit_down: int
    avg_change: float
    total_amount_yi: float