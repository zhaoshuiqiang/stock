import streamlit as st
import plotly.graph_objects as go
from plotly.subplots import make_subplots
import pandas as pd
import json
import os

from data_fetcher import search_stock, get_realtime_quote, get_stock_history, get_market_sentiment
from indicators import calc_all_indicators, get_indicator_summary
from signals import detect_all_signals, get_signal_score
from advisor import generate_advice, assess_risk

WATCHLIST_FILE = "watchlist.json"


def load_watchlist():
    if "watchlist" in st.session_state:
        return st.session_state.watchlist
    if os.path.exists(WATCHLIST_FILE):
        with open(WATCHLIST_FILE, "r", encoding="utf-8") as f:
            wl = json.load(f)
    else:
        wl = []
    st.session_state.watchlist = wl
    return wl


def save_watchlist(watchlist):
    st.session_state.watchlist = watchlist
    with open(WATCHLIST_FILE, "w", encoding="utf-8") as f:
        json.dump(watchlist, f, ensure_ascii=False, indent=2)


def add_to_watchlist(code_name: str):
    watchlist = load_watchlist()
    if code_name not in watchlist:
        watchlist.append(code_name)
        save_watchlist(watchlist)


def remove_from_watchlist(code_name: str):
    watchlist = load_watchlist()
    if code_name in watchlist:
        watchlist.remove(code_name)
        save_watchlist(watchlist)


def extract_code(code_name: str) -> str:
    return code_name.split(" - ")[0].strip() if " - " in code_name else code_name.strip()


def render_price_chart(df: pd.DataFrame):
    fig = make_subplots(
        rows=4, cols=1,
        shared_xaxes=True,
        vertical_spacing=0.03,
        row_heights=[0.5, 0.15, 0.15, 0.2],
        subplot_titles=["K线与均线", "成交量", "MACD", "RSI"],
    )

    fig.add_trace(go.Candlestick(
        x=df["date"], open=df["open"], high=df["high"],
        low=df["low"], close=df["close"],
        increasing_line_color="#ef5350", decreasing_line_color="#26a69a",
        increasing_fillcolor="#ef5350", decreasing_fillcolor="#26a69a",
        name="K线",
    ), row=1, col=1)

    ma_colors = {"ma5": "#ffd54f", "ma10": "#42a5f5", "ma20": "#ab47bc", "ma60": "#ff7043"}
    for ma, color in ma_colors.items():
        if ma in df.columns:
            fig.add_trace(go.Scatter(
                x=df["date"], y=df[ma], mode="lines",
                line=dict(color=color, width=1),
                name=ma.upper(),
            ), row=1, col=1)

    if "boll_upper" in df.columns:
        fig.add_trace(go.Scatter(
            x=df["date"], y=df["boll_upper"], mode="lines",
            line=dict(color="rgba(173,216,230,0.5)", width=1), name="BOLL上轨",
        ), row=1, col=1)
        fig.add_trace(go.Scatter(
            x=df["date"], y=df["boll_lower"], mode="lines",
            line=dict(color="rgba(173,216,230,0.5)", width=1), name="BOLL下轨",
            fill="tonexty", fillcolor="rgba(173,216,230,0.1)",
        ), row=1, col=1)

    colors = ["#ef5350" if c >= o else "#26a69a" for c, o in zip(df["close"], df["open"])]
    fig.add_trace(go.Bar(
        x=df["date"], y=df["volume"], marker_color=colors, name="成交量", showlegend=False,
    ), row=2, col=1)

    if "vol_ma5" in df.columns:
        fig.add_trace(go.Scatter(
            x=df["date"], y=df["vol_ma5"], mode="lines",
            line=dict(color="#ffd54f", width=1), name="VOL5",
        ), row=2, col=1)
    if "vol_ma10" in df.columns:
        fig.add_trace(go.Scatter(
            x=df["date"], y=df["vol_ma10"], mode="lines",
            line=dict(color="#42a5f5", width=1), name="VOL10",
        ), row=2, col=1)

    if "dif" in df.columns:
        fig.add_trace(go.Scatter(
            x=df["date"], y=df["dif"], mode="lines",
            line=dict(color="#ffd54f", width=1), name="DIF",
        ), row=3, col=1)
        fig.add_trace(go.Scatter(
            x=df["date"], y=df["dea"], mode="lines",
            line=dict(color="#42a5f5", width=1), name="DEA",
        ), row=3, col=1)
        macd_colors = ["#ef5350" if v >= 0 else "#26a69a" for v in df["macd"]]
        fig.add_trace(go.Bar(
            x=df["date"], y=df["macd"], marker_color=macd_colors, name="MACD柱", showlegend=False,
        ), row=3, col=1)

    if "rsi6" in df.columns:
        fig.add_trace(go.Scatter(
            x=df["date"], y=df["rsi6"], mode="lines",
            line=dict(color="#ffd54f", width=1), name="RSI6",
        ), row=4, col=1)
        fig.add_trace(go.Scatter(
            x=df["date"], y=df["rsi12"], mode="lines",
            line=dict(color="#42a5f5", width=1), name="RSI12",
        ), row=4, col=1)
        fig.add_hline(y=70, line_dash="dash", line_color="rgba(255,0,0,0.3)", row=4, col=1)
        fig.add_hline(y=30, line_dash="dash", line_color="rgba(0,128,0,0.3)", row=4, col=1)

    fig.update_layout(
        height=800, xaxis_rangeslider_visible=False,
        template="plotly_dark", hovermode="x unified",
        margin=dict(l=50, r=50, t=30, b=30),
        legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1),
    )
    fig.update_xaxes(type="category", row=1, col=1)
    fig.update_xaxes(type="category", row=2, col=1)
    fig.update_xaxes(type="category", row=3, col=1)
    fig.update_xaxes(type="category", row=4, col=1)
    fig.update_traces(
        selector=dict(type="scatter"),
        line=dict(width=1),
    )

    st.plotly_chart(fig, use_container_width=True)


def render_kdj_chart(df: pd.DataFrame):
    if "k" not in df.columns:
        return
    fig = go.Figure()
    fig.add_trace(go.Scatter(x=df["date"], y=df["k"], mode="lines", line=dict(color="#ffd54f", width=1), name="K"))
    fig.add_trace(go.Scatter(x=df["date"], y=df["d"], mode="lines", line=dict(color="#42a5f5", width=1), name="D"))
    fig.add_trace(go.Scatter(x=df["date"], y=df["j"], mode="lines", line=dict(color="#ef5350", width=1), name="J"))
    fig.add_hline(y=80, line_dash="dash", line_color="rgba(255,0,0,0.3)")
    fig.add_hline(y=20, line_dash="dash", line_color="rgba(0,128,0,0.3)")
    fig.update_layout(
        title="KDJ指标", height=300, template="plotly_dark",
        margin=dict(l=50, r=50, t=40, b=30),
        legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1),
    )
    st.plotly_chart(fig, use_container_width=True)


def render_quote_card(quote: dict):
    pct = quote.get("涨跌幅", 0)
    color = "#ef5350" if pct > 0 else ("#26a69a" if pct < 0 else "#9e9e9e")
    arrow = "▲" if pct > 0 else ("▼" if pct < 0 else "—")

    col1, col2, col3, col4 = st.columns(4)
    with col1:
        st.markdown(f"""
        <div style="text-align:center; padding:10px; background:rgba(255,255,255,0.05); border-radius:10px; margin:5px;">
            <div style="font-size:14px; color:#9e9e9e;">最新价</div>
            <div style="font-size:28px; font-weight:bold; color:{color};">{quote.get('最新价', '--')}</div>
            <div style="font-size:14px; color:{color};">{arrow} {pct:.2f}%</div>
        </div>
        """, unsafe_allow_html=True)
    with col2:
        st.markdown(f"""
        <div style="text-align:center; padding:10px; background:rgba(255,255,255,0.05); border-radius:10px; margin:5px;">
            <div style="font-size:14px; color:#9e9e9e;">今开 / 昨收</div>
            <div style="font-size:20px; font-weight:bold; color:#fff;">{quote.get('今开', '--')} / {quote.get('昨收', '--')}</div>
        </div>
        """, unsafe_allow_html=True)
    with col3:
        st.markdown(f"""
        <div style="text-align:center; padding:10px; background:rgba(255,255,255,0.05); border-radius:10px; margin:5px;">
            <div style="font-size:14px; color:#9e9e9e;">最高 / 最低</div>
            <div style="font-size:20px; font-weight:bold; color:#fff;">{quote.get('最高', '--')} / {quote.get('最低', '--')}</div>
        </div>
        """, unsafe_allow_html=True)
    with col4:
        st.markdown(f"""
        <div style="text-align:center; padding:10px; background:rgba(255,255,255,0.05); border-radius:10px; margin:5px;">
            <div style="font-size:14px; color:#9e9e9e;">成交量 / 成交额</div>
            <div style="font-size:16px; font-weight:bold; color:#fff;">{quote.get('成交量', 0):.0f}手</div>
            <div style="font-size:14px; color:#9e9e9e;">{quote.get('成交额', 0)/1e8:.2f}亿</div>
        </div>
        """, unsafe_allow_html=True)

    col5, col6, col7, col8 = st.columns(4)
    with col5:
        st.metric("振幅", f"{quote.get('振幅', 0):.2f}%")
    with col6:
        st.metric("换手率", f"{quote.get('换手率', 0):.2f}%")
    with col7:
        st.metric("市盈率(动)", f"{quote.get('市盈率-动态', 0):.1f}")
    with col8:
        st.metric("市净率", f"{quote.get('市净率', 0):.2f}")


def render_signals_panel(signals: list, score: dict):
    direction = score.get("direction", "中性")
    confidence = score.get("confidence", 0)

    if direction == "偏多":
        dir_color = "#ef5350"
        dir_emoji = "🟢"
    elif direction == "偏空":
        dir_color = "#26a69a"
        dir_emoji = "🔴"
    else:
        dir_color = "#9e9e9e"
        dir_emoji = "⚪"

    st.markdown(f"""
    <div style="text-align:center; padding:15px; background:rgba(255,255,255,0.05); border-radius:10px; margin:10px 0;">
        <span style="font-size:24px;">{dir_emoji}</span>
        <span style="font-size:22px; font-weight:bold; color:{dir_color};">{direction}</span>
        <span style="font-size:14px; color:#9e9e9e; margin-left:10px;">置信度 {confidence}%</span>
        <span style="font-size:14px; color:#9e9e9e; margin-left:10px;">
            多头得分: {score.get('buy_score', 0)} | 空头得分: {score.get('sell_score', 0)}
        </span>
    </div>
    """, unsafe_allow_html=True)

    buy_signals = [s for s in signals if s["type"] == "buy"]
    sell_signals = [s for s in signals if s["type"] == "sell"]

    col_buy, col_sell = st.columns(2)

    with col_buy:
        st.markdown("### 🟢 买入信号")
        if buy_signals:
            for s in buy_signals:
                strength_icon = "🔥" if s["strength"] == "强" else ("⚡" if s["strength"] == "中" else "💡")
                st.markdown(f"""
                <div style="padding:8px; background:rgba(239,83,80,0.1); border-left:3px solid #ef5350; border-radius:5px; margin:5px 0;">
                    <strong>{strength_icon} [{s['indicator']}] {s['signal']}</strong><br>
                    <span style="font-size:13px; color:#bdbdbd;">{s['desc']}</span>
                </div>
                """, unsafe_allow_html=True)
        else:
            st.info("暂无买入信号")

    with col_sell:
        st.markdown("### 🔴 卖出信号")
        if sell_signals:
            for s in sell_signals:
                strength_icon = "🔥" if s["strength"] == "强" else ("⚡" if s["strength"] == "中" else "💡")
                st.markdown(f"""
                <div style="padding:8px; background:rgba(38,166,154,0.1); border-left:3px solid #26a69a; border-radius:5px; margin:5px 0;">
                    <strong>{strength_icon} [{s['indicator']}] {s['signal']}</strong><br>
                    <span style="font-size:13px; color:#bdbdbd;">{s['desc']}</span>
                </div>
                """, unsafe_allow_html=True)
        else:
            st.info("暂无卖出信号")


def render_advice_panel(advice: dict, risk: dict):
    col1, col2 = st.columns(2)

    with col1:
        st.markdown("### 📋 操作建议")
        rating = advice.get("综合评级", "")
        suggestion = advice.get("操作建议", "")
        st.markdown(f"""
        <div style="text-align:center; padding:15px; background:rgba(255,255,255,0.05); border-radius:10px; margin:10px 0;">
            <div style="font-size:14px; color:#9e9e9e;">综合评级</div>
            <div style="font-size:24px; font-weight:bold; color:#ffd54f;">{rating}</div>
            <div style="font-size:18px; color:#fff; margin-top:5px;">{suggestion}</div>
        </div>
        """, unsafe_allow_html=True)

        details = advice.get("建议详情", [])
        if details:
            st.markdown("**建议详情：**")
            for d in details:
                st.markdown(f"- {d}")

    with col2:
        st.markdown("### ⚠️ 风险评估")
        risk_level = risk.get("风险等级", "")
        risk_color = {"高风险": "#ef5350", "中高风险": "#ff7043", "中等风险": "#ffd54f", "中低风险": "#66bb6a", "低风险": "#26a69a"}.get(risk_level, "#9e9e9e")
        st.markdown(f"""
        <div style="text-align:center; padding:15px; background:rgba(255,255,255,0.05); border-radius:10px; margin:10px 0;">
            <div style="font-size:14px; color:#9e9e9e;">风险等级</div>
            <div style="font-size:24px; font-weight:bold; color:{risk_color};">{risk_level}</div>
            <div style="font-size:14px; color:#9e9e9e; margin-top:5px;">{risk.get('波动率评估', '')}</div>
        </div>
        """, unsafe_allow_html=True)

        risk_factors = risk.get("风险因素", [])
        safety_factors = risk.get("安全因素", [])
        if risk_factors:
            st.markdown("**风险因素：**")
            for r in risk_factors:
                st.markdown(f"- 🔴 {r}")
        if safety_factors:
            st.markdown("**安全因素：**")
            for s in safety_factors:
                st.markdown(f"- 🟢 {s}")


def render_opportunity_risk(advice: dict):
    col1, col2 = st.columns(2)

    with col1:
        st.markdown("### 🌟 机会分析")
        opportunities = advice.get("机会分析", [])
        if opportunities:
            for o in opportunities:
                st.markdown(f"""
                <div style="padding:8px; background:rgba(239,83,80,0.08); border-left:3px solid #ef5350; border-radius:5px; margin:5px 0;">
                    {o}
                </div>
                """, unsafe_allow_html=True)
        else:
            st.info("暂无明显机会信号")

    with col2:
        st.markdown("### ⚡ 风险提示")
        risks = advice.get("风险提示", [])
        if risks:
            for r in risks:
                st.markdown(f"""
                <div style="padding:8px; background:rgba(38,166,154,0.08); border-left:3px solid #26a69a; border-radius:5px; margin:5px 0;">
                    {r}
                </div>
                """, unsafe_allow_html=True)
        else:
            st.info("暂无明显风险信号")


def render_indicator_table(summary: dict):
    if not summary:
        st.info("暂无指标数据")
        return

    rows = []
    for key, val in summary.items():
        if "信号" in key or "位置" in key:
            rows.append({"指标类别": key, "数值/判断": val})
        else:
            rows.append({"指标类别": key, "数值/判断": val})

    st.dataframe(
        pd.DataFrame(rows),
        use_container_width=True,
        hide_index=True,
        column_config={
            "指标类别": st.column_config.TextColumn("指标类别", width="medium"),
            "数值/判断": st.column_config.TextColumn("数值/判断", width="large"),
        },
    )


def main():
    st.set_page_config(
        page_title="股票监控分析工具",
        page_icon="📊",
        layout="wide",
        initial_sidebar_state="expanded",
    )

    st.markdown("""
    <style>
    .stMetric { background: rgba(255,255,255,0.05); border-radius: 8px; padding: 10px; }
    </style>
    """, unsafe_allow_html=True)

    st.title("📊 股票数据监控与分析工具")
    st.caption("数据来源：新浪财经（akshare） | 免费开源 | 仅供参考，不构成投资建议")

    with st.sidebar:
        st.header("🔍 股票搜索与管理")

        search_keyword = st.text_input("输入股票代码或名称搜索", placeholder="如：002384 或 东山精密")

        if search_keyword:
            with st.spinner("搜索中，首次加载可能需要几秒..."):
                results = search_stock(search_keyword)
            if results:
                selected = st.selectbox("搜索结果", ["请选择..."] + results)
                if selected != "请选择...":
                    if st.button("➕ 添加到关注列表", use_container_width=True):
                        add_to_watchlist(selected)
                        st.success(f"已添加：{selected}")
                        st.rerun()
            else:
                st.warning("未找到匹配的股票，请检查输入的代码或名称是否正确")

        st.divider()
        st.header("📋 关注列表")
        watchlist = load_watchlist()

        if watchlist:
            for item in watchlist:
                col_item, col_del = st.columns([4, 1])
                with col_item:
                    if st.button(f"📌 {item}", key=f"select_{item}", use_container_width=True):
                        st.session_state["selected_stock"] = item
                with col_del:
                    if st.button("🗑️", key=f"del_{item}"):
                        remove_from_watchlist(item)
                        st.rerun()
        else:
            st.info("关注列表为空，请搜索添加股票")

        st.divider()
        st.header("⏱️ 数据刷新")
        refresh_interval = st.selectbox(
            "自动刷新间隔",
            [30, 60, 120, 300, 600],
            index=1,
            format_func=lambda x: f"{x}秒",
        )
        if st.button("🔄 立即刷新", use_container_width=True):
            st.cache_data.clear()
            st.rerun()

        st.divider()
        st.header("📈 大盘情绪")
        with st.spinner("获取市场数据..."):
            sentiment = get_market_sentiment()
        if sentiment:
            up = sentiment.get("上涨家数", 0)
            down = sentiment.get("下跌家数", 0)
            total = up + down
            ratio = up / total * 100 if total > 0 else 50
            bar_color = "#ef5350" if ratio > 50 else "#26a69a"
            st.markdown(f"""
            <div style="background:rgba(255,255,255,0.05); border-radius:10px; padding:10px; margin:5px 0;">
                <div style="font-size:13px; color:#9e9e9e;">上涨/下跌</div>
                <div style="font-size:16px; font-weight:bold;">
                    <span style="color:#ef5350;">{up}</span> / <span style="color:#26a69a;">{down}</span>
                </div>
                <div style="background:#333; border-radius:5px; height:8px; margin-top:5px;">
                    <div style="background:{bar_color}; border-radius:5px; height:8px; width:{ratio}%;"></div>
                </div>
                <div style="font-size:12px; color:#9e9e9e; margin-top:3px;">
                    涨停{sentiment.get('涨停家数', 0)} | 跌停{sentiment.get('跌停家数', 0)} | 均幅{sentiment.get('平均涨跌幅', 0)}%
                </div>
            </div>
            """, unsafe_allow_html=True)

    selected_stock = st.session_state.get("selected_stock", None)

    if not selected_stock and watchlist:
        selected_stock = watchlist[0]
        st.session_state["selected_stock"] = selected_stock

    if not selected_stock:
        st.markdown("""
        <div style="text-align:center; padding:80px 20px;">
            <div style="font-size:48px;">📊</div>
            <div style="font-size:24px; font-weight:bold; margin:20px 0;">欢迎使用股票监控分析工具</div>
            <div style="font-size:16px; color:#9e9e9e;">请在左侧搜索并添加股票到关注列表开始使用</div>
        </div>
        """, unsafe_allow_html=True)
        return

    code = extract_code(selected_stock)

    with st.spinner("获取行情数据..."):
        quote = get_realtime_quote(code)

    if not quote:
        st.error(f"无法获取 {selected_stock} 的行情数据，请检查股票代码是否正确")
        return

    st.header(f"📈 {quote.get('名称', selected_stock)} ({code})")
    render_quote_card(quote)

    tab_chart, tab_indicators, tab_signals, tab_advice = st.tabs(
        ["📈 K线图表", "📊 技术指标", "🔔 买卖信号", "💡 操作建议"]
    )

    with st.spinner("计算技术指标..."):
        df = get_stock_history(code, days=120)
        if not df.empty:
            df = calc_all_indicators(df)
            indicator_summary = get_indicator_summary(df)
            signals = detect_all_signals(df)
            score = get_signal_score(signals)
            advice = generate_advice(quote, indicator_summary, signals, score)
            risk = assess_risk(quote, df)
        else:
            indicator_summary = {}
            signals = []
            score = {"buy_score": 0, "sell_score": 0, "direction": "中性", "confidence": 0}
            advice = {"操作建议": "数据不足", "建议详情": [], "机会分析": [], "风险提示": [], "综合评级": ""}
            risk = {"风险等级": "数据不足", "风险因素": [], "安全因素": [], "波动率评估": ""}

    with tab_chart:
        if not df.empty:
            render_price_chart(df)
            render_kdj_chart(df)
        else:
            st.warning("暂无历史K线数据")

    with tab_indicators:
        if indicator_summary:
            render_indicator_table(indicator_summary)
        else:
            st.warning("暂无技术指标数据")

    with tab_signals:
        render_signals_panel(signals, score)

    with tab_advice:
        render_advice_panel(advice, risk)
        st.divider()
        render_opportunity_risk(advice)

    st.markdown("---")
    st.caption("⚠️ 免责声明：本工具仅供学习研究使用，所有分析结果均基于技术指标，不构成任何投资建议。投资有风险，入市需谨慎。")

    st.markdown(f"""
    <script>
        setTimeout(function() {{
            window.location.reload();
        }}, {refresh_interval * 1000});
    </script>
    """, unsafe_allow_html=True)


if __name__ == "__main__":
    main()
