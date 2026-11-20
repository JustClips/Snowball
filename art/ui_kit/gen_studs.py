"""Draws the kit's stud overlay (art/ui/Ui_Studs.png): a tileable 128 px square with 2x2
toy-brick studs seen from above. It is a see-through overlay (white highlight on the top
and left of each stud, dark shade on the bottom and right), so it lays over any fill colour
or gradient without tinting. Ui.studs() tiles it on panels, headers and buttons.

  python3 art/ui_kit/gen_studs.py
"""
import os
from PIL import Image, ImageDraw, ImageFilter

S = 4  # supersample
N = 128
OUT = os.path.join(os.path.dirname(__file__), "..", "ui", "Ui_Studs.png")


def stud_layer(offset, color, alpha):
    im = Image.new("RGBA", (N * S, N * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cell = N // 2
    for cx in range(2):
        for cy in range(2):
            x0 = (cx * cell + 13) * S + offset[0] * S
            y0 = (cy * cell + 13) * S + offset[1] * S
            sz = (cell - 26) * S
            d.rounded_rectangle((x0, y0, x0 + sz, y0 + sz), radius=9 * S, fill=color + (alpha,))
    return im


def main():
    light = stud_layer((-2, -2), (255, 255, 255), 120)
    dark = stud_layer((2, 3), (0, 0, 0), 70)
    face = stud_layer((0, 0), (255, 255, 255), 255)
    # keep only the rims: subtract the face from the light/dark copies
    out = Image.new("RGBA", (N * S, N * S), (0, 0, 0, 0))
    out.alpha_composite(dark)
    out.alpha_composite(light)
    fa = face.split()[3]
    rim = Image.new("RGBA", out.size, (0, 0, 0, 0))
    rim.paste(out, mask=fa.point(lambda v: 255 - v))
    # faint face tint so the stud top reads a touch lighter than the base
    top = Image.new("RGBA", out.size, (255, 255, 255, 0))
    top.putalpha(fa.point(lambda v: v * 22 // 255))
    rim.alpha_composite(top)
    rim = rim.filter(ImageFilter.GaussianBlur(S * 0.6)).resize((N, N), Image.LANCZOS)
    rim.save(OUT)
    print("wrote", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
