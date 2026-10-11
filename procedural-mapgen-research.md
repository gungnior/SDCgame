# 2D 俯视随机地图生成 · 技术与 Godot 4 实现调研

> 目标项目：Godot 4.x / GDScript，安卓 2D 像素俯视「搜打撤」，房间-走廊式室内地图，tile 16×16，GPL-3.0。
> 硬约束：全连通 / 撤离点 ≥2 / 出生—撤离图距离 ≥ 阈值 / 最小可行走宽度 ≥3 格 / 房间类型表驱动战利品与敌人预算 / 全随机走 seed。

## 验证状态说明（先行声明，避免误读）

- 本会话运行环境**无法访问 github.com 与 raw.githubusercontent.com**（被解析到非公网 IP 而拦截）。因此所有 GitHub 仓库内容是通过 **jsDelivr CDN 镜像**（`cdn.jsdelivr.net/gh/<user>/<repo>@<branch>/<file>`）读取的，读到的是仓库真实文件内容，但**未能查看提交历史/Star/Issue 列表**。
- Godot 官方文档通过 Sphinx 的 `_sources/*.rst.txt` 纯文本源读取（稳定版）。
- **未能访问**：GitHub Issue `godotengine/godot#119322` 的正文、`Edgar-DotNet` 的 LICENSE 文件（两者均因 GitHub 主机被拦截）。相关结论已标注「待确认」。
- 标注约定：**【可直接使用】** / **【需改造】** / **【仅参考思路，自己重写】**。

---

## A. 算法与理论基础

### A1/A2. 主流算法对比与适配场景

| 算法 | 核心原理 | 最适合的地图 | 优点 | 缺点 | 与本项目约束的契合度 |
|---|---|---|---|---|---|
| **随机房间 + 走廊**（Angband 式，Bob Nystrom 文中所述起源） | 反复随机撒不重叠矩形；再随机游走/L 形走廊两两相连 | 半室内、地牢、废弃城区 | 实现最简单；房间/走廊宽度可直接参数化 | 房间分布不均；走廊会穿房；**不保证连通**，需额外连通性修复 | ★★☆ 需加连通性修复与宽度控制 |
| **BSP 空间分割**（Binary Space Partitioning） | 递归二分整个矩形，叶节点内放房间，兄弟节点相连 | 军事基地、实验室、方正室内城区 | 房间不重叠、无浪费空间、房间尺寸可控、连接天然成树因而**天然全连通**；生成 O(n log n) 极快 | 结构规整/对称、走廊通常是直线、默认无环路；房间尺寸受分割约束 | ★★★★ 最贴合「室内方正 + 全连通」 |
| **Drunkard's Walk / 随机游走** | 从一点开始随机方向挖洞 | 洞穴、废墟、下水道 | 有机、便宜 | 不保证连通、不保证宽度、房间概念弱 | ★ 只在洞穴区段用 |
| **Cellular Automata**（元胞自动机） | 随机噪声 + 多轮邻域平滑 | 洞穴、自然地形 | 视觉自然；实现短 | 会切碎房间、**破坏走廊宽度**、需 flood fill 清理孤岛；房间/走廊语义丢失 | ★ 与本项目硬约束冲突（见 C1 对 ProcGen 的说明） |
| **Voronoi / Poisson-disc 分区** | 撒站点→Voronoi 划分→相邻区域连通 | 开放地形、城区分块、超大室外 | 区域大小可控、分布均匀、天然有邻接图 | 房间形状不规则、最小宽度难保证 | ★★☆ 可作「城区分块」上层，下层仍需走廊化 |
| **Space Partitioning / 网格法** | 把空间切成大小不一的网格单元，部分单元升级为房间 | 通用地牢 | 单元填满空间，走廊可利用非房间单元自然成形（TinyKeep 做法） | 需要「分离转向」等额外步骤才不重叠 | ★★★★ |
| **Graph-based（TinyKeep / Edgar / Gungeon 式）** | **先在抽象图上决定「有哪些房间、谁连谁」，再落位到 tile** | 任何需要「设计控制」的关卡 | 房间类型、连通性、环路数、关键路径长度、预算**全部在图阶段可算可校验**；与手绘房间模板结合最好 | 实现量最大；落位（layout/backtracking）是最难的一步 | ★★★★★ 唯一能同时满足你全部硬约束的范式 |

**结论**：你的 4 条硬约束（全连通、撤离点≥2、图距离阈值、房间类型预算）本质都是**图上的约束**，因此应采用 **Graph-based 图优先**范式：用 BSP 或分离布点产生房间矩形，用图算法保证连通与环路，最后才落位成 tile。

### A3. 约束满足：连通性 / 可达性 / 死路与环路

| 问题 | 成熟做法 | 出处 |
|---|---|---|
| **保证全连通** | ① BSP：兄弟节点互连，天然成树；② 图法：对房间邻接图跑 **Kruskal/Prim 最小生成树（MST）**——MST 存在 ⇒ 全连通；③ 房间+走廊法：找出所有候选「连接格」（一侧是 A 区域、一侧是 B 区域的实心格），在「区域图」上求生成树，只打通生成树上的连接格 | TinyKeep 第 7 步（Delaunay→MST）；Bob Nystrom「Looking for a connection」 |
| **可达性分析** | 生成后必须**独立验证**，不能信任生成器：把可走格建成图跑 BFS/DFS / flood fill 计数（对比可走格总数）；Godot 内置 `AStarGrid2D` / `AStar2D` 可直接算路径与距离 | Godot `AStarGrid2D` 文档 |
| **控制死路比例** | **Uncarve（反雕刻）**：反复找到「三面是墙」的死路格并填回，直到达到目标数量或占比。Bob Nystrom 明确说「跑到底会把迷宫全擦掉」，所以要**只删一部分**（该 demo 暴露 `Dead ends to remove` 滑杆） | Bob Nystrom「A dark and twisty passageway」 |
| **控制环路数量** | ① 生成树建立时，对被丢弃的候选连接格给一个**小概率仍然打通**（该 demo 暴露滑杆，概率越高越密）；② TinyKeep：MST 后**回加约 15% 的 Delaunay 边**；③ Gungeon：手工 flow 图里直接画好回路 | Bob Nystrom 第 3 步；TinyKeep 第 8 步；BorisTheBrave Gungeon 文 |
| **最小宽度 ≥3 格**（你的硬约束） | ⚠️**不要**指望任何插件的默认输出。三种可行手段：(a) **逻辑格 = N×N tile**（推荐 N=3），走廊恒为 1 逻辑格宽 = 3 tile；(b) 走廊雕刻完成后做**膨胀/腐蚀（dilate）**，把 1 格宽通道撑到 3 格，再重新校验连通；(c) 用固定宽度的走廊模板拼接。注意 (b) 可能把两条平行走廊并成一块，需重新标注房间 id | 无单一权威出处；属工程做法。TinyKeep 的「cells 网格」本质上就是 (a) 的变体 |
| **出生点与撤离点图距离 ≥ 阈值** | 在**房间邻接图**上跑 BFS 得「跳数」，或在 tile 层用 `AStarGrid2D` 得**实际路径长度**。建议两者都算：跳数保证「要穿过足够多房间」，路径长度保证「不会绕远但实际很近」。图距离应在**加环路之前**和之后各算一次 | 工程做法；Godot `AStarGrid2D` |

### A4. 预算分配：按房间类型分配战利品与敌人

公开的成熟做法（按可信度排序）：

| 做法 | 说明 | 出处 |
|---|---|---|
| **Gungeon：flow 图 + 房间类型元数据 + node injection** | 每个节点带 room type（普通/奖励/hub/boss/connector），房间从「该类型的房间表」里抽（第一关约 300 个房间，且避免重复选同一个）；「注入」节点带**出现概率 + 前置条件**（如已获得某道具、诅咒值高、尚未救出某角色），用于商店、牢房、密室等 | [BorisTheBrave, "Dungeon Generation in Enter The Gungeon"](https://www.boristhebrave.com/2019/07/28/dungeon-generation-in-enter-the-gungeon/)（Dodge Roll 官方在评论区确认该拆解「完全说中了我们的意图」） |
| **Spelunky：房间类型表 + 关键路径（solution path）** | 4×4=16 个房间，4 种基础房间类型（0 侧房 / 1 左右贯通 / 2 左右+下 / 3 左右+上），先只生成**红色关键路径**，敌人/尖刺/箭陷阱/宝藏**全部是后面才放进去的** | [Darius Kazemi, "Spelunky Generator Lessons"](https://tinysubversions.com/spelunkyGen/) |
| **Spelunky 的「预算（budget）」系统** | 社区广泛流传的说法是：按关卡深度给每个房间一个预算，每个敌人/陷阱有 cost，抽到预算耗尽。**但我本次没有找到可引用的公开原始文章 URL**（该内容主要在 Derek Yu 的《Spelunky》书与 GDC 演讲中）。**→ 标注：未能验证权威出处，不建议直接引用** | — |
| **权重抽样（工程实现）** | Godot 内置 `RandomNumberGenerator.rand_weighted(weights)` 直接返回按权重抽样的索引，是「按房间类型抽战利品/敌人」最省事的实现；官方文档也给出「weighted random probability」的 `randf()` 阈值写法 | [Godot 文档：Random number generation](https://docs.godotengine.org/en/stable/tutorials/math/random_number_generation.html) |
| **学术框架** | 《Procedural Content Generation in Games》第 3 章 Constructive generation methods for dungeons and levels；第 12 章 Evaluating content generators（如何量化「好玩度」） | [pcgbook.com](https://www.pcgbook.com/)（Springer 2016，作者版 PDF 免费） |

**给你的具体建议**（把上面的做法落到你的房间类型表）：
1. 每个房间先产出 `RoomType`（普通/高价值/医疗/军械/出生/撤离）。
2. 每个类型给一张「权重表 + 预算区间」：例如 `军械 = {敌人权重: 高, 战利品权重: 高, 预算: 300±60}`，`医疗 = {敌人权重: 低, 医疗品权重: 极高, 预算: 120}`。
3. 每房间用**单一 RNG 顺序消费**：先按权重抽 5±2 个「点数」，再用 `rand_weighted` 反复抽具体敌人/战利品并扣点数，点数不足即停。这样「预算」和「随机」统一在一个可复现流里。
4. 难度系数乘在预算上：`budget *= lerp(0.7, 1.5, depth)`，且**出生点相邻房间强制降预算**（给玩家喘息）。
5. 保证「高价值房」不全部落在出生点跳数 1 的位置——用 A3 的图距离做二次筛选。

---

## B. 权威学习资料

| 名称 | 链接（均已实际访问验证） | 讲什么（已核实的内容概要） | 对我们的价值 | 用法定性 |
|---|---|---|---|---|
| **Rooms and Mazes: A Procedural Dungeon Generator** — Bob Nystrom, 2014-12-21 | https://journal.stuffwithstuff.com/2014/12/21/rooms-and-mazes/ | 完整流程：①撒不重叠房间（固定**尝试次数**而非固定成功数，以控制密度）②在剩余实心区跑迷宫生成器填满③找「连接格」并把**区域**当节点求生成树连通④丢弃多余连接格、但给它们小概率打通以产生**环路**⑤最后 uncarve 死路。作者明确列出 5 条设计目标（高效/连通/非完美/开阔房间/可调）并指出「跑到底会把迷宫擦光」。引用了 [/u/FastAsUcan 的 Karcero](http://www.odedwelgreen.com/karcero/) 与 [Jamis Buck 的迷宫文章](http://weblog.jamisbuck.org/) | **最直接对应你「死路比例 / 环路数量 / 可调参」三项需求**。Karcero / Jamis Buck 是它的前身，值得顺藤摸瓜 | 【仅参考思路，自己重写】（原文是 Dart，代码仓 munificent/hauberk） |
| **Dungeon Generation Demo** — Phigames（TinyKeep 开发者）, IndieDB, 2013-05-09 | https://www.indiedb.com/games/tinykeep/news/dungeon-generation-demo | 9 步原文：①150 个 cell ②每 cell 一个随机矩形（用 **Park-Miller 正态分布**让小房间更多，并限制长宽比）③**分离转向（separation steering）**推开重叠 ④用 1×1 cell 填满缝隙→完美铺满的网格 ⑤宽高过阈值的 cell 升级为房间 ⑥对房间中心做 **Delaunay 三角剖分** ⑦取 **MST** 保证全连通 ⑧**回加约 15%** 剩余边制造环路 ⑨沿图的边画直线/L 形，与 L 形相交的 cell 变成走廊 tile（因此走廊墙是「扭扭曲曲」的） | **图论法的标准模板**，与你的「图论校验」要求一一对应。第 ⑨ 步（用 cell 吸收 L 形线）是很聪明的宽走廊落地手法 | 【仅参考思路，自己重写】 |
| **Dungeon Generation in Enter The Gungeon** — BorisTheBrave, 2019-07-28 | https://www.boristhebrave.com/2019/07/28/dungeon-generation-in-enter-the-gungeon/ | flow（预置房间图，节点带 room type，含 root 树 + 额外边成环）→ flow transformation（替换为随机长度的房间串、二选一支路）→ **node injection**（带概率与前置条件）→ 按 type 从房间表抽具体房间 → 拆成 **composites**（环 or 树）分别落位（树用 DFS + 回溯重选，环用「两端交替生长 + 优先对向出口」，未闭合时用小矩形房或 4–30 单位长的窄走廊补齐）→ 最终拼装（从连接最多的房间开始走） | 给出**「房间类型 + 预算 + 环路 + 节奏」如何同时成立**的一手拆解；`injection` 的概率+前置条件机制正好可以拿来做你的「高价值房 / 密室」 | 【仅参考思路，自己重写】 |
| **Dungeon Generation in Diablo 1** — BorisTheBrave, 2019-07-14 | https://www.boristhebrave.com/2019/07/14/dungeon-generation-in-diablo-1/ | 同一系列，Diablo 1 的房间/走廊 + 主题化做法（引用的原文结论：「先把地牢做成抽象图、之后再落地」非常有效） | 系列阅读，理解「抽象图 → 具体 tile」的普适性 | 【仅参考思路】 |
| **BFS for dungeon generation** — Red Blob Games（Amit Patel）, 2020-10-22 | https://www.redblobgames.com/x/2043-bfs-dungeons/ | 目标：一条主路径 + 多条短支路 + 偶尔环路 + 锁与钥匙。步骤：poisson disc 撒房间种子 → **并行 BFS** 扩张到最小尺寸 → **串行 BFS** 逐个扩张到最大尺寸（房间尺寸递增、顺序随机）→ 门检测（共享墙的房间对生成候选门）→ 图分析选子图 → 放门 → 修剪无用房间/走廊。作者自述「我至今没写出细节版，而且有个偶发死循环没修」 | 「房间会绕着先放的房间生长」——这是**保证连通性**的一种优雅替代方案；锁/钥匙机制可直接用于你的高价值区 | 【仅参考思路】 |
| **Red Blob Games 其他相关页** | https://www.redblobgames.com/x/1939-planetary-dungeon/ | 同一生成器的球形地图版本；文中还链到 brogue room accretion 的剖析 | 参考 | 【仅参考思路】 |
| **Procedural Content Generation in Games**（教材，Shaker/Togelius/Nelson, Springer 2016，**作者版 PDF 免费**） | https://www.pcgbook.com/ | 第 3 章 *Constructive generation methods for dungeons and levels*（Shaker, Liapis, Togelius, Lopes, Bidarra）；第 12 章 *Evaluating content generators*（如何评估生成器质量）；附录 A 含 Andrew Doull / Ed Key / Michael Toy / Richard Evans / **Tarn Adams** 的开发者访谈 | **学术级框架与术语**；第 12 章对「好玩度调参如何量化」很关键。注：我未逐字阅读第 3 章，请下载 PDF 自行核对具体收录的算法清单 | 【参考/引用】 |
| **Spelunky Generator Lessons** — Darius Kazemi | https://tinysubversions.com/spelunkyGen/ （[Part 2](http://tinysubversions.com/spelunkyGen2)） | 4×4=16 房间、4 种房间类型、先只生成关键路径（红），敌人/陷阱/宝藏之后才放；3~4 个连成竖线的 type 0 房间有机会变「蛇坑」 | 「房间类型 + 关键路径」的最小可用范例，非常适合手机小地图 | 【仅参考思路】 |

### B4. 需要明确纠正/找不到的两件事（诚实标注）

1. **Adi Shavit 与 TinyKeep 地牢生成没有找到任何关联。** 搜索到的 Adi Shavit 是 C++ 社群讲者（CppCon 的 *The Salami Method for Cross-Platform Development*、[*The C++ Bestiary*](https://isocpp.org/blog/2017/10/the-cpp-bestiary)，以及 [NXTBLD 讲者页](https://nxtbld.com/speakers/adi-shavit-2026/)），**没有找到他做过 "Procedural Generation in Games" 的地牢生成演讲**。TinyKeep 的生成方法是开发者 Phigames 本人在 IndieDB 上写的，见上表。**请不要把 TinyKeep 方法归因到 Adi Shavit 名下。**
2. **「Spelunky 的房间预算（budget）系统」我没能找到公开可引用的原始文章。** 该内容主要在 Derek Yu 的《Spelunky》（Boss Fight Books）与他的 GDC 演讲中。上表已标注。若你需要可引用形式，建议直接买书或看 GDC Vault。

---

## C. Godot 4 现成实现

### C1. 插件/项目技术表

全部条目来自 Godot 官方 Asset Library 页面或仓库 README（授权与兼容性以 Asset Library 页面标注为准）。

| 名称 | 用途 | 授权 | 维护状态 | Godot 4 兼容 | 结论 | 链接 |
|---|---|---|---|---|---|---|
| **ProcGen**（作者 Epsy / 仓库 alexishachemi/godot-procgen） | 房间制地牢 + 洞穴生成器（BSP 分区 + Kruskal MST + 元胞自动机），带 `ProcGenVisualizer` | **MIT** | v1.3，2026-01-15 更新（活跃） | **4.5**（Asset Library 标注 `2D Tools 4.5 Community`） | **【需改造】** 与你的约束冲突点明确：①末段 CA 会让走廊边缘不规则、**无法保证 ≥3 格宽**；②README 自述多线程「不稳定且更慢」，建议 `automaton_threads=1`。**建议只取它的 BSP 分区 + Kruskal 连接 + `get_rooms()/get_corridor_areas()` 数据结构，丢掉 CA 步骤**。另有官方文档级提示：它用内部 `RandomNumberGenerator`，**必须关掉 `generate_new_seed_on_run` 否则 seed 会被覆盖** | [Asset 4672](https://godotengine.org/asset-library/asset/4672) · [README](https://cdn.jsdelivr.net/gh/alexishachemi/godot-procgen@main/README.md) |
| **Edgar.Godot**（作者 RickyYC / 仓库 RickyYCheng/Edgar.Godot） | 把 Edgar-DotNet 的**图优先关卡生成器**接进 Godot：用 Godot 场景/Tiled 地图作为**手绘房间模板**，用 level graph 描述房间类型与连接，运行时组装 | **MIT**（包装层）；⚠️ 底层 Edgar-DotNet 的授权**我未能核实（待确认）** | v0.5.9，2026-06-16 更新（活跃） | **4.5**（`Tools 4.5 Community`） | **【需改造】最贴合你的图论需求，但代价最高。** 优点：level graph + room templates（手工房间）+ 门/走廊连接 + 约束（我在仓库里看到 `CorridorConstraint` / `MinimumDistanceConstraint` / `BasicConstraint` / `FixedConfigurationConstraint` 等实现）+ 可接 C# 或 GDExtension 两种内核。缺点：需要 **.NET 版 Godot** 或 **Edgar.GDExtension**，安卓导出链路复杂度上升；上游 Edgar 明确「**不适合大关卡，最佳 <30 房间**」 | [Asset 3770](https://godotengine.org/asset-library/asset/3770) · [Edgar-Unity 文档](https://cdn.jsdelivr.net/gh/OndrejNepozitek/Edgar-Unity@docusaurus/docs/introduction.md) |
| **DTL (Dungeon Template Library) — Godot GDExtension**（作者 krazyjakee，包装 AsPJT/DungeonTemplateLibrary） | C++ DTL 的 GDExtension 绑定，一次调用返回一维网格数组：`RogueLike` / `SimpleRogueLike`（房间+走廊，参数含 `min_way_horizontal` 等走廊尺寸）/ `MazeBar` / `MazeDig` / `ClusteringMaze` / CA 岛屿 / Voronoi / Perlin | **MIT** | v1.0，2025-01-03（一年前，更新较慢） | **4.3** | **【可直接使用，但功能偏底层】** 优点：**C++ 原生、有 GDExtension 版，对手机性能最友好**；缺点：**只给「网格数据」，没有房间语义、没有房间图、没有预算系统**，图论校验必须自己在其输出上重建。⚠️ 安卓需要各 ABI 的 `.so`，**该 release 是否自带 Android 二进制我未能确认（待确认）** | [Asset 3583](https://godotengine.org/asset-library/asset/3583) · [README](https://cdn.jsdelivr.net/gh/krazyjakee/DungeonTemplateLibrary-Godot@main/README.md) · [Codeberg 镜像](https://codeberg.org/krazyjakee/DungeonTemplateLibrary-Godot) |
| **Blobsmith Autotile Wirer**（作者 blobsmith） | **与生成算法无关**，解决 autotile 配置痛点：把 47-blob 图集**一键**生成完整配好 terrain 的 TileSet（Match Corners and Sides，47 个 tile 的 peering bits 全自动），也支持 16-tile 的 sides-only（Match Sides），可选整格碰撞 | **MIT** | v1.0.0，2026-09-06（新） | **4.3**（作者声明「已在 Godot **4.7 stable** 上验证，含 headless 测试套件」——**这是作者自述，我未复现**） | **【可直接使用】** 省掉手工配 47 个 tile 的一整天。注意它是编辑器工具（Project > Tools），运行时不用 | [Asset 5343](https://godotengine.org/asset-library/asset/5343) |
| **YATI (Yet Another Tiled Importer) for Godot 4**（作者 Kiamo） | 导入 Tiled 的 `.tmx/.tsx` 到 Godot 4 | **MIT** | v2.2.7，2026-03-20 更新（活跃） | **4.3** | **【可直接使用】** 若你走「Tiled 手绘模板房 → Godot」路线，这是首选导入器 | [Asset 1772](https://godotengine.org/asset-library/asset/1772) |
| **Godot4-TiledImporter**（作者 feendrache） | Tiled 导入（旧） | MIT | **最后更新 2022-12-23**（停更） | 4.0 | **不推荐**（维护停滞，被 YATI 取代） | [Asset 1583](https://godotengine.org/asset-library/asset/1583) |
| **loothammer/godot_2D_procedural_dungeon_gen** | 极简 GDScript 示例：80×80 网格、10 个 8×8~16×16 房间、L 形走廊（`carve_corridor(prev, curr, 3)` 已带宽度参数）、自动加墙、TileMapLayer 渲染 | **MIT**（README 明确写 MIT） | 学习项目 | 4.x（README 称 tested 4.0+，使用 `TileMapLayer`） | **【仅参考思路】** 代码很短适合起步抄结构。**致命缺陷：全程用 `randi_range`，无 seed 控制**，且 README 自陈「走廊偶尔会产生极窄通道」——正好是你必须避免的。必须改造 | [GitHub](https://github.com/loothammer/godot_2D_procedural_dungeon_gen) |
| **statico/godot-roguelike-example** | 完整 Godot 4 roguelike 示例：**BSP 地牢生成** + 多生成器类型（dungeon/arena）+ 可配置参数的**地图生成预览工具**（`scenes/debug/map_generator_tool.tscn`，点 Regenerate Map 即重随）+ **CSV 数据驱动**的物品/怪物表 + FOV/迷雾 + 行为树 AI | **MIT**（代码）；美术是 Dawnlike，另有自身授权 | 作者在职维护，自陈 "unfinished" | 4.x | **【仅参考思路】** **对你价值最高的一条**：它演示了「生成器参数 → 编辑器内一键预览」的调试工作流，以及「CSV 表驱动内容」——正是你要的战利品/敌人预算表形态 | [GitHub](https://github.com/statico/godot-roguelike-example) |
| **Dungeon Forge**（Ladnopoka/Godot-room-generator-plugin） | 编辑器插件：三种生物群系（地牢/木屋/冰冻洞穴）生成 **3D GridMap** 布局与网格，含第一人称探索、保存/复用布局 | **README 未声明授权 → 待确认** | 有后续计划；自陈已知 bug（重启丢失存档） | 4.x（README 称 "Godot 4 extension plugin"） | **【仅参考思路】** 它是 **3D GridMap**，与你的 2D tile 管线不通用。授权不明 + 3D，**不建议引入** | [GitHub](https://github.com/Ladnopoka/Godot-room-generator-plugin) |
| **Dingo Room Generator**（作者 benjtek01） | 程序化地牢/房间生成与装饰 | **MIT** | v1.0，2026-01-08 | 4.0，但 Asset Library 分类为 **3D Tools** | **【不推荐】** 3D 向 | [Asset 4654](https://godotengine.org/asset-library/asset/4654) |
| **2D Procedural Map Generator**（Unreference / DereferenceMyPointer） | 2D 地图生成 | MIT | v1.0.0，2024-06-16 | 4.2 | **未详查内容**（我未打开仓库 README，不敢下结论） | [Asset 3070](https://godotengine.org/asset-library/asset/3070) |
| **Procedural Scene Generator 2D**（FerrisPhilippi） | 2D 程序化场景生成 | MIT | v0.1，2024-06-24 | 4.3 | **未详查内容** | [Asset 3100](https://godotengine.org/asset-library/asset/3100) |

> 检索方式备注：上表来自 Godot Asset Library 官方检索 API（`https://godotengine.org/asset-library/api/asset?filter=<关键词>&godot_version=4.5`），关键词 `dungeon`（仅 2 条）、`roguelike`（仅 1 条）、`procedural`、`map generator`、`tiled`。**结论：Godot 4 生态里「成熟的 2D 房间-走廊地牢生成插件」非常稀缺**——真正可用的只有 ProcGen、Edgar.Godot、DTL 三个，其余要么是 3D、要么是教学项目、要么已停更。

### C2. TileMap / TileMapLayer 与 terrain autotiling（**全部内置，不需要插件**）

| 项目 | 结论 | 依据 |
|---|---|---|
| `TileMap` vs `TileMapLayer` | **`TileMap` 已废弃**；`TileMapLayer` 一个节点只有一层 tile，用多个节点代替多层。官方描述原文：「Unlike the TileMap node, which is deprecated, TileMapLayer has only one layer of tiles.」 | [class_tilemaplayer 文档源](https://docs.godotengine.org/en/stable/classes/class_tilemaplayer.html) |
| 批量写 tile | `set_cell(coords, source_id, atlas_coords, alternative_tile)`；**更新在帧末批处理**，要立刻生效需 `update_internals()`（官方明确警告该操作开销大、少用） | 同上 |
| 读回已用格（做连通性/校验用） | `get_used_cells()` / `get_used_cells_by_id()` / `get_used_rect()`；`get_cell_tile_data()` 可取 **Custom Data Layer**（把「房间 ID / 房间类型 / 可走」写进 tile 的 custom data 是很好的做法） | 同上 |
| **terrain autotiling（47-blob / 9-slice）** | **内置**。`TileSet` 的 terrain set 有三种模式，枚举 `TERRAIN_MODE_MATCH_CORNERS_AND_SIDES = 0`（即 **47-tile blob**，要求角与边都匹配）、`MATCH_CORNERS`、`MATCH_SIDES`。**不需要插件** | Godot `TileSet` 类参考的枚举定义（检索到官方 `class_tileset.rst` 片段：`TERRAIN_MODE_MATCH_CORNERS_AND_SIDES = 0 --- Requires both corners and side to match with neighboring tiles' terrains`）；[官方 Using TileSets 文档](https://docs.godotengine.org/en/stable/tutorials/2d/using_tilesets.html) |
| **按路径自动铺 terrain（对你的走廊特别有用）** | `TileMapLayer.set_cells_terrain_connect(cells, terrain_set, terrain, ignore_empty_terrains)`：把一组格子设成某 terrain 并**自动与邻居接合**，必要时还会修改邻居格子。另有 `set_cells_terrain_path(path, ...)`：沿路径依次连接。⚠️ 官方警告：要求 TileSet 里已配置**全部** terrain 组合，否则结果不可预期 | [class_tilemaplayer 文档源](https://docs.godotengine.org/en/stable/classes/class_tilemaplayer.html) |
| 配置 47-blob 的实际难度 | 官方文档这一节**长期被认为写得不够清楚**（社区几乎每天有人问「center bits 是干嘛的」）。社区补充版文档 + 可运行 starter 项目：[dandeliondino/godot-4-tileset-terrains-docs](https://github.com/dandeliondino/godot-4-tileset-terrains-docs)（PDF + 示例工程，**许可 CC BY 3.0**，与 Godot 文档相同）。**若不想手工配，用 Blobsmith Autotile Wirer（MIT）一键生成** | 该仓库 README（已读） |
| 图距离/可达性 | `AStarGrid2D`（网格专用，可设 `region`、`cell_size`、对角移动等）或 `AStar2D`（自定义图） | [AStarGrid2D 文档](https://docs.godotengine.org/en/stable/classes/class_astargrid2d.html) |

### C3. 可视化预览与调试

| 手段 | 说明 | 依据 |
|---|---|---|
| **编辑器内一键生成（`@tool` 插件）** | ProcGen 在 inspector 里直接给 `Generate` 按钮；Blobsmith 在 `Project > Tools` 下开工具面板。这是「改参数→立刻看图」的最短回路 | [ProcGen README](https://cdn.jsdelivr.net/gh/alexishachemi/godot-procgen@main/README.md) |
| **独立预览场景 + 重随按钮** | statico 的 `scenes/debug/map_generator_tool.tscn`：选中节点、点 Regenerate Map 即按当前参数重生成 | [statico README](https://github.com/statico/roguelike-example) |
| **专用可视化器** | ProcGen 自带 `ProcGenVisualizer`（README 原文：「See `ProcGenVisualizer` for an easy way to see and debug the result of the generator」） | 同上 |
| **图论叠加视图（强烈建议自己写）** | 把房间画成圆点、连接画成线、房间类型用颜色、出生/撤离点标星，叠加在 tilemap 之上。**这是「调好玩度」唯一能看见结构性问题的办法**（死路扎堆？环路太密？撤离点太近？）——我在现成插件里**没有找到**这个功能，需自写 | 工程建议（未找到现成实现） |
| **把 seed 显示在屏幕上 + 一键重随 + 支持手输 seed** | 立项早期就要做，否则玩家报「这张图有问题」时你无法复现 | 工程建议 |

### C4. 把生成的地图导出为「可编辑关卡」

| 方向 | 可用工具 | 状态 |
|---|---|---|
| **Tiled → Godot 4**（手绘关卡进 Godot） | **Tiled 1.10+ 自带 Godot 4 导出器**，直接产出 `.tscn`。特性：`resPath` 让 object 替换成 Godot 场景；tile 的 custom property 会导出为 Godot 的 **Custom Data Layers**；`tilesetResPath` 把 tileset 存成外置 `.tres` 共用；支持 `ySortEnabled`/`zIndex`/`noExport`/`tilesetOnly` | **【可直接使用】** [Tiled 官方文档 export-tscn](https://doc.mapeditor.org/en/stable/manual/export-tscn/)（已读源文件；「Since Tiled 1.10」） |
| **Tiled → Godot 4**（另一种） | YATI 导入器（MIT，活跃） | 同上 C1 |
| **Godot 生成结果 → 可编辑关卡**（生成后想手工微调） | 理论做法：生成完成后把 `TileMapLayer`（及其子节点/装饰）用 `PackedScene.pack()` + `ResourceSaver.save()` 存成 `.tscn`，即成为编辑器里可正常打开编辑的普通场景 | **【待验证】** 我**没有找到**官方文档中描述这一完整工作流的章节，这是基于 Godot 资源系统的推断，需自己实测 |
| **Godot → Tiled**（反向导出） | — | **未找到任何官方或成熟工具。** 明确说找不到 |

---

## D. 性能与工程

### D1. 手机上的生成耗时预算

**先说结论：没有官方权威数字。** Godot 官方文档和 Asset Library 里**不存在**「手机生成一张地图应该多少 ms」的规范，我不编造。

可用的**参考锚点**与工程建议：

| 锚点 | 数值/说明 | 出处 |
|---|---|---|
| 帧预算 | 60 FPS ⇒ **16.67 ms/帧**。任何同步生成若超过 ~16 ms 就会掉帧 | 通用常识；Godot 文档未给「生成」专项预算 |
| 玩家可感知阈值 | >100 ms 会感觉「顿一下」；>1 s 会被认为卡死（因此**加载关卡时用 loading 界面可以容忍几百 ms ~ 1–2 s**） | 通用经验值，非文档结论 |
| **实际操作建议** | ① 目标：小/中图（80×80 ~ 160×160）「生成 + 铺 tile」**同步 < 50 ms**；② **一定不要**在游戏内无缝生成（搜打撤通常是进图前 loading），放 loading 里最省心；③ 若必须局内生成，用 `WorkerThreadPool`/`Thread` 丢后台，或分帧协程（每帧处理 N 个房间 / 若干 CA 迭代） | [Godot 多线程文档](https://docs.godotengine.org/en/stable/tutorials/performance/using_multiple_threads.html)（机制来源） |
| **重要经验证据** | ProcGen README 原文：多线程「**currently quite unstable and inefficient**」，实测「增加线程数导致性能下降」，建议 `automaton_threads = 1`——**但即便如此它仍不会冻结调用线程**。说明「单后台线程」比「多线程并行分区」在 GDScript 下更实际 | [ProcGen README](https://cdn.jsdelivr.net/gh/alexishachemi/godot-procgen@main/README.md) |
| TileMapLayer 写入成本 | 批量 `set_cell` 的更新**在帧末批处理**；`update_internals()` 可强制立即更新，但官方**警告开销大、要少用**。⇒ 建议「先写进自建数组/`PackedByteArray`，校验全部通过后再一次性灌进 TileMapLayer」 | [class_tilemaplayer 文档源](https://docs.godotengine.org/en/stable/classes/class_tilemaplayer.html) |
| 实测方法 | `Time.get_ticks_usec()` 打点，把「分区 / 连接 / 走廊 / uncarve / 校验 / 铺 tile」六段分别计时并打印；在**最低配目标机**上跑 1000 张图统计 P50/P95/max | 工程建议 |

### D2. 确定性 / seed 复现最佳实践

依据：[Godot 官方 Random number generation 文档](https://docs.godotengine.org/en/stable/tutorials/math/random_number_generation.html)（原文已读）+ [ProcGen README](https://cdn.jsdelivr.net/gh/alexishachemi/godot-procgen@main/README.md)。

1. **用 `RandomNumberGenerator` 实例，不要用全局随机**。官方原文：「RandomNumberGenerator requires more code to use, but allows creating multiple instances, each with their own seed and state. This is useful in certain scenarios like networked multiplayer, replay systems, games that feature rewind mechanics, and more.」
2. **每局/每张图一个 seed，并持久化**：写进存档与日志、与「地图 ID」绑定；玩家报 bug 时能精确复现。
3. **⚠️ 给 `seed` 赋值会重置 `state`**。官方文档明确警告：「Changing the seed will reset the state, so make sure to set the seed first.」因此顺序必须是 `new()` → `seed = X` → 记录 `state`。
4. **`state` 可以存档/回滚**：官方给的用法是先存 `random.state`，之后恢复它就能重放同一段随机序列（适合「预览后再决定是否重随」）。
5. **子系统派生 seed**：不同子系统（房间布局 / 战利品 / 敌人）用不同流，避免「改一处 loot 代码导致地图结构全变」。**但注意**：我检索到一个报告——`RandomNumberGenerator` 实例在极短时间连续创建并赋 seed 时会产生**相关的随机流**（标题：「RandomNumberGenerator seeding produces correlated streams when instances are created in quick succession」）。**⚠️ 本环境无法打开该 Issue 正文（GitHub 被拦截），结论待确认。** 稳妥做法：**用同一个 RNG 顺序消费**，或给每个子系统赋**差异很大的整数**（如 `seed ^ (0x9E3779B9 * id)`）而不是相邻整数。
6. **插件级陷阱（真实踩坑，来自 README 原文）**：ProcGen 使用**内部 RNG**，「thus not affected by the global random seed」，并且**如果不禁用 `generate_new_seed_on_run`，你设的 seed 会在生成前被覆盖**。⇒ 引入任何第三方生成器时，**第一件事就是确认它的 RNG 来源与是否有自播种开关**。
7. **禁止在生产生成代码里出现全局 `randi()/randf()/randi_range()`**（它们走全局流，会互相污染且无法局部复现）。建议加一条自检脚本/lint 规则。

### D3. `RandomNumberGenerator` 与「`Random` 单例」的正确用法差异

**⚠️ 先纠正一个前提：Godot 4 里不存在名为 `Random` 的类/单例。**

依据：
- 官方 Random number generation 文档开篇原文：「Godot exposes **two ways** to generate random numbers: via *global scope* methods or using the `RandomNumberGenerator` class.」
- 我尝试访问 `https://docs.godotengine.org/en/stable/_sources/classes/class_random.rst.txt` → **HTTP 404**（Godot 文档会为每个暴露的类生成 `class_<name>.rst`，不存在说明没有这个类）。同一 stable 版本里 `class_tilemaplayer.rst.txt`、`class_randomnumbergenerator` 系列均正常。

所以你在别处看到的「Random 单例」大概率是：① **`@GlobalScope` 的全局作用域函数**（`randi()` / `randf()` / `randfn()` / `randi_range()` / `randf_range()` / `seed()` / `randomize()`；注意 Godot 4 里这些是**静态方法**，不再有 `Random` 节点或单例），或 ② 对 `RandomNumberGenerator` 的口头简称。

| 维度 | 全局作用域函数（`randi()` / `randf()` …） | `RandomNumberGenerator` 实例 |
|---|---|---|
| 初始化成本 | 零，随处可用 | 需 `new()` |
| 流的数量 | **全局仅一条**，所有调用者共享并互相推进 | 每个实例一条独立流 |
| 局部复现 | ❌ 无法（别处的调用会打乱你的序列） | ✅ 只需 seed + state |
| seed 控制 | `seed(12345)` / `randomize()`（全局） | `rng.seed = 12345` / `rng.randomize()` |
| state 存取 | ❌ 无 | ✅ `rng.state` 可读可写 |
| 专属方法 | 无 | `rand_weighted()`（按权重抽索引，**正好用于房间类型/战利品预算**）、`randfn()` 等 |
| **本项目应采用** | **禁止用于地图生成** | ✅ **统一使用**：地图一个实例、战利品一个、敌人一个，全部由图 seed 派生 |

---

## 结论与推荐

### 1. 算法选择：**图优先（Graph-based）**，不是「BSP vs CA」二选一

你的四条硬约束里有三条（全连通、撤离点 ≥2、出生—撤离图距离）**本质是图上的性质**，而 BSP/CA 都是在 tile 上「事后补救」连通性。因此推荐链路：

```
种子
 └─ ① 房间布点：BSP 递归分割（方正室内，如军事基地/实验室）
                或 泊松盘 + 分离转向（更有机，如废弃城区）
 └─ ② 房间邻接图：网格邻接 or Delaunay 三角剖分
 └─ ③ 连通性：Kruskal/Prim 求 MST  → 保证全连通（硬约束 ✅）
 └─ ④ 环路：回加 MST 之外的边 10%~20%（TinyKeep 用 15%）
 └─ ⑤ 走廊：固定宽度多段线/L 形，转弯处外扩
 └─ ⑥ 死路修剪：uncarve，只删一部分，保留 10%~20% 尽头房
 └─ ⑦ 房间类型分配：按图距离 + 深度，用权重表分配 6 种类型
 └─ ⑧ 图论校验（不通过就换 seed 重来，最多 N 次）
 └─ ⑨ 预算填充：按房间类型 + 深度系数，用 rand_weighted 花点数
 └─ ⑩ 铺 tile：terrain set 自动接合
```

**最关键的工程决策：逻辑格 = 3×3 tile（16px → 48px 逻辑格），走廊恒宽 1 逻辑格。** 这一条把「最小可行走宽度 ≥3 格」从「每处都要小心」变成「结构上不可能违反」，同时把寻路与生成规模缩小 9 倍。房间最小 2×2 逻辑格（6×6 tile）。

**不建议 CA（元胞自动机）**：它天生破坏走廊宽度，且抹掉房间语义——你要房间类型表，就必须保住清晰的房间边界。

### 2. 插件选择

| 优先级 | 选择 | 理由 |
|---|---|---|
| **首选** | **不直接用插件**，用 Godot **内置的 `TileMapLayer` + `TileSet` terrain set（47-blob 模式）+ 自写生成器**（约 600–1200 行 GDScript） | 现有插件**没有一个**能同时满足「房间类型表 + 图论硬校验 + 3 格宽走廊」。自写核心反而更快，且 GPL-3.0 项目没有授权摩擦 |
| **省时方案** | **ProcGen（MIT，Godot 4.5）→ 【需改造】**：取它的 BSP 分区 + Kruskal 连接 + `get_rooms()/get_corridor_areas()`，**丢掉 CA 步骤**，并把它的内部 RNG 换成你注入的 `RandomNumberGenerator`（并关掉 `generate_new_seed_on_run`） | 活跃维护、纯 GDScript、零导出风险；BSP + MST 恰好是你需要的骨架 |
| **高级方案** | **Edgar.Godot（MIT，Godot 4.5）→ 【需改造，风险中高】**：如果你想走「手工画房间模板 + 用 level graph 描述房间类型与连接」的路线，这是**唯一**现成的图优先方案（含 `CorridorConstraint`/`MinimumDistanceConstraint` 等约束） | 代价：需要 .NET 版 Godot 或 Edgar.GDExtension，安卓导出复杂度上升；上游自陈「最佳 <30 房间」；⚠️ 底层 Edgar-DotNet 授权**待确认**，进仓库前必须先查清 |
| **性能方案** | **DTL Godot GDExtension（MIT，Godot 4.3）→ 【可直接使用但偏底层】**：用它当 C++ 挖洞器（`RogueLike` 已带走廊宽度参数），语义层/图/预算全部自己写 | 手机性能最好；但**必须确认 release 是否自带 Android 各 ABI 的 `.so`（待确认）** |
| **必装（与算法无关）** | **Blobsmith Autotile Wirer（MIT，Godot 4.3+）→ 【可直接使用】** 一键生成配好 47-blob terrain 的 TileSet | 省一天手工配置；只是编辑器工具，不影响运行时 |
| **参考资料（不引入）** | statico 的 `godot-roguelike-example`（MIT，BSP + **地图生成预览工具** + CSV 数据驱动） | 只抄「调试工作流」和「数据表形态」的想法 |

### 3. 因为你做的是「搜打撤」，再补两条针对性建议

- **撤离点不要「生成完再随便挑两个房间」**。应在 ⑦ 阶段就用**图 BFS 跳数 + tile 路径长度双阈值**筛选：`跳数 ≥ 4 且 路径长度 ≥ 图对角线的 40%`，且两个撤离点互不相邻（避免一局里两个出口挨着）。这里正好用 `AStarGrid2D` 算真实路径长度。
- **高价值房应落在「环路末端」而不是「主干道旁边」**。Gungeon 的做法是让宝箱多数位于单向环路的尽头或需要多打几间房才能拿到（BorisTheBrave 文中原话：「The majority of chests in the game either are at the end of a one way loop, or deep enough into the level to force you to fight many rooms just for that chest. No risk – no reward.」）。你的「搜打撤」风险-收益曲线可以直接复用这个规则：**用图距离筛高价值房**。

### 4. 授权合规小结

- 上表所有 Godot 资产均为 **MIT**，与 GPL-3.0 项目兼容；唯一例外是 **Dungeon Forge 授权未声明（待确认）**、**Edgar-DotNet 授权未核实（待确认）**。
- **Edgar-Unity（Unity 版）明确不可再分发或转售**——注意不要把 Unity 版资源直接搬进 Godot 仓库。
- 学习资料（Bob Nystrom / TinyKeep / BorisTheBrave / Red Blob / Darius Kazemi）**只学思路，代码全部自己写**；Bob Nystrom 的 demo 代码（`munificent/rooms-and-mazes`）作者自述「pretty gnarly」，本来也不适合照搬。
