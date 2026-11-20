"""Draws the HUD in every mode on a phone (844 x 390) and a PC (1280 x 720) screen from the
same numbers the game uses (src/shared/Config/HudLayout.luau + the Ui kit sizes), so the
layout can be checked for overlaps before anything is pushed. Also flags overlapping
clusters automatically.

  python tools/hud_preview.py [out_dir]      (needs Pillow; icons from the project files)

The art is approximate (real icons, the Fredoka One font, rounded gradient shapes); the
positions and sizes are exact copies of the Luau layout maths:
  cluster top-left = inset + (scale.X * W + offset.X, scale.Y * H + offset.Y) - anchor * size * s
  s = clamp(min(W / 1280, H / 720) * 1.05, 0.55, 1.25), at least 0.62 on phones (Ui.luau)
"""
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
ICONS = ["/mnt/project-files/game-ideas/roll-the-snowball/icons", os.path.join(ROOT, "art", "ui")]
FONT = os.environ.get("HUD_FONT", "/tmp/claude-0/fonts/Fredoka.ttf")
SS = 2  # supersample

DEVICES = {
    # name: (W, H, inset left, top, right, bottom). Insets = Roblox top bar + phone notch.
    "PC": (1280, 720, 0, 58, 0, 0),
    "Phone": (844, 390, 47, 40, 47, 21),
}


def parse_layout():
    src = open(os.path.join(ROOT, "src", "shared", "Config", "HudLayout.luau")).read()
    out = {}
    for m in re.finditer(r"(\w+) = (\d+),", src):
        out[m.group(1)] = float(m.group(2))
    for m in re.finditer(r"(\w+) = Vector2\.new\(([-\d.]+), ([-\d.]+)\),", src):
        out[m.group(1)] = (float(m.group(2)), float(m.group(3)))
    for m in re.finditer(
        r"(\w+) = \{ Anchor = Vector2\.new\(([-\d.]+), ([-\d.]+)\), Pos = UDim2\.new\(([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+)\), "
        r"Size = Vector2\.new\(([-\d.]+), ([-\d.]+)\) \}", src):
        g = [float(x) for x in m.groups()[1:]]
        out[m.group(1)] = {"Anchor": (g[0], g[1]), "Pos": (g[2], g[3], g[4], g[5]), "Size": (g[6], g[7])}
    return out


L = parse_layout()


def ui_scale(w, h):
    s = max(0.55, min(1.25, min(w / 1280, h / 720) * 1.05))
    if min(w, h) < 500:
        s = max(s, 0.62)
    return s


_icon_cache = {}


def icon(name):
    if name not in _icon_cache:
        for d in ICONS:
            p = os.path.join(d, name + ".png")
            if os.path.exists(p):
                _icon_cache[name] = Image.open(p).convert("RGBA")
                break
        else:
            _icon_cache[name] = None
    return _icon_cache[name]


def font(px):
    return ImageFont.truetype(FONT, max(6, int(px)))


class Canvas:
    """Draws in screen pixels (already scaled), supersampled."""

    def __init__(self, w, h, bg):
        self.w, self.h = w, h
        self.img = bg.resize((w * SS, h * SS)).convert("RGBA")
        self.boxes = []  # (name, x0, y0, x1, y1) for overlap checks

    def layer(self):
        return Image.new("RGBA", self.img.size, (0, 0, 0, 0))

    def comp(self, lay):
        self.img = Image.alpha_composite(self.img, lay)

    def rect(self, x, y, w, h, color, radius=0, stroke=0, stroke_color=(22, 20, 38), alpha=255, grad=True):
        lay = self.layer()
        d = ImageDraw.Draw(lay)
        X, Y, W, H, R = [v * SS for v in (x, y, w, h, radius)]
        if stroke:
            st = stroke * SS
            d.rounded_rectangle([X - st, Y - st, X + W + st, Y + H + st], radius=R + st, fill=stroke_color + (alpha,))
        d.rounded_rectangle([X, Y, X + W, Y + H], radius=R, fill=tuple(color) + (alpha,))
        if grad and h > 4:
            # Darker bottom like Ui.gradient (white -> 175 grey multiply).
            shade = self.layer()
            sd = ImageDraw.Draw(shade)
            steps = 24
            for i in range(steps):
                t = i / (steps - 1)
                a = int(70 * t * alpha / 255)
                sd.rectangle([X, Y + H * i / steps, X + W, Y + H * (i + 1) / steps + 1], fill=(0, 0, 20, a))
            mask = Image.new("L", lay.size, 0)
            ImageDraw.Draw(mask).rounded_rectangle([X, Y, X + W, Y + H], radius=R, fill=255)
            lay = Image.alpha_composite(lay, Image.composite(shade, self.layer(), mask))
        self.comp(lay)

    def icon(self, name, x, y, w, h, rot=0, alpha=255):
        im = icon(name)
        if im is None:
            self.rect(x, y, w, h, (255, 0, 255), radius=4, grad=False)
            return
        if rot:
            im = im.rotate(rot, expand=True)
        r = min(w / im.width, h / im.height)
        iw, ih = max(1, int(im.width * r * SS)), max(1, int(im.height * r * SS))
        im = im.resize((iw, ih), Image.LANCZOS)
        if alpha < 255:
            im.putalpha(im.split()[3].point(lambda v: v * alpha // 255))
        lay = self.layer()
        lay.paste(im, (int((x + w / 2) * SS - iw / 2), int((y + h / 2) * SS - ih / 2)), im)
        self.comp(lay)

    def text(self, x, y, w, h, s, color=(255, 255, 255), align="c", stroke=2.5, size=None):
        """TextScaled: the biggest size that fits the box (or a fixed size)."""
        if not s:
            return
        if size is None:
            px = h * SS
            while px > 6:
                f = font(px)
                b = f.getbbox(s)
                if b[2] - b[0] <= w * SS and (b[3] - b[1]) <= h * SS * 0.92:
                    break
                px -= 1
        else:
            px = size * SS
        f = font(px)
        b = f.getbbox(s)
        tw, th = b[2] - b[0], b[3] - b[1]
        X = {"l": x * SS, "c": x * SS + (w * SS - tw) / 2, "r": (x + w) * SS - tw}[align] - b[0]
        Y = y * SS + (h * SS - th) / 2 - b[1]
        lay = self.layer()
        ImageDraw.Draw(lay).text((X, Y), s, font=f, fill=tuple(color) + (255,), stroke_width=int(stroke * SS * px / (h * SS + 1e-6) if size is None else stroke * SS),
                                 stroke_fill=(22, 20, 38, 255))
        self.comp(lay)

    def dim(self, hole, alpha=128):
        lay = self.layer()
        d = ImageDraw.Draw(lay)
        d.rectangle([0, 0, self.w * SS, self.h * SS], fill=(0, 0, 0, alpha))
        x, y, w, h = [v * SS for v in hole]
        d.rectangle([x, y, x + w, y + h], fill=(0, 0, 0, 0))
        self.comp(lay)

    def outline(self, name, x, y, w, h):
        self.boxes.append((name, x, y, x + w, y + h))

    def save(self, path):
        self.img.resize((self.w, self.h), Image.LANCZOS).convert("RGB").save(path)


def background(w, h):
    """A plain snowy scene so the HUD reads like it would in game."""
    im = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(im)
    for y in range(h):
        t = y / h
        if t < 0.55:
            c = (int(120 + 80 * t), int(180 + 50 * t), 250)
        else:
            k = (t - 0.55) / 0.45
            c = (int(225 + 20 * k), int(235 + 12 * k), 250)
        d.line([(0, y), (w, y)], fill=c)
    # A few pines and the player in the middle.
    for k, x in enumerate((0.12, 0.2, 0.78, 0.88, 0.95)):
        bx, by = x * w, h * 0.6
        d.polygon([(bx, by - h * 0.25), (bx - h * 0.08, by), (bx + h * 0.08, by)], fill=(40, 140, 90))
    cx, cy = w / 2, h * 0.62
    d.rectangle([cx - h * 0.025, cy - h * 0.12, cx + h * 0.025, cy], fill=(240, 200, 60))
    d.ellipse([cx - h * 0.03, cy - h * 0.18, cx + h * 0.03, cy - h * 0.12], fill=(255, 220, 160))
    return im


class Hud:
    def __init__(self, dev):
        self.W, self.H, self.il, self.it, self.ir, self.ib = DEVICES[dev]
        self.aw = self.W - self.il - self.ir
        self.ah = self.H - self.it - self.ib
        self.s = ui_scale(self.W, self.H)
        self.c = Canvas(self.W, self.H, background(self.W, self.H))

    def place(self, d, size=None):
        """Top-left (screen px) and scale of a cluster def from HudLayout."""
        sw, sh = size or d["Size"]
        s = self.s
        px = self.il + d["Pos"][0] * self.aw + d["Pos"][1]
        py = self.it + d["Pos"][2] * self.ah + d["Pos"][3]
        return px - d["Anchor"][0] * sw * s, py - d["Anchor"][1] * sh * s, s

    # ---- widgets (design units * s)
    def tile(self, x, y, s, name, color, word):
        t = L["Tile"] * s
        self.c.rect(x, y, t, t, color, radius=t * 0.22, stroke=3 * s)
        self.c.icon(name, x + 4 * s, y + 4 * s, t - 8 * s, t - 8 * s)
        wh = max(18, int(L["Tile"] * 0.3)) * s
        self.c.text(x - 12 * s, y + t - 6 * s, t + 24 * s, wh, word)

    def rail(self, key, tiles):
        d = L[key]
        x0, y0, s = self.place(d)
        cell_w, cell_h, gap = L["Tile"], L["Tile"] + L["TileWord"], L["TileGap"]
        rows = (len(tiles) + 1) // 2
        content_h = rows * cell_h + (rows - 1) * gap
        top = y0 + (d["Size"][1] - content_h) / 2 * s  # VerticalAlignment Center
        right = d["Anchor"][0] > 0.5
        for i, (name, color, word) in enumerate(tiles):
            r, col = divmod(i, 2)
            n_in_row = min(2, len(tiles) - r * 2)
            if right:
                # HorizontalAlignment Right: the row's cells hug the right edge.
                rw = n_in_row * cell_w + (n_in_row - 1) * gap
                cx = x0 + (d["Size"][0] - rw + col * (cell_w + gap)) * s
            else:
                cx = x0 + col * (cell_w + gap) * s
            self.tile(cx, top + r * (cell_h + gap) * s, s, name, color, word)
        self.c.outline(key, x0, top, d["Size"][0] * s, (content_h + 6) * s)

    def stats(self, cash=True):
        d = L["Stats"]
        x, y, s = self.place(d)
        w = d["Size"][0]
        rows = [("Cash", (110, 235, 90), "$1.2K", 0)] if cash else []
        rows.append(("Power", (120, 210, 255), "245", L["StatRow"]))
        for name, color, val, oy in rows:
            self.c.icon(name, x, y + oy * s, 50 * s, 50 * s)
            self.c.text(x + 56 * s, y + (oy + 4) * s, (w - 58) * s, 42 * s, val, color, align="l", stroke=3)
        self.c.outline("Stats", x, y, w * s, d["Size"][1] * s)

    def top_right(self):
        d = L["TopRight"]
        x, y, s = self.place(d)
        w = d["Size"][0]
        self.c.rect(x + 24 * s, y + 6 * s, (w - 24) * s, 30 * s, (20, 24, 54), radius=15 * s, stroke=3 * s, grad=False)
        self.c.rect(x + 24 * s, y + 6 * s, (w - 24) * s * 0.4, 30 * s, (60, 170, 255), radius=15 * s)
        self.c.text(x + 56 * s, y + 9 * s, (w - 64) * s, 24 * s, "40%")
        self.c.icon("Storm", x - 1 * s, y - 4 * s, 50 * s, 50 * s)
        cw, ch = L["Chip"]
        for k, (ic, col, txt) in enumerate((("Power", (255, 120, 60), "x2 4:59"), ("Luck", (70, 205, 95), "x2 9:12"))):
            cx = x + (w - cw - k * (cw + 8)) * s
            cy = y + 46 * s
            self.c.rect(cx, cy, cw * s, ch * s, col, radius=ch / 2 * s, stroke=3 * s)
            self.c.icon(ic, cx - 6 * s, cy - 3 * s, (ch + 6) * s, (ch + 6) * s)
            self.c.text(cx + ch * s, cy + 4 * s, (cw - ch - 4) * s, (ch - 8) * s, txt)
        self.c.outline("TopRight", x, y, w * s, (46 + ch) * s)

    def action(self, kind):
        d = L["Action"]
        x, y, s = self.place(d)
        w, h = d["Size"]
        if kind == "Roll":
            self.c.rect(x, y, w * s, h * s, (60, 170, 255), radius=h / 2 * s, stroke=4 * s)
            isz = h + 14
            self.c.icon("Icon_Snowball", x + (h * 0.42 - isz / 2) * s, y + (h / 2 - 4 - isz / 2) * s, isz * s, isz * s)
            left = h * 0.95
            self.c.text(x + left * s, y + (h / 2 - h * 0.31) * s, (w - left - 14) * s, h * 0.62 * s, "ROLL")
        else:
            self.c.rect(x, y, w * s, h * s, (235, 70, 70), radius=h / 2 * s, stroke=4 * s)
            self.c.text(x + 14 * s, y + (h / 2 - h * 0.31) * s, (w - 28) * s, h * 0.62 * s, "STOP")
        self.c.outline("Action", x, y, w * s, h * s)
        return (x, y, w * s, h * s)

    def goal(self, ic, words, bar=None, button=None):
        d = L["Goal"]
        x, y, s = self.place(d)
        w, h = d["Size"]
        self.c.rect(x, y, w * s, h * s, (0, 0, 0), radius=h / 2 * s, alpha=150, grad=False)
        self.c.icon(ic, x + (22 - (h + 14) / 2) * s, y + (h / 2 - (h + 14) / 2) * s, (h + 14) * s, (h + 14) * s)
        self.c.text(x + 62 * s, y + 9 * s, (w - 86) * s, 40 * s, words)
        bottom = h
        if bar is not None:
            self.c.rect(x + 62 * s, y + (h + 4) * s, (w - 90) * s, 14 * s, (20, 24, 54), radius=7 * s, stroke=2 * s, grad=False)
            self.c.rect(x + 62 * s, y + (h + 4) * s, (w - 90) * s * bar, 14 * s, (60, 170, 255), radius=7 * s)
            bottom = h + 20
        rect = None
        if button:
            bx, by = x + (w / 2 - 85) * s, y + (h + 14) * s
            self.c.rect(bx, by, 170 * s, 58 * s, (70, 205, 95), radius=12 * s, stroke=3 * s)
            self.c.text(bx + 5 * s, by + 4 * s, 160 * s, 50 * s, button)
            rect = (bx, by, 170 * s, 58 * s)
            bottom = h + 14 + 58
        self.c.outline("Goal", x, y, w * s, bottom * s)
        return rect

    def toast(self, text, color=(70, 205, 95)):
        s = self.s
        f = font(24 * SS)
        b = f.getbbox(text)
        w = (b[2] - b[0]) / SS + 36
        x = self.il + self.aw / 2 - w * s / 2
        y = self.it + 78
        self.c.rect(x, y, w * s, 40 * s, color, radius=20 * s, stroke=3 * s)
        self.c.text(x + 18 * s, y + 5 * s, (w - 36) * s, 30 * s, text, size=24 * s)
        self.c.outline("Toast", x, y, w * s, 40 * s)

    def hand(self, rect):
        x, y, w, h = rect
        size = max(48, min(96, h * 0.9))
        self.c.icon("Tap", x + w - 20, y + h * 0.45, size, size)

    def meter(self):
        d = L["Meter"]
        x, y, s = self.place(d)
        W, H = d["Size"]
        w, h = 66, H - 70
        tx = x + (W / 2 - w / 2) * s
        self.c.rect(tx, y, w * s, h * s, (235, 70, 70), radius=w / 2 * s, stroke=5 * s, stroke_color=(255, 255, 255), grad=False)
        yw, gw = 0.4, 0.14
        self.c.rect(tx, y + h * (0.5 - yw / 2) * s, w * s, h * yw * s, (255, 205, 60), grad=False)
        self.c.rect(tx, y + h * (0.5 - gw / 2) * s, w * s, h * gw * s, (70, 205, 95), grad=False)
        self.c.icon("Star", x + (W / 2 + w / 2 + 6) * s, y + (h / 2 - 26) * s, 52 * s, 52 * s)
        sy = y + h * 0.3 * s
        self.c.rect(x + (W / 2 - (w + 26) / 2) * s, sy - 7 * s, (w + 26) * s, 14 * s, (255, 255, 255), radius=7 * s, stroke=3 * s, grad=False)
        self.c.text(x + (W / 2 - (W + 40) / 2) * s, y + (h + 12) * s, (W + 40) * s, 52 * s, "TAP!", (255, 205, 60))
        self.c.icon("Tap", x + (W / 2 + 96 - 42) * s, y + (h + 30) * s, 84 * s, 84 * s)
        self.c.outline("Meter", x, y, W * s, H * s)

    def luck(self):
        d = L["Luck"]
        x, y, s = self.place(d)
        w = d["Size"][0]
        self.c.rect(x, y, w * s, 74 * s, (0, 0, 0), radius=37 * s, alpha=115, grad=False)
        self.c.text(x + 10 * s, y + 2 * s, (w - 20) * s, 58 * s, "12.5X", (255, 215, 60), stroke=3)
        self.c.text(x, y + 58 * s, w * s, 22 * s, "LUCK")
        self.c.rect(x, y + 90 * s, w * s, 40 * s, (70, 170, 90), radius=20 * s, stroke=3 * s)
        self.c.text(x + 10 * s, y + 94 * s, (w - 20) * s, 32 * s, "Pine Forest")
        self.c.outline("Luck", x, y, w * s, 130 * s)

    def result(self):
        d = L["Result"]
        x, y, s = self.place(d)
        w, h = d["Size"]
        self.c.rect(x, y, w * s, h * s, (20, 24, 54), radius=18 * s, stroke=4 * s, grad=False)
        self.c.text(x + 15 * s, y + 16 * s, (w - 30) * s, 60 * s, "Frozen Lake", (90, 200, 230))
        cx = x + (w / 2 - 150) * s
        self.c.icon("Cash", cx, y + 80 * s, 56 * s, 56 * s)
        self.c.text(cx + 64 * s, y + 83 * s, 236 * s, 50 * s, "+$2.4K", (110, 235, 90), align="l")
        for k in range(3):
            self.c.icon("Egg" if k < 2 else "GoldenEgg", x + (w / 2 - 87 + k * 58) * s, y + 142 * s, 52 * s, 52 * s)
        self.c.text(x + 15 * s, y + (h - 36) * s, (w - 30) * s, 26 * s, "tap to continue", (190, 200, 230), stroke=2)
        # tilted tag
        self.c.rect(x + (w - 40 - 85) * s, y + (4 - 22) * s, 170 * s, 44 * s, (255, 205, 60), radius=10 * s, stroke=3 * s)
        self.c.text(x + (w - 40 - 85) * s, y + (4 - 22) * s, 170 * s, 44 * s, "NEW BEST!")
        self.c.outline("Result", x, y, w * s, h * s)
        # banner at 30% height
        bw, bh = 700 * s, 100 * s
        bx, by = self.il + self.aw / 2 - bw / 2, self.it + self.ah * 0.3 - bh / 2
        self.c.text(bx, by, bw, bh, "SUPER LUCKY!", (255, 110, 210), stroke=5)
        self.c.outline("Banner", bx + bw * 0.15, by, bw * 0.7, bh)

    def window(self):
        s = self.s
        w, h = 620, 420
        x, y = self.il + self.aw / 2 - w * s / 2, self.it + self.ah / 2 - h * s / 2
        self.c.rect(x, y, w * s, h * s, (20, 24, 54), radius=16 * s, stroke=4 * s, grad=False)
        self.c.rect(x, y, w * s, 56 * s, (196, 60, 230), radius=16 * s, grad=False)
        self.c.rect(x, y + 40 * s, w * s, 16 * s, (160, 55, 225), grad=False)
        self.c.text(x + 18 * s, y + 7 * s, (w - 90) * s, 42 * s, "Shop", align="l")
        self.c.rect(x + (w - 14 - 23) * s, y + (14 - 23) * s, 46 * s, 46 * s, (235, 70, 70), radius=10 * s, stroke=3 * s)
        self.c.text(x + (w - 14 - 17) * s, y + (14 - 17) * s, 34 * s, 34 * s, "X")
        cols = [((255, 255, 255), "Potion", "Lucky"), ((90, 220, 110), "Gem", "Gems"), ((70, 150, 255), "Crown", "VIP"), ((170, 90, 255), "Chest", "Pack")]
        for k, (col, ic, name) in enumerate(cols):
            cx, cy = x + (20 + k * 148) * s, y + 76 * s
            self.c.rect(cx, cy, 132 * s, 300 * s, col, radius=14 * s, stroke=3 * s)
            self.c.text(cx + 6 * s, cy + 8 * s, 120 * s, 30 * s, name)
            self.c.icon(ic, cx + 16 * s, cy + 50 * s, 100 * s, 100 * s)
            self.c.rect(cx + 8 * s, cy + 240 * s, 116 * s, 48 * s, (255, 150, 40), radius=10 * s, stroke=3 * s)
            self.c.text(cx + 12 * s, cy + 246 * s, 108 * s, 36 * s, "R$ 49")


RAIL_L = [("Shop", (255, 70, 90), "Shop"), ("Pets", (255, 160, 40), "Pets"), ("Upgrade", (70, 200, 80), "Upgrade"),
          ("Base", (70, 130, 255), "Home"), ("Rebirth", (180, 90, 255), "Rebirth")]
RAIL_R = [("Daily", (255, 200, 60), "Daily"), ("Gift", (255, 110, 150), "Gifts"), ("Wheel", (70, 200, 255), "Spin"),
          ("Codes", (150, 120, 255), "Codes")]


def overlaps(c):
    bad = []
    for i in range(len(c.boxes)):
        for j in range(i + 1, len(c.boxes)):
            a, b = c.boxes[i], c.boxes[j]
            if a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]:
                bad.append(f"{a[0]} x {b[0]}")
    for name, x0, y0, x1, y1 in c.boxes:
        if x0 < 0 or y0 < 0 or x1 > c.w or y1 > c.h:
            bad.append(f"{name} off screen ({x0:.0f},{y0:.0f})-({x1:.0f},{y1:.0f})")
    return bad


def scene(dev, mode):
    h = Hud(dev)
    if mode in ("Normal", "Training", "Spotlight", "Results", "Window"):
        h.rail("LeftRail", RAIL_L)
        h.rail("RightRail", RAIL_R)
        h.top_right()
        h.stats()
    if mode == "Normal":
        h.action("Roll")
        h.goal("Power", "Step on your roller!")
        h.toast("Stone Roller! +5 Power")
    elif mode == "Training":
        h.action("Stop")
        h.goal("Power", "Train to 100 Power!", bar=0.45)
    elif mode == "Spotlight":
        rect = h.action("Roll")
        h.goal("Icon_Snowball", "Roll your snowball!")
        pad = 10
        h.c.dim((rect[0] - pad, rect[1] - pad, rect[2] + pad * 2, rect[3] + pad * 2))
        h.hand((rect[0] - pad, rect[1] - pad, rect[2] + pad * 2, rect[3] + pad * 2))
    elif mode == "EggStep":
        h.rail("LeftRail", RAIL_L)
        h.rail("RightRail", RAIL_R)
        h.top_right()
        h.stats()
        h.action("Roll")
        rect = h.goal("Egg", "Put your egg down!", button="PLACE")
        pad = 10
        h.c.dim((rect[0] - pad, rect[1] - pad, rect[2] + pad * 2, rect[3] + pad * 2))
        h.hand((rect[0] - pad, rect[1] - pad, rect[2] + pad * 2, rect[3] + pad * 2))
    elif mode == "Packing":
        h.stats()
        h.goal("Icon_Snowball", "Tap when it's green!")
        h.meter()
    elif mode == "Rolling":
        h.stats(cash=False)
        h.luck()
    elif mode == "Results":
        h.action("Roll")
        h.result()
    elif mode == "Window":
        h.action("Roll")
        h.window()
    return h


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "art", "out", "hud")
    os.makedirs(out, exist_ok=True)
    modes = ["Normal", "Training", "Spotlight", "EggStep", "Packing", "Rolling", "Results", "Window"]
    report = []
    for dev in DEVICES:
        shots = []
        for mode in modes:
            h = scene(dev, mode)
            path = os.path.join(out, f"{dev}_{mode}.png")
            h.c.save(path)
            shots.append(path)
            bad = overlaps(h.c) if mode not in ("Results", "Window", "Spotlight", "EggStep") else [
                b for b in overlaps(h.c) if "Result" not in b and "Banner" not in b]
            report.append(f"{dev:5} {mode:9} " + ("OK" if not bad else "; ".join(bad)))
        # Contact sheet
        ims = [Image.open(p) for p in shots]
        w, hh = ims[0].size
        cols = 2
        rows = (len(ims) + 1) // cols
        sheet = Image.new("RGB", (w * cols + 10 * (cols - 1), hh * rows + 10 * (rows - 1)), (30, 30, 30))
        for k, im in enumerate(ims):
            sheet.paste(im, ((k % cols) * (w + 10), (k // cols) * (hh + 10)))
        sheet.save(os.path.join(out, f"{dev}_sheet.png"))
    print("\n".join(report))


if __name__ == "__main__":
    main()
