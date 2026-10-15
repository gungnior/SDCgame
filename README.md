# 肉鸽 × 自动战斗 · 搜打撤 · 2D 像素俯视射击（安卓）

> just want make a little game with my firend
> —— 库主原话，建库时的自我介绍，保留于此

单机 PvE 撤离射击游戏。Godot 4.7 · GDScript · 目标平台 TapTap / 好游快爆。

**三个要素**：**搜打撤**（进图搜索-战斗-撤离，死亡掉落身上装备）·
**自动战斗**（一键自动寻路/搜刮/交火，`sim/ai/player_autopilot.gd`）·
**肉鸽**（每局地图结构随机 + 每局规则变体随机，局局不重样）。

**完全离线 · 零变现 · 不收集任何个人信息。**

---

## 当前状态

| 阶段 | 状态 |
|---|---|
| 技术调研（6 路） | ✅ 完成 |
| 规划（8 份 spec） | ✅ 完成 |
| **B 阶段：核心循环** | 🚧 **进行中** |
| A 阶段：完整搜打撤 | ⏳ 未开始 |
| C 阶段：内容充实 | ⏳ 未开始 |

## 文档

| 文件 | 内容 |
|---|---|
| [specs/action-plan.md](specs/action-plan.md) | **执行入口** —— 从这份开始 |
| [specs/roadmap-bac.md](specs/roadmap-bac.md) | B→A→C 递进路线与架构硬约束 |
| [specs/feasibility.md](specs/feasibility.md) | 范围冻结决策 D-01~D-18 |
| [specs/tech-stack.md](specs/tech-stack.md) | 技术选型 T-01~T-86 + 待验证清单 |
| [specs/art-pipeline.md](specs/art-pipeline.md) | 美术规范与生产流程 |
| [specs/reference-teardown.md](specs/reference-teardown.md) | 竞品拆解数值表 |
| [specs/third-party.md](specs/third-party.md) | 第三方资源登记与署名 |
| [specs/publishing-cn.md](specs/publishing-cn.md) | 国内上架合规 |
| [specs/automation.md](specs/automation.md) | 夜间批处理（错峰时段） |

## 目录结构

```
specs/          设计与规格文档
data/           游戏数据（JSON 为唯一真源）
tools/          构建与校验脚本
tasks/          夜间批处理任务队列
research/       技术调研原始报告
godot/          Godot 工程（待建）
```

## 关键约束

- 🚫 **不申请 `INTERNET` 权限**，代码内零网络请求
- 🚫 **零变现**：无内购、无广告、无打赏
- 🚫 **禁止商业游戏提取素材**
- ⚠️ **付费素材不入本仓库**

详见 [specs/feasibility.md](specs/feasibility.md) 的冻结决策表。

## 许可证

MIT（见 `LICENSE`；2026-10-13 由拥有者拍板，取代早期的 GPL-3.0 方案）。
第三方素材授权见 [specs/third-party.md](specs/third-party.md) 与 `CREDITS.md`。
