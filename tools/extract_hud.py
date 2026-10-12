# -*- coding: utf-8 -*-
"""把 HUD 从 raid_scene.gd 摘出去，改为委托给 view/raid_hud.gd

策略：
  · 按【函数边界】定位，不硬编码行号
  · 从文件【底部往顶部】改，避免行号漂移
  · 每一步都断言"确实匹配到了"，匹配不到就中止（不允许静默跳过）
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
F = ROOT / "view" / "raid_scene.gd"
src = F.read_text(encoding="utf-8")
lines = src.split("\n")

changes = []


def find_func(name: str) -> int:
    """返回顶层函数的起始行号（0-based）；找不到抛异常"""
    for i, l in enumerate(lines):
        if l.startswith("func " + name + "("):
            return i
    raise SystemExit("❌ 找不到函数 %s" % name)


def func_end(start: int) -> int:
    """返回该函数结束后的第一个行号（0-based，指向下一个顶层 func 或文件尾）"""
    for j in range(start + 1, len(lines)):
        if lines[j].startswith("func "):
            return j
    return len(lines)


# ═══════════════ 1) 删除 _set_label + _cache_* 段（文件末尾）═══════════════
setlabel = find_func("_set_label")
# 往上吃掉紧随其后的 _cache_* 声明
top = setlabel
while top > 0 and (lines[top - 1].strip() == "" or lines[top - 1].startswith("var _cache_")):
    top -= 1
end = len(lines)
del lines[top:end]
changes.append("删除 _set_label + _cache_* 段（%d 行）" % (end - top))

# ═══════════════ 2) 替换 _update_hud 的函数体 ═══════════════
u = find_func("_update_hud")
e = func_end(u)
lines[u:e] = [
    "func _update_hud() -> void:",
    "\t# HUD 的全部文本与提示都在 RaidHud 里（view/raid_hud.gd）——",
    "\t# 这里只留委托，避免 _update_hud 继续当「每加一个统计量都要改」的冲突点。",
    "\tif raid_hud != null:",
    "\t\traid_hud.refresh()",
    "",
    "",
]
changes.append("_update_hud -> 委托 raid_hud.refresh()")

# ═══════════════ 3) 删除 HUD 顶层变量 ═══════════════
drop = []
for name in ["var _toast_text", "var _toast_until", "var _toast_label",
             "var corpse_label", "var _hud_fs"]:
    for i, l in enumerate(lines):
        if l.startswith(name):
            drop.append(i)
            break
# 连同它们的注释行一起删
extra = []
for i in drop:
    j = i - 1
    while j >= 0 and (lines[j].strip().startswith("##") or lines[j].strip().startswith("#")):
        extra.append(j)
        j -= 1
for i in sorted(set(drop + extra), reverse=True):
    del lines[i]
changes.append("删除 HUD 顶层变量 %d 个（含注释共删 %d 行）" % (len(drop), len(set(drop + extra))))

# ═══════════════ 4) _toast 改为委托 ═══════════════
t = find_func("_toast")
te = func_end(t)
lines[t:te] = [
    "func _toast(msg: String, seconds: float = 2.0) -> void:",
    "\tif raid_hud != null:",
    "\t\traid_hud.toast(msg, seconds)",
    "",
    "",
]
changes.append("_toast -> 委托 raid_hud.toast()")

# ═══════════════ 5) _bag_key_hint 改为委托 ═══════════════
b = find_func("_bag_key_hint")
be = func_end(b)
lines[b:be] = [
    "func _bag_key_hint() -> String:",
    "\treturn raid_hud.bag_key_hint() if raid_hud != null else \"B\"",
    "",
    "",
]
changes.append("_bag_key_hint -> 委托 raid_hud.bag_key_hint()")

# ═══════════════ 6) _setup_view 里的 HUD 创建块换成 RaidHud ═══════════════
v = find_func("_setup_view")
ve = func_end(v)
# 找 hud = CanvasLayer.new() 那一行
hud_at = None
for i in range(v, ve):
    if lines[i].strip() == "hud = CanvasLayer.new()":
        hud_at = i
        break
if hud_at is None:
    raise SystemExit("❌ _setup_view 里找不到 hud = CanvasLayer.new()")
# 块结束：hud.add_child(_toast_label) 之后
block_end = None
for i in range(hud_at, ve):
    if lines[i].strip() == "hud.add_child(_toast_label)":
        block_end = i + 1
        break
if block_end is None:
    raise SystemExit("❌ 找不到 HUD 创建块的结尾")
lines[hud_at:block_end] = [
    "\t# ── HUD（Labels / toast / 尸体提示）全部在 view/raid_hud.gd ──",
    "\t# 抽出去的原因：_update_hud 是「纯追加型」函数，每加一个统计量都要改，",
    "\t# 是 raid_scene.gd 上最大的冲突面之一。",
    "\traid_hud = RaidHud.new()",
    "\traid_hud.scene = self",
    "\traid_hud.setup(_is_touch)",
    "\tadd_child(raid_hud)",
]
changes.append("_setup_view 的 HUD 创建块 -> RaidHud 实例")

# ═══════════════ 7) 顶层变量声明替换 ═══════════════
replaced = 0
for i, l in enumerate(lines):
    if l == "var hud: CanvasLayer":
        lines[i] = ("## 突袭 HUD（Labels / toast / 尸体提示）—— 实现在 view/raid_hud.gd\n"
                    "var raid_hud: RaidHud")
        replaced += 1
    elif l in ("var hud_label: Label", "var hint_label: Label", "var view_label: Label"):
        lines[i] = ""
        replaced += 1
if replaced < 4:
    raise SystemExit("❌ 只替换了 %d 个 HUD 变量声明（期望 4）" % replaced)
changes.append("顶层变量：hud -> raid_hud，删掉 3 个 Label 声明")

F.write_text("\n".join(lines), encoding="utf-8")
print("✅ raid_scene.gd 改造完成：")
for c in changes:
    print("   -", c)
print("   总行数：%d -> %d" % (len(src.split("\n")), len(lines)))
