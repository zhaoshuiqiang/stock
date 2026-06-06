import React, { useState, useEffect, useCallback } from 'react';
import { getAlerts, createAlert, updateAlert, deleteAlert } from '../api';

export default function AlertManager({ watchlist }) {
  const [isOpen, setIsOpen] = useState(false);
  const [alerts, setAlerts] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  // 新建预警表单
  const [showForm, setShowForm] = useState(false);
  const [formData, setFormData] = useState({
    code: '',
    name: '',
    type: 'price_above',
    threshold: '',
    enabled: true
  });

  const loadAlerts = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await getAlerts();
      setAlerts(Array.isArray(data) ? data : []);
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (isOpen) {
      loadAlerts();
    }
  }, [isOpen, loadAlerts]);

  const handleSubmit = async (e) => {
    e.preventDefault();
    if (!formData.code || !formData.threshold) {
      setError('请填写完整信息');
      return;
    }
    setLoading(true);
    setError(null);
    try {
      await createAlert({
        code: formData.code,
        name: formData.name,
        alert_type: formData.type,
        threshold: parseFloat(formData.threshold),
        enabled: formData.enabled
      });
      setShowForm(false);
      setFormData({ code: '', name: '', type: 'price_above', threshold: '', enabled: true });
      await loadAlerts();
    } catch (e) {
      setError(e.message);
    } finally {
      setLoading(false);
    }
  };

  const handleDelete = async (id) => {
    if (!confirm('确定要删除此预警吗？')) return;
    try {
      await deleteAlert(id);
      await loadAlerts();
    } catch (e) {
      setError(e.message);
    }
  };

  const handleToggle = async (alert) => {
    try {
      await updateAlert(alert.id || alert._id, { enabled: !alert.enabled });
      await loadAlerts();
    } catch (e) {
      setError(e.message);
    }
  };

  const alertTypeLabels = {
    price_up: '价格上破',
    price_down: '价格下破',
    pct_up: '涨幅超',
    pct_down: '跌幅超',
    volume_surge: '放量'
  };

  return (
    <>
      <button className="status-btn" onClick={() => setIsOpen(true)}>
        🔔 预警管理
      </button>

      {isOpen && (
        <div className="modal-overlay" onClick={() => setIsOpen(false)}>
          <div className="modal-content" onClick={(e) => e.stopPropagation()}>
            <div className="modal-header">
              <h2>🔔 预警管理</h2>
              <button className="modal-close" onClick={() => setIsOpen(false)}>✕</button>
            </div>

            <div className="modal-body">
              {error && <div className="modal-error">{error}</div>}

              <button
                className="modal-add-btn"
                onClick={() => setShowForm(!showForm)}
              >
                {showForm ? '取消' : '+ 新建预警'}
              </button>

              {showForm && (
                <form className="alert-form" onSubmit={handleSubmit}>
                  <div className="form-row">
                    <label>股票代码</label>
                    <select
                      value={formData.code}
                      onChange={(e) => {
                        const selected = watchlist.find(w => w.code === e.target.value);
                        setFormData({
                          ...formData,
                          code: e.target.value,
                          name: selected?.name || ''
                        });
                      }}
                    >
                      <option value="">选择股票</option>
                      {watchlist.map(w => (
                        <option key={w.code} value={w.code}>{w.code} {w.name}</option>
                      ))}
                    </select>
                  </div>
                  <div className="form-row">
                    <label>预警类型</label>
                    <select
                      value={formData.type}
                      onChange={(e) => setFormData({ ...formData, type: e.target.value })}
                    >
                      <option value="price_up">价格上破</option>
                      <option value="price_down">价格下破</option>
                      <option value="pct_up">涨幅超过</option>
                      <option value="pct_down">跌幅超过</option>
                      <option value="indicator">技术指标</option>
                    </select>
                  </div>
                  <div className="form-row">
                    <label>阈值</label>
                    <input
                      type="number"
                      step="0.01"
                      value={formData.threshold}
                      onChange={(e) => setFormData({ ...formData, threshold: e.target.value })}
                      placeholder="输入阈值"
                    />
                  </div>
                  <button type="submit" className="modal-submit-btn" disabled={loading}>
                    {loading ? '创建中...' : '创建预警'}
                  </button>
                </form>
              )}

              <div className="alert-list">
                {loading && <div className="alert-loading">加载中...</div>}
                {alerts.length === 0 && !loading && (
                  <div className="alert-empty">暂无预警规则</div>
                )}
                {alerts.map((alert) => (
                  <div key={alert.id || alert._id} className={`alert-item ${alert.enabled ? '' : 'alert-disabled'}`}>
                    <div className="alert-item-info">
                      <span className="alert-item-code">{alert.code}</span>
                      <span className="alert-item-name">{alert.name}</span>
                      <span className="alert-item-type">
                        {alertTypeLabels[alert.type] || alert.type}
                      </span>
                      <span className="alert-item-threshold">
                        {alert.threshold}
                      </span>
                    </div>
                    <div className="alert-item-actions">
                      <label className="alert-toggle">
                        <input
                          type="checkbox"
                          checked={alert.enabled}
                          onChange={() => handleToggle(alert)}
                        />
                        <span>启用</span>
                      </label>
                      <button
                        className="alert-delete-btn"
                        onClick={() => handleDelete(alert.id || alert._id)}
                      >
                        删除
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>
      )}
    </>
  );
}