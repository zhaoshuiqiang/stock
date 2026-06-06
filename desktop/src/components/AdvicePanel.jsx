import React from 'react';

function getRiskColor(level) {
  if (typeof level === 'string') {
    const l = level.toLowerCase();
    if (l.includes('低') || l === 'low') return 'risk-low';
    if (l.includes('高') || l === 'high') return 'risk-high';
  }
  return 'risk-medium';
}

function getRiskLabel(level) {
  if (typeof level === 'string') {
    if (level.includes('低')) return '🟢 ' + level;
    if (level.includes('高')) return '🔴 ' + level;
    if (level === 'low') return '� 低风险';
    if (level === 'high') return '🔴 高风险';
  }
  return '🟡 ' + (level || '中风险');
}

function getAdviceAction(adviceText) {
  if (!adviceText) return { text: '观望', className: 'advice-hold' };
  const t = adviceText.toLowerCase();
  if (t.includes('买入') || t.includes('介入') || t.includes('buy')) return { text: adviceText, className: 'advice-buy' };
  if (t.includes('卖出') || t.includes('减仓') || t.includes('sell')) return { text: adviceText, className: 'advice-sell' };
  if (t.includes('持有') || t.includes('hold')) return { text: adviceText, className: 'advice-hold' };
  return { text: adviceText, className: 'advice-hold' };
}

export default function AdvicePanel({ analysis, loading }) {
  if (loading) {
    return (
      <div className="panel-container">
        <div className="panel-loading">加载操作建议中...</div>
      </div>
    );
  }

  if (!analysis) {
    return (
      <div className="panel-container">
        <div className="panel-empty">暂无操作建议数据</div>
      </div>
    );
  }

  const advice = analysis.advice || analysis;
  const risk = analysis.risk || {};
  const riskLevel = risk['风险等级'] || risk.risk_level || risk.level || 'medium';
  const actionInfo = getAdviceAction(advice['操作建议'] || advice.action || advice.advice_action || '');
  const details = advice['建议详情'] || advice.reasons || advice.signals || [];
  const opportunities = advice['机会分析'] || [];
  const riskWarnings = advice['风险提示'] || [];
  const rating = advice['综合评级'] || advice.rating || '';
  const score = analysis.score || {};
  const confidence = score.confidence ?? advice.confidence ?? advice.score ?? null;

  return (
    <div className="panel-container">
      <div className="panel-title-bar">
        <span className="panel-title-text">💡 操作建议</span>
      </div>

      <div className="advice-main">
        <div className={`advice-action-card ${actionInfo.className}`}>
          <div className="advice-action-label">建议操作</div>
          <div className="advice-action-text">{actionInfo.text}</div>
          {confidence !== null && (
            <div className="advice-confidence">
              置信度: {Number(confidence).toFixed(0)}%
            </div>
          )}
          {rating && (
            <div className="advice-rating">{rating}</div>
          )}
        </div>

        <div className={`advice-risk-card ${getRiskColor(riskLevel)}`}>
          <div className="advice-risk-label">风险等级</div>
          <div className="advice-risk-text">{getRiskLabel(riskLevel)}</div>
        </div>
      </div>

      {/* 分析依据 */}
      {details.length > 0 && (
        <div className="advice-reasons">
          <h3 className="advice-reasons-title">📝 分析依据</h3>
          <ul className="advice-reasons-list">
            {details.map((reason, idx) => (
              <li key={idx} className="advice-reason-item">
                {typeof reason === 'string' ? reason : (reason.description || reason.reason || reason.name || '')}
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* 机会分析 */}
      {opportunities.length > 0 && (
        <div className="advice-reasons">
          <h3 className="advice-reasons-title">🟢 机会分析</h3>
          <ul className="advice-reasons-list">
            {opportunities.map((item, idx) => (
              <li key={idx} className="advice-reason-item up-text">
                {typeof item === 'string' ? item : (item.description || item.reason || '')}
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* 风险提示 */}
      {riskWarnings.length > 0 && (
        <div className="advice-reasons">
          <h3 className="advice-reasons-title">� 风险提示</h3>
          <ul className="advice-reasons-list">
            {riskWarnings.map((item, idx) => (
              <li key={idx} className="advice-reason-item down-text">
                {typeof item === 'string' ? item : (item.description || item.reason || '')}
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* 推荐仓位 */}
      {advice.position !== undefined && (
        <div className="advice-position">
          <span className="advice-position-label">📐 建议仓位:</span>
          <span className="advice-position-value">{(Number(advice.position) * 100).toFixed(0)}%</span>
        </div>
      )}

      {/* 摘要 */}
      {advice.summary && (
        <div className="advice-summary">
          <h3 className="advice-summary-title">📋 综合摘要</h3>
          <p className="advice-summary-text">{advice.summary}</p>
        </div>
      )}
    </div>
  );
}