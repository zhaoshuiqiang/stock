import React from 'react';

export default function TrendSignalsPanel({ techAnalysis, loading }) {
  if (loading) {
    return (
      <div className="panel-container">
        <div className="panel-loading">加载趋势信号中...</div>
      </div>
    );
  }

  if (!techAnalysis || !techAnalysis.trend_signals) {
    return (
      <div className="panel-container">
        <div className="panel-empty">暂无趋势信号数据</div>
      </div>
    );
  }

  const signals = techAnalysis.trend_signals;
  const stabilization = signals.stabilization || [];
  const top = signals.top || [];
  const bottom = signals.bottom || [];

  const hasSignals = stabilization.length > 0 || top.length > 0 || bottom.length > 0;

  return (
    <div className="panel-container">
      <div className="panel-title-bar">
        <span className="panel-title-text">📊 趋势信号分析</span>
      </div>

      {!hasSignals ? (
        <div className="panel-empty">当前未检测到明显的趋势信号</div>
      ) : (
        <div className="trend-signals-grid">
          {/* 企稳信号 */}
          {stabilization.length > 0 && (
            <div className="trend-signal-section">
              <h3 className="trend-signal-title stabilization-title">
                🟡 企稳信号 ({stabilization.length})
              </h3>
              <div className="trend-signal-list">
                {stabilization.map((signal, idx) => (
                  <div key={idx} className="trend-signal-card stabilization-card">
                    <div className="trend-signal-icon">✓</div>
                    <div className="trend-signal-content">
                      <span className="trend-signal-name">{signal}</span>
                      <span className="trend-signal-desc">价格可能企稳，关注后续走势</span>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* 见顶信号 */}
          {top.length > 0 && (
            <div className="trend-signal-section">
              <h3 className="trend-signal-title top-title">
                🔴 见顶信号 ({top.length})
              </h3>
              <div className="trend-signal-list">
                {top.map((signal, idx) => (
                  <div key={idx} className="trend-signal-card top-card">
                    <div className="trend-signal-icon">⚠</div>
                    <div className="trend-signal-content">
                      <span className="trend-signal-name">{signal}</span>
                      <span className="trend-signal-desc">警惕回调风险，考虑减仓</span>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* 见底信号 */}
          {bottom.length > 0 && (
            <div className="trend-signal-section">
              <h3 className="trend-signal-title bottom-title">
                🟢 见底信号 ({bottom.length})
              </h3>
              <div className="trend-signal-list">
                {bottom.map((signal, idx) => (
                  <div key={idx} className="trend-signal-card bottom-card">
                    <div className="trend-signal-icon">↑</div>
                    <div className="trend-signal-content">
                      <span className="trend-signal-name">{signal}</span>
                      <span className="trend-signal-desc">可能出现反弹，关注买入机会</span>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}

      {/* 综合提示 */}
      {hasSignals && (
        <div className="trend-signal-summary">
          <div className="summary-item">
            <span className="summary-label">企稳信号:</span>
            <span className={`summary-value ${stabilization.length > 0 ? 'stabilization-text' : ''}`}>
              {stabilization.length > 0 ? `${stabilization.length}个` : '无'}
            </span>
          </div>
          <div className="summary-item">
            <span className="summary-label">见顶信号:</span>
            <span className={`summary-value ${top.length > 0 ? 'top-text' : ''}`}>
              {top.length > 0 ? `${top.length}个` : '无'}
            </span>
          </div>
          <div className="summary-item">
            <span className="summary-label">见底信号:</span>
            <span className={`summary-value ${bottom.length > 0 ? 'bottom-text' : ''}`}>
              {bottom.length > 0 ? `${bottom.length}个` : '无'}
            </span>
          </div>
        </div>
      )}
    </div>
  );
}
