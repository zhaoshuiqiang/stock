import React from 'react';

function formatVal(val, decimals = 2) {
  if (val === null || val === undefined) return '-';
  if (typeof val === 'number') return val.toFixed(decimals);
  return val;
}

export default function IndicatorTable({ analysis, loading }) {
  if (loading) {
    return (
      <div className="panel-container">
        <div className="panel-loading">加载技术指标中...</div>
      </div>
    );
  }

  if (!analysis) {
    return (
      <div className="panel-container">
        <div className="panel-empty">暂无技术指标数据</div>
      </div>
    );
  }

  // 后端返回 indicator_summary 为中文键名dict，如 {"均线位置": "...", "MACD信号": "..."}
  // 同时从 quote 中提取数值型指标
  const summary = analysis.indicator_summary || analysis.indicators || {};
  const stockName = analysis.name || analysis.stock_name || '';
  const quote = analysis.quote || {};

  // 数值型指标行（从quote提取）
  const numericRows = [
    { label: '股票名称', value: stockName },
    { label: '最新价', value: formatVal(quote['最新价'] ?? quote.price) },
    { label: '涨跌幅', value: formatVal(quote['涨跌幅'] ?? quote.change_pct) + '%' },
    { label: '成交量', value: formatVal(quote['成交量'] ?? quote.volume, 0) },
    { label: '换手率', value: formatVal(quote['换手率'] ?? quote.turnover) + '%' },
    { label: '市盈率', value: formatVal(quote['市盈率-动态'] ?? quote.pe) },
    { label: '市净率', value: formatVal(quote['市净率'] ?? quote.pb) },
  ].filter(r => r.value !== '-' && r.value !== '-%');

  // 摘要型指标行（从indicator_summary提取）
  const summaryRows = Object.entries(summary).map(([key, val]) => ({
    label: key,
    value: typeof val === 'object' ? JSON.stringify(val) : String(val),
  }));

  const rows = [...numericRows, ...summaryRows];

  return (
    <div className="panel-container">
      <div className="panel-title-bar">
        <span className="panel-title-text">📋 技术指标汇总</span>
      </div>
      <div className="indicator-table">
        <table>
          <thead>
            <tr>
              <th>指标名称</th>
              <th>数值</th>
              <th>状态</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row, idx) => {
              let status = '-';
              let statusClass = '';

              // 判断一些指标状态
              if (row.label === '涨跌幅') {
                const v = parseFloat(row.value);
                if (v > 0) { status = '上涨'; statusClass = 'status-up'; }
                else if (v < 0) { status = '下跌'; statusClass = 'status-down'; }
                else { status = '平盘'; statusClass = 'status-neutral'; }
              }
              if (row.label === 'MACD信号' || row.label === '均线信号') {
                const v = row.value;
                if (v.includes('金叉') || v.includes('多头')) { status = '偏多'; statusClass = 'status-up'; }
                else if (v.includes('死叉') || v.includes('空头')) { status = '偏空'; statusClass = 'status-down'; }
                else { status = '中性'; statusClass = 'status-neutral'; }
              }
              if (row.label === 'RSI状态') {
                const v = row.value;
                if (v.includes('超买')) { status = '注意'; statusClass = 'status-down'; }
                else if (v.includes('超卖')) { status = '关注'; statusClass = 'status-up'; }
                else { status = '中性'; statusClass = 'status-neutral'; }
              }

              return (
                <tr key={idx}>
                  <td className="indicator-name">{row.label}</td>
                  <td className="indicator-value">{row.value}</td>
                  <td className={`indicator-status ${statusClass}`}>{status}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}