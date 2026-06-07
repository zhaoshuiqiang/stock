"""技术分析 API"""
from fastapi import APIRouter, HTTPException

from server.models.schemas import AnalysisResult, TechnicalAnalysis

router = APIRouter()


def _get_analysis_services():
    """延迟导入分析服务"""
    try:
        from server.services.data_fetcher import get_realtime_quote, get_stock_history
        from server.services.indicators import calc_all_indicators, get_indicator_summary, calc_support_resistance
        from server.services.patterns import detect_dragon_retreat, calc_fibonacci, detect_trend_signals
        from server.services.signals import detect_all_signals
        from server.services.advisor import generate_advice, generate_score, assess_risk
        return (
            get_realtime_quote,
            get_stock_history,
            calc_all_indicators,
            get_indicator_summary,
            calc_support_resistance,
            detect_dragon_retreat,
            calc_fibonacci,
            detect_trend_signals,
            detect_all_signals,
            generate_advice,
            generate_score,
            assess_risk,
        )
    except ImportError:
        return None


@router.get("/analysis/{code}", response_model=AnalysisResult)
async def get_analysis(code: str):
    services = _get_analysis_services()
    if services is None:
        raise HTTPException(status_code=503, detail="分析服务暂不可用，请确保 services 模块已创建")

    (
        get_realtime_quote_fn,
        get_stock_history_fn,
        calc_all_indicators_fn,
        get_indicator_summary_fn,
        calc_support_resistance_fn,
        detect_dragon_retreat_fn,
        calc_fibonacci_fn,
        detect_trend_signals_fn,
        detect_all_signals_fn,
        generate_advice_fn,
        generate_score_fn,
        assess_risk_fn,
    ) = services

    quote = get_realtime_quote_fn(code)
    if not quote:
        raise HTTPException(status_code=404, detail=f"未找到股票 {code} 的行情数据")

    name = quote.get("名称", code)

    df = get_stock_history_fn(code, days=180)
    if df is None or df.empty:
        raise HTTPException(status_code=404, detail=f"未找到股票 {code} 的历史数据")

    df = calc_all_indicators_fn(df)

    indicator_summary = get_indicator_summary_fn(df)

    signals = detect_all_signals_fn(df)

    score = generate_score_fn(df)

    advice = generate_advice_fn(quote, indicator_summary, signals, score)

    risk = assess_risk_fn(quote, df) if callable(assess_risk_fn) else {}

    return AnalysisResult(
        code=code,
        name=name,
        quote=quote,
        indicator_summary=indicator_summary,
        signals=signals,
        score=score,
        advice=advice,
        risk=risk,
    )


@router.get("/levels/{code}", response_model=TechnicalAnalysis)
async def get_levels(code: str):
    services = _get_analysis_services()
    if services is None:
        raise HTTPException(status_code=503, detail="分析服务暂不可用")

    (
        get_realtime_quote_fn,
        get_stock_history_fn,
        calc_all_indicators_fn,
        _,
        calc_support_resistance_fn,
        _,
        _,
        _,
        _,
        _,
        _,
        _,
        _,
    ) = services

    df = get_stock_history_fn(code, days=60)
    if df is None or df.empty:
        raise HTTPException(status_code=404, detail=f"未找到股票 {code} 的历史数据")

    df = calc_all_indicators_fn(df)

    levels = calc_support_resistance_fn(df, window=20)

    quote = get_realtime_quote_fn(code) or {}
    name = quote.get("名称", code)

    return TechnicalAnalysis(
        code=code,
        name=name,
        support_levels=levels.get("support", []),
        resistance_levels=levels.get("resistance", []),
        nearest_support=levels.get("nearest_support"),
        nearest_resistance=levels.get("nearest_resistance"),
    )


@router.get("/patterns/{code}", response_model=TechnicalAnalysis)
async def get_patterns(code: str):
    services = _get_analysis_services()
    if services is None:
        raise HTTPException(status_code=503, detail="分析服务暂不可用")

    (
        get_realtime_quote_fn,
        get_stock_history_fn,
        calc_all_indicators_fn,
        _,
        _,
        detect_dragon_retreat_fn,
        _,
        _,
        _,
        _,
        _,
        _,
        _,
    ) = services

    df = get_stock_history_fn(code, days=60)
    if df is None or df.empty:
        raise HTTPException(status_code=404, detail=f"未找到股票 {code} 的历史数据")

    df = calc_all_indicators_fn(df)

    dragon_retreat = detect_dragon_retreat_fn(df)

    quote = get_realtime_quote_fn(code) or {}
    name = quote.get("名称", code)

    return TechnicalAnalysis(
        code=code,
        name=name,
        dragon_retreat=dragon_retreat,
    )


@router.get("/fibonacci/{code}", response_model=TechnicalAnalysis)
async def get_fibonacci(code: str):
    services = _get_analysis_services()
    if services is None:
        raise HTTPException(status_code=503, detail="分析服务暂不可用")

    (
        get_realtime_quote_fn,
        get_stock_history_fn,
        calc_all_indicators_fn,
        _,
        _,
        _,
        calc_fibonacci_fn,
        _,
        _,
        _,
        _,
        _,
        _,
    ) = services

    df = get_stock_history_fn(code, days=60)
    if df is None or df.empty:
        raise HTTPException(status_code=404, detail=f"未找到股票 {code} 的历史数据")

    fibonacci = calc_fibonacci_fn(df, window=20)

    quote = get_realtime_quote_fn(code) or {}
    name = quote.get("名称", code)

    return TechnicalAnalysis(
        code=code,
        name=name,
        fibonacci=fibonacci,
    )


@router.get("/trend-signals/{code}", response_model=TechnicalAnalysis)
async def get_trend_signals(code: str):
    services = _get_analysis_services()
    if services is None:
        raise HTTPException(status_code=503, detail="分析服务暂不可用")

    (
        get_realtime_quote_fn,
        get_stock_history_fn,
        calc_all_indicators_fn,
        _,
        _,
        _,
        _,
        detect_trend_signals_fn,
        _,
        _,
        _,
        _,
        _,
    ) = services

    df = get_stock_history_fn(code, days=60)
    if df is None or df.empty:
        raise HTTPException(status_code=404, detail=f"未找到股票 {code} 的历史数据")

    df = calc_all_indicators_fn(df)

    trend_signals = detect_trend_signals_fn(df)

    quote = get_realtime_quote_fn(code) or {}
    name = quote.get("名称", code)

    return TechnicalAnalysis(
        code=code,
        name=name,
        trend_signals=trend_signals,
    )