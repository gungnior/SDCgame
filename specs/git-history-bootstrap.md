# git 历史落地记录 —— 16 个逻辑提交怎么拆的

> 写于 2026-10-13 · 执行：WorkBuddy · 提交区间 `fe63a0e..c38f9c9`（本地 master，**未推 remote**）
> 验收：`tools\verify_all.ps1 -Fast` 退出码 0（单元 1555/0 + 集成 105/0 + 数据 0 错 0 警），
> 提交前后各跑一次，工作树与 HEAD 零差异。

## 为什么要拆

动手前整棵树有 **73 个修改 + 86 个未跟踪文件**全部未提交，横跨 W-00 ~ uiredesign 十几轮工作。
一个 "WIP" 巨提交对两人协作是三重的坏：没法 bisect、没法 review、回滚只能整体回滚。
拆成逻辑提交后，每个提交是一个可读的切片，`git log` 本身就是一部项目简史。

## ⚠️ 拆分原则：按主题，不按轮次（诚实声明）

**没有按 W-00/W-01/... 逐轮拆，因为拆不出来**——整棵树此前没有任何中间提交，
每轮的改动都叠在同一份工作树里，逐轮归属等于编造历史。实际按**主题层**切：

- 能唯一归属的（新文件 = 某轮独有的）严格归到该轮；
- 跨轮的协调者文件（`view/raid_scene.gd` 等 7 个）合并为**一个"汇总"提交**，
  提交信息里明确标注这是汇总性质，覆盖哪些轮次——见 `feat(view)` 提交。

## 提交地图（从旧到新）

| # | 提交 | 内容 | 代表文件 |
|---|---|---|---|
| 1 | `chore(git)` | .gitignore 补 `.workbuddy/`、修两处乱码注释 | `.gitignore` |
| 2 | `fix(determinism)` | W-00：hitstop 帧计数 + 验收工具两 bug + 专项确定性命令 | `feel/feel.gd`、`tools/check_determinism.ps1`、`specs/w00-determinism.md` |
| 3 | `test(adversarial)` | W-01：7 条证伪清单（6 条未能证伪，1 条发现真弱点） | `test/suites/s11_adversarial.gd` |
| 4 | `fix(ai)` | W-06：窄走廊侧翼穿墙，包夹点先夹到可走格 | `sim/ai/enemy_agent.gd` |
| 5 | `feat(data)` | 数据层：recipes/弹种/护甲/C 档武器敌人 + 契约测试 | `data/*.json`、`sim/defs/*`、`io/data_registry.gd`、`tools/validate_data.py` |
| 6 | `feat(art)` | W-04：tile 对比度（墙压暗/地提亮/描边加粗） | `art/tiles/*`、`tools/art/*`、`view/whitebox_painter.gd` |
| 7 | `feat(craft)` | 制造系统接入藏身处 + 阶段开关 A→C | `sim/craft_system.gd`、`ui/craft_panel.gd`、`game/game_state.gd` |
| 8 | `feat(missions)` | 任务系统框架 + 内容 | `sim/mission_system.gd`、`data/missions.json` |
| 9 | `feat(equipment)` | 装备打通：配装/穿脱/改枪/死亡连身掉/存档 v4 | `sim/equipment.gd`、`ui/{loadout,mod}_panel.gd`、`io/save_manager.gd` |
| 10 | `feat(containers)` | 世界容器 + 地图主题 + 生成加固（坏种子不刷 0 敌） | `sim/items/container.gd`、`sim/mapgen/*`、`data/{containers,maps,rooms}.json` |
| 11 | `feat(combat)` | 视野锥硬门限 + 穿甲模型 + 地图面板/拖拽/数量 prompt | `sim/combat/*`、`ui/{map_panel,qty_prompt,drag_ghost}.gd` |
| 12 | `feat(stash)` | 死亡损失策略 + 背包容量/按弹种备弹 + 分类排序 + 平衡文档 | `sim/death_policy.gd`、`ui/{stash,carry}_panel.gd`、`data/BALANCE_TUNING.md` |
| 13 | `feat(ui)` | 主菜单 + tokens + 主题修复 + 截图探针；主场景切主菜单 | `view/main_menu.*`、`ui/tokens.gd`、`project.godot` |
| 14 | `feat(view)` | **汇总提交**：战斗协调层多轮接线（静步/地图键/装备栏/身份色） | `view/raid_*.gd`、`ui/touch_controls.gd` |
| 15 | `chore(android)` | 一键真机验证 + 导出预设（0.24.0 + 模拟器预设） | `tools/android_verify.ps1`、`export_presets.cfg` |
| 16 | `docs` | 协作规则/任务板/交接文档同步 | `AGENTS.md`、`specs/*.md` |

## 过程中的两个小动作（透明记录）

1. **一次性补丁脚本 `tools/_patch_{data2,items}.py` 移入 `_install/tmp/`**（本地留底、不入库）——
   它们写死了 `D:/AAAASDC` 绝对路径，违反 AGENTS.md 的相对路径约定，且脚本自述"执行后可删除"。
2. **三个文件起初漏 stage**（`data/recipes.json` / `sim/defs/room_type_def.gd` / `project.godot`），
   已用 `--fixup` + `--autosquash` 非交互 rebase 归位到各自主题提交，未留"补提交"疤痕。

## 下一步（两人协作还差的事）

见 [workboard.md](workboard.md) 待办 **W-07**：建共享 remote（GitHub/Gitee）→ 两人各自 clone →
工具链本地自备 → 各跑一次 `verify_all.ps1` 确认退出码 0 再开工。
