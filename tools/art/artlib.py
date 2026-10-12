#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
artlib.py -- 美术管线基础库

依据 specs/art-pipeline.md：
  §2    硬规格（画布尺寸 / 调色板 / 锚点）
  §8.2  调色板策略：所有素材入库前必须量化到 art/palette.gpl
  §9    验收标准（尺寸 / 颜色数 / 无抗锯齿 / 命名）

用法：
    from artlib import load_palette, quantize, validate_image, SPEC
    pal = load_palette()
    quantize("raw.png", "out.png", pal)
"""

import os
import re
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    raise SystemExit("需要 Pillow：请用 bundled python 运行本脚本")


ROOT = Path(__file__).resolve().parent.parent.parent
ART = ROOT / "art"
PALETTE_PATH = ART / "palette.gpl"

# ─────────── 硬规格（art-pipeline.md §2）───────────
SPEC = {
    "tile": (16, 16),
    "character_frame": (48, 48),      # 身体约 32x32，其余留给枪械旋转
    "item_icon": (32, 32),
    "gun_base": (48, 24),
    "ui_icon_small": (16, 16),
    "ui_icon": (24, 24),
    "vfx_max": (64, 64),
}

# 角色帧的脚底锚点（art-pipeline.md §2）
ANCHOR_FOOT = (24, 40)
# 肩部锚点（手臂/枪械旋转中心）
ANCHOR_SHOULDER = (24, 26)


# ─────────── 调色板 ───────────

def load_palette(path=None):
    """读 .gpl，返回 [(r,g,b), ...]"""
    p = Path(path) if path else PALETTE_PATH
    if not p.exists():
        raise SystemExit(f"调色板不存在：{p}")
    colors = []
    for line in p.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("GIMP") \
           or line.startswith("Name:") or line.startswith("Columns:"):
            continue
        parts = line.split()
        if len(parts) >= 3:
            try:
                colors.append((int(parts[0]), int(parts[1]), int(parts[2])))
            except ValueError:
                continue
    if not colors:
        raise SystemExit("调色板为空")
    return colors


def save_palette_json(path=None):
    """导出 JSON 版（给 GDScript / 校验器用）"""
    import json
    pal = load_palette()
    out = Path(path) if path else (ART / "palette.json")
    out.write_text(json.dumps({
        "name": "搜打撤 Tactical 40",
        "count": len(pal),
        "colors": [{"r": c[0], "g": c[1], "b": c[2],
                    "hex": "#%02x%02x%02x" % c} for c in pal],
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    return out


# ─────────── 量化 ───────────

def _make_palette_image(colors):
    """PIL 的 quantize 需要一个 P 模式调色板图"""
    pal_img = Image.new("P", (1, 1))
    flat = []
    for c in colors:
        flat.extend(c)
    # PIL 调色板必须 768 字节
    flat += [0] * (768 - len(flat))
    pal_img.putpalette(flat)
    return pal_img


def quantize(src, dst=None, colors=None, dither=Image.NONE):
    """
    把图片量化到项目调色板。

    ⚠️ 像素画【默认不用抖动】—— 抖动会引入额外的中间色，
       破坏像素画的硬边与有限色板（art-pipeline.md §8.2 的取舍）。
    """
    if colors is None:
        colors = load_palette()
    img = Image.open(src)
    had_alpha = img.mode in ("RGBA", "LA")
    alpha = img.getchannel("A") if had_alpha else None

    rgb = img.convert("RGB")
    pal_img = _make_palette_image(colors)
    q = rgb.quantize(palette=pal_img, dither=dither).convert("RGB")

    if had_alpha:
        q = q.convert("RGBA")
        q.putalpha(alpha)

    if dst:
        Path(dst).parent.mkdir(parents=True, exist_ok=True)
        q.save(dst)
    return q


def color_count(img):
    """统计不透明像素用到的不同颜色数"""
    if isinstance(img, (str, Path)):
        img = Image.open(img)
    img = img.convert("RGBA")
    px = img.load()
    seen = set()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a > 0:
                seen.add((r, g, b))
    return len(seen)


# ─────────── 校验（art-pipeline.md §9）───────────

def validate_image(path, expect_size=None, max_colors=40, palette=None,
                   allow_alpha=True, max_anchor_drift=None):
    """
    返回 (ok: bool, problems: list[str])。
    覆盖 art-pipeline.md §9 的验收项：
      尺寸精确 / 颜色数 <= 调色板 / 无半透明抗锯齿残留 / 在调色板内
    """
    problems = []
    p = Path(path)
    if not p.exists():
        return False, [f"文件不存在：{path}"]

    img = Image.open(p)
    if expect_size and tuple(img.size) != tuple(expect_size):
        problems.append(f"尺寸 {img.size} != 期望 {tuple(expect_size)}")

    if img.mode not in ("RGBA", "LA", "P"):
        img = img.convert("RGBA")

    # 半透明残留 = 抗锯齿/矢量痕迹（像素画不该有）
    if not allow_alpha:
        if img.mode == "RGBA":
            alphas = set(img.getchannel("A").getdata())
            if alphas - {0, 255}:
                problems.append(f"存在半透明像素（值 {sorted(alphas - {0,255})[:6]}）——疑似抗锯齿残留")
    else:
        if img.mode == "RGBA":
            bad = {a for a in img.getchannel("A").getdata() if a not in (0, 255)}
            if bad:
                problems.append(f"存在半透明像素（{sorted(bad)[:6]}）——疑似抗锯齿残留")

    n = color_count(img)
    if max_colors and n > max_colors:
        problems.append(f"颜色数 {n} > 上限 {max_colors}")

    if palette:
        allowed = set(palette)
        img_rgb = img.convert("RGBA")
        px = img_rgb.load()
        off = set()
        for y in range(img_rgb.height):
            for x in range(img_rgb.width):
                r, g, b, a = px[x, y]
                if a > 0 and (r, g, b) not in allowed:
                    off.add((r, g, b))
        if off:
            problems.append(f"有 {len(off)} 种颜色不在项目调色板内，例如 {sorted(off)[:5]}")

    return (len(problems) == 0), problems


# ─────────── 命名规范（art-pipeline.md §7）───────────

NAME_RE = re.compile(r"^[a-z0-9_]+\.(png)$")


def validate_name(path):
    name = Path(path).name
    if not NAME_RE.match(name):
        return False, f"命名不合规（须全小写+下划线）：{name}"
    if re.search(r"[\u4e00-\u9fff]", name):
        return False, f"文件名含中文：{name}"
    return True, ""


def iter_assets(subdir=""):
    base = ART / subdir if subdir else ART
    if not base.exists():
        return
    for p in sorted(base.rglob("*.png")):
        if "_raw" in p.parts or "_licenses" in p.parts:
            continue
        yield p


# ─────────── 自检 ───────────

if __name__ == "__main__":
    pal = load_palette()
    print(f"调色板：{len(pal)} 色")
    print("  前 8 色：", ["#%02x%02x%02x" % c for c in pal[:8]])
    print("  后 8 色：", ["#%02x%02x%02x" % c for c in pal[-8:]])
    out = save_palette_json()
    print(f"已导出 {out}")
    for k, v in SPEC.items():
        print(f"  规格 {k}: {v[0]}x{v[1]}")
