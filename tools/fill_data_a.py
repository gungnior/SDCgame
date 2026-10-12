# -*- coding: utf-8 -*-
"""② 数据填充：枪械 3->6 / 物品 15->50 / 敌人 2->4

设计约束（全部来自 tools/validate_data.py 的可执行契约）：
  · items  必须有 id/name/name_en/category/weight/stack_max/icon/value/desc，
           desc <= 20 字，icon 以 res:// 开头，category 在 ITEM_CATS 内
  · weapons 必须有 ammo_id，且该 id 在 items 里且 category == "ammo"
           **平衡启发式**：射程最远必须是步枪、最近必须是霰弹枪、散布最大必须是霰弹枪
  · enemies 的 archetype 在 {melee, ranged}；**ranged 的 reaction_time >= 0.25**

stage 一律给 "A"：DataRegistry.load_all("A") 会加载 B+A。
掉落表里加 A 阶段物品是**安全**的 —— LootRoller 对未加载的物品 `continue` 跳过，
所以 B 阶段自动看不到、A 阶段自动出现（这就是"数据开关"的正确用法）。
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"


def load(name):
    return json.loads((DATA / name).read_text(encoding="utf-8"))


def save(name, obj):
    # 不用 BOM（项目卫生测试会查），缩进 2 与现有文件一致
    (DATA / name).write_text(
        json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


# ═══════════════════════ 武器 3 -> 6 ═══════════════════════
#
# 刻意落在现有包络内，避免触发平衡警告：
#   射程：霰弹枪 18 < 冲锋枪 42 < 轻机枪 70 < 精确射手 88 < 步枪 90
#   散布：霰弹枪 6.5 最大（其余 <= 2.8）
NEW_WEAPONS = [
    {
        "id": "weapon_smg", "name": "冲锋枪", "name_en": "SMG", "category": "weapon",
        "ammo_id": "ammo_pistol",
        "damage": 14, "rpm": 900, "mag_size": 35, "reload_time": 2.0,
        "spread_deg": 2.8, "range_m": 42, "recoil_v": 0.5, "recoil_h": 0.9,
        "weight": 2.4, "value": 600,
        "icon": "res://art/guns/weapon_smg/base.png", "stage": "A",
        "aim_cone_deg": 48.0,
    },
    {
        "id": "weapon_dmr", "name": "精确射手步枪", "name_en": "DMR",
        "category": "weapon", "ammo_id": "ammo_rifle",
        "damage": 58, "rpm": 120, "mag_size": 10, "reload_time": 2.8,
        "spread_deg": 0.4, "range_m": 88, "recoil_v": 2.2, "recoil_h": 0.5,
        "weight": 4.2, "value": 1400,
        "icon": "res://art/guns/weapon_dmr/base.png", "stage": "A",
        "aim_cone_deg": 38.0,
    },
    {
        "id": "weapon_lmg", "name": "轻机枪", "name_en": "LMG", "category": "weapon",
        "ammo_id": "ammo_rifle",
        "damage": 30, "rpm": 700, "mag_size": 75, "reload_time": 5.2,
        "spread_deg": 1.6, "range_m": 70, "recoil_v": 1.4, "recoil_h": 1.2,
        "weight": 6.8, "value": 1800,
        "icon": "res://art/guns/weapon_lmg/base.png", "stage": "A",
        "aim_cone_deg": 45.0,
    },
]


# ═══════════════════════ 物品 15 -> 50（补 35 条）═══════════════════════

def it(iid, name, en, cat, weight, stack, value, desc, treat=None):
    o = {
        "id": iid, "name": name, "name_en": en, "category": cat,
        "weight": weight, "stack_max": stack,
        "icon": "res://art/items/%s.png" % iid,
        "value": value, "desc": desc, "stage": "A",
    }
    if treat:
        o["treat"] = treat
    return o


NEW_ITEMS = [
    # ── medical +5 ──
    it("medical_surgical", "外科手术包", "Surgical Kit", "medical", 0.6, 2, 400,
       "回血极多，附带修甲", {"hp": 100, "time": 7.0, "bleed": True, "armor": 15}),
    it("medical_stim", "战斗兴奋剂", "Combat Stim", "medical", 0.1, 5, 220,
       "注射极快，回血少", {"hp": 15, "time": 0.8, "bleed": False}),
    it("medical_antibiotic", "抗生素", "Antibiotics", "medical", 0.15, 5, 180,
       "中速治疗并止血", {"hp": 30, "time": 3.0, "bleed": True}),
    it("medical_tourniquet", "止血带卷", "Tourniquet", "medical", 0.08, 8, 60,
       "只止血，回血很少", {"hp": 20, "time": 1.5, "bleed": True}),
    it("medical_splint", "夹板", "Splint", "medical", 0.2, 4, 90,
       "处理骨伤，回血极少", {"hp": 5, "time": 2.5, "bleed": False}),

    # ── armor +4（护甲：stack 1）──
    it("armor_helmet_light", "轻型头盔", "Light Helmet", "armor", 0.8, 1, 150,
       "轻便，防御有限"),
    it("armor_helmet_heavy", "重型头盔", "Heavy Helmet", "armor", 1.6, 1, 500,
       "重而可靠，影响负重"),
    it("armor_medium", "中型护甲", "Medium Armor", "armor", 4.5, 1, 400,
       "攻守平衡的选择"),
    it("armor_plate", "防弹插板", "Ballistic Plate", "armor", 2.2, 1, 300,
       "可替换插板，补甲用"),

    # ── backpack +2 ──
    it("backpack_assault", "突击背包", "Assault Pack", "backpack", 1.2, 1, 600,
       "容量与灵活兼顾"),
    it("backpack_large", "大容量背包", "Large Backpack", "backpack", 2.0, 1, 1100,
       "装得多，但也更重"),

    # ── consumable +5 ──
    it("consumable_energybar", "能量棒", "Energy Bar", "consumable", 0.1, 5, 35,
       "快速补充体力"),
    it("consumable_coffee", "速溶咖啡", "Instant Coffee", "consumable", 0.1, 3, 40,
       "提神，小幅恢复"),
    it("consumable_ration", "军用口粮", "Military Ration", "consumable", 0.5, 2, 90,
       "恢复量最高的食物"),
    it("consumable_cigarette", "香烟", "Cigarettes", "consumable", 0.05, 5, 55,
       "缓解疼痛，会上瘾"),
    it("consumable_vodka", "伏特加", "Vodka", "consumable", 0.6, 2, 70,
       "壮胆，减痛但手抖"),

    # ── valuables +16（卖钱为主）──
    it("valuables_screwdriver", "螺丝刀", "Screwdriver", "valuables", 0.3, 3, 60, "工具，能卖钱"),
    it("valuables_battery", "汽车电池", "Car Battery", "valuables", 8.0, 1, 220, "很重，但值钱"),
    it("valuables_copperwire", "铜线", "Copper Wire", "valuables", 0.5, 4, 130, "回收料"),
    it("valuables_capacitor", "电容", "Capacitor", "valuables", 0.2, 4, 260, "电子件"),
    it("valuables_goldchain", "金链", "Gold Chain", "valuables", 0.1, 3, 520, "纯金，好出手"),
    it("valuables_silvercoin", "银币", "Silver Coin", "valuables", 0.05, 8, 140, "收藏级银币"),
    it("valuables_painting", "油画", "Oil Painting", "valuables", 1.5, 1, 1600, "大件，占地方"),
    it("valuables_antique", "古董花瓶", "Antique Vase", "valuables", 2.0, 1, 1900, "易碎，价值高"),
    it("valuables_jewelry", "珠宝盒", "Jewelry Box", "valuables", 0.6, 1, 2400, "本图最值钱的之一"),
    it("valuables_camera", "老式相机", "Vintage Camera", "valuables", 0.8, 1, 700, "还能用"),
    it("valuables_radio", "军用电台", "Military Radio", "valuables", 1.8, 1, 850, "军用规格"),
    it("valuables_dogtag", "军牌", "Dog Tags", "valuables", 0.02, 10, 300, "每块都有名字"),
    it("valuables_watch_broken", "坏手表", "Broken Watch", "valuables", 0.1, 3, 45, "不值钱但能拆"),
    it("valuables_circuit", "电路板", "Circuit Board", "valuables", 0.3, 3, 380, "含稀有金属"),
    it("valuables_lens", "光学镜片", "Optical Lens", "valuables", 0.4, 2, 640, "精密光学件"),
    it("valuables_medal", "勋章", "Medal", "valuables", 0.1, 2, 950, "收藏家很想要"),

    # ── key +3 ──
    it("key_dorm", "宿舍钥匙", "Dorm Key", "key", 0.01, 1, 0, "开宿舍的门"),
    it("key_warehouse", "仓库钥匙", "Warehouse Key", "key", 0.01, 1, 0, "开仓库的门"),
    it("key_office", "办公室钥匙", "Office Key", "key", 0.01, 1, 0, "开办公室的门"),
]


# ═══════════════════════ 敌人 2 -> 4 ═══════════════════════
#
# ⚠️ ranged 的 reaction_time 有下限 0.25（EnemyDef.MIN_RANGED_REACTION）——
#    低于它会被玩家感知为"不公平"。
NEW_ENEMIES = [
    {
        "id": "enemy_raider", "name": "武装劫掠者", "name_en": "Raider",
        "archetype": "ranged", "hp": 130, "move_speed": 2.2,
        "sight_range_m": 16, "sight_angle_deg": 110, "hear_range_m": 18,
        "reaction_time": 0.60, "give_up_dist_m": 45,
        "damage": 14, "attack_cooldown": 0.55, "loot_value_avg": 180,
        "sprite": "res://art/enemies/enemy_raider/side/idle_00.png", "stage": "A",
    },
    {
        "id": "enemy_marksman", "name": "神射手", "name_en": "Marksman",
        "archetype": "ranged", "hp": 90, "move_speed": 1.5,
        "sight_range_m": 24, "sight_angle_deg": 70, "hear_range_m": 12,
        "reaction_time": 0.90, "give_up_dist_m": 55,
        "damage": 34, "attack_cooldown": 1.6, "loot_value_avg": 260,
        "sprite": "res://art/enemies/enemy_marksman/side/idle_00.png", "stage": "A",
    },
]


def main():
    # ── 武器 ──
    w = load("weapons.json")
    have = {x["id"] for x in w}
    added_w = [x for x in NEW_WEAPONS if x["id"] not in have]
    w.extend(added_w)
    save("weapons.json", w)

    # ── 物品 ──
    it_list = load("items.json")
    have_i = {x["id"] for x in it_list}
    added_i = [x for x in NEW_ITEMS if x["id"] not in have_i]
    it_list.extend(added_i)
    save("items.json", it_list)

    # ── 敌人 ──
    e = load("enemies.json")
    have_e = {x["id"] for x in e}
    added_e = [x for x in NEW_ENEMIES if x["id"] not in have_e]
    e.extend(added_e)
    save("enemies.json", e)

    # ── 掉落表：把新物品按稀有度分配进去 ──
    # B 阶段自动跳过（LootRoller 对未加载物品 continue），A 阶段自动出现。
    lt = load("loot_tables.json")
    by_id = {t["id"]: t for t in lt}

    def add_entry(table_id, item_id, weight, mn, mx):
        t = by_id.get(table_id)
        if t is None:
            return
        if any(en["item_id"] == item_id for en in t["entries"]):
            return
        t["entries"].append({"item_id": item_id, "weight": weight,
                             "min": mn, "max": mx})

    # 普通房间：常见消耗品 + 廉价杂项
    for iid, wgt, mn, mx in [
        ("medical_tourniquet", 20, 1, 2), ("consumable_energybar", 24, 1, 3),
        ("consumable_cigarette", 18, 1, 2), ("valuables_screwdriver", 14, 1, 2),
        ("valuables_watch_broken", 14, 1, 2), ("valuables_copperwire", 10, 1, 2),
        ("medical_antibiotic", 10, 1, 1), ("consumable_coffee", 12, 1, 2),
        ("valuables_silvercoin", 8, 1, 2), ("valuables_dogtag", 7, 1, 2),
    ]:
        add_entry("loot_common", iid, wgt, mn, mx)

    # 撤离点房间：高价值
    for iid, wgt, mn, mx in [
        ("valuables_jewelry", 5, 1, 1), ("valuables_antique", 6, 1, 1),
        ("valuables_painting", 6, 1, 1), ("valuables_medal", 9, 1, 1),
        ("valuables_lens", 10, 1, 1), ("medical_surgical", 12, 1, 1),
        ("armor_helmet_heavy", 7, 1, 1), ("backpack_large", 6, 1, 1),
        ("valuables_radio", 8, 1, 1), ("valuables_capacitor", 10, 1, 2),
        ("key_warehouse", 5, 1, 1), ("key_office", 4, 1, 1),
    ]:
        add_entry("loot_extract", iid, wgt, mn, mx)

    # 敌人掉落：弹药 + 药 + 廉价杂项（不放大件贵重品）
    for iid, wgt, mn, mx in [
        ("medical_tourniquet", 20, 1, 2), ("medical_stim", 8, 1, 1),
        ("consumable_energybar", 14, 1, 2), ("valuables_dogtag", 12, 1, 1),
        ("valuables_watch_broken", 10, 1, 1), ("armor_helmet_light", 6, 1, 1),
        ("armor_plate", 7, 1, 1), ("key_dorm", 5, 1, 1),
    ]:
        add_entry("loot_enemy_drop", iid, wgt, mn, mx)

    save("loot_tables.json", lt)

    print("武器  %d -> %d  (+%d)" % (len(w) - len(added_w), len(w), len(added_w)))
    print("物品  %d -> %d  (+%d)" % (len(it_list) - len(added_i), len(it_list), len(added_i)))
    print("敌人  %d -> %d  (+%d)" % (len(e) - len(added_e), len(e), len(added_e)))
    print("掉落表条目数:", {t["id"]: len(t["entries"]) for t in lt})


main()
