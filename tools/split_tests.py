# -*- coding: utf-8 -*-
"""把 test/run_tests.gd（3439 行 / 59 套件）拆成：框架 + test/suites/*.gd

原则：
  · 测试函数体**逐字节原样搬运**（只换文件，不改内容）——搬迁风险最低
  · 套件注册顺序**保持与原来一致**（输出顺序不变，方便对比）
  · 顺带修掉 4 个"定义了但从未注册"的测试函数
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "test" / "run_tests.gd"
OUT_DIR = ROOT / "test" / "suites"
OUT_DIR.mkdir(parents=True, exist_ok=True)

lines = SRC.read_text(encoding="utf-8").splitlines(keepends=True)

# ── 1. 切出每个顶层函数 ──
func_starts = []
for i, l in enumerate(lines):
    if l.startswith("func "):
        name = l.split("(")[0].replace("func ", "").strip()
        func_starts.append((i, name))

funcs = {}
for idx, (start, name) in enumerate(func_starts):
    end = func_starts[idx + 1][0] if idx + 1 < len(func_starts) else len(lines)
    funcs[name] = "".join(lines[start:end]).rstrip("\n")

FRAMEWORK = {"_initialize", "_suite", "_check", "_check_eq"}
HELPERS = {"_open_grid", "_scan_bom"}

# ── 2. 解析原来的注册顺序 ──
reg_pat = re.compile(r'_suite\(\s*"([^"]+)"\s*,\s*(\w+)\s*\)')
registrations = []          # [(suite_name, func_name)] 按原顺序
for l in lines:
    m = reg_pat.search(l)
    if m:
        registrations.append((m.group(1), m.group(2)))

registered_funcs = {f for _, f in registrations}
all_tests = [n for n in funcs if n.startswith("_test_")]
# ⚠️ 定义了但没注册的（原实现里它们静默不执行）
orphans = [n for n in all_tests if n not in registered_funcs]

# ── 3. 分组（按套件名；未注册的按主题塞进对应组并登记）──
GROUPS = [
    ("s01_core_data", "基础数据与工程卫生", [
        "数据加载", "数据内容", "阶段开关", "SimRng 确定性", "定义类辅助方法",
        "掉落表抽样", "CJK 字体与中文断行", "项目卫生",
    ], []),
    ("s02_mapgen", "地图生成与寻路", [
        "逻辑网格 LogicalGrid", "房间图 RoomGraph", "地图生成器 MapGenerator",
        "流场寻路 FlowField", "流场缓存 FlowFieldManager",
    ], []),
    ("s03_combat", "战斗与物品", [
        "战斗：弹道与视线 Ballistics", "战斗：伤害与部位 DamageModel",
        "战斗：武器状态 WeaponState", "背包 Inventory", "掉落 LootRoller",
        "触屏：子弹磁性 AimAssist",
    ], []),
    ("s04_ai", "AI 与群体协同", [
        "感知 Perception", "小队 Squad", "敌人个体 EnemyAgent",
        "群体 AI：包夹角色", "群体 AI：警戒扩散", "群体 AI：警戒驱动行为",
    ], []),
    ("s05_raid", "突袭回合与 A 阶段系统", [
        "突袭回合 RaidSession", "A 阶段：人物状态 Vitals", "A 阶段：枪械改装 WeaponModding",
        "A 阶段：医疗 MedicalSystem", "A 阶段：藏身处 Hideout",
        "真机修复：出生安全区", "真机修复：死亡结算",
    ], []),
    ("s06_feel_audio", "手感与音频", [
        "手感 Feel（hitstop/震动/闪白）", "音效库 Sfx",
        "手机实测：音频并发计数", "真机修复2：hitstop 频率配额",
    ], []),
    ("s07_ui_mobile", "UI 与移动端", [
        "真机修复：结算界面与触屏接口", "真机修复2：触屏输入隔离",
        "真机修复2：白模渲染", "PC实测：键位与设置菜单",
        "PC实测：Control 尺寸不得塌成 0", "PC实测：藏身处布局",
        "手机实测：HUD 性能读数", "PC实测：粒子坐标换算",
        "真机修复3：测试模式敌人上限",
    ], ["_test_settings_menu_layout"]),          # ⚠️ 原先从未注册
    ("s08_hitbox_aim", "命中判定与视野", [
        "真机修复3：#1 贴脸 hitbox", "真机修复3：#4/#5 自动瞄准",
        "真机修复3：#5 视野锥随枪械变化", "真机修复4：命中判定无双重随机",
        "真机修复4：散布收缩 hitbox", "白模：视野锥不透视",
    ], []),
    ("s09_whitebox_ai", "白模一致性与性能回归", [
        "真机修复3：白模与碰撞一致", "白模：可走格必须真的可达",
        "真机修复3：#6 尸体战利品", "真机修复3：#7 藏身处与设置",
        "性能回归：听觉代价场缓存",
    ], ["_test_corpse_interaction_visible", "_test_whitebox_is_default"]),  # ⚠️ 原先从未注册
    ("s10_save_hideout", "存档与藏身处经济", [
        "存档：读写与版本迁移", "藏身处：升级效果接进局内", "藏身处：商人买卖",
    ], ["_test_save_roundtrip_hideout"]),         # ⚠️ 原先从未注册
]

# 归属检查
assigned_suites = [s for _, _, ss, _ in GROUPS for s in ss]
assigned_orphans = [o for _, _, _, oo in GROUPS for o in oo]
missing_suites = [s for s, _ in registrations if s not in assigned_suites]
extra_suites = [s for s in assigned_suites if s not in {x for x, _ in registrations}]
unassigned_orphans = [o for o in orphans if o not in assigned_orphans]

if missing_suites or extra_suites or unassigned_orphans:
    print("❌ 分组不完整，已中止：")
    if missing_suites:
        print("   未分配的套件:", missing_suites)
    if extra_suites:
        print("   名单里有但原文件没有:", extra_suites)
    if unassigned_orphans:
        print("   未分配的无主测试:", unassigned_orphans)
    raise SystemExit(1)

# ── 4. 写各套件文件 ──
name_to_func = dict(registrations)
written = []
for fname, title, suite_names, orphan_funcs in GROUPS:
    parts = []
    parts.append("extends TestSuite")
    parts.append("")
    parts.append("## %s" % title)
    parts.append("##")
    parts.append("## 由 test/run_tests.gd 拆分而来（测试函数体原样搬运，未改一字）。")
    parts.append("")
    parts.append("")
    parts.append("func register() -> void:")
    for s in suite_names:
        parts.append('\t_suite("%s", %s)' % (s, name_to_func[s]))
    # 原先从未注册的，这次补上
    for o in orphan_funcs:
        # 用函数名做人读的套件名
        pretty = o.replace("_test_", "").replace("_", " ")
        parts.append('\t# ⚠️ 原先【定义了但从未注册】—— 补上（见 test_kit.gd 的说明）')
        parts.append('\t_suite("补注册：%s", %s)' % (pretty, o))
    parts.append("")
    parts.append("")
    # 函数体：_scan_bom 属于卫生套件，跟着 s01 走
    for s in suite_names:
        parts.append(funcs[name_to_func[s]].rstrip("\n"))
        parts.append("")
        parts.append("")
    for o in orphan_funcs:
        parts.append(funcs[o].rstrip("\n"))
        parts.append("")
        parts.append("")
    if fname == "s01_core_data" and "_scan_bom" in funcs:
        parts.append("# 递归扫描目录里的 UTF-8 BOM（原样搬运）")
        parts.append(funcs["_scan_bom"].rstrip("\n"))
        parts.append("")

    text = "\n".join(parts).rstrip("\n") + "\n"
    (OUT_DIR / (fname + ".gd")).write_text(text, encoding="utf-8")
    written.append((fname, len(text.splitlines()), len(suite_names) + len(orphan_funcs)))

print("已写出套件文件：")
for f, n, s in written:
    print("  %-22s %5d 行  %2d 套件" % (f + ".gd", n, s))
print("  合计 %d 行 / %d 套件（原 %d 套件）" % (
    sum(n for _, n, _ in written), sum(s for _, _, s in written), len(registrations)))
print()
print("⚠️ 补注册的 4 个测试函数（原先静默不执行）:")
for o in orphans:
    print("   %s" % o)
