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

**阶段范围（`roadmap-bac.md` §3）**

| 表 | B | A | C |
|---|---|---|---|
| items | 15 | 50 | 80 |
| weapons | 3 | 6 | 10 |
| enemies | 2 | 4 | 6 + 1 Boss |
| loot_tables | 3 | 5 | 8 |
| rooms | 3 | 3 | 5 |
| attachments | 0 | 12 | 40 |
| recipes | 0 | 0 | 40 |

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
| `stage` | string | ⬜ | `B` / `A` / `C`，默认 `B` |

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
| `stage` | string | ⬜ | |

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
| `stage` | string | ⬜ | |

**硬约束（`tech-stack.md` §5.9 / T-34）**

| 约束 | 理由 |
|---|---|
| `spawn` 的 `min_count == max_count == 1` | 出生点唯一 |
| `extract` 的 `min_count ≥ 2` | **撤离点至少两个**，否则玩家无选择 |
| `extract` 的 `min_graph_dist ≥ 4` | **防止出生即撤离**——这是撤离点设计的关键 |

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
- [x] 阶段数量与 `roadmap-bac.md` §3 一致

> ⚠️ **本文件与校验器是配套的。** 改 schema 必须同步改校验器，否则契约失效。
