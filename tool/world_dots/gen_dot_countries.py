#!/usr/bin/env python3
"""穿云 1.20.0（首页连接卡地图）：给 assets/map/world_dots.bin 的每个陆地点阵点标上所属国家（ISO 3166-1 alpha-2），
生成 lib/features/muse/home/route_map/route_countries.dart（国家代码 → 点阵格序号 row*W+col）。

数据来源：Natural Earth 1:110m Admin 0 – Countries（ne_110m_admin_0_countries），公有领域（Public Domain），
https://www.naturalearthdata.com/about/terms-of-use/ ；GeoJSON 取自
https://github.com/nvkelso/natural-earth-vector/blob/master/geojson/ne_110m_admin_0_countries.geojson 。
源数据不进仓库，运行时下载（或 --src 指定本地文件）。国家代码用 ISO_A2_EH（法国、挪威等 ISO_A2 为 -99 的也有值）。
做法：按与 gen_world_dots.py 相同的网格（1.5°，北 84° 到南 -60°）以 SS 倍超采样栅格化各国多边形，
每个陆地格取格内占比最多的国家；格内一个都没落上（海岸线精度差异）时，取 3×3 邻格里最多的国家；仍没有则不归属。
依赖：Pillow。用法：python3 tool/world_dots/gen_dot_countries.py [--src ...]
"""
import argparse, json, struct, urllib.request
from collections import Counter
from PIL import Image, ImageDraw

URL = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_110m_admin_0_countries.geojson"
SS = 8


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src")
    ap.add_argument("--dots", default="assets/map/world_dots.bin")
    ap.add_argument("--out", default="lib/features/muse/home/route_map/route_countries.dart")
    a = ap.parse_args()
    data = json.load(open(a.src)) if a.src else json.load(urllib.request.urlopen(URL, timeout=60))
    b = open(a.dots, "rb").read()
    assert b[:4] == b"CYWD"
    _, w, h, step10, north, south = struct.unpack("<BHHBbb", b[4:12])
    bits = b[12:]
    land = lambda r, c: (bits[(r * w + c) >> 3] >> ((r * w + c) & 7)) & 1
    W, H = w * SS, h * SS
    img = Image.new("I", (W, H), 0)
    d = ImageDraw.Draw(img)
    codes = [None]

    def px(lon, lat):
        return ((lon + 180) / 360 * W, (north - lat) / (north - south) * H)

    for f in data["features"]:
        p = f["properties"]
        iso = p.get("ISO_A2_EH") or p.get("ISO_A2")
        if not iso or iso == "-99" or iso == "AQ":
            continue
        codes.append(iso)
        idx = len(codes) - 1
        g = f["geometry"]
        polys = g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]
        for poly in polys:
            for i, ring in enumerate(poly):
                d.polygon([px(x, y) for x, y in ring], fill=0 if i else idx)
    pix = img.load()

    def cell_votes(r, c):
        cnt = Counter()
        for y in range(r * SS, r * SS + SS):
            for x in range(c * SS, c * SS + SS):
                v = pix[x, y]
                if v:
                    cnt[v] += 1
        return cnt

    out = {}
    miss = 0
    for r in range(h):
        for c in range(w):
            if not land(r, c):
                continue
            cnt = cell_votes(r, c)
            if not cnt:
                for dr in (-1, 0, 1):
                    for dc in (-1, 0, 1):
                        rr, cc = r + dr, (c + dc) % w
                        if 0 <= rr < h:
                            cnt.update(cell_votes(rr, cc))
            if not cnt:
                miss += 1
                continue
            out.setdefault(codes[cnt.most_common(1)[0][0]], []).append(r * w + c)
    lines = [
        "// 穿云 1.20.0 首页连接卡地图：点阵底图每个陆地点所属国家（已连接时高亮节点所在国家）。由 tool/world_dots/gen_dot_countries.py 生成，勿手改。",
        "// 数据：Natural Earth 1:110m Admin 0 – Countries，公有领域（Public Domain）。",
        "// Part of 穿云 (GPLv3).",
        "",
        f"/// 点阵网格宽 {w}、高 {h}；值为格序号 row * {w} + col。",
        "const museDotCountryCells = <String, List<int>>{",
    ]
    for k in sorted(out):
        lines.append(f"  '{k}': [{', '.join(map(str, out[k]))}],")
    lines.append("};")
    open(a.out, "w").write("\n".join(lines) + "\n")
    print(f"{a.out}: {len(out)} countries, {sum(map(len, out.values()))} dots, {miss} unassigned; US={len(out.get('US', []))} JP={len(out.get('JP', []))} DE={len(out.get('DE', []))} CN={len(out.get('CN', []))}")


if __name__ == "__main__":
    main()
