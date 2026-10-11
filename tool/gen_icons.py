# 穿云: renders launcher/splash PNGs from the icon design (design/chuanyun/app_icon.svg).
# Usage: python3 tool/gen_icons.py  (run from repo root; needs Pillow)
from PIL import Image, ImageDraw
import os

C0 = (0x3B, 0x8B, 0xFF); C1 = (0x1A, 0x4F, 0xD6)
PEAK = [(33, 66), (54, 28), (75, 66)]
CLOUD = [(18, 74), [(22, 66), (30, 64), (36, 67)], [(40, 60), (50, 58), (56, 64)],
         [(62, 58), (74, 60), (76, 67)], [(82, 64), (90, 68), (90, 74)]]

def bez(p0, c1, c2, p3, n=24):
    out = []
    for i in range(1, n + 1):
        t = i / n; u = 1 - t
        out.append((u**3*p0[0]+3*u*u*t*c1[0]+3*u*t*t*c2[0]+t**3*p3[0],
                    u**3*p0[1]+3*u*u*t*c1[1]+3*u*t*t*c2[1]+t**3*p3[1]))
    return out

def cloud_pts():
    pts = [CLOUD[0]]; cur = CLOUD[0]
    for seg in CLOUD[1:]:
        pts += bez(cur, seg[0], seg[1], seg[2]); cur = seg[2]
    return pts

def glyph(draw, s, scale=1.0, dy=7, ox=0, oy=0, color=(255, 255, 255, 255)):
    # coordinates in the 108 design box, scaled about the centre
    def tr(p):
        x, y = p[0], p[1] + dy
        x = 54 + (x - 54) * scale; y = 54 + (y - 54) * scale
        return (x * s + ox, y * s + oy)
    w = max(1, round(6 * scale * s))
    for pts in (PEAK, cloud_pts()):
        P = [tr(p) for p in pts]
        draw.line(P, fill=color, width=w, joint='curve')
        r = w / 2
        for q in (P[0], P[-1]):
            draw.ellipse([q[0]-r, q[1]-r, q[0]+r, q[1]+r], fill=color)

def gradient(size):
    img = Image.new('RGBA', (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            px[x, y] = tuple(round(C0[i] + (C1[i]-C0[i]) * t) for i in range(3)) + (255,)
    return img

def icon(size, shape):
    S = 4; big = size * S
    img = gradient(big)
    d = ImageDraw.Draw(img)
    # legacy icons: glyph a bit smaller, centred (glyph box y 35..84)
    glyph(d, big / 108, scale=0.78, dy=3)
    mask = Image.new('L', (big, big), 0)
    md = ImageDraw.Draw(mask)
    if shape == 'round':
        md.ellipse([0, 0, big-1, big-1], fill=255)
    else:
        md.rounded_rectangle([0, 0, big-1, big-1], radius=big*0.22, fill=255)
    out = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    out.paste(img, (0, 0), mask)
    return out.resize((size, size), Image.LANCZOS)

res = 'android/app/src/main/res'
for name, px in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
    icon(px, 'square').save(f'{res}/mipmap-{name}/ic_launcher.webp', 'WEBP', lossless=True)
    icon(px, 'round').save(f'{res}/mipmap-{name}/ic_launcher_round.webp', 'WEBP', lossless=True)
# pre-Android-12 splash: the round icon, centred by the layer-list
icon(288, 'round').save(f'{res}/drawable-xxxhdpi/splash.png')
icon(512, 'square').save('android/app/src/main/ic_launcher-playstore.png')
print('ok')

# TV banner (legacy, xhdpi 320x180): light background with the blue glyph
S = 4
b = Image.new('RGBA', (320*S, 180*S), (0xF0, 0xF3, 0xFA, 255))
glyph(ImageDraw.Draw(b), 1.3*S, scale=1.0, dy=7, ox=(160-54*1.3)*S, oy=(90-58*1.3)*S, color=(0x2F, 0x6B, 0xFF, 255))
b.resize((320, 180), Image.LANCZOS).save(f'{res}/mipmap-xhdpi/ic_banner.png')
print('banner ok')
