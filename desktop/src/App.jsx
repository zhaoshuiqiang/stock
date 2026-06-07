import React, { useState, useEffect, useCallback, useRef } from 'react';
import { createQuoteWebSocket, getWatchlist, getMarketSentiment, getAnalysis, getHistory, getQuote, getLevels, getPatterns, getFibonacci, getTrendSignals } from './api';
import SearchBar from './components/SearchBar';
import Watchlist from './components/Watchlist';
import QuoteCard from './components/QuoteCard';
import MarketSentiment from './components/MarketSentiment';
import KLineChart from './components/KLineChart';
import IndicatorTable from './components/IndicatorTable';
import SignalsPanel from './components/SignalsPanel';
import AdvicePanel from './components/AdvicePanel';
import TrendSignalsPanel from './components/TrendSignalsPanel';
import AlertManager from './components/AlertManager';

const TABS = [
  { key: 'kline', label: 'K线图表' },
  { key: 'indicators', label: '技术指标' },
  { key: 'signals', label: '买卖信号' },
  { key: 'trend_signals', label: '趋势信号' },
  { key: 'advice', label: '操作建议' }
];

export default function App() {
  const [selectedStock, setSelectedStock] = useState(null);
  const [quote, setQuote] = useState(null);
  const [watchlist, setWatchlist] = useState([]);
  const [sentiment, setSentiment] = useState(null);
  const [analysis, setAnalysis] = useState(null);
  const [history, setHistory] = useState(null);
  const [techAnalysis, setTechAnalysis] = useState(null);
  const [activeTab, setActiveTab] = useState('kline');
  const [wsConnected, setWsConnected] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const [appVersion, setAppVersion] = useState('');

  const wsRef = useRef(null);

  useEffect(() => {
    if (window.electronAPI?.getVersion) {
      window.electronAPI.getVersion().then(v => setAppVersion(v));
    }
  }, []);

  useEffect(() => {
    const ws = createQuoteWebSocket(
      (data) => {
        if (data.type === 'quote' && selectedStock) {
          if (data.code === selectedStock || data.code === selectedStock.code) {
            setQuote(data);
          }
        }
      },
      (connected) => setWsConnected(connected)
    );
    ws.connect();
    wsRef.current = ws;

    return () => ws.disconnect();
  }, []);

  useEffect(() => {
    if (wsRef.current.ws && selectedStock) {
    }
  }, [selectedStock]);

  const loadWatchlist = useCallback(async () => {
    try {
      const data = await getWatchlist();
      setWatchlist(Array.isArray(data) ? data : []);
    } catch (e) {
      setError('加载自选列表失败: ' + e.message);
    }
  }, []);

  const loadSentiment = useCallback(async () => {
    try {
      const data = await getMarketSentiment();
      setSentiment(data);
    } catch (e) {
    }
  }, []);

  useEffect(() => {
    loadWatchlist();
    loadSentiment();
  }, [loadWatchlist, loadSentiment]);

  const handleSelectStock = useCallback(async (stock) => {
    setSelectedStock(stock);
    setLoading(true);
    setError(null);
    setQuote(null);
    setAnalysis(null);
    setHistory(null);
    setTechAnalysis(null);

    try {
      const [quoteData, historyData, analysisData] = await Promise.all([
        getQuote(stock.code || stock),
        getHistory(stock.code || stock),
        getAnalysis(stock.code || stock)
      ]);
      setQuote(quoteData);
      setHistory(historyData);
      setAnalysis(analysisData);
      
      // Fetch technical analysis data
      try {
        const [levelsData, patternsData, fibonacciData, trendData] = await Promise.all([
          getLevels(stock.code || stock),
          getPatterns(stock.code || stock),
          getFibonacci(stock.code || stock),
          getTrendSignals(stock.code || stock)
        ]);
        setTechAnalysis({
          support_levels: levelsData?.support_levels || [],
          resistance_levels: levelsData?.resistance_levels || [],
          nearest_support: levelsData?.nearest_support,
          nearest_resistance: levelsData?.nearest_resistance,
          dragon_retreat: patternsData?.dragon_retreat || {found: false},
          fibonacci: fibonacciData?.fibonacci || {},
          trend_signals: trendData?.trend_signals || {}
        });
      } catch (e) {
        console.error('Failed to load technical analysis:', e);
      }
    } catch (e) {
      setError('加载股票数据失败: ' + e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  const handleWatchlistChange = useCallback(() => {
    loadWatchlist();
  }, [loadWatchlist]);

  return (
    <div className="app">
      <aside className="sidebar">
        <div className="sidebar-header">
          <h1 className="app-title">📈 股票分析系统</h1>
          {appVersion && <span className="version">v{appVersion}</span>}
        </div>

        <SearchBar onSelectStock={handleSelectStock} />

        <Watchlist
          watchlist={watchlist}
          onSelectStock={handleSelectStock}
          onWatchlistChange={handleWatchlistChange}
          selectedStock={selectedStock}
        />

        <MarketSentiment sentiment={sentiment} />
      </aside>

      <main className="main-content">
        {!selectedStock ? (
          <div className="welcome">
            <div className="welcome-icon">📊</div>
            <h2>欢迎使用股票分析系统</h2>
            <p>请搜索并选择一只股票开始分析</p>
            <div className="welcome-hints">
              <span>支持沪深A股实时行情</span>
              <span>技术指标综合分析</span>
              <span>智能买卖信号识别</span>
            </div>
          </div>
        ) : (
          <>
            <QuoteCard quote={quote} stock={selectedStock} loading={loading} />

            <div className="tab-bar">
              {TABS.map(tab => (
                <button
                  key={tab.key}
                  className={`tab-btn ${activeTab === tab.key ? 'active' : ''}`}
                  onClick={() => setActiveTab(tab.key)}
                >
                  {tab.label}
                </button>
              ))}
            </div>

            {error && (
              <div className="error-banner">
                <span>⚠️ {error}</span>
                <button onClick={() => setError(null)}>✕</button>
              </div>
            )}

            <div className="tab-content">
              {activeTab === 'kline' && (
                <KLineChart history={history} loading={loading} techAnalysis={techAnalysis} />
              )}
              {activeTab === 'indicators' && (
                <IndicatorTable analysis={analysis} loading={loading} />
              )}
              {activeTab === 'signals' && (
                <SignalsPanel analysis={analysis} loading={loading} />
              )}
              {activeTab === 'trend_signals' && (
                <TrendSignalsPanel techAnalysis={techAnalysis} loading={loading} />
              )}
              {activeTab === 'advice' && (
                <AdvicePanel analysis={analysis} loading={loading} />
              )}
            </div>
          </>
        )}
      </main>

      <footer className="status-bar">
        <div className="status-left">
          <span className={`status-dot ${wsConnected ? 'connected' : 'disconnected'}`}></span>
          <span>{wsConnected ? '实时数据已连接' : '实时数据未连接'}</span>
        </div>
        <div className="status-right">
          <button className="status-btn" onClick={() => loadSentiment()}>
            🔄 刷新市场数据
          </button>
          <AlertManager watchlist={watchlist} />
          <span className="status-time">
            {new Date().toLocaleTimeString('zh-CN')}
          </span>
        </div>
      </footer>
    </div>
  );
}