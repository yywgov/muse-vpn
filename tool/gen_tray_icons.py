# 穿云 1.21.0 I6：托盘图标从同一个字形（tool/gen_icons.py 的峰 + 云）生成，16–24px 只画字形 + 状态角标，
# 不再塞整块蓝底：
#   tray_icon            未连接（浅色任务栏）：景泰蓝字形
#   tray_icon_dark       未连接（深色任务栏）：浅色字形
#   tray_icon_connected  已连接：字形 + 绿色圆形角标
#   tray_icon_connecting 连接中：字形 + 琥珀色半圆角标
# 用法：python3 tool/gen_tray_icons.py（仓库根目录运行，需要 Pillow）。png 128px，ico 含 16/24/32/48/64/128。
from PIL import Image, ImageDraw
import os

src = open(os.path.join(os.path.dirname(__file__), 'gen_icons.py'), encoding='utf-8').read()
exec(src.split('\nres = ')[0].split('\ndef gradient')[0])  # PEAK / CLOUD / bez / glyph

SIZE = 128
S = 8  # supersampling
BRAND = (0x27, 0x75, 0xB6, 255)  # 景泰蓝
LIGHT = (0xE8, 0xEC, 0xF5, 255)  # 深色任务栏上的浅色字形
GREEN = (0x0E, 0xB8, 0x3A, 255)  # 葱青（灯色）
AMBER = (0xF0, 0x9A, 0x1A, 255)  # 琥珀




def thick_glyph(color):
    # 与 gen_icons.glyph 同路径，笔画 8（设计框单位）
    big = SIZE * S
    img = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    k = big / 84  # 字形宽约 78 + 笔画，留 3 单位边
    ox = (big - 108 * k) / 2
    oy = (big - 108 * k) / 2 - 4 * k

    def tr(p):
        return (p[0] * k + ox, (p[1] + 7) * k + oy)
    w = round(8 * k)
    for pts in (PEAK, cloud_pts()):
        P = [tr(p) for p in pts]
        d.line(P, fill=color, width=w, joint='curve')
        r = w / 2
        for q in (P[0], P[-1]):
            d.ellipse([q[0] - r, q[1] - r, q[0] + r, q[1] + r], fill=color)
    return img


def badge(img, color, half=False):
    big = img.size[0]
    r = big * 0.2
    cx, cy = big - r - big * 0.01, big - r - big * 0.01
    gap = big * 0.05
    # 镂空一圈，角标和字形之间留缝
    hole = Image.new('L', img.size, 0)
    ImageDraw.Draw(hole).ellipse([cx - r - gap, cy - r - gap, cx + r + gap, cy + r + gap], fill=255)
    clear = Image.new('RGBA', img.size, (0, 0, 0, 0))
    img = Image.composite(clear, img, hole)
    d = ImageDraw.Draw(img)
    if half:
        ring = big * 0.06
        d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=color, width=round(ring))
        d.pieslice([cx - r, cy - r, cx + r, cy + r], 90, 270, fill=color)
    else:
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)
    return img


def save(img, name):
    out = img.resize((SIZE, SIZE), Image.LANCZOS)
    out.save(f'assets/images/{name}.png', optimize=True)
    out.save(f'assets/images/{name}.ico', sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128)])


save(thick_glyph(BRAND), 'tray_icon')
save(thick_glyph(LIGHT), 'tray_icon_dark')
save(badge(thick_glyph(BRAND), GREEN), 'tray_icon_connected')
save(badge(thick_glyph(BRAND), AMBER, half=True), 'tray_icon_connecting')
print('tray ok')
