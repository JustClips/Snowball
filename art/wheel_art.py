"""Lucky Wheel art for Roll the Snowball, copied from Sweep the World's wheel (Dev 2026-11-20:
"you could've just copied it from sweep the world"), with an icy rim and snow bulbs:
  art/ui/SpinWheel.png     the wheel face, 8 coloured wedges (icons are laid on top in game)
  art/ui/SpinPointer.png   the gold pointer over the top of the wheel
  art/ui/Rays.png          white sun rays (behind prizes and reward cards)

Wedge i covers (i-1)*45 .. i*45 degrees clockwise from 12 o'clock, the same order as
Config/Rewards.Wheel.Segments. Keep WEDGES in step with the segment colours there.

  python3 art/wheel_art.py
Then upload: python3 tools/upload_images.py
"""
import math
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
LINE = (21, 21, 28, 255)
WHITE = (255, 255, 255, 255)
GOLD = (255, 194, 46, 255)
GOLD_D = (214, 150, 20, 255)
WOOD = (88, 170, 240, 255)     # icy blue rim
WOOD_D = (40, 104, 190, 255)

# Same order as Rewards.Wheel.Segments.
WEDGES = ["#5CD65C", "#4CA8FF", "#9B6BFF", "#FF9A3C", "#FFC22E", "#7FD3FF", "#FF7EB6", "#FF4B55"]


def rgb(h, a=255):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


def darker(c, k=0.82):
    return (int(c[0] * k), int(c[1] * k), int(c[2] * k), c[3])


def lighter(c, k=0.35):
    return tuple(int(v + (255 - v) * k) for v in c[:3]) + (c[3],)


def circle(d, cx, cy, r, fill):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)


def wheel(size, wedges, rim=True, bulbs=16, hub=0.13):
    S = 4
    n = size * S
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = n / 2
    outer = n / 2 - 2 * S
    line = n * 0.028
    circle(d, c, c, outer, LINE)
    r = outer - line
    if rim:
        circle(d, c, c, r, WOOD)
        circle(d, c, c, r - n * 0.012, lighter(WOOD, 0.15))
        band = n * 0.055
        for k in range(bulbs):
            a = math.radians(k * 360 / bulbs + 360 / bulbs / 2 - 90)
            bx, by = c + math.cos(a) * (r - band / 2), c + math.sin(a) * (r - band / 2)
            circle(d, bx, by, band * 0.36, LINE)
            circle(d, bx, by, band * 0.36 - n * 0.006, (225, 248, 255, 255))
            circle(d, bx - band * 0.08, by - band * 0.08, band * 0.12, WHITE)
        r = r - band
        circle(d, c, c, r, LINE)
        r -= line * 0.55
    count = len(wedges)
    step = 360 / count
    box = (c - r, c - r, c + r, c + r)
    for i, col in enumerate(wedges):
        col = rgb(col)
        a0 = -90 + i * step
        d.pieslice(box, a0, a0 + step, fill=col)
        # A darker band near the rim and a lighter one near the middle: a bit of depth.
        inner = r * 0.9
        d.pieslice((c - r, c - r, c + r, c + r), a0, a0 + step, fill=darker(col))
        d.pieslice((c - inner, c - inner, c + inner, c + inner), a0, a0 + step, fill=col)
        mid = r * 0.42
        d.pieslice((c - mid, c - mid, c + mid, c + mid), a0, a0 + step, fill=lighter(col, 0.18))
    # dividers
    for i in range(count):
        a = math.radians(-90 + i * step)
        d.line((c, c, c + math.cos(a) * r, c + math.sin(a) * r), fill=LINE, width=int(line * 0.55))
    # hub
    h = n * hub
    circle(d, c, c, h, LINE)
    circle(d, c, c, h - line * 0.7, GOLD)
    circle(d, c, c, (h - line * 0.7) * 0.72, GOLD_D)
    circle(d, c, c, (h - line * 0.7) * 0.5, GOLD)
    circle(d, c - h * 0.25, c - h * 0.25, h * 0.16, lighter(GOLD, 0.7))
    return img.resize((size, size), Image.LANCZOS)


def pointer(size):
    S = 4
    n = size * S
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    w = n * 0.07
    tip = (n / 2, n * 0.94)
    top = n * 0.1
    left, right = n * 0.16, n * 0.84
    # Round knob on top + a triangle pointing down (the tip touches the wheel).
    def shape(grow, fill):
        d.polygon([(left - grow, top + n * 0.22 - grow * 0.3), (right + grow, top + n * 0.22 - grow * 0.3),
                   (tip[0], tip[1] + grow * 1.3)], fill=fill)
        circle(d, n / 2, top + n * 0.24, n * 0.23 + grow, fill)
    shape(w, LINE)
    shape(0, GOLD)
    # shade on the right half, highlight dot
    d.polygon([(n / 2, top + n * 0.24), (right, top + n * 0.22), (tip[0], tip[1])], fill=GOLD_D)
    circle(d, n / 2, top + n * 0.24, n * 0.12, LINE)
    circle(d, n / 2, top + n * 0.24, n * 0.12 - w * 0.5, (255, 75, 85, 255))
    circle(d, n / 2 - n * 0.1, top + n * 0.13, n * 0.045, WHITE)
    return img.resize((size, size), Image.LANCZOS)


def icon(size=512):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    w = wheel(int(size * 0.86), WEDGES, rim=True, bulbs=8, hub=0.16)
    img.alpha_composite(w, ((size - w.width) // 2, size - w.height - 4))
    p = pointer(int(size * 0.34))
    img.alpha_composite(p, ((size - p.width) // 2, 0))
    return img


def rays(size=512, count=16):
    import numpy as np
    n = size * 2
    y, x = np.mgrid[0:n, 0:n] - (n - 1) / 2
    ang = np.arctan2(y, x)
    rad = np.hypot(x, y) / (n / 2)
    wedge = (np.cos(ang * count) > 0.35).astype(float)
    fade = np.clip(1 - rad, 0, 1) ** 0.8
    alpha = (wedge * fade * 255).astype(np.uint8)
    img = Image.new("RGBA", (n, n), WHITE)
    img.putalpha(Image.fromarray(alpha))
    return img.resize((size, size), Image.LANCZOS)


def main():
    out_ui = os.path.join(HERE, "ui")
    os.makedirs(out_ui, exist_ok=True)
    wheel(1024, WEDGES).save(os.path.join(out_ui, "SpinWheel.png"))
    pointer(256).save(os.path.join(out_ui, "SpinPointer.png"))
    rays().save(os.path.join(out_ui, "Rays.png"))
    print("wheel art written")


if __name__ == "__main__":
    main()
