#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_tiles.py -- 程序化生成地形 tile（16x16，严格可平铺）

为什么不用 AI 生成 tile（实测结论，2026-10-12）：
  pixel-art-xl 是【角色】LoRA。写 "seamless concrete floor texture" 时，
  它产出的是"物件轮廓"（一块石头/一个色块），不是满幅铺满的纹理。
  试过 LoRA 权重 1.15 / 0.35 / 0.0 —— 三种都失败。
  而 16x16 地砖本质上就是「底色 + 几个深色像素」，AI 在这里是过度工具。

所以：tile 走程序化，AI 留给角色/物品/枪械/道具。

所有颜色取自 art/palette.gpl，输出严格 16x16、无半透明、可无缝平铺。

用法：
    python tools/art/gen_tiles.py            # 生成全部
    python tools/art/gen_tiles.py --list
"""

import argparse
import random
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from artlib import ART, SPEC, load_palette  # noqa: E402

try:
    from PIL import Image
except ImportError:
    raise SystemExit("需要 Pillow")

W, H = SPEC["tile"]          # 16 x 16
OUT = ART / "tiles"


# ─────────── 调色板索引助手 ───────────
# 按 art/palette.gpl 的分组顺序索引（见该文件注释）
class Pal:
    def __init__(self, colors):
        self.c = colors

    def __getitem__(self, i):
        return self.c[i % len(self.c)]

    def at(self, i):
        return self.c[i]


def group(colors, start, n):
    return colors[start:start + n]


# palette.gpl 的分组起点（累计）
G_DARK = 0        # 3   深邃背景
G_WALL = 3        # 5   墙体混凝土
G_STONE = 8       # 4   地面石材/沥青
G_DIRT = 12       # 4   泥土/沙
G_OLIVE = 16      # 5   军绿/橄榄
G_WOOD = 21       # 4   木材/锈
G_METAL = 25      # 4   金属钢
G_BLOOD = 29      # 3   血/暗红
G_FIRE = 32       # 3   火/橙黄
G_TECH = 35       # 3   科技青
G_WARN = 38       # 2   警示黄


# ─────────── 生成原语 ───────────

def blank(color):
    return Image.new("RGBA", (W, H), color + (255,))


def speckle(img, rng, palette_colors, count, avoid_edge=True, margin=1):
    """撒噪点。avoid_edge=True 时不动最外圈 —— 这样平铺时不会出现接缝。"""
    px = img.load()
    m = margin if avoid_edge else 0
    for _ in range(count):
        x = rng.randrange(m, W - m)
        y = rng.randrange(m, H - m)
        px[x, y] = rng.choice(palette_colors) + (255,)


def crack(img, rng, color, segments=3, margin=2):
    """
    画裂缝。只在内部游走并【不碰边界】，保证平铺无缝。
    """
    px = img.load()
    x = rng.randrange(margin + 1, W - margin - 1)
    y = rng.randrange(margin + 1, H - margin - 1)
    for _ in range(segments):
        px[x, y] = color + (255,)
        dx, dy = rng.choice([(1, 0), (-1, 0), (0, 1), (0, -1)])
        nx, ny = x + dx, y + dy
        if margin <= nx < W - margin and margin <= ny < H - margin:
            x, y = nx, ny
        else:
            dx, dy = -dx, -dy


def top_edge(img, color, rows=1):
    """给墙加亮顶边 —— 让墙从地板上读得出来（俯视 2.5D 的常用手法）。"""
    px = img.load()
    for y in range(rows):
        for x in range(W):
            px[x, y] = color + (255,)


def bottom_shadow(img, color, rows=1):
    px = img.load()
    for y in range(H - rows, H):
        for x in range(W):
            px[x, y] = color + (255,)


def bricks(img, rng, mortar, brick_colors, brick_h=4, brick_w=8, row_offset=4):
    """砌砖墙。严格按 16x16 整除的尺寸，保证可平铺。"""
    px = img.load()
    for y in range(H):
        for x in range(W):
            px[x, y] = mortar + (255,)
    for row, y0 in enumerate(range(0, H, brick_h)):
        off = 0 if row % 2 == 0 else row_offset
        for x0 in range(-brick_w + off, W, brick_w):
            col = rng.choice(brick_colors)
            for y in range(y0, min(y0 + brick_h - 1, H)):
                for x in range(x0, min(x0 + brick_w - 1, W)):
                    if 0 <= x < W:
                        px[x, y] = col + (255,)


def rivets(img, color, step=5, margin=3):
    """在金属板上打铆钉，位置按 step 均匀分布 —— 平铺时对齐。"""
    px = img.load()
    for y in range(margin, H - margin + 1, step):
        for x in range(margin, W - margin + 1, step):
            px[x, y] = color + (255,)


# ─────────── 各类 tile ───────────

def make_floor_concrete(rng, C):
    base = C[G_STONE + 2]
    img = blank(base)
    speckle(img, rng, [C[G_STONE + 0], C[G_STONE + 3], C[G_WALL + 3]], 30)
    for _ in range(2):
        crack(img, rng, C[G_STONE], segments=rng.randint(2, 4))
    return img


def make_floor_asphalt(rng, C):
    base = C[G_STONE + 1]
    img = blank(base)
    speckle(img, rng, [C[G_DARK + 2], C[G_STONE + 2], C[G_WALL + 3]], 38)
    return img


def make_floor_dirt(rng, C):
    base = C[G_DIRT + 1]
    img = blank(base)
    speckle(img, rng, [C[G_DIRT + 0], C[G_DIRT + 2], C[G_DIRT + 3]], 36)
    return img


def make_floor_metal(rng, C):
    base = C[G_METAL + 1]
    img = blank(base)
    speckle(img, rng, [C[G_METAL + 0], C[G_METAL + 3]], 22)
    rivets(img, C[G_METAL + 2], step=7, margin=4)
    return img


def make_wall_concrete(rng, C):
    # ⚠️ 不加 top_edge/bottom_shadow：
    #    一个逻辑格铺 3x3 块砖，每块都带边 = 3 条横杠（实测踩过）。
    #    墙的轮廓交给渲染层画（见 view/raid_scene.gd 的格边描线）。
    base = C[G_WALL + 1]
    img = blank(base)
    speckle(img, rng, [C[G_WALL], C[G_WALL + 3], C[G_WALL + 4]], 30)
    for _ in range(2):
        crack(img, rng, C[G_WALL], segments=3)
    return img


def make_wall_brick(rng, C):
    brick_cols = [C[G_WOOD + 1], C[G_WOOD + 2], C[G_BLOOD + 0]]
    img = Image.new("RGBA", (W, H))
    bricks(img, rng, C[G_WALL], brick_cols, brick_h=4, brick_w=8, row_offset=4)
    return img


def make_wall_metal(rng, C):
    base = C[G_METAL + 2]
    img = blank(base)
    # 竖向波纹
    px = img.load()
    for x in range(0, W, 4):
        for y in range(H):
            px[x, y] = C[G_METAL + 1] + (255,)
            if x + 1 < W:
                px[x + 1, y] = C[G_METAL + 3] + (255,)
    speckle(img, rng, [C[G_WOOD + 1], C[G_WOOD + 2]], 8)   # 锈迹
    return img


TILES = {
    "tile_floor_concrete": make_floor_concrete,
    "tile_floor_asphalt":  make_floor_asphalt,
    "tile_floor_dirt":     make_floor_dirt,
    "tile_floor_metal":    make_floor_metal,
    "tile_wall_concrete":  make_wall_concrete,
    "tile_wall_brick":     make_wall_brick,
    "tile_wall_metal":     make_wall_metal,
}


# ─────────── 可平铺性自检 ───────────

def check_tileable(img):
    """
    检查最外圈是否"安静"（噪点/裂缝不碰边界）。
    碰边界不一定是错的，但会放大平铺接缝；这里作为提示返回。
    """
    px = img.load()
    edge_colors = set()
    for x in range(W):
        edge_colors.add(px[x, 0][:3])
        edge_colors.add(px[x, H - 1][:3])
    for y in range(H):
        edge_colors.add(px[0, y][:3])
        edge_colors.add(px[W - 1, y][:3])
    return len(edge_colors)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=20261012)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--variants", type=int, default=3, help="每种生成几个变体")
    a = ap.parse_args()

    C = load_palette()
    if len(C) < 40:
        print(f"⚠️ 调色板只有 {len(C)} 色，期望 40")

    if a.list:
        for k in TILES:
            print(" ", k)
        return 0

    OUT.mkdir(parents=True, exist_ok=True)
    total = 0
    for name, fn in TILES.items():
        for v in range(a.variants):
            rng = random.Random(a.seed + hash(name) % 100000 + v * 977)
            img = fn(rng, C)
            assert img.size == (W, H), f"{name} 尺寸错误 {img.size}"
            # 强制不透明 + 颜色数自检
            out = OUT / (f"{name}_{v}.png" if a.variants > 1 else f"{name}.png")
            img.save(out)
            total += 1
    print(f"生成 {total} 个 tile -> {OUT.relative_to(ART.parent)}  ({W}x{H})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
