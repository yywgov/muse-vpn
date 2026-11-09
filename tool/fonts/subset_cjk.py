#!/usr/bin/env python3
"""穿云 1.19.2：把思源黑体（Noto Sans SC，SIL OFL 1.1）子集化成随应用分发的中文字体。

源字体不进仓库：从 Google Fonts 下载可变字体 NotoSansSC[wght].ttf（OFL），再运行

    python3 tool/fonts/subset_cjk.py <NotoSansSC 可变字体.ttf> [输出目录=assets/fonts]

字符集 = GB2312 一级 + 二级全部汉字（6763 字，覆盖《通用规范汉字表》一级 3500 字）
      + GB2312 符号区（全角标点、序号、单位等）
      + ASCII 可打印字符 + Latin-1 补充 + 常用排版符号
      + 扫描 lib/ 下全部 .dart 文件里出现的每一个非 ASCII 字符（应用内文案用字必须全部包含）。
字重：400 / 600（由可变字体 wght 轴实例化）。去掉 hinting 与竖排表以减小体积；保留 kern。
脚本只依赖 fontTools（pip install fonttools）。输出 MuseHei-Regular/Medium/Bold.ttf 与字符清单。
"""
import os
import pathlib
import sys

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = pathlib.Path(__file__).resolve().parents[2]
# 1.19.2：400 + 600 两档（三档 400/500/700 每包增量约 4.4 MB，超出 4 MB 目标）
WEIGHTS = {400: 'Regular', 600: 'SemiBold'}


def gb2312_chars():
    out = set()
    # 符号区 A1–A9，一级 B0–D7，二级 D8–F7
    for hi in list(range(0xA1, 0xAA)) + list(range(0xB0, 0xF8)):
        for lo in range(0xA1, 0xFF):
            try:
                out.add(bytes([hi, lo]).decode('gb2312'))
            except UnicodeDecodeError:
                pass
    return out


def app_chars():
    out = set()
    for p in (ROOT / 'lib').rglob('*.dart'):
        for ch in p.read_text(encoding='utf-8', errors='ignore'):
            if ord(ch) > 0x7E:
                out.add(ch)
    return out


def charset():
    chars = gb2312_chars() | app_chars()
    chars |= {chr(c) for c in range(0x20, 0x7F)}
    chars |= {chr(c) for c in range(0xA0, 0x100)}
    chars |= set('‐‑–—―‘’‚“”„†‡•…‰′″‹›€™←↑→↓↔⇄√∞≈≠≤≥①②③④⑤⑥⑦⑧⑨⑩·・、。〈〉《》「」『』【】〔〕〖〗〜！＂＃＄％＆＇（）＊＋，－．／：；＜＝＞？＠［＼］＾＿｀｛｜｝～￥')
    # 只保留字体本身有字形的字符（emoji、国旗等交给系统 / Emoji 字体）
    return {c for c in chars if not (0xD800 <= ord(c) <= 0xDFFF)}


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = sys.argv[1]
    out_dir = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else ROOT / 'assets' / 'fonts')
    out_dir.mkdir(parents=True, exist_ok=True)
    chars = charset()
    var = TTFont(src)
    cmap = var.getBestCmap()
    keep = sorted(c for c in chars if ord(c) in cmap)
    missing = sorted(c for c in app_chars() if ord(c) not in cmap and ord(c) > 0x2E7F and not (0x1F000 <= ord(c)))
    print(f'字符 {len(keep)} 个（应用内文案非 ASCII 字符 {len(app_chars())} 个，字体缺字形 {len(missing)} 个：{"".join(missing)[:80]}）')
    for w, name in WEIGHTS.items():
        f = instancer.instantiateVariableFont(TTFont(src), {'wght': w}, updateFontNames=False)
        opts = subset.Options()
        opts.layout_features = ['kern', 'locl', 'ccmp', 'liga', 'calt', 'palt', 'halt', 'vert']
        opts.hinting = False
        opts.drop_tables += ['vhea', 'vmtx', 'BASE', 'STAT', 'DSIG']
        opts.name_IDs = ['*']
        opts.name_languages = ['*']
        opts.notdef_outline = True
        opts.glyph_names = False
        s = subset.Subsetter(opts)
        s.populate(text=''.join(keep))
        s.subset(f)
        # 名称：族名 MuseHei（OFL 保留字体名 Noto 不用于修改版）
        for rec in f['name'].names:
            if rec.nameID in (1, 16):
                rec.string = 'MuseHei'
            elif rec.nameID in (2, 17):
                rec.string = name
            elif rec.nameID == 4:
                rec.string = f'MuseHei {name}'
            elif rec.nameID == 6:
                rec.string = f'MuseHei-{name}'
            elif rec.nameID == 3:
                rec.string = f'MuseHei-{name};chuanyun-subset'
        f['OS/2'].usWeightClass = w
        path = out_dir / f'MuseHei-{name}.ttf'
        f.save(path)
        print(path.name, os.path.getsize(path))
    (ROOT / 'tool' / 'fonts' / 'musehei_chars.txt').write_text(''.join(keep), encoding='utf-8')


if __name__ == '__main__':
    main()
