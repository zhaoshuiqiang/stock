import React, { useRef, useEffect, useState, useCallback } from 'react';
import { drawLevelsOverlay } from './LevelsOverlay.jsx';
import { drawFibonacciOverlay } from './FibonacciOverlay.jsx';

// 简单的移动平均线计算
function calcMA(data, period) {
  const result = [];
  for (let i = 0; i < data.length; i++) {
    if (i < period - 1) {
      result.push(null);
    } else {
      let sum = 0;
      for (let j = i - period + 1; j <= i; j++) {
        sum += data[j].close;
      }
      result.push(sum / period);
    }
  }
  return result;
}

// EMA 计算
function calcEMA(data, period) {
  const result = [];
  const k = 2 / (period + 1);
  let ema = null;
  for (let i = 0; i < data.length; i++) {
    if (i === 0) {
      ema = data[i].close;
    } else if (i < period - 1) {
      result.push(null);
      continue;
    } else if (i === period - 1) {
      let sum = 0;
      for (let j = 0; j < period; j++) {
        sum += data[j].close;
      }
      ema = sum / period;
    } else {
      ema = data[i].close * k + ema * (1 - k);
    }
    result.push(ema);
  }
  return result;
}

// MACD 计算 (12, 26, 9)
function calcMACD(data) {
  const ema12 = calcEMA(data, 12);
  const ema26 = calcEMA(data, 26);
  const dif = [];
  const dea = [];
  const macdHist = [];

  for (let i = 0; i < data.length; i++) {
    if (ema12[i] === null || ema26[i] === null) {
      dif.push(null);
      dea.push(null);
      macdHist.push(null);
    } else {
      dif.push(ema12[i] - ema26[i]);
    }
  }

  const difValid = dif.map((v, i) => (v !== null ? v : 0));
  const deaValues = calcEMA(difValid.map(v => ({ close: v })), 9);

  for (let i = 0; i < dif.length; i++) {
    if (i < 25) {
      dea.push(null);
      macdHist.push(null);
    } else {
      const d = deaValues[i];
      dea.push(d);
      if (d !== null && dif[i] !== null) {
        macdHist.push((dif[i] - d) * 2);
      } else {
        macdHist.push(null);
      }
    }
  }

  return { dif, dea, macd: macdHist };
}

// RSI 计算
function calcRSI(data, period = 14) {
  const result = [];
  let avgGain = 0, avgLoss = 0;

  for (let i = 0; i < data.length; i++) {
    if (i < period) {
      result.push(null);
      if (i > 0) {
        const change = data[i].close - data[i - 1].close;
        if (change > 0) avgGain += change;
        else avgLoss += Math.abs(change);
      }
      if (i === period - 1) {
        avgGain /= period;
        avgLoss /= period;
        const rs = avgLoss === 0 ? 100 : avgGain / avgLoss;
        result[period - 1] = 100 - 100 / (1 + rs);
      }
    } else {
      const change = data[i].close - data[i - 1].close;
      const gain = change > 0 ? change : 0;
      const loss = change < 0 ? Math.abs(change) : 0;
      avgGain = (avgGain * (period - 1) + gain) / period;
      avgLoss = (avgLoss * (period - 1) + loss) / period;
      const rs = avgLoss === 0 ? 100 : avgGain / avgLoss;
      result.push(100 - 100 / (1 + rs));
    }
  }
  return result;
}

const COLORS = {
  bg: '#1a1a2e',
  grid: 'rgba(255,255,255,0.06)',
  text: 'rgba(255,255,255,0.6)',
  textBright: 'rgba(255,255,255,0.85)',
  up: '#ef5350',
  down: '#26a69a',
  upBg: 'rgba(239,83,80,0.9)',
  downBg: 'rgba(38,166,154,0.9)',
  ma5: '#ffeb3b',
  ma10: '#ff9800',
  ma20: '#e91e63',
  ma60: '#00bcd4',
  macdLine: '#2196f3',
  macdSignal: '#ff5722',
  volumeUp: 'rgba(239,83,80,0.4)',
  volumeDown: 'rgba(38,166,154,0.4)',
  rsi: '#ab47bc',
  crosshair: 'rgba(255,255,255,0.3)'
};

// 格式化成交量/成交额
function formatVolume(num) {
  if (num === null || num === undefined) return '-';
  const value = Number(num) / 10000;
  if (value >= 1e8) return (value / 1e8).toFixed(2) + '亿手';
  if (value >= 1e4) return (value / 1e4).toFixed(2) + '万手';
  return value.toFixed(2) + '万手';
}

function formatAmount(num) {
  if (num === null || num === undefined) return '-';
  const value = Number(num);
  if (value >= 1e8) return (value / 1e8).toFixed(2) + '亿';
  if (value >= 1e4) return (value / 1e4).toFixed(2) + '万';
  return value.toFixed(0);
}

export default function KLineChart({ history, loading, techAnalysis }) {
  const canvasRef = useRef(null);
  const containerRef = useRef(null);
  const [dimensions, setDimensions] = useState({ width: 0, height: 0 });
  const [tooltip, setTooltip] = useState(null);

  // 处理缩放和滚动
  const [visibleRange, setVisibleRange] = useState({ start: 0, end: 0 });
  const [data, setData] = useState([]);
  
  // 技术分析开关
  const [showLevels, setShowLevels] = useState(false);
  const [showFibonacci, setShowFibonacci] = useState(false);

  useEffect(() => {
    if (history) {
      const arr = Array.isArray(history) ? history : (history.data || history.records || []);
      setData(arr);
      setVisibleRange({ start: Math.max(0, arr.length - 80), end: arr.length });
    }
  }, [history]);

  // 响应容器大小变化
  useEffect(() => {
    const observer = new ResizeObserver(entries => {
      for (const entry of entries) {
        const { width, height } = entry.contentRect;
        setDimensions({ width, height });
      }
    });
    if (containerRef.current) {
      observer.observe(containerRef.current);
    }
    return () => observer.disconnect();
  }, []);

  const draw = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas || dimensions.width === 0 || data.length === 0) return;

    const dpr = window.devicePixelRatio || 1;
    canvas.width = dimensions.width * dpr;
    canvas.height = dimensions.height * dpr;
    canvas.style.width = dimensions.width + 'px';
    canvas.style.height = dimensions.height + 'px';

    const ctx = canvas.getContext('2d');
    ctx.scale(dpr, dpr);
    ctx.clearRect(0, 0, dimensions.width, dimensions.height);

    const W = dimensions.width;
    const H = dimensions.height;
    const padding = { top: 10, right: 60, bottom: 200, left: 10 };

    // 可见数据范围
    const start = visibleRange.start;
    const end = Math.min(visibleRange.end, data.length);
    const visibleData = data.slice(start, end);
    const count = visibleData.length;

    if (count === 0) return;

    const chartW = W - padding.left - padding.right;
    const kLineH = H - padding.top - padding.bottom;
    const volH = 60;
    const macdH = 60;
    const rsiH = 60;

    const candleW = Math.max(2, Math.min(15, chartW / count * 0.7));
    const candleGap = chartW / count;

    // 计算价格范围
    let priceMin = Infinity, priceMax = -Infinity;
    for (const d of visibleData) {
      const h = Number(d.high), l = Number(d.low);
      if (h > priceMax) priceMax = h;
      if (l < priceMin) priceMin = l;
    }
    const priceRange = priceMax - priceMin || 1;
    const priceY = (price) => padding.top + kLineH - ((price - priceMin) / priceRange) * kLineH;

    // 计算指标
    const ma5 = calcMA(data, 5);
    const ma10 = calcMA(data, 10);
    const ma20 = calcMA(data, 20);
    const ma60 = calcMA(data, 60);
    const macdData = calcMACD(data);
    const rsiData = calcRSI(data);

    // ===== 绘制网格 =====
    ctx.strokeStyle = COLORS.grid;
    ctx.lineWidth = 0.5;

    // K线图水平网格
    const gridLines = 5;
    for (let i = 0; i <= gridLines; i++) {
      const y = padding.top + (kLineH / gridLines) * i;
      ctx.beginPath();
      ctx.moveTo(padding.left, y);
      ctx.lineTo(W - padding.right, y);
      ctx.stroke();

      // 价格标签
      const price = priceMax - (priceRange / gridLines) * i;
      ctx.fillStyle = COLORS.text;
      ctx.font = '10px monospace';
      ctx.textAlign = 'right';
      ctx.fillText(price.toFixed(2), W - 2, y + 3);
    }

    // ===== 绘制K线 =====
    for (let i = 0; i < count; i++) {
      const d = visibleData[i];
      const x = padding.left + candleGap * i + candleGap / 2;
      const open = Number(d.open), close = Number(d.close);
      const high = Number(d.high), low = Number(d.low);
      const isUp = close >= open;

      ctx.strokeStyle = isUp ? COLORS.up : COLORS.down;
      ctx.fillStyle = isUp ? COLORS.upBg : COLORS.downBg;

      const yOpen = priceY(open);
      const yClose = priceY(close);
      const yHigh = priceY(high);
      const yLow = priceY(low);

      // 影线
      ctx.beginPath();
      ctx.moveTo(x, yHigh);
      ctx.lineTo(x, Math.min(yOpen, yClose));
      ctx.stroke();

      ctx.beginPath();
      ctx.moveTo(x, yLow);
      ctx.lineTo(x, Math.max(yOpen, yClose));
      ctx.stroke();

      // 实体
      const bodyH = Math.max(1, Math.abs(yClose - yOpen));
      ctx.fillRect(x - candleW / 2, Math.min(yOpen, yClose), candleW, bodyH);
      ctx.strokeRect(x - candleW / 2, Math.min(yOpen, yClose), candleW, bodyH);
    }

    // ===== 绘制MA均线 =====
    const drawMA = (maArr, color) => {
      ctx.strokeStyle = color;
      ctx.lineWidth = 1;
      ctx.beginPath();
      let started = false;
      for (let i = 0; i < count; i++) {
        const idx = start + i;
        const val = maArr[idx];
        if (val === null) continue;
        const x = padding.left + candleGap * i + candleGap / 2;
        const y = priceY(val);
        if (!started) {
          ctx.moveTo(x, y);
          started = true;
        } else {
          ctx.lineTo(x, y);
        }
      }
      ctx.stroke();
    };

    drawMA(ma5, COLORS.ma5);
    drawMA(ma10, COLORS.ma10);
    drawMA(ma20, COLORS.ma20);
    drawMA(ma60, COLORS.ma60);

    // MA 图例
    const maLegendY = padding.top + 2;
    ctx.font = 'bold 11px monospace';
    const legends = [
      { label: 'MA5', color: COLORS.ma5 },
      { label: 'MA10', color: COLORS.ma10 },
      { label: 'MA20', color: COLORS.ma20 },
      { label: 'MA60', color: COLORS.ma60 }
    ];
    let lx = padding.left + 5;
    for (const l of legends) {
      ctx.fillStyle = l.color;
      const text = l.label;
      const tw = ctx.measureText(text).width;
      ctx.fillText(text, lx, maLegendY + 12);
      lx += tw + 15;
    }

    // ===== 成交量区域 =====
    const volTop = padding.top + kLineH + 10;
    let volMax = 0;
    for (const d of visibleData) {
      const v = Number(d.volume);
      if (v > volMax) volMax = v;
    }
    volMax = volMax || 1;

    // 成交量网格
    ctx.strokeStyle = COLORS.grid;
    ctx.beginPath();
    ctx.moveTo(padding.left, volTop);
    ctx.lineTo(W - padding.right, volTop);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(padding.left, volTop + volH);
    ctx.lineTo(W - padding.right, volTop + volH);
    ctx.stroke();

    ctx.fillStyle = COLORS.text;
    ctx.font = '10px monospace';
    ctx.textAlign = 'left';
    ctx.fillText('VOL', padding.left + 2, volTop + 12);
    
    // 显示最大成交量
    ctx.textAlign = 'right';
    ctx.fillText(formatVolume(volMax), W - 2, volTop + 12);

    for (let i = 0; i < count; i++) {
      const d = visibleData[i];
      const x = padding.left + candleGap * i + candleGap / 2;
      const v = Number(d.volume);
      const barH = (v / volMax) * volH;
      const isUp = Number(d.close) >= Number(d.open);

      ctx.fillStyle = isUp ? COLORS.volumeUp : COLORS.volumeDown;
      ctx.fillRect(x - candleW / 2, volTop + volH - barH, candleW, barH);
    }

    // ===== MACD 区域 =====
    const macdTop = volTop + volH + 5;
    const macdVals = [];
    let macdAbsMax = 0;
    for (let i = start; i < end; i++) {
      const d = macdData.dif[i];
      const e = macdData.dea[i];
      const m = macdData.macd[i];
      macdVals.push({ dif: d, dea: e, macd: m });
      if (d !== null && Math.abs(d) > macdAbsMax) macdAbsMax = Math.abs(d);
      if (e !== null && Math.abs(e) > macdAbsMax) macdAbsMax = Math.abs(e);
      if (m !== null && Math.abs(m) > macdAbsMax) macdAbsMax = Math.abs(m);
    }
    macdAbsMax = Math.max(macdAbsMax, 0.01);

    // 0轴
    const macdZero = macdTop + macdH / 2;
    ctx.strokeStyle = 'rgba(255,255,255,0.2)';
    ctx.lineWidth = 0.5;
    ctx.beginPath();
    ctx.moveTo(padding.left, macdZero);
    ctx.lineTo(W - padding.right, macdZero);
    ctx.stroke();

    // 标签
    ctx.fillStyle = COLORS.text;
    ctx.font = '10px monospace';
    ctx.textAlign = 'left';
    ctx.fillText('MACD', padding.left + 2, macdTop + 12);

    // 柱子
    for (let i = 0; i < macdVals.length; i++) {
      const mv = macdVals[i];
      if (mv.macd === null) continue;
      const x = padding.left + candleGap * i + candleGap / 2;
      const h = (mv.macd / macdAbsMax) * (macdH / 2);
      ctx.fillStyle = mv.macd >= 0 ? COLORS.up : COLORS.down;
      ctx.fillRect(x - candleW / 4, macdZero - Math.max(0, h), candleW / 2, Math.abs(h));
      ctx.fillRect(x - candleW / 4, macdZero, candleW / 2, Math.abs(Math.min(0, h)));
    }

    // DIF 和 DEA 线
    const drawMACDLine = (arr, color) => {
      ctx.strokeStyle = color;
      ctx.lineWidth = 1;
      ctx.beginPath();
      let started = false;
      for (let i = 0; i < macdVals.length; i++) {
        const val = arr[i];
        if (val === null) continue;
        const x = padding.left + candleGap * i + candleGap / 2;
        const y = macdZero - (val / macdAbsMax) * (macdH / 2);
        if (!started) {
          ctx.moveTo(x, y);
          started = true;
        } else {
          ctx.lineTo(x, y);
        }
      }
      ctx.stroke();
    };
    drawMACDLine(macdVals.map(v => v.dif), COLORS.macdLine);
    drawMACDLine(macdVals.map(v => v.dea), COLORS.macdSignal);

    // ===== RSI 区域 =====
    const rsiTop = macdTop + macdH + 5;
    const rsiVals = [];
    for (let i = start; i < end; i++) {
      rsiVals.push(rsiData[i]);
    }

    // RSI 参考线
    const rsiY = (v) => rsiTop + rsiH - ((v / 100) * rsiH);
    ctx.strokeStyle = 'rgba(255,255,255,0.1)';
    ctx.lineWidth = 0.5;
    for (const level of [30, 50, 70]) {
      const y = rsiY(level);
      ctx.beginPath();
      ctx.moveTo(padding.left, y);
      ctx.lineTo(W - padding.right, y);
      ctx.stroke();

      ctx.fillStyle = COLORS.text;
      ctx.font = '9px monospace';
      ctx.textAlign = 'right';
      ctx.fillText(level.toString(), W - 2, y + 3);
    }

    ctx.fillStyle = COLORS.text;
    ctx.font = '10px monospace';
    ctx.textAlign = 'left';
    ctx.fillText('RSI(14)', padding.left + 2, rsiTop + 12);

    // RSI 线
    ctx.strokeStyle = COLORS.rsi;
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    let rsiStarted = false;
    for (let i = 0; i < rsiVals.length; i++) {
      const val = rsiVals[i];
      if (val === null) continue;
      const x = padding.left + candleGap * i + candleGap / 2;
      const y = rsiY(val);
      if (!rsiStarted) {
        ctx.moveTo(x, y);
        rsiStarted = true;
      } else {
        ctx.lineTo(x, y);
      }
    }
    ctx.stroke();

    // ===== 技术分析叠加 =====
    if (showLevels && techAnalysis?.support_levels) {
      drawLevelsOverlay(ctx, techAnalysis, priceMin, priceMax, priceRange, padding, chartW, kLineH);
    }
    if (showFibonacci && techAnalysis?.fibonacci?.levels) {
      drawFibonacciOverlay(ctx, techAnalysis.fibonacci.levels, priceMin, priceMax, priceRange, padding, chartW, kLineH);
    }

    // ===== 鼠标交互 =====
    const handleMouseMove = (e) => {
      const rect = canvas.getBoundingClientRect();
      const mx = e.clientX - rect.left;
      const my = e.clientY - rect.top;

      // 检查是否在K线区域
      if (my > padding.top && my < padding.top + kLineH) {
        const idx = Math.floor((mx - padding.left) / candleGap) + start;
        if (idx >= 0 && idx < data.length) {
          const d = data[idx];
          const cx = padding.left + candleGap * (idx - start) + candleGap / 2;
          setTooltip({
            x: cx,
            y: my,
            data: d,
            visible: true
          });
          return;
        }
      }
      setTooltip({ visible: false });
    };

    const handleMouseLeave = () => {
      setTooltip({ visible: false });
    };

    canvas.onmousemove = handleMouseMove;
    canvas.onmouseleave = handleMouseLeave;

    // 如果 tooltip 可见且数据匹配，重绘 tooltip
    if (tooltip?.visible && tooltip.data) {
      ctx.strokeStyle = COLORS.crosshair;
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 4]);
      ctx.beginPath();
      ctx.moveTo(tooltip.x, padding.top);
      ctx.lineTo(tooltip.x, padding.top + kLineH);
      ctx.stroke();
      ctx.setLineDash([]);

      // Tooltip
      const d = tooltip.data;
      const tipX = Math.min(W - 120, Math.max(10, tooltip.x + 10));
      const tipY = Math.min(padding.top + kLineH - 90, Math.max(padding.top, tooltip.y - 50));

      ctx.fillStyle = 'rgba(0,0,0,0.85)';
      ctx.fillRect(tipX, tipY, 110, 80);
      ctx.strokeStyle = 'rgba(255,255,255,0.3)';
      ctx.strokeRect(tipX, tipY, 110, 80);

      ctx.fillStyle = COLORS.textBright;
      ctx.font = '11px monospace';
      ctx.textAlign = 'left';
      const fields = [
        `日期: ${d.date || '-'}`,
        `开: ${Number(d.open).toFixed(2)}`,
        `高: ${Number(d.high).toFixed(2)}`,
        `低: ${Number(d.low).toFixed(2)}`,
        `收: ${Number(d.close).toFixed(2)}`,
        `量: ${formatVolume(d.volume)}`,
        `额: ${formatAmount(d.amount)}`
      ];
      fields.forEach((text, i) => {
        ctx.fillText(text, tipX + 8, tipY + 14 + i * 13);
      });
    }

  }, [data, dimensions, visibleRange, tooltip, showLevels, showFibonacci, techAnalysis]);

  useEffect(() => {
    let animationId;
    const render = () => {
      draw();
      animationId = requestAnimationFrame(render);
    };
    animationId = requestAnimationFrame(render);
    return () => cancelAnimationFrame(animationId);
  }, [draw]);

  // 滚轮缩放
  const handleWheel = useCallback((e) => {
    e.preventDefault();
    const range = visibleRange.end - visibleRange.start;
    const delta = e.deltaY > 0 ? Math.floor(range * 0.1) : -Math.floor(range * 0.1);
    const newStart = Math.max(0, visibleRange.start + delta);
    const newEnd = Math.min(data.length, visibleRange.end - delta);
    if (newEnd - newStart > 10 && newEnd - newStart <= data.length) {
      setVisibleRange({ start: newStart, end: newEnd });
    }
  }, [visibleRange, data]);

  if (loading) {
    return (
      <div className="chart-container">
        <div className="chart-loading">加载K线数据中...</div>
      </div>
    );
  }

  if (!data || data.length === 0) {
    return (
      <div className="chart-container">
        <div className="chart-empty">暂无K线数据</div>
      </div>
    );
  }

  return (
    <div className="chart-container">
      <div className="chart-toolbar">
        <span className="chart-title">📈 K线图</span>
        <div className="chart-controls">
          <button 
            className={showLevels ? 'active' : ''}
            onClick={() => setShowLevels(!showLevels)}
          >
            支撑压力
          </button>
          <button 
            className={showFibonacci ? 'active' : ''}
            onClick={() => setShowFibonacci(!showFibonacci)}
          >
            斐波那契
          </button>
          <button onClick={() => setVisibleRange({ start: Math.max(0, data.length - 60), end: data.length })}>
            60日
          </button>
          <button onClick={() => setVisibleRange({ start: Math.max(0, data.length - 120), end: data.length })}>
            120日
          </button>
          <button onClick={() => setVisibleRange({ start: 0, end: data.length })}>
            全部
          </button>
        </div>
      </div>
      <div className="chart-canvas-wrapper" ref={containerRef} onWheel={handleWheel}>
        <canvas ref={canvasRef} style={{ width: '100%', height: '100%' }} />
      </div>
    </div>
  );
}