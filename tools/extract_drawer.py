# -*- coding: utf-8 -*-
"""从 raid_scene.gd 抽出 _draw -> view/raid_drawer.gd

做法：把 `_draw` 的函数体搬过去，并对**裸的场景成员名**统一加 `scene.` 前缀。
用**单次正则替换**（一个 alternation），避免"加了前缀之后又被二次匹配"。

依据（跑依赖分析得出的，不是猜的）：
  · 12 个 C_* 颜色**只在 _draw 里用** -> 整体搬进 drawer
  · CELL_PX / TRACER_TTL / aim_cone_deg / _lock_info 在别处也用 -> 留在场景，drawer 读 scene.*
  · _cell_rect 只在 _draw 用 -> 搬进 drawer
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "view" / "raid_scene.gd"
OUT = ROOT / "view" / "raid_drawer.gd"

src = SRC.read_text(encoding="utf-8")
lines = src.split("\n")

# ── 1. 取出 _draw 原文 ──
ds = next(i for i, l in enumerate(lines) if l.startswith("func _draw("))
de = next(j for j in range(ds + 1, len(lines)) if lines[j].startswith("func "))
draw_body = "\n".join(lines[ds:de]).rstrip("\n")
del lines[ds:de]

# ── 2. 取出 _cell_rect 原文 ──
cs = next(i for i, l in enumerate(lines) if l.startswith("func _cell_rect("))
ce = next(j for j in range(cs + 1, len(lines)) if lines[j].startswith("func "))
cell_rect_body = "\n".join(lines[cs:ce]).rstrip("\n")
del lines[cs:ce]

# ── 3. 取出 12 个 C_* 颜色常量 ──
colors = []
i = 0
while i < len(lines):
    if re.match(r"^const C_[A-Z_]+ :=", lines[i]):
        colors.append(lines.pop(i))
    else:
        i += 1
if len(colors) != 12:
    raise SystemExit("❌ 只取到 %d 个 C_* 颜色（期望 12）" % len(colors))

# ── 4. 给裸的场景成员名加 scene. 前缀（单次替换）──
SCENE_MEMBERS = [
    "gen", "raid", "agents", "bullets", "muzzle_flash", "drops_on_ground",
    "player_pos", "player_aim", "player_facing", "player_weapon",
    "debug_mode", "flows", "squad", "noises", "auto_aim", "_lock_info",
    "aim_cone_deg", "CELL_PX", "TRACER_TTL",
]
# 排除局部变量同名的风险：逐个确认这些名字不是 _draw 里的局部变量
local_names = set(re.findall(r"\bvar\s+([a-zA-Z_]\w*)", draw_body))
clash = [n for n in SCENE_MEMBERS if n in local_names]
if clash:
    raise SystemExit("❌ 这些名字既是场景成员又是 _draw 局部变量，不能无脑加前缀：%s" % clash)

alt = "|".join(re.escape(n) for n in SCENE_MEMBERS)
# 前面不能是 . 或标识符字符；后面不能是标识符字符
pat = re.compile(r"(?<![\w.])(?:" + alt + r")(?![\w])")


def prefix(m: re.Match) -> str:
    return "scene." + m.group(0)


new_draw = pat.sub(prefix, draw_body)
new_cell = pat.sub(prefix, cell_rect_body)      # _cell_rect 体里也用 CELL_PX

# 统计替换了多少处（便于自检）
n_draw = len(pat.findall(draw_body))
n_cell = len(pat.findall(cell_rect_body))

# ── 5. 生成 raid_drawer.gd ──
header = '''class_name RaidDrawer
extends Node2D

## 世界绘制 —— 从 `view/raid_scene.gd` 抽出来
##
## ─── 为什么抽 ───
## `_draw()` 是 raid_scene.gd 上最典型的**纯追加型**函数：
## 每加一个视觉元素（曳光、枪口火光、视野锥、血条…）都要往里塞一段。
## 1676 行的场景里它自己就占 181 行，是最大的单块冲突面。
##
## ─── 为什么是这个节点 ───
## 它是场景的**子 Node2D**，放在原点，所以绘制坐标系与父节点完全一致
## （父场景的 `_draw` 也是画在同一空间里）。
##
## ⚠️ **z 序**：子节点画在父节点**之上**，子节点之间按加入顺序。
##    所以这个 drawer 必须在 FxPool（粒子）**之前**加进场景，
##    才能保持"世界在下、粒子在上"的原观感。
##
## ─── 状态从哪来 ───
## `scene` 故意不加类型（duck typing）：用 Node2D 的话 GDScript 编译期
## 就拒绝 `scene.player_pos` 这类场景自定义成员。

## 宿主场景（RaidScene）
var scene = null

'''
parts = [header]
for c in colors:
    parts.append(c)
parts.append("")
parts.append("")
parts.append("## 逻辑格矩形 -> 世界像素矩形")
parts.append(new_cell)
parts.append("")
parts.append("")
parts.append(new_draw)
parts.append("")

OUT.write_text("\n".join(parts), encoding="utf-8")
SRC.write_text("\n".join(lines), encoding="utf-8")

print("✅ 已抽出 view/raid_drawer.gd")
print("   搬走 _draw（%d 行，加了 %d 处 scene. 前缀）" % (len(draw_body.split("\n")), n_draw))
print("   搬走 _cell_rect（%d 处前缀）" % n_cell)
print("   搬走 %d 个 C_* 颜色常量" % len(colors))
print("   raid_scene.gd: %d -> %d 行" % (len(src.split("\n")), len(lines)))
print()
print("⚠️ 还要手工接线：")
print("   · 场景加 var drawer: RaidDrawer，在 _setup_view 里【fx 之前】add_child")
print("   · queue_redraw() -> drawer.queue_redraw()")
