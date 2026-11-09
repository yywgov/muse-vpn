#!/usr/bin/env python3
"""穿云 1.19.0 P1：生成首页路由弧线图的点阵世界底图 assets/map/world_dots.bin。

数据来源：Natural Earth 1:110m Land（ne_110m_land），公有领域（Public Domain），
https://www.naturalearthdata.com/about/terms-of-use/ ；GeoJSON 取自
https://github.com/nvkelso/natural-earth-vector/blob/master/geojson/ne_110m_land.geojson 。
源数据不进仓库，运行本脚本时下载（或用 --src 指定本地文件）。

输出格式（小端）：
  4 字节 'CYWD'，1 字节版本(1)，u16 宽 W，u16 高 H，1 字节步长×10（度），
  i8 北界纬度，i8 南界纬度，随后 ceil(W*H/8) 字节位图：行优先，从北到南、从经度 -180 起，
  每格中心落在陆地上则为 1（字节内低位在前）。
用法：python3 tool/world_dots/gen_world_dots.py [--src ne_110m_land.geojson] [--out assets/map/world_dots.bin]
依赖：Pillow。
"""
import argparse, json, struct, urllib.request
from PIL import Image, ImageDraw

URL = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_land.geojson"
STEP = 1.5          # 度
NORTH, SOUTH = 84, -60   # 去掉南极洲
SS = 8              # 每格超采样倍数（栅格化精度）


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src")
    ap.add_argument("--out", default="assets/map/world_dots.bin")
    a = ap.parse_args()
    data = json.load(open(a.src)) if a.src else json.load(urllib.request.urlopen(URL, timeout=60))
    w = int(round(360 / STEP)); h = int(round((NORTH - SOUTH) / STEP))
    W, H = w * SS, h * SS
    img = Image.new("1", (W, H), 0)
    d = ImageDraw.Draw(img)

    def px(lon, lat):
        return ((lon + 180) / 360 * W, (NORTH - lat) / (NORTH - SOUTH) * H)

    for f in data["features"]:
        g = f["geometry"]
        polys = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
        for poly in polys:
            for i, ring in enumerate(poly):
                d.polygon([px(x, y) for x, y in ring], fill=0 if i else 1)
    bits = bytearray((w * h + 7) // 8)
    n = 0
    for r in range(h):
        for c in range(w):
            if img.getpixel((c * SS + SS // 2, r * SS + SS // 2)):
                k = r * w + c
                bits[k >> 3] |= 1 << (k & 7)
                n += 1
    out = b"CYWD" + struct.pack("<BHHBbb", 1, w, h, int(STEP * 10), NORTH, SOUTH) + bytes(bits)
    open(a.out, "wb").write(out)
    print(f"{a.out}: {w}x{h}, {n} land dots, {len(out)} bytes")


if __name__ == "__main__":
    main()
