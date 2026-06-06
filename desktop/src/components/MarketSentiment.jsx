/*
 * @Author: error: error: git config user.name & please set dead value or install git && error: git config user.email & please set dead value or install git & please set dead value or install git
 * @Date: 2026-06-06 20:22:35
 * @LastEditors: error: error: git config user.name & please set dead value or install git && error: git config user.email & please set dead value or install git & please set dead value or install git
 * @LastEditTime: 2026-06-06 20:22:37
 * @FilePath: \stock\desktop\src\components\MarketSentiment.jsx
 * @Description: 这是默认设置,请设置`customMade`, 打开koroFileHeader查看配置 进行设置: https://github.com/OBKoro1/koro1FileHeader/wiki/%E9%85%8D%E7%BD%AE
 */
import React from 'react';

export default function MarketSentiment({ sentiment }) {
  if (!sentiment) {
    return (
      <div className="sentiment-panel">
        <div className="panel-header">
          <span className="panel-title">📊 市场情绪</span>
        </div>
        <div className="sentiment-loading">加载中...</div>
      </div>
    );
  }

  const upCount = sentiment.up_count ?? sentiment.up ?? 0;
  const downCount = sentiment.down_count ?? sentiment.down ?? 0;
  const total = upCount + downCount;
  const upRatio = total > 0 ? (upCount / total * 100).toFixed(1) : 50;
  const downRatio = total > 0 ? (downCount / total * 100).toFixed(1) : 50;

  const getSentimentLabel = () => {
    const ratio = parseFloat(upRatio);
    if (ratio >= 70) return '🟢 强势';
    if (ratio >= 55) return '🔵 偏强';
    if (ratio >= 45) return '⚪ 中性';
    if (ratio >= 30) return '🟡 偏弱';
    return '🔴 弱势';
  };

  return (
    <div className="sentiment-panel">
      <div className="panel-header">
        <span className="panel-title">📊 市场情绪</span>
        <span className="sentiment-label-text">{getSentimentLabel()}</span>
      </div>

      <div className="sentiment-bar-wrapper">
        <div className="sentiment-bar">
          <div
            className="sentiment-bar-up"
            style={{ width: `${upRatio}%` }}
          ></div>
          <div
            className="sentiment-bar-down"
            style={{ width: `${downRatio}%` }}
          ></div>
        </div>
      </div>

      <div className="sentiment-numbers">
        <div className="sentiment-up-info">
          <span className="sentiment-up-label">上涨</span>
          <span className="sentiment-up-count">{upCount}</span>
          <span className="sentiment-up-pct">{upRatio}%</span>
        </div>
        <div className="sentiment-down-info">
          <span className="sentiment-down-label">下跌</span>
          <span className="sentiment-down-count">{downCount}</span>
          <span className="sentiment-down-pct">{downRatio}%</span>
        </div>
      </div>

      {sentiment.volume_ratio !== undefined && (
        <div className="sentiment-extra">
          <span>量比: {Number(sentiment.volume_ratio).toFixed(2)}</span>
        </div>
      )}
    </div>
  );
}