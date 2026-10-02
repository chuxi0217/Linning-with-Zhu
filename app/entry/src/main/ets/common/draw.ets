// ── canvas 小件（9-30 第 3 批拆分·纯函数零依赖）─────────────────────────
// 从 pages/Index.ets 的 struct 方法原样外提：hexToRgba / drawStar5 / drawSpark4。
// 行为逐字未改（搬家而已）。

export function hexToRgba(hex: string, alpha: number): string {
  let h = hex;
  if (h.startsWith('#')) {
    h = h.substring(1);
  }
  if (h.length !== 6) {
    return `rgba(201,190,176,${alpha})`;
  }
  const r = parseInt(h.substring(0, 2), 16);
  const g = parseInt(h.substring(2, 4), 16);
  const b = parseInt(h.substring(4, 6), 16);
  return `rgba(${r},${g},${b},${alpha})`;
}

export function drawStar5(ctx: CanvasRenderingContext2D, x: number, y: number, r: number,
                  color: string, alpha: number): void {
  ctx.globalAlpha = alpha;
  ctx.fillStyle = color;
  ctx.beginPath();
  for (let k = 0; k < 10; k++) {
    const rad = k % 2 === 0 ? r : r * 0.45;
    const ang = -Math.PI / 2 + k * Math.PI / 5;
    const px = x + rad * Math.cos(ang);
    const py = y + rad * Math.sin(ang);
    if (k === 0) {
      ctx.moveTo(px, py);
    } else {
      ctx.lineTo(px, py);
    }
  }
  ctx.closePath();
  ctx.fill();
  ctx.globalAlpha = 1;
}

export function drawSpark4(ctx: CanvasRenderingContext2D, x: number, y: number, r: number,
                   color: string, alpha: number): void {
  ctx.globalAlpha = alpha;
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.moveTo(x, y - r);
  ctx.quadraticCurveTo(x, y, x + r, y);
  ctx.quadraticCurveTo(x, y, x, y + r);
  ctx.quadraticCurveTo(x, y, x - r, y);
  ctx.quadraticCurveTo(x, y, x, y - r);
  ctx.closePath();
  ctx.fill();
  ctx.globalAlpha = 1;
}
