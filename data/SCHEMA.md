# 数据契约（Data Schema）

> **本文件是数据层的唯一契约。** 所有 `data/*.json` 必须符合这里的定义。
> 校验器：`tools/validate_data.py`（现在就能跑，不需要 Godot）。
> 关联：`specs/tech-stack.md` §6（JSON 为唯一真源）· `specs/roadmap-bac.md` §3（各阶段数据量）

---

## 0. 总则

| 规则 | 说明 |
|---|---|
| **唯一真源** | JSON 是唯一真源，运行时编译成 `Dictionary` 索引；**不生成 475 个 `.tres`**（T-64） |
| **编码** | **UTF-8 无 BOM** |
| **命名** | id 全小写 `snake_case`，全局唯一 |
| **中文** | `name` 用中文，`name_en` 用英文——用于本地化（T-70） |
| **图标路径** | 存 `res://` 字符串，加载时 `load()` 并缓存 |
| **类型** | JSON 只有数字。整数用 `int()` 转；**向量类字段一律用字符串**（如 `"Vector2i(2, 2)"` + `str_to_var()`） |
| **阶段标记** | 每条记录可带 `"stage"`（`"B"` / `"A"` / `"C"`），默认 `"B"`。用于递进路线的数据开关（D-17 约束 5） |

**阶段范围（`roadmap-bac.md` §3）** —— 下表是**当前实际条数**（C 档为进行中的值，目标是 items 80 / 配件 40 / 配方 40）

| 表 | B | A | C |
|---|---|---|---|
| items | 18 | 56 | **66** |
| weapons | 3 | 6 | **10** |
| enemies | 2 | 4 | **7**（含 1 Boss）|
| loot_tables | 3 | 3 | **9** |
| rooms | 3 | 3 | **8** |
| containers | 0 | 0 | **8** |
| maps | 0 | 0 | **3** |
| attachments | 0 | 12 | 12 |
| recipes | 0 | 0 | 12 |

---

## 1. `data/items.json`

**数组**，每项：

| 字段 | 类型 | 必填 | 约束 |
|---|---|---|---|
| `id` | string | ✅ | 唯一，`snake_case` |
| `name` | string | ✅ | 中文名 |
| `name_en` | string | ✅ | 英文名 |
| `category` | enum | ✅ | `medical` / `ammo` / `armor` / `backpack` / `consumable` / `valuables` / `key` / `misc` |
| `weight` | number | ✅ | kg，两位小数 |
| `stack_max` | int | ✅ | ≥1；不可堆叠为 1 |
| `icon` | string | ✅ | `res://art/items/{id}.png` |
| `value` | int | ✅ | ≥0，商人回收价（元） |
| `desc` | string | ✅ | 中文，≤20 字 |
| `treat` | object | ⬜ | **仅 medical 类用**：`{ hp, time, bleed, armor }` |
| `ammo_type` | enum | ⬜ | **仅 ammo 类**：`standard` / `ap` / `hp` |
| `pen` | number | ⬜ | **仅 ammo 类**：穿甲值 **0~10**，越高越能穿透护甲 |
| `flesh` | number | ⬜ | **仅 ammo 类**：对**无甲**目标的伤害倍率 |
| `durability` | int | ⬜ | **装备类**（weapon/armor/backpack）：最大耐久，损耗系统用 |
| `armor` | int | ⬜ | **仅 armor 类**：护甲值 **0~10**（0 = 无甲） |
| `carry_slots` | int | ⬜ | **仅 backpack 类**：本局携带背包的**槽位数**（≥1）。>0 时覆盖默认的 12 格；不填回退默认 |
| `carry_weight` | number | ⬜ | **仅 backpack 类**：本局携带背包的**负重上限 kg**（≥0）。>0 时取 `max(升级上限, 此值)`；不填回退升级上限 |
| `stage` | string | ⬜ | `B` / `A` / `C`，默认 `B` |

> ⚠️ `carry_slots` / `carry_weight` 的具体数值属于**平衡范畴**（见下文「数值平衡」），
> 由平衡专家在 `data/items.json` 调；`validate_data.py` 仅在缺省时给 warning、格式错误时报 error。

**`treat` 字段**（医疗物品的治疗参数，见 `sim/medical.gd`）

| 子字段 | 类型 | 含义 |
|---|---|---|
| `hp` | int | 回复血量 |
| `time` | number | **耗时秒数** —— 治疗期间不能移动/射击，这是真实的战术取舍 |
| `bleed` | bool | 是否同时止血 |
| `armor` | int | 修甲量（可选） |

### 弹药弹型（2026-10-13 新增）

同一口径下有**三种弹型**，围绕目标的 `armor`（护甲值）做取舍：

| 弹型 | `ammo_type` | `pen` | `flesh` | 优势 | 劣势 |
|---|---|---|---|---|---|
| 标准弹 | `standard` | 中（3） | 中（1.0） | 万金油 | 没有突出项 |
| 穿甲弹 | `ap` | **高**（7~8） | **低**（0.7~0.8） | **打有甲单位** | 打无甲单位反而弱 |
| 肉伤弹 | `hp` | **低**（0） | **高**（1.4~1.5） | **打无甲单位** | 几乎打不穿甲 |

**伤害结算**（`sim/combat/damage_model.gd::resolve_vs_armor`）：
```
有甲目标：基础伤害 × flesh × (0.25 + 0.75 × clamp(pen / armor, 0, 1))
无甲目标：基础伤害 × flesh
```
即：**打有甲看 `pen`，打无甲看 `flesh`** —— 这正是两种特殊弹的取舍来源。

**契约级约束**（`validate_data.py` 会强制检查）：
穿甲弹的 `pen` 必须 **>** 标准弹均值、`flesh` 必须 **<** 标准弹均值；肉伤弹反之。
这条防止有人把某个弹种写成"全能弹"从而取消取舍。

> 💡 每把枪的 `ammo_id` 指向**标准弹**（默认装填）。换弹种是玩家的选择，不是武器的属性。

---

## 2. `data/weapons.json`

**数组**，每项：

| 字段 | 类型 | 必填 | 约束 |
|---|---|---|---|
| `id` | string | ✅ | 唯一 |
| `name` / `name_en` | string | ✅ | |
| `category` | enum | ✅ | 固定 `weapon` |
| `ammo_id` | string | ✅ | 必须存在于 `items.json` 且 `category == "ammo"` |
| `damage` | int | ✅ | ≥1 |
| `rpm` | int | ✅ | >0，发/分钟 |
| `mag_size` | int | ✅ | ≥1 |
| `reload_time` | number | ✅ | >0，秒 |
| `spread_deg` | number | ✅ | ≥0 |
| `range_m` | int | ✅ | >0 |
| `recoil_v` / `recoil_h` | number | ✅ | ≥0 |
| `weight` | number | ✅ | kg |
| `value` | int | ✅ | ≥0 |
| `icon` | string | ✅ | `res://art/guns/{id}/base.png` |
| `stage` | string | ⬜ | |

**平衡直觉**：手枪 range_m 最小、霰弹枪散布最大换弹最慢、步枪是全能基准。

---

## 3. `data/enemies.json`

**数组**，每项：

| 字段 | 类型 | 必填 | 约束 |
|---|---|---|---|
| `id` / `name` / `name_en` | | ✅ | |
| `archetype` | enum | ✅ | `melee` / `ranged` |
| `hp` | int | ✅ | ≥1 |
| `move_speed` | number | ✅ | 米/秒 |
| `sight_range_m` | int | ✅ | >0 |
| `sight_angle_deg` | int | ✅ | 1–360 |
| `hear_range_m` | int | ✅ | ≥0 |
| `reaction_time` | number | ✅ | 秒。⚠️ **`ranged` 不得低于 0.25**——低于此值会被玩家感知为「不公平」 |
| `give_up_dist_m` | int | ✅ | ≥`sight_range_m` |
| `damage` | int | ✅ | ≥1 |
| `attack_cooldown` | number | ✅ | >0，秒 |
| `loot_value_avg` | int | ✅ | ≥0 |
| `sprite` | string | ✅ | `res://art/enemies/{id}/side/idle_00.png` |
| `armor` | int | ⬜ | **0~10，0 = 无甲**（穿甲弹/肉伤弹就是围绕它取舍的） |
| `color` | string | ⬜ | `#rrggbb` / `#rrggbbaa` —— **敌人类型身份色**（2026-10-13 真机反馈 #3）。缺省时按 `id` 稳定派生。与「警戒状态色」（放松/警觉/交战，画成外圈环）是**两条独立通道** |
| `stage` | string | ⬜ | |

> 敌人还带 `weapon_id` / `armor_id` / `helmet_id`（C 阶段敌人装备系统，死后掉进尸体）。

---

## 4. `data/loot_tables.json`

**数组**，每项：

| 字段 | 类型 | 必填 | 约束 |
|---|---|---|---|
| `id` | string | ✅ | 唯一 |
| `name` | string | ✅ | |
| `entries` | array | ✅ | ≥1 项 |
| `entries[].item_id` | string | ✅ | 必须存在于 `items.json`（**交叉引用校验**） |
| `entries[].weight` | int | ✅ | >0，相对权重 |
| `entries[].min` / `.max` | int | ✅ | `0 ≤ min ≤ max` |
| `stage` | string | ⬜ | |

---

## 5. `data/rooms.json`

**数组**，每项：

| 字段 | 类型 | 必填 | 约束 |
|---|---|---|---|
| `id` / `name` | | ✅ | |
| `room_type` | enum | ✅ | `spawn` / `common` / `extract` |
| `min_count` / `max_count` | int | ✅ | `0 ≤ min ≤ max` |
| `loot_table_id` | string | ✅ | 必须存在于 `loot_tables.json`（**交叉引用校验**） |
| `enemy_budget_min` / `_max` | int | ✅ | `0 ≤ min ≤ max` |
| `min_graph_dist` | int | ✅ | ≥0，距出生点的最小图距离（跳数） |
| `containers` | array | ⬜ | 该房间生成哪些容器：`[{container_id, count_min, count_max}]`，见 §9 |
| `weight` | int | ⬜ | 主题分配权重。**多个 `common` 类房间类型**按它按比例分配 |
| `stage` | string | ⬜ | |

**`room_type` 与「房间主题」是两回事**

`room_type` 只有 3 个值（拓扑角色）：`spawn` / `common` / `extract`。
但 **`common` 角色可以有多个房间类型定义**（军械库 / 医疗室 / 宿舍 / 仓库 / 实验室…），
它们各自有不同的 `loot_table_id`、`containers`、`enemy_budget`。
地图生成时，普通房间会按各定义的 `weight` **按比例抽主题** —— 这就是"更多房间类型"。

**硬约束（`tech-stack.md` §5.9 / T-34）**

| 约束 | 理由 |
|---|---|
| `spawn` 的 `min_count == max_count == 1` | 出生点唯一 |
| `extract` 的 `min_count ≥ 2` | **撤离点至少两个**，否则玩家无选择 |
| `extract` 的 `min_graph_dist ≥ 4` | **防止出生即撤离**——这是撤离点设计的关键 |

---

---

## 7. `data/attachments.json`（A 阶段）

**数组**，每项：

| 字段 | 类型 | 必填 | 约束 |
|---|---|---|---|
| `id` | string | ✅ | 唯一 |
| `name` / `name_en` | string | ✅ | |
| `slot` | enum | ✅ | `sight` / `muzzle` / `grip` / `mag` |
| `mods` | object | ✅ | 字段 → **增量**（正负皆可） |
| `weight` | number | ✅ | kg |
| `value` | int | ✅ | ≥0 |
| `icon` | string | ✅ | `res://art/items/{id}.png` |
| `desc` | string | ✅ | |
| `stage` | string | ⬜ | 默认 `A` |

**`mods` 允许的字段**（`sim/items/weapon_modding.gd` 的 `MODIFIABLE`）：
`damage` · `rpm` · `mag_size` · `reload_time` · `spread_deg` · `range_m` ·
`recoil_v` · `recoil_h` · `weight` · `noise_m`（**未知字段会被忽略**，防脏数据）

**数值下限**（`FLOORS`）：伤害 ≥1 · 射速 ≥20 · 弹匣 ≥1 · 换弹 ≥0.3s · 散布 ≥0 · 射程 ≥3m
—— 保证塞满负向配件也不会出现负数伤害这类荒谬结果。

**每把枪的插槽数**：A 阶段 **2 个**（`WeaponModding.SLOTS_A`），C 阶段 **4 个**（`SLOTS_C`），
顺序按 `AttachmentDef.SLOTS` = `[sight, muzzle, grip, mag]`。

> ⚠️ `attachments.json` **只由 GDScript 的 `DataRegistry` 校验**（Python 校验器暂未覆盖）。
> B 阶段允许该文件缺失。

---

## 6. 校验器覆盖范围

`tools/validate_data.py` 检查：

- [x] JSON 可解析、UTF-8、无 BOM
- [x] 必需字段齐全、类型正确
- [x] id 唯一
- [x] 枚举值合法
- [x] 数值范围（如 `stack_max ≥ 1`、`min ≤ max`）
- [x] **交叉引用**：`weapons.ammo_id` → items；`loot_tables.entries[].item_id` → items；`rooms.loot_table_id` → loot_tables
- [x] **房间硬约束**（spawn 唯一 / extract ≥2 / extract 图距离 ≥4）
- [x] `enemies` 中 ranged 的 `reaction_time ≥ 0.25`
- [x] **弹型平衡**（穿甲弹 pen>标准、flesh<标准；肉伤弹反之）
- [x] **护甲范围**（items.armor / enemies.armor ∈ 0~10）
- [x] **容器交叉引用**（`rooms.containers[].container_id` → containers；`containers.loot_table_id` → loot_tables）
- [x] **地图主题交叉引用**（`maps.room_weights` → rooms；`maps.enemy_weights` → enemies）
- [x] 阶段数量与 `roadmap-bac.md` §3 一致

> ⚠️ **本文件与校验器是配套的。** 改 schema 必须同步改校验器，否则契约失效。

---

## 8. `data/recipes.json`（C 阶段）

**数组**，每项：

| 字段 | 类型 | 必填 | 约束 |
|---|---|---|---|
| `id` | string | ✅ | 唯一，`snake_case` |
| `name` / `name_en` | string | ✅ | |
| `station` | enum | ✅ | `bench` / `forge` / `lab` / `kitchen` |
| `inputs` | array | ✅ | ≥1 项 |
| `inputs[].item_id` | string | ✅ | 必须存在于 `items.json`（**交叉引用校验**） |
| `inputs[].count` | int | ✅ | ≥1 |
| `output_item_id` | string | ✅ | 必须存在于 `items.json`（**交叉引用校验**） |
| `output_count` | int | ✅ | ≥1 |
| `time` | number | ✅ | ≥0，秒 |
| `stage` | string | ⬜ | 默认 `C` |

⚠️ `recipes.json` 默认不存在（C 阶段才引入）；`DataRegistry` 与 `validate_data.py` 都允许其缺失。

---

## 9. `data/containers.json`（C 阶段）

**容器 = 房间里真正能搜的东西。** 它把「房间类型 → 容器 → 物品」串起来：

```
room_type.containers[]  →  container.id  →  container.loot_table_id  →  items
```

**数组**，每项：

| 字段 | 类型 | 必填 | 约束 |
|---|---|---|---|
| `id` | string | ✅ | 唯一，`snake_case` |
| `name` | string | ✅ | 中文名 |
| `capacity` | int | ✅ | ≥1，容器内可容纳的物品种类数 |
| `loot_table_id` | string | ✅ | 必须存在于 `loot_tables.json`（**交叉引用校验**） |
| `search_time` | number | ✅ | ≥0，搜索耗时（秒）—— 搜得越久越暴露 |
| `desc` | string | ⬜ | 中文说明 |
| `stage` | string | ⬜ | 默认 `C` |

⚠️ 与 `recipes.json` 一样，C 阶段才引入；B/A 阶段允许缺失。

---

## 10. `data/maps.json`（C 阶段）

**地图主题** = 进图前的"这是哪种地方"。它一次性决定 5 件事：

| 维度 | 字段 | 说明 |
|---|---|---|
| 地图多大 | `map_w` / `map_h` | **逻辑格**数（1 逻辑格 = 3 tile）。越大房间越多、敌人越多 |
| 房间配额 | `room_weights` | `{room_def_id: weight}`，普通房间按权重抽主题 |
| 敌人种类 | `enemy_weights` | `{enemy_id: weight}`，**这个主题刷哪些敌人** |
| 敌人密度 | `enemy_density` | 敌人总数 ≈ `房间数 × enemy_density`（再按房间预算分配） |
| 白模色调 | `tile_theme` | `dirt` / `concrete` / `metal`（白模阶段用色调区分主题，不写死美术） |

**数组**，每项：

| 字段 | 类型 | 必填 | 约束 |
|---|---|---|---|
| `id` / `name` / `desc` | string | ✅ | |
| `map_w` / `map_h` | int | ✅ | 8~128（逻辑格） |
| `enemy_density` | number | ✅ | ≥0 |
| `tile_theme` | enum | ✅ | `dirt` / `concrete` / `metal` 等（**渲染层按它选白模色调**） |
| `room_weights` | object | ✅ | 非空；键必须存在于 `rooms.json`（**交叉引用校验**） |
| `enemy_weights` | object | ✅ | 非空；键必须存在于 `enemies.json`（**交叉引用校验**） |
| `stage` | string | ⬜ | 默认 `C` |

**当前 3 个主题**：`map_forest` 森林（34×34，感染体为主）、
`map_urban` 城区（40×40，拾荒者/劫掠者混编）、`map_military` 军事基地（44×44，重装单位）。
