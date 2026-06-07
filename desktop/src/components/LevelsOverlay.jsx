const COLORS = {
  resistance: '#ef5350',
  support: '#26a69a',
};

export default function LevelsOverlay({ levels, currentPrice, bounds }) {
  return null;
}

export function drawLevelsOverlay(ctx, levels, priceMin, priceMax, priceRange, padding, chartWidth, chartHeight) {
  const { support = [], resistance = [] } = levels || {};
  
  const priceY = (price) => padding.top + chartHeight - ((price - priceMin) / priceRange) * chartHeight;

  support.forEach((price, idx) => {
    const y = priceY(price);
    ctx.strokeStyle = COLORS.support;
    ctx.lineWidth = 1;
    ctx.setLineDash([5, 5]);
    ctx.beginPath();
    ctx.moveTo(padding.left, y);
    ctx.lineTo(padding.left + chartWidth, y);
    ctx.stroke();
    
    ctx.fillStyle = COLORS.support;
    ctx.font = '9px monospace';
    ctx.textAlign = 'left';
    ctx.fillText(`支撑: ${price.toFixed(2)}`, padding.left + 2, y - 2);
  });

  ctx.setLineDash([]);
  
  resistance.forEach((price, idx) => {
    const y = priceY(price);
    ctx.strokeStyle = COLORS.resistance;
    ctx.lineWidth = 1;
    ctx.setLineDash([5, 5]);
    ctx.beginPath();
    ctx.moveTo(padding.left, y);
    ctx.lineTo(padding.left + chartWidth, y);
    ctx.stroke();
    
    ctx.fillStyle = COLORS.resistance;
    ctx.font = '9px monospace';
    ctx.textAlign = 'left';
    ctx.fillText(`压力: ${price.toFixed(2)}`, padding.left + 2, y - 2);
  });

  ctx.setLineDash([]);
}