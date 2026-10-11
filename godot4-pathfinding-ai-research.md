# Godot 4 寻路与游戏 AI 技术方案调研

> **核查时间**：截至 **2026 年 10 月初**（依据 godotengine.org/versions.json 与各仓库 pushedAt 元数据）
> **当前 Godot 稳定版**：**4.7.2**（2026-08-18 发布）；4.8 处于 dev 阶段（dev7，2026-09-29）
> **方法说明**：本报告的每一条项目名/作者/链接/授权/时间，均通过实际抓取 GitHub 仓库文件（LICENSE、project.godot、README、源码）、GitHub API 镜像（ungh.cc）、Godot 官方文档源文件（godot-docs 仓库 .rst）、Godot 官方类参考源文件（godot 仓库 doc/classes/*.xml）与 Godot Asset Library 页面核实。**凡无法核实的均明确写"待确认"，不做推测。**
> **授权判定原则**（按你的约束）：MIT / Apache-2.0 / CC0 / GPL-3.0 / AGPL / LGPL-3.0 → 可用；**GPL-2.0 / LGPL-2.1 → 禁止**；**未声明授权 → 视为保留所有权利，只能参考思路，不能复制代码**。

---

## A. 寻路

### A.1 Godot 4 内置能力

| 技术 | 解决什么问题 | 适用 / 不适用 | 授权 | 维护状态 | 结论 | 链接 |
|---|---|---|---|---|---|---|
| **AStarGrid2D** | 部分网格上的 A*，格点自动互联，无需手建点/边 | **适用**：固定方格、随机生成关卡、可破坏墙体（`set_point_solid` 后**无需** `update()`）、需要权重代价（沼泽/危险区）<br>**不适用**：连续空间、非方格拓扑 | Godot 引擎自带（MIT，引擎内） | 引擎核心，随版本维护 | **【可直接使用】** | [类参考](https://docs.godotengine.org/en/stable/classes/class_astargrid2d.html) · [官方 XML 源](https://github.com/godotengine/godot/blob/4.4/doc/classes/AStarGrid2D.xml) |
| **AStar2D** | 任意点+边图的 A*（加权路点图） | **适用**：路点图（门口、掩体点、巡逻点）、成本驱动的连接关系<br>官方原话："best suited for cell-based 2D gameplay that does not require actors to reach any possible position within an area but only predefined, distinct positions"<br>**不适用**：需要"走到区域内任意一点" | 引擎自带（MIT） | 引擎核心 | **【可直接使用】** | [类参考](https://docs.godotengine.org/en/stable/classes/class_astar2d.html) · [2D 导航总览](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_2d.html) |
| **NavigationServer2D / NavigationRegion2D / NavigationPolygon / NavigationAgent2D** | 基于导航多边形（导航网格）的路径查询 + 路径跟随 + RVO 避让 | **适用**：连续空间、需要"到达区域内任意位置"、大世界（官方："a large area can often be defined with a single polygon when it would require many, many grid cells"）<br>**不适用**：地块频繁翻转（重烘焙贵） | 引擎自带（MIT） | 引擎核心 | **【可直接使用】** | [2D 导航总览](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_2d.html) · [NavigationRegion2D](https://docs.godotengine.org/en/stable/classes/class_navigationregion2d.html) · [NavigationAgent2D](https://docs.godotengine.org/en/stable/classes/class_navigationagent2d.html) |
| **NavigationObstacle2D** | ①导航网格烘焙时挖洞 ②约束避让智能体的速度 | **关键事实：它不影响寻路**。官方原文："This Node does NOT affect the pathfinding of agents. You need to change the navigation meshes for that instead." | 引擎自带（MIT） | 引擎核心 | **【可直接使用】**（但**不能**用来做"动态阻挡改变路径") | [使用 NavigationObstacles](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationobstacles.html) |
| **NavigationLink2D** | 在导航网格之间建立任意距离的连接（门、跳台、传送） | 可运行时 **enable/disable** → 门开关的零成本方案 | 引擎自带（MIT） | 引擎核心 | **【可直接使用】** | [2D 导航总览](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_2d.html) |
| **TileMapLayer（4.3+）导航层** | 用 TileSet 编辑器画导航层，自动生成 NavigationPolygon | 适用：瓦片地图关卡快速出导航 | 引擎自带（MIT） | 引擎核心 | **【可直接使用】** | [2D 导航总览](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_2d.html) · [TileMapLayer 迁移说明](https://docs.godotengine.org/en/stable/tutorials/migrating/upgrading_to_godot_4.5.html) |
| **官方 Demo：2D Navigation / AStarGrid2D** | 官方最小可运行示例 | 直接抄结构 | **MIT**（已核验 LICENSE.md） | 官方维护 | **【可直接使用】** | [godot-demo-projects LICENSE](https://github.com/godotengine/godot-demo-projects/blob/master/LICENSE.md) · [2d/navigation](https://github.com/godotengine/godot-demo-projects/tree/master/2d/navigation) · [2d/navigation_astar](https://github.com/godotengine/godot-demo-projects/tree/master/2d/navigation_astar) |

#### ⚠️ 必读的坑（均已核验文档原文）

1. **`AStarGrid2D.update()` 会清空所有点数据**：官方注释 "All point data (solidity and weight scale) will be cleared." 只有 `set_point_solid()` / `fill_solid_region()` / `set_point_weight_scale()` 才不需要 `update()`。改 `region`/`cell_size`/`offset`/`cell_shape` 才需要 `update()`，但必须重设所有 solid/weight。
2. **AStarGrid2D 的路径查询不是线程安全的**：`get_id_path()` / `get_point_path()` 官方注明 "This method is not thread-safe. If called from a Thread, it will return an empty array and will print an error message." → **不能**把每帧 A* 丢到 Thread 里省时间，只能分帧错峰或改用流场。
3. **`jumping_enabled = true`（JPS 加速）会忽略 weight_scale**：官方注明 "toggling it on disables the consideration of weight scaling in pathfinding." → 想要权重代价就不能开 JPS。
4. **AStarGrid2D 提供 4 种启发式 + 4 种对角模式**：`HEURISTIC_EUCLIDEAN / MANHATTAN / OCTILE / CHEBYSHEV`；`DIAGONAL_MODE_ALWAYS / NEVER / AT_LEAST_ONE_WALKABLE / ONLY_IF_NO_OBSTACLES`。**避免角色"贴角穿墙"必须用 `ONLY_IF_NO_OBSTACLES` 或 `AT_LEAST_ONE_WALKABLE`**（`DIAGONAL_MODE_ALWAYS` 会无视实心邻居直接从障碍对角穿过）。
5. **NavigationAgent2D 的避让有明确性能警告**：`avoidance_enabled` 官方说明 "Avoidance processing with many registered agents has a significant performance cost and should only be enabled on agents that currently require it." → **不要给全部 30 个敌人无脑开 RVO 避让**。
6. **NavigationAgent2D 的 `radius` 不影响寻路**：官方说明 "Does not affect normal pathfinding. To change an actor's pathfinding radius bake NavigationMesh resources with a different agent_radius property and use different navigation maps for each actor size."
7. **必须每物理帧调用一次 `get_next_path_position()`** 来推进内部路径逻辑；`is_navigation_finished()` 为 true 时应停止调用（官方警告：反复调用会导致站立中的智能体抖动）。
8. **首帧拿不到路径**：官方注记 "On the first frame the NavigationServer map has not synchronized region data and any path query will return empty." → 需 `await get_tree().physics_frame`。
9. **`NavigationRegion2D` 在 4.4 类文档里带 `experimental` 标记**（`<class name="NavigationRegion2D" ... experimental="">`，`NavigationAgent2D` / `NavigationObstacle2D` 同样带该标记）——这是导航系统重构期的标记。4.5/4.6/4.7 是否已摘掉该标记**我本次未逐版核对 → 待确认**。如果你们对 API 稳定性敏感，建议在目标 Godot 版本的编辑器里查一次类文档。

#### 选型速查（针对你的场景）

| 你的需求 | 该用哪个 |
|---|---|
| 随机生成的房间/地牢，格子可破坏 | **AStarGrid2D**（`set_point_solid` 立即生效、无需 update） |
| 20–30 个敌人追同一个玩家 / 同一个撤离点 | **自研 Flow Field**（见 A.2） |
| 只想做"Squad 走位到掩体点/巡逻点" | **AStar2D** 路点图 或 **NavigationLink2D** |
| 开阔大地图 + 复杂可破坏地形 | **NavigationServer2D + NavigationPolygon**（但墙体多变就要频繁重烘焙，慎用） |

---

### A.2 Flow Field（流场寻路）

#### 权威否定结论（重要）

**Godot 官方 Asset Library 中没有任何 Flow Field 资产。** 我用官方站内检索 `filter=flow+field` 实测结果为 **"40 items per page, 0 items total."** → 即：**Godot 4 生态没有现成的、可安装的流场寻路插件。必须自研。**

| 项目 | 解决什么问题 | 适用 / 不适用 | 授权 | 最后更新（代码推送） | Godot 版本兼容 | 结论 | 链接 |
|---|---|---|---|---|---|---|---|
| **Griiimon/Manymies** | GDScript 参考实现：流场（`solutions/flowfield.gd`）+ 方向流场（`directional_flowfield.gd`）+ 网格 A*（`grid pathfinding/grid_pathfinding.gd`）+ 三种分离方案（Area2D 软分离 / 射线转向 / RigidBody2D），README 宣称 **"3 solutions with 1000+ enemies at 60fps"** | **适用**：作为你们自研流场的**最佳起点**；代码短、可读、纯 GDScript、含调试绘制<br>**不适用**：不能直接当库用（无插件结构、依赖它的 `Global` 单例、`TileMapLayer`） | **MIT**（LICENSE 已逐字核验，Copyright (c) 2024 Griiimon） | **2025-06-03**（82 stars） | **Godot 4.3**（`project.godot`: `config_features=PackedStringArray("4.3","GL Compatibility")`）；用了 **TileMapLayer**（4.3+ API），4.3 以下不可用 | **【需改造】** | [GitHub](https://github.com/Griiimon/Manymies) · [flowfield.gd](https://github.com/Griiimon/Manymies/blob/main/solutions/flowfield.gd) |
| **nathanfranke-archive/gdmapf** | GDExtension 版多智能体寻路，README 自述为 **"modified flow-field algorithm"** | **不适用**：① **仅 3D**（`src/` 只有 `pathfinding_agent_3d` / `pathfinding_region_3d` / `pathfinding_server_3d`，`register_types.cpp` 只注册 3D 类）② **无 Android 二进制**（`.gdextension` 的 libraries 只列 macos/windows/linux）③ README 顶部两条警告：**"This will not receive updates"** + **存在智能体对撞卡死的已知重大 bug** | **MIT**（LICENSE 已逐字核验，Copyright (c) 2022 Nathan Franke） | **2024-12-12**（11 stars，仓库已 archive 归档） | GDExtension（需自行编译），3D only | **【不可用】**（3D + 无 Android + 已归档 + 已知卡死 bug）；**仅参考思路** | [GitHub](https://github.com/nathanfranke-archive/gdmapf) · [README](https://github.com/nathanfranke-archive/gdmapf/blob/main/README.md) |
| **kvbc/godot-FlowFieldPathfinding** | 引擎模块（C++ module）形式的流场寻路，支持最多 1000 个 agent（`FFP_MAX_AGENTS`），带 agent 占位（避免互相卡位） | **不可用**：① **Godot 3 专用**——源码 `#include "core/reference.h"`、`class FlowFieldPathfinding : public Reference`、`VARIANT_ENUM_CAST`，全是 Godot 3 API（Godot 4 已改为 `RefCounted` / `core/object/ref_counted.h`）② 是**引擎模块**（`SCsub` + `config.py`），意味着**必须从源码重编译整个 Godot**，无法用于 Android 导出流程 | **MIT**（已逐字核验，Copyright (c) 2023 Matt） | **2023-06-20**（6 stars，仅 1 次提交） | **仅 Godot 3**（源码 API 已证实） | **【不可用】**（Godot 3）→ **仅参考思路**（其 agent 占位设计值得读） | [GitHub](https://github.com/kvbc/godot-FlowFieldPathfinding) |
| **arnemileswinter/godot-tilemap-flowfields** | 从 TileMap 生成流场的插件，Rust 原生（`native/src/algo.rs`、`flowfield.rs`）+ GDNative | **不可用**：① **Godot 3 专用**——`project.godot` 为 `config_version=4`、`_global_script_classes` 用 `NativeScript` + `.gdns`、`PoolStringArray`，并且是 **GDNative**（`.gdnlib`/`.gdns`）而 Godot 4 已换成 **GDExtension** ② 只带 Linux `.so` 与 Windows `.dll`，**无 Android 库** | **MIT**（已逐字核验，Copyright (c) 2022 Arne Winter） | **2022-10-24**（32 stars） | **仅 Godot 3**（已证实） | **【不可用】**（Godot 3）→ **仅参考思路** | [GitHub](https://github.com/arnemileswinter/godot-tilemap-flowfields) |

#### 自研流场实现要点（**这部分是我的工程综合，非引文**，但 Manymies 源码可作对照）

1. **三层数据**（复用同一张 W×H 数组）：
   - **Cost Field**：每格通行代价。墙/不可破坏物 = 不可通行；可破坏物/沼泽 = 高代价。
   - **Integration Field**：从目标格做一次 BFS/Dijkstra，得到每格"到目标的累计代价"。8 方向时对角代价用 `sqrt(2)` 或 1.414。
   - **Direction Field**：每格记录"邻居中 integration 值最小的那个方向"，归一化成 `Vector2`。
2. **共享性**：同一目标（同一玩家位置 / 同一撤离点）的所有敌人**共用一份流场**。这是它相对"每个敌人各跑一次 A*"的唯一优势来源。
3. **重算时机（省 CPU 的关键）**：
   - 只有**目标格发生变化**时才重建。Manymies 的做法就是 `previous_player_grid_coords == player_grid_coords` 就 `return` 不重建——**照抄这个思路**。
   - **地图变化**（墙被打掉）时重建。Manymies 的流场直接从 `tile_map.get_cell_source_id(point) == -1` 读墙体，所以"墙被打掉"= 改一个 tile id = O(1)，下一次重建自动生效。
   - 多个目标 → 多份流场（玩家一份、撤离点一份、最近枪声位置一份）。**不要**为每个敌人建一份。
4. **性能修正（Manymies 代码的真实缺陷，别照抄）**：它的 `flowfield.gd` 在 `while not active_points.is_empty()` 里用 `active_points.remove_at(0)`，在 GDScript 里这是 **O(n) 的数组头删除**，整个 BFS 退化为 O(n²)。正确做法是用**下标游标**（`var head := 0` … `active_points[head]` … `head += 1`）模拟队列，或直接用 `PackedInt32Array` + 手工环形队列。Manymies 对 40×25 = 1000 格的测试场跑得动，但你们地图更大时这个点会先炸。
5. **地图尺寸**：流场成本 ≈ W×H 次松弛。40×25 = 1000 格，重建一次完全可接受；即便是 200×200 = 40,000 格，只在目标换格时重建也很便宜。**真正的成本是 direction field 的构建，不是内存。**
6. **与移动结合**：流场只给"方向"，不给路径。需要配合分离（separation）避免单位挤在一起——Manymies 提供了三种现成方案（Area2D 软分离 / 射线转向 / RigidBody2D），见 A.3。
7. **和 headless 单元测试的契合点**：流场三层数据全是纯数组，**不依赖场景树**，非常适合放进你的模拟层做 headless 测试（可断言某个被墙围死的格子的 integration 值不下发方向等）。

---

### A.3 多智能体寻路（Multi-Agent Pathfinding, MAPF）

**结论先行：Godot 4 生态里没有可用的、兼容 Android 的现成 MAPF 解算器。** 你点名的两个仓库实测结果如下：

| 项目 | 类型 | 授权 | 最后更新（代码推送） | Godot 版本兼容 | 是否 Android 可用 | 结论 | 链接 |
|---|---|---|---|---|---|---|---|
| **nathanfranke-archive/gdmapf** | GDExtension，多智能体寻路（modified flow field） | **MIT**（已核验 LICENSE） | **2024-12-12**（已 archive 归档） | GDExtension，**仅 3D** | **否**（`.gdextension` 无 android 条目） | **【不可用】** — 仅 3D、无 Android、已归档、README 自述"不会再更新"且存在**对向智能体卡死**的已知重大 bug | [GitHub](https://github.com/nathanfranke-archive/gdmapf) |
| **Griiimon/Manymies** | 非正式 MAPF 解算器：**局部避让（separation）** + 流场，非全局最优、无协同路径规划 | **MIT**（已核验 LICENSE） | **2025-06-03** | **Godot 4.3**（已核验 `project.godot`） | **是**（纯 GDScript，无原生库） | **【需改造】** — 作为"多智能体不互相卡位"的**局部避让**参考实现很好，但它**不是** MAPF（不做协同成本/优先级规划） | [GitHub](https://github.com/Griiimon/Manymies) |

**诚实结论**：gdmapf 与 Manymies **都不是**你们可以直接拿来做真正 MAPF（如 CBS/ECBS/Prioritized Planning）的方案。真正的 MAPF 在实时安卓游戏里也不实用（NP-hard，重规划成本高）。

**针对"避免单位互相卡位"的可行路线（工程综合，按推荐顺序）**：
1. **流场 + 局部分离**（Manymies 路线）：全局方向由共享流场给，局部用软分离/射线转向推开队友。20–30 单位完全够用，且是**确定性、可 headless 测试**的。
2. **格子占位 + 代价惩罚**：给已被队友占据的格子在流场 cost field 上加惩罚权重（gdmapf 的思路就是"在格子里存智能体密度"，但 README 自述该做法有缺陷，他们的补救思路是改存速度而不是密度）。这是"仅参考思路"级别。
3. **NavigationAgent2D 的 RVO 避让**：可用，但官方明确警告多智能体下开销显著，且要注意 `radius` 不影响寻路（见 A.1 第 5、6 条）。
4. **物理层兜底**：真卡住了用 `RigidBody2D`/`move_and_slide` 的滑移兜底。Manymies 也提供了这条方案。

---

### A.4 随机生成地图上的动态阻挡 / 可破坏墙体

| 方案 | 机制 | 授权 | 维护状态 | 结论 | 链接 |
|---|---|---|---|---|---|
| **AStarGrid2D 翻转 solid 标志** | `set_point_solid(id, true/false)` / `fill_solid_region()`，官方注明**调用后不需要 `update()`**。→ 打掉一面墙 = 翻转几个格子的 solid 标志，**O(格数)**，即时生效 | 引擎自带（MIT） | 引擎核心 | **【可直接使用】——这是你的场景的首选方案** | [AStarGrid2D 类参考](https://docs.godotengine.org/en/stable/classes/class_astargrid2d.html) |
| **流场重建（A.2）** | 流场从 tile id 读墙体 → 改一个 tile id 后下次重建即生效，天然支持可破坏地形 | 见 A.2 | — | **【需改造】**（自研，参考 Manymies） | [Manymies flowfield.gd](https://github.com/Griiimon/Manymies/blob/main/solutions/flowfield.gd) |
| **NavigationLink2D enable/disable** | 门/闸门类阻挡：保留两侧导航网格，用可开关的 link 表示连通性 | 引擎自带（MIT） | 引擎核心 | **【可直接使用】**（最适合"门"而非"墙"） | [2D 导航总览](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_2d.html) |
| **运行时重烘焙 NavigationPolygon** | `NavigationRegion2D.bake_navigation_polygon(on_thread := true)`；有 `is_baking()` 与 `bake_finished` 信号；也可走 `NavigationServer2D.parse_source_geometry_data()` + `NavigationMeshSourceGeometryData2D.add_projected_obstruction()` + `bake_from_source_geometry_data()` 全程脚本化 | 引擎自带（MIT） | 引擎核心 | **【需改造】** — 可行但**贵**：每拆一面墙就重烘焙整块网格，不适合高频破坏 | [NavigationRegion2D](https://docs.godotengine.org/en/stable/classes/class_navigationregion2d.html) · [使用 NavigationObstacles（含 2D 烘焙代码）](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationobstacles.html) |
| **NavigationObstacle2D 做"动态阻挡"** | ❌ **不能用**：官方原文 "This Node does NOT affect the pathfinding of agents. You need to change the navigation meshes for that instead." 它只影响**避让**和**烘焙**，不改变寻路结果 | 引擎自带（MIT） | 引擎核心 | **【不可用】**（用于改变路径时） | [使用 NavigationObstacles](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationobstacles.html) |
| **NavigationRegion2D 启停** | `enabled` 可运行时切换，但官方警告："**Existing paths will not be automatically updated** when a region gets enabled / disabled." | 引擎自带（MIT） | 引擎核心 | **【需改造】**（要自己触发重寻路） | [使用 NavigationRegions](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationregions.html) |
| **动态避让障碍（moving obstacle）** | `NavigationObstacle2D` 若只用 `radius`（>0）则为动态障碍，**可每帧改位置而无额外开销**；若用 `vertices`（静态）则"不能改位置、只能整块重建，每帧改位置性能代价很高"（官方原文） | 引擎自带（MIT） | 引擎核心 | **【可直接使用】**（但要按官方建议在移动时先删 vertices 用 radius，停下后再加回 vertices） | [使用 NavigationObstacles](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationobstacles.html) |

**给你的直接建议**：既然你们是**随机生成 + 可破坏**，就走 **格子系（AStarGrid2D / 流场）**，不要走导航网格系。导航网格在"地形频繁变化"这个维度上是结构性劣势。

---

## B. 游戏 AI 决策

### B.1 行为树插件

| 名称 / 项目 | 解决什么问题 | 授权 | 最后更新 | Godot 版本兼容 | 结论 | 链接 |
|---|---|---|---|---|---|---|
| **LimboAI**（limbonaut/limboai） | 行为树 + 分层状态机（LimboHSM）+ 黑板（Blackboard/BlackboardPlan）+ 可视化编辑器 + 可视化调试器。**C++ 编写但任务/状态用 GDScript 写** | **MIT**（LICENSE.md 已逐字核验；Asset Library 亦标 MIT） | **代码推送 2026-10-04**；最新 release **v1.8.1 = 2026-08-20**；Asset Library 条目 2026-03-02 | **版本强绑定**：v1.8.1 针对 **Godot 4.7.2**；v1.7.1 针对 4.6.3；v1.7.0 明确声明 **"It's not compatible with previous Godot versions"**；Asset Library 上架版本 1.6.0 针对 4.4–4.5。**必须选与你的 Godot 版本匹配的发行包** | **【可直接使用】——但注意版本必须严格对齐** | [GitHub](https://github.com/limbonaut/limboai) · [Releases](https://github.com/limbonaut/limboai/releases) · [Asset Library 3787](https://godotengine.org/asset-library/asset/3787) · [文档](https://limboai.readthedocs.io/) |
| **Beehave**（bitbrain/beehave） | 行为树插件（GDScript，纯 addon，可拖入 `addons/` 即用），含编辑器与调试视图 | **MIT**（LICENSE 已逐字核验，Copyright (c) 2023 bitbrain） | **代码推送 2026-09-20**；Asset Library 版本 **2.9.2** 更新于 **2026-02-09** | Asset Library 标注支持 **Godot 4.5**；默认分支为 **`godot-4.x`** | **【可直接使用】**（纯 GDScript，无原生库 → Android 无障碍） | [GitHub](https://github.com/bitbrain/beehave) · [Asset Library 1349](https://godotengine.org/asset-library/asset/1349) |
| **GodotBT**（kagenash1/godot-behavior-tree） | Godot 4.x 行为树框架：复合节点、装饰器、条件、**服务（Service）**、**黑板（含类型化访问与变更检测）**、反应式条件（带 abort scope）、每 agent 独立 context 共享同一棵树 | ⚠️ **待确认 / 有风险**：README 写明 "This project is available under the MIT License."，但**仓库根目录未找到 `LICENSE` 或 `LICENSE.md`（均 404）** → 授权声明方式不规范，建议直接向作者确认后再用 | **代码推送 2025-05-02**（218 stars） | README 自述 **Godot 4.x** | **【需改造】+ 授权需先确认** | [GitHub](https://github.com/kagenash1/godot-behavior-tree) |
| **Behavior Tree for Groups**（pascal-ballet） | 把行为树挂到**节点分组**上，做 swarm / flock / 多智能体集体行为（无代码配置 collective behavior），含 2D/3D 示例 | **MIT**（Asset Library 标注；仓库 `LICENSE` 未逐字核验 → 建议确认） | **代码推送 2024-11-25**；Asset Library 版本 1.1.3 更新于 2024-01-17（22 stars） | Asset Library 标注 "Tools **4.2**" | **【需改造】/【仅参考思路】** — 偏 flocking/群体运动，**不是**战斗小队战术 | [GitHub](https://github.com/pascal-ballet/BehaviorTreeForGroups) · [Asset Library 2355](https://godotengine.org/asset-library/asset/2355) |

> **【不可用 / 找不到】说明**：我**没有**找到其他值得推荐的、活跃维护的 Godot 4 行为树插件。Asset Library 上按 "Behavior tree" 检索的完整清单本次未逐条穷举（→ 待确认是否还有低星长尾项目）。

---

### B.2 效用 AI（Utility AI）与 GOAP

| 名称 / 项目 | 解决什么问题 | 授权 | 最后更新 | Godot 版本兼容 | 结论 | 链接 |
|---|---|---|---|---|---|---|
| **GOAP**（pixelrogueart/goap-godot-4） | 目标导向行动规划：A* **反向链式**规划器、基于优先级的**目标选择**、**运行时重规划**、内置编辑器调试器（实时世界状态检视、规划图可视化、多智能体支持）。Asset Library 描述明确写 **"Pure GDScript, zero dependencies"**，附生存示例 | **MIT**（Asset Library 标注；仓库 LICENSE 未逐字核验 → 建议确认） | **代码推送 2026-08-06**；Asset Library 版本 **1.1.4** 更新于 **2026-08-07**（43 stars） | Asset Library 标注 "Tools **4.6**" | **【可直接使用】/【需改造】** — 纯 GDScript、零依赖 → Android 无障碍；但生态小（43 stars），需自己评估代码质量 | [GitHub](https://github.com/pixelrogueart/goap-godot-4) · [Asset Library 4888](https://godotengine.org/asset-library/asset/4888) |
| **Utility AI**（Pennycook/godot-utility-ai） | 效用 AI 脚本/资源集合：可在 Inspector 里编辑 agent 行为、考量项（considerations）与响应曲线（response curves） | **MIT**（LICENSE 已逐字核验，Copyright (c) 2023 John Pennycook） | **代码推送 2024-04-21**；Asset Library 版本 **0.2.0** 更新于 **2024-01-03**（86 stars） | Asset Library 标注 "Tools **4.2**" | **【需改造】** — 已约 2.5 年未更新，但纯 GDScript、MIT、体量小，作为自研效用 AI 的骨架很合适 | [GitHub](https://github.com/Pennycook/godot-utility-ai) · [Asset Library 1937](https://godotengine.org/asset-library/asset/1937) |
| **Utility_AI**（JarkkoPar/Utility_AI） | 用 **GDExtension**（C++）实现的效用 AI | **MIT**（LICENSE 已逐字核验，Copyright (c) 2023 JarkkoPar） | **代码推送 2025-02-25**（24 stars） | GDExtension；**具体支持的 Godot 版本我未核对 → 待确认**；Android 二进制是否存在**未核对 → 待确认** | **【需改造】/【待确认】** — 只有 24 stars，且原生库会带来 Android 交叉编译负担，与你们"GDScript + headless 模拟层"的偏好不符 | [GitHub](https://github.com/JarkkoPar/Utility_AI) |

> **诚实说明**：Godot 4 生态里**没有**一个"活跃维护 + 纯 GDScript + 高采用度"的 Utility AI 插件。上面两个 Utility AI 项目一个 2024 年停更、一个只有 24 stars 且是原生扩展。**若要 Utility AI，建议自己写**——效用 AI 本质就是"给每个行为打分取最大"，几十行 GDScript 就能落地，且天然适合放在你们的 headless 模拟层里做单元测试。反过来，**GOAP** 因为规划器有真实复杂度，用现成库更划算。

---

### B.3 有限状态机（FSM）插件

| 名称 / 项目 | 解决什么问题 | 授权 | 最后更新 | Godot 版本兼容 | 结论 | 链接 |
|---|---|---|---|---|---|---|
| **Godot State Charts**（derkork/godot-statecharts） | **状态图（State Charts）**，比 FSM 更强：支持层级/复合状态、并行状态、历史状态，**避免传统 FSM 的状态爆炸**；含编辑器与实时调试器 | **MIT**（Asset Library 标注；仓库 LICENSE 未逐字核验） | **代码推送 2026-06-26**；Asset Library 版本 **0.22.5** 更新于 **2026-06-27**（1619 stars） | Asset Library 标注 "Tools **4.0**"，描述为 "an extension for Godot Engine **4 or later**" | **【可直接使用】——FSM 类需求的首选**（活跃、星数高、纯 GDScript 系） | [GitHub](https://github.com/derkork/godot-statecharts) · [Asset Library 1778](https://godotengine.org/asset-library/asset/1778) · [手册](https://github.com/derkork/godot-statecharts/blob/main/manual/manual.md) |
| **fsm**（nofacer/godot-fsm） | 极简 FSM 插件 | **MIT**（Asset Library 标注） | **代码推送 2025-12-29**；Asset Library 版本 **0.0.5** 更新于 **2025-07-21**（**仅 3 stars**） | Asset Library 标注 "Tools **4.4**" | **【可直接使用】**（依赖风险低 —— 代码量小、MIT，即使弃坑也能自己维护）；**但采用度极低**，建议先读源码 | [GitHub](https://github.com/nofacer/godot-fsm) · [Asset Library 1665](https://godotengine.org/asset-library/asset/1665) |
| **LimboAI 的 LimboHSM** | 层级状态机，与行为树同项目、可与 BT 互相嵌入；支持 per-transition guard function | **MIT**（已核验 LICENSE.md） | 见 B.1 | 见 B.1（版本严格绑定） | **【可直接使用】** — 如果你们已经选了 LimboAI，**不需要再引入独立 FSM 插件** | [GitHub](https://github.com/limbonaut/limboai) |
| **Beehave 是否内置 FSM** | — | — | — | — | **待确认**（Beehave 以行为树为核心，我本次**未核实**它是否附带 FSM 组件） | [GitHub](https://github.com/bitbrain/beehave) |

> **【找不到】说明**：`NathanHoad/godot-state-machine` 这个常被提及的 FSM 仓库，本次通过 GitHub API 镜像查询返回 **404（仓库不存在或已改名）** → 我**不**把它列为候选。如果你在其他资料里看到它，请注意先自行确认链接是否有效。

---

### B.4 群体 / 小队协同 AI（squad、黑板、包夹 flanking、警戒等级扩散）

**结论先行（诚实）**：**Godot 生态里没有成熟的、开源的"战斗小队协同 AI 库"**（即开箱提供包夹、警戒等级扩散、火力分配）。这类逻辑在 Godot 社区普遍是**自研**的。行为树/黑板提供的是**承载结构**，不是**战术本身**。以下是能真正帮到你的东西：

| 名称 / 项目 | 提供什么 | 有没有包夹/警戒扩散 | 授权 | 最后更新 | Godot 版本 | 结论 | 链接 |
|---|---|---|---|---|---|---|---|
| **LimboAI 的 Blackboard / BlackboardPlan** | ①**黑板**：节点间共享数据（类型化变量、可与节点属性绑定）②**BlackboardPlan**：可复用、可在 Inspector 编辑 ③**多智能体共享同一棵行为树** ④v1.7.0 起支持**运行时黑板检视**（调试器里直接看值） | ❌ 不含战术（需你在 BT/黑板之上自研） | **MIT** | 2026-10-04（代码） | 见 B.1 | **【可直接使用】** — 作为小队黑板的现成基础设施 | [Releases（v1.7.0 说明含 "Debugger: Blackboard runtime inspection"）](https://github.com/limbonaut/limboai/releases) |
| **GodotBT（kagenash1）** | **黑板 + 每 agent 独立 context 共享同一棵 BT**；README 明确写 "Reusable Behavior Trees: Define a behavior tree once and use it across multiple agents with their own contexts"；示例含 `BTPlayerDetector` 服务 | ❌ 不含战术 | ⚠️ **待确认**（README 称 MIT，但仓库无 LICENSE 文件） | 2025-05-02（代码） | Godot 4.x | **【需改造】+ 授权需确认** | [GitHub](https://github.com/kagenash1/godot-behavior-tree) |
| **Behavior Tree for Groups（pascal-ballet）** | 把行为树施加到**节点分组**，做 swarm/flock/多智能体集体行为 | ❌ 不含战术（是 flocking 不是包夹） | Asset Library 标 **MIT**（仓库 LICENSE 未逐字核验） | 2024-11-25（代码） | Tools 4.2 | **【仅参考思路】** — "用分组表达集体行为"这个建模思路值得借鉴 | [Asset Library 2355](https://godotengine.org/asset-library/asset/2355) |
| **Jhon-Crow/godot-topdown-MVP** | 一个**俯视射击**模板（**Godot 4.3+**，与你们品类高度接近），包含：`VisionComponent`（视线检测）、`CoverComponent`（掩体评估）、`GOAP planner`、敌人状态机、**敌人听觉**（PR 记录"enemies now hear breaching charge explosions"）、FOV 改进；组件化架构 + 信号解耦 | ⚠️ 部分（有听觉/警戒相关行为，但**未见**明确的包夹/警戒等级扩散系统 → 待确认） | ❌ **未声明授权**：**仓库根目录 `LICENSE` 返回 404，我没有找到任何 LICENSE 文件** → 按"保留所有权利"处理 | 2026-05-06（代码推送）；仓库 2026-01 创建（仅 3 stars） | **Godot 4.3+**（README 明确要求） | **【仅参考思路，自己重写】** — **绝对不能复制它的代码**（未声明授权 = 不授予任何权利）；但作为"同品类工程结构长什么样"的参考很有价值 | [GitHub](https://github.com/Jhon-Crow/godot-topdown-MVP) |

**自研 squad AI 的推荐结构（工程综合，非引文）**：
1. **Squad 层**：一个 Squad 节点持有共享 **Blackboard**（目标、警戒等级 `alert_level: float`、已知玩家位置与最后可见时间、已分配包夹位、阵亡成员）。
2. **警戒等级扩散**：单个敌人发现玩家 → 写黑板 `alert_level = 1.0` + 广播位置 → 每帧按距离/时间衰减并向下取整扩散到相邻 squad（classic "sound/alert propagation"）。**关键：扩散走格子 BFS 而不是直线**，可以直接重用 A.2 的 cost field 做"通过墙的衰减"。
3. **包夹（flanking）**：不是路径规划问题，是**位置分配问题**——在玩家周围取若干个角度槽位（如 ±45°、±90°），用简单代价（距离 + 是否被玩家视线覆盖 + 是否被队友占用）做贪心/匈牙利匹配，然后用流场或 A* 各自走到槽位。Manymies 的 `directional_flowfield` 正好给"朝某方向绕行"提供方向场。
4. **不要**上真正的多智能体协同规划（MAPF），实时性和复杂度都划不来。

---

## C. 感知

### C.1 视野锥 + 射线遮挡

**先纠正一个常见误解（已核验）**：**`LightOccluder2D` / `OccluderPolygon2D` 不能用于 AI 视线查询。**
`OccluderPolygon2D` 的类文档只有三个成员：`polygon`、`closed`、`cull_mode`，描述是 "Defines a 2D polygon for LightOccluder2D … Editor facility that helps you draw a 2D polygon used as resource for LightOccluder2D." → 它纯粹属于 **2D 光照/阴影渲染系统**，**没有任何查询 API**。用它做视线判断是错的。

| 技术 | 解决什么问题 | 关键事实（已核验） | 授权 | 结论 | 链接 |
|---|---|---|---|---|---|
| **`PhysicsDirectSpaceState2D.intersect_ray()` + `PhysicsRayQueryParameters2D.create(from, to, mask, exclude)`** | 视线遮挡判定（墙后看不见） | **必须在 `_physics_process()` 内调用**：官方原文 "the only time accessing space is safe is during the `Node._physics_process()` callback. Accessing it from outside this function may result in an error due to space being *locked*."；`query.exclude = [self]` 防自撞；用 `collision_mask` 比用 exceptions 数组高效（官方明说） | 引擎自带（MIT） | **【可直接使用】——视线遮挡的首选** | [Ray-casting 教程](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html) |
| **`RayCast2D` 节点** | 每物理帧自动返回射线结果，适合"每帧都要知道"的少数角色（玩家、精英怪） | 节点封装，无需手写查询；但对 20–30 个敌人逐个挂节点+每帧更新，属于节点开销路线 | 引擎自带（MIT） | **【可直接使用】**（少量角色）；大量敌人建议改用直接物理查询 | [RayCast2D](https://docs.godotengine.org/en/stable/classes/class_raycast2d.html) |
| **`ShapeCast2D`（4.x 有）** | 扫掠一个**形状**而非一条线 → 可以一次查询近似"视野锥"区域；可返回多个碰撞对象 | 已核验 API：`shape`、`target_position`（默认 `Vector2(0,50)`）、`max_results`（默认 32）、`collision_result`、`collide_with_bodies`/`collide_with_areas`、`exclude_parent`、`margin`、`enabled`，方法 `force_shapecast_update()`、`is_colliding()`、`get_collision_count()`、`get_collider(i)`、`get_collision_point(i)`。**官方警告："Shape casting is more computationally expensive than ray casting."** 可用 `max_results` 限制开销 | 引擎自带（MIT） | **【可直接使用】**（但注意开销 > 射线） | [ShapeCast2D](https://docs.godotengine.org/en/stable/classes/class_shapecast2d.html) |
| **`Area2D`** | 用信号（`body_entered` / `area_entered`）做进入/离开检测，或 `get_overlapping_bodies()` 批量取 | **官方明说它的短板**（来自 ShapeCast2D 文档）："This helps to overcome some limitations of `Area2D` when used as an instantaneous detection area, as **collision information isn't immediately available to it**." → Area2D 的碰撞信息要等物理帧结束才可用，**不适合做"这一帧立刻要答案"的瞬时检测** | 引擎自带（MIT） | **【需改造】** — 适合做"粗筛"（谁进了大圈），不适合做瞬时精确判定 | [Area2D](https://docs.godotengine.org/en/stable/classes/class_area2d.html) · [ShapeCast2D（引用该说明）](https://docs.godotengine.org/en/stable/classes/class_shapecast2d.html) |
| **Vision Cone 2D**（d-bucur/godot-vision-cone，作者 sirdorius） | 现成插件：给 2D 实体加可配置视野锥，描述明确用于"simulate the vision of enemies in a stealth game" | **MIT**（Asset Library 标注）；Asset Library 版本 0.2，更新 2025-07-13；代码推送 2025-08-06（94 stars） | **MIT** | **【可直接使用】/【需改造】** — 但它**是否用射线做遮挡检测我未核实 → 待确认**；若它只做角度+距离锥而不做遮挡，你仍需自己接 `intersect_ray` | [GitHub](https://github.com/d-bucur/godot-vision-cone) · [Asset Library 1568](https://godotengine.org/asset-library/asset/1568) · [Store 页](https://store.godotengine.org/asset/sirdorius/vision-cone/) |

**推荐的视野实现组合（工程综合）**：
1. **两级过滤**：先做 `distance² < range²` 与 `dot(facing, to_target) > cos(half_angle)` 的**纯数学**判定（零物理开销），只有通过的才发物理查询。
2. **一次查询代替多次**：用**一个 `ShapeCast2D` / `intersect_shape` + 一个近似视野锥的 `ConvexPolygonShape2D`**，一次拿到锥内所有目标，而不是"每个敌人向每个候选目标打一条射线"。
3. **精确遮挡**：对通过粗筛的候选，再用 `intersect_ray` 确认中间没有墙。
4. **分帧错峰**（见 C.3）。

---

### C.2 听觉 / 声音传播（枪声吸引敌人）

**引擎能力核实结论：Godot 4 没有游戏逻辑层面的"听觉/声音传播"API。**

已核验 `AudioListener2D` 类文档：它的唯一职责是 "**Overrides the location sounds are heard from**"（覆盖声音被听到的位置），只有 `make_current()` / `is_current()` / `clear_current()` 三个方法——这是**给音频混音/声像用的听者位置**，**不是**"哪里有声音、敌人能不能听见"的游戏查询。AudioServer 的区域效果同样是音频处理，不产生游戏逻辑事件。

| 方案 | 说明 | 授权 | 结论 | 链接 |
|---|---|---|---|---|
| **自研事件总线 + 半径广播** | 全局信号 `noise_emitted(position, loudness, source_team)`；开火/换弹/跑动/爆炸发布事件；敌人只订阅、先用半径与距离做粗筛，再决定警戒升级 | — | **【仅参考思路，自己重写】**（这是通用做法，非某项目） | [AudioListener2D 文档（证明引擎无此能力）](https://docs.godotengine.org/en/stable/classes/class_audiolistener2d.html) |
| **基于格子的声音传播（推荐）** | 复用 A.2 的 cost field 做一次**从声源出发的 BFS/Dijkstra**，得到"声音强度场"，再对敌人采样。好处：**穿墙衰减天然正确**（墙给高代价），且能直接与流场共用数据结构 → 可 headless 单测 | — | **【仅参考思路，自己重写】** | [Manymies flowfield.gd（可复用其 BFS 结构）](https://github.com/Griiimon/Manymies/blob/main/solutions/flowfield.gd) |
| **Jhon-Crow/godot-topdown-MVP** | 同品类的参考实现：仓库 PR 记录里明确有"enemies now hear breaching charge explosions"与"reload completion sound triggers enemy cautious mode"这类听觉联动；含 `VisionComponent`、`CoverComponent`、GOAP | ❌ **未声明授权**（无 LICENSE 文件） | **【仅参考思路，自己重写】——禁止复制代码** | [GitHub](https://github.com/Jhon-Crow/godot-topdown-MVP) |

> **【找不到】说明**：我**没有**找到任何成熟、有授权、值得推荐的 Godot 4"声音传播/听觉系统"插件或库。搜索中出现的若干命中（例如 `thedivergentai/GD-Agentic-Skills` 下的 `sound_propagation_system.md`、`sound_occlusion_manager.gd`）经查是**给 AI 编码助手用的"技能/提示词文档仓库"**，**不是可用的游戏库**，我不把它当作候选项凑数。

---

### C.3 性能：同屏 20–30 个敌人各带视野检测

#### 已核验的引擎事实（有出处）

| 事实 | 原文要点 | 出处 |
|---|---|---|
| **不要每帧向物理/渲染服务器取值** | "Try to **never** request any information from `RenderingServer`, `PhysicsServer2D`, or `PhysicsServer3D` by calling functions unless you know what you are doing. These servers will often run **asynchronously** for performance and calling any function that returns a value will **stall them** and force them to process anything pending until the function is actually called. This will **severely decrease performance** if you call them every frame (and it won't be obvious why)." → 直接对应"30 个敌人每帧都查物理空间"的反模式 | [Optimization using Servers](https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html) |
| **物理空间只能在 `_physics_process()` 访问** | 空间在其他回调里是 *locked* 的，访问会报错。注意你们若开 `2d/run_on_separate_thread`（Manymies 就开了），这个约束更要小心 | [Ray-casting](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html) |
| **ShapeCast 比 RayCast 贵** | "Shape casting is more computationally expensive than ray casting."（可用 `max_results` 限流） | [ShapeCast2D](https://docs.godotengine.org/en/stable/classes/class_shapecast2d.html) |
| **导航避让在多智能体下开销显著** | NavigationAgent2D 的 `avoidance_enabled`："Avoidance processing with many registered agents has a **significant performance cost** and should only be enabled on agents that currently require it." | [NavigationAgent2D](https://docs.godotengine.org/en/stable/classes/class_navigationagent2d.html) |
| **AStarGrid2D 查询不能放线程** | `get_point_path()` / `get_id_path()`："This method is **not thread-safe**. If called from a `Thread`, it will return an empty array and will print an error message." → **不能靠多线程绕过每帧寻路成本** | [AStarGrid2D](https://docs.godotengine.org/en/stable/classes/class_astargrid2d.html) |
| **低层 PhysicsServer2D 可绕过场景树** | 服务器 API 是场景系统的底层，用于"tens of thousands of instances … processed every frame"这类瓶颈场合，但代价是复杂度、线程受限、内存更多 | [Optimization using Servers](https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html) |

> ⚠️ **我没有找到 Godot 官方给出的"每帧安全射线数"这类具体数字。不敢编。** 官方文档不发布这种预算数字（它完全取决于目标设备、物理引擎、形状复杂度）。所以下面的数字是我的**工程建议**，不是文档结论。

#### 工程建议（**属"社区/工程实践"，非官方文档**；20–30 敌人 / 安卓 / 2D 像素俯视）

1. **分帧错峰（最有效的一条）**：把 30 个敌人按 `index % 3` 分成 3 组，每物理帧只让 1 组做完整视野检测 → 每帧 10 次检测，每个敌人每 3 帧（50ms）得到一次视野更新。对枪战手感而言 50ms 的感知延迟**不可感知**。这是把 CPU 峰值削掉 2/3。
2. **粗筛先行**：距离平方比较 + 点积夹角比较，全是纯数学，**零物理开销**。真正需要射线遮挡的往往只剩 3–8 个候选。
3. **用一次形状查询代替 N 条射线**：`intersect_shape` + 近似视野锥的 `ConvexPolygonShape2D`，一次拿到锥内全部目标（注意 ShapeCast 更贵，所以要配合 `max_results` 与粗筛）。
4. **遮挡检测只在必要时做**：如果敌人与玩家之间没有墙（可用关卡生成时预计算的格子可见性矩阵，或 A.2 的 cost field 判断"直线格子是否全通行"），**根本不需要射线**——直接查格子表，零物理调用。这是你们"数据驱动 + 网格地图"架构的最大红利。
5. **听觉也走格子而非物理**：见 C.2，用一次 BFS 声音场代替"每个敌人对每次枪声做检测"。
6. **寻路用流场而不是每敌人 A***：30 个敌人共享一份流场 = 每帧最多 1 次重算，且只在玩家换格时。
7. **不要开 `run_on_separate_thread` 后又在非物理帧查空间**：线程化物理会放大"空间锁定"类错误。
8. **给敌人做可见性/距离 LOD**：屏幕外或远处的敌人降频到每 6–10 帧一次感知，甚至只做纯数学判定。

---

## 结论与推荐

### 针对你们场景（Godot 4.x / Android / 2D 像素俯视 / 搜打撤 / 随机生成 + 可破坏 / GPL-3.0 / 数据驱动 + 模拟层 headless 可测）的选型

#### 1. 寻路：**以格子系为骨干，自研「流场 + 局部分离」；AStarGrid2D 作为单点寻路补充；不用导航网格**

- **主方案**：**自研 Flow Field**，以 [Griiimon/Manymies](https://github.com/Griiimon/Manymies)（**MIT**、Godot 4.3、纯 GDScript）为起点**改造**。理由：
  - 生态实测**没有任何 Godot 4 流场插件**（官方 Asset Library 检索 "flow field" = **0 条结果**），所以只有自研一条路；而 Manymies 已经把三层数据结构和"只在目标换格时重建"的优化都写好了。
  - 流场天生适配**可破坏墙体**（从 tile id 读墙，改一格即生效）与**随机生成地图**（网格天然对齐）。
  - 流场数据是**纯数组**，可以完整放进你们的**模拟层**做 headless 单测——这与你们"模拟层与表现层分离"的架构决策完全契合。
  - **必须改造的两点**：① 修掉它 BFS 队列的 `remove_at(0)`（O(n²)）改下标游标；② 它依赖自己的 `Global` 单例与 `TileMapLayer`，要解耦成纯数据。
  - 它的三种分离方案（Area2D 软分离 / 射线转向 / RigidBody2D）可直接借鉴，用来解决"20–30 个单位互相卡位"。
- **补充**：单目标精确寻路（例如某个敌人被指派去一个具体掩体点）用 **AStarGrid2D**。记住三个坑：`update()` 会清空 solid/weight、路径查询**不能丢线程**、要开 `DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES` 防止贴角穿墙。
- **不使用 `NavigationRegion2D` + 重烘焙**做大范围方案：你们的"可破坏墙体"这个需求会把它拖垮。导航网格只在**静态、大面积的关卡外壳**上考虑。
- **MAPF 明确不建议**：你点名的两个仓库里，[gdmapf](https://github.com/nathanfranke-archive/gdmapf) 是 **3D only + 无 Android 二进制 + 已归档 + 作者自述存在对撞卡死 bug**（【不可用】），[Manymies](https://github.com/Griiimon/Manymies) 不是真正的 MAPF 解算器（是流场 + 局部避让）。真正的 MAPF 在实时安卓游戏里性价比极低。**用"流场 + 分离 + 格子占位惩罚"就够了。**

#### 2. AI 决策：**行为树为主，FSM 为辅；Utility AI 自己写；GOAP 可以用现成的**

- **行为树**：**推荐 [Beehave](https://github.com/bitbrain/beehave)（MIT、纯 GDScript、Godot 4.5、活跃）**。
  - 关键理由：**纯 GDScript** → 对 Android 导出零负担，也能在 PC headless 下跑。
  - **[LimboAI](https://github.com/limbonaut/limboai)（MIT）是功能上更强的选项**——它自带黑板、HSM、可视化调试器，而且 **release 里确实提供了预编译的 `android-lib` 包**（已核实 v1.8.1 的 android-lib asset 存在），所以 Android 不是问题。**但它的代价是版本强绑定**：v1.8.1 → Godot 4.7.2，v1.7.x → 4.6.x，v1.7.0 明确声明与更早版本不兼容。**你们必须先冻结 Godot 版本，再选对应的 LimboAI 发行包**；如果你们希望跟引擎升级有更大的自由度，选 Beehave。
  - 因此：**想省事且要黑板/HSM/调试器 → LimboAI；想要长期升级自由度且坚持纯 GDScript → Beehave。**
- **FSM**：若不用 LimboAI 的 HSM，用 **[Godot State Charts](https://github.com/derkork/godot-statecharts)（MIT，1619 stars，2026-06 仍在更新）**。它支持层级/并行状态，能避免状态爆炸。简单场景也可以用 [nofacer/godot-fsm](https://godotengine.org/asset-library/asset/1665)（MIT，极简，但只有 3 stars → 要读源码）。
- **Utility AI**：**自己写**。生态里唯一的两个都偏弱（[Pennycook/godot-utility-ai](https://github.com/Pennycook/godot-utility-ai) MIT 但 2024-04 后停更；[JarkkoPar/Utility_AI](https://github.com/JarkkoPar/Utility_AI) 是原生扩展且只有 24 stars）。效用 AI 的逻辑本质是"打分取最大"，几十行 GDScript、完全可 headless 单测——**自己写比引依赖更划算，也更符合你们"数据驱动"的架构**（行为/考量项/响应曲线全放 JSON）。
- **GOAP**：**可以用 [pixelrogueart/goap-godot-4](https://github.com/pixelrogueart/goap-godot-4)（MIT，Asset Library 标注 Pure GDScript / zero dependencies，2026-08 更新）**。规划器本身有真实复杂度，自己写不划算。但要注意它生态还小（43 stars），需要先做代码评审。
- **Squad / 黑板 / 包夹 / 警戒扩散**：**没有现成库，必须自研**（这部分我很确定，且已明确说明找不到）。能复用的基础设施是：**LimboAI 的 Blackboard/BlackboardPlan** 或 **GodotBT 的黑板**（后者授权待确认）。战术本身（包夹槽位分配、警戒等级沿格子扩散）要自己写——建议把警戒扩散直接建在 A.2 的 cost field 上，这样"隔墙传声衰减"天然正确，并且可在 headless 下单测。

#### 3. 感知：**两级过滤 + 分帧错峰 + 格子可见性表优先于射线**

- **视线遮挡**：用 `PhysicsDirectSpaceState2D.intersect_ray()` + `PhysicsRayQueryParameters2D`（**必须在 `_physics_process` 内**，`exclude = [self]`，用 `collision_mask` 而非 exceptions 数组）。
- **明确不要用 `LightOccluder2D`/`OccluderPolygon2D` 做视线**——它们只有 `polygon`/`closed`/`cull_mode`，属于 2D 光照渲染，**没有查询 API**。
- 视野锥可以先用现成的 [Vision Cone 2D](https://godotengine.org/asset-library/asset/1568)（**MIT**，94 stars，Godot 4）省事，但**它是否自带射线遮挡我未核实，需先看源码**。
- **性能方案（我最有信心的一条）**：既然你们是**网格地图**，就在关卡生成时（或地图变化后）预计算**格子级可见性/视线表**——判断"两格之间直线上的格子是否全通行"是**纯数据操作，零物理调用**。这样 30 个敌人的视野检测大多不需要碰物理引擎，只在边界情况才退回射线。这条比任何射线调优都更省，而且**完全可 headless 单测**。
- 再加**分帧错峰**（30 人分 3 组，每帧 10 人）与**距离 LOD**，安卓上的预算就非常宽裕。
- **听觉没有引擎支持**（已核验 `AudioListener2D` 只是音频听者位置）。用事件总线 + **基于格子的声音强度场**（复用 A.2 的 BFS）实现，穿墙衰减天然正确。

#### 4. 一张总表：最终推荐

| 需求 | 选什么 | 授权 | 动作 |
|---|---|---|---|
| 群体寻路（20–30 单位追玩家/撤离点） | **自研 Flow Field**（参考 Manymies） | MIT（参考物） | **需改造** |
| 单体精确寻路 | **AStarGrid2D**（引擎内置） | MIT | **可直接使用** |
| 动态/可破坏阻挡 | `set_point_solid` + 流场重建 | MIT | **可直接使用** |
| 行为树 | **Beehave**（纯 GDScript）或 **LimboAI**（功能强、Android 有预编译包、版本强绑定） | MIT | **可直接使用** |
| FSM / 状态图 | **Godot State Charts**（或 LimboAI 的 HSM） | MIT | **可直接使用** |
| 效用 AI | **自己写**（放 JSON 数据） | — | **仅参考思路，自己重写** |
| GOAP | **pixelrogueart/goap-godot-4** | MIT（建议再核 LICENSE 文件） | **可直接使用 / 需改造** |
| 黑板 / squad | 用 LimboAI 或 GodotBT 的黑板作底座，战术自研 | MIT / 待确认 | **需改造** |
| 视野锥遮挡 | `intersect_ray` + **格子可见性表** | MIT | **可直接使用 / 自己重写** |
| 视野锥插件（省事） | **Vision Cone 2D** | MIT | **可直接使用**（先确认是否带遮挡） |
| 听觉 | 事件总线 + 格子声音场 | — | **仅参考思路，自己重写** |

### 需要你们注意的授权红线（本次调研中发现的具体风险）

1. **[Jhon-Crow/godot-topdown-MVP](https://github.com/Jhon-Crow/godot-topdown-MVP)**（同品类、含视野/掩体/GOAP/听觉参考）——**仓库内找不到任何 LICENSE 文件（`LICENSE` 返回 404）**。按著作权默认规则 = **保留所有权利**。**只能读思路，绝对不能复制代码进你的 GPL-3.0 项目。**
2. **[kagenash1/godot-behavior-tree](https://github.com/kagenash1/godot-behavior-tree)**（GodotBT）——README 声称 MIT，但**仓库根目录没有 LICENSE / LICENSE.md**。声明与文件不一致，**建议先向作者确认再使用**。
3. **Godot 3 的坑（本次实测命中两个，正好印证你的担心）**：
   - [kvbc/godot-FlowFieldPathfinding](https://github.com/kvbc/godot-FlowFieldPathfinding)（MIT）——源码 `#include "core/reference.h"` / `public Reference` 证实是 **Godot 3**，且是**引擎模块**（要重编译 Godot）。
   - [arnemileswinter/godot-tilemap-flowfields](https://github.com/arnemileswinter/godot-tilemap-flowfields)（MIT）——`project.godot` 为 `config_version=4` + **GDNative**（`.gdns`/`.gdnlib`）证实是 **Godot 3**，且只有 Linux/Windows 原生库、**无 Android**。
   两个都**不能**用在 Godot 4 上。
4. **[LimboAI](https://github.com/limbonaut/limboai)** 本身是 MIT（含 Android 预编译包），但**版本与 Godot 强绑定**——这不是授权风险，是**工程风险**：升级 Godot 时必须同步更换 LimboAI 包。

### 本次未能核实 / 找不到的事项（**明确列出，不猜**）

| 事项 | 状态 |
|---|---|
| `NavigationRegion2D` / `NavigationAgent2D` / `NavigationObstacle2D` 在 Godot 4.5/4.6/4.7 中是否仍带 `experimental` 标记 | **待确认**（4.4 类文档中确实带；未逐版核对后续版本） |
| [JarkkoPar/Utility_AI](https://github.com/JarkkoPar/Utility_AI) 具体支持的 Godot 版本、是否有 Android 二进制 | **待确认** |
| [d-bucur/godot-vision-cone](https://github.com/d-bucur/godot-vision-cone)（Vision Cone 2D）是否内置射线遮挡检测 | **待确认**（我未读其实现源码） |
| Beehave 是否内置 FSM 组件 | **待确认** |
| [pascal-ballet/BehaviorTreeForGroups](https://github.com/pascal-ballet/BehaviorTreeForGroups) 与 [pixelrogueart/goap-godot-4](https://github.com/pixelrogueart/goap-godot-4) 仓库 `LICENSE` 文件逐字内容（仅 Asset Library 标注为 MIT） | **待确认**（Asset Library 元数据可信度较高，但未逐字核验仓库文件） |
| Godot 官方给出的"每帧安全射线数"预算数字 | **找不到**——官方文档不发布此类数字；请以真机 profile 为准 |
| 成熟的 Godot 4 开源"战斗小队协同 AI（包夹/警戒扩散）"库 | **找不到**——此类逻辑在 Godot 生态中普遍自研 |
| 成熟的 Godot 4 开源"声音传播/听觉"库 | **找不到**（搜索命中的若干结果是 AI 编码助手的提示词文档仓库，不是游戏库，未计入） |
| `NathanHoad/godot-state-machine` | **无法验证**（API 查询返回 404，仓库不存在或已改名）→ 未列为候选 |
| Asset Library 上 "Behavior tree" 分类的**完整**清单（是否还有低星长尾项目） | **未穷举** → 待确认 |
| 论文《Analisis Perbandingan Performa Algoritma A* Grid dan NavigationMesh pada Game 2D Top-Down Menggunakan Godot Engine 4》（[Zenodo 记录](https://zenodo.org/records/21227116)）——唯一的"A* Grid vs NavigationMesh 在 Godot 4 2D 中的实测对比" | **未能抓取正文**（本次会话中 zenodo.org 域名解析失败）→ **无法引用其结论，请勿把我的选型建议当作该论文的结论** |
