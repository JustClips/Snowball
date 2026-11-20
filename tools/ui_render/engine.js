// In-page layout engine: turns a dumped Roblox GUI tree into absolutely positioned DOM.
// Follows the Roblox rules the game uses: UDim2 size/position, AnchorPoint, UIScale
// (scales around the anchor), UIPadding, UIListLayout, UIGridLayout, AutomaticSize,
// UIAspectRatioConstraint, UISizeConstraint, TextScaled (+UITextSizeConstraint), UIStroke
// (outside the border; text outline on text), UICorner, UIGradient, ScaleType
// (Stretch/Fit/Crop/Tile/Slice), ImageColor3 tint, ScrollingFrame canvas, ZIndex (sibling).
/* global IMAGES, FONTMAP */
(function () {
  const MOD = new Set(["UIStroke", "UICorner", "UIGradient", "UIScale", "UIPadding", "UIListLayout", "UIGridLayout",
    "UIAspectRatioConstraint", "UISizeConstraint", "UITextSizeConstraint", "UIFlexItem"]);
  const TEXT = new Set(["TextLabel", "TextButton", "TextBox"]);
  const IMAGE = new Set(["ImageLabel", "ImageButton"]);

  const rgb = (c, a = 1) => `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${a})`;
  const ud = (u, size) => (u ? u[0] * size + u[1] : 0);

  function fontCss(p) {
    const f = p.FontFace || { family: "SourceSansPro", weight: "Regular" };
    let fam = f.family || "";
    const m = fam.match(/families\/([A-Za-z0-9]+)\.json/);
    const key = m ? m[1] : fam;
    const mapped = FONTMAP[key] || FONTMAP.default;
    const weights = { Thin: 100, ExtraLight: 200, Light: 300, Regular: 400, Medium: 500, SemiBold: 600, Bold: 700, ExtraBold: 800, Heavy: 900 };
    let w = weights[f.weight] || 400;
    if (mapped.forceWeight) w = mapped.forceWeight;
    return { family: mapped.family, weight: w };
  }

  function mods(node) {
    const out = { strokes: [] };
    for (const k of node.k) {
      if (!MOD.has(k.c)) continue;
      if (k.c === "UIStroke") { if (k.p.Enabled !== false) out.strokes.push(k.p); }
      else out[k.c] = k.p;
    }
    return out;
  }

  // Roblox draws U+E002 as the Robux mark; draw a stand-in shape.
  const ROBUX = '<span style="display:inline-block;width:.72em;height:.72em;border:.15em solid currentColor;border-radius:.2em;box-sizing:border-box;vertical-align:-.04em;margin-right:.05em;transform:rotate(0deg)"></span>';
  function richToHtml(text, rich) {
    return richToHtml0(text, rich).replace(/\uE002/g, ROBUX);
  }
  function richToHtml0(text, rich) {
    const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    if (!rich) return esc(text).replace(/\n/g, "<br>");
    let s = text;
    // keep a small whitelist of tags
    s = s.replace(/<br\s*\/?>/gi, "\n");
    const parts = s.split(/(<[^>]+>)/);
    let html = "";
    const stack = [];
    for (const part of parts) {
      if (!part) continue;
      if (part[0] !== "<") { html += esc(part).replace(/\n/g, "<br>"); continue; }
      const tag = part.toLowerCase();
      if (tag.startsWith("</")) { html += stack.pop() || ""; continue; }
      if (tag.startsWith("<font")) {
        let style = "";
        const col = part.match(/color\s*=\s*["']([^"']+)["']/i);
        if (col) {
          let c = col[1];
          const rm = c.match(/rgb\((\d+),\s*(\d+),\s*(\d+)\)/i);
          if (rm) c = `rgb(${rm[1]},${rm[2]},${rm[3]})`;
          style += `color:${c};`;
        }
        const sz = part.match(/size\s*=\s*["'](\d+)["']/i);
        if (sz) style += `font-size:${sz[1]}px;`;
        const wt = part.match(/weight\s*=\s*["'](\w+)["']/i);
        if (wt) style += `font-weight:${({ bold: 700, heavy: 900, extrabold: 800 })[wt[1].toLowerCase()] || 400};`;
        html += `<span style="${style}">`; stack.push("</span>");
      } else if (tag === "<b>") { html += "<b>"; stack.push("</b>"); }
      else if (tag === "<i>") { html += "<i>"; stack.push("</i>"); }
      else if (tag === "<u>") { html += "<u>"; stack.push("</u>"); }
      else if (tag.startsWith("<stroke")) { html += "<span>"; stack.push("</span>"); }
      else { html += ""; stack.push(""); }
    }
    while (stack.length) html += stack.pop();
    return html;
  }

  // measure text in a hidden box
  const meas = document.createElement("div");
  meas.style.cssText = "position:absolute;left:-99999px;top:0;visibility:hidden;white-space:pre;line-height:1.0";
  document.body.appendChild(meas);
  function measure(html, font, size, wrapWidth) {
    meas.style.fontFamily = font.family; meas.style.fontWeight = font.weight; meas.style.fontSize = size + "px";
    if (wrapWidth) { meas.style.whiteSpace = "pre-wrap"; meas.style.width = wrapWidth + "px"; meas.style.wordBreak = "normal"; }
    else { meas.style.whiteSpace = "pre"; meas.style.width = "auto"; }
    meas.innerHTML = html;
    return { w: meas.scrollWidth, h: meas.scrollHeight };
  }

  function sizeOf(p, pw, ph) {
    let w = ud(p.Size && [p.Size[0], p.Size[1]], pw), h = ud(p.Size && [p.Size[2], p.Size[3]], ph);
    if (!p.Size) { w = 100; h = 100; }
    if (p.SizeConstraint === "RelativeXX") h = p.Size[2] * pw + p.Size[3];
    if (p.SizeConstraint === "RelativeYY") w = p.Size[0] * ph + p.Size[1];
    return [w, h];
  }

  function applyConstraints(w, h, m) {
    const a = m.UIAspectRatioConstraint;
    if (a) {
      const r = a.AspectRatio || 1;
      if (a.AspectType === "ScaleWithParentSize") {
        if (a.DominantAxis === "Height") w = h * r; else h = w / r;
      } else {
        if (w / h > r) w = h * r; else h = w / r;
      }
    }
    const sc = m.UISizeConstraint;
    if (sc) {
      w = Math.min(Math.max(w, sc.MinSize[0]), sc.MaxSize[0]);
      h = Math.min(Math.max(h, sc.MinSize[1]), sc.MaxSize[1]);
    }
    return [w, h];
  }

  function guiKids(node) {
    return node.k.filter((k) => !MOD.has(k.c) && k.c !== "Folder" && k.p.Visible !== false);
  }

  // Lays out node inside a parent content box of pw x ph. Returns {el, w, h}.
  // forced: {w,h} from a grid; place: {x,y} top-left from a list/grid (ignores Position).
  function build(node, pw, ph, forced, place) {
    const p = node.p, m = mods(node);
    let [w, h] = forced ? [forced.w, forced.h] : sizeOf(p, pw, ph);
    if (!forced) [w, h] = applyConstraints(w, h, m);
    const el = document.createElement("div");
    el.className = "g " + node.c;
    el.dataset.name = node.n;

    const pad = m.UIPadding || {};
    const auto = p.AutomaticSize || "None";
    const isText = TEXT.has(node.c);
    const font = fontCss(p);
    let textHtml = null;
    if (isText) {
      let t = p.Text || "";
      if (node.c === "TextBox" && !t) t = p.PlaceholderText || "";
      textHtml = richToHtml(t, p.RichText);
    }
    // automatic size from text
    if (isText && auto !== "None" && !p.TextScaled) {
      const padX = ud(pad.PaddingLeft, w) + ud(pad.PaddingRight, w);
      const padY = ud(pad.PaddingTop, h) + ud(pad.PaddingBottom, h);
      const mm = measure(textHtml, font, p.TextSize || 14, (auto === "Y" && p.TextWrapped) ? w - padX : 0);
      if (auto === "X" || auto === "XY") w = Math.max(w, mm.w + padX);
      if (auto === "Y" || auto === "XY") h = Math.max(h, mm.h * (p.LineHeight || 1) + padY);
    }

    function layoutChildren(W, H) {
      el.querySelectorAll(":scope > .kids").forEach((x) => x.remove());
      const box = document.createElement("div");
      box.className = "kids";
      const pl = ud(pad.PaddingLeft, W), pr = ud(pad.PaddingRight, W), pt = ud(pad.PaddingTop, H), pb = ud(pad.PaddingBottom, H);
      let cw = W - pl - pr, ch = H - pt - pb;
      let canvasW = cw, canvasH = ch;
      const isScroll = node.c === "ScrollingFrame";
      if (isScroll && p.CanvasSize) {
        canvasW = Math.max(cw, ud([p.CanvasSize[0], p.CanvasSize[1]], cw));
        canvasH = Math.max(0, ud([p.CanvasSize[2], p.CanvasSize[3]], ch));
        if (p.AutomaticCanvasSize === "Y" || p.AutomaticCanvasSize === "XY") canvasH = 0;
        if (p.AutomaticCanvasSize === "X" || p.AutomaticCanvasSize === "XY") canvasW = 0;
        if (!canvasH) canvasH = ch;
      }
      const kids = guiKids(node);
      const list = m.UIListLayout, grid = m.UIGridLayout;
      let bbW = 0, bbH = 0;
      const sorted = kids.slice().map((k, i) => ({ k, i })).sort((a, b) => {
        if ((list || grid) && ((list || grid).SortOrder !== "Name")) {
          const d = (a.k.p.LayoutOrder || 0) - (b.k.p.LayoutOrder || 0);
          if (d) return d;
        }
        if ((list || grid) && (list || grid).SortOrder === "Name") return a.k.n < b.k.n ? -1 : a.k.n > b.k.n ? 1 : 0;
        return a.i - b.i;
      }).map((x) => x.k);
      const refW = isScroll ? canvasW : cw, refH = isScroll ? canvasH : ch;
      if (grid) {
        let cellW = ud([grid.CellSize[0], grid.CellSize[1]], refW), cellH = ud([grid.CellSize[2], grid.CellSize[3]], refH);
        const ar = m.UIAspectRatioConstraint;
        if (ar) { if (cellW / cellH > ar.AspectRatio) cellW = cellH * ar.AspectRatio; else cellH = cellW / ar.AspectRatio; }
        const padX = ud([grid.CellPadding[0], grid.CellPadding[1]], refW), padY = ud([grid.CellPadding[2], grid.CellPadding[3]], refH);
        const horiz = grid.FillDirection !== "Vertical";
        let per = horiz ? Math.max(1, Math.floor((refW + padX + 0.01) / (cellW + padX))) : Math.max(1, Math.floor((refH + padY + 0.01) / (cellH + padY)));
        if (grid.FillDirectionMaxCells > 0) per = Math.min(per, grid.FillDirectionMaxCells);
        const n = sorted.length;
        const lines = Math.ceil(n / per);
        const cols = horiz ? Math.min(per, n) : lines, rows = horiz ? lines : Math.min(per, n);
        const blockW = cols * cellW + Math.max(0, cols - 1) * padX, blockH = rows * cellH + Math.max(0, rows - 1) * padY;
        const ox = grid.HorizontalAlignment === "Center" ? (refW - blockW) / 2 : grid.HorizontalAlignment === "Right" ? refW - blockW : 0;
        const oy = grid.VerticalAlignment === "Center" ? (refH - blockH) / 2 : grid.VerticalAlignment === "Bottom" ? refH - blockH : 0;
        sorted.forEach((k, i) => {
          const a = horiz ? i % per : Math.floor(i / per), b = horiz ? Math.floor(i / per) : i % per;
          const r = build(k, refW, refH, { w: cellW, h: cellH }, { x: ox + a * (cellW + padX), y: oy + b * (cellH + padY) });
          box.appendChild(r.el);
        });
        bbW = Math.max(bbW, blockW); bbH = Math.max(bbH, blockH);
      } else if (list) {
        const horiz = list.FillDirection === "Horizontal";
        const gap = ud(list.Padding, horiz ? refW : refH);
        const built = sorted.map((k) => build(k, refW, refH, null, { x: 0, y: 0 }));
        const total = built.reduce((s, r) => s + (horiz ? r.w : r.h), 0) + gap * Math.max(0, built.length - 1);
        const cross = built.reduce((s, r) => Math.max(s, horiz ? r.h : r.w), 0);
        let cur = 0;
        const along = horiz ? list.HorizontalAlignment : list.VerticalAlignment;
        const avail = horiz ? refW : refH;
        if (along === "Center") cur = (avail - total) / 2; else if (along === "Right" || along === "Bottom") cur = avail - total;
        for (const r of built) {
          let x, y;
          if (horiz) {
            x = cur;
            y = list.VerticalAlignment === "Center" ? (refH - r.h) / 2 : list.VerticalAlignment === "Bottom" ? refH - r.h : 0;
            cur += r.w + gap;
          } else {
            y = cur;
            x = list.HorizontalAlignment === "Center" ? (refW - r.w) / 2 : list.HorizontalAlignment === "Right" ? refW - r.w : 0;
            cur += r.h + gap;
          }
          r.el.style.left = x + "px"; r.el.style.top = y + "px";
          box.appendChild(r.el);
        }
        if (horiz) { bbW = Math.max(bbW, total); bbH = Math.max(bbH, cross); } else { bbH = Math.max(bbH, total); bbW = Math.max(bbW, cross); }
      } else {
        for (const k of sorted) {
          const r = build(k, refW, refH, null, null);
          box.appendChild(r.el);
          bbW = Math.max(bbW, r.right); bbH = Math.max(bbH, r.bottom);
        }
      }
      box.style.cssText = `position:absolute;left:${pl}px;top:${pt}px;width:${isScroll ? Math.max(cw, bbW) : cw}px;height:${isScroll ? Math.max(canvasH, bbH) : ch}px;`;
      if (isScroll && p.CanvasPosition) box.style.transform = `translate(${-p.CanvasPosition[0]}px,${-p.CanvasPosition[1]}px)`;
      return { box, needW: bbW + pl + pr, needH: bbH + pt + pb };
    }

    let res = layoutChildren(w, h);
    if (!isText && auto !== "None" && guiKids(node).length) {
      let nw = w, nh = h;
      if (auto === "X" || auto === "XY") nw = Math.max(w, res.needW);
      if (auto === "Y" || auto === "XY") nh = Math.max(h, res.needH);
      if (nw !== w || nh !== h) { w = nw; h = nh; res = layoutChildren(w, h); }
    }

    // position
    let x, y;
    const ap = p.AnchorPoint || [0, 0];
    if (place) { x = place.x; y = place.y; }
    else {
      const pos = p.Position || [0, 0, 0, 0];
      x = pos[0] * pw + pos[1] - ap[0] * w;
      y = pos[2] * ph + pos[3] - ap[1] * h;
    }
    el.style.cssText = `position:absolute;left:${x}px;top:${y}px;width:${w}px;height:${h}px;z-index:${p.ZIndex ?? 1};`;
    const transforms = [];
    if (p.Rotation) transforms.push(`rotate(${p.Rotation}deg)`);
    if (m.UIScale && m.UIScale.Scale !== 1 && m.UIScale.Scale !== undefined) transforms.push(`scale(${m.UIScale.Scale})`);
    if (transforms.length) {
      el.style.transform = transforms.join(" ");
      el.style.transformOrigin = place ? "50% 50%" : `${ap[0] * 100}% ${ap[1] * 100}%`;
    }
    if (node.c === "CanvasGroup" && p.GroupTransparency) el.style.opacity = 1 - p.GroupTransparency;

    // corner
    let radius = 0;
    if (m.UICorner) {
      const cr = m.UICorner.CornerRadius || [0, 8];
      radius = Math.min(cr[0] * Math.min(w, h) + cr[1], Math.min(w, h) / 2);
      el.style.borderRadius = radius + "px";
    }
    const grad = m.UIGradient && m.UIGradient.Enabled !== false ? m.UIGradient : null;
    function gradientCss(base, alpha) {
      const cs = grad.Color || [[0, 1, 1, 1], [1, 1, 1, 1]];
      const ts = grad.Transparency || [[0, 0], [1, 0]];
      const tAt = (t) => { for (let i = 0; i < ts.length - 1; i++) { if (t >= ts[i][0] && t <= ts[i + 1][0]) { const f = (t - ts[i][0]) / ((ts[i + 1][0] - ts[i][0]) || 1); return ts[i][1] + (ts[i + 1][1] - ts[i][1]) * f; } } return ts[ts.length - 1][1]; };
      const stops = new Set(cs.map((k) => k[0]).concat(ts.map((k) => k[0])));
      const cAt = (t) => { for (let i = 0; i < cs.length - 1; i++) { if (t >= cs[i][0] && t <= cs[i + 1][0]) { const f = (t - cs[i][0]) / ((cs[i + 1][0] - cs[i][0]) || 1); return [1, 2, 3].map((j) => cs[i][j] + (cs[i + 1][j] - cs[i][j]) * f); } } const l = cs[cs.length - 1]; return [l[1], l[2], l[3]]; };
      const off = grad.Offset || [0, 0];
      const list = [...stops].sort((a, b) => a - b).map((t) => {
        const c = cAt(t); const col = [base[0] * c[0], base[1] * c[1], base[2] * c[2]];
        const pct = (t + (Math.abs(grad.Rotation % 180) === 90 ? off[1] : off[0])) * 100;
        return `${rgb(col, alpha * (1 - tAt(t)))} ${pct}%`;
      });
      return `linear-gradient(${(grad.Rotation || 0) + 90}deg, ${list.join(", ")})`;
    }

    const bgT = p.BackgroundTransparency ?? 0;
    if (bgT < 1 && p.BackgroundColor3) {
      if (grad) el.style.background = gradientCss(p.BackgroundColor3, 1 - bgT);
      else el.style.background = rgb(p.BackgroundColor3, 1 - bgT);
    }
    if ((p.BorderSizePixel || 0) > 0 && bgT < 1 && node.c !== "ScreenGui") {
      // Legacy border (inside). Rarely used; the kit sets 0.
      el.style.boxShadow = `inset 0 0 0 ${p.BorderSizePixel}px ${rgb(p.BorderColor3 || [0.1, 0.16, 0.2], 1 - bgT)}`;
    }
    const shadows = [];
    let textStroke = null;
    for (const s of m.strokes) {
      const mode = s.ApplyStrokeMode || "Contextual";
      const a = 1 - (s.Transparency || 0);
      if (isText && mode === "Contextual") textStroke = { t: s.Thickness ?? 1, c: rgb(s.Color || [0, 0, 0], a * (1 - (p.TextTransparency || 0))) };
      else shadows.push(`0 0 0 ${s.Thickness ?? 1}px ${rgb(s.Color || [0, 0, 0], a)}`);
    }
    if (shadows.length) el.style.boxShadow = shadows.join(",");

    // image
    if (IMAGE.has(node.c) || node.c === "ViewportFrame") {
      if (node.c === "ViewportFrame") {
        const v = document.createElement("div");
        v.style.cssText = "position:absolute;inset:0;border:1px dashed rgba(255,255,255,.5);color:rgba(255,255,255,.7);font:10px sans-serif;display:flex;align-items:center;justify-content:center";
        v.textContent = "3D";
        el.appendChild(v);
      } else if (p.Image) {
        const info = IMAGES[p.Image];
        const layer = document.createElement("div");
        layer.style.cssText = `position:absolute;inset:0;border-radius:${radius}px;overflow:hidden;isolation:isolate;opacity:${1 - (p.ImageTransparency || 0)}`;
        if (!info) {
          layer.style.outline = "1px dashed #f0f"; layer.title = p.Image;
        } else {
          const st = p.ScaleType || "Stretch";
          let bg = `url("${info.src}") no-repeat`;
          let size = "100% 100%", posCss = "center";
          if (st === "Fit") size = "contain";
          else if (st === "Crop") size = "cover";
          else if (st === "Tile") { const ts = p.TileSize || [1, 0, 1, 0]; size = `${ud([ts[0], ts[1]], w)}px ${ud([ts[2], ts[3]], h)}px`; bg = `url("${info.src}") repeat`; posCss = "0 0"; }
          const rs = p.ImageRectSize, ro = p.ImageRectOffset;
          const img = document.createElement("div");
          if (rs && (rs[0] > 0 || rs[1] > 0) && st !== "Slice") {
            const sx = w / rs[0], sy = h / rs[1];
            let s = Math.min(sx, sy);
            let fw = rs[0] * s, fh = rs[1] * s;
            if (st === "Stretch") { fw = w; fh = h; }
            img.style.cssText = `position:absolute;left:${(w - fw) / 2}px;top:${(h - fh) / 2}px;width:${fw}px;height:${fh}px;background:url("${info.src}") no-repeat;background-size:${info.w * fw / rs[0]}px ${info.h * fh / rs[1]}px;background-position:${-ro[0] * fw / rs[0]}px ${-ro[1] * fh / rs[1]}px`;
          } else if (st === "Slice" && p.SliceCenter) {
            const sc = p.SliceCenter; const k = p.SliceScale || 1;
            const L = sc[0], T = sc[1], Rr = info.w - sc[2], B = info.h - sc[3];
            img.style.cssText = `position:absolute;inset:0;border-style:solid;border-width:${T * k}px ${Rr * k}px ${B * k}px ${L * k}px;border-image:url("${info.src}") ${T} ${Rr} ${B} ${L} fill stretch;box-sizing:border-box`;
          } else {
            img.style.cssText = `position:absolute;inset:0;background:${bg};background-size:${size};background-position:${posCss}`;
          }
          layer.appendChild(img);
          const tint = p.ImageColor3;
          if (tint && (tint[0] < 0.999 || tint[1] < 0.999 || tint[2] < 0.999)) {
            const t = img.cloneNode();
            t.style.background = rgb(tint);
            t.style.borderImage = "none"; t.style.borderColor = "transparent";
            const maskSrc = img.style.backgroundImage || `url("${info.src}")`;
            t.style.webkitMaskImage = maskSrc; t.style.maskImage = maskSrc;
            t.style.webkitMaskSize = img.style.backgroundSize || "100% 100%"; t.style.maskSize = t.style.webkitMaskSize;
            t.style.webkitMaskPosition = img.style.backgroundPosition || "center"; t.style.maskPosition = t.style.webkitMaskPosition;
            t.style.webkitMaskRepeat = img.style.backgroundRepeat || "no-repeat"; t.style.maskRepeat = t.style.webkitMaskRepeat;
            if (st === "Slice") { t.style.cssText += `;border-image:none;border-width:0;-webkit-mask-image:url("${info.src}");-webkit-mask-size:100% 100%`; }
            t.style.mixBlendMode = "multiply";
            layer.appendChild(t);
          }
          if (grad) {
            const g = document.createElement("div");
            g.style.cssText = `position:absolute;inset:0;background:${gradientCss([1, 1, 1], 1)};mix-blend-mode:multiply;-webkit-mask-image:url("${info.src}");-webkit-mask-size:${size === "100% 100%" ? "100% 100%" : size};-webkit-mask-repeat:no-repeat;-webkit-mask-position:center`;
            layer.appendChild(g);
          }
        }
        el.appendChild(layer);
      }
    }

    // text
    if (isText && textHtml && (p.TextTransparency ?? 0) < 1) {
      const pl = ud(pad.PaddingLeft, w), pr = ud(pad.PaddingRight, w), pt = ud(pad.PaddingTop, h), pb = ud(pad.PaddingBottom, h);
      const bw = w - pl - pr, bh = h - pt - pb;
      let size = p.TextSize || 14;
      const tsc = m.UITextSizeConstraint;
      const wrap = !!p.TextWrapped;
      if (p.TextScaled) {
        const max = tsc ? tsc.MaxTextSize : 100, min = tsc ? tsc.MinTextSize : 1;
        let lo = 1, hi = Math.min(100, max);
        while (hi - lo > 0.5) {
          const mid = (lo + hi) / 2;
          const mm = measure(textHtml, font, mid, wrap ? bw : 0);
          if (mm.w <= bw + 0.5 && mm.h * (p.LineHeight || 1) <= bh + 0.5) lo = mid; else hi = mid;
        }
        size = Math.max(min, Math.floor(lo));
      } else if (tsc) size = Math.min(Math.max(size, tsc.MinTextSize), tsc.MaxTextSize);
      const t = document.createElement("div");
      const xa = p.TextXAlignment || "Center", ya = p.TextYAlignment || "Center";
      const color = rgb(p.TextColor3 || [0.1, 0.16, 0.2], 1 - (p.TextTransparency || 0));
      t.style.cssText = `position:absolute;left:${pl}px;top:${pt}px;width:${bw}px;height:${bh}px;display:flex;` +
        `justify-content:${xa === "Left" ? "flex-start" : xa === "Right" ? "flex-end" : "center"};` +
        `align-items:${ya === "Top" ? "flex-start" : ya === "Bottom" ? "flex-end" : "center"};` +
        `text-align:${xa === "Left" ? "left" : xa === "Right" ? "right" : "center"};` +
        `font-family:${font.family};font-weight:${font.weight};font-size:${size}px;line-height:${p.LineHeight || 1};color:${color};` +
        `white-space:${wrap ? "pre-wrap" : "pre"};overflow:visible;z-index:0`;
      const inner = document.createElement("span");
      inner.innerHTML = textHtml;
      if (grad && bgT >= 1) {
        inner.style.background = gradientCss(p.TextColor3 || [1, 1, 1], 1);
        inner.style.webkitBackgroundClip = "text"; inner.style.color = "transparent";
      }
      if (textStroke) {
        inner.style.webkitTextStroke = `${textStroke.t * 2}px ${textStroke.c}`;
        inner.style.paintOrder = "stroke fill";
      } else if ((p.TextStrokeTransparency ?? 1) < 1) {
        inner.style.webkitTextStroke = `2px ${rgb(p.TextStrokeColor3 || [0, 0, 0], 1 - p.TextStrokeTransparency)}`;
        inner.style.paintOrder = "stroke fill";
      }
      t.appendChild(inner);
      el.appendChild(t);
    }

    if (p.ClipsDescendants || node.c === "ScrollingFrame") {
      const clip = document.createElement("div");
      clip.style.cssText = `position:absolute;inset:0;overflow:hidden;border-radius:${radius}px`;
      clip.appendChild(res.box);
      el.appendChild(clip);
      if (node.c === "ScrollingFrame" && (p.ScrollBarThickness ?? 12) > 0) {
        const sb = document.createElement("div");
        sb.style.cssText = `position:absolute;right:0;top:0;width:${p.ScrollBarThickness ?? 12}px;height:40%;background:${rgb(p.ScrollBarImageColor3 || [0, 0, 0], 0.6)};border-radius:4px`;
        el.appendChild(sb);
      }
    } else el.appendChild(res.box);

    // bounds for AutomaticSize of the parent (offset-only approximation)
    return { el, w, h, right: x + w, bottom: y + h };
  }

  window.renderScreens = function (screens, device) {
    const stage = document.getElementById("stage");
    stage.style.width = device.w + "px"; stage.style.height = device.h + "px";
    const sorted = screens.map((s, i) => ({ s, i })).filter((x) => x.s.p.Enabled !== false || device.showDisabled)
      .sort((a, b) => ((a.s.p.DisplayOrder || 0) - (b.s.p.DisplayOrder || 0)) || (a.i - b.i));
    for (const { s } of sorted) {
      const ins = s.p.ScreenInsets || "CoreUISafeInsets";
      let L = 0, T = 0, Rr = 0, B = 0;
      if (ins === "CoreUISafeInsets") { [L, T, Rr, B] = device.core; }
      else if (ins === "DeviceSafeInsets") { [L, T, Rr, B] = device.safe; }
      if (s.p.IgnoreGuiInset === false && ins === "None") T = device.core[1];
      const layer = document.createElement("div");
      layer.className = "screen"; layer.dataset.name = s.n;
      const W = device.w - L - Rr, H = device.h - T - B;
      layer.style.cssText = `position:absolute;left:${L}px;top:${T}px;width:${W}px;height:${H}px;`;
      const fake = { c: "Frame", n: s.n, p: { Size: [0, W, 0, H], BackgroundTransparency: 1 }, k: s.k };
      const r = build(fake, W, H, null, null);
      layer.appendChild(r.el);
      stage.appendChild(layer);
    }
  };
})();
