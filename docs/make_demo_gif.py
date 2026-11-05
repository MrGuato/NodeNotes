"""Draws docs/demo.gif, the animated tour at the top of the README.

Everything is drawn from shapes in the style of the logo, so it is easy to
change and rebuild. It needs Pillow:

    python docs/make_demo_gif.py
"""
import math
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "demo.gif")
LOGO = os.path.join(HERE, "logo.png")

W, H = 800, 450
S = 2           # draw at twice the size, then shrink, for smooth edges
FRAME_MS = 66   # about 15 frames a second

BG_TOP, BG_BOTTOM = (13, 50, 54), (22, 72, 75)
CONTOUR = (34, 84, 87)
LAKE, LAKE_EDGE = (32, 96, 110), (58, 128, 138)
PATH = (92, 140, 120)
GOLD, GOLD_DARK, GOLD_LIGHT = (246, 196, 66), (110, 74, 16), (255, 230, 140)
BLUE, BLUE_DARK = (98, 168, 245), (28, 66, 128)
CREAM, INK = (250, 243, 222), (34, 44, 46)
WHITE, MUTED = (240, 240, 232), (150, 182, 178)
CARD, CARD_EDGE = (16, 22, 26), (120, 120, 120)

# Where each kind of node lands on the map, and what the side panel says.
PINS = [
    ("herb", (150, 215), "Herbs", "Every herb you pick, with what it gave you and when."),
    ("ore", (310, 160), "Ore", "Each vein keeps its last yield and an all time total."),
    ("fish", (232, 330), "Fishing spots", "One stretch of shore, one spot. Every catch counted."),
    ("chest", (430, 285), "Chests", "Named after the chest you opened. Quest objects stay out."),
    ("rare", (470, 150), "Rares", "Seen when you spot one, a kill when you loot it."),
    ("find", (380, 390), "Special finds", "A blue or better from any mob gets its own pin."),
    ("friend", (85, 365), "Friends' nodes", "Turn on sharing and your group's nodes show up too."),
]
NOTE = "behind the troll ruins, watch the patrol"


def font(size, weight="regular"):
    names = {"regular": "segoeui.ttf", "semibold": "seguisb.ttf", "bold": "segoeuib.ttf"}
    for path in (os.path.join(os.environ.get("WINDIR", "C:/Windows"), "Fonts", names[weight]),
                 "DejaVuSans-Bold.ttf" if weight != "regular" else "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(path, size * S)
        except OSError:
            continue
    return ImageFont.load_default()


F_TITLE, F_SUB = font(26, "bold"), font(14)
F_ITEM, F_DESC = font(16, "semibold"), font(14)
F_CARD_TITLE, F_CARD = font(16, "bold"), font(13)


def s(*values):
    return [v * S for v in values]


def blob(cx, cy, r, k, wobble=0.14, steps=90):
    pts = []
    for i in range(steps):
        a = 2 * math.pi * i / steps
        rr = r * (1 + wobble * math.sin(3 * a + k) + wobble * 0.5 * math.sin(5 * a + 2 * k))
        pts.append(((cx + rr * math.cos(a)) * S, (cy + rr * 0.72 * math.sin(a)) * S))
    return pts


def background():
    img = Image.new("RGB", (W * S, H * S))
    d = ImageDraw.Draw(img)
    for y in range(H * S):
        t = y / (H * S)
        d.line([(0, y), (W * S, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(BG_TOP, BG_BOTTOM)))
    # Contour lines, like the logo.
    for cx, cy, base, k in ((170, 200, 40, 0.3), (420, 210, 36, 1.7), (300, 420, 50, 2.9), (650, 120, 30, 4.1)):
        for ring in range(6):
            d.line(blob(cx, cy, base + ring * 28, k + ring * 0.25) + blob(cx, cy, base + ring * 28, k + ring * 0.25)[:1],
                   fill=CONTOUR, width=2 * S // 2 + 1)
    # A lake by the fishing spot and a road between the nodes.
    d.polygon(blob(215, 360, 46, 1.1, 0.1), fill=LAKE, outline=LAKE_EDGE)
    road = [(40, 250), (120, 240), (200, 262), (290, 230), (360, 250), (440, 236), (530, 250)]
    for i in range(len(road) - 1):
        (x1, y1), (x2, y2) = road[i], road[i + 1]
        n = 6
        for j in range(n):
            if j % 2 == 0:
                a, b = j / n, (j + 1) / n
                d.line(s(x1 + (x2 - x1) * a, y1 + (y2 - y1) * a, x1 + (x2 - x1) * b, y1 + (y2 - y1) * b),
                       fill=PATH, width=3 * S)
    # Divider between the map and the side panel.
    d.line(s(556, 72, 556, 430), fill=CONTOUR, width=S)
    # Title with the logo.
    logo = Image.open(LOGO).convert("RGBA").resize((44 * S, 44 * S), Image.LANCZOS)
    img.paste(logo, (18 * S, 12 * S), logo)
    d.text(s(70, 10), "NodeNotes", font=F_TITLE, fill=GOLD)
    d.text(s(72, 44), "Remembers every node you've used, and what it gave you", font=F_SUB, fill=MUTED)
    return img


def icon(d, kind, cx, cy, k=1.0):
    def p(x, y):
        return ((cx + x * k) * S, (cy + y * k) * S)

    def box(x1, y1, x2, y2):
        return [p(x1, y1), p(x2, y2)]

    if kind == "herb":
        leaf = []
        for i in range(24):
            t = math.pi * i / 23
            leaf.append((math.cos(t) * 9, -math.sin(t) * 5))
        for i in range(24):
            t = math.pi * i / 23
            leaf.append((-math.cos(t) * 9, math.sin(t) * 5))
        a = math.radians(-35)
        d.polygon([p(x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a)) for x, y in leaf],
                  fill=(70, 158, 82), outline=(30, 90, 40))
        d.line([p(-7 * math.cos(a), -7 * math.sin(a)), p(7 * math.cos(a), 7 * math.sin(a))], fill=(190, 235, 170), width=S)
    elif kind == "ore":
        d.polygon([p(0, -9), p(8, 0), p(0, 9), p(-8, 0)], fill=(214, 118, 44), outline=(110, 50, 12))
        d.polygon([p(0, -9), p(4, -1), p(-3, -1)], fill=(246, 170, 100))
    elif kind == "fish":
        d.polygon([p(4, 0), p(10, -6), p(10, 6)], fill=(50, 120, 190))
        d.ellipse(box(-10, -5, 6, 5), fill=(70, 150, 220), outline=(30, 80, 140))
        d.ellipse(box(-7, -2, -5, 0), fill=INK)
    elif kind == "chest":
        d.rectangle(box(-9, -3, 9, 8), fill=(140, 88, 42), outline=(70, 40, 14))
        d.rounded_rectangle(box(-9, -9, 9, -2), radius=3 * S, fill=(110, 66, 30), outline=(70, 40, 14))
        d.rectangle(box(-2, -9, 2, 8), fill=GOLD)
        d.rectangle(box(-2.5, -2, 2.5, 2), fill=GOLD_DARK)
    elif kind == "rare":
        d.ellipse(box(-8, -10, 8, 4), fill=WHITE, outline=INK)
        d.rectangle(box(-5, 1, 5, 8), fill=WHITE, outline=INK)
        d.ellipse(box(-5.5, -5, -1, -0.5), fill=INK)
        d.ellipse(box(1, -5, 5.5, -0.5), fill=INK)
        for x in (-2.5, 0, 2.5):
            d.line([p(x, 4), p(x, 8)], fill=INK, width=S)
    elif kind == "find":
        d.polygon([p(-6, -8), p(6, -8), p(9, -3), p(0, 9), p(-9, -3)], fill=(92, 150, 255), outline=(30, 60, 140))
        d.line([p(-9, -3), p(9, -3)], fill=(190, 215, 255), width=S)
        d.line([p(-2, -8), p(0, 9)], fill=(160, 195, 255), width=S)
    elif kind == "friend":
        d.ellipse(box(-4, -9, 4, -1), fill=BLUE_DARK)
        d.chord(box(-8, 0, 8, 16), 180, 360, fill=BLUE_DARK)


def pin(layer, kind, x, y, shadow=1.0, noted=False):
    """A pin whose tip touches (x, y). Draws on an RGBA layer."""
    d = ImageDraw.Draw(layer)
    friend = kind == "friend"
    body, edge = (BLUE, BLUE_DARK) if friend else (GOLD, GOLD_DARK)
    if shadow > 0:
        w = 12 * shadow
        d.ellipse(s(x - w, y - 3 * shadow, x + w, y + 3 * shadow), fill=(0, 0, 0, int(110 * shadow)))
    hx, hy = x, y - 30
    if kind == "find":
        d.ellipse(s(hx - 23, hy - 23, hx + 23, hy + 23), outline=(70, 140, 255, 255), width=3 * S)
    d.ellipse(s(hx - 19.5, hy - 19.5, hx + 19.5, hy + 19.5), fill=edge)
    d.polygon([tuple(s(hx - 17, hy + 9)), tuple(s(hx + 17, hy + 9)), tuple(s(x, y + 2.5))], fill=edge)
    d.ellipse(s(hx - 17, hy - 17, hx + 17, hy + 17), fill=body)
    d.polygon([tuple(s(hx - 14.6, hy + 8.5)), tuple(s(hx + 14.6, hy + 8.5)), tuple(s(x, y - 0.8))], fill=body)
    d.chord(s(hx - 13, hy - 15, hx + 5, hy - 3), 180, 300, fill=GOLD_LIGHT if not friend else (170, 210, 255))
    d.ellipse(s(hx - 12, hy - 12, hx + 12, hy + 12), fill=CREAM)
    icon(d, kind, hx, hy, 0.95)
    if friend:
        d.rectangle(s(hx - 19, hy + 7, hx - 10, hy + 16), fill=(77, 166, 255), outline=BLUE_DARK)
    if noted:
        # The gold corner the addon puts on a node with a note.
        d.rounded_rectangle(s(hx + 9, hy - 22, hx + 21, hy - 8), radius=2 * S, fill=CREAM, outline=GOLD_DARK, width=S)
        for i in range(3):
            d.line(s(hx + 11.5, hy - 19 + i * 3.5, hx + 18.5, hy - 19 + i * 3.5), fill=GOLD_DARK, width=S)


def ease_back(t):
    c = 1.70158
    t -= 1
    return 1 + (c + 1) * t ** 3 + c * t ** 2


def wrap(text, fnt, width, d):
    words, lines, line = text.split(), [], ""
    for w in words:
        trial = (line + " " + w).strip()
        if d.textlength(trial, font=fnt) <= width * S:
            line = trial
        else:
            lines.append(line)
            line = w
    lines.append(line)
    return lines


def side_panel(d, shown, current):
    x0, y0 = 572, 84
    for i, (kind, _, label, _) in enumerate(PINS):
        y = y0 + i * 34
        on = i < shown
        ring = (BLUE if kind == "friend" else GOLD) if on else CONTOUR
        d.ellipse(s(x0, y, x0 + 24, y + 24), fill=CREAM if on else BG_TOP, outline=ring, width=2 * S)
        if on:
            icon(d, kind, x0 + 12, y + 12, 0.62)
        d.text(s(x0 + 34, y + 1), label, font=F_ITEM, fill=(WHITE if i == current else MUTED) if on else CONTOUR)
    if current is not None:
        lines = wrap(PINS[current][3], F_DESC, 196, d)
        for j, line in enumerate(lines):
            d.text(s(x0, 334 + j * 20), line, font=F_DESC, fill=CREAM)


def card(d, x, y, typed, alpha_step):
    if alpha_step <= 0:
        return
    w, h = 300, 150
    lift = (1 - alpha_step) * 8
    y = y + lift
    d.rounded_rectangle(s(x, y, x + w, y + h), radius=6 * S, fill=CARD, outline=CARD_EDGE, width=S)
    d.text(s(x + 12, y + 8), "Kingsblood", font=F_CARD_TITLE, fill=GOLD)
    lines = ["Stranglethorn Vale  45.1, 60.3", "Gathered 3 times, last 2h ago",
             "Last yield: 2x Kingsblood", "All time: 5x Kingsblood, 1x Wild Steelbloom"]
    for i, line in enumerate(lines):
        d.text(s(x + 12, y + 34 + i * 18), line, font=F_CARD, fill=WHITE)
    if typed:
        cursor = "|" if len(typed) < len(NOTE) else ""
        d.text(s(x + 12, y + 112), typed + cursor, font=F_CARD, fill=GOLD)
    else:
        d.text(s(x + 12, y + 112), "Click to write a note", font=F_CARD, fill=(150, 150, 150))


def cursor_arrow(d, x, y):
    pts = [(0, 0), (0, 17), (4.5, 13), (8, 20), (11, 18.5), (7.5, 12), (13, 12)]
    d.polygon([tuple(s(x + a, y + b)) for a, b in pts], fill=WHITE, outline=INK)


def render(bg, landed, dropping, current, card_step=0.0, typed="", mouse=None, noted=False):
    frame = bg.copy().convert("RGBA")
    layer = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    for i in range(landed):
        kind, (x, y), _, _ = PINS[i]
        pin(layer, kind, x, y, noted=noted and kind == "herb")
    if dropping is not None:
        i, t = dropping
        kind, (x, y), _, _ = PINS[i]
        e = ease_back(t)
        pin(layer, kind, x, y - 140 * (1 - e), shadow=max(0.15, min(1, t * 1.2)))
    frame = Image.alpha_composite(frame, layer)
    d = ImageDraw.Draw(frame)
    side_panel(d, landed + (1 if dropping else 0), current)
    hx, hy = PINS[0][1]
    card(d, hx + 30, hy - 70, typed, card_step)
    if mouse:
        cursor_arrow(d, *mouse)
    return frame.convert("RGB").resize((W, H), Image.LANCZOS)


def main():
    bg = background()
    frames, durations = [], []

    def add(img, ms=FRAME_MS):
        frames.append(img)
        durations.append(ms)

    add(render(bg, 0, None, None), 500)
    drop = 10
    for i in range(len(PINS)):
        for f in range(drop):
            add(render(bg, i, (i, (f + 1) / drop), i))
        add(render(bg, i + 1, None, i), 650)

    # Point at the herb, open its card and write a note.
    start, (hx, hy) = (520.0, 420.0), PINS[0][1]
    goal = (hx + 2, hy - 30)
    for f in range(14):
        t = (f + 1) / 14
        t = t * t * (3 - 2 * t)
        mouse = (start[0] + (goal[0] - start[0]) * t, start[1] + (goal[1] - start[1]) * t)
        add(render(bg, len(PINS), None, None, mouse=mouse))
    for f in range(6):
        add(render(bg, len(PINS), None, None, card_step=(f + 1) / 6, mouse=goal))
    add(render(bg, len(PINS), None, None, card_step=1, mouse=goal), 500)
    for n in range(2, len(NOTE) + 2, 2):
        add(render(bg, len(PINS), None, None, card_step=1, typed=NOTE[:n], mouse=goal))
    add(render(bg, len(PINS), None, None, card_step=1, typed=NOTE, mouse=goal, noted=True), 2600)
    add(render(bg, len(PINS), None, None, noted=True), 1200)

    palette = frames[-2].quantize(colors=128, method=Image.Quantize.MEDIANCUT)
    paletted = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in frames]
    paletted[0].save(OUT, save_all=True, append_images=paletted[1:], duration=durations, loop=0, optimize=True)
    print("wrote", OUT, len(frames), "frames", os.path.getsize(OUT) // 1024, "KB")


if __name__ == "__main__":
    main()
