#!/usr/bin/env python3
"""穿云 e2e: are the status bar icons visible on every screenshot?

For each PNG: take the status bar strip (top 24 dp), find the background colour (the most common
one) and the pixels that differ from it (clock, signal, battery). The icons are visible when
enough pixels contrast clearly with the background. Writes a table and exits 1 if any fails.
usage: check_status_bar.py <dir> <density dpi>
"""
import json
import sys
from collections import Counter
from pathlib import Path

from PIL import Image


def lum(c):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = c[:3]
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def check(path, density):
    img = Image.open(path).convert("RGB")
    w, h = img.size
    bar = int(24 * density / 160)
    strip = img.crop((0, 2, w, bar - 2))
    px = list(strip.getdata())
    bg = Counter(px).most_common(1)[0][0]
    strong = sum(1 for p in px if contrast(p, bg) >= 3.0)
    ratio = strong / len(px)
    # a clock + battery + signal on a 1080 px wide bar is well above 0.4 % of the strip
    ok = ratio >= 0.004
    return {"file": path.name, "bg": "#%02x%02x%02x" % bg, "contrastPixels": round(ratio * 100, 2), "ok": ok}


def main():
    d = Path(sys.argv[1])
    density = int(sys.argv[2]) if len(sys.argv) > 2 else 420
    rows = [check(p, density) for p in sorted(d.glob("*.png"))]
    for r in rows:
        print(("OK  " if r["ok"] else "FAIL"), r["file"], "bg", r["bg"], "icon px %", r["contrastPixels"])
    (d / "status_bar_check.json").write_text(json.dumps(rows, indent=2))
    bad = [r for r in rows if not r["ok"]]
    if not rows:
        print("no screenshots")
        sys.exit(1)
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
