# WORKBOARD —— 共享任务板

> 这是**文件版的任务板**：给「人 + DSH + WorkBuddy 同时参与」用。
> 为什么不用工具自带的：各家的任务板互相看不见，**文件是唯一双方都能读写的通道**。
>
> 规则见 [AGENTS.md](../AGENTS.md)。开始干活前**先在这里声明写入范围**。
>
> 🆕 **上一轮的交接在 [session-handoff.md](session-handoff.md)**
> —— 含「未验证清单」和「建议的下一步顺序」。

---

## 怎么用

1. **领取**：把任务从「待办」移到「进行中」，写上 `@你的名字` + **写入范围**
2. **干活**：只改你声明的范围。发现要改范围外的东西 -> 停下来先改声明或找人协调
3. **交付**：跑 `tools\verify_all.ps1`，退出码必须是 0，把退出码填进「完成」表
4. **冲突**：两个任务写入范围有重叠 -> **必须串行**，或者重新切分

---

## 进行中

### ✅ 可玩性四步 + 平衡（2026-10-16 · 拥有者「提高可玩性」+「做平衡」，全部完成）

**负责人**：@WorkBuddy · **`verify_all.ps1 -Fast` 退出码 0**（单元 **3194/0** + 集成 **105/0** + 数据 0 错 0 警）

**四步提交链**（每步单独验收再进下一步）：
`b82622c`（① 时间压力）→ `181bba0`（② 搜刮代价）→ `2cd4c12`（③ 撤离守卫）→
`ca7becb`（④ 敌人威胁机制）→ `e5ea34f`（平衡：威胁带调参 + TTK 锁）。

**四步结果**：
1. ✅ **时间压力真正生效**：地图级时限（森林 180 / 城区 240 / 军事基地 300）+ 撤离点按离出生点
   由近到远排序、最近的先关、最远保底常开（`raid_seconds` 写入 `maps.json` + `MapThemeDef` +
   `clone()` 同步；`RaidSession.start(0)` 安全回退默认；HUD 预警「Xs 后关闭一个」）。
2. ✅ **搜刮有代价**：`ContainerDef.search_time` 死字段接上 —— `RaidSession` 搜刮推进、
   离开 2.5 格中断但进度保留、未解锁拿不到；`raid_loot_actions`/`raid_sim_runner` 接线、
   搜刮发噪音（响度=开枪一半）；HUD 显示「搜刮中 XX%」。
3. ✅ **撤离不是免费的**：`RaidSession.extract_guard_count` 守卫规则（最近 0 / 中间 1 / 保底 2，
   仅 1 个点返回 0）；`raid_scene._spawn_extract_guards` 按规则生成（`MAX_TEST_ENEMIES>0` 跳过）。
4. ✅ **敌人威胁上调（机制 + 平衡）**：`EnemyAgent` 惊动后反应更快（`ALERTED_REACTION_MUL=0.45`）
   + 命中修正（`AIM_SPREAD_BONUS_DEG=1.5`）；平衡轮把基础敌人倍率约翻倍，击杀无甲玩家理想值
   全部落入 2.7~5.0s 威胁带（拾荒者 7.5s→3.6s），全敌人在 [2.0,6.0]s；`s30` 新增「平衡锁」
   钉死不许退化。

**仍挂着的（诚实记录）**：
- 门 1 另一卡点**「死亡痛感」**（`death_policy` 三旋钮全 0=全掉、无保险 UI）仍是**设计待拍板**，
  本轮没替你拍板；
- 真机没跑：所有数值/机制的真手感（敌人威胁、搜刮风险窗口、撤离守卫密度）都要人眼/真机确认；
- ⚠️ `sim_raid.gd` 端到端走 `raid.loot_container()` 绕过容器系统，**不能当改动对照**，
  真实节奏只能真机验。

**偏离记录**：本轮又是 roadmap §5「门 1 不过不加系统」的偏离，但这次改的**正是门 1 本身**
（难度/取舍），拥有者点名四项全做 + 给平衡最大权限。

---

### ✅ 完整策划案 + 雏形验收（2026-10-16 · 拥有者要求「先出策划案，再做可运行雏形」）—— 已完成

**负责人**：@WorkBuddy · **状态**：完成（退出码 0：3124/0 + 105/0 + 数据 0 错 0 警）

**结果**：提交 `f063ad4`（`specs/game-design-doc.md` + `tools/balance_report.gd`）。
· 雏形**三处实测均可跑**：main_menu 85 节点 / hideout 244 节点 / raid 216 节点（62 容器 36 敌人）
  —— headless 全部 exit 0 零报错；端到端 `sim_raid.gd` 完整循环 exit 0。
· 🔴 **两份门 1 硬证据**：① 玩家步枪杀拾荒者 0.3s vs 拾荒者杀玩家 7.5s（1v1 碾压 ~25×）；
  ② 端到端 17.6s 直线跑图 / 0 击杀 / 满血 / 带出 472 元（跑刀收益风险比过高）。
  倍率**待平衡专家定夺**，本轮只测量不拍板。

**写入范围**（只动这些，别越界）：
· 新增 `specs/game-design-doc.md`（策划案，纯新增）
· 新增 `tools/balance_report.gd`（headless 平衡报告工具，纯新增，不改 sim/）
· `specs/workboard.md` / `specs/session-handoff.md`（文档）
· ⛔ **不改** `sim/` `view/` `ui/` `data/` 任何既有文件 —— 本轮是"盘点 + 测量"，不是"改数值"

**说明**：经核实，可运行雏形**已经存在且能跑**（主菜单 / 战局场景 / 端到端 demo 三处
headless 均 exit 0）。本轮不重复造轮子，改为：① 把策划案写在真实代码上；
② 补一个平衡报告工具，把门 1 的「难度平衡」缺口变成可测量的数字。

---

### ✅ 装备闭环补齐四步（2026-10-16 · 拥有者点名四项全做）—— 全部完成

**负责人**：@WorkBuddy · **`verify_all.ps1 -Fast` 退出码 0**（单元 **3124/0** + 集成 **105/0** + 数据 0 错 0 警）

**四步提交链**：`bb779c6`（A 掉落→捡起）→ `0b84198`（B UI 显示）→
`dfb5e8c`（C 敌人侧）→ `ec601a5`（D 自动作战换装）。每步单独跑验收再进下一步。

**结果**：
· **A**：容器补 `roll_gear_for_drops`；`add_container` / 尸体两条登记保留 gear；
  四条取物路径（`ContainerInstance.take/take_all` + 两个 corpse take）改 `add_with_gear`；
  塞不下时 gear **留在原处**不丢。`s29` 钉死。
· **B**：搜刮面板的临时 Inventory 此前也用 `add`（gear 在**视图层**也丢）→ 同改；
  面板带 gear 的装备**每槽一行不合并**，显示"稀有 · 武器伤害+8% · 评分 132"、
  按钮描边用数据自带 color；装备栏 4 槽显示品质名。
· **C**：`GearGen.apply_affixes()` 抽成玩家/敌人**共用**（此前只有玩家侧会用词条）；
  敌人改用 `enemies.json` 的 `weapon_id`（此前被忽略、统一发手枪），
  depth≥1 roll 品质词条，depth≤0 不变（浅区强度与旧版逐字一致）；
  敌人死后**掉他自己那把**（含品质）。
· **D**：`Equipment.equip_at(槽位)` 修"点史诗却穿上稀有"；`best_upgrade_slot()`
  按评分挑更好的，自动作战搜刮完自动换上（只升不降，无 gear 不参与）。

**仍挂着的（诚实记录）**：
· 背包面板「装备」按钮仍走 item_id —— 同 id 多件时可能穿错那件（sim 的 equip_at 已就位，
  面板改按下标是下一小步）；
· ⚠️ **真机没跑**：品质色是否好看、词条文案是否挤、自动换装的手感都要人眼确认；
· ⚠️ **rng 消耗序列变长**（容器 + 深区敌人都多 roll）→ 同 seed 世界不再与旧版一致，
  像素基线 ④ 若需重设请按协作规则说明理由；
· 敌人/装备**倍率全是温和默认值，待平衡专家定夺**；门 1 两缺口仍挂待办。

**背景**：拥有者问「自动战斗推进/掉落后怎么装备/敌人性能配合/辅助瞄准挂钩」四问，
读代码体检发现：装备系统**"穿上之后"是通的（辅助瞄准✅已挂钩），"掉落到捡起"是断的**。
断点清单（已核实带行号）：
① `_spawn_containers`（`raid_scene.gd:266`）只调 `roll_for_room`，**容器从不 roll 词条**；
   `add_container`（`raid_session.gd:540`）只复制 item_id/count；
② `take_from_corpse`/`take_all_from_corpse`（`raid_session.gd:489/510`）与
   `ContainerInstance.take/take_all`（`container.gd:59/74`）用 `inv.add()`，**搜尸洗掉 gear**；
③ `ui/` 全局无 gear/品质/词条显示代码 → **玩家看不到，无法决策换不换**；
④ 敌人活的时是硬编码 `weapon_pistol`（`raid_scene.gd:514/533`），`enemies.json` 的
   `weapon_id` 只用于死亡掉落 → **敌人不吃装备系统，玩家单方面变强，门 1「难度偏低」被放大**；
⑤ `player_autopilot.gd` grep gear/equipment 零命中 → **自动战斗不认识装备**。
（`_drop_loot` 是死代码：有 roll gear 但全仓无调用点，尸体机制已取代。）

**分步计划（每步单独跑验收，不一次堆完）**：
- **Phase A（sim）**：四处取物改 gear-aware + 容器补 roll → 硬回归单测钉死
- **Phase B（UI）**：背包/配装/搜刮界面显示品质颜色 + 词条行 + 评分
- **Phase C（敌人）**：敌人穿戴装备 roll 品质词条并作用于战斗性能（倍率温和默认，待平衡专家定夺）
- **Phase D（自动战斗）**：autopilot 搜刮后自动换上评分/品质更高的同类装备

**写入范围**：`sim/items/container.gd`、`sim/raid/raid_session.gd`、
`view/raid_scene.gd`（单一作者）、`ui/inventory_panel.gd`、`ui/loadout_panel.gd`、
`view/raid_loot_actions.gd`、`sim/ai/enemy_agent.gd`、**不碰**（Phase A 时）、
`test/suites/s29_gear_flow.gd`（新）、本文件、`specs/session-handoff.md`。
**不碰**：`sim/mapgen/`、数值拍板（倍率一律标"待平衡专家定夺"）、队友的 `sim/ai/` 之外的协调者。

---

### ✅ 全境2化装备 Phase 1：品质 + 评分 + 词条进公式 — 已完成 2026-10-16（拥有者拍板转向）

**负责人**：@WorkBuddy · **`verify_all.ps1 -Fast` 退出码 0**（单元 **3091/0** + 集成 **105/0** + 数据 0 错 0 警）

**背景**：拥有者 2026-10-16 拍板：**数值偏 RPG，装备系统参考全境封锁2**。
盘点差距：品质分级/词条/装备评分**全部不存在**；伤害链
（`weapon.damage → 部位×距离 → 弹型×护甲 → 磨损`）上**没有任何玩家属性加成乘区**
——这就是"数值 RPG 化"的缺口。三个拍板：① 范围=品质+评分+词条进公式
（品牌套装/天赋/校准重铸放 Phase 2 候选）；② 公式=词条直加成乘区（不做三围面板化）；
③ 死亡=品质加权保留（`death_policy` 权重从纯价值改 品质×价值）。

**写入范围**：`sim/gear/`（rarity_def/affix_def/gear_gen，新）、`data/gear_rarity.json`（新）、
`data/gear_affixes.json`（新）、`io/data_registry.gd`、`sim/items/inventory.gd`、
`sim/equipment.gd`、`sim/raid/raid_session.gd`、`view/raid_scene.gd`、
`test/suites/s28_gear_system.gd`（新）、`data/SCHEMA.md`、`data/BALANCE_TUNING.md`、
本文件、`specs/session-handoff.md`。
**不碰**：队友的 `sim/ai/`、`view/raid_scene.gd` 之外的协调者文件、数值细节
（倍率全是温和默认值，标"待平衡专家定夺"）、UI 面板大改（Phase 1b）。

**设计定案**：
① 品质 5 级（普通/精良/稀有/史诗/传说），决定词条数 0~4、强度倍率、评分系数、死亡保留权重；
② 词条 8 条：武器 5（伤害/射速/装填/散布/射程，pct 或 pct_neg 进 `Loadout.effective` 乘区）+
   护甲 flat（+1~3 进 `effective_armor()`）+ 生命/移速 pct（进 vitals 与玩家移速）；
③ ⭐ 词条挂**背包槽位**：装备类 `stack_max=1` 永不堆叠，每槽天然一件独立装备 →
   slot 加可选 `gear` 字段，掉落时 roll、转移时搬运、不破坏现有堆叠语义；
④ rng 全程注入（T-32 纪律，同 seed 整局可复现）；无 gear = 向后兼容（老档/商店货=普通品质无词条）。

**已知限制（诚实记录，别当成已做）**：
· 词条只在**世界生成（掉落/容器）**时 roll；`Hideout.stash` 转移保留 gear，但商店购买是普通品质；
· `Inventory` 仍是 id 堆叠模型，本设计靠"装备不堆叠"绕过；将来若做装备实例化再统一；
· 天赋（条件触发词条）/品牌/套装/校准重铸**没做**，Phase 2 候选，等真机验证。

**结果**：`0065857`（数据层）→ `da055d6`（sim 接线）→ `a55d3e3`（表现层）→
`0f3598e`（s28 测试 984 断言）→ 文档提交（SCHEMA §12 契约 + 本文件 + handoff）。
战局内闭环：容器/掉落 roll 出带品质词条的装备 → 穿上进 `Loadout.effective` 乘区与
`effective_armor()` → 死亡按 `价值 × death_weight` 品质加权保留。
**⚠️ 偏离记录**：同 s27——`roadmap-bac.md` §5「门 1 不过不加系统」，拥有者 2026-10-16
**明确拍板接受偏离**（原文不改写，加注记）。门 1 两缺口仍挂待办。

### ✅ 肉鸽第一块：局内规则变体 RunModifiers（2026-10-16 · 拥有者拍板转向）

**负责人**：@WorkBuddy · **`verify_all.ps1 -Fast` 退出码 0**（单元 **2107/0** + 集成 **105/105** + 数据 0 错 0 警）

**背景**：拥有者 2026-10-16 拍板：项目定位改为**「肉鸽 × 自动战斗 × 搜打撤」**。
盘点三要素现状：搜打撤 ✅ 完整循环；自动战斗 ✅ 已有（`player_autopilot.gd` 287 行
寻路/搜刮/交火三态 + s25 覆盖，敌人侧 `enemy_agent` 本就自动）；**肉鸽 ❌ 完全没有**。
地图结构已 seed 随机 + 主题随机 + HUD 显示种子，故"局局不同"的结构基础已在，
本项补**规则变体层**（roguelite 的"每局带一两个变数"）。

**做了什么（Phase 1 · 最小可用）**：
① 新类 `sim/run_modifiers.gd`（`RunModifiers`：按 group 互斥抽 1~2 个变体、
因子连乘查询、中文摘要；rng 注入保证同 seed 可复现，T-32 纪律）；
② 新表 `data/run_modifiers.json`（4 变体 2 互斥组：敌潮/防线薄弱 + 富饶容器/被搜刮过），
`DataRegistry._load_run_modifiers()` 加载 + 契约校验（SCHEMA §11）；
③ `MapThemeDef.clone()` + `raid_scene` 接线：⭐ 防御性拷贝——
`reg.get_map()` 是**共享实例**，直接乘 density 会污染全局（后续每局累积倍率）；
变体乘进 `theme.enemy_density`（影响敌人数）与容器抽取次数（`rolls` 上限 5→8）；
`raid_session.run_mods` 为唯一真源，HUD 开局一行"本局变体 敌潮 · 富饶容器"；
④ 新套件 `s27_run_modifiers.gd`（6 套件 ~440 断言）：roll 确定性、200-seed 互斥组采样、
因子连乘、空数据安全、数据契约、源码结构防污染回归。

**Phase 2 候选（待拥有者真机验证后再做，不擅自加）**：
撤离时间变体组（extract_time_mul）、敌人类型权重变体、地图参数变体、
变体权重（Phase 1 等权）、局外 meta 成长线。
**倍率数值全部标"待平衡专家定夺"**，本项只搭生效机制。

**⚠️ 偏离记录**：`roadmap-bac.md` §5「门 1 不过不加系统」——拥有者 2026-10-16
**明确拍板接受偏离**（原文不改写，加注记）。门 1 两缺口仍挂待办。

### ✅ sim/view 边界类型安全收口（2026-10-16 · 规划盘点后的代码推进）

**负责人**：@WorkBuddy · **`verify_all.ps1 -Fast` 退出码 0**（单元 **1664/0** + 集成 **105/105** + 数据 0 错 0 警）

**背景**：拥有者要求"读规划、推进代码层面"。盘点 `roadmap-bac.md` + `progress-report.md` 后发现
报告的代码清单**大部分已过时**（警戒扩散/商人/撤离结算/存档/B 方案均已由 DSH 完成），
逐一核实后选定本项 —— `progress-report.md` 技术债第 2 条的真实残存部分。

**写入范围（实际）**：`sim/ai/enemy_agent.gd`、`test/suites/s26_type_safety.gd`（**新文件**）、
`specs/progress-report.md`（同步过时状态）。未碰数值、玩法与队友的 `s25`。

**做了什么**：
① `enemy_agent` 两处消费 `ctx.get("lane_shots")` 用 `Variant` 接（`LaneShotManager` 有
`class_name` 却在 sim 层被鸭子类型消费，方法名拼错要到运行时以"敌人不开火"暴露）→
改 `as LaneShotManager` 强类型，`as` 失败得 null、自然落进既有兼容路径，行为不变；
② `ctx.get("prof")` 的 4 处重复 `!= null` 检查收口成 `_mark_prof()`，加
`is Object + has_method("mark")` 两层防护（鸭子类型**保留**：Tel 是 autoload，
sim/ 不能依赖，headless 编译不过——实测踩过 `Identifier not found: Sfx`）；
③ 新套件 `s26_type_safety.gd`（5 套件 14 断言）钉死：三条路径（正常/缺失/错类型）
行为不变、正确的鸭子探针仍照常打点、prof 传错对象不炸 tick、源码结构防回流；
④ `progress-report.md` 头部加 2026-10-16 核对块（正文是 10-12 快照：制造/任务/存档/
商人/结算/警戒扩散/多主题均已完成、测试 1664 项），§九 加指向注记。

**为什么不做更大的**（流场增量构建等）：`roadmap-bac.md` §5 纪律 —— 门 1 未过，
"回去改数值与节奏，而不是加系统"；性能大改等拥有者真机反馈后再定。

### ✅ 自动作战 / 固定弹道 / 闪避（2026-10-13 · 拥有者需求）

**负责人**：@DSH-Lead · **`verify_all.ps1` 退出码 0**（单元 **1619/0** + 集成 **105/105** + 数据 0 错 0 警；
④ 像素基线本环境无法成像，未作结论）

**一句话**：把「自动寻路 / 自动锁定攻击 / 遇容器自动搜刮」与
「敌人固定弹道（2 倍身位宽、锁开火瞬间人物中心）+ 闪避（1.5 身位）」落进代码。

**写入范围**：新增 `sim/combat/body_metrics.gd`、`sim/combat/lane_shot.gd`、`sim/combat/lane_shot_manager.gd`、
`sim/combat/dodge.gd`、`sim/ai/player_autopilot.gd`、`test/suites/s25_auto_combat.gd`；
修改 `sim/ai/enemy_agent.gd`、`sim/combat/auto_aim.gd`、`view/raid_sim_runner.gd`、`view/raid_scene.gd`、
`view/raid_drawer.gd`、`view/raid_input.gd`、`ui/touch_controls.gd`、`ui/settings_menu.gd`、`game/game_state.gd`。

**身位约定**：`BodyMetrics.BODY_WIDTH = 0.9 逻辑格`（判定半径 0.45 × 2）；
弹道半宽 = 1 身位、总宽 = 2 身位、闪避位移 = 1.5 身位 —— 三处全部由它推导。

**验收当场抓出并修掉 2 处**：`raid_input.gd` 的 `KEY_G/KEY_SHIFT` 缩进错位、
`raid_sim_runner.gd` 三处 `:=` 在 duck-typed 链上类型推断失败。

**未验证**：④ 像素基线（本环境无绘图会话）；真机手感。


### ✅ 装备系统「打通」（2026-10-13）—— 藏身处配装 / 战局穿脱 / 改枪 / 敌人装备掉落

**负责人**：@WorkBuddy · **`verify_all.ps1` 退出码 0**（单元 **1094/0** + 集成 51/51 + 数据 0 错 0 警；
④ 像素基线本次用 `-Fast` 跳过）

**一句话**：`Equipment` 早就写好并有单测，但 **`grep Equipment` 只命中它自己和 s16** ——
在游戏里根本没被调用，等于"一个不可见的大号衣柜"。本轮把它接进藏身处与战局。

**写入范围（实际）**：`sim/equipment.gd`、`sim/hideout.gd`、`sim/raid/raid_session.gd`、
`io/save_manager.gd`（v3→v4 迁移）、`ui/loadout_panel.gd`（**新**）、`ui/mod_panel.gd`（**新**）、
`ui/inventory_panel.gd`、`view/hideout_scene.gd`、`view/raid_scene.gd`、`view/raid_hud.gd`、
`test/suites/s17_loadout.gd`（**新**）

**四个能力对应到哪**：

| 需求 | 落点 |
|---|---|
| 藏身处配装 | `Hideout.loadout`（跨局持久、进存档）+ `ui/loadout_panel.gd`（仓库 ↔ 4 槽，点选点放） |
| 战局穿脱装备 | `RaidSession.equip_from_carry/unequip_from_carry`（带 phase 守卫）+ `ui/inventory_panel.gd` 顶部装备栏 |
| 修改枪械配件 | `Equipment.set_mod/build_loadout`（**配件跟枪走**：按 weapon_id 索引）+ `ui/mod_panel.gd` |
| 从敌人身上拿装备/枪械 | 上轮已做（`enemy_def.weapon_id/armor_id/helmet_id` + `_spawn_corpse` 掉进尸体）；本轮补了**端到端**测试与背包里「装备」按钮 |

**关键设计**：`raid.equipment = hideout.loadout` 是**引用共享**而非拷贝 ——
局内捡到的枪装上身，撤离后直接就是新配装（少一次搬运 = 少一个漏搬点）；
代价是**死亡必须显式清空**（`_on_death` 连身上这套一起丢，只丢背包 = 半个搜打撤）。

**⚠️ 已知缺口（没做）**：护甲/头盔/背包槽目前只影响"能带走 / 能卖钱"，**不影响数值**
（数据层没有护甲值，也没有"背包 → 负重上限"映射，没敢凭空造数）—— **weapon 槽是完全打通的**，
进局打的真的就是你配的那把枪（含改的配件）。另外换枪后备弹不按弹药类型取（简化模式给足）。

**⚠️ 未验证**：安卓真机人眼确认（藏身处配装面板 / 战局背包装备栏）；像素基线本轮跳过。

**本轮修掉的两个真 bug（都是新增的 UI 冒烟测试跑出来的，不是看出来的）**：
① 面板 `open()` 若在 `_ready` 之前被调用，内部控件全是 Nil → 一路
`Invalid assignment ... on a base object of type 'Nil'`；修法是幂等 `_ensure_built()`
（`_ready` 与 `open()` 都调）。
② 藏身处顶部栏加第三个按钮后**横向**挤不下会把左侧标题/资金压成一条缝（不报错，只是难看）——
已固化为 `BAR_BTN_W_*` 常量 + `bar_fits()` 静态自检（`s17` 直接调）。

### ✅ W-00 已完成 —— 报告见 [w00-determinism.md](w00-determinism.md)

**负责人**：@DSH-Lead（单一作者）· **`verify_all.ps1` 退出码 0** · 847 单测 + 51 集成 + 数据契约 0 错

**结论（与上面的原始判断**不同**，务必读报告）**：
真正让"第 300 帧不一致"的**不是** hitstop，而是**验收工具自己**的两个 bug ——
① `--hide-hud` 静默失效（HUD 里 `平均 %.1f ms` 是墙钟读数，被当成世界像素在比）；
② `_mouse_aiming()` 读操作系统鼠标速度（**验收时有人动鼠标，视野锥整块变，差 5%~7%**）。
两者修掉后，`verify_all.ps1` 的 ④ 从「两次截图不一致（0.43%~5.36%）」
变成「**同构建两次截图完全一致**」+「与基线一致：**逐像素完全一致**」。

hitstop 的墙钟问题**是真的**（单位级实测：同一个 120ms 请求，旧实现
紧凑循环冻 **251104 帧** vs 每帧 +3ms 冻 **29 帧**；新实现两种都是 **8 帧**），已改帧计数。

**写入范围（实际）**：`feel/feel.gd`、`view/raid_scene.gd`、`test/suites/s06_feel_audio.gd`、
`test/screenshot.gd`、`tools/determinism_{probe.gd,check.py}`、`tools/check_determinism.ps1`、
`specs/w00-determinism.md`、`AGENTS.md`（更正结论）、`specs/session-handoff.md`（更新交接）

**验收命令**：`tools\check_determinism.ps1`（4 场景 × 4 次，容差 0）
**⚠️ 我重设过 `art/_raw/_baseline.png`**（理由见报告 §3.3：旧基线含 HUD 的墙钟读数，不可能稳定）

**⚠️ 未验证**：hitstop 观感（人眼）、安卓真机帧率、满编 35 敌。

---

## 待办

### W-07 · 建共享 remote（两人协作的前提）—— ✅ **已完成（2026-10-13 晚，拥有者本机执行）**

**背景**：本地历史已拆成逻辑提交（见 [git-history-bootstrap.md](git-history-bootstrap.md)）。

**结果**：`https://github.com/gungnior/SDCgame.git` 已推送成功。拥有者本机执行
`git push -u origin main --force`，浏览器认证通过（`+ d1a56fe...b3641e7 main -> main (forced update)`，
1156 objects / 12.26 MiB）。远端原本不是空库（GitHub 自动 init 的 MIT LICENSE + 两行 README），
内容已保留进本地历史，强推未丢任何东西。

**推送后验证（全过）**：`origin/main` 与本地 `main` 哈希一致（`b3641e7`）；449 个文件树结构一致；
远端 `LICENSE` = MIT（Copyright (c) 2026 gungnior）；README 保留库主原话；
`_install/`、`build/`、`.godot/`、`.workbuddy/` 均未入库；唯一大文件 `art/fonts/NotoSansSC-VF.ttf`（17MB，已知）。

**⚠️ 连带变更（2026-10-13 拥有者拍板）**：项目许可证由 **GPL-3.0 改为 MIT**（以建库选择为准）。
`AGENTS.md` §5 红线、README、action-plan/progress-report/art-pipeline/tech-stack 等现行声明已全线同步；
`feasibility.md` D-09 等**决策记录保留原文、加推翻注记**（不改写历史）。

**下一步（两人开工流程）**：
① 队友 `git clone https://github.com/gungnior/SDCgame.git`；
② `_install/` 工具链每人本地自备（AGENTS.md 已要求全脚本相对定位，clone 到任何盘符都能跑验收）；
③ 各跑一次 `verify_all.ps1` 确认退出码 0 再动手；
④ 动工前在本文档声明"进行中 + 写入范围"（防撞车唯一机制）；
⑤ 以后 `git push` 即可，**别再加 `--force`**（会覆盖队友提交）。

**写入范围**：本轮只改 git 配置/历史与文档，未动游戏代码。

---

### W-00 · ⭐ **让模拟可复现：hitstop 改用帧计数**（✅ 已完成，见上）

> ✅ **已完成** @DSH-Lead —— 报告 [w00-determinism.md](w00-determinism.md)。
> ⚠️ 下面这段"根因"是**当时的判断，已被实测更正**（真正的主因是验收工具两个 bug）；
> 保留原文是为了留下"判断→证伪"的记录，**不要照它继续推断**。

**背景**：做协作基础设施时实测发现，这局游戏**运行期本质不确定** ——
同种子同参数连跑 4 次，第 300 帧两两比较 **3~5 对不一致（2~7%）**；
但第 30 帧 5/5 完全一致 —— 说明早期确定、后期混沌放大。

**根因**：`feel/feel.gd` 的 hitstop 用 `Time.get_ticks_msec()`（真实时钟）
把 `Engine.time_scale` 压到 0。而 `time_scale = 0` 时 `delta` 也是 0，
**游戏没法用模拟时间给自己计时**，只能用真实时钟 →
停顿帧数随真实耗时浮动 → 模拟推进量不同 → 混沌放大。

**影响**（不只是测试问题）：
- **bug 报告无法从种子复现** —— 这对一个靠种子排障的项目是硬伤
- 多人协作时两边看到的"同一个 bug"可能不是同一个
- 像素基线不能当回归门

**方向**：让模拟推进不依赖 `Engine.time_scale`（例如 hitstop 期间走
独立的帧计数冻结，而不是压 `time_scale`），或让 hitstop 时长按帧定义。

**写入范围**：`feel/feel.gd`、`view/raid_scene.gd`、`view/raid_sim_runner.gd`
**验收**：改完后「同参数连跑 4 次、第 300 帧 5 对全一致」——
这条可以作为新的确定性回归测试。
**注意**：这是**手感**改动，必须**单一作者**，且要人眼确认 hitstop 观感没变。

---

### W-01 · **对抗性验收：证伪清单**（推荐给 WorkBuddy）—— ✅ **已完成**

**性质**：评审，不是执行。**目标不是"确认它对"，是"证明它不对"。**
**负责人**：@WorkBuddy（与 @DSH 协作）· **`verify_all.ps1 -Fast` 退出码 0** · 单元 849/0 + 集成 51/0 + 数据 0 错
**报告**：[w01-adversarial-verify.md](w01-adversarial-verify.md)
**结论**：7 条全部跑通（0 失败）。6 条「未能证伪」；第 ③ 条在 1 格宽走廊发现「侧翼逻辑坐标穿墙」真实弱点（机制已定位，修法见报告 §2.3，交由 dsh 决定）。

这是目前**价值最高**的一项。理由：实现者（DSH）有确认偏误 ——
本会话里我自己发现的 bug 至少一半是"我以为对了"的
（对称性假设 / 包夹点稳定性 / 双重随机判定 / 升级涨价）。

**要求**（照抄 `D:\prompt-chat\docs\prompt-chat-revision-4-verify.md` 的写法）：

> 下面是我（实现者）声称已完成的事。**你的任务不是确认，是证伪。**
> 每一条都必须用**你自己的命令**重跑，**不许引用我给的数字**。
> 找不出问题就写「未能证伪」，**不许写"通过"**。

**候选证伪清单**（都是本项目现存弱点）：

| # | 要证伪的断言 | 为什么可疑 |
|---|---|---|
| 1 | 存档在**安卓**上走 `user://` | PC 上走的是可移植回退 —— **两条不同的代码路径**，只在 PC 验过 |
| 2 | `MAX_TEST_ENEMIES=0` 时满编 35 敌人跑得动 | **从没测过**（一直是 4 个） |
| 3 | 包夹 AI 在**狭窄走廊**不互相卡住 | 测试只覆盖开阔地 |
| 4 | 存档迁移支持 **v1 直接升 v3** | 只测过相邻版本 |
| 5 | 掉落表过滤后 B 档**总掉落量没变少** | 我按推理说"不会少"，**没有实测** |
| 6 | `_hearing_cache` 在多次噪音下不会漏更新 | 只有 1 个测试 |
| 7 | 商人「回收比例」升级真的影响卖出价 | 只断言了比例函数，没断言端到端金额 |

**写入范围**：`test/suites/`（新增文件）+ 报告写在 `specs/`
**不要改**：`view/`、`sim/` —— 复验阶段**先报告缺陷，不要边查边改**
（改完就分不清是复验还是新实现了）
**⚠️ 衍生待修**：W-01 ③ 发现「窄走廊侧翼穿墙」真实弱点 → 见待办 **W-06**。

---

### ✅ W-02 · C 阶段数据：制造配方 — 已完成 2026-10-12

**写入范围**：`data/recipes.json`（新建）+ `tools/`
**依赖**：无。可以和 W-03 并行。
**验收**：`tools\validate_data.py` 通过；新表被 `DataRegistry` 加载；加一个 `test/suites/s11_*.gd`

**结果**：新建 `sim/defs/recipe_def.gd`（`RecipeDef.from_dict` 工厂，`STATIONS={bench,forge,lab,kitchen}`）；
`data/recipes.json` 12 条 C 阶段配方（输入/输出全部引用 `items.json` 已存在 id）；
`io/data_registry.gd` 增加 `_load_recipes()` + 配方交叉引用校验 + `get_recipe()` + summary；
`tools/validate_data.py` 增加 `val_recipes` 并接入 `main()`；`data/SCHEMA.md` 新增 §8 配方契约；
测试落在 `test/suites/s12_recipes.gd`（加载/交叉引用/结构约束）。

---

### ✅ W-03 · C 阶段数据：更多枪械 / 敌人 — 已完成 2026-10-12

**写入范围**：`data/weapons.json`、`data/enemies.json`
**依赖**：无。
**注意**：`enemies.json` 的 `reaction_time` 对有远程攻击的有下限校验（`EnemyDef.MIN_RANGED_REACTION`），
改之前先看 `tools/validate_data.py` 的规则。
**验收**：`verify_all.ps1 -Fast` 退出码 0

**结果**：weapons 6→10（新增冲锋枪/精确步枪/轻机枪/自动霰弹/狙击/重型手枪等 C 档，全部带 `stage:"C"`）；
enemies 4→7（新增 C 普通敌人 + 1 Boss，ranged 反应时间均 ≥ 0.25）。狙击枪 id 由 `weapon_sniper`
改为 `weapon_rifle_sniper`（同属步枪族，符合校验器的射程极值启发式）。
**顺带修**：`tools/validate_data.py` 的武器平衡启发式原本用**精确 id** 比对 `weapon_shotgun`，
同族新增武器会误报；已改为按 id 子串判族（`"shotgun"`/`"rifle"`），消除误报。

---

### ✅ W-04 · 美术管线：tile 对比度 — 已完成 2026-10-12（人眼确认待 dsh）

**背景**：白模是当前默认，因为**美术 tile 的墙/地板对比度太低**（看不清哪能走）。
**写入范围**：`tools/`、`art/`
**验收**：截图对比（可以用 `tools\compare_images.py` 而不是肉眼）+ 人眼确认

**结果（可度量部分已完成）**：新增 `tools/art/measure_contrast.py` —— 读 `art/tiles/*.png`，
按 wall/floor 分类算平均 Rec709 亮度 + WCAG 对比度，标出「墙比地亮(INV)」和「对比度过低(LOW)」。
实测**修复前** 17 处问题、最弱 1.06:1，且 `tile_wall_metal` 比所有地板都亮（墙像地）。
修法（均在锁定的 40 色调色板内重选索引，未新增颜色）：
- `tools/art/gen_tiles.py`：墙面统一压暗（墙混凝土取 `G_WALL+0`、砖墙改暗墙色系、金属墙改暗底+金属肋条），
  地板提亮（混凝土 `G_STONE+3`、沥青 `G_STONE+2`、泥土/金属取最亮档）——**消除所有「墙比地亮」反转**。
- `view/raid_map_baker.gd::_bake_structure`：墙描边 1px→2px、地板 AO 0.30/2px→0.45/3px（强化边界可读性）。
**修复后**：0 反转、12 对全部 ≥1.5:1、其中 6 对达理想 2.5:1（最弱对是暗沥青贴暗墙 1.72:1，
靠边界描边承担）。已重新生成 21 块 tile。
**门槛为何是 1.5 而非 2.5**：40 色调色板墙/石两组在暗部本就接近，最暗地板贴最暗墙物理上拉不到 2.5:1；
俯视游戏「哪是墙」主要靠 `_bake_structure` 边界线（~3.7:1）分辨。面 gate 1.5 + 边界线 = 可读。
**⚠️ 待 dsh**：跑一局看美术 tile 模式（白模本身已 3.8:1 没问题），人眼确认辨识度；
安卓端可在 **UU 模拟器**测（用户提供）。

---

### ✅ W-05 · `data/` 与代码的契约测试 — 已完成 2026-10-12

**背景**：`data/*.json` 是"冷轨道"，最安全也最容易悄悄写坏 ——
比如引用了不存在的 `item_id`（**已经发生过一次**：掉落表引用了未加载的物品，
表现为"掉落悄悄变少"）。
**写入范围**：`test/suites/`（新增）
**验收**：能抓住"引用了不存在的 id"这类错误

**结果**：新增 `test/suites/s13_data_contract.gd`，两个方向都覆盖：
- 正向：B/A/C 三档 `load_all` 均无错误，且独立扫一遍四类交叉引用
  （`weapon.ammo_id` / `loot.entries[].item_id` / `room.loot_table_id` / `recipe.input|output`）零悬空；
- 负向：注入 5 个不同悬空 id 后，`DataRegistry._validate_cross_refs()` 必须逐个报错、
  且报错文本能定位到坏 id（证明守卫真在查，不是空转）。这把"引用不存在 id"钉成硬失败。

---

### ✅ W-06 · **窄走廊侧翼穿墙修复**（来自 W-01 ③ 发现）— 已完成 2026-10-12

**背景**：W-01 ③ 对抗性验收发现，1 格宽走廊里两个侧翼敌人（FLANK_LEFT/RIGHT）的
逻辑坐标会穿进墙格。机制（已在 W-01 中定位）：
1. `Squad.goal_for()` 的包夹点 = `target_pos - dir.rotated(±58°) * 3.2`，
   走廊为 1 格宽、敌人同侧接近时偏移量落到墙带里；
2. 远程 `_combat()` 直接 `move_dir = dir_to.normalized()` 施加位移，**不查墙**
   （只有 `_move_toward` 走流场才查墙）。

**修复（采纳修法 1，最小改动）**：在 `sim/ai/enemy_agent.gd` 的 `_combat()` 中，
拿到 `Squad.goal_for()` 的包夹点后，先经新增的 `_snap_walkable(grid, goal)`
夹到**最近的可行走逻辑格**（外环螺旋搜索，命中率 100%），再施加移动。
远程/近战分支都走夹后的 `goal`，包夹点落在墙里时不再直线穿墙。
开阔地包夹点本就可走 → snap 不改变行为；只有落墙的包夹点被拉回走廊中心，
窄走廊里退化为「沿走廊跟住」（与 W-01 预期一致）。

**验收**：`verify_all.ps1 -Fast` 退出码 0；且 ③ 测试在 1 格宽走廊里 3 个敌人 **0 穿墙**
（`clipped == 0`，已升为硬失败），最近距玩家 3.5 格（无死锁）。

**改动文件**：`sim/ai/enemy_agent.gd`（仅此一个；未动 `squad.gd`）。
**衍生**：`test/suites/s11_adversarial.gd` ③ 测试升级为硬回归守卫。

---

## 完成

> 📌 下表中 “_（本会话，未提交）_” 是 2026-10-13 **git 历史落地之前**的旧标注 ——
> 这些任务的提交现已全部在 `main` 历史中，逐任务到提交的映射见 [git-history-bootstrap.md](git-history-bootstrap.md)。
> 表格保留原样是为了不改写历史记录。

| 任务 | 负责人 | verify_all 退出码 | 提交 |
|---|---|---|---|
| 拆分 `test/run_tests.gd`（3439 → 110 行 + 10 套件 + 结构守卫） | DSH | 0 | `fc4bf3d` |
| 拆 `raid_scene.gd` / HUD | DSH | 0 | `5575950` |
| 拆 `raid_scene.gd` / 地图烘焙 | DSH | 0 | `8ef63d6` |
| 拆 `raid_scene.gd` / 世界绘制 | DSH | 0 | `c388561` |
| 拆 `raid_scene.gd` / 键盘输入 | DSH | 0 | `fd307a8` |
| 拆 `raid_scene.gd` / 模拟调度（1676 → 859 行） | DSH | 0 | `eceae22` |
| 把 7 份 prompt-chat 文档移出本仓库 | DSH | 0 | `0f97d31` |
| 统一验收命令 `tools/verify_all.ps1` | DSH | 0 | _（本次）_ |
| **W-00 让模拟可复现（hitstop 帧计数 + 修两个验收工具 bug）** | **DSH-Lead** | **0** | _（本会话，未提交）_ |
| **W-01 对抗性验收（7 条证伪清单）** | **WorkBuddy** | **0** | _（本会话，未提交）_ · 报告 [w01-adversarial-verify.md](w01-adversarial-verify.md) · 衍生 **W-06** |
| **W-06 窄走廊侧翼穿墙修复（`_snap_walkable` 夹包夹点到可走格）** | **WorkBuddy** | **0** | _（本会话，未提交）_ · 见 [w01-adversarial-verify.md](w01-adversarial-verify.md) §2.3 |
| **W-02 C 阶段制造配方（recipes.json + RecipeDef + 校验 + s12 测试）** | **WorkBuddy** | **0** | _（本会话，未提交）_ · `data/recipes.json` 12 条 |
| **W-03 C 阶段更多枪械/敌人（weapons 6→10、enemies 4→7）+ 修校验器启发式** | **WorkBuddy** | **0** | _（本会话，未提交）_ |
| **W-04 tile 对比度（gen_tiles 重选色 + _bake_structure 加粗 + measure_contrast.py）** | **WorkBuddy** | **0** | _（本会话，未提交）_ · 人眼确认待 dsh（安卓可 UU 模拟器） |
| **W-05 data/代码契约测试（s13：正向零悬空 + 负向注入必被抓）** | **WorkBuddy** | **0** | _（本会话，未提交）_ |
| **C-制造系统逻辑（`sim/craft_system.gd`：station 闸 + 原子制造 + s14 测试）** | **WorkBuddy** | **0** | _（本会话，未提交）_ · 吃 W-02 的 recipes |
| **A-改装系统（⚠️ 更正：早已存在）** | — | — | **`sim/items/weapon_modding.gd`（`WeaponModding`）本就是完整的改装系统**且已接入游戏（`raid_scene.gd:205` 创建玩家 Loadout + `auto_fit`）、已有 `s05`/`s08` 测试覆盖。本会话曾误写一个更弱的重复实现 `sim/weapon_mods.gd`+`s15`，**已删除**。教训：动手前先 grep 现有 `class_name`。 |
| **静步功能（`silent_walk`，原「蹲伏」改为此）** | **WorkBuddy** | **0** | _（本会话，未提交）_ · C 键 / 触屏「静步」按钮切换；移速 ×0.55、**脚步完全不发声**（不追加 noise、不播脚步音效）；HUD 有状态指示；不影响开枪声与敌人视觉 |
| **C 制造接入藏身处 UI** | **WorkBuddy** | **0** | _（本会话，未提交）_ · 新建 `ui/craft_panel.gd`（CraftPanel）+ 藏身处「制造台」按钮。此前 `CraftSystem` 已实现但**无 UI 入口**（同商人当年的处境）。工作台解锁由外部注入 Dictionary（技术验证期 4 台全开） |
| **⭐ 阶段开关 A -> C** | **WorkBuddy** | **0** | _（本会话，未提交）_ · `game/game_state.gd` 的 `reg.load_all("A")` -> `"C"`。原先只加载 A，**recipes.json 等 C 数据进不来**；按 roadmap 约束 5「用数据开关」，**改回 "A" 只动这一个参数** |
| **W-01 安卓真机验证（arm64 包装机跑通、`user://` 可写证实；x86_64 模拟器包 + `tools/android_verify.ps1`）** | **WorkBuddy** | — | _（本会话，未提交）_ · 存档持久化待手动玩一局 |

### 装备 / 任务系统（2026-10-12 ~ 10-13）

| 任务 | 负责人 | verify_all 退出码 | 提交 |
|---|---|---|---|
| **任务系统「只搭框架」**（`sim/mission_system.gd` + 空 `data/missions.json` + `s15_mission.gd`） | **WorkBuddy** | **0** | _（本会话，未提交）_ · 按用户要求**不写具体任务内容**；schema 先定死 |
| **装备系统 sim + 数据层**（`sim/equipment.gd`；武器做成 item（`items.json` category="weapon"）；敌人 `weapon_id/armor_id/helmet_id`；尸体掉落接入；`s16_equipment.gd`） | **WorkBuddy** | **0** | _（本会话，未提交）_ · ⚠️ 此时**只有 sim 层，游戏里无人调用** |
| **⭐ 装备系统「打通」（UI + 战局接线）** | **WorkBuddy** | **0** | _（本会话，未提交）_ · 见上方「进行中」的完整条目 |
| 修 `Equipment.get()` 与 `Object.get()` 冲突 | **WorkBuddy** | **0** | 方法改名 `id_in`。⚠️ **踩坑记录**：RefCounted 上的方法**不能叫 `get`/`set`**（与 `Object.get/set` 冲突）→ Parse Error → Godot `--script` 加载失败**空转不退出** → `verify_all` 假死 12 分钟 |
| 修「地图生成坏种子 → 刷出 0 敌人」 | **WorkBuddy** | **0** | `sim/mapgen/map_generator.gd` 的 `MAX_ATTEMPTS` 24→64（诊断 16 种子：坏种子要到第 36 次才成功） |
| **git 历史落地：未提交的全部改动拆成 16 个逻辑提交，工作树清零** | **WorkBuddy** | **0**（1555 单测 + 105 集成 + 数据 0 错 0 警） | `fe63a0e..c38f9c9`（本地，**未推 remote**）· 提交地图与拆分理由见 [git-history-bootstrap.md](git-history-bootstrap.md) |
| **push 前门禁：`tools/pre_push_check.ps1`（7 项检查）+ 清单文档** | **WorkBuddy** | 脚本已实跑两轮（含一次全量验收 exit 0） | `b50edc6`、`ef6b361` · [collab-push-checklist.md](collab-push-checklist.md) |
| **remote 配置 + 许可证拍板 MIT + 文档全线同步（分支改名 main）+ ⭐ 推送成功（W-07 完成）** | **WorkBuddy**（push 由拥有者本机执行） | 0（验收未重跑：全程零代码改动） | `9105114`、`b0af01b`、`3bac6e6` · 远端 `origin/main` = `b3641e7`，与本地哈希一致，449 文件树 IDENTICAL |

---

## ⚠️ 给并行协作的三个提醒

1. **`verify_all.ps1` 的像素基线：噪声的真实来源已查明（W-00）。** ——
   原来那句"噪声约 0.02%~0.036%"是**错的**：那 0.018% 是
   `--hide-hud` 静默失效导致 HUD 的 `平均 %.1f ms`（墙钟读数）进了世界基线。
   修掉之后**自身复现性是"逐像素完全一致"**。现在 ④ 可以当真正的粗粒度门用了，
   但注意：**验收时必须别动鼠标**（`_mouse_aiming()` 读操作系统鼠标速度），
   或者用 `tools/determinism_probe.gd`（它把鼠标瞄准钉住）。详见
   [w00-determinism.md](w00-determinism.md)。
2. **像素基线只能一个人重设** —— 两个人同时 `-UpdateBaseline` 会互相覆盖，
   等于把对方的回归当成自己的新基线。重设后**必须在提交信息里说明为什么**。
3. **`test/suites/*.gd` 虽然可并行，但别改同一个已有文件** ——
   新增文件是安全的，改别人正在改的文件不是。

### ✅ 开火前预警 + 移动端 UI 重做（2026-10-13 · 拥有者需求）

**负责人**：@DSH-Lead · **`verify_all.ps1 -Fast` 退出码 0**（单元 **1639/0** + 集成 **105/105** + 数据 0 错 0 警）

**一句话**：A 方案预警（`warn = clamp(0.45 - 飞行时间, 0.12, 0.20)`）解决贴脸必中；
移动端去开火键/视角摇杆、删静步、闪避移到右半屏十字中心。

**写入范围**：`sim/combat/lane_shot.gd`、`sim/combat/lane_shot_manager.gd`、`sim/ai/enemy_agent.gd`、
`view/raid_drawer.gd`、`view/raid_hud.gd`、`view/raid_scene.gd`、`view/raid_sim_runner.gd`、`view/raid_input.gd`、
`ui/touch_controls.gd`、`ui/tokens.gd`、`game/game_state.gd`、`test/suites/s25_auto_combat.gd`、`test/suites/s07_ui_mobile.gd`

**✅ 后续已补**（2026-10-13 · 队友 `de493b7`）：B 方案「同时开火节流」已落地 ——
`LaneShotManager` 加令牌桶（`SPAWN_RATE = 2.0` 条/秒、`SPAWN_BURST = 2.0` 瞬时爆发），
`EnemyAgent._fire_at` 在 `weapon.fire()` 前查配额，不足就本帧不开火（表现为**延迟**而非打空）。
调参口径：`SPAWN_RATE` 应与最大闪避频率（`1/DodgeState.COOLDOWN` ≈ 1.18 次/秒）同量级，
否则“躲得开”从数学上不成立。详见 `CHANGELOG.md` 顶部条目。
