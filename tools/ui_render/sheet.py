"""Puts PC and phone renders side by side: python3 tools/ui_render/sheet.py out.png a_PC.png a_Phone.png ..."""
import sys
from PIL import Image
out, files = sys.argv[1], sys.argv[2:]
ims = [Image.open(f).convert("RGB") for f in files]
h = 720
ims = [im.resize((int(im.width * h / im.height), h)) for im in ims]
W = Image.new("RGB", (sum(i.width for i in ims) + 10 * (len(ims) - 1), h), (0, 0, 0))
x = 0
for im in ims:
    W.paste(im, (x, 0)); x += im.width + 10
W.save(out)
