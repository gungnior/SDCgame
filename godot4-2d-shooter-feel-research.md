# Godot 4.x 安卓 2D 俯视像素「搜打撤」射击 —— 战斗核心 & 手感调研

> 调研方式：全部结论来自本次实际 `web_search` / `web_fetch`。
> **沙箱限制（诚实声明，影响可信度分级）**：
> - `github.com` / `raw.githubusercontent.com` / `api.github.com` 在本沙箱 **DNS 被拦**，`web_fetch` 全部失败 → **所有 GitHub 仓库的 LICENSE 文件我都没能亲自打开**，授权信息来自 Godot 官方资产库/商店的登记字段或搜索结果标题，属**二手信息**，落地前请自己打开 LICENSE 复核。
> - `archive.org` / `youtube.com` / `gamedeveloper.com`（Cloudflare 403）同样无法直连 → 相关演讲 URL 属「搜索结果中可见但未亲自打开正文」。
> - 能 100% 亲自打开并引用的：**Godot 官方文档**、**Godot Asset Store（store.godotengine.org）**、**Godot 旧 Asset Library（godotengine.org/asset-library）**、**Godot 官方论坛**、**saltmire.github.io** 教程。
>
> 标签含义：**【可直接使用】**= 授权&版本合适、开箱即用；**【需改造】**= 能用但要改/升级/裁剪；**【仅参考思路】**= 别直接抄，自己实现。

---

## A. 战斗核心

### A1. 弹道实现方案对比

| 方案 | 适用场景 | 性能 | 对手感的影响 | 致命坑（有官方/论坛依据） |
|---|---|---|---|---|
| **`Area2D` 物理子弹** | 慢速可见弹（手雷、火箭、能量球、弩箭）、需要真实碰撞反弹、< 50 发同屏 | 中。每个 Area2D 有节点开销 + 物理宽相位 | 有**可见飞行时间** → 必须打提前量（lead），慢弹速会让「我明明瞄到了」变成常态，压手感 | **不会在同一帧内采样多个位置**，高速子弹会**穿模漏检**。官方论坛答复：CharacterBody2D 用 `move_and_slide` 一帧内走多步，Area2D 采不到；解法是**把碰撞形状沿运动方向拉长**或**改用 raycast**。[来源](https://forum.godotengine.org/t/should-i-use-area2d-for-bullet/126535/2) |
| **`CharacterBody2D` 物理子弹** | 需要自己写碰撞响应（穿透/反弹）的可见子弹 | 中 | 同上 | `move_and_collide()` 返回 `KinematicCollision2D`，含 `get_position()` / `get_normal()`，可自己写 `velocity.bounce(normal)`。[官方 Physics introduction](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html) |
| **射线 / hitscan（`RayCast2D` 或 `PhysicsDirectSpaceState2D.intersect_ray`）** | **高射速武器、霰弹、机枪、狙击、任何「瞬时命中」需求** | 高。一次查询，无节点、无物理体 | **即点即到**，反馈零延迟，是射击手感的地基 | ①**只能在 `_physics_process()` 里访问 space**，`_input()` 里可能 space 被锁；②返回值是 Dictionary（`position / normal / collider / collider_id / rid / shape / metadata`）；③自击穿问题用 `exclude` 或 `collision_mask`。全部见[官方 Ray-casting 文档](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html) |

**关键官方结论（直接影响架构选型）**：Godot 官方文档明确写道，提高 physics ticks per second 的**额外好处**是「**让 tunneling（穿透漏检）和物理不稳定更不容易发生**」——反过来说，**默认 60Hz 的物理引擎一定会 tunneling**。
来源：[Fixing jitter, stutter and input lag](https://docs.godotengine.org/en/stable/tutorials/rendering/jitter_stutter.html)

**性能上限方案（万弹级）**：绕开场景树，直接用 `PhysicsServer2D` / `RenderingServer` 创建对象。官方文档专门有一节并点名了官方 demo：
- [Optimization using Servers](https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html)（含 `PhysicsServer2D.body_create()`、RID 生命周期、以及 **「不要每帧向 server 查询数据，会 stall 服务器、严重掉性能」的警告**）
- 官方 demo：**Bullet Shower（`2d/bullet_shower`）** — <https://github.com/godotengine/godot-demo-projects/tree/master/2d/bullet_shower> **【可直接使用/参考】**

**推荐（结论）**：
> **逻辑层一律用 hitscan 射线判定（权威判决），表现层再决定要不要画一颗飞行的子弹。** 对你们的「模拟层/表现层分离 + headless 单测」是天然契合的。
> 例外：狙击/火箭/投掷物等**需要被玩家看见并预判**的弹药，才用可见的物理或纯视觉抛物线子弹。

---

### A2. 命中判定：2D 俯视怎么做「部位伤害」

2D 俯视视角下，**「爆头」在视觉上不成立**（你看到的是头顶）。所以行业做法是把它转化为**「弱点区域」**语义。三条可落地路线：

| 做法 | 实现 | 评价 |
|---|---|---|
| **多 shape + `shape` 索引映射** | 一个敌人身上挂多个 `CollisionShape2D`（头/躯干/四肢），射线返回的 `result["shape"]` 就是**命中的子形状索引** → 查表得部位与倍率 | **最推荐**。官方 `intersect_ray` 返回值里原生带 `shape: int`（[Ray-casting 文档](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html)） |
| **多 Area2D + 碰撞层分层** | `head_hurtbox` 在层 6、`torso_hurtbox` 在层 7，用 `collision_mask` 区分 | 可行，但每帧多几次查询；适合需要**不同判定逻辑**（如护甲只挡躯干）时 |
| **命中点几何判定** | 拿到 `result.position`，相对敌人朝向做扇形/椭圆归属判断（前 60° = 躯干，背后 = 背刺暴击） | 对**「侧身/背刺」这类俯视专属机制最自然**，但对「爆头」不适用 |

**层/掩码最佳实践（官方原话要点）**：每个 `CollisionObject2D` 有 32 层；`collision_layer` = **我在哪层**，`collision_mask` = **我扫描哪些层**。命名层在 **Project Settings → Layer Names → 2D Physics**，运行时代码用 `set_collision_layer_value(n, true)`，编辑器导出用 `@export_flags_2d_physics`。
来源：[Physics introduction → Collision layers and masks](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html#collision-layers-and-masks)

> **来源标注**：「俯视视角不该做爆头」是**设计层面判断**（我的工程结论），非查证事实。技巧层面的「多 shape / shape 索引」有官方文档支撑。

---

### A3. 穿透、跳弹、扩散、弹道下坠

| 特性 | 实现要点 | 来源/性质 |
|---|---|---|
| **穿透** | 不要依赖物理引擎穿透。做法：一次 `intersect_ray` → 命中 → **把命中体加进 `exclude` 再打一次**，循环消耗「穿透力 / remaining_penetration」；每穿一层按材质扣减伤害 | 机制基于官方 `exclude` 与 `intersect_ray`；【仅参考思路】自己实现 |
| **跳弹** | 用 `result["normal"]`；2D 里最省事的是 `velocity.bounce(normal)`（官方 Physics introduction 里有现成示例）。真实化则加**跳弹概率 + 入射角阈值**（入射角太平坦才跳） | 官方有 `bounce()` 示例：[Physics introduction](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html)；**概率/阈值是设计参数** |
| **扩散** | 不要用 `randf_range` 均匀分布（弹孔会「四角多中间少」，观感假）。用**高斯/三角分布** + **固定弹道图案（spread pattern）**（数据里存 N 发偏移序列，循环取） | 纯工程经验【仅参考思路】 |
| **弹道下坠** | **2D 俯视强烈建议不做。** 俯视没有重力轴，下坠只会在**画面上表现为莫名偏离准心**，玩家读不出来，手感 = 变差。用**射程衰减（距离 → 伤害/穿透衰减）**替代 | **我的设计结论**，非查证事实 |
| **射速/精度动态** | 扩散值随连续射击增长、停火后线性回落（`spread_base` / `spread_per_shot` / `spread_max` / `spread_recovery`），这是「压枪」手柄感的来源 | 设计模式，无单一权威源 |

**一个已知的现成穿透插件**（授权/版本需你自己复核）：
`PenetrationSystem` by Lakamfo — GitHub <https://github.com/Lakamfo/PenetrationSystem>，商店页 <https://store.godotengine.org/asset/lakamfo/penetrarion-system/>。**授权与 Godot 版本：待确认**（我未打开详情页）**【仅参考思路】**

---

### A4. 高射速武器（机枪）在 Godot 4 的性能做法

按「先别优化，最后再优化」的前提，优先级从高到低：

1. **不要每发子弹建一个物理节点。** 高射速武器一次开火 = **一次 raycast**（hitscan），视觉上再画 tracer。
2. **每物理帧合并散射**：机枪 900 RPM = 15 发/秒，60Hz 下**平均每 4 帧才 1 发**，根本不需要「一帧发 N 发」的特殊处理。真正要处理的是**霰弹枪**（一枪 8–12 丸）→ 用 `PhysicsDirectSpaceState2D` 连打 N 次查询即可，无须节点。
3. **要显示海量子弹时**：走官方 `PhysicsServer2D` 路线（见上面的 Bullet Shower demo），或者干脆**子弹完全不用物理**：自己维护 `Array` 做圆-圆/圆-AABB 判定，一帧批量算完，用 `RenderingServer.canvas_item_add_texture_rect` 或 `MultiMeshInstance2D` 一次画完。
4. **弹幕量级参考**：社区项目 `Jhon-Crow/godot-topdown-MVP` 有一个专门的 PR **「Optimize projectiles for 200+ bullet-hell scenarios」**（#776），说明 200+ 是 Godot 4 社区认为需要专项优化的量级线。<https://github.com/Jhon-Crow/godot-topdown-MVP/pull/776>（GitHub 被拦，未验证内容；授权**待确认**）**【仅参考思路】**

---

### A5. 对象池：Godot 4 的推荐做法

**先泼冷水（重要事实）**：**Godot 4 没有任何内置的对象池节点。** 需要把 Godot 3 的 `PoolByteArray` 之类迁移到 `PackedByteArray` 的官方迁移文档里能看到命名变更，但**没有「Pool 节点」这种东西**。

**推荐做法（自建 autoload 池）**，社区总结得很到位的一篇（可完整访问，代码可直接抄）：
[Object pooling vs instantiate in Godot 4 — when it actually matters](https://saltmire.github.io/godot-4-object-pooling-vs-instantiate.html)

要点摘录 + 我的补充：
- **什么时候才值得池化**：该文给出的经验阈值是「**持续每秒 spawn + free 超过约 20 个对象**」才值得；低于这个数 `instantiate()` 不是瓶颈，池化只是增加 bug 面。
- **必须给每个可池化对象写 `reset()`**：池化对象**永远不是干净的**，它会带着上一个使用者的 velocity / timer / tween / signal 连接回来。这类 bug 的特征是「第一次正常，第五十次出错」。
- **`take()` 永不返回 `null`**：池空时回退到真实 `instantiate()`。静默丢失一颗子弹比多一次分配难 debug 得多。
- **预热要在加载屏或分帧做**（`await get_tree().process_frame`），否则你只是把卡顿从战斗中搬到了战斗开始那一刻。

**现成插件**：

| 项目 | 授权 | Godot 版本 | 状态 | 标签 |
|---|---|---|---|---|
| [Godot Projectile Engine](https://store.godotengine.org/asset/azyrgames/godot-projectile-engine/) | **MIT**（商店登记） | Godot 4.4（商店 `Minimum 4.4`） | **v0.6.0-beta，作者自己警告「contains many bugs, frequent breaking changes…not recommended for production use」** | **【仅参考思路】** |
| [Object Pooling - Godot 4](https://store.godotengine.org/asset/levari-f/object-pooling-godot-4/) | **待确认** | **待确认** | 我只在搜索结果里见到标题，未打开详情页 | **待确认** |
| "Indie Blueprint Pool" | **待确认** | **待确认** | 仅见编辑记录页 | **待确认** |

> **结论**：对象池这件事**自己写 60 行**比引入 beta 插件更划算。你们已经有「数据驱动 + 模拟/表现分离」的架构洁癖，池子属于表现层，自己写反而更干净。

---

## B. 手感 / Game Feel

> ⚠️ **先说实话**：手感**没有任何文档、任何 AI 能替你调到「好」**。下面能给你的是**模型、实现方式、参数该往哪个方向动、以及哪些是公认高性价比项**。最终数值必须靠**真人反复试玩 + 盲测**。我会在每个数值处明确标注「**必须人工调参**」。

### B1. 后坐力的三种实现模型

| 模型 | 机制 | 优点 | 缺点 | 适合 |
|---|---|---|---|---|
| **纯视觉后坐** | 只推枪贴图 / 枪手臂旋转 / 相机轻微 kick 后回原位，**准心数据不动** | 上手最快，玩家不会「打不准」，2D 里观感提升明显 | 没有技术深度，长期玩会腻 | 休闲向、双摇杆体验优先 |
| **真实准心偏移 + 回正** | 射击时准心真的被推走，停火后按恢复速率拉回 | 有「压枪」技术表达，可做武器性格差异 | 手机小屏上很痛苦；纯 pointer 瞄准时容易失控 | 键鼠/手柄的硬核向 |
| **两者结合（主流）** | 视觉 kick（立刻、夸张、纯表现）+ 准心偏移（较小、真实、影响判定）**分成两条通道**，各自独立衰减 | 既爽又能保留技术上限 | 调参量翻倍 | **推荐你们的方案** |

**建议的数据字段（放进你们的 JSON/Resource）**：
`recoil_visual_kick`（像素/度）、`recoil_visual_recover`（恢复速度）、`recoil_aim_offset`（准心真实偏移角，建议很小）、`recoil_aim_recover`、`spread_base / spread_per_shot / spread_max / spread_recover`、`recoil_pattern[]`（固定后坐图案，可选）。

> **必须人工调参**：所有这些数值。文档只能告诉你「分两条通道」，告不了你 kick 该是 3px 还是 8px。
> **可执行方法**：做一个调试热键面板（或直接用 Godot 编辑器的 **Remote Inspector** 在运行中改 `@export` 变量），**一次只改一个参数**、录屏、隔天盲测排序。

---

### B2. 命中反馈：哪些对「手感」贡献最大

按**性价比排序**（我的判断，基于 [Saltmire 的 Godot 4 screen shake + hit-stop 教程](https://saltmire.github.io/godot-4-screen-shake-hit-stop.html) 与通用实践）：

| 优先级 | 效果 | 为什么 | 关键参数 / 坑 |
|---|---|---|---|
| ★★★★★ | **Hitstop（命中停顿 / 冻结帧）** | **单位代码量收益最高**。它直接改变了「时间感」，让打击变「重」 | 该教程建议 **60–120 ms 为上限**，「再长游戏就感觉卡而不是猛」。全局 `Engine.time_scale` 是粗暴但有效的做法 |
| ★★★★★ | **音效**（每次命中不同音高/材质） | 玩家对听觉延迟容忍度最低，音效是打击感的骨架 | 用 pitch 随机化 + 击杀专用音 |
| ★★★★☆ | **受击闪白（sprite flash）** | 确认「打到了」的最廉价手段 | 用 `modulate` 白闪 1–3 帧，别用 shader 做全屏 |
| ★★★★☆ | **屏幕震动（trauma 模型）** | 放大冲击，但**过量即毁**（见 B3） | `offset` + trauma 平方衰减 |
| ★★★☆☆ | **命中标记 / 伤害数字** | 提供数值信息，不是「爽感」来源 | 池化，且数字**别挡住敌人** |
| ★★★☆☆ | **血雾 / 命中火花粒子** | 视觉确认 + 方向信息 | 用 `result["normal"]` 定向 |
| ★★☆☆☆ | **弹壳抛射** | 提升「开火感」而非「命中感」 | 开火帧后延迟 1–2 帧丢出，纯视觉，不参与判定 |
| ★★☆☆☆ | **枪口火光 / 扬尘** | 同上，属于**发射反馈** | 见 B4 时机 |

**核心原则（比选哪个效果更重要）**：**反馈必须分级**。轻击 / 重击 / 暴击 / 击杀 走**不同量级**的同一套效果（不同 hitstop 时长、不同震动 trauma、不同音效、不同粒子数量）。全部用同一套 = 玩家分辨不出轻重，手感反而变平。

> **必须人工试玩**：以上哪个贡献最大**没有客观数据**，高度依赖你的游戏节奏（搜打撤节奏偏慢，可能 hitstop 权重更高；如果节奏快，音效权重更高）。

**现成「一站式」手感库**（省掉接线工作）：

| 项目 | 授权 | Godot 版本 | 内容 | 维护/评价 | 标签 |
|---|---|---|---|---|---|
| [**Saltmire Juice**](https://store.godotengine.org/asset/saltmire/saltmire-juice/)（源码 <https://github.com/saltmire/saltmire-juice>） | **MIT**（商店登记） | **Godot 4.6+**（商店 `Minimum 4.6`） | trauma 屏幕震动、hit-stop、sprite flash、**池化伤害数字**、弹性 scale pop；**单个 autoload、零依赖**，有可玩网页 demo | v1.0.0，2026-07；商店标注「Uses AI: AI-assisted code, reviewed and tested by hand」 | **【可直接使用】**（若你们锁 4.4/4.5 则需改造） |
| [**GameFeelFlow**](https://store.godotengine.org/asset/indieshade/gamefeelflow/) | **MIT**（商店登记） | **Godot 4.6+** | 29 个效果 + 15 个组合（transform/camera/audio/time/particles/physics/events），数据驱动，Inspector 编辑，自定义 easing、叠加策略 | v1.0.0，2026-07，**0 条评价（全新）**；商店标注「Uses AI: generating texts, codes, **and images**」 | **【需改造/需评估】** |

---

### B3. 屏幕震动：怎么实现，以及**什么时候不该做**

**Godot 4 实现（可抄的完整代码，来自 [Saltmire 教程](https://saltmire.github.io/godot-4-screen-shake-hit-stop.html)）**——trauma 模型：

```gdscript
extends Camera2D
var _trauma := 0.0        # 0..1
var _decay := 4.0         # 每秒衰减
var _max_offset := 12.0   # 满 trauma 时的像素偏移

func shake(amount: float) -> void:
    _trauma = min(_trauma + amount, 1.0)

func _process(delta: float) -> void:
    if _trauma <= 0.0:
        offset = Vector2.ZERO
        return
    _trauma = max(_trauma - _decay * delta, 0.0)
    var t := _trauma * _trauma          # 平方 → 小击很轻、大击很猛
    offset = Vector2(
        randf_range(-1, 1) * _max_offset * t,
        randf_range(-1, 1) * _max_offset * t)
```
> 该文明确指出「**把 trauma 平方是让它手感好的关键**」。

**相机插件**：

| 项目 | 授权 | Godot 版本 | 说明 | 标签 |
|---|---|---|---|---|
| [**Phantom Camera**](https://store.godotengine.org/asset/ramokz/phantom-camera/)（by Ramokz） | **MIT**（商店登记） | Godot 4（商店 `Minimum 4.4`，当前 v0.11.0.3） | 「Godot 版 Cinemachine」，2D+3D，跟随/看向/多目标取景/相机间动画过渡；**商店 79 条好评**，24 年–26 年持续更新。文档 <https://phantom-camera.dev/> | **【可直接使用】**（但它**不是专门的 shake 库**，shake 仍需自己写或配 Saltmire） |
| **EZ Camera Shake 的 Godot 4 版** | — | — | ⚠️ **我没能查证到可靠的 Godot 4 移植版本。** 请勿据传闻引入。 | **待确认** |
| "Trauma - 2D Camera Shake Plugin for Godot" | **待确认** | **待确认** | 只在搜索结果里见到[编辑记录页](https://godotengine.org/asset-library/asset/edit/21617)，我没打开正式资产页 | **待确认** |

**该不该做 / 什么时候不该做**：
- ✅ **该做**：单次、离散、有明确因果的冲击（开枪、被击中、爆炸、击杀）用**短促、非循环**的震动。
- ❌ **不该做**：**连续随机震动**（例如机枪每一发都抖）——长时间低频随机噪声会让人不适，且**摧毁画面可读性**（俯视射击里「看清敌人在哪」比「爽」更重要）。
- ❌ **不该做**：把「自己受伤」和「自己射击」用同一套幅度 —— 玩家分不清发生了什么事。
- ⚠️ **像素游戏专属坑（工程经验，非查证）**：`randf_range` 产生的**亚像素偏移会让像素网格抖动/撕裂**，看起来像画质故障而不像震动。缓解：**把 offset 量化到整像素**；俯视像素游戏里更好用的替代是**「一帧式 kick」**（瞬间位移几像素然后立刻回位，不做随机噪声）。
- ♿ **无障碍**：务必提供「关闭 / 降低震动强度」选项（尤其是手机上的前庭不适人群）。

---

### B4. 枪口火光、弹壳、扬尘的触发时机

| 效果 | 触发时机 | 位置 | 备注 |
|---|---|---|---|
| **枪口火光** | **逻辑上「子弹生成」的那一帧**（不是按下按键那一帧，因为射速/热量判定可能拒绝这一发） | 枪口节点全局坐标，跟随枪口旋转 | 同一帧多丸（霰弹）**只显示一次** |
| **弹壳抛射** | 开火帧**之后延迟 1–2 帧** | 抛壳口 | **纯视觉、不参与判定、绝不加物理体**，用池化的 `Node2D` + Tween/手写抛物 |
| **扬尘 / 命中火花** | 射线命中的**当帧** | `result["position"]`，朝向按 `result["normal"]` | 穿透时**每次穿透都出一次**，并让烟尘更小 |
| **血雾** | 命中「活体」当帧 | 同上 | 击杀走另一套（更大、方向性更强） |
| **地面/墙面弹孔** | 命中环境当帧 | `result["position"]` | **必须池化 + 上限**（否则长时间战斗后地图上会有上万弹孔） |

实现建议：`GPUParticles2D`（一次性 `one_shot`）+ 对象池 **预热**；不要把粒子实例化放在战斗帧里造成帧时间尖峰。

---

### B5. 有价值的公开资料（URL 查证情况已标注）

| 资料 | URL | 查证情况 |
|---|---|---|
| **Jan Willem Nijman — "The Art of Screenshake"**（INDIGO Classes 2013） | Internet Archive 存档：<https://archive.org/details/the-art-of-screenshake> | ⚠️ **存在性已确认**（搜索结果显示作者署名 "Jan Willem Nijman"、标题 "The Art Of Screenshake"），但**本沙箱 archive.org 直连失败**，未能打开正文 |
| 同一演讲的 YouTube 版 | 常见链接为 <https://www.youtube.com/watch?v=AJdEqssNZ-U> | ⚠️ **未能直连验证（YouTube 被拦）→ 待确认**，请自行确认 ID |
| 同一演讲的 B 站转载（中文字幕） | <https://www.bilibili.com/video/BV1Ds411v7Ux/> | 搜索结果确认标题「屏幕震动的艺术 The Art of Screenshake」 |
| **Vlambeer 联合创始人的动作游戏设计建议**（Game Developer 报道） | <https://www.gamedeveloper.com/design/vlambeer-co-founder-shares-advice-on-building-better-action-games> | ⚠️ 页面 **HTTP 403（Cloudflare）**，标题/主题在搜索中确认，**未能读取正文** |
| **"Juice it or lose it"**（Martin Jonasson & Petri Purho）相关报道 | <https://www.gamedeveloper.com/design/video-indies-resist-the-urge-to-juice-it-or-lose-it-> | ⚠️ 同上 403；YouTube 原始 ID **待确认** |
| **Saltmire — Godot 4 screen shake and hit-stop in one script** | <https://saltmire.github.io/godot-4-screen-shake-hit-stop.html> | ✅ **完整读取**，含可抄代码与 60–120ms 建议 |

---

### B6. 像素射击游戏特有的手感问题

#### （1）像素旋转锯齿 —— **你们「12 角度烘焙」的决策是对的**

**官方文档给出了决定性依据**：Godot 2D MSAA **「永远不会影响 nearest-neighbor 滤波纹理内部（即像素画）的锯齿」**；也就是说**开 MSAA 修不了像素图旋转的锯齿**。
来源：[2D antialiasing](https://docs.godotengine.org/en/stable/tutorials/2d/2d_antialiasing.html)（原文：*"Aliasing within nearest-neighbor filtered textures (pixel art)"* 明确列在 **MSAA 无效** 清单里）

**推论（工程结论）**：
- 连续旋转的像素图 = **必然锯齿**，且没有便宜的修复（关 nearest 用 linear 会糊成一团，更糟）。
- **烘焙有限角度（你们选的 12 角）+ 最近邻**是像素游戏的标准正解。
- 社区还在推动 "sharp bilinear" 之类的折中滤波（[godot-proposals #6995](https://github.com/godotengine/godot-proposals/issues/6995)），**状态待确认**（GitHub 被拦）。

#### （2）帧率 / 分辨率设置与手感 —— **一个和你们方案直接冲突的官方警告**

官方 [Multiple resolutions](https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html) 对像素游戏的推荐是 `viewport` 拉伸模式 + `integer` 缩放（防止像素缩放不均），但**同一页给出明确警告**：

> *"The `viewport` stretch mode ... If you are OK with sprites being able to move or rotate in **sub-pixel** positions, you should use the `canvas_items` stretch mode instead."*

**这对你们是硬冲突**：武器要**连续跟随任意瞄准角**（亚像素旋转/位置），而 `viewport` + integer scale 恰恰会**杀死亚像素运动**。
→ **建议：`canvas_items` stretch mode + `integer` stretch scale mode**（`Stretch Scale Mode` 是 Godot 4.2+ 才有的设置，官方说明它「防止像素画缩放不均」）。这样画面缩放仍是整数倍，但世界坐标保留亚像素精度，武器旋转才不会一跳一跳。
> 这一条建议是**官方文档两段话的交叉推论**，不是文档直接结论 —— 请务必实机 A/B。

#### （3）物理插值（4.4+）—— 平滑 vs 输入延迟的官方权衡

- 官方提供 **physics interpolation**，能消除「物理 60Hz vs 屏幕刷新率不一致」造成的 **jitter**。
- **但官方文档明确写**：*"Enabling physics interpolation will **increase input lag** for behavior that depends on the physics tick, such as player movement."* 并建议用**提高 physics ticks per second** 来补偿。
- 官方还提醒：**固定帧率游戏（格斗/音游）要谨慎考虑**。
→ 文档页：[Fixing jitter, stutter and input lag](https://docs.godotengine.org/en/stable/tutorials/rendering/jitter_stutter.html)；physics interpolation 专页（4.4 版）：<https://docs.godotengine.org/en/4.4/tutorials/physics/interpolation/2d_and_3d_physics_interpolation.html>

**对你们的建议**：射击游戏**输入延迟 > 视觉平滑**。默认**关闭** physics interpolation，先用**提高 physics ticks（120/180/240）** 换低延迟；若实机画面抖动明显再单独评估。

#### （4）输入延迟优化清单（**全部出自官方文档，可直接照做**）

| 手段 | 官方说明 | 代价 |
|---|---|---|
| 关闭 V-Sync | 可显著降低输入延迟感知 | 画面撕裂 |
| **`Display > Window > V-Sync > Swapchain Image Count = 2`**（Godot **4.3+**，仅 Forward+/Mobile） | 双缓冲替代默认三缓冲，降低视觉延迟 | 帧率不稳时**直接从 55→30 FPS**，仅当能稳定跑满刷新率时用 |
| **提高 `Physics > Common > Physics Ticks Per Second`**（默认 60 → 120/180/240） | 「尤其在使用物理插值时明显」；**且能减少 tunneling** | CPU 上升；**不同物理频率会产生不同模拟结果**（联机公平性问题） |
| **`Input.set_use_accumulated_input(false)`** | 让 `_input()` 每帧真正被调而不是累积等待渲染帧 | 官方警告「CPU 使用上升，需谨慎」 |
| **独占全屏（Exclusive Fullscreen）** | 官方明说非独占的 Fullscreen 会留 1 像素线，妨碍系统降低延迟 | — |
| `--disable-vsync` / `--max-fps` 命令行（4.2+） | 用于测试 | — |
| VRR 屏：开 V-Sync + 把 FPS 上限设成略低于刷新率（如 144Hz → 141） | 官方引用 blurbusters 方案 | — |

来源：[Fixing jitter, stutter and input lag](https://docs.godotengine.org/en/stable/tutorials/rendering/jitter_stutter.html)

#### （5）Android 特有

- 官方原文：**Android 通常 jitter/stutter-free**（activity 拿到全部优先级）；「问题设备」少见。
- **已知问题追踪**：`InputEventScreenDrag` 在 Android 上触发间隔过长 — [godotengine/godot issue #120322](https://github.com/godotengine/godot/issues/120322)。**修复状态待确认**（GitHub 被拦，无法读取）。→ 对瞄准摇杆是**直接风险**，务必在真机先验证。

---

## C. Godot 4 现成资源

### C1 + C2. 射击模板 / 相机插件 总表

| 项目 | 类型 | 授权 | Godot 版本 | 维护状态 | 标签 |
|---|---|---|---|---|---|
| [**Phantom Camera**](https://store.godotengine.org/asset/ramokz/phantom-camera/) | 相机插件 | **MIT**（商店登记） | 4.x（商店 `Minimum 4.4`），当前 v0.11.0.3 | 活跃，2026-07 更新，79 好评 | **【可直接使用】** |
| [**Saltmire Juice**](https://store.godotengine.org/asset/saltmire/saltmire-juice/) | 手感套件 | **MIT**（商店登记） | **4.6+** | v1.0.0，2026-07；含 trauma shake / hitstop / flash / 池化伤害数字 | **【可直接使用】**（4.6+） |
| [**GameFeelFlow**](https://store.godotengine.org/asset/indieshade/gamefeelflow/) | 手感框架 | **MIT**（商店登记） | **4.6+** | v1.0.0，2026-07，**0 评价**；使用 AI 生成文本/代码/**图片** | **【需改造/需评估】** |
| [**Godot Projectile Engine**](https://store.godotengine.org/asset/azyrgames/godot-projectile-engine/) | 弹道引擎 | **MIT**（商店登记） | 4.4 | **v0.6.0-beta，作者明确警告勿用于生产** | **【仅参考思路】** |
| [**Virtual Joystick DX**](https://godotengine.org/asset-library/asset/5256)（Repechul） | 触屏摇杆 | **MIT**（资产库登记） | **4.6+（作者称 tested on 4.7）** | 2026-08；360°摇杆/8向D-Pad、STATIC·DYNAMIC·FOLLOWING、**Action Mapping 5 种触发模式（可用于第二摇杆瞄准）**、触觉反馈、Active Region、自动隐藏、模块化 | **【可直接使用】** |
| [Virtual Joystick](https://godotengine.org/asset-library/asset/1787) | 触屏摇杆 | **待确认** | **待确认** | 未打开详情页 | **待确认** |
| [**Simple Concept Template: 2D Top-Down-Shooter**](https://godotengine.org/asset-library/asset/2460)（BosenCheng / Unchained112） | 模板 | **MIT**（资产库登记） | **Godot 4.2**，Community | **2023-12-28 最后更新**（偏旧）。含伤害数字、受击闪烁、击杀叉号、**相机震动**、血粒子、拖尾、音效 | **【需改造】**（仅当练手/对照，别当骨架） |
| [**Jhon-Crow/godot-topdown-MVP**](https://github.com/Jhon-Crow/godot-topdown-MVP) | 开源射击 MVP | **待确认**（GitHub 被拦） | Godot 4 | 活跃（有 C# 重构、200+ 弹幕优化 PR #776） | **【仅参考思路】** |
| [**Lakamfo/PenetrationSystem**](https://github.com/Lakamfo/PenetrationSystem) | 穿透系统 | **待确认** | **待确认** | — | **【仅参考思路】** |
| [godot-demo-projects `2d/bullet_shower`](https://github.com/godotengine/godot-demo-projects/tree/master/2d/bullet_shower) | 官方 demo | **MIT**（Godot 官方 demo 项目） | Godot 4 | 官方维护，被官方文档点名引用 | **【可直接使用/参考】** |
| **EZ Camera Shake 的 Godot 4 版** | — | — | — | ⚠️ **未找到可靠来源 → 待确认** | **待确认** |

### ⚠️ 一个授权地雷（重要）

搜索相机震动时出现 **Rokojori Action Library**（<https://store.godotengine.org/asset/rokojori/rokojori-action-library/>），功能很全（VFX/SFX/屏幕震动/镜头光晕/后处理），但它的授权是 **"Rokojori Public Indie License" —— 这是自定义许可，不是 OSI 认可的开源许可**。
→ **对你们 GPL-3.0 开源、代码公开的项目，这个授权存在不兼容风险，建议直接排除。**

> **红线复查**：本次检索到的所有候选（Phantom Camera / Saltmire Juice / GameFeelFlow / Godot Projectile Engine / Virtual Joystick DX / Simple Concept Template）登记授权**均为 MIT**，**未发现 GPL-2.0 或 LGPL-2.1 的候选**。Godot 引擎本身是 MIT。

### C3. Hitstop（命中停顿）的实现库 / 标准做法

**没有「内置库」**。Godot 里没有 hitstop 节点或 API。标准做法有两种：

**做法 A：全局 `Engine.time_scale`（最简单，社区标准写法）**
```gdscript
func hit_stop(duration := 0.08, scale := 0.05) -> void:
    Engine.time_scale = scale
    # 关键：ignore_time_scale = true，否则计时器本身也被缩放
    await get_tree().create_timer(duration, true, false, true).timeout
    Engine.time_scale = 1.0
```
来源：[Saltmire 教程](https://saltmire.github.io/godot-4-screen-shake-hit-stop.html)（该文强调 **60–120 ms 上限**，再长「感觉卡而非猛」）

**坑**：`SceneTreeTimer` 的第三个参数（`process_always`）与第四个参数（`ignore_time_scale`）**必须设对**，否则冻结时长会被自己的 `time_scale` 缩放（这是最常见的 hitstop bug）。

**做法 B：局部 hitstop（更可控，推荐给群体战）**
只冻结「被击中的实体 + 攻击者」的动画/逻辑，不冻结整个世界（摄像机、UI、其他敌人照常）。
→ **这是社区常见实践，我没有找到单一权威文档来源，标注为【仅参考思路 / 工程经验】。**
对你们的「搜打撤」（多敌人 + 拾取 + 撤离计时）来说，**全局 time_scale 会连带冻结搜刮/撤离计时和所有敌人**，体验上更危险 → **建议优先局部 hitstop**。

### C4. `PhysicsServer2D` / `Area2D` 碰撞层在弹道系统里的最佳实践

1. **层划分建议（我的建议，非权威）**：
   `1 = world_solid`、`2 = player_body`、`3 = enemy_body`、`4 = player_hurtbox`、`5 = enemy_hurtbox`、`6 = bullet_blocker`（只挡子弹的墙/掩体）、`7 = pickup`、`8 = interactable`。命名写在 Project Settings 里，代码里用 `set_collision_mask_value()`。
   依据：[Physics introduction → Collision layers and masks](https://docs.godotengine.org/en/stable/tutorials/physics/physics_introduction.html#collision-layers-and-masks)
2. **射线查询用 mask，不要用巨大的 `exclude` 列表**。官方原话：靠 exceptions 「在你需要一个很大和/或动态的例外列表时会非常不方便；这种情况下**用碰撞层/掩码系统效率高得多**」。[Ray-casting 文档](https://docs.godotengine.org/en/stable/tutorials/physics/ray-casting.html)
3. **自己的角色用 `exclude = [self]`**（一次性、精准）。
4. **绝对不要在 `_process()` 里访问 physics space**；只在 `_physics_process()`。官方明确：physics 线程独立时，在回调外访问 space 可能被锁而报错。
5. **`PhysicsServer2D` 的两条铁律**（官方 [using_servers](https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html)）：
   - **RID 不受引用计数保护** → 必须自己在服务器外部**持有资源引用**，否则资源和 RID 一起被释放。
   - **绝不要每帧向 server 请求数据** → 「调用任何返回值的函数都会 **stall** 服务器，强制它处理所有挂起操作，严重降低性能，而且你还看不出原因。」
6. **服务器路线必须调用 `RenderingServer.canvas_item_reset_physics_interpolation(ci_rid)`**（若启用插值），否则对象会「瞬移入场」。[同上](https://docs.godotengine.org/en/stable/tutorials/performance/using_servers.html)

---

## D. 触屏射击的特殊性

> 前置说明：**触屏瞄准 / aim assist 不是引擎问题，Godot 没有（也不会有）官方文档**。下面 D1/D2 是**设计 + 实现模式**，标注了我的验证程度。

### D1. 辅助瞄准（aim assist）的具体做法

**四种机制（可叠加，建议只选 2 种）**：

| 机制 | 做法 | 副作用 | 建议 |
|---|---|---|---|
| **角度吸附 / 软锁（angular snap / soft lock）** | 摇杆方向在目标 ±X° 内时，实际瞄准角被拉向目标 | 太强会「抢枪」，玩家感觉失去控制 | 容差 **3–8°**，且**指数衰减**（离目标越远吸附越弱） |
| **磁性（magnetism / sticky aim）** | 准心划过目标时**降低转速**（像被粘住），而不是直接吸附 | 会拖慢大范围转向 | 只降低**角速度**不改方向，体验最自然 |
| **子弹磁性（bullet magnetism）** | **不改准心**，只在判定时把射线加粗成胶囊 / 用 `intersect_shape` 圆形扫掠 | 几乎无副作用（玩家看不到） | ★**最推荐**，尤其配合你们的 hitscan 架构 |
| **目标重力（target gravity）** | 准心被「吸引」向附近目标 | 最激进，最容易抢枪 | 仅在「目标已基本对准」时启用 |

**来源**：
- 「target gravity / 磁性把准心拉向附近目标」的概念在学术会议论文中被明确描述：[BISEC 2025 proceedings PDF](https://bisec.metropolitan.ac.rs/wp-content/uploads/2026/04/Proceedings-BISEC2025.pdf)（含 *"This technique creates a magnetic effect that draws the player's crosshair toward targets that are close by"*）
- Game Developer 的公平自动瞄准设计文章：[How to create a 'fair' auto-aiming system in a robot shooter](https://www.gamedeveloper.com/design/how-to-create-a-fair-auto-aiming-system-in-a-robot-shooter-) ⚠️ **URL 与标题已确认，但页面 403 未能读取正文**
- Godot 实现思路（⚠️ **AI 生成仓库，仅作思路，不可当权威**）：[soft_lock_aim_assist.gd](https://github.com/thedivergentai/GD-Agentic-Skills/blob/main/skills/godot-genre-shooter/scripts/soft_lock_aim_assist.gd)

**我的落地建议（工程结论）**：
1. **优先做「子弹磁性」**（射线加粗），因为它对玩家的**输入映射零干扰**，且你们是 hitscan，实现成本极低。
2. **次选「磁性减速」**，绝不默认做「角度吸附」。
3. **辅助强度必须可被超越**（skill-respecting）：玩家把摇杆**推到最大幅度并主动转向时，辅助立即减弱/关闭** —— 否则精准玩家会觉得被抢。
4. **只在目标处于屏幕内 + 有视线（raycast 无遮挡）时生效**，避免「隔着墙吸附」。
5. **对「搜打撤」的额外考虑**：辅助瞄准**绝不能自动锁定你不想打的中立 NPC/同伴**（搜打撤里有大量非敌意单位），必须做**目标筛选（敌对阵营 + 距离 + 是否在射界内）**。

> **必须人工调参**：容差角度、衰减曲线、磁性强度、生效距离。这类参数是**手感的核心**，只能试玩定。

### D2. 自动开火 vs 手动开火

| 维度 | 自动开火（进入射界即射） | 手动开火（独立开火键 / 第二摇杆 / 点按） |
|---|---|---|
| 操作负担 | 低（手机上友好） | 高 |
| 战术表达 | 弱 —— 你**无法选择「现在不开枪」** | 强 —— 开火时机本身是资源决策 |
| 对搜打撤的适配 | 差：会**暴露位置、浪费弹药、误伤中立单位**，破坏潜行/取舍 | 好：搜打撤的核心乐趣就是**风险决策** |
| 对硬核目标人群 | 通常被反感 | 被期待 |

**结论（设计判断，非查证）**：
> 你们的核心循环是「**搜 → 打 → 撤**」，**开火时机的决策权比操作省力更重要**。
> **推荐：默认手动开火 + 强 aim assist（子弹磁性）**；提供「辅助开火」作为**可选辅助功能**（无障碍/新手向），而不是默认。
> 折中方案：**近身自动、远程手动**（很多手游射击的做法），可作为第三条路。

### D3. 触屏瞄准的延迟敏感度与优化

**引擎侧能做的（全部官方，见 B6-4）**：关 V-Sync / `Swapchain Image Count = 2`（4.3+）/ 提高 physics ticks / `Input.set_use_accumulated_input(false)` / 独占全屏。

**引擎侧做不到的**：**触摸屏本身的采样 → 系统输入栈 → 合成 的延迟是系统级的，引擎改不了。**
👉 官方要求：**要报告输入延迟问题，必须用高速摄像机拍摄「屏幕 + 手指」同框**，数出输入到画面响应之间的帧数。
来源：[Fixing jitter, stutter and input lag → Reporting](https://docs.godotengine.org/en/stable/tutorials/rendering/jitter_stutter.html)

**设计层面的降延迟手段（工程经验建议）**：
1. **`touch down` 即预瞄 / 即开火**，不要等 `release`。
2. **瞄准摇杆用固定锚点（STATIC），不要用动态跟随（DYNAMIC）** —— 动态摇杆每次触摸都要先「找零位」，等于额外延迟。Virtual Joystick DX 提供 `STATIC / DYNAMIC / FOLLOWING` 三种模式可对比实测。
3. **对瞄准输入做一阶低通 + 一帧前瞻（lead）** 来掩盖抖动与延迟（但要小心：前瞻会带来过冲）。
4. **准心与枪口解耦**：枪口跟随瞄准角但带 1 帧平滑，避免触屏抖动直接传到枪贴图上。
5. **在真机验证 [issue #120322](https://github.com/godotengine/godot/issues/120322)**（`InputEventScreenDrag` 在 Android 上触发间隔过长）—— 这**直接决定你的瞄准摇杆是否可用**。

---

## 结论与推荐

### 1. 架构（支撑你们已有的「模拟层 / 表现层分离 + headless 单测」）

```
Simulation (纯 GDScript, 不继承 Node, 可在 headless 下单测)
├── WeaponData (Resource)          ← JSON 只作为导出/工具格式, 运行时统一转 Resource
├── BallisticsMath (静态纯函数)     ← ray-circle / ray-AABB / spread / penetration
│      ↑ 生产实现: PhysicsDirectSpaceState2D.intersect_ray
│      ↑ 测试实现: 纯几何 (不需要场景树, 单测快 100 倍)
├── DamageResolver (部位/倍率/穿透衰减)
└── RecoilState / SpreadState (纯数值状态机)

Presentation (Node2D 树)
├── TracerPool / MuzzleFlashPool / ShellPool / BloodPool / DamageNumberPool
├── JuiceBus (hitstop / camera trauma / sfx / flash) ← 订阅 Simulation 事件
└── AimAssistPresenter (触屏辅助, 只影响输入 → 不影响判定权威)
```

**关键**：把**弹道数学写成不碰 `Node` 的纯函数**，命中查询抽成接口。这样 headless 单测可以覆盖「扩散/穿透/伤害」全部逻辑，而 `PhysicsDirectSpaceState2D` 只在集成测试里出现。

### 2. 推荐的最小可行战斗核心（按实现顺序）

1. **hitscan 射线 + 扩散**（先做这个，其他都是锦上添花）
2. **命中分级**（轻/重/暴击/杀）→ 每级走不同量级的 **hitstop + 闪白 + 相机 trauma + 音效**
3. **对象池**（粒子 / 伤害数字 / tracer / 弹壳）
4. **后坐力**（视觉 kick 与准心偏移**分成两条独立通道**）
5. **可选**：穿透、跳弹、慢速可见子弹（仅特殊武器）

### 3. 直接可用的现成件（最低风险）

- **Phantom Camera**（MIT, 4.x）— 相机框架
- **Saltmire Juice**（MIT, **4.6+**）— trauma shake / hitstop / flash / 池化伤害数字（**若你们锁 4.4/4.5 需要改造或只抄代码**）
- **Virtual Joystick DX**（MIT, **4.6+**）— 触屏双摇杆
- 官方 **`2d/bullet_shower` demo** — 万弹级性能参考

### 4. 必须人工反复试玩调参的部分（**直说**）

**以下没有任何文档、没有 AI 能替你定，只能真人试玩**：

| 参数 | 为什么无法自动化 |
|---|---|
| hitstop 时长（20/40/60/80 ms） | 依赖你的整体节奏与音效，长一点就「卡」 |
| 相机震动 trauma 幅度与衰减 `_decay` / `_max_offset` | 像素游戏还要处理**整像素量化**，纯数值算不出来 |
| 后坐力曲线（kick 幅度 / 恢复速率 / pattern） | 这是「武器性格」，是美术级决策 |
| spread 数值与增长/回落速率 | 直接决定「打不打得中」，与镜头、敌人尺寸耦合 |
| **aim assist 容差角度 / 磁性强度** | 手感核心，且极主观 |
| 摇杆死区、灵敏度曲线 | 与具体硬件屏幕尺寸相关 |

**可执行的调参流程（强烈建议立刻搭）**：
1. 做一个**运行时调试面板**：所有手感参数都是 `@export`，用 Godot 编辑器的 **Remote Inspector** 运行中实时改，或绑热键。
2. **一次只改一个参数**，录屏。
3. **盲测**：找 **≥3 个不同水平**的测试者做 A/B 排序（不要问「哪个好」，问「哪个更重 / 更准 / 更舒服」）。
4. 用 **Profiler 看 frame time 而不是 FPS**（FPS 平均值会隐藏你真正在意的尖峰）。
5. 真机测延迟必须用**高速摄像机拍屏幕 + 手指**。

### 5. 落地前的复核清单（诚实交代不确定项）

- [ ] **所有 GitHub 仓库的 LICENSE 亲自打开复核**（本沙箱 GitHub 被 DNS 拦截，我只能读到 Godot 官方登记字段/搜索标题，属二手）
- [ ] 确认 **Jhon-Crow/godot-topdown-MVP**、**Lakamfo/PenetrationSystem**、**object-pooling-godot-4**、**Virtual Joystick (1787)**、**Trauma 2D Camera Shake** 的授权与 Godot 版本
- [ ] **排除** Rokojori Action Library（自定义 "Public Indie License"，与 GPL-3.0 开源项目不兼容风险）
- [ ] 确认 **EZ Camera Shake 是否存在可信的 Godot 4 移植**（我未找到 → 待确认）
- [ ] 确认 **[godot#120322](https://github.com/godotengine/godot/issues/120322)** 是否已修复（直接影响触屏瞄准）
- [ ] 确认 **"The Art of Screenshake" 的 YouTube 链接**（我无法直连 YouTube 验证 ID）
