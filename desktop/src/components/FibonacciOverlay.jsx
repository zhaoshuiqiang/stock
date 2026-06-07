import React from 'react';

const FIB_COLORS = {
  '23.6%': '#4fc3f7',
  '38.2%': '#2196f3',
  '50.0%': '#2196f3',
  '61.8%': '#ffd740',
  '78.6%': '#2196f3',
};

export default function FibonacciOverlay({ fibLevels, bounds }) {
  return null;
}

export function drawFibonacciOverlay(ctx, fibLevels, priceMin, priceMax, priceRange, padding, chartWidth, chartHeight) {
  if (!fibLevels || Object.keys(fibLevels).length === 0) return;

  const priceY = (price) => padding.top + chartHeight - ((price - priceMin) / priceRange) * chartHeight;

  Object.entries(fibLevels).forEach(([ratio, price]) => {
    const y = priceY(price);
    const color = FIB_COLORS[ratio] || '#2196f3';
    const isGolden = ratio === '61.8%';
    
    ctx.strokeStyle = color;
    ctx.lineWidth = isGolden ? 2 : 1;
    ctx.setLineDash([4, 4]);
    ctx.beginPath();
    ctx.moveTo(padding.left, y);
    ctx.lineTo(padding.left + chartWidth, y);
    ctx.stroke();
    
    ctx.fillStyle = color;
    ctx.font = isGolden ? 'bold 9px monospace' : '9px monospace';
    ctx.textAlign = 'left';
    ctx.fillText(`${ratio} ${Number(price).toFixed(2)}`, padding.left + 2, y - 2);
  });

  ctx.setLineDash([]);
}