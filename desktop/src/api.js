const API_BASE = 'http://localhost:8000/api';
const WS_BASE = 'ws://localhost:8000';

// ==================== HTTP API ====================

async function request(url, options = {}) {
  try {
    const response = await fetch(url, {
      headers: { 'Content-Type': 'application/json' },
      ...options
    });
    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(errorText || `请求失败: ${response.status}`);
    }
    return await response.json();
  } catch (error) {
    if (error.message.includes('Failed to fetch') || error.message.includes('NetworkError')) {
      throw new Error('无法连接到后端服务，请确保服务器已启动 (http://localhost:8000)');
    }
    throw error;
  }
}

// 搜索股票
export async function searchStocks(keyword) {
  return request(`${API_BASE}/search?keyword=${encodeURIComponent(keyword)}`);
}

// 获取实时行情
export async function getQuote(code) {
  return request(`${API_BASE}/quote/${code}`);
}

// 获取历史K线数据
export async function getHistory(code, days = 120) {
  return request(`${API_BASE}/history/${code}?days=${days}`);
}

// 获取市场情绪
export async function getMarketSentiment() {
  return request(`${API_BASE}/market_sentiment`);
}

// 获取分析结果
export async function getAnalysis(code) {
  return request(`${API_BASE}/analysis/${code}`);
}

// 获取支撑压力位
export async function getLevels(code) {
  return request(`${API_BASE}/levels/${code}`);
}

// 获取龙回头形态
export async function getPatterns(code) {
  return request(`${API_BASE}/patterns/${code}`);
}

// 获取斐波那契回撤
export async function getFibonacci(code) {
  return request(`${API_BASE}/fibonacci/${code}`);
}

// 获取趋势信号
export async function getTrendSignals(code) {
  return request(`${API_BASE}/trend-signals/${code}`);
}

// 获取自选列表
export async function getWatchlist() {
  return request(`${API_BASE}/watchlist`);
}

// 添加到自选
export async function addToWatchlist(code, name) {
  return request(`${API_BASE}/watchlist`, {
    method: 'POST',
    body: JSON.stringify({ code, name })
  });
}

// 从自选移除
export async function removeFromWatchlist(code) {
  return request(`${API_BASE}/watchlist/${code}`, {
    method: 'DELETE'
  });
}

// 获取预警列表
export async function getAlerts() {
  return request(`${API_BASE}/alerts`);
}

// 创建预警
export async function createAlert(data) {
  return request(`${API_BASE}/alerts`, {
    method: 'POST',
    body: JSON.stringify(data)
  });
}

// 更新预警
export async function updateAlert(id, data) {
  return request(`${API_BASE}/alerts/${id}`, {
    method: 'PUT',
    body: JSON.stringify(data)
  });
}

// 删除预警
export async function deleteAlert(id) {
  return request(`${API_BASE}/alerts/${id}`, {
    method: 'DELETE'
  });
}

// ==================== WebSocket ====================

export function createQuoteWebSocket(onMessage, onStatusChange) {
  let ws = null;
  let reconnectTimer = null;
  let isConnected = false;

  function connect() {
    if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
      return;
    }

    try {
      ws = new WebSocket(`${WS_BASE}/ws/quote?user_id=default`);
    } catch (e) {
      scheduleReconnect();
      return;
    }

    ws.onopen = () => {
      isConnected = true;
      if (onStatusChange) onStatusChange(true);
    };

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);
        if (onMessage) onMessage(data);
      } catch (e) {
        // 忽略解析错误
      }
    };

    ws.onerror = () => {
      // WebSocket 错误，等待 onclose 处理重连
    };

    ws.onclose = () => {
      isConnected = false;
      if (onStatusChange) onStatusChange(false);
      ws = null;
      scheduleReconnect();
    };
  }

  function scheduleReconnect() {
    if (reconnectTimer) return;
    reconnectTimer = setTimeout(() => {
      reconnectTimer = null;
      connect();
    }, 3000);
  }

  function disconnect() {
    if (reconnectTimer) {
      clearTimeout(reconnectTimer);
      reconnectTimer = null;
    }
    if (ws) {
      ws.onclose = null; // 防止触发重连
      ws.close();
      ws = null;
    }
    isConnected = false;
    if (onStatusChange) onStatusChange(false);
  }

  return { connect, disconnect };
}