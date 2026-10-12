#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
postprocess.py -- 素材后处理（art-pipeline.md §8.1 的 ③④⑤ 步）

做四件事：
  1. 去背景（角落泛洪填充 -> 透明）
  2. 自动裁到主体包围盒
  3. 按锚点对齐到目标画布（角色脚底锚点见 artlib.ANCHOR_FOOT）
  4. 生成接触表预览（肉眼验收用）

为什么需要这些：实测 AI 输出的主体只占画面一小块、背景不透明、姿态不居中，
直接压到 48x48 会又小又糊。
"""

import sys
from collections import deque
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from artlib import ANCHOR_FOOT, load_palette, quantize  # noqa: E402

try:
    from PIL import Image
except ImportError:
    raise SystemExit("需要 Pillow")


# ─────────── 1. 去背景 ───────────

def _sample_bg_color(px, w, h, ring=2):
    """
    采样背景色：取外圈 ring 像素里出现最多的颜色。

    ⚠️ 实测：只用四角采样会取错 —— 有些图下边缘有地板/阴影，
       某个角落拿到的是地板色而不是背景色，导致整张图去背失败。
       外圈众数稳健得多。
    """
    from collections import Counter
    cnt = Counter()
    for x in range(w):
        for y in range(min(ring, h)):
            cnt[px[x, y][:3]] += 1
        for y in range(max(0, h - ring), h):
            cnt[px[x, y][:3]] += 1
    for y in range(h):
        for x in range(min(ring, w)):
            cnt[px[x, y][:3]] += 1
        for x in range(max(0, w - ring), w):
            cnt[px[x, y][:3]] += 1
    if not cnt:
        return (0, 0, 0)
    return cnt.most_common(1)[0][0]


def remove_background(img, tolerance=38, mode="both", global_tol=None, feather=False):
    """
    去背景。

    mode:
      "border" —— 从四角泛洪填充，只删与边界连通的背景
                  （安全，但腿间/腋下等【封闭】背景区域删不掉 —— 实测踩过）
      "global" —— 全局色键，删掉所有接近背景色的像素
                  （能删封闭区域，但可能吃掉与背景同色的浅色装备）
      "both"   —— 先 border 再 global（推荐：border 保护主体，global 补封闭区）

    tolerance:       border 阶段的颜色距离阈值
    global_tol:      global 阶段的阈值，默认取 tolerance 的 0.6 倍
                     （更严，避免吃掉头盔这类浅色装备）
    """
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()

    bg = _sample_bg_color(px, w, h)
    if global_tol is None:
        global_tol = max(10, int(tolerance * 0.6))

    def dist(c):
        dr, dg, db = c[0] - bg[0], c[1] - bg[1], c[2] - bg[2]
        return (dr * dr + dg * dg + db * db) ** 0.5

    # ── 阶段 1：边界泛洪 ──
    if mode in ("border", "both"):
        visited = bytearray(w * h)
        q = deque()
        for x in range(w):
            for y in (0, h - 1):
                if not visited[y * w + x]:
                    visited[y * w + x] = 1
                    q.append((x, y))
        for y in range(h):
            for x in (0, w - 1):
                if not visited[y * w + x]:
                    visited[y * w + x] = 1
                    q.append((x, y))
        while q:
            x, y = q.popleft()
            if px[x, y][3] == 0 or dist(px[x, y]) <= tolerance:
                px[x, y] = (0, 0, 0, 0)
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h and not visited[ny * w + nx]:
                        visited[ny * w + nx] = 1
                        q.append((nx, ny))

    # ── 阶段 2：全局补封闭区域（阈值更严）──
    if mode == "global" or mode == "both":
        for y in range(h):
            for x in range(w):
                c = px[x, y]
                if c[3] != 0 and dist(c) <= global_tol:
                    px[x, y] = (0, 0, 0, 0)

    return img


def keep_largest_component(img, min_ratio=0.35):
    """
    只保留最大的连通主体，删掉零散碎片。
    实测：AI 有时会在角落多画一个小人／装饰，这个函数把它清掉。
    """
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    label = [-1] * (w * h)
    comps = []

    for sy in range(h):
        for sx in range(w):
            i0 = sy * w + sx
            if label[i0] != -1 or px[sx, sy][3] <= 16:
                continue
            cid = len(comps)
            q = deque([(sx, sy)])
            label[i0] = cid
            cells = []
            while q:
                x, y = q.popleft()
                cells.append((x, y))
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h:
                        ni = ny * w + nx
                        if label[ni] == -1 and px[nx, ny][3] > 16:
                            label[ni] = cid
                            q.append((nx, ny))
            comps.append(cells)

    if len(comps) <= 1:
        return img
    comps.sort(key=len, reverse=True)
    biggest = len(comps[0])
    keep = set()
    for cells in comps:
        if len(cells) >= biggest * min_ratio:
            keep.update(cells)
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > 16 and (x, y) not in keep:
                px[x, y] = (0, 0, 0, 0)
    return img


# ─────────── 2. 自动裁到主体 ───────────

def subject_bbox(img, alpha_threshold=16):
    """返回非透明像素的包围盒；没有主体返回 None"""
    img = img.convert("RGBA")
    a = img.getchannel("A").point(lambda v: 255 if v > alpha_threshold else 0)
    return a.getbbox()


def autocrop(img, pad=6):
    """裁到主体包围盒 + 留 padding"""
    bb = subject_bbox(img)
    if bb is None:
        return img
    w, h = img.size
    x0 = max(0, bb[0] - pad)
    y0 = max(0, bb[1] - pad)
    x1 = min(w, bb[2] + pad)
    y1 = min(h, bb[3] + pad)
    return img.crop((x0, y0, x1, y1))


# ─────────── 3. 对齐到目标画布 ───────────

def fit_to_canvas(img, target, anchor=None, scale_mode="fit", pad=2):
    """
    把主体缩放进 target 画布。

    scale_mode:
      "fit"  —— 等比缩放到能放进画布（保比例，留空）
      "fill" —— 等比缩放到铺满画布短边（可能裁掉边缘，适合 tile）
    anchor: 目标画布上的锚点像素坐标（如角色脚底 ANCHOR_FOOT）。
            给了 anchor 就把主体【底部中心】对齐到它；否则居中。
    """
    if isinstance(target, int):
        target = (target, target)
    canvas = Image.new("RGBA", target, (0, 0, 0, 0))
    bb = subject_bbox(img)
    if bb is None:
        return canvas

    sub = img.crop(bb)
    tw, th = target
    sw, sh = sub.size
    if sw <= 0 or sh <= 0:
        return canvas

    if scale_mode == "fill":
        k = max(tw / sw, th / sh)
    else:
        k = min((tw - pad * 2) / sw, (th - pad * 2) / sh)
    nw, nh = max(1, int(round(sw * k))), max(1, int(round(sh * k)))
    sub = sub.resize((nw, nh), Image.LANCZOS)

    if anchor is not None:
        ax, ay = anchor
        ox = int(round(ax - nw / 2.0))
        oy = int(round(ay - nh))          # 主体底部贴 anchor
    else:
        ox = (tw - nw) // 2
        oy = (th - nh) // 2
    canvas.alpha_composite(sub, (ox, oy))
    return canvas


# ─────────── 4. 预览接触表 ───────────

def preview_sheet(items, out_path, zoom=8, cols=None, bg=(24, 25, 30)):
    """
    items: [(图片路径 或 PIL.Image, 标签), ...]
    上排原图缩略，下排像素版放大 —— 肉眼验收用（art-pipeline §8.3 preview_sheet.py）
    """
    imgs = []
    for it in items:
        p = it[0]
        im = Image.open(p) if isinstance(p, (str, Path)) else p
        imgs.append((im.convert("RGBA"), it[1] if len(it) > 1 else ""))
    if not imgs:
        return None

    cols = cols or len(imgs)
    rows = (len(imgs) + cols - 1) // cols

    # 上排：等宽缩略
    thumb = 256
    gap = 12
    top_h = thumb
    # 下排：按各自尺寸放大
    max_zoom_h = max(im.height for im, _ in imgs) * zoom
    bot_h = min(max_zoom_h, 512)

    W = cols * (thumb + gap) + gap
    H = top_h + bot_h + gap * 3
    sheet = Image.new("RGB", (W, H), bg)

    for i, (im, _) in enumerate(imgs):
        r, c = divmod(i, cols)
        x = gap + c * (thumb + gap)

        # 上排缩略（保比例）
        a = im.copy()
        a.thumbnail((thumb, thumb), Image.LANCZOS)
        sheet.paste(a.convert("RGB"), (x + (thumb - a.width) // 2, gap + (thumb - a.height) // 2),
                    a if a.mode == "RGBA" else None)

        # 下排放大
        z = min(zoom, max(1, bot_h // max(1, im.height)))
        big = im.resize((im.width * z, im.height * z), Image.NEAREST)
        y = top_h + gap * 2
        sheet.paste(big.convert("RGB"), (x, y), big if big.mode == "RGBA" else None)

    sheet.save(out_path)
    return out_path


# ─────────── 完整流程 ───────────

def process(raw_path, target, anchor=None, palette=None, tolerance=38,
            scale_mode="fit", pad=2, dither=False, bg_mode="both",
            largest_only=True, min_ratio=0.35):
    """去背景 -> 去碎片 -> 裁主体 -> 缩放对齐 -> 量化。返回 PIL.Image"""
    img = Image.open(raw_path)
    img = remove_background(img, tolerance=tolerance, mode=bg_mode)
    if largest_only:
        img = keep_largest_component(img, min_ratio=min_ratio)
    img = autocrop(img, pad=8)
    img = fit_to_canvas(img, target, anchor=anchor, scale_mode=scale_mode, pad=pad)
    if palette is not None:
        tmp = Path(raw_path).with_name(Path(raw_path).stem + "_fit.png")
        img.save(tmp)
        img = quantize(tmp, None, palette)
        tmp.unlink(missing_ok=True)
    return img


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--size", type=int, nargs=2, default=[48, 48])
    ap.add_argument("--anchor", type=int, nargs=2, default=list(ANCHOR_FOOT))
    ap.add_argument("--tol", type=int, default=38)
    ap.add_argument("--fill", action="store_true")
    a = ap.parse_args()
    pal = load_palette()
    out = process(a.src, tuple(a.size), tuple(a.anchor), pal,
                  tolerance=a.tol, scale_mode="fill" if a.fill else "fit")
    out.save(a.dst)
    print(f"{a.src} -> {a.dst}  {out.size}")
