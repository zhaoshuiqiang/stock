"""技术分析 API"""
from fastapi import APIRouter, HTTPException

from server.models.schemas import AnalysisResult

router = APIRouter()


def _get_analysis_services():
    """延迟导入分析服务"""
    try:
        from server.services.data_fetcher import get_realtime_quote, get_stock_history
        from server.services.indicators import calc_all_indicators, get_indicator_summary
        from server.services.signals import detect_all_signals
        from server.services.advisor import generate_advice, generate_score, assess_risk
        return (
            get_realtime_quote,
            get_stock_history,
            calc_all_indicators,
            get_indicator_summary,
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
        detect_all_signals_fn,
        generate_advice_fn,
        generate_score_fn,
        assess_risk_fn,
    ) = services

    # 获取行情数据
    quote = get_realtime_quote_fn(code)
    if not quote:
        raise HTTPException(status_code=404, detail=f"未找到股票 {code} 的行情数据")

    name = quote.get("名称", code)

    # 获取历史数据
    df = get_stock_history_fn(code, days=180)
    if df is None or df.empty:
        raise HTTPException(status_code=404, detail=f"未找到股票 {code} 的历史数据")

    # 计算技术指标
    df = calc_all_indicators_fn(df)

    # 汇总指标
    indicator_summary = get_indicator_summary_fn(df)

    # 检测信号
    signals = detect_all_signals_fn(df)

    # 打分
    score = generate_score_fn(df)

    # 生成建议
    advice = generate_advice_fn(quote, indicator_summary, signals, score)

    # 风险评估
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