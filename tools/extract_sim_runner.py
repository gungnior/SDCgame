# -*- coding: utf-8 -*-
"""从 raid_scene.gd 抽出模拟调度 -> view/raid_sim_runner.gd

搬：_tick_player / _tick_enemies / _update_auto_aim / _try_fire（合计 ~324 行）
这四个构成一个**调用图闭合**的单元（后两个只被前两个调用），所以一起搬。

做法与 drawer 抽取相同：单次正则替换加 `scene.` 前缀。

⚠️ 这是**冲突面削减**而不是内聚性改进 ——
   新模块仍然通过 `scene.xxx` 读写同样的状态。
   但对目标（让两个人能在不同文件上并行开工）是有效的：
   调 AI / 战斗的手感不再和场景搭建 / UI 胶水抢同一个文件。
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "view" / "raid_scene.gd"
OUT = ROOT / "view" / "raid_sim_runner.gd"

src = SRC.read_text(encoding="utf-8")
lines = src.split("\n")

MOVE = {
    "_tick_player": "tick_player",
    "_tick_enemies": "tick_enemies",
    "_update_auto_aim": "update_auto_aim",
    "_try_fire": "try_fire",
}

# ⚠️ 顶层声明的样子。
#    这个文件把 `var` / `const` **夹在函数之间**（不是全放在文件头），
#    所以"函数体"的右边界不能简单取"下一个 func" ——
#    否则那些类级声明会被当成前一个函数的函数体一起搬走。
#    （本次就在这里栽了两次：`var _roles_cooldown`、
#      `const SQUAD_ROLES_INTERVAL`、`var _lock_info` 都被误搬。）
TOP_DECL = re.compile(r"^(?:var|const|signal|enum|class_name|extends|@\w)")


def func_bounds(start: int) -> int:
    """返回函数体的结束行（不含），在"下一个 func"与"下一个顶层声明"里取先到的。"""
    for j in range(start + 1, len(lines)):
        if lines[j].startswith("func ") or TOP_DECL.match(lines[j]):
            return j
    return len(lines)


# ── 1. 取出四个函数（按它们在文件里出现的顺序，保证依赖顺序不乱）──
found = {}
order = []
i = 0
while i < len(lines):
    if lines[i].startswith("func "):
        name = lines[i].split("(")[0].replace("func ", "").strip()
        if name in MOVE:
            e = func_bounds(i)
            # 往前吃掉紧贴 func 的连续注释行。
            #
            # ⚠️ 这里连着踩了两次：
            #   ① 第一版遇到 `## 注释` 就回退，但注释和 func 之间**还夹着一行
            #      `const SQUAD_ROLES_INTERVAL := 0.4`** —— 于是 const 被一起搬走，
            #      还被打上前缀变成 `const scene.SQUAD_ROLES_INTERVAL := 0.4`（语法错误）。
            #   ② 第二版"只吃连续注释行"仍然不对：`lines[top:e]` 是**区间切片**，
            #      中间夹着的东西照样会进来。
            #   现在改成：**只有紧贴在 func 上一行开始、连续到顶都是注释时才回退**，
            #   碰到空行就停（正常代码里注释块与 func 之间没有空行）。
            top = i
            while top > 0 and lines[top - 1].lstrip().startswith("#"):
                top -= 1
            # 再确认一下 top..i 之间确实只有注释，否则干脆不回退，
            # 免得把不属于这个函数的东西搬走。
            if any(not lines[k].lstrip().startswith("#") for k in range(top, i)):
                top = i
            found[name] = "\n".join(lines[top:e]).rstrip("\n")
            order.append((top, e, name))
            del lines[top:e]
            i = top
            continue
    i += 1

missing = [k for k in MOVE if k not in found]
if missing:
    raise SystemExit("❌ 没找到: %s" % missing)

# ── 2. 场景成员 + 场景方法（跑依赖分析得出的，不是猜的）──
MEMBERS = [
    "CELL_PX", "NOISE_QUIET", "NOISE_LOUD", "PLAYER_SPEED", "TRACER_TTL",
    "GRACE_SECONDS", "SQUAD_ROLES_INTERVAL", "AUTO_AIM_TURN_DEG",
    "_firing", "_move_input", "_step_accum", "game_paused",
    "medical", "noises", "player_aim", "player_facing", "player_pos",
    "player_weapon", "raid", "touch", "vitals",
    "_hearing_cache", "_prev_shots", "_rng", "_time",
    "agents", "bullets", "flows", "gen", "muzzle_flash", "squad",
    "auto_aim", "fx",
]
METHODS = [
    "_aim_push", "_aim_targets", "_floor_material", "_mouse_aiming",
    "_read_move_input", "_spawn_corpse", "_spread_radius_factor",
    "_walkable", "_weapon_kind",
]
NAMES = MEMBERS + METHODS

alt = "|".join(re.escape(n) for n in sorted(NAMES, key=len, reverse=True))
pat_prefix = re.compile(r"(?<![\w.])(?:" + alt + r")(?![\w])")

# 被搬走的四个函数：内部互相调用要变成"本类内的方法调用"
alt_fn = "|".join(re.escape(k) for k in MOVE)
pat_fn = re.compile(r"(?<![\w.])(?:" + alt_fn + r")(?=\s*\()")


def transform(body: str) -> str:
    """加 scene. 前缀 + 改公开方法名。
    ⚠️ **不改注释行** —— 第一版没跳过注释，把 `sim/combat/auto_aim.gd`
       这类路径里的 `auto_aim` 也改成了 `scene.auto_aim`，注释被改坏。
    """
    out_lines = []
    for line in body.split("\n"):
        stripped = line.lstrip()
        if stripped.startswith("#"):
            out_lines.append(line)          # 整行注释原样保留
            continue
        # 行尾注释单独摘出来，只对代码部分做替换
        code, sep, comment = line.partition(" #")
        code = pat_prefix.sub(lambda m: "scene." + m.group(0), code)
        code = pat_fn.sub(lambda m: MOVE[m.group(0)], code)
        out_lines.append(code + sep + comment)
    return "\n".join(out_lines)


new_bodies = {n: transform(b) for n, b in found.items()}
n_prefix = {n: len(pat_prefix.findall(b)) for n, b in found.items()}

# ── 3. 场景里剩下对这四个函数的引用，改成 sim_runner.xxx ──
remaining = "\n".join(lines)
for old, new in MOVE.items():
    remaining = re.sub(r"(?<![\w.])" + re.escape(old) + r"(?=\s*\()",
                       "sim_runner." + new, remaining)
lines = remaining.split("\n")

# ── 4. 生成 raid_sim_runner.gd ──
header = '''class_name RaidSimRunner
extends RefCounted

## 模拟调度 —— 从 `view/raid_scene.gd` 抽出来
##
## 搬来的是四个**调用图闭合**的函数：
##   tick_player -> update_auto_aim / try_fire
##   tick_enemies
## （`update_auto_aim` 与 `try_fire` 只被前两个调用，所以一起搬才闭合。）
##
## ─── 这解决的是什么问题 ───
## `raid_scene.gd` 曾 1676 行，50% 的提交都要改它。
## 调 AI / 战斗手感 和 场景搭建 / UI 胶水 挤在同一个文件里，
## 两个人没法同时开工。现在前者在这个文件里，后者在场景里。
##
## ⚠️ 说清楚：这是**冲突面削减**，**不是内聚性改进** ——
##    本模块仍然通过 `scene.xxx` 读写同样的状态，耦合没变，
##    只是把"往哪儿写代码"分开了。
##
## ─── 为什么这个抽取可以被严格验证 ───
## 固定地图种子 + 固定 delta 后，第 300 帧的**像素**能验证**整个模拟**：
## 只要 tick 的行为有一点点不同，实体位置就会变，像素就不同。
## 这比验证渲染抽取还强（渲染只看一帧，模拟是累积的）。

## 宿主场景（RaidScene）。无类型：duck typing 读场景自定义成员。
var scene = null

'''

parts = [header]
for _, _, name in order:
    parts.append(new_bodies[name])
    parts.append("")
    parts.append("")

OUT.write_text("\n".join(parts).rstrip("\n") + "\n", encoding="utf-8")
SRC.write_text("\n".join(lines), encoding="utf-8")

print("✅ 已抽出 view/raid_sim_runner.gd")
for _, _, name in order:
    print("   %-20s -> %-20s  %3d 行, %d 处 scene. 前缀"
          % (name, MOVE[name], len(found[name].split("\n")), n_prefix[name]))
print("   raid_scene.gd: %d -> %d 行" % (len(src.split("\n")), len(lines)))
print()
print("⚠️ 还要手工接线：场景加 var sim_runner，并在 _setup_view 里 new + 设 scene")
