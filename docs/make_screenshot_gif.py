"""Turns docs/map-note.png into docs/map-note.gif.

The cursor moves onto the pin, the view eases in on the tooltip and note
window, the note types itself, then the view eases back out. Only the real
in-game screenshot is used; the cursor, the pulse and the typing are drawn on
top. It needs Pillow:

    python docs/make_screenshot_gif.py
"""
import os

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "map-note.png")
OUT = os.path.join(HERE, "map-note.gif")

OUT_W = 800
FRAME_MS = 66

PIN = (594, 612)                    # the copper vein pin, in screenshot pixels
NOTE_TEXT = (140, 358, 300, 412)    # the two lines typed in the note box
NOTE_LINES = [(362, 385), (385, 410)]
BOX_COLOR = (13, 12, 11)
ZOOM = (90, 130, 1040, 665)         # the tooltip and the note window
GOLD = (255, 210, 60)


def ease(t):
    return t * t * (3 - 2 * t)


def lerp_box(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(4))


def fit(box, size):
    """Grow a box to the output's aspect ratio, kept inside the image."""
    w, h = size
    x1, y1, x2, y2 = box
    aspect = w / h
    bw, bh = x2 - x1, y2 - y1
    if bw / bh < aspect:
        grow = bh * aspect - bw
        x1, x2 = x1 - grow / 2, x2 + grow / 2
    else:
        grow = bw / aspect - bh
        y1, y2 = y1 - grow / 2, y2 + grow / 2
    dx = max(0, -x1) - max(0, x2 - w)
    dy = max(0, -y1) - max(0, y2 - h)
    return (x1 + dx, y1 + dy, x2 + dx, y2 + dy)


def cursor(d, x, y, k):
    pts = [(0, 0), (0, 17), (4.5, 13), (8, 20), (11, 18.5), (7.5, 12), (13, 12)]
    d.polygon([(x + a * k, y + b * k) for a, b in pts], fill=(245, 245, 240), outline=(20, 20, 20))


def frame(src, view, typed=None, mouse=None, pulse=0.0):
    img = src.copy()
    d = ImageDraw.Draw(img)
    if typed is not None:
        # Hide what is not typed yet, line by line.
        x1, _, x2, _ = NOTE_TEXT
        for i, (top, bottom) in enumerate(NOTE_LINES):
            shown = min(max(typed - i, 0), 1)
            d.rectangle((x1 + (x2 - x1) * shown, top, x2, bottom), fill=BOX_COLOR)
    if pulse > 0:
        r = 16 + 22 * pulse
        d.ellipse((PIN[0] - r, PIN[1] - r, PIN[0] + r, PIN[1] + r), outline=GOLD, width=max(1, int(5 * (1 - pulse))))
    if mouse:
        cursor(d, mouse[0], mouse[1], 1.6)
    out_h = round(OUT_W * src.height / src.width)
    return img.crop(tuple(round(v) for v in view)).resize((OUT_W, out_h), Image.LANCZOS)


def main():
    src = Image.open(SRC).convert("RGB")
    full = (0, 0, src.width, src.height)
    zoom = fit(ZOOM, src.size)
    frames, durations = [], []

    def add(img, ms=FRAME_MS):
        frames.append(img)
        durations.append(ms)

    start, goal = (1400.0, 820.0), (PIN[0] + 4, PIN[1] - 4)
    add(frame(src, full, typed=0, mouse=start), 700)
    for i in range(16):
        t = ease((i + 1) / 16)
        add(frame(src, full, typed=0, mouse=(start[0] + (goal[0] - start[0]) * t, start[1] + (goal[1] - start[1]) * t)))
    for i in range(10):
        add(frame(src, full, typed=0, mouse=goal, pulse=(i + 1) / 10))
    for i in range(12):
        add(frame(src, lerp_box(full, zoom, ease((i + 1) / 12)), typed=0, mouse=goal))
    add(frame(src, zoom, typed=0, mouse=goal), 400)
    steps = 22
    for i in range(steps):
        add(frame(src, zoom, typed=2 * (i + 1) / steps, mouse=goal))
    add(frame(src, zoom, mouse=goal), 2200)
    for i in range(12):
        add(frame(src, lerp_box(zoom, full, ease((i + 1) / 12)), mouse=goal))
    add(frame(src, full, mouse=goal), 1600)

    palette = frames[len(frames) // 2].quantize(colors=128, method=Image.Quantize.MEDIANCUT)
    paletted = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in frames]
    paletted[0].save(OUT, save_all=True, append_images=paletted[1:], duration=durations, loop=0, optimize=True)
    print("wrote", OUT, len(frames), "frames", os.path.getsize(OUT) // 1024, "KB")


if __name__ == "__main__":
    main()
