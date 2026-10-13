# 改动日志

> 按「新 → 旧」记录每一次入库。提交信息规范见 [specs/collab-push-checklist.md](specs/collab-push-checklist.md)。

---

## 2026-10-13 · 自动作战 / 敌人固定弹道 / 闪避

**类型**：`feat` · **范围**：`sim/` `view/` `ui/` `game/` `test/`

**验收**：`tools\verify_all.ps1` 退出码 **0** —— 单元 **1619 项 / 0 失败**、集成 **105 项 / 全过**、
数据契约 **0 错误 0 警告**；④ 像素基线在本环境无法成像（无交互式绘图会话），未作结论（该脚本已标明它非门槛）。
详细日志见 [specs/verify-2026-10-13-auto-combat.md](specs/verify-2026-10-13-auto-combat.md)。

### 需求（拥有者原话）

> 攻击方式改为自动锁定敌人进行攻击；玩家角色在地图里自动寻路；
> 遇到物品容器会自动搜索、拾取其中的物品；遇见敌人会自动攻击。
> 敌人的攻击为固定弹道，宽度为两倍人物判定身位，会固定锁定人物为中心，
> 即人物两侧的弹道均为 1 格人物身位。角色可以进行闪避操作，闪避的距离为 1.5 倍人物身位。

### 新增（6 个文件）

| 文件 | 作用 |
|---|---|
| `sim/combat/body_metrics.gd` | **身位换算的唯一来源**：判定半径 0.45 → 身位 0.9 逻辑格；弹道半宽 1 身位、总宽 2 身位、闪避 1.5 身位全部由它推导 |
| `sim/combat/lane_shot.gd` | 单条**固定弹道**：方向开火瞬间锁死；命中在「前沿扫过玩家」那一帧结算，于是飞行时间 = 闪避窗口 |
| `sim/combat/lane_shot_manager.gd` | 弹道集合与**延后结算**（`pending_damage` → 场景统一走护甲）；`incoming()` 供自动闪避预警 |
| `sim/combat/dodge.gd` | 闪避状态机：位移 1.5 身位、时长 0.18s、冷却 0.85s、无敌帧 0.22s |
| `sim/ai/player_autopilot.gd` | 自动作战决策（纯逻辑）：交战 / 搜刮 / 待机三态、卡住拉黑、走流场不穿墙 |
| `test/suites/s25_auto_combat.gd` | 7 个套件：身位换算 / 弹道几何 / 弹道管理器 / 敌人开火 / 自动作战 / 闪避 / 接线防回流 |

### 修改（9 个文件）

| 文件 | 改了什么 |
|---|---|
| `sim/ai/enemy_agent.gd` | `_fire_at()` 由「hitscan + 掷骰子决定是否命中」改为**放出一条固定弹道**；保留无管理器时的兼容结算路径 |
| `sim/combat/auto_aim.gd` | `scan_nearest()` / `update()` 增加 `omni`：自动作战时全向锁定，只保留「视线 + 阵营」两条硬原则 |
| `view/raid_sim_runner.gd` | 玩家侧流场预算、闪避位移分支、`_try_auto_dodge()`、`_tick_autopilot()` 与自动搜刮、抽出 `_apply_player_step()` 共用分轴碰撞、弹道结算段与统一受伤入口、移除敌人瞬时曳光 |
| `view/raid_scene.gd` | 4 个新字段（`player_flows` / `lane_shots` / `dodge` / `autopilot`）+ 初始化 + `_try_dodge()` / `_toggle_autopilot()` + 触屏接线 |
| `view/raid_drawer.gd` | 绘制固定弹道（预警走廊 + 飞行弹头），「看到多宽」即「判定多宽」 |
| `view/raid_input.gd` | `G` 切换自动作战、`Shift` 闪避 |
| `ui/touch_controls.gd` | 新增闪避按钮（沿右边缘竖排，刻意避开瞄准摇杆矩形）与 `dodge_pressed` 信号 |
| `ui/settings_menu.gd` | 辅助区新增「自动作战」开关 |
| `game/game_state.gd` | 跨场景设置 `autopilot` 并纳入存档读写 |

### 关键决策

1. **身位只有一个来源**：`BodyMetrics.BODY_WIDTH = 0.9` 逻辑格。三处数值全部由它推导，不许在别处写死。
2. **敌人开火不再是「掷骰子」**：改造前是 hitscan + 随机数，玩家站在空地上毫无办法；改造后是几何 ——
   站在弹道外就是打不到。伤害数值与部位仍走 `DamageModel`，只换了「是否命中」的模型。
3. **闪避为什么带无敌帧**：本作走廊**恒宽 1 逻辑格**，而人物判定宽 0.9 格 ——
   走廊里没有侧移 1.35 格的空间。只靠位移的话，「闪避躲弹道」在占地图很大比例的走廊里数学上不成立。
   于是：开阔处靠位移（1.5 身位 > 1 身位，一步就出去），走廊里靠无敌帧。理由写在 `dodge.gd` 文件头。

### 踩过的坑（本仓库已知坑的又一次复现，均已修）

- `var x := scene.xxx()` 在 duck-typed 链上**类型推断失败** —— `AGENTS.md` §4 点名过的那条（`lane_damage` / `applied` / `heavy`）。
- `match` 分支缩进错位：新增的 `KEY_G:` / `KEY_SHIFT:` 落进了 `KEY_C:` 体内，导致 `raid_input.gd` 解析失败、
  连带 `raid_scene.gd` 无法加载、**② 集成验证整项失败**。由 `verify_all.ps1` 当场抓出。

### 未验证

- **④ 像素基线**：截图脚本在本环境未产出 `art/_raw/_verify_now.png`，该项无结论（非门槛）。
- **真机手感**：弹速 11 格/秒、闪避冷却 0.85 秒、自动作战交战距离 3~8 格均为首版未调参数值，需安卓真机复核。

### 可调参数

| 参数 | 值 | 文件 |
|---|---|---|
| `LaneShot.DEFAULT_SPEED` | 11 格/秒 | `sim/combat/lane_shot.gd`（闪避窗口 = 距离 / 弹速） |
| `DodgeState.DURATION / COOLDOWN / INVULN_SEC` | 0.18 / 0.85 / 0.22 秒 | `sim/combat/dodge.gd` |
| `PlayerAutopilot.STANDOFF_MIN / MAX / ENGAGE_MAX` | 3.0 / 8.0 / 16.0 格 | `sim/ai/player_autopilot.gd` |
| `AUTO_DODGE_LOOKAHEAD` | 0.30 秒 | `view/raid_sim_runner.gd` |

### 操作方式

| 平台 | 自动作战 | 闪避 |
|---|---|---|
| PC | `G`（或 ESC 设置菜单） | `Shift` |
| 触屏 | 设置菜单 | 右侧按钮列「闪避」 |
