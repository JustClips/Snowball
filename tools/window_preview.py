"""Rough render of the Rewards windows (RewardsController): Gifts, Daily and the Lucky
Wheel at 1280x720 with the same sizes as the Luau code, to check the layout reads before
Dev playtests. Eggs are drawn as the egg icon (the game shows the 3D egg).

  /tmp/claude-0/bpyenv/bin/python tools/window_preview.py [outdir]
"""
import math
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from hud_preview import Canvas, ROOT, icon as load_icon, SS  # noqa: E402

W, H = 1280, 720
GREEN, NAVY, DARK = (70, 205, 95), (30, 38, 78), (20, 24, 54)
RAR = {"Rare": (70, 150, 255), "Epic": (170, 90, 255), "Legendary": (255, 200, 40), "Mythic": (255, 80, 160)}
CASH, BOOST, LUCK, GOLD = (70, 200, 90), (255, 140, 50), (60, 200, 120), (255, 200, 50)


def bg():
    im = Image.new("RGB", (W, H), (150, 200, 245))
    im.paste((236, 244, 252), (0, 300, W, H))
    return im


def window(c, w, h, title):
    x, y = (W - w) / 2, (H - h) / 2
    c.rect(x, y, w, h, DARK, radius=16, stroke=4, grad=False)
    c.rect(x, y, w, 56, (196, 60, 230), radius=16, grad=False)
    c.rect(x, y + 40, w, 16, (160, 55, 225), grad=False)
    c.text(x + 18, y + 7, w - 90, 42, title, align="l")
    c.rect(x + w - 14 - 23, y + 14 - 23, 46, 46, (235, 70, 70), radius=10, stroke=3)
    c.text(x + w - 14 - 17, y + 14 - 17, 34, 34, "X")
    return x + 12, y + 62


def rays(c, cx, cy, size, alpha=110):
    im = load_icon("Rays")
    if im is None:
        return
    im = im.resize((int(size * SS), int(size * SS)))
    im.putalpha(im.split()[3].point(lambda v: v * alpha // 255))
    lay = c.layer()
    lay.paste(im, (int(cx * SS - size * SS / 2), int(cy * SS - size * SS / 2)), im)
    c.comp(lay)


def card(c, x, y, w, h, title, color, ico, amount, status, scolor, bonus=None, big=False, done=False):
    c.rect(x, y, w, h, color, radius=14, stroke=3)
    p = 150 if big else int(min(w, h) * 0.5)
    cy = y + h / 2 - (10 if big else 6)
    rays(c, x + w / 2, cy, min(p * 2, w - 4))
    c.text(x + 5, y + 4, w - 10, 40 if big else 28, title)
    if big:
        c.text(x + 10, y + 44, w - 20, 26, "THE BEST!", (255, 200, 50))
    c.icon(ico, x + w / 2 - p / 2, cy - p / 2, p, p)
    if bonus:
        b = p * 0.5
        c.icon(bonus, x + w / 2 + p * 0.42 - b / 2, cy + p * 0.18 - b / 2, b, b)
    ah = 30 if big else 22
    c.text(x + 5, y + h - 40 - ah, w - 10, ah, amount)
    c.rect(x + 8, y + h - 38, w - 16, 32, scolor, radius=16, stroke=3)
    c.text(x + 13, y + h - 35, w - 26, 26, status)
    if done:
        c.rect(x, y, w, h, (10, 12, 30), radius=14, alpha=130, grad=False)
        c.icon("Checkmark", x + w / 2 - 32, y + h * 0.45 - 32, 64, 64)


def gifts(out):
    c = Canvas(W, H, bg())
    cw, ch, gap = 168, 190, 12
    w = 3 * cw + 2 * gap + 24
    h = 2 * ch + gap + 68 + 46
    bx, by = window(c, w, h, "FREE GIFTS")
    c.text(bx, by, w - 24, 28, "Play to unlock free gifts!", (190, 220, 255))
    items = [("2 MIN", CASH, "Cash", "$1.2K", "CLAIMED", NAVY, None, True),
             ("5 MIN", BOOST, "Power", "x2 Power 5m", "CLAIM!", GREEN, None, False),
             ("10 MIN", CASH, "Cash", "$3.4K", "4:12", NAVY, None, False),
             ("20 MIN", LUCK, "Luck", "1x Lucky Roll", "14:12", NAVY, None, False),
             ("35 MIN", RAR["Rare"], "Egg", "Rare Egg", "29:12", NAVY, None, False),
             ("60 MIN", RAR["Epic"], "Egg", "Epic Egg", "54:12", NAVY, None, False)]
    for i, (t, col, ico, amt, st, sc, bo, done) in enumerate(items):
        x = bx + (i % 3) * (cw + gap)
        y = by + 36 + (i // 3) * (ch + gap)
        card(c, x, y, cw, ch, t, col, ico, amt, st, sc, bo, done=done)
    c.save(os.path.join(out, "Gifts.png"))


def daily(out):
    c = Canvas(W, H, bg())
    cw, ch, gap = 150, 168, 10
    w = 3 * cw + 2 * gap + gap + 210 + 24
    h = 2 * ch + gap + 68 + 46
    bx, by = window(c, w, h, "DAILY REWARDS")
    c.text(bx, by, w - 24, 28, "Your reward is ready!", (190, 220, 255))
    items = [(CASH, "Cash", "$2.1K", None), (RAR["Rare"], "Egg", "Rare Egg + x2 Power 10m", "Power"),
             (CASH, "Cash", "$5.0K + +1 Spin", "Wheel"), (LUCK, "Luck", "3x Lucky Roll", None),
             (RAR["Epic"], "Egg", "Epic Egg + 3x Golden Run", "Star"), (BOOST, "Cash", "x2 Cash 15m + Power", "Power")]
    for i, (col, ico, amt, bo) in enumerate(items):
        x = bx + (i % 3) * (cw + gap)
        y = by + 36 + (i // 3) * (ch + gap)
        st, sc, done = ("CLAIMED", NAVY, True) if i == 0 else (("CLAIM!", GREEN, False) if i == 1 else ("LOCKED", NAVY, False))
        card(c, x, y, cw, ch, f"DAY {i + 1}", col, ico, amt, st, sc, bo, done=done)
    card(c, bx + 3 * (cw + gap), by + 36, 210, 2 * ch + gap, "DAY 7", (255, 140, 200), "Pets", "Red Panda + Legendary Egg",
         "LOCKED", NAVY, "Egg", big=True)
    c.save(os.path.join(out, "Daily.png"))


def wheel(out):
    c = Canvas(W, H, bg())
    c.rect(0, 0, W, H, (0, 0, 0), alpha=180, grad=False)
    x0, y0 = (W - 800) / 2, (H - 480) / 2
    size = 450
    cx, cy = x0 + 235, y0 + 240 + 12
    c.icon("SpinWheel", cx - size / 2, cy - size / 2, size, size)
    segs = [("Cash", "$9.9K", "32%"), ("Power", "x2 10m", "18%"), ("Egg", "Rare", "12%"), ("Star", "x2", "17%"),
            ("Egg", "Legendary", "1%"), ("Luck", "x2", "14%"), ("Egg", "Mythic", "1%"), ("Egg", "Epic", "5%")]
    for i, (ico, amt, ch) in enumerate(segs):
        a = math.radians((i + 0.5) * 45)
        r = 0.6 * size / 2
        sx, sy = cx + math.sin(a) * r, cy - math.cos(a) * r
        # draw upright (the game rotates them with the wedge; upright is enough for sizing)
        c.icon(ico, sx - 40, sy - 56 + 42 - 40, 80, 80)
        c.rect(sx - 31, sy - 56 + 84, 62, 24, (22, 20, 38), radius=12, alpha=190, grad=False)
        c.text(sx - 29, sy - 56 + 86, 58, 20, ch, (255, 240, 170))
    c.icon("SpinPointer", cx - 44, y0 - 6 - 13, 88, 88)
    sx, sy = x0 + 800 - 310, y0 + 240 + 12 - 205
    c.rect(sx, sy, 310, 410, DARK, radius=18, stroke=4, grad=False)
    c.text(sx + 12, sy + 10, 286, 42, "SPINS: 1")
    c.text(sx + 12, sy + 52, 286, 22, "Free spin ready!", (150, 255, 120))
    c.rect(sx + 12, sy + 82, 286, 84, GREEN, radius=12, stroke=3)
    c.text(sx + 17, sy + 86, 276, 76, "FREE SPIN!")
    for k, (n, p) in enumerate((("+1", "19"), ("+5", "79"), ("+10", "149"))):  # LayoutOrder
        bx = sx + 12 + (286 - (3 * 88 + 16)) / 2 + k * 96
        c.rect(bx, sy + 178, 88, 76, (150, 70, 240), radius=12, stroke=3)
        c.text(bx + 4, sy + 184, 80, 30, n)
        c.text(bx + 4, sy + 178 + 76 - 32, 80, 26, "R$" + p, (150, 255, 120))
    c.rect(sx + 12, sy + 266, 286, 132, NAVY, radius=12, grad=False)
    for i, (ico, amt, ch) in enumerate(segs):
        ox = sx + 16 + (i % 2) * 143
        oy = sy + 270 + (i // 2) * 32
        c.icon(ico, ox, oy, 28, 28)
        c.text(ox + 32, oy + 3, 107, 24, f"{amt} {ch}", align="l", size=16)
    c.rect(sx + 310 - 8 - 24, sy + 8 - 24, 48, 48, (235, 70, 70), radius=12, stroke=3)
    c.text(sx + 310 - 8 - 18, sy + 8 - 18, 36, 36, "X")
    c.save(os.path.join(out, "Wheel.png"))


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "art", "out", "windows")
    os.makedirs(out, exist_ok=True)
    gifts(out)
    daily(out)
    wheel(out)
    print("written", out)


def rescue(out):
    """Rescue HUD (RescueController) over the bottom hotbar and the stats (PC 1280x720)."""
    c = Canvas(W, H, bg())
    # goal pill
    x, y = (W - 460) / 2, 10
    c.rect(x, y, 460, 58, (40, 40, 40), radius=29, alpha=150, grad=False)
    c.icon("Pin", x + 22 - 36, y + 29 - 36, 72, 72)
    c.text(x + 62, y + 9, 460 - 86, 40, "Run to the flag!", (110, 235, 90))
    ix = x + 80
    c.icon("Egg", ix + 40, y + 64, 40, 40)
    c.text(ix + 84, y + 68, 80, 32, "x2", align="l")
    c.icon("Clock", ix + 160, y + 66, 36, 36)
    c.text(ix + 200, y + 68, 90, 32, "2:31", align="l")
    # LEAVE
    c.rect(24, 18, 150, 56, (235, 70, 70), radius=12, stroke=3)
    c.text(29, 22, 140, 48, "LEAVE")
    # bottom buttons at (0.5, 1, -98)
    bx, by = (W - 520) / 2, H - 98 - 84
    for k, (ico, word, w, ox) in enumerate((("Base", "SLED HOME", 270, 0), ("Exclamation", "NO YETI", 230, 290))):
        px = bx + ox
        c.rect(px, by, w, 78, (150, 70, 240), radius=39, stroke=4)
        c.icon(ico, px + 78 * 0.42 - 46, by + 39 - 4 - 46, 92, 92)
        c.text(px + 74, by + 15, w - 88, 48, word)
        c.rect(px + w / 2 + 30 - 55, by - 4 - 15, 110, 30, GREEN, radius=15, stroke=3)
        c.text(px + w / 2 + 30 - 50, by - 17, 100, 26, "R$" + ("25" if k == 0 else "29"))
    # hotbar (0.5, 1, -10), 616x70
    hx, hy = (W - 616) / 2, H - 10 - 70
    for k in range(7):
        c.rect(hx + k * 78, hy, 70, 70, DARK, radius=14, stroke=3, grad=False)
        c.icon("Egg", hx + k * 78 + 8, hy + 8, 54, 54)
    # stats bottom-left
    c.icon("Cash", 24, H - 14 - 120, 50, 50)
    c.text(80, H - 14 - 116, 190, 42, "$1.2K", (110, 235, 90), align="l")
    c.text(82, H - 14 - 76, 190, 22, "+$42K/s", (150, 255, 120), align="l")
    c.icon("Power", 24, H - 14 - 50, 50, 50)
    c.text(80, H - 14 - 46, 190, 42, "245", (120, 210, 255), align="l")
    c.save(os.path.join(out, "Rescue.png"))


if __name__ == "__main__":
    rescue(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "art", "out", "windows"))
