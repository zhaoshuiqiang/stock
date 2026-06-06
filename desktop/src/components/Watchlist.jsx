/*
 * @Author: error: error: git config user.name & please set dead value or install git && error: git config user.email & please set dead value or install git & please set dead value or install git
 * @Date: 2026-06-06 20:21:45
 * @LastEditors: error: error: git config user.name & please set dead value or install git && error: git config user.email & please set dead value or install git & please set dead value or install git
 * @LastEditTime: 2026-06-06 20:21:47
 * @FilePath: \stock\desktop\src\components\Watchlist.jsx
 * @Description: 这是默认设置,请设置`customMade`, 打开koroFileHeader查看配置 进行设置: https://github.com/OBKoro1/koro1FileHeader/wiki/%E9%85%8D%E7%BD%AE
 */
import React, { useState } from 'react';
import { removeFromWatchlist } from '../api';

export default function Watchlist({ watchlist, onSelectStock, onWatchlistChange, selectedStock }) {
  const [removing, setRemoving] = useState(null);

  const handleRemove = async (e, code) => {
    e.stopPropagation();
    setRemoving(code);
    try {
      await removeFromWatchlist(code);
      onWatchlistChange();
    } catch (err) {
      alert('移除失败: ' + err.message);
    } finally {
      setRemoving(null);
    }
  };

  const isSelected = (item) => {
    if (!selectedStock) return false;
    const selCode = selectedStock.code || selectedStock;
    return item.code === selCode;
  };

  return (
    <div className="watchlist-panel">
      <div className="panel-header">
        <span className="panel-title">⭐ 自选股</span>
        <span className="panel-count">{watchlist.length}</span>
      </div>
      <div className="watchlist-items">
        {watchlist.length === 0 ? (
          <div className="watchlist-empty">暂无自选股</div>
        ) : (
          watchlist.map(item => (
            <div
              key={item.code}
              className={`watchlist-item ${isSelected(item) ? 'selected' : ''}`}
              onClick={() => onSelectStock(item)}
            >
              <div className="watchlist-item-main">
                <span className="watchlist-code">{item.code}</span>
                <span className="watchlist-name">{item.name}</span>
              </div>
              <div className="watchlist-item-actions">
                {item.price !== undefined && (
                  <span className={`watchlist-price ${(item.change_pct || 0) >= 0 ? 'up' : 'down'}`}>
                    {typeof item.price === 'number' ? item.price.toFixed(2) : item.price}
                  </span>
                )}
                <button
                  className="watchlist-remove-btn"
                  onClick={(e) => handleRemove(e, item.code)}
                  disabled={removing === item.code}
                  title="移除自选"
                >
                  {removing === item.code ? '...' : '✕'}
                </button>
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}