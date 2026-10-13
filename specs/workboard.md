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

_（空）_

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

### W-07 · 建共享 remote（两人协作的前提）—— 待拥有者操作

**背景**：本地历史已清零并拆成 16 个逻辑提交（见 [git-history-bootstrap.md](git-history-bootstrap.md)），
但仓库**至今没有 remote**，第二个人无法 clone。`.gitignore` 已挡掉 `_install/`（2.2G 工具链）、
`build/`（534M APK）、`.godot/`，入库仅 362 个文本/小文件。

**要做**：① 拥有者在 GitHub/Gitee 建空仓库（项目 GPL-3.0 免费开源，公开推符合红线；
国内访问优先 Gitee）；② `git remote add origin <url>` + `git push -u origin master`；
③ 两人各自 clone，`_install/` 工具链每人本地自备（AGENTS.md 已要求全脚本相对定位，
clone 到任何盘符都能跑验收）；④ 各跑一次 `verify_all.ps1` 确认退出码 0 再开工。

**写入范围**：无仓库写入（remote 是账号侧操作）。

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
