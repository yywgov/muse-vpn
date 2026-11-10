#!/usr/bin/env python3
"""穿云首页连接卡地图：给 assets/map/world_dots.bin 的每个陆地点阵点标上所属国家（ISO 3166-1 alpha-2），
生成 lib/features/muse/home/route_map/route_countries.dart。

1.20.1 起数据改用 Natural Earth 1:50m Admin 0 – Countries（ne_50m_admin_0_countries），公有领域（Public Domain），
https://www.naturalearthdata.com/about/terms-of-use/ ；GeoJSON 取自
https://github.com/nvkelso/natural-earth-vector/blob/master/geojson/ne_50m_admin_0_countries.geojson 。
源数据不进仓库，运行时下载（或 --src 指定本地文件）。国家代码用 ISO_A2_EH（法国、挪威等 ISO_A2 为 -99 的也有值）。

输出两张表：
- museDotCountryCells：底图网格（1.5°，北 84° 到南 -60°）上每个陆地格取格内占比最多的国家；格内一个都没落上时取
  3×3 邻格里最多的国家。底图格少于 [SMALL] 个的小国（荷兰、瑞士、以色列、卡塔尔……）再补上「格内有任何覆盖」的格
  （不论底图上是不是陆地），按真实轮廓多亮几个点。
- museDotCountryFine：这些小国在 0.5° / 0.25° 细网格上的点（格内有任何覆盖即算；一个都没有时取国家标注点），
  打包成 (纬度×8 + 720) × 4096 + (经度×8 + 1440)，画的时候按当前格距挑看得见的一级。
  细网格只给节点常见地区（[FINE_REGIONS]，与 route_geo.dart 的代表城市表一致）出，表不至于太大。
依赖：Pillow。用法：python3 tool/world_dots/gen_dot_countries.py [--src ...]
"""
import argparse, json, struct, urllib.request
from collections import Counter
from PIL import Image, ImageDraw

URL = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_countries.geojson"
SS = 8
SMALL = 8
FAR = 10.0
FINE = (0.5, 0.25)
FINE_PX = 0.025  # 细网格栅格化分辨率（度 / 像素）
# 有代表城市的地区（route_geo.dart museRegionCities）；只有它们出细网格
FINE_REGIONS = set("""HK MO TW JP KR SG MY TH VN PH ID KH MN IN PK BD LK NP MM LA BN KZ UZ KG AE SA QA BH KW OM JO LB IL CY IR IQ TR
GE AM AZ RU UA BY MD GB IE FR DE NL BE LU CH AT LI MC IT MT ES PT SE NO FI DK EE LV LT PL CZ SK SI HR RS BA ME MK AL GR BG RO HU IS
US CA MX PA CR GT BR AR CL CO PE EC UY VE AU NZ ZA EG NG KE MA TN""".split())


def iso_of(p):
    iso = p.get("ISO_A2_EH") or p.get("ISO_A2")
    return None if not iso or iso in ("-99", "AQ") else iso


def _area(ring):
    return abs(sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(ring, ring[1:] + ring[:1]))) / 2


def _centroid(ring):
    xs = [x for x, _ in ring]
    ys = [y for _, y in ring]
    return (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2


def rings(g):
    return g["coordinates"] if g["type"] == "MultiPolygon" else [g["coordinates"]]


def trim_far_parts(f):
    """1.20.1：去掉离本土很远的小块属地（荷兰的加勒比海岛屿、法属圭亚那、夏威夷、加那利群岛……）——
    面积不到最大一块的 20%、且中心离国家标注点超过 FAR° 的多边形不参与归属，否则取景会被拉到整幅世界。"""
    g = f["geometry"]
    if g["type"] != "MultiPolygon":
        return f
    p = f["properties"]
    lx, ly = p.get("LABEL_X"), p.get("LABEL_Y")
    if lx is None or ly is None:
        return f
    big = max(_area(poly[0]) for poly in g["coordinates"])
    keep = []
    for poly in g["coordinates"]:
        cx, cy = _centroid(poly[0])
        far = max(abs(cx - lx), abs(cy - ly)) > FAR
        if far and _area(poly[0]) < 0.2 * big:
            continue
        keep.append(poly)
    return {**f, "geometry": {"type": "MultiPolygon", "coordinates": keep}}


def fine_cells(feature, step):
    """国家在 step° 网格上「格内有任何覆盖」的格中心（纬度, 经度）。"""
    polys = rings(feature["geometry"])
    xs = [x for poly in polys for x, _ in poly[0]]
    ys = [y for poly in polys for _, y in poly[0]]
    lo_x, hi_x = min(xs), max(xs)
    lo_y, hi_y = min(ys), max(ys)
    if hi_x - lo_x > 180:  # 跨 180° 经线的国家不会是小国，跳过
        return []
    # 网格对齐：经度 -180 起、纬度 -90 起，每 step 一格
    gx0 = int((lo_x + 180) // step)
    gx1 = int((hi_x + 180) // step)
    gy0 = int((lo_y + 90) // step)
    gy1 = int((hi_y + 90) // step)
    per = int(round(step / FINE_PX))
    W = (gx1 - gx0 + 1) * per
    H = (gy1 - gy0 + 1) * per
    img = Image.new("1", (W, H), 0)
    d = ImageDraw.Draw(img)
    x0 = gx0 * step - 180
    y1 = (gy1 + 1) * step - 90

    def px(lon, lat):
        return ((lon - x0) / FINE_PX, (y1 - lat) / FINE_PX)

    for poly in polys:
        for i, ring in enumerate(poly):
            pts = [px(x, y) for x, y in ring]
            if len(pts) >= 3:
                d.polygon(pts, fill=0 if i else 1, outline=0 if i else 1)
    pix = img.load()
    out = []
    for gy in range(gy0, gy1 + 1):
        for gx in range(gx0, gx1 + 1):
            cx0 = (gx - gx0) * per
            cy0 = (gy1 - gy) * per
            hit = any(pix[x, y] for y in range(cy0, cy0 + per) for x in range(cx0, cx0 + per))
            if hit:
                out.append((gy * step - 90 + step / 2, gx * step - 180 + step / 2))
    if not out:
        p = feature["properties"]
        lx, ly = p.get("LABEL_X"), p.get("LABEL_Y")
        if lx is not None and ly is not None:
            out.append(((ly + 90) // step * step - 90 + step / 2, (lx + 180) // step * step - 180 + step / 2))
    return out


def pack(lat, lon):
    return int(round(lat * 8 + 720)) * 4096 + int(round(lon * 8 + 1440))


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
    step = step10 / 10
    bits = b[12:]
    land = lambda r, c: (bits[(r * w + c) >> 3] >> ((r * w + c) & 7)) & 1
    W, H = w * SS, h * SS
    img = Image.new("I", (W, H), 0)
    d = ImageDraw.Draw(img)
    codes = [None]
    feats = {}

    def px(lon, lat):
        return ((lon + 180) / 360 * W, (north - lat) / (north - south) * H)

    for f in data["features"]:
        iso = iso_of(f["properties"])
        if not iso:
            continue
        f = trim_far_parts(f)
        codes.append(iso)
        feats.setdefault(iso, []).append(f)
        idx = len(codes) - 1
        for poly in rings(f["geometry"]):
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

    fine = {}
    for iso, fs in sorted(feats.items()):
        if len(out.get(iso, [])) >= SMALL or iso not in FINE_REGIONS:
            continue
        # 小国：底图格补上「格内有任何覆盖」的格（真实轮廓）
        cover = set(out.get(iso, []))
        for f in fs:
            cover.update(fine_cells_coarse(f, step, north, w, h))
        out[iso] = sorted(cover)
        levels = []
        for s in FINE:
            pts = set()
            for f in fs:
                pts.update(pack(la, lo) for la, lo in fine_cells(f, s))
            # 0.5° 已有足够的点时不再存更细一级（表小一些；画的时候也用不上）
            levels.append(sorted(pts) if not levels or len(levels[0]) < 12 else [])
        fine[iso] = levels

    lines = [
        "// 穿云首页连接卡地图：点阵底图每个陆地点所属国家（已连接时高亮节点所在国家）。由 tool/world_dots/gen_dot_countries.py 生成，勿手改。",
        "// 数据：Natural Earth 1:50m Admin 0 – Countries，公有领域（Public Domain）。1.20.1 起由 1:110m 换成 1:50m。",
        "// Part of 穿云 (GPLv3).",
        "",
        f"/// 点阵网格宽 {w}、高 {h}；值为格序号 row * {w} + col。底图格少于 {SMALL} 个的小国另含「格内有任何覆盖」的格。",
        "const museDotCountryCells = <String, List<int>>{",
    ]
    for k in sorted(out):
        if out[k]:
            lines.append(f"  '{k}': [{', '.join(map(str, out[k]))}],")
    lines.append("};")
    lines.append("")
    lines.append(f"/// 1.20.1：小国（底图格少于 {SMALL} 个）在 {FINE[0]}° / {FINE[1]}° 细网格上的点，")
    lines.append("/// 打包为 (纬度×8 + 720) × 4096 + (经度×8 + 1440)，见 museUnpackFine。")
    lines.append("const museDotCountryFine = <String, List<List<int>>>{")
    for k in sorted(fine):
        lines.append(f"  '{k}': [{', '.join('[' + ', '.join(map(str, lv)) + ']' for lv in fine[k])}],")
    lines.append("};")
    open(a.out, "w").write("\n".join(lines) + "\n")
    rep = " ".join(f"{c}={len(out.get(c, []))}/{'/'.join(str(len(x)) for x in fine.get(c, []))}" for c in "NL CH IL BE QA HK SG MO LU JP US DE".split())
    print(f"{a.out}: {len(out)} countries, {sum(map(len, out.values()))} cells, {miss} unassigned; {rep}")


def fine_cells_coarse(feature, step, north, w, h):
    """国家在底图网格上「格内有任何覆盖」的格序号。"""
    res = []
    for lat, lon in fine_cells(feature, step):
        # fine_cells 按 -90 / -180 对齐；底图网格按北 [north] / -180 对齐，二者同为 step 的整数倍时一致
        row = int((north - lat) // step)
        col = int((lon + 180) // step) % w
        if 0 <= row < h:
            res.append(row * w + col)
    return res


if __name__ == "__main__":
    main()
