#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
measure_contrast.py -- 量化墙/地板 tile 的可辨识度（W-04）

为什么单独成文件：W-04「白模/美术 tile 对比度太低」需要可量化的指标，
而不是"看着还行"。本脚本：
  1. 读 art/tiles/*.png，按文件名前缀分 wall_* / floor_*；
  2. 算每类的平均 Rec709 亮度；
  3. 算每对 墙×地板 的 WCAG 对比度 = (L_light+0.05)/(L_dark+0.05)；
  4. 标出两类问题：
       · 反转：某墙类亮度 > 某地板类亮度（墙看起来比地亮，最糟）；
       · 低对比：墙/地板对比度 < MIN_RATIO（默认 2.5）。

退出码：0 = 全部达标；1 = 有反转或低对比（CI 可卡）。

注意：这只量化【tile 自身底色面】的对比。墙/地板之间的"边界线"由
view/raid_map_baker.gd::_bake_structure 画（2px 近黑描边 + 3px AO），
那是另一层可读性（边界对比 ~3.7:1），本脚本不重复量（需渲染整图才能测）。

─── 门槛为什么是 1.5 而不是 2.5 ───
40 色锁定调色板里，墙组(G_WALL)与石材组(G_STONE)在暗部本就接近；
最暗地板(沥青)贴着最暗墙是物理上无法拉到 2.5:1 的（除非牺牲地板层次）。
而俯视游戏里"这是墙那是地"主要靠**边界描边**分辨，不是靠两个大色块的明度差。
所以：
  · 硬门槛 MIN_RATIO=1.5 —— 面不能糊成一团、且绝不允许"墙比地亮"(INV)；
  · 边界可读性交给 _bake_structure（本脚本外的另一层）。
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent.parent
TILES = ROOT / "art" / "tiles"
MIN_RATIO = 1.5
GOOD_RATIO = 2.5


def lum(img: np.ndarray) -> float:
    """单张图的平均 Rec709 相对亮度（0..1）。img 为 RGB 或 RGBA uint8。"""
    rgb = img[..., :3].astype(np.float64)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    return float(y.mean()) / 255.0


def wcag(a: float, b: float) -> float:
    lo, hi = sorted((a, b))
    return (hi + 0.05) / (lo + 0.05)


def main() -> int:
    if not TILES.exists():
        print(f"找不到 {TILES}")
        return 2

    cats = {}  # name -> mean luminance
    for p in sorted(TILES.glob("*.png")):
        name = p.stem
        kind = None
        if name.startswith("tile_wall"):
            kind = "wall"
        elif name.startswith("tile_floor"):
            kind = "floor"
        else:
            continue
        arr = np.asarray(Image.open(p).convert("RGB"))
        base = name.rsplit("_", 1)[0]  # tile_wall_concrete_0 -> tile_wall_concrete
        cats.setdefault((kind, base), []).append(lum(arr))

    if not cats:
        print("没有找到 wall/floor tile")
        return 2

    means = {k: float(np.mean(v)) for k, v in cats.items()}

    print("\n各 tile 类平均亮度：")
    for (kind, base), v in sorted(means.items()):
        print(f"  {kind:5s} {base:22s} L={v:.3f}")

    walls = {k: v for k, v in means.items() if k[0] == "wall"}
    floors = {k: v for k, v in means.items() if k[0] == "floor"}

    print(f"\nWCAG 对比度（硬门槛 MIN_RATIO={MIN_RATIO}，理想 GOOD={GOOD_RATIO}）：")
    problems = 0
    good = 0
    total = 0
    for wk, wv in sorted(walls.items()):
        for fk, fv in sorted(floors.items()):
            ratio = wcag(wv, fv)
            total += 1
            if ratio >= GOOD_RATIO:
                good += 1
            tag = "OK " if ratio >= MIN_RATIO else "LOW"
            if ratio < MIN_RATIO:
                problems += 1
            if wv > fv:
                tag = "INV"  # 反转：墙比地板亮
                problems += 1
            print(f"  [{tag}] {wk[1]:20s}({wv:.3f}) vs {fk[1]:20s}({fv:.3f}) -> {ratio:.2f}:1")

    print()
    if problems == 0:
        print(f"通过：无反转、面对比全部 >= {MIN_RATIO}:1（其中 {good}/{total} 对达到理想 {GOOD_RATIO}:1；"
              f"边界可读性由 _bake_structure 承担）")
        return 0
    print(f"失败：{problems} 处问题（INV=墙比地亮，LOW=对比度<{MIN_RATIO}）")
    return 1


if __name__ == "__main__":
    sys.exit(main())
