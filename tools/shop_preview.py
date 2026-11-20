"""Draws the Shop (ShopController, ported from Sweep the World) on a phone and a PC screen,
over the HUD from tools/hud_preview.py, using the same sizes and window scale as the Luau
code, so the layout can be checked before a push.

  python tools/shop_preview.py [out_dir]     (needs Pillow + the Fredoka One font, see hud_preview)

Writes <Device>_Shop_<scroll>.png for the top of the list and further down.
The art is approximate (stud texture and glow are drawn here, real pictures from art/ui);
positions, sizes, colours and the window scale are copies of ShopController.luau.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
import hud_preview as hp  # noqa: E402

D = 2  # design supersample
WIN_W, WIN_H, PANEL_W, NAV_W = 820, 520, 720, 96
CELL_W, CELL_H = 220, 226
INK = (23, 25, 30)
BODY = (58, 62, 73)
GREEN = (76, 209, 55)
GIFT = (178, 77, 255)
RED = (255, 77, 94)
GREY = (166, 174, 194)
YELLOW = (255, 227, 77)

SECTIONS = [  # key, title, icon, heading colour, card colour
    ("Featured", "Featured", "Gift", (255, 212, 59), (255, 77, 94)),
    ("Passes", "Passes", "Star", (197, 155, 255), (155, 107, 255)),
    ("Boosts", "Boosts", "Luck", (255, 154, 60), (255, 128, 48)),
    ("Power", "Power", "Power", (127, 200, 255), (62, 142, 240)),
    ("Rolls", "Rolls", "Roll", (255, 126, 182), (255, 95, 162)),
    ("Money", "Money", "Cash", (107, 227, 74), (76, 209, 55)),
]
R = ""  # Roblox's Robux glyph; drawn as "R$" here
PASSES = [  # sorted by price like the Shop
    ("Cash2x", 99, "Shop_Pass2xCash", "2x", "CASH", "POPULAR"),
    ("PopMagnet", 99, "Magnet", "AUTO", "POPS", None),
    ("AutoTrain", 129, "Shop_PassFastTrain", "2x", "TRAIN SPEED", None),
    ("Train2x", 149, "Shop_Pass2xPower", "2x", "POWER", None),
    ("Lucky", 149, "Shop_PassLucky", "+50%", "LUCK", None),
    ("ExtraEquips", 199, "Pets", "+2", "PET EQUIPS", None),
    ("ExtraSlots", 199, "Base", "+4", "PET SLOTS", None),
    ("FastHatch", 229, "Clock", "2x", "HATCH SPEED", None),
    ("CarryTwo", 149, "GoldenEgg", "CARRY", "2 EGGS", None),
    ("GoldenSnowball", 249, "Shop_PassGoldBall", "GOLD", "BALL", "BEST"),
    ("VIP", 249, "Shop_PassVIP", "", "VIP", None),
]


class Board:
    """Draws in design px (x D)."""

    def __init__(self, w, h):
        self.img = Image.new("RGBA", (w * D, h * D), (0, 0, 0, 0))

    def lay(self):
        return Image.new("RGBA", self.img.size, (0, 0, 0, 0))

    def comp(self, l):
        self.img = Image.alpha_composite(self.img, l)

    def box(self, x, y, w, h, color, stroke=0, stroke_color=INK, studs=False, shade=True, alpha=255):
        l = self.lay()
        d = ImageDraw.Draw(l)
        X, Y, W, H = x * D, y * D, w * D, h * D
        if stroke:
            s = stroke * D
            d.rectangle([X - s / 2, Y - s / 2, X + W + s / 2, Y + H + s / 2], fill=stroke_color + (255,))
            X2, Y2, W2, H2 = X + s / 2, Y + s / 2, W - s, H - s
        else:
            X2, Y2, W2, H2 = X, Y, W, H
        d.rectangle([X2, Y2, X2 + W2, Y2 + H2], fill=tuple(color) + (alpha,))
        if studs:
            step = 40 * D
            r = 11 * D
            lighter = tuple(min(255, int(c * 1.12 + 8)) for c in color) + (alpha,)
            darker = tuple(int(c * 0.82) for c in color) + (alpha,)
            yy = Y2 + step / 2
            while yy < Y2 + H2:
                xx = X2 + step / 2
                while xx < X2 + W2:
                    d.ellipse([xx - r, yy - r + D, xx + r, yy + r + D], fill=darker)
                    d.ellipse([xx - r, yy - r, xx + r, yy + r], fill=lighter)
                    xx += step
                yy += step
            # Keep studs inside the box.
            mask = Image.new("L", l.size, 0)
            ImageDraw.Draw(mask).rectangle([X2, Y2, X2 + W2, Y2 + H2], fill=255)
            bg = self.lay()
            bg.paste(l, (0, 0), mask)
            if stroke:
                ImageDraw.Draw(bg).rectangle([X - s / 2, Y - s / 2, X + W + s / 2, Y + H + s / 2], outline=stroke_color + (255,),
                                             width=int(s))
            l = bg
        if shade and h > 6:
            sh = self.lay()
            sd = ImageDraw.Draw(sh)
            for i in range(20):
                a = int(55 * i / 19)
                sd.rectangle([X2, Y2 + H2 * i / 20, X2 + W2, Y2 + H2 * (i + 1) / 20], fill=(0, 0, 20, a))
            l = Image.alpha_composite(l, sh)
        self.comp(l)

    def glow(self, cx, cy, size, alpha=190):
        g = Image.new("L", (int(size * D), int(size * D)), 0)
        ImageDraw.Draw(g).ellipse([size * D * 0.18, size * D * 0.18, size * D * 0.82, size * D * 0.82], fill=alpha)
        g = g.filter(ImageFilter.GaussianBlur(size * D * 0.12))
        l = self.lay()
        white = Image.new("RGBA", g.size, (255, 255, 255, 0))
        white.putalpha(g)
        l.paste(white, (int(cx * D - size * D / 2), int(cy * D - size * D / 2)), white)
        self.comp(l)

    def icon(self, name, x, y, w, h):
        im = hp.icon(name)
        if im is None:
            self.box(x, y, w, h, (255, 0, 255), shade=False)
            return
        r = min(w / im.width, h / im.height)
        iw, ih = max(1, int(im.width * r * D)), max(1, int(im.height * r * D))
        im = im.resize((iw, ih), Image.LANCZOS)
        l = self.lay()
        l.paste(im, (int((x + w / 2) * D - iw / 2), int((y + h / 2) * D - ih / 2)), im)
        self.comp(l)

    def text(self, x, y, w, h, parts, maxsize, stroke=2.5, align="c"):
        """parts: [(text, colour)] drawn on one line, TextScaled up to maxsize."""
        if isinstance(parts, str):
            parts = [(parts, (255, 255, 255))]
        parts = [(t.replace(R, "R$ ").replace("R$  ", "R$ "), c) for t, c in parts if t]
        if not parts:
            return
        full = " ".join(t for t, _ in parts)
        px = min(maxsize, h) * D
        while px > 6:
            f = hp.font(px)
            b = f.getbbox(full)
            if b[2] - b[0] <= w * D and b[3] - b[1] <= h * D * 0.95:
                break
            px -= 1
        f = hp.font(px)
        b = f.getbbox(full)
        tw, th = b[2] - b[0], b[3] - b[1]
        X = {"l": x * D, "c": x * D + (w * D - tw) / 2, "r": (x + w) * D - tw}[align] - b[0]
        Y = y * D + (h * D - th) / 2 - b[1]
        l = self.lay()
        d = ImageDraw.Draw(l)
        sw = int(stroke * D * min(1, px / (maxsize * D) + 0.3))
        for i, (t, c) in enumerate(parts):
            s = t + (" " if i < len(parts) - 1 else "")
            d.text((X, Y), s, font=f, fill=tuple(c) + (255,), stroke_width=sw, stroke_fill=INK + (255,))
            X += f.getlength(s)
        self.comp(l)

    def button(self, x, y, w, h, color, label=None, icon=None, maxsize=28):
        self.box(x, y, w, h, color, stroke=3, studs=True)
        if icon:
            self.icon(icon, x + w / 2 - 17, y + h / 2 - 17, 34, 34)
        if label:
            self.text(x + 6, y + 3, w - 12, h - 6, label, maxsize)


def card(b, x, y, color, pic, hi, lo, price, tag=None, gift=True, owned=False):
    col = GREY if owned else color
    b.box(x, y, CELL_W, CELL_H, col, stroke=4, studs=True)
    b.glow(x + CELL_W / 2, y + 78, 230, 175)
    b.icon(pic, x + CELL_W / 2 - 60, y + 14, 120, 120)
    if tag:
        b.box(x - 6, y + 6, 104, 26, (255, 46, 77), stroke=2.5)
        b.text(x - 3, y + 6, 98, 26, tag, 16, 2)
    b.text(x + 6, y + CELL_H - 60 - 32, CELL_W - 12, 32, [(hi, YELLOW), (lo, (255, 255, 255))], 28, 3)
    if gift and not owned:
        b.button(x + 8, y + CELL_H - 54, 50, 46, GIFT, icon="Gift")
        b.button(x + 68, y + CELL_H - 54, CELL_W - 76, 46, GREEN, label=price)
    else:
        b.button(x + 8, y + CELL_H - 54, CELL_W - 16, 46, GREY if owned else GREEN, label="Owned" if owned else price)


def list_content(width):
    """The list (inside its padding) drawn top to bottom; returns the image and the y of each heading."""
    items = []  # (kind, height, payload)
    heads = {}

    def heading(key, title, colour):
        items.append(("head", 52, (title, colour)))
        heads[key] = None

    def grid(cards, colour):
        rows = (len(cards) + 2) // 3
        items.append(("grid", rows * CELL_H + (rows - 1) * 12, (cards, colour)))

    for key, title, ic, hcol, ccol in SECTIONS:
        heading(key, title, hcol)
        if key == "Featured":
            items.append(("starter", 172, None))
        elif key == "Passes":
            grid([(p[2], p[3], p[4], f"R$ {p[1]}", p[5], False) for p in PASSES], ccol)
        elif key == "Boosts":
            items.append(("luck", 132, None))
            grid([("Shop_Pass2xPower", "2x", "POWER 10m", "R$ 13", "CHEAP", True),
                  ("Shop_Pass2xCash", "2x", "CASH 15m", "R$ 25", None, True),
                  ("Shop_SuperLucky", "x100", "LUCK ROLL", "R$ 9", None, True)], ccol)
        elif key == "Power":
            grid([(f"Shop_Power{i}", a, "POWER", f"R$ {p}", "BEST VALUE" if i == 4 else None, True)
                  for i, a, p in ((1, "+2.4K", 3), (2, "+9.6K", 9), (3, "+48K", 39), (4, "+144K", 99))], ccol)
        elif key == "Rolls":
            grid([(f"Shop_Lucky{n}", f"x{n}", "LUCKY ROLLS", f"R$ {p}", t, True)
                  for n, p, t in ((3, 27, None), (10, 69, "POPULAR"), (35, 199, None), (100, 499, "BEST VALUE"))], ccol)
        elif key == "Money":
            grid([(f"Shop_Cash{i}", a, "", f"R$ {p}", "BEST VALUE" if i == 4 else None, True)
                  for i, a, p in ((1, "+$12.5K", 25), (2, "+$48K", 59), (3, "+$150K", 149), (4, "+$520K", 399))], ccol)
    items.append(("codes", 172, None))
    total = 8 + sum(h for _, h, _ in items) + 12 * (len(items) - 1) + 14
    b = Board(width, total)
    y = 8
    for kind, h, payload in items:
        if kind == "head":
            title, colour = payload
            b.text(0, y, width, h, f"-- {title.upper()} --", 40, 4) if False else b.text(0, y, width, h, [(f"-- {title.upper()} --", colour)], 40, 4)
            heads[title] = y
        elif kind == "grid":
            cards, colour = payload
            gx = (width - (3 * CELL_W + 20)) / 2
            for i, (pic, hi, lo, price, tag, gift) in enumerate(cards):
                r, c = divmod(i, 3)
                n = min(3, len(cards) - r * 3)
                rx = (width - (n * CELL_W + (n - 1) * 10)) / 2  # centred rows
                card(b, rx + c * (CELL_W + 10), y + r * (CELL_H + 12), colour, pic, hi, lo, price, tag, gift)
        elif kind == "starter":
            b.box(0, y, width, h, RED, stroke=4, stroke_color=(255, 176, 32), studs=True)
            b.box(0, y, width, 44, (0, 0, 0), alpha=115, shade=False)
            b.box(8, y + 7, 96, 30, RED, stroke=2.5)
            b.text(12, y + 7, 88, 30, "OFFER", 18, 2)
            b.text(114, y + 3, width - 320, 38, [("STARTER PACK", YELLOW)], 30, 3, align="l")
            b.box(width - 208, y + 7, 200, 30, (27, 16, 48), alpha=205, shade=False)
            b.icon("Clock", width - 204, y + 10, 24, 24)
            b.text(width - 176, y + 9, 164, 26, "1h 52m 10s", 18, 0, align="l")
            for i, (pic, cap) in enumerate((("Shop_StarterRoller", "ROLLER"), ("Shop_EpicEgg", "Epic Egg"),
                                            ("Shop_Lucky3", "x3 Rolls"), ("Shop_Pass2xPower", "2x 15m"))):
                cx = 10 + i * 76
                cy = y + h - 10 - 84
                b.box(cx + 5, cy, 60, 60, (255, 255, 255), alpha=46, shade=False)
                b.icon(pic, cx + 8, cy + 3, 54, 54)
                b.text(cx - 3, cy + 62, 76, 22, cap, 16, 2)
            b.box(width - 172, y + h - 96, 150, 26, (27, 16, 48), stroke=2)
            b.text(width - 168, y + h - 95, 142, 24, [("WORTH R$ 56", YELLOW)], 16, 2)
            b.button(width - 202, y + h - 64, 190, 54, GREEN, label="R$ 9", maxsize=30)
        elif kind == "luck":
            b.box(0, y, width, h, (46, 158, 74), stroke=4, studs=True)
            b.glow(62, y + h / 2, 150, 150)
            b.icon("Shop_ServerLuck", 12, y + h / 2 - 50, 100, 100)
            b.text(124, y + 10, 260, 28, [("SERVER LUCK", YELLOW)], 26, 3, align="l")
            b.text(124, y + 38, width - 320, 56, [("1x", (255, 255, 255)), ("> 2x", YELLOW)], 50, 3.5, align="l")
            b.text(124, y + 96, width - 320, 22, "Luckier rolls for EVERYONE here!", 16, 2, align="l")
            b.text(width - 202, y + 12, 190, 26, "Lasts 15 min", 20, 2.5, align="r")
            b.button(width - 192, y + h - 68, 180, 54, GREEN, label="R$ 19", maxsize=30)
        elif kind == "codes":
            b.box(0, y, width, h, (107, 61, 240), stroke=4, studs=True)
            b.icon("Codes", 12, y + h / 2 - 54, 108, 108)
            b.text(132, y + 10, width - 150, 40, [("CODES", (255, 200, 60))], 38, 3.5, align="l")
            b.text(132, y + 52, width - 150, 22, [("Join the group for free codes!", (200, 208, 232))], 18, 2, align="l")
            b.box(132, y + 84, width - 318, 54, (255, 255, 255), stroke=3, shade=False)
            b.text(146, y + 90, 200, 42, [("Enter code...", (138, 144, 160))], 24, 0, align="l")
            b.button(width - 170, y + 84, 156, 54, GREEN, label="Redeem")
        y += h + 12
    return b.img, heads


def window(scroll_to=None):
    """The whole Shop window in design px x D."""
    b = Board(WIN_W, WIN_H)
    b.box(0, 0, PANEL_W, WIN_H, BODY, stroke=4, studs=True, shade=False)
    b.box(0, 0, PANEL_W, 70, GREEN, stroke=4, studs=True)
    b.text(18, 0, 300, 70, "Shop", 44, 4, align="l")
    b.button(PANEL_W - 66, 8, 58, 54, RED, label="X", maxsize=34)
    lw = PANEL_W - 12 - 8 - 16  # list width - scrollbar - padding
    content, heads = list_content(lw)
    vy = heads.get(scroll_to, 0) - 4 if scroll_to else 0
    vh = WIN_H - 80
    vy = max(0, min(vy, content.height / D - vh))
    crop = content.crop((0, int(vy * D), content.width, int((vy + vh) * D)))
    b.img.paste(crop, (int((6 + 6) * D), int(74 * D)), crop)
    # Scrollbar
    th = vh * vh / (content.height / D)
    ty = 74 + (vh - th) * vy / max(1, content.height / D - vh)
    b.box(PANEL_W - 6 - 8, ty, 8, th, (154, 163, 184), shade=False)
    b.box(PANEL_W + 4, 76, NAV_W, len(SECTIONS) * 62 + 12, BODY, stroke=4, studs=True, shade=False)
    for i, (key, title, ic, hcol, _) in enumerate(SECTIONS):
        y = 82 + i * 62
        b.icon(ic, PANEL_W + 4 + NAV_W / 2 - 21, y, 42, 42)
        b.text(PANEL_W + 4 - 5, y + 42, NAV_W + 10, 18, [(title, hcol)], 18, 3)
    return b.img


def window_scale(dev):
    W, H, il, it, ir, ib = hp.DEVICES[dev]
    aw, ah = W - il - ir, H - it - ib
    phone = min(W, H) < 500
    s = max(0.4, min(1.15, min(W / 1280, H / 720) * 1.05))
    fit = min((ah - 12) / WIN_H, (aw - 24) / WIN_W)
    w = max(0.3, min(fit, max(s, 1)))
    return w if phone else min(w, s * 0.8)


def shot(dev, scroll_to, path):
    h = hp.scene(dev, "Normal")
    c = h.c
    W, H, il, it, ir, ib = hp.DEVICES[dev]
    k = window_scale(dev)
    # Dim over everything (the oversized Dim button).
    dim = c.layer()
    ImageDraw.Draw(dim).rectangle([0, 0, W * hp.SS, H * hp.SS], fill=(11, 14, 30, 102))
    c.comp(dim)
    win = window(scroll_to)
    ww, wh = int(WIN_W * k * hp.SS), int(WIN_H * k * hp.SS)
    win = win.resize((ww, wh), Image.LANCZOS)
    cx = il + (W - il - ir) / 2
    cy = it + (H - it - ib) / 2
    lay = c.layer()
    lay.paste(win, (int(cx * hp.SS - ww / 2), int(cy * hp.SS - wh / 2)), win)
    c.comp(lay)
    c.save(path)
    x0, y0 = cx - WIN_W * k / 2, cy - WIN_H * k / 2
    return k, (x0, y0, x0 + WIN_W * k, y0 + WIN_H * k)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(hp.ROOT, "art", "out", "shop")
    os.makedirs(out, exist_ok=True)
    for dev in hp.DEVICES:
        for scroll in (None, "Boosts", "Money"):
            path = os.path.join(out, f"{dev}_Shop_{scroll or 'Top'}.png")
            k, box = shot(dev, scroll, path)
            W, H, il, it, ir, ib = hp.DEVICES[dev]
            inside = box[0] >= il and box[1] >= it and box[2] <= W - ir and box[3] <= H - ib
            print(f"{dev:5} {scroll or 'Top':7} scale {k:.2f} window {box[2]-box[0]:.0f}x{box[3]-box[1]:.0f} "
                  f"at ({box[0]:.0f},{box[1]:.0f}) {'inside safe area' if inside else 'OFF THE SAFE AREA'}  card {CELL_W*k:.0f}x{CELL_H*k:.0f}px")


if __name__ == "__main__":
    main()
