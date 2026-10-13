# 平衡 / 数值 对接口文档（Balance Tuning Interface）

> 本文件是给**数值平衡专家**的"调数入口"。所有可调数值都已做成**数据驱动 / 集中常量**，
> 专家直接改对应数据源即可，**不需要改任何算法代码**。改完跑 `tools/verify_all.ps1` 验收。
>
> 约定：
> - 数据源分两类：**JSON 数据**（`data/*.json`，量最大、最该专家调）与 **GDScript 常量**（`sim/...` 里 `const`，少量但全局生效）。
> - 凡是标注"交给专家"的，本仓库当前是占位默认值，**不代表最终手感**。
> - 所有数值单位：距离 = 米（m），角度 = 度（°），时间 = 秒（s），重量 = kg，钱 = 元。

---

## 1. 地图（主题）`data/maps.json`
每个主题对象决定：地图多大、刷哪些房间/敌人、敌密度。

| 字段 | 含义 | 当前默认（森林/城区/军事） |
|---|---|---|
| `map_w` / `map_h` | 逻辑格尺寸（每格 3 tile） | 56 / 64 / 72 |
| `enemy_density` | 敌人总数 ≈ 房间数 × density | 0.7 / 1.1 / 1.4 |
| `room_weights` | 普通房间类型权重（`room_common`/`room_dorm`/`room_warehouse`/`room_armory`/`room_medical`/`room_lab`） | 见 json |
| `enemy_weights` | 敌人种类权重（见 §2 的 id） | 见 json |
| `tile_theme` | 白模色调（`dirt`/`concrete`/`metal`） | — |

⚠️ 地图越大 → 房间越多 → 敌人越多（受 `enemy_density` 放大）。扩图时建议同步看 §2 敌人数值。
硬约束见 `sim/mapgen/map_generator.gd`（只校验"撤离点数量≥阈值"与图连通性，无网格上限）。

> **房间数量不随地图变大而自动变多**：房间数上限由 `BSP_MAX_DEPTH`（§10）决定（depth 5 → ≤32 房间）。
> 所以"扩大地图"默认只让**单间更大、走廊更长**，敌人总数基本不变（受 `enemy_density × 房间数` 决定）。
> 若想让更大的地图**房间更多**（而非单间更大），调高 `BSP_MAX_DEPTH`（如 6 → ≤64 房间）；
> 但房间变多会按 `enemy_density` 线性增加敌人，**务必同步重标 `enemy_density`**（见 §12 P1），否则默认难度会暴涨。

---

## 2. 敌人 `data/enemies.json`（按 id，如 `enemy_infected`）

当前 **7 种**，按 `stage` 分 B/A/C 三层（B=开局常见，A=中期，C=后期/精英）：

| id | 阶段 | hp | damage | armor | loot_value_avg | 特点 |
|---|---|---|---|---|---|---|
| `enemy_infected` | B | 60 | 12 | 0 | 30 | 近战、反应 0s、跑得快（3.2） |
| `enemy_scav` | B | 100 | 10 | 3 | 90 | 手枪、有轻甲、反应慢（0.75s） |
| `enemy_raider` | A | 130 | 14 | 6 | 180 | 步枪 + 中甲 + 头盔，攻击间隔 0.55s |
| `enemy_marksman` | A | 90 | 34 | 3 | 260 | DMR、视距 24m、单发痛 |
| `enemy_drone` | C | 70 | 8 | 0 | 120 | SMG、脆但机动（2.5） |
| `enemy_brute` | C | 280 | 32 | 9 | 340 | 霰弹 + 重甲，血厚慢（1.1） |
| `enemy_boss_warden` | C | 650 | 30 | 9 | 1800 | 狙击 + 重甲，Boss |

字段说明：
| 字段 | 含义 | 取值范围 |
|---|---|---|
| `move_speed` | 移动速度 m/s | 1.1（屠夫）~ 3.2（感染体） |
| `sight_range_m` / `sight_angle_deg` | 视距 / 视锥角 | 9~24m / 70~140° |
| `hear_range_m` | 听觉半径 | 10~22m |
| `reaction_time` | 发现后反应延迟 s | 0（感染体/屠夫）~ 0.9（ Marksman ） |
| `give_up_dist_m` | 超过此距离放弃追击 | 18（屠夫）~ 70（Boss） |
| `attack_cooldown` | 攻击间隔 s | 0.5（无人机）~ 1.6（屠夫/Marksman） |
| `loot_value_avg` | 掉落平均价值（经济/掉落曲线） | 30 ~ 1800 |
| `armor` | 自带护甲值 0~10 | 0 ~ 9 |
| `color` | **身份色**（非警戒色，见第八轮 #3） | 7 种各异 |

类型由 `archetype` 决定（`melee`/`ranged`），行为在 `sim/ai/enemy_agent.gd`，数值全走本表。
> ⚠️ 上表数值为**已分层但未做 TTK/容错验证**的初版（见 §12 P0）。

---

## 3. 武器 `data/weapons.json`（按 id，如 `weapon_rifle`）

当前 **10 把**，按 `stage` 分 B/A/C 三层：

| id | 阶段 | damage | rpm | mag | reload | spread | range | recoil_v | value |
|---|---|---|---|---|---|---|---|---|---|
| `weapon_pistol` | B | 18 | 300 | 12 | 1.6 | 1.5° | 35 | 0.8 | 250 |
| `weapon_rifle` | B | 32 | 600 | 30 | 2.4 | 0.8° | 90 | 1.6 | 900 |
| `weapon_shotgun` | B | 95 | 70 | 6 | 3.2 | 6.5° | 18 | 4.2 | 700 |
| `weapon_smg` | A | 14 | 900 | 35 | 2.0 | 2.8° | 42 | 0.5 | 600 |
| `weapon_dmr` | A | 58 | 120 | 10 | 2.8 | 0.4° | 88 | 2.2 | 1400 |
| `weapon_lmg` | A | 30 | 700 | 75 | 5.2 | 1.6° | 70 | 1.4 | 1800 |
| `weapon_carbine` | C | 28 | 750 | 25 | 2.2 | 1.2° | 72 | 1.2 | 1100 |
| `weapon_rifle_sniper` | C | 120 | 40 | 5 | 3.5 | 0.2° | 120 | 3.5 | 2200 |
| `weapon_pistol_heavy` | C | 35 | 180 | 7 | 2.0 | 2.0° | 28 | 1.5 | 500 |
| `weapon_shotgun_auto` | C | 80 | 110 | 8 | 3.6 | 7.5° | 16 | 5.0 | 1300 |

字段说明：
| 字段 | 含义 | 取值范围 |
|---|---|---|
| `damage` | 单发伤害 | 14（SMG）~ 120（狙击） |
| `rpm` | 射速（发/分） | 40（狙击）~ 900（SMG） |
| `mag_size` | 弹匣容量 | 5（狙击）~ 75（LMG） |
| `reload_time` | 换弹时间 s | 1.6 ~ 5.2 |
| `spread_deg` | 基础散布角 ° | 0.2（狙击）~ 7.5（连喷） |
| `range_m` | 有效射程 m（影响伤害衰减，见 §5） | 16（连喷）~ 120（狙击） |
| `recoil_v` / `recoil_h` | 垂直/水平后坐 | 0.4 ~ 5.0 |
| `aim_cone_deg` | 该枪辅助瞄准锥半角（逻辑上限，见 §6） | 30（狙击）~ 55（步枪） |
| `weight` / `value` | 重量 / 售价基准 | 1.1~6.8 kg / 250~2200 元 |
| `ammo_id` | 消耗弹药类型（换枪备弹按此取，见第八轮 #3b） | `ammo_pistol`/`ammo_rifle`/`ammo_shell` |

> ⚠️ `SIMPLE_WEAPON` 占位已移除（全仓 0 引用），上表即真实手感；但**整套 TTK/容错未验证**（见 §12 P0）。

---

## 4. 物品 `data/items.json`（按 id）
| 字段 | 含义 | 默认/备注 |
|---|---|---|
| `value` | 基准售价（商人买价 = value×1.9，卖价 = value×`BASE_SELL_RATIO`） | 见 json |
| `weight` | 重量 kg | 见 json |
| `stack_max` | 单槽堆叠上限 | 见 json |
| `armor` | 护甲值 0~10（仅 armor 类，已接战斗，第七轮） | 见 json |
| `durability` | 装备耐久上限（损耗系统） | 见 json |
| `carry_slots` | **背包专用**：穿上后本局随身格数（第八轮 #3a） | 战术14/突击18/大容量24 |
| `carry_weight` | **背包专用**：穿上后本局负重上限 kg | 30/38/50 |

---

## 5. 伤害 / 部位模型 `sim/combat/damage_model.gd`（常量，谨慎改）
| 常量 | 含义 | 当前值 |
|---|---|---|
| `MULT.head` / `MULT.torso` / `MULT.limb` | 部位倍率（2D 俯视无爆头，用"弱点"替代） | 2.0 / 1.0 / 0.7 |
| `MIN_FALLOFF` | 超出射程后最少保留的伤害比例 | 0.40 |

精度/距离衰减算法在 `DamageModel.accuracy_at()`，数值走 §3 的 `range_m`/`spread_deg`。

### 5.1 玩家生命 / 护甲 `sim/vitals.gd` + `view/raid_scene.gd`

**玩家侧唯一数值源**（第七轮 #3 接装备护甲后清理为单路径）：
| 项 | 含义 | 当前值 / 来源 |
|---|---|---|
| `max_hp` | 玩家血量 | **100**（`sim/raid/raid_session.gd:28`） |
| 护甲池 | **唯一来源 = 身上装备**（没穿 = 0） | `raid_scene._player_armor()` → `Equipment.worn_armor()`；护甲值见 §4 的 `armor` 字段 |
| `DamageModel.armor_multiplier(pen, armor)` | 弹型穿透 → 通过比例 | `0.25 + 0.75 × clamp(pen/armor, 0, 1)`：pen=甲 → 全过；pen=0 → 只过 25% |
| 敌人统一按标准弹结算 | 敌人打玩家用的穿透 | `ammo_rifle` 的 `pen = 3`（`raid_scene.gd:310`） |
| `Vitals.ARMOR_ABSORB` | 旧路径吸收比例（仅老测试在用） | 0.55 |
| 护甲耐久磨损 | 每吸收 6 点伤害 = 1 点耐久 | `raid_scene.gd:318`（护甲/头盔各摊一半） |
| `BLEED_DPS` | 流血每秒伤害 | 轻 0.35 / 重 1.2 |
| `OVERWEIGHT_SLOWDOWN` | 超重减速（每超 1 倍负重） | 0.45 |
| 低血跛行 | hp < 30% 时移速插值 | 0.6 → 1.0 |

> ⚠️ 这套数值是 **P0 TTK 验证的基准**：敌人 §2 的 `damage` 打 100 血玩家 = 几枪倒；
> 玩家用 §3 武器打 §2 敌人的 `hp`/`armor` = 几发杀。两侧都还没实算（见 §12 P0）。

---

## 6. 辅助瞄准 / 自动瞄准（常量，全局生效）
`sim/combat/aim_assist.gd`：
| 常量 | 含义 | 当前值 |
|---|---|---|
| `PLAYER_VISION_HALF_DEG` | **玩家视野锥硬门限**（第八轮 #1，绘制与逻辑同源） | 40.0 |
| `BASE_HALF_ANGLE_DEG` | 基础辅助半角 | 4.2 |
| `MAX_BEND_DEG` | 单发最大偏转 | 6.0 |
| `WEAPON_CONE_RATIO` | 武器锥 = 武器 `aim_cone_deg` × 此比 | 0.12 |
| `MIN/MAX_WEAPON_HALF_ANGLE` | 武器辅助半角夹取区间 | 2.0 / 7.5 |
| `ASSIST_RANGE_RATIO` | 辅助生效距离 = 武器射程 × 此比 | 0.85 |
| `DEFAULT_HIT_RADIUS` | 命中半径（格） | 0.45 |

`sim/combat/auto_aim.gd`：
| 常量 | 含义 | 当前值 |
|---|---|---|
| `LOCK_GRACE` | 锁定保持时间 s | 1.2 |
| `DEFAULT_RADIUS` | 扫描命中半径（格） | 0.45 |

> 想"调辅助瞄准强弱"优先动 `PLAYER_VISION_HALF_DEG` 与 `BASE_HALF_ANGLE_DEG`。

---

## 7. 后坐力 `sim/combat/weapon_state.gd`（常量）
| 常量 | 含义 | 当前值 |
|---|---|---|
| `RECOIL_PER_SHOT` | 每发累积后坐 | 0.16 |
| `RECOIL_RECOVERY_PER_SEC` | 每秒恢复 | 1.5 |
| `MAX_RECOIL` | 后坐上限 | 1.0 |

---

## 8. 藏身处升级 / 经济 `sim/hideout.gd`
升级树 `UPGRADES`（id → 参数）：
| id | 名称 | `base_cost` | `cost_growth` | `max_level` | `per_level`（每级效果） |
|---|---|---|---|---|---|
| `stash_size` | 仓库扩建 | 1500 | 1.8 | 5 | +8 仓库槽 |
| `carry_size` | 负重训练 | 1200 | 1.7 | 4 | +3 kg 负重上限 |
| `heal_speed` | 战地急救 | 1800 | 1.9 | 3 | 治疗 +12% |
| `merchant_rep` | 商人关系 | 2200 | 2.0 | 3 | 售价 +6% |

全局常量：
| 常量 | 含义 | 当前值 |
|---|---|---|
| `BASE_SLOT_COUNT` | 仓库基础槽位（2026-10-14 扩容：40→64） | 64 |
| `BASE_WEIGHT_LIMIT` | 仓库/负重基准 kg（实际近乎无限，靠升级拉开） | 20.0 |
| `PACK_SLOTS` | 携带背包固定槽（= `RaidSession.DEFAULT_CARRY_SLOTS`，须对齐） | 12 |
| `BASE_SELL_RATIO` | 商人基础回收比例（`merchant_rep` 每级 +0.06） | 0.55 |
| `REPAIR_PRICE_PER_POINT` | 每点耐久修理费（缺 1 点 = 2 元，全或无） | 2 |
| 商人买价 | 收购倍率（`hideout.gd:194` 硬编码，未做升级联动） | value × 1.9 |

> 仓库实际容量 = `BASE_SLOT_COUNT + stash_size等级 × 8`（当前 64 + 5×8 = **满级 104 槽**）。
> 想"仓库更宽松"调 `BASE_SLOT_COUNT` 或 `per_level`。
> 仓库界面（2026-10-14「优化藏身处仓库」）已是**分类标签 + 排序 + 全量滚动**（`ui/stash_panel.gd`），槽位价值可直接在上面核对。

---

## 9. 死亡损失策略（交给专家）
机制在 `sim/death_policy.gd`（纯函数，默认**全掉**）。参数从 `Hideout.raid_modifiers()` 注入本局：
| 参数（modifiers key） | 含义 | 当前默认 |
|---|---|---|
| `death_keep_equipment` | 身上装备保留比例 0~1 | 0.0 |
| `death_keep_carry` | 携带背包保留比例 0~1 | 0.0 |
| `death_insured` | 保险槽位（最值钱的前 N 个必留） | 0 |

> 想做"保险/找回/损失比例"，只改这三个默认值即可，算法不用动。

---

## 10. 地图生成参数 `sim/mapgen/map_generator.gd`（常量，慎改）
| 常量 | 含义 | 当前值 |
|---|---|---|
| `BSP_MAX_DEPTH` | BSP 切分最大深度（≤ 2^depth 房间；5→32，6→64） | 5 |
| `CYCLE_RATIO` | 回加环边比例 | 0.15 |
| `SPAWN_SAFE_GRAPH_DIST` | 出生点周围 N 跳内不刷敌（防贴脸） | 2 |
| `MAX_ATTEMPTS` | 生成失败重试上限 | 64 |

---

## 11. 携带容量来源说明（避免调错地方）
本局随身 `carry` 的**槽位/负重**来自：
- 槽位 = 装备的背包 ItemDef 的 `carry_slots`（第八轮 #3a）；**没穿背包则回退 12 格**。
- 负重 = `max(负重训练升级上限, 背包 ItemDef 的 carry_weight)`。
注入点：`view/raid_scene.gd`（建 `RaidSession` 前拼 `mods`）。调"带得更多"→ 改背包 `carry_slots`/`carry_weight`（§4）或 `carry_size` 升级（§8）。

---

## 验收
改完任意上述数值后：
```
tools\verify_all.ps1
```
退出码 0 = 数据/单测/集成全绿，可打包。视觉相关（地图大小、敌人配色）改动建议额外跑像素基线复核。

---

## 12. 待办清单（数值策划）

> **本清单已于 2026-10-13 按数据源逐项核对重写**（旧版本严重过期：写着"全为 `[ ]`"，
> 其中 7 项实际已完成）。核对方式 = 直接读 `data/*.json` 与 grep 代码，不靠记忆。
> 标 `[x]` = 已闭环（附证据）；`[ ]` = 真待办。每条指回上方章节。

### ✅ 已完成（2026-10-13 核对）

- [x] **关掉 `SIMPLE_WEAPON` 占位并填真实武器手感**
  - 证据：`view/raid_scene.gd` 已无 `SIMPLE_WEAPON` 任何引用（grep 全仓 0 命中）；
    10 把枪全部有真实 `spread_deg / recoil_v / recoil_h / range_m`（§3 表）
- [x] **敌人扩编并分层**（原 2 种 → 7 种，B/A/C 三层）
  - 证据：`data/enemies.json` 7 条，hp 60~650 / damage 8~34 / armor 0~9（§2 表）
- [x] **武器扩编**（原 3 把 → 10 把）
  - 证据：`data/weapons.json` 10 条，damage 14~120 / rpm 40~900 / mag 5~75（§3 表）
- [x] **物品扩表**（原 15 → 50+），含三背包容量已接 §4/§11
- [x] **掉落表建成**（9 张：common / extract / enemy_drop / armory / …）
  - 证据：`data/loot_tables.json` 每张 12~19 条，`weight` + `min`/`max` 均已填
- [x] **任务系统内容 + 事件接线闭环**
  - 证据：`data/missions.json` 4 个任务（初战告捷/全身而退/拾荒者/猎手，B/A 阶段）；
    `sim/raid/raid_session.gd` 已 emit `notify("kill")` / `notify("loot", n)` / `notify("extract")`，
    而 4 个任务的 objective 只用到这三种 type → **推进链路实测可达**
  - 注：`craft` / `survive` 两种 type 尚未 emit，新任务若要用需先接线
- [x] **`enemy_density` 按地图扩张重标**（0.9/1.4/1.8 → **0.7/1.1/1.4**，§1）
  - 注：因 `BSP_MAX_DEPTH=5` 封顶 ≤32 房间，仅扩尺寸不增房间；此轮已预防性压低
- [x] **藏身处仓库 UI 优化**（分类标签 + 三种排序 + 全量滚动）
  - 证据：`ui/stash_panel.gd`，已接 `view/hideout_scene.gd` 概览区「打开仓库」按钮

### 🔴 P0 —— 门1（B→A）卡点，剩余 2 项

- [ ] **死亡痛感策略定稿（门1 卡点一）**
  - 位置：`sim/death_policy.gd` + `Hideout.raid_modifiers()` 的 `death_keep_*` 旋钮（§9）
  - 现状：三旋钮全 `0.0 / 0.0 / 0` = **死亡掉光**，无保险购买 UI
  - 这是**设计决策不是填数**：需拍板保留比例 / 保险槽位；若做"花钱买保险"要另加购买界面（属功能）

- [ ] **敌人 / 武器难度的 TTK 与容错验证（门1 卡点二）**
  - 数据已分层填好（§2/§3），但**没验证过实际手感**：
    - 用 §3 武器表对 §2 敌人表算 TTK（如步枪 32 伤 vs 掠夺者 130 血/6 甲 = 几发？）
    - 敌人 DPS 对玩家（玩家多少血？见 §12 下方"待补"）能否构成威胁
  - 动作：算出关键对局的 TTK 表 → 判断"太脆/太硬" → 回改 §2/§3 数值
  - ⚠️ **前置缺口**：玩家 hp / 受击模型尚未在本文档登记（见下方"待补登记"）

### 🟠 P1 —— 经济相关剩余

- [ ] **物品 `value` 全表标定**
  - 位置：`data/items.json`（§4）
  - 现状：部分仍是占位值；它同时决定**卖价**与**死亡损失估值**，需全部合理

- [ ] **掉落权重的平衡性验证（蒙特卡洛）**
  - 位置：`data/loot_tables.json`（9 张表已建成，权重已填）
  - 现状：权重是初版填写，**没跑过"每局平均进账多少"**
  - 动作：按表 + 容器分布模拟 100 局，得出每局进账期望与方差，判断是否通胀/太穷

- [ ] **携带背包容量值复核**
  - 位置：`data/items.json` 三背包 `carry_slots / carry_weight`（§4/§11）
  - 现状：战术 14格/30kg、突击 18格/38kg、大容量 24格/50kg（机制已通，值待验）

### 🟡 P2 —— 经济闭环与任务数值

- [ ] **经济闭环测算**
  - 动作：把"每局进账（掉落价值 + 任务奖励）"对照 §8 的卖价 0.55 / 修理 2 元每耐久点 /
    升级树（stash 1500×1.8、carry 1200×1.7、heal 1800×1.9、merchant 2200×2.0），
    测算"升满一级要打几局"，判断是否太肝/通胀

- [ ] **任务奖励与目标数量标定**
  - 位置：`data/missions.json` 4 个任务的 `reward.wallet` / `objectives[].need`
  - 现状：初版值（200/300/250/500 元；击杀 3/8、搜刮 10、撤离 1），未对照经济曲线校验

### 📋 待补登记（本文档尚未覆盖的数据源）

以下数值**已生效但本文档没登记**，专家若要调需先补章节：
| 数据 | 位置 | 说明 |
|---|---|---|
| 弹药价格与携带量 | `data/items.json` 的 `ammo_*` | 每局开火成本，影响经济 |
| 商人收购价倍率 | `sim/hideout.gd`（买价 = value×1.9，见 §4） | §8 已登卖价，买价未登 |

### 优先级速查
| 优先级 | 项 | 为什么 |
|---|---|---|
| 🔴 P0 | 死亡痛感策略定稿 | 门1 卡点之一，纯设计决策 |
| 🔴 P0 | 敌人/武器 TTK 验证 | 门1 卡点之二，先补登玩家 hp |
| 🟠 P1 | 物品 value 全表标定 | 同时决定卖价与死亡估值 |
| 🟠 P1 | 掉落权重蒙特卡洛验证 | 表已建好，差验证 |
| 🟡 P2 | 经济闭环测算 | 依赖上面两项的结果 |
| 🟡 P2 | 任务奖励/目标标定 | 依赖经济曲线 |
