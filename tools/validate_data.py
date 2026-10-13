#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
validate_data.py -- 数据契约校验器

校验 data/*.json 是否符合 data/SCHEMA.md。退出码 0 = 全部通过，1 = 有错误。

用法：
    python tools/validate_data.py            # 校验全部
    python tools/validate_data.py items      # 只校验 items.json
    python tools/validate_data.py -v         # 显示通过项详情

设计原则：契约在 SCHEMA.md，本文件是它的可执行版本。改 schema 必须同步改这里。
"""

import json
import sys
from pathlib import Path

# Windows 控制台默认用 GBK/ANSI 编码，中文输出会乱码。强制 stdout 走 UTF-8。
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"

# ─────────────────────────── 结果收集 ───────────────────────────

class Report:
    def __init__(self):
        self.errors = []
        self.warnings = []
        self.passes = []

    def err(self, where, msg):
        self.errors.append(f"{where}: {msg}")

    def warn(self, where, msg):
        self.warnings.append(f"{where}: {msg}")

    def ok(self, msg):
        self.passes.append(msg)

    def dump(self, verbose):
        for p in self.passes:
            if verbose:
                print(f"  \033[32mOK\033[0m   {p}")
        for w in self.warnings:
            print(f"  \033[33mWARN\033[0m {w}")
        for e in self.errors:
            print(f"  \033[31mERR\033[0m  {e}")


R = Report()

# ─────────────────────────── 工具函数 ───────────────────────────

def load(name, optional=False):
    """读 JSON，同时检查 BOM 与编码。返回 (数据, 错误)"""
    path = DATA / f"{name}.json"
    if not path.exists():
        if optional:
            return None
        R.err(name, f"文件不存在: {path}")
        return None

    raw = path.read_bytes()
    if raw.startswith(b"\xef\xbb\xbf"):
        R.err(name, "文件带 UTF-8 BOM（契约要求无 BOM）")
        raw = raw[3:]

    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as e:
        R.err(name, f"不是合法 UTF-8: {e}")
        return None

    # 全角字符混入数字字段是常见坑，这里不做拦截只提示
    try:
        data = json.loads(text)
    except json.JSONDecodeError as e:
        R.err(name, f"JSON 解析失败: 第{e.lineno}行 {e.msg}")
        return None

    R.ok(f"{name}.json 解析成功（{len(data) if isinstance(data, list) else 'object'}）")
    return data


def req(obj, field, where, typ=None, minval=None, maxval=None, nonempty=False):
    """检查必需字段存在、类型、范围。返回 True 表示通过"""
    if field not in obj:
        R.err(where, f"缺少字段 '{field}'")
        return False
    v = obj[field]

    if typ is not None:
        if typ is int and isinstance(v, bool):
            R.err(where, f"'{field}' 应为整数，实为 bool")
            return False
        if typ is float and isinstance(v, bool):
            R.err(where, f"'{field}' 应为数字，实为 bool")
            return False
        if typ is int and not isinstance(v, int):
            R.err(where, f"'{field}' 应为整数，实为 {type(v).__name__}")
            return False
        if typ is float and not isinstance(v, (int, float)):
            R.err(where, f"'{field}' 应为数字，实为 {type(v).__name__}")
            return False
        if typ is str and not isinstance(v, str):
            R.err(where, f"'{field}' 应为字符串，实为 {type(v).__name__}")
            return False
        if typ is list and not isinstance(v, list):
            R.err(where, f"'{field}' 应为数组，实为 {type(v).__name__}")
            return False

    if nonempty and isinstance(v, str) and not v.strip():
        R.err(where, f"'{field}' 不能为空")
        return False

    if minval is not None and isinstance(v, (int, float)) and v < minval:
        R.err(where, f"'{field}' = {v} 小于下限 {minval}")
        return False

    if maxval is not None and isinstance(v, (int, float)) and v > maxval:
        R.err(where, f"'{field}' = {v} 超过上限 {maxval}")
        return False

    return True


def check_unique(arr, key, name):
    seen = {}
    for i, o in enumerate(arr):
        k = o.get(key)
        if k in seen:
            R.err(name, f"{key} 重复: '{k}'（第 {seen[k]} 与第 {i} 项）")
        else:
            seen[k] = i
    return seen


def check_enum(arr, key, allowed, name):
    for i, o in enumerate(arr):
        v = o.get(key)
        if v not in allowed:
            R.err(name, f"第{i}项 '{o.get('id','?')}': {key}='{v}' 不在允许集合 {sorted(allowed)}")


def check_stage(arr, name):
    for i, o in enumerate(arr):
        s = o.get("stage", "B")
        if s not in ("B", "A", "C"):
            R.err(name, f"第{i}项 '{o.get('id','?')}': stage='{s}' 必须是 B/A/C")


# ─────────────────────────── 各表校验 ───────────────────────────

# ⚠️ 2026-10-12 新增 "weapon"：武器也做成 item（id 与 weapons.json 一致），
#    这样"敌人掉枪 -> 进背包 -> 装备"链路才统一。战斗数值仍以 weapons.json 为准。
ITEM_CATS = {"medical", "ammo", "armor", "backpack", "consumable",
             "valuables", "key", "misc", "weapon"}


def val_items(data):
    name = "items"
    if not isinstance(data, list):
        R.err(name, "顶层必须是数组")
        return {}
    for i, o in enumerate(data):
        w = f"{name}[{i}] {o.get('id','?')}"
        req(o, "id", w, str, nonempty=True)
        req(o, "name", w, str, nonempty=True)
        req(o, "name_en", w, str, nonempty=True)
        req(o, "category", w, str)
        req(o, "weight", w, float, minval=0)
        req(o, "stack_max", w, int, minval=1)
        req(o, "icon", w, str, nonempty=True)
        req(o, "value", w, int, minval=0)
        req(o, "desc", w, str, nonempty=True)
        if len(o.get("desc", "")) > 20:
            R.warn(w, f"desc 超过 20 字（{len(o['desc'])}）")
        icon = o.get("icon", "")
        if icon and not icon.startswith("res://"):
            R.err(w, f"icon 必须以 res:// 开头: {icon}")

        # ── 弹药弹型（2026-10-13）：标准 / 穿甲 / 肉伤 ──
        # pen = 穿甲值(0~10)，flesh = 对【无甲】目标的伤害倍率。
        # 设计意图：穿甲弹 pen 高 flesh 低（打有甲强），肉伤弹反之，标准弹居中。
        if o.get("category") == "ammo":
            at = o.get("ammo_type")
            if at is None:
                R.warn(w, "弹药没有 ammo_type（建议 standard/ap/hp）")
            elif at not in ("standard", "ap", "hp"):
                R.err(w, f"ammo_type='{at}' 必须是 standard/ap/hp")
            pv = o.get("pen")
            if pv is None:
                R.warn(w, "弹药没有 pen（穿甲值 0~10）")
            elif not isinstance(pv, (int, float)) or not (0 <= pv <= 10):
                R.err(w, f"pen={pv} 应为 0~10 的数字")
            fv = o.get("flesh")
            if fv is None:
                R.warn(w, "弹药没有 flesh（对无甲倍率）")
            elif not isinstance(fv, (int, float)) or fv <= 0:
                R.err(w, f"flesh={fv} 应为 >0 的数字")

        # ── 装备耐久 / 护甲值（2026-10-13 损耗系统）──
        for f in ("durability", "armor"):
            if f not in o:
                continue
            if not isinstance(o[f], (int, float)) or isinstance(o[f], bool):
                R.err(w, f"'{f}' 应为数字")
            elif o[f] < 0:
                R.err(w, f"'{f}' = {o[f]} 不能为负")

        # ── 背包容量（2026-10-13 「3a」补全：装备背包 → 本局容量/负重）──
        # carry_slots / carry_weight 是**可选**字段：不填则本局回退到默认 12 格 /
        # 升级负重上限。填了就必须合规。具体数值由【平衡专家】调。
        if o.get("category") == "backpack":
            for f, caster, lo in (("carry_slots", int, 1), ("carry_weight", float, 0.0)):
                if f not in o:
                    R.warn(w, f"背包没有 {f}（将回退默认；建议填以启用该背包的容量）")
                    continue
                v = o[f]
                if isinstance(v, bool) or not isinstance(v, (int, float)):
                    R.err(w, f"'{f}' 应为数字")
                elif v < lo:
                    R.err(w, f"'{f}' = {v} 应 >= {lo}")

    check_enum(data, "category", ITEM_CATS, name)
    check_unique(data, "id", name)
    check_stage(data, name)

    # ── 弹型平衡启发式（契约级约束，防止有人把穿甲弹写成"全能弹"）──
    # 穿甲弹：pen 必须高于标准弹、flesh 必须低于标准弹；肉伤弹反之。
    ammos = [o for o in data if o.get("category") == "ammo"
             and isinstance(o.get("pen"), (int, float)) and isinstance(o.get("flesh"), (int, float))]
    std = [o for o in ammos if o.get("ammo_type") == "standard"]
    if std:
        ref_pen = sum(o["pen"] for o in std) / len(std)
        ref_flesh = sum(o["flesh"] for o in std) / len(std)
        for o in ammos:
            if o.get("ammo_type") == "ap":
                if o["pen"] <= ref_pen:
                    R.err(o["id"], f"穿甲弹 pen={o['pen']} 必须高于标准弹均值 {ref_pen:.1f}")
                if o["flesh"] >= ref_flesh:
                    R.err(o["id"], f"穿甲弹 flesh={o['flesh']} 必须低于标准弹均值 {ref_flesh:.2f}")
            elif o.get("ammo_type") == "hp":
                if o["pen"] >= ref_pen:
                    R.err(o["id"], f"肉伤弹 pen={o['pen']} 必须低于标准弹均值 {ref_pen:.1f}")
                if o["flesh"] <= ref_flesh:
                    R.err(o["id"], f"肉伤弹 flesh={o['flesh']} 必须高于标准弹均值 {ref_flesh:.2f}")
        R.ok(f"{name}: 弹型平衡通过（标准 pen={ref_pen:.1f}/flesh={ref_flesh:.2f}）")

    R.ok(f"{name}: {len(data)} 条，字段/枚举/唯一性通过")
    return {o["id"]: o for o in data if "id" in o}


def val_weapons(data, items):
    name = "weapons"
    if not isinstance(data, list):
        R.err(name, "顶层必须是数组")
        return
    for i, o in enumerate(data):
        w = f"{name}[{i}] {o.get('id','?')}"
        for f in ("id", "name", "name_en", "category", "ammo_id", "icon"):
            req(o, f, w, str, nonempty=True)
        for f in ("damage", "rpm", "mag_size", "range_m", "value"):
            req(o, f, w, int, minval=1 if f != "value" else 0)
        for f in ("reload_time", "spread_deg", "recoil_v", "recoil_h", "weight"):
            req(o, f, w, float, minval=0)
        # 交叉引用
        aid = o.get("ammo_id")
        if aid:
            if aid not in items:
                R.err(w, f"ammo_id='{aid}' 在 items.json 中不存在")
            elif items[aid].get("category") != "ammo":
                R.err(w, f"ammo_id='{aid}' 的 category 不是 ammo")

    check_enum(data, "category", {"weapon"}, name)
    check_unique(data, "id", name)
    check_stage(data, name)

    # 平衡直觉：步枪族射程最远，霰弹枪族最近且散布最大。
    # 按 id 是否含 "rifle"/"shotgun" 判定族，而非锁定某个固定 id，
    # 这样同族新增武器（如 weapon_shotgun_auto）不会误报。
    if len(data) >= 3:
        by_id = {o["id"]: o for o in data if "id" in o}
        rng = {k: v.get("range_m", 0) for k, v in by_id.items()}
        spr = {k: v.get("spread_deg", 0) for k, v in by_id.items()}
        if rng:
            far = max(rng, key=rng.get)
            if "rifle" not in far:
                R.warn(name, f"射程最远的不是步枪族（是 {far}），请确认符合设计意图")
            near = min(rng, key=rng.get)
            if "shotgun" not in near:
                R.warn(name, f"射程最近的不是霰弹枪族（是 {near}），请确认符合设计意图")
        if spr and "shotgun" not in max(spr, key=spr.get):
            R.warn(name, f"散布最大的不是霰弹枪族（是 {max(spr, key=spr.get)}），请确认符合设计意图")

    R.ok(f"{name}: {len(data)} 条，交叉引用通过")


def val_enemies(data):
    name = "enemies"
    if not isinstance(data, list):
        R.err(name, "顶层必须是数组")
        return
    for i, o in enumerate(data):
        w = f"{name}[{i}] {o.get('id','?')}"
        for f in ("id", "name", "name_en", "archetype", "sprite"):
            req(o, f, w, str, nonempty=True)
        for f in ("hp", "sight_range_m", "sight_angle_deg", "hear_range_m",
                  "give_up_dist_m", "damage", "loot_value_avg"):
            req(o, f, w, int, minval=1 if f in ("hp", "sight_range_m", "sight_angle_deg", "damage") else 0)
        for f in ("move_speed", "reaction_time", "attack_cooldown"):
            req(o, f, w, float, minval=0)

        req(o, "sight_angle_deg", w, int, minval=1, maxval=360)

        sr, gu = o.get("sight_range_m"), o.get("give_up_dist_m")
        if isinstance(sr, int) and isinstance(gu, int) and gu < sr:
            R.err(w, f"give_up_dist_m({gu}) 应 >= sight_range_m({sr})")

        # 关键平衡约束：远程敌人的反应时间不得低于 0.25 秒
        if o.get("archetype") == "ranged" and isinstance(o.get("reaction_time"), (int, float)):
            if o["reaction_time"] < 0.25:
                R.err(w, f"ranged 的 reaction_time={o['reaction_time']} < 0.25 —— 会被玩家感知为不公平")

        # 护甲值（2026-10-13）：0~10，0 = 无甲。穿甲弹/肉伤弹就是围绕它做取舍的。
        if "armor" in o:
            av = o["armor"]
            if not isinstance(av, (int, float)) or isinstance(av, bool):
                R.err(w, "'armor' 应为数字")
            elif not (0 <= av <= 10):
                R.err(w, f"armor={av} 应在 0~10")

        # 类型配色（2026-10-13 真机反馈 #3）：不同敌人要有不同的身份色。
        # 给了就必须是合法的 "#rrggbb" / "#rrggbbaa"；没给只警告
        # （代码会按 id 稳定派生，仍然可区分，所以不算错误）。
        cv = o.get("color")
        if cv is None or cv == "":
            R.warn(w, "缺 'color' —— 将按 id 派生身份色（建议显式指定，便于配色统一）")
        elif not isinstance(cv, str) or len(cv) not in (7, 9) or not cv.startswith("#") \
                or any(c not in "0123456789abcdefABCDEF" for c in cv[1:]):
            R.err(w, f"color={cv!r} 必须是 '#rrggbb' 或 '#rrggbbaa'")

    check_enum(data, "archetype", {"melee", "ranged"}, name)
    check_unique(data, "id", name)
    check_stage(data, name)

    arche = {o.get("archetype") for o in data}
    for need in ("melee", "ranged"):
        if need not in arche:
            R.warn(name, f"没有 archetype='{need}' 的敌人，B 阶段建议两种都覆盖")

    R.ok(f"{name}: {len(data)} 条，平衡约束通过")
    return {o["id"] for o in data if "id" in o}


def val_loot(data, items):
    name = "loot_tables"
    if not isinstance(data, list):
        R.err(name, "顶层必须是数组")
        return set()
    for i, o in enumerate(data):
        w = f"{name}[{i}] {o.get('id','?')}"
        req(o, "id", w, str, nonempty=True)
        req(o, "name", w, str, nonempty=True)
        if not req(o, "entries", w, list):
            continue
        if len(o["entries"]) < 1:
            R.err(w, "entries 不能为空")
        for j, e in enumerate(o["entries"]):
            ew = f"{w}.entries[{j}]"
            req(e, "item_id", ew, str, nonempty=True)
            req(e, "weight", ew, int, minval=1)
            req(e, "min", ew, int, minval=0)
            req(e, "max", ew, int, minval=0)
            if isinstance(e.get("min"), int) and isinstance(e.get("max"), int) and e["min"] > e["max"]:
                R.err(ew, f"min({e['min']}) > max({e['max']})")
            iid = e.get("item_id")
            if iid and iid not in items:
                R.err(ew, f"item_id='{iid}' 在 items.json 中不存在")

    check_unique(data, "id", name)
    check_stage(data, name)
    R.ok(f"{name}: {len(data)} 条，条目交叉引用通过")
    return {o["id"] for o in data if "id" in o}


def val_rooms(data, loot, containers):
    name = "rooms"
    if not isinstance(data, list):
        R.err(name, "顶层必须是数组")
        return set()
    for i, o in enumerate(data):
        w = f"{name}[{i}] {o.get('id','?')}"
        req(o, "id", w, str, nonempty=True)
        req(o, "name", w, str, nonempty=True)
        req(o, "room_type", w, str)
        for f in ("min_count", "max_count", "enemy_budget_min", "enemy_budget_max", "min_graph_dist"):
            req(o, f, w, int, minval=0)
        req(o, "loot_table_id", w, str, nonempty=True)

        if isinstance(o.get("min_count"), int) and isinstance(o.get("max_count"), int):
            if o["min_count"] > o["max_count"]:
                R.err(w, f"min_count({o['min_count']}) > max_count({o['max_count']})")
        if isinstance(o.get("enemy_budget_min"), int) and isinstance(o.get("enemy_budget_max"), int):
            if o["enemy_budget_min"] > o["enemy_budget_max"]:
                R.err(w, "enemy_budget_min > enemy_budget_max")

        lt = o.get("loot_table_id")
        if lt and lt not in loot:
            R.err(w, f"loot_table_id='{lt}' 在 loot_tables.json 中不存在")

        # ── 容器挂靠（2026-10-13）：该房间生成哪些容器、各几个 ──
        raw_c = o.get("containers", [])
        if not isinstance(raw_c, list):
            R.err(w, "containers 必须是数组")
        else:
            for j, c in enumerate(raw_c):
                cw = f"{w}.containers[{j}]"
                req(c, "container_id", cw, str, nonempty=True)
                req(c, "count_min", cw, int, minval=0)
                req(c, "count_max", cw, int, minval=0)
                if isinstance(c.get("count_min"), int) and isinstance(c.get("count_max"), int):
                    if c["count_min"] > c["count_max"]:
                        R.err(cw, f"count_min({c['count_min']}) > count_max({c['count_max']})")
                cid = c.get("container_id")
                if cid and cid not in containers:
                    R.err(cw, f"container_id='{cid}' 在 containers.json 中不存在")
        # 主题分配权重：多个 common 类房间类型靠它按比例分配
        if "weight" in o and not isinstance(o["weight"], int):
            R.err(w, "'weight' 应为整数")

    check_enum(data, "room_type", {"spawn", "common", "extract"}, name)
    check_unique(data, "id", name)
    check_stage(data, name)

    # ── 地图生成硬约束（SCHEMA §5 / T-34）──
    spawns = [o for o in data if o.get("room_type") == "spawn"]
    extracts = [o for o in data if o.get("room_type") == "extract"]

    if len(spawns) != 1:
        R.err(name, f"必须恰好有 1 个 spawn 房间类型，实为 {len(spawns)}")
    for s in spawns:
        if s.get("min_count") != 1 or s.get("max_count") != 1:
            R.err(f"{name}/{s.get('id')}", "spawn 的 min_count 与 max_count 必须都为 1")
        if s.get("min_graph_dist") != 0:
            R.warn(f"{name}/{s.get('id')}", "spawn 的 min_graph_dist 建议为 0")

    if not extracts:
        R.err(name, "没有 extract 房间类型")
    for e in extracts:
        if e.get("min_count", 0) < 2:
            R.err(f"{name}/{e.get('id')}", f"extract 的 min_count={e.get('min_count')} 必须 >= 2（撤离点至少两个）")
        if e.get("min_graph_dist", 0) < 4:
            R.err(f"{name}/{e.get('id')}", f"extract 的 min_graph_dist={e.get('min_graph_dist')} 必须 >= 4（防止出生即撤离）")

    R.ok(f"{name}: {len(data)} 条，地图硬约束通过")
    return {o["id"] for o in data if "id" in o}


# ── 容器类型（2026-10-13）──
# 容器是"房间里真正能搜的东西"。房间类型通过 room.containers 挂靠它，
# 它自己再指向一张 loot_table —— 这就是「容器 ↔ 房间 ↔ 物品」三级对应关系。
def val_containers(data, loot):
    name = "containers"
    if not isinstance(data, list):
        R.err(name, "顶层必须是数组")
        return set()
    for i, o in enumerate(data):
        w = f"{name}[{i}] {o.get('id','?')}"
        for f in ("id", "name", "loot_table_id"):
            req(o, f, w, str, nonempty=True)
        req(o, "capacity", w, int, minval=1)
        req(o, "search_time", w, float, minval=0)
        lt = o.get("loot_table_id")
        if lt and lt not in loot:
            R.err(w, f"loot_table_id='{lt}' 在 loot_tables.json 中不存在")
    check_unique(data, "id", name)
    check_stage(data, name)
    R.ok(f"{name}: {len(data)} 条，交叉引用通过")
    return {o["id"] for o in data if "id" in o}


# ── 地图主题（2026-10-13）──
# 森林 / 城区 / 军事基地…… 每个主题决定：地图多大、房间配额、敌人池、白模色调。
def val_maps(data, room_ids, enemy_ids):
    name = "maps"
    if not isinstance(data, list):
        R.err(name, "顶层必须是数组")
        return
    for i, o in enumerate(data):
        w = f"{name}[{i}] {o.get('id','?')}"
        for f in ("id", "name", "desc", "tile_theme"):
            req(o, f, w, str, nonempty=True)
        req(o, "map_w", w, int, minval=8, maxval=128)
        req(o, "map_h", w, int, minval=8, maxval=128)
        req(o, "enemy_density", w, float, minval=0)

        rw = o.get("room_weights", {})
        if not isinstance(rw, dict) or not rw:
            R.err(w, "room_weights 必须是非空对象")
        else:
            for k in rw:
                if k not in room_ids:
                    R.err(w, f"room_weights 里的 '{k}' 在 rooms.json 中不存在")
        ew = o.get("enemy_weights", {})
        if not isinstance(ew, dict) or not ew:
            R.err(w, "enemy_weights 必须是非空对象")
        else:
            for k in ew:
                if k not in enemy_ids:
                    R.err(w, f"enemy_weights 里的 '{k}' 在 enemies.json 中不存在")
    check_unique(data, "id", name)
    check_stage(data, name)
    R.ok(f"{name}: {len(data)} 条，主题交叉引用通过")


RECIPE_STATIONS = {"bench", "forge", "lab", "kitchen"}


def val_recipes(data, items):
    name = "recipes"
    if not isinstance(data, list):
        R.err(name, "顶层必须是数组")
        return
    for i, o in enumerate(data):
        w = f"{name}[{i}] {o.get('id','?')}"
        for f in ("id", "name", "name_en", "station", "output_item_id"):
            req(o, f, w, str, nonempty=True)
        req(o, "output_count", w, int, minval=1)
        req(o, "time", w, float, minval=0)

        raw = o.get("inputs")
        if not isinstance(raw, list):
            R.err(w, "inputs 必须是数组")
        else:
            if len(raw) < 1:
                R.err(w, "inputs 不能为空")
            for j, g in enumerate(raw):
                gw = f"{w}.inputs[{j}]"
                req(g, "item_id", gw, str, nonempty=True)
                req(g, "count", gw, int, minval=1)
                iid = g.get("item_id")
                if iid and iid not in items:
                    R.err(gw, f"item_id='{iid}' 在 items.json 中不存在")

        oid = o.get("output_item_id")
        if oid and oid not in items:
            R.err(w, f"output_item_id='{oid}' 在 items.json 中不存在")

    check_enum(data, "station", RECIPE_STATIONS, name)
    check_unique(data, "id", name)
    check_stage(data, name)
    R.ok(f"{name}: {len(data)} 条，交叉引用通过")


# ─────────────────────────── 主流程 ───────────────────────────

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    verbose = "-v" in sys.argv or "--verbose" in sys.argv

    print("\n数据契约校验  == data/SCHEMA.md ==\n")

    items_raw = load("items")
    weapons_raw = load("weapons")
    enemies_raw = load("enemies")
    loot_raw = load("loot_tables")
    # containers / maps 是 C 阶段才引入的表，缺失不算错误（契约 §8/§9）
    containers_raw = load("containers", optional=True)
    rooms_raw = load("rooms")
    maps_raw = load("maps", optional=True)
    recipes_raw = load("recipes", optional=True)

    items = val_items(items_raw) if items_raw is not None else {}
    if weapons_raw is not None:
        val_weapons(weapons_raw, items)
    enemy_ids = val_enemies(enemies_raw) if enemies_raw is not None else set()
    loot_ids = val_loot(loot_raw, items) if loot_raw is not None else set()
    container_ids = val_containers(containers_raw, loot_ids) if containers_raw is not None else set()
    room_ids = val_rooms(rooms_raw, loot_ids, container_ids) if rooms_raw is not None else set()
    if maps_raw is not None:
        val_maps(maps_raw, room_ids, enemy_ids)
    if recipes_raw is not None:
        val_recipes(recipes_raw, items)

    print()
    R.dump(verbose)

    n_err, n_warn = len(R.errors), len(R.warnings)
    print()
    if n_err == 0:
        print(f"\033[32m通过\033[0m：0 错误，{n_warn} 警告")
        return 0
    print(f"\033[31m失败\033[0m：{n_err} 错误，{n_warn} 警告")
    return 1


if __name__ == "__main__":
    sys.exit(main())
