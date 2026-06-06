import React from 'react';

function getSignalStrengthClass(strength) {
  const s = String(strength).toLowerCase();
  if (s === '强' || s === 'strong') return 'signal-strong';
  if (s === '中' || s === 'medium') return 'signal-medium';
  if (s === '弱' || s === 'weak') return 'signal-weak';
  return 'signal-weak';
}

function getSignalStrengthLabel(strength) {
  const s = String(strength);
  if (s === '强' || s === 'strong') return '强';
  if (s === '中' || s === 'medium') return '中';
  if (s === '弱' || s === 'weak') return '弱';
  return s || '弱';
}

export default function SignalsPanel({ analysis, loading }) {
  if (loading) {
    return (
      <div className="panel-container">
        <div className="panel-loading">加载买卖信号中...</div>
      </div>
    );
  }

  if (!analysis) {
    return (
      <div className="panel-container">
        <div className="panel-empty">暂无买卖信号数据</div>
      </div>
    );
  }

  const signals = analysis.signals || [];
  const buySignals = Array.isArray(signals)
    ? signals.filter(s => s.type === 'buy' || s.signal === 'buy' || s.direction === 'long')
    : [];
  const sellSignals = Array.isArray(signals)
    ? signals.filter(s => s.type === 'sell' || s.signal === 'sell' || s.direction === 'short')
    : [];

  return (
    <div className="panel-container">
      <div className="panel-title-bar">
        <span className="panel-title-text">📊 买卖信号</span>
      </div>

      <div className="signals-grid">
        {/* 买入信号 */}
        <div className="signals-column">
          <h3 className="signals-column-title up-text">🟢 买入信号</h3>
          {buySignals.length === 0 ? (
            <div className="signals-empty">暂无买入信号</div>
          ) : (
            buySignals.map((signal, idx) => (
              <div key={idx} className="signal-card signal-buy">
                <div className="signal-header">
                  <span className="signal-name">{signal.name || signal.indicator || '技术指标'}</span>
                  <span className={`signal-strength ${getSignalStrengthClass(signal.strength)}`}>
                    {getSignalStrengthLabel(signal.strength)}
                  </span>
                </div>
                <div className="signal-body">
                  <p className="signal-desc">{signal.desc || signal.description || signal.reason || '信号触发'}</p>
                  {signal.value !== undefined && (
                    <span className="signal-value">当前值: {signal.value}</span>
                  )}
                </div>
              </div>
            ))
          )}
        </div>

        {/* 卖出信号 */}
        <div className="signals-column">
          <h3 className="signals-column-title down-text">🔴 卖出信号</h3>
          {sellSignals.length === 0 ? (
            <div className="signals-empty">暂无卖出信号</div>
          ) : (
            sellSignals.map((signal, idx) => (
              <div key={idx} className="signal-card signal-sell">
                <div className="signal-header">
                  <span className="signal-name">{signal.name || signal.indicator || '技术指标'}</span>
                  <span className={`signal-strength ${getSignalStrengthClass(signal.strength)}`}>
                    {getSignalStrengthLabel(signal.strength)}
                  </span>
                </div>
                <div className="signal-body">
                  <p className="signal-desc">{signal.desc || signal.description || signal.reason || '信号触发'}</p>
                  {signal.value !== undefined && (
                    <span className="signal-value">当前值: {signal.value}</span>
                  )}
                </div>
              </div>
            ))
          )}
        </div>
      </div>

      {/* 综合信号强度 */}
      {analysis.score && (
        <div className="signal-overall">
          <span className="signal-overall-label">综合信号:</span>
          <span className={`signal-overall-value ${(analysis.score.direction || '').includes('多') ? 'up-text' : (analysis.score.direction || '').includes('空') ? 'down-text' : ''}`}>
            {analysis.score.direction || '中性'}
          </span>
          <span className="signal-overall-score">
            (置信度: {analysis.score.confidence ?? 0}%)
          </span>
        </div>
      )}
    </div>
  );
}