import React from 'react';

function formatNumber(num, decimals = 2) {
  if (num === null || num === undefined) return '-';
  return Number(num).toFixed(decimals);
}

function formatPercent(num) {
  if (num === null || num === undefined) return '-';
  const val = Number(num);
  const sign = val >= 0 ? '+' : '';
  return `${sign}${val.toFixed(2)}%`;
}

function formatVolume(num) {
  if (num === null || num === undefined) return '-';
  if (num >= 1e8) return (num / 1e8).toFixed(2) + '亿';
  if (num >= 1e4) return (num / 1e4).toFixed(2) + '万';
  return num.toString();
}

export default function QuoteCard({ quote, stock, loading }) {
  if (loading) {
    return (
      <div className="quote-card">
        <div className="quote-loading">加载行情数据中...</div>
      </div>
    );
  }

  if (!quote) {
    return (
      <div className="quote-card">
        <div className="quote-skeleton">
          <div className="skeleton-header"></div>
          <div className="skeleton-row"></div>
        </div>
      </div>
    );
  }

  const stockCode = stock?.code || quote.code || '';
  const stockName = stock?.name || quote.name || '';
  const price = quote.price ?? quote.current_price ?? quote.close;
  const change = quote.change ?? 0;
  const changePct = quote.change_pct ?? quote.pct_change ?? 0;
  const isUp = changePct >= 0;
  const open = quote.open ?? '-';
  const high = quote.high ?? '-';
  const low = quote.low ?? '-';
  const prevClose = quote.prev_close ?? quote.pre_close ?? '-';
  const volume = quote.volume ?? '-';
  const amount = quote.amount ?? quote.turnover ?? '-';
  const turnover = quote.turnover_rate ?? quote.turnover_pct ?? '-';
  const amplitude = quote.amplitude ?? '-';
  const highLimit = quote.high_limit ?? quote.limit_up ?? '-';
  const lowLimit = quote.low_limit ?? quote.limit_down ?? '-';

  return (
    <div className="quote-card">
      <div className="quote-header">
        <div className="quote-stock-info">
          <span className="quote-stock-name">{stockName}</span>
          <span className="quote-stock-code">{stockCode}</span>
        </div>
        <div className={`quote-price-main ${isUp ? 'up' : 'down'}`}>
          <span className="quote-price-value">{formatNumber(price)}</span>
        </div>
        <div className={`quote-change ${isUp ? 'up' : 'down'}`}>
          <span className="quote-change-value">{formatNumber(change)}</span>
          <span className="quote-change-pct">{formatPercent(changePct)}</span>
        </div>
      </div>

      <div className="quote-grid">
        <div className="quote-grid-item">
          <span className="quote-label">开盘</span>
          <span className="quote-value">{formatNumber(open)}</span>
        </div>
        <div className="quote-grid-item">
          <span className="quote-label">昨收</span>
          <span className="quote-value">{formatNumber(prevClose)}</span>
        </div>
        <div className="quote-grid-item">
          <span className="quote-label">最高</span>
          <span className={`quote-value ${isUp ? 'up-text' : 'down-text'}`}>{formatNumber(high)}</span>
        </div>
        <div className="quote-grid-item">
          <span className="quote-label">最低</span>
          <span className={`quote-value ${isUp ? 'down-text' : 'up-text'}`}>{formatNumber(low)}</span>
        </div>
        <div className="quote-grid-item">
          <span className="quote-label">成交量</span>
          <span className="quote-value">{formatVolume(volume)}</span>
        </div>
        <div className="quote-grid-item">
          <span className="quote-label">成交额</span>
          <span className="quote-value">{formatVolume(amount)}</span>
        </div>
        <div className="quote-grid-item">
          <span className="quote-label">换手率</span>
          <span className="quote-value">{turnover !== '-' ? formatPercent(turnover) : '-'}</span>
        </div>
        <div className="quote-grid-item">
          <span className="quote-label">振幅</span>
          <span className="quote-value">{amplitude !== '-' ? formatPercent(amplitude) : '-'}</span>
        </div>
        <div className="quote-grid-item">
          <span className="quote-label">涨停</span>
          <span className="quote-value up-text">{formatNumber(highLimit)}</span>
        </div>
        <div className="quote-grid-item">
          <span className="quote-label">跌停</span>
          <span className="quote-value down-text">{formatNumber(lowLimit)}</span>
        </div>
      </div>
    </div>
  );
}