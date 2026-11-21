"""앱 아이콘(핑: 말풍선 + 반짝이) 1024px PNG 생성.

python tools/make-icon.py  →  Dayline/Assets.xcassets/AppIcon.appiconset/icon-{light,dark}.png
도형 좌표는 120x120 디자인 기준.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent.parent / "Dayline/Assets.xcassets/AppIcon.appiconset"
SIZE = 1024
SS = 4  # 슈퍼샘플링 배율
K = SIZE * SS / 120


def cubic(p0, p1, p2, p3, n=48):
    t = np.linspace(0, 1, n)[:, None]
    p0, p1, p2, p3 = map(np.array, (p0, p1, p2, p3))
    return list(map(tuple, (1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * p1 + 3 * (1 - t) * t ** 2 * p2 + t ** 3 * p3))


def path(start, segs, scale=1.0, center=(60, 57)):
    pts = [start]
    for s in segs:
        pts += cubic(pts[-1], *s)[1:] if len(s) == 3 else [s[0]]
    cx, cy = center
    return [((cx + (x - cx) * scale) * K, (cy + (y - cy) * scale) * K) for x, y in pts]


BUBBLE = path((60, 24), [
    ((84, 24), (100, 39), (100, 57)),
    ((100, 75), (84, 90), (60, 90)),
    ((55, 90), (50, 89), (46, 88)),
    ((30, 98),),
    ((34, 81),),
    ((25, 75), (20, 66), (20, 57)),
    ((20, 39), (36, 24), (60, 24)),
])

SPARKLE = path((60, 37), [
    ((62, 50), (66, 54), (79, 57)),
    ((66, 60), (62, 64), (60, 77)),
    ((58, 64), (54, 60), (41, 57)),
    ((54, 54), (58, 50), (60, 37)),
], scale=1.12)


def gradient(c1, c2, diagonal=True):
    n = SIZE * SS
    y, x = np.mgrid[0:n, 0:n] / (n - 1)
    t = (x + y) / 2 if diagonal else y
    a, b = np.array(c1, float), np.array(c2, float)
    rgb = a + (b - a) * t[..., None]
    return Image.fromarray(rgb.astype(np.uint8), "RGB")


def hexrgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def fill(base, pts, top, bottom, diagonal=False):
    mask = Image.new("L", base.size, 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    base.paste(gradient(hexrgb(top), hexrgb(bottom), diagonal), (0, 0), mask)


def make(name, bg, bubble, sparkle):
    img = gradient(hexrgb(bg[0]), hexrgb(bg[1]))
    fill(img, BUBBLE, *bubble)
    fill(img, SPARKLE, *sparkle)
    img.resize((SIZE, SIZE), Image.LANCZOS).save(OUT / name)
    print("wrote", OUT / name)


make("icon-light.png", bg=("9A80F4", "4B2FB3"), bubble=("FFFFFF", "EEE8FF"), sparkle=("B19BF7", "5E3FD2"))
make("icon-dark.png", bg=("2C2546", "100D18"), bubble=("C2B2FA", "8A6EEA"), sparkle=("2A2247", "15111F"))
