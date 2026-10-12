# -*- coding: utf-8 -*-
"""从 raid_scene.gd 抽出地图烘焙 -> view/raid_map_baker.gd

搬迁的是【原文】而不是手抄 —— 避免抄错。
地图烘焙是纯图像生成：不画东西、不碰坐标空间、不依赖节点树，
所以是 raid_scene.gd 里边界最干净、风险最低的一块。
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "view" / "raid_scene.gd"
OUT = ROOT / "view" / "raid_map_baker.gd"

src = SRC.read_text(encoding="utf-8")
lines = src.split("\n")


def grab(name: str) -> str:
    """取出顶层函数原文（含前导注释行），并从文件里删掉它"""
    start = None
    for i, l in enumerate(lines):
        if l.startswith("func " + name + "("):
            start = i
            break
    if start is None:
        raise SystemExit("❌ 找不到函数 %s" % name)
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if lines[j].startswith("func "):
            end = j
            break
    # 往前吃掉紧邻的注释
    top = start
    while top > 0 and (lines[top - 1].strip().startswith("#") or lines[top - 1].strip() == ""):
        if lines[top - 1].strip() == "" and not (top - 2 >= 0 and lines[top - 2].strip().startswith("#")):
            break
        top -= 1
    body = "\n".join(lines[top:end]).rstrip("\n")
    del lines[top:end]
    return body


def grab_const(name: str) -> str:
    """取出常量定义原文（支持多行字典），并从文件里删掉它"""
    start = None
    for i, l in enumerate(lines):
        if l.startswith("const " + name + " ") or l.startswith("const " + name + ":"):
            start = i
            break
    if start is None:
        raise SystemExit("❌ 找不到常量 %s" % name)
    end = start + 1
    if lines[start].rstrip().endswith("{"):
        depth = lines[start].count("{") - lines[start].count("}")
        while end < len(lines) and depth > 0:
            depth += lines[end].count("{") - lines[end].count("}")
            end += 1
    text = "\n".join(lines[start:end])
    del lines[start:end]
    return text


# ── 逐个取出 ──
bodies = {}
for fn in ["_load_tiles", "_build_map_texture", "_build_whitebox",
           "_build_tiles", "_bake_structure", "_draw_seam", "_tile_key_for"]:
    bodies[fn] = grab(fn)

tile_names = grab_const("TILE_NAMES")
tile_px = grab_const("TILE_PX")

# ── 取出 _tiles 变量声明 ──
tiles_var = None
for i, l in enumerate(lines):
    if l.startswith("var _tiles"):
        tiles_var = l
        del lines[i]
        break
if tiles_var is None:
    raise SystemExit("❌ 找不到 var _tiles")

# ── 生成 raid_map_baker.gd ──
header = '''class_name RaidMapBaker
extends RefCounted

## 地图烘焙 —— 从 `view/raid_scene.gd` 抽出来
##
## 职责：把逻辑网格烘成**一张像素图**（白模或美术 tile），供场景一次性绘制。
##
## ─── 为什么是它先被切出来 ───
## `raid_scene.gd` 曾 1676 行 / 51 函数，50% 的提交都要改它。
## 这块是其中**边界最干净**的：纯图像生成 ——
## 不画东西、不碰坐标空间、不依赖节点树、不读玩家状态。
## 所以它可以（也应该）被 headless 单测，而留在场景里的时候做不到。
##
## ⚠️ 搬迁的是**原文**，没有手抄 —— 避免抄错像素逻辑。

'''

parts = [header, tile_px, "", tile_names, "", tiles_var, "", ""]
for fn in ["_load_tiles", "_build_map_texture", "_build_whitebox",
           "_build_tiles", "_bake_structure", "_draw_seam", "_tile_key_for"]:
    parts.append(bodies[fn])
    parts.append("")
    parts.append("")

OUT.write_text("\n".join(parts).rstrip("\n") + "\n", encoding="utf-8")

SRC.write_text("\n".join(lines), encoding="utf-8")

print("✅ 已抽出 view/raid_map_baker.gd")
print("   搬走的函数:", ", ".join(bodies.keys()))
print("   搬走的常量: TILE_PX, TILE_NAMES")
print("   raid_scene.gd: %d -> %d 行" % (len(src.split("\n")), len(lines)))
