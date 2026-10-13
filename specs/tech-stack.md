# 技术选型（Technology Stack）

> 本文件汇总**已查证的**技术方案与外部资源，是实现的依据。
> 关联：`feasibility.md`（范围内决策 D-xx）、`art-pipeline.md`（美术规范 A-xx）、`third-party.md`（授权登记）。
> **本文件用 `T-xx` 编号记录技术决策。**

---

## 0. 调研状态

| # | 领域 | 状态 | 原始报告 | 本章节 |
|---|---|---|---|---|
| 1 | **移动端与触屏** | ✅ 已归档 | `godot4-mobile-research.md` | §2 |
| 2 | **像素美术素材** | ✅ 已归档 | `research/pixel-asset-research.md` | §3 |
| 3 | **随机地图生成** | ✅ 已归档 | `procedural-mapgen-research.md` | §5 |
| 4 | **射击战斗与手感** | ✅ 已归档 | `godot4-2d-shooter-feel-research.md` | §7 |
| 5 | **背包 / 数据 / 存档 / 测试 / 本地化** | ✅ 已提炼 | ⚠️ **原始报告未落盘**（内容已完整提炼至 §6） | §6 |
| 6 | **寻路与 AI** | ✅ 已归档 | `godot4-pathfinding-ai-research.md` | §4 |

> ✅ **六路调研全部完成。** 仅第 5 路的原始报告未写入文件，其结论已完整提炼进 §6。

> ⚠️ **调研环境的已知限制**（影响了部分结论的可信度，已在各节逐条标注）：
>
> | 限制 | 影响 |
> |---|---|
> | **itch.io 完全无法访问**（DNS 解析失败） | **像素素材最大聚集地完全未覆盖**。§3 的美术结论不包含任何 itch.io 包 |
> | **github.com / raw.githubusercontent.com DNS 被拦** | 部分仓库 LICENSE 只能读到二手登记信息，**落地前必须自行复核**。部分调研改走 jsDelivr / ungh.cc 镜像抓到了真实文件 |
> | Godot 官方文档站（Sphinx）导航树过长 | `web_fetch` 抓正文会被截断；部分结论改从 `_sources/*.rst.txt` 与 `doc/classes/*.xml` 源文件取得 |
> | Google Play 政策页抓取失败 | targetSdk 要求未核实，**这是唯一会导致拒审的合规项** |
> | youtube.com / archive.org / gamedeveloper.com / zenodo.org | 演讲与论文「URL 与标题可确认，正文未读」 |

> 📁 **报告文件位置不统一**：§0 表格里 1/3/4/6 在**工作区根目录**，2 在 `research/`。
> 后续如整理，统一移到 `research/` 更清晰。

> ⚠️ **调研环境的已知限制**（影响了部分结论的可信度，已在各节逐条标注）：
>
> | 限制 | 影响 |
> |---|---|
> | **itch.io 完全无法访问**（DNS 解析失败） | **像素素材最大聚集地完全未覆盖**。§3 的美术结论不包含任何 itch.io 包 |
> | **github.com / raw.githubusercontent.com DNS 被拦** | 部分仓库 LICENSE 只能读到二手登记信息，**落地前必须自行复核** |
> | Godot 官方文档站（Sphinx）导航树过长 | `web_fetch` 抓正文会被截断，部分设置项标为「待确认」而非编造 |
> | Google Play 政策页抓取失败 | targetSdk 要求未核实，**这是唯一会导致拒审的合规项** |
> | youtube.com / archive.org / gamedeveloper.com | 演讲与文章「URL 与标题可确认，正文未读」 |

---

## 1. 引擎与渲染

| ID | 决策 | 依据 |
|---|---|---|
| **T-01** | **引擎版本 = Godot 4.7.x 稳定版**（当前 **4.7.2**，2026-08-18 发布） | ⚠️ **本条已更正**：早先版本锁定 4.6，理由是"4.7 仅 dev"。实测 [官方 versions.json](https://godotengine.org/versions.json) 显示 **4.7.2 已稳定**（4.8 才在 dev）。三处独立佐证：官方版本清单、LimboAI v1.8.1 对应 4.7.2、GUT 9.7.1 对应 4.7 |
| **T-01b** | **因 T-01 更正，必须重新评估"原生 `VirtualJoystick` 是否取代第三方插件"** | 该节点自 **4.7 起内置**（三模式 `FIXED` / `DYNAMIC` / `FOLLOWING`，`FOLLOWING` 是双摇杆射击首选）。若 4.7.2 稳定版确认可用，则 **T-10 降级为备选** |
| **T-02** | **渲染器 = Compatibility（`gl_compatibility`）**，用项目设置按平台覆盖 | 纯 2D 像素游戏，兼容设备最广、更省电、驱动问题更少 |
| **T-03** | ⚠️ **粒子一律使用 `CPUParticles2D`**（VFX 的基准实现） | ⚠️ **本条理由已更正**（结论不变）。见下方 T-03 详解 |

```ini
; project.godot —— 桌面开发用 Forward+，移动导出自动切 Compatibility
[rendering]
renderer/rendering_method = "forward_plus"
renderer/rendering_method.mobile = "gl_compatibility"
```

> **T-03 的例外**：若确认必须用 GPU 粒子，则渲染器改 Mobile（Vulkan），覆盖 2018 年后设备，但老机驱动风险上升。
> **默认走 T-03，不选 Mobile。**

### 1.1 ⚠️ T-03 详解：这条的理由已被实测更正

**旧说法（错的）**：「`GPUParticles2D` 在 Compatibility 下必定静默失效」。

**实测与查证后的正确说法**：**桌面能用，安卓 OpenGL ES 上不可靠。**

| 证据 | 内容 |
|---|---|
| **本机实测**（Godot 4.7.2 / `gl_compatibility` / OpenGL 3.3 / RTX 4070 SUPER） | `GPUParticles2D` **正常渲染**（204 亮像素 vs CPU 的 249）——**没有静默失效** |
| [saltmire 实测文章](https://dev.to/saltmire/gpuparticles2d-vs-cpuparticles2d-in-godot-4-which-and-when-3e1f) | 「GPU particles only work on the Compatibility renderer ... **since Godot 4.2**」 —— 4.2 起 Compatibility 后端**加了 GPU 粒子路径** |
| [bugnet 分析](https://bugnet.io/blog/fix-godot-gpu-particles-not-rendering-mobile) | Compatibility（**OpenGL ES 3.0**）不支持 **compute shader** → 移动端 GPU 粒子**静默不渲染、无报错** |
| [godot#94915](https://github.com/godotengine/godot/issues/94915) | `gl_compatibility` 下 `GPUParticles2D` 的可见性与崩溃问题 |

**⇒ 为什么结论仍然是「一律用 `CPUParticles2D`」**：

1. **桌面验证通过 ≠ 设备上没问题。** 本机是 OpenGL 3.3 桌面驱动；安卓走 OpenGL ES，
   驱动与能力集不同。**桌面测试会给人虚假的安全感。**
2. `CPUParticles2D` **在所有渲染器/平台上行为一致**，没有第一帧 shader 编译卡顿，
   也不需要维护 `visibility_rect`。
3. 我们的 VFX 是**大量小而短的爆发**（枪口火光/弹壳/血花），
   **正是 CPU 粒子的适用场景**——不是需要 turbulence/collision/sub-emitter 的大场面。
4. 若将来确实需要大场面（雨雪、雾团），再**局部**改用 `GPUParticles2D` 并在真机复验。

**验证工具**：`test/test_particles_compat.gd` —— 像素级 A/B，可自动化：

```bash
godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
      --script res://test/test_particles_compat.gd
```

> 脚本会如实报告三种结果，**不会为了迎合假设而假装通过**：
> ① CPU 可见 + GPU 不可见 → 证实静默失效
> ② **两者都可见 → 报告「本机未失效」，并提示仍需真机复验**（本机就是这种）
> ③ CPU 也不可见 → 报告统计方式或渲染器有问题，退出码 1

**关于 GDScript 性能**：不要预optimize。只有 Profiler 证明瓶颈在脚本执行时才考虑 C# / GDExtension——
两者都要为每个 ABI 交叉编译 `.so` 并打包，显著增加构建复杂度，**在安卓上是最后手段**。
先做缓存 / 对象池 / 降频通常能解决 80% 问题。

---

## 2. 移动端与触屏

### 2.1 虚拟摇杆

| ID | 决策 | 依据 |
|---|---|---|
| **T-10** | ⚠️ **优先级已调整**：**先用 4.7 内置的原生 `VirtualJoystick`**（见 T-01b）；仅在原生不满足时退回 [Virtual Joystick DX](https://www.godotengine.org/asset-library/asset/5256)（MIT，4.6+）。右摇杆用 `FOLLOWING` / `DYNAMIC` | 4.7 起引擎内置摇杆节点，含 STATIC / DYNAMIC / FOLLOWING 三模式。**能用原生就不引第三方**，少一个依赖与版本绑定 |
| **T-11** | **按钮/摇杆底一律用 `Control` 自绘，禁用 `TouchScreenButton`** | `TouchScreenButton` 继承 `Node2D`，**不支持 anchors**，无法自适应；且只能触发 `action`，**无模拟量** |
| **T-12** | 多点触控状态用 **`Dictionary[int, Vector2]`（键 = finger index）** | 用单一 `touch_position` 存"当前触点"是双摇杆互相干扰的根因 |

**备选摇杆**（均 MIT，若 T-10 有问题）：
[Virtual Joystick CF](https://godotengine.org/asset-library/asset/4891)（4.5+）·
[Virtual Joystick Plus](https://godotengine.org/asset-library/asset/4458)（4.5+）·
[MarcoFazioRandom](https://godotengine.org/asset-library/asset/1787)（4.2，**【需改造】**，2 年未更新）

### 2.2 多点触控要点与常见 bug

| 常见 bug | 根因 | 修法 |
|---|---|---|
| 双摇杆互相干扰 | 用单一 `touch_position` 存"当前触点" | 按 `index`（finger id）分别存状态 |
| 松开左手导致右手归零 | 抬起事件无脑清空 | `pressed == false` 时**只清该 index** |
| 摇杆跳变/抖动 | 屏幕坐标与控件坐标混用 | 统一坐标系，显式做 canvas/stretch 变换的逆变换 |
| 刘海/圆角区点不到 | UI 贴边 | `DisplayServer.get_display_safe_area()` 留安全边距 |
| 触点被别的 Control 吃掉 | `mouse_filter` 默认值 | 摇杆容器 `MOUSE_FILTER_STOP`，全屏背景 `IGNORE`/`PASS` |

**浮动摇杆实现要点**：① 动态模式下原点 = 按下瞬间的触摸点，`Control` 矩形只当"激活区域"；
② 输出归一化 `(pos - origin).limit_length(radius) / radius`；③ **死区只配一处**（放 InputMap，不在节点上重复配）；
④ 浮动摇杆按下瞬间才显示，避免幽灵摇杆糊屏。

### 2.3 辅助瞄准（aim assist）

| ID | 决策 | 依据 |
|---|---|---|
| **T-13** | **自研 aim assist** —— ⚠️ **具体机制以 §7.7（T-56）为准：优先「子弹磁性」（射线加粗），而非角度吸附** | **Godot 官方不提供 aim assist**，引擎无此能力 |

1. **磁吸**：摇杆方向开 ±X° 锥形，锥内最近敌人把方向"拉"过去，权重按夹角衰减
2. **减速**：准星接近目标角度时降低转动灵敏度（比硬吸附体感自然）
3. **子弹微偏转**：出膛/飞行中向最近敌人轻微偏转——**唯一能让手感"必中"却不让玩家觉得被抢控制权的手段**

**必须加的约束**：只在"玩家正在推瞄准摇杆"时生效、回中立即失效；FOV 门限**按屏幕尺寸换算**（手机视口小，固定 90° 会过强）；
加**视线/遮挡检查**（`RayCast2D`）；加"主动反向拨杆即脱锁"。

**起点参考**（含可用的距离门限 + 角度门限 + `lerp` 实现）：
[Godot 官方论坛 aim assist 实现](https://forum.godotengine.org/t/how-to-create-a-aim-assist-auto-aim-in-godot-4-4/121083)

### 2.4 像素完美渲染

| ID | 决策 | 依据 |
|---|---|---|
| **T-14** | **相机用 [PixelPerfectSmoother](https://godotengine.org/asset-library/asset/4846)（MIT）**，或自写高精度平滑 | `Camera2D.position_smoothing` **先插值后取整，每帧丢弃亚像素余量** → 表现退化为整数跳变（相机 snap + 精灵边缘爬行）。官方 issue [#7758](https://github.com/godotengine/godot-docs/issues/7758) / [#93048](https://github.com/godotengine/godot/issues/93048) / [#95571](https://github.com/godotengine/godot/issues/95571) |
| **T-15** | `stretch/mode = canvas_items`，`stretch/aspect = keep`，`stretch/scale_mode = **integer**` | `viewport` 会把 UI 也按低分辨率光栅化；`fractional` 必然破坏像素完美 |
| **T-16** | 纹理过滤 = **项目级 Nearest**（`rendering/textures/canvas_textures/default_texture_filter`） | 节点 > 纹理导入 > 项目默认，三层都要一致 |

**已知行为异常必须实测**：`aspect=expand` + `scale_mode=integer` 有官方 issue
[#92055](https://github.com/godotengine/godot/issues/92055)。**上线前实机验证；异常则退回 T-15 的 `keep`。**

> **最易忽略**：抖动常常不是相机问题，而是**玩家/相机在不同 `_process` 频率更新**。
> 统一"物理更新 + 渲染插值"或"全部 `_process`"比调平滑参数更有效。
>
> **不要用**每帧 `global_position.round()` 的土办法——**会加剧**低速抖动（直接丢光亚像素余量）。

**宽高比策略取舍**：

| 策略 | 结论 |
|---|---|
| 整数缩放 + 黑边（`keep`+`integer`） | ✅ **采纳**（T-15）。绝对像素完美 |
| 整数缩放 + `expand` | ⚠️ 无黑边但踩 issue #92055，需实测 |
| **动态视口** | ❌ **慎用**——不同设备可视范围不同 = **直接改变玩法平衡**（搜打撤里视野=战术优势） |
| 分数缩放 | ❌ 必然破坏像素完美 |

### 2.5 移动端性能

| ID | 决策 |
|---|---|
| **T-17** | `Engine.max_fps = 60`（低端档 30）。**不锁帧会跑满刷新率 → 发热降频 → 反而掉帧** |
| **T-18** | **必做四件**：图集（`AtlasTexture`）· 对象池（子弹/弹壳/伤害数字）· `@onready` 缓存引用 · 屏外可见性裁剪 |
| **T-19** | 比较用 `distance_squared_to()`，避免每帧 `get_node()`，避免字符串比较（用 `StringName`/enum） |

**关键认知**：手机 CPU 在"派发大量小 draw call"上远弱于桌面，
**2D 瓶颈几乎总在 CPU / draw call，而非填充率**。因此图集是首要优化手段。

监控 draw call：
```gdscript
RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
```

⚠️ **两个图集陷阱**：
1. **图集内所有图必须有相同的压缩/导入设置**，混用会让 Godot 拆批，反而抵消收益
2. **启用 ETC2/ASTC 后必须重新导入纹理**（删 `.godot/imported` 或 Export 对话框 Fix Imports），否则等于没开

### 2.6 ⚠️ 待决策：ETC2/ASTC 压缩取舍

**ETC2/ASTC 是有损压缩，会糊掉像素边缘。** 像素项目常选择不压缩（PNG 直出）保锐利，代价是包体与显存。

| 方案 | 优 | 劣 |
|---|---|---|
| 开 ETC2/ASTC | 包体小、显存省、低端机更稳 | **像素边缘变糊**，风格受损 |
| 不开（PNG 直出） | 像素绝对锐利 | 包体大、显存占用高、低端机 OOM 风险 |

**建议**：先不开压缩做原型（保风格正确），到 M2 再按真机显存实测决定。**这条必须在 M2 前定案。**

### 2.7 安卓导出工程

| ID | 决策 |
|---|---|
| **T-20** | 工具链：**JDK 17**（Temurin/Adoptium；**JDK 21 常致 Gradle 失败**）+ Android SDK（Android Studio 或 command-line tools）|
| **T-21** | 导出预设必须点 **Install Android Build Template**（生成 `android/build` Gradle 工程）——**AAB 必需** |
| **T-22** | 只保留 **arm64-v8a**（满足 Play 64 位要求）；`armeabi-v7a` 仅在明确要覆盖极老机型时勾选 |

**最大的坑（按实际影响排序）**：

1. **编辑器 / 导出模板 / JDK 三者版本不一致** —— 绝大多数首次导出失败的根因（预设红点、Gradle 崩、`App not installed`）
2. 改 SDK/NDK 路径后 **Gradle 缓存会让旧配置继续生效**
3. 包名必须**反向域名全小写**，含空格/连字符/大写必崩
4. **Android SDK 35 (API 35) 与旧版 Godot 的 Gradle/AGP 不兼容** → 社区补丁版 [shipth-is/godot-android-sdk-upgrade](https://github.com/shipth-is/godot-android-sdk-upgrade)（**【需改造】**）
5. **release keystore 丢失 = 无法再更新同一应用**。**必须立刻备份**（存两处不同介质）
6. 换签名后旧包覆盖安装失败，需先卸载

**排查手段**：预设**红点悬停会直接告诉你缺哪个**；导出后**黑屏**通常是渲染器选错；
`adb logcat` 是最底层可靠的调试通道；一键部署（编辑器右上角 Android 图标）自动 build+install+launch+attach。

---

## 3. 美术素材来源

### 3.1 核心结论

> **免费/CC0 世界里的「俯视现代军事像素素材」基本是空白。**

**结构性原因**：军事题材商业价值高，作者倾向放 CraftPix / GameDev Market 卖钱；
CC0 生态的主流兴趣是奇幻 RPG / 平台跳跃 / 可爱风。

**这意味着：这块不能靠"找包"解决，必须按「自研美术」而非「找现成素材」排期。这是本项目最大的美术风险。**

### 3.2 采纳的素材来源

| ID | 来源 | 授权 | 用途 | 是否入公开仓库 |
|---|---|---|---|---|
| **T-23** | [Kenney **Desert Shooter Pack**](https://kenney.nl/assets/desert-shooter-pack)（**16×16** 像素，2025，shooter/roguelike/ui） | **CC0** | **起步基底**：tile、角色、枪械、UI 通用件 | ✅ 可入 |
| **T-24** | [OGA **Futuristic Guns, Weapons and Items**（knekko）](https://opengameart.org/content/futuristic-guns-weapons-and-items) | **CC0** | **枪械/物品图标（32×32，正合我们的图标规格）** | ✅ 可入 |
| **T-25** | [OGA **Post-apocalyptic 16x16 tileset**（CobraLad）](https://opengameart.org/content/post-apocalyptic-16x16-tileset-update1) | **CC-BY-SA 3.0** | 废土风格地表 | ⚠️ 可入，**有传染性** |
| **T-26** | [CraftPix **TDS Modern: Pixel Game Kit**](https://craftpix.net/product/tds-modern-pixel-game-kit/) | 自定义，**禁再分发源文件** | 现代军事全套（士兵/载具/建筑/GUI/爆炸/枪械） | 🚫 **不得入库**，见 §3.4 |
| **T-27** | Kenney 其余像素包（[`tag:pixel`](https://kenney.nl/assets/tag:pixel)）+ [Input Prompts Pixel](https://kenney.nl/assets/tag:pixel) | **CC0** | UI、字体、**安卓触屏按钮图标**、环境打底 | ✅ 可入 |

### 3.3 Kenney 的正确定位

| 用途 | 结论 |
|---|---|
| **作为美术主基底** | ❌ **不行**。像素包占比极小，题材偏奇幻/平台/可爱风，**没有任何现代军事题材的完整像素包**；调色板平淡、轻描边，容易被认出 |
| **作为 UI / 音频 / 原型占位 / 环境打底** | ✅ **可以**。CC0 是公开开源仓库**唯一无痛授权**（可 commit、免署名、无再分发限制、无 NC 锁死），且现成可用 |

> **一句话**：Kenney 当「UI / 音频 / 原型占位 / 环境打底」的来源，**不当「主视觉基底」**。

### 3.4 ⚠️ 付费素材与公开仓库的冲突（D-13 的落地）

CraftPix 等付费素材的条款**明确禁止再分发源文件**。而本项目是**公开开源仓库**——
**把素材 commit 进 GitHub 就等于"再分发源文件"，直接违约。**

**合规方案**：

```
仓库内（公开）                     仓库外（本地）
├── code/          ← MIT（原 GPL-3.0，2026-10-13 改）  └── assets_paid/   ← 各自购买后放入
├── assets/        ← 仅 CC0 / CC-BY      （.gitignore 排除）
├── fetch_assets.sh  ← 获取脚本
└── README.md      ← 说明需自备付费素材
```

**要点**：代码开源、素材可以不开源。付费素材由使用者**自行购买**后放入本地目录，`.gitignore` 排除。

### 3.5 风格统一难点（6 项）

| 难点 | 修法 |
|---|---|
| **调色板**（Kenney 明亮 vs CraftPix 军绿低饱和 vs OGA 废土脏暗） | 定统一受限调色板（32–48 色战术色系）+ **索引重映射**——**性价比最高的一步** |
| **描边**不统一 | 固定一种规则逐素材补删 |
| **光照方向与阴影**不一致 | 先固定光源方向（建议左上），统一所有阴影 |
| **像素密度（最致命）** | 16×16 与 32×32 混用**只能整数倍 nearest 缩放**；非整数缩放会破坏像素网格导致比例失真 → **项目初期敲定：16×16 tile + 32×32 角色** |
| **抗锯齿/半透明** | **无解，只能弃用或重画**（这也是矢量包不能改造成像素画的原因） |
| **动画帧数与头身比** | 4/6/8 帧、chibi vs 1:2.5 需**早期锁定**，改动成本极高 |

### 3.6 ⚠️ 音效

| 发现 | 说明 |
|---|---|
| **Freesound 是逐条授权** | 同一个站里混有 CC0 / CC-BY / **CC-BY-NC** / 遗留 Sampling+。**CC-BY-NC 会永久锁死商业化路径**（本项目非商用，可接受，但要知道） |
| **Kenney 没有枪声包** | Kenney 音频分类只有 Casino / Sci-fi / Interface / Impact / Voiceover / Music Jingles / RPG / Digital / UI。**枪声必须另找来源** |
| **枪声获取未解决** | 本次**未找到并核实任何高质量免费枪声包**。需在能访问 itch.io / Sonniss 的环境补做 |

**实务提醒**：top-down 射击需要的是**短促、有冲击力、game-ready** 的枪声，不是长尾写实录音。
Freesound 的 raw field recording 直接丢进游戏会糊、拖尾长、动态过大，需要
**裁尾 + 分层（低频 thump / 高频 crack / 尾音）+ 随机 pitch/volume**。

---

## 4. 寻路与 AI

### 4.1 核心选型：格子系骨干（T-80）

> **关键判断**：既然是**随机生成 + 可破坏墙体**，就走**格子系（AStarGrid2D / 流场）**，
> **不要走导航网格系**——导航网格在"地形频繁变化"这个维度上是**结构性劣势**。

| 需求 | 选型 |
|---|---|
| 单目标精确寻路 | **`AStarGrid2D`** |
| **20–30 敌人追同一目标** | **自研流场（Flow Field）** |
| 只需到预定义路点 | `AStar2D` / `NavigationLink2D` |
| 开阔静态大地图 | `NavigationServer2D` |

### 4.2 流场必须自研（T-81）

**权威否定**：Godot Asset Library 检索 `filter=flow+field` 实测返回 **"0 items total"**
→ **Godot 4 生态没有任何现成可装的流场插件。**

**起点**：[Griiimon/Manymies](https://github.com/Griiimon/Manymies) — **MIT**、纯 GDScript、**Godot 4.3**、82 stars、2025-06
- 含 `flowfield.gd`（BFS 积分场）+ `directional_flowfield.gd` + 三种分离方案
- README 自称 "3 solutions with 1000+ enemies at 60fps"
- ✅ **Android 可用**（纯 GDScript）

**⚠️ 必须修掉它的缺陷，不要照抄**：
- `flowfield.gd` 在 while 循环里用 `active_points.remove_at(0)` —— GDScript 里这是 **O(n) 头删**，
  **整个 BFS 退化成 O(n²)**
- **改用下标游标或 `PackedInt32Array` 环形队列**
- 它 40×25 = 1000 格跑得动，**地图更大就先炸**

**自研三层结构**：

```
Cost Field        （墙不可通行 / 沼泽高代价）
   ↓
Integration Field （从目标 BFS / Dijkstra，8 方向对角代价 √2）
   ↓
Direction Field   （每格指向 integration 最小的邻居）
```

- 同一目标的所有敌人**共用一份**
- **只在目标换格时重建**（Manymies 的优化思路）
- 多目标 → 多份流场
- 流场只给方向不给路径，**需配合分离（separation）**

### 4.3 ❌ 明确不可用的方案（避免踩坑）

| 项目 | 为什么不行 |
|---|---|
| 🚫 [**gdmapf**](https://github.com/nathanfranke-archive/gdmapf) | **仅 3D**（`register_types.cpp` 只注册 3D 类）；`.gdextension` **无 Android 库**；**已 archive 归档**；README 自述**存在对向智能体卡死的重大 bug** → **完全不可用** |
| 🚫 [kvbc/godot-FlowFieldPathfinding](https://github.com/kvbc/godot-FlowFieldPathfinding) | **Godot 3**（`#include "core/reference.h"`），且是**引擎模块**（要重编译整个 Godot） |
| 🚫 [arnemileswinter/godot-tilemap-flowfields](https://github.com/arnemileswinter/godot-tilemap-flowfields) | **Godot 3 GDNative**，且只有 Linux/Windows 库、**无 Android** |

> ⚠️ **关于 MAPF**：Godot 4 生态**没有**可用且兼容 Android 的 MAPF 解算器；
> 真正的 MAPF（CBS/ECBS）在实时安卓游戏里也不实用（NP-hard、重规划贵）。
> **「流场 + 局部软分离 + 格子占位代价惩罚 + 物理滑移兜底」已经够用。**

### 4.4 AStarGrid2D 的四个坑（官方文档原文核实）

1. **`update()` 会清空所有点数据**："All point data (solidity and weight scale) will be cleared."
   → 只有 `set_point_solid()` / `fill_solid_region()` / `set_point_weight_scale()` **不需要** `update()`
2. 🚨 **路径查询不是线程安全的**：`get_id_path()` / `get_point_path()`
   "is not thread-safe. If called from a Thread, it will return an empty array and will print an error message."
   → **不能靠多线程绕过每帧 A* 成本**
3. **`jumping_enabled = true`（JPS）会忽略 weight_scale**：
   "toggling it on disables the consideration of weight scaling in pathfinding."
4. **必须用 `DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES` 或 `AT_LEAST_ONE_WALKABLE`**
   （`ALWAYS` 会无视实心邻居，**从障碍对角直接穿过去**）

> ✅ **可破坏墙体的最佳方案**：`set_point_solid()` **调用后无需 `update()`**
> → 打掉墙 = 翻转几个格子标志，**立即生效**。

### 4.5 导航网格的四个限制（若使用 NavigationServer2D）

| 事实 | 原文 |
|---|---|
| **`NavigationObstacle2D` 不影响寻路** | "This Node does NOT affect the pathfinding of agents. You need to change the navigation meshes for that instead." |
| **避让开销显著** | `avoidance_enabled`："Avoidance processing with many registered agents has a significant performance cost" → **别给 30 个敌人无脑开 RVO** |
| **`radius` 不影响寻路** | "To change an actor's pathfinding radius bake NavigationMesh resources with a different agent_radius" |
| **Region 启停不会自动更新路径** | "Existing paths will not be automatically updated when a region gets enabled / disabled." |
| ⚠️ **4.4 文档中标记 `experimental`** | `NavigationRegion2D` / `NavigationAgent2D` / `NavigationObstacle2D`。**4.5/4.6/4.7 是否摘掉 → 待确认** |

### 4.6 AI 决策层选型（T-82）

| 需求 | 选型 | 授权 | Godot |
|---|---|---|---|
| **行为树（纯 GDScript，Android 零负担）** | [**Beehave**](https://github.com/bitbrain/beehave) | **MIT** | **4.5**，活跃（2026-09） |
| **行为树（功能最强：黑板 + HSM + 调试器）** | [**LimboAI**](https://github.com/limbonaut/limboai) | **MIT** | ⚠️ **v1.8.1 → 4.7.2**（**版本强绑定**）。release 里确有预编译 **`android-lib`** |
| **状态机** | [**Godot State Charts**](https://github.com/derkork/godot-statecharts) | **MIT** | 1619 stars，2026-06 更新。支持层级/并行状态，**避免状态爆炸** |
| **GOAP** | [pixelrogueart/goap-godot-4](https://github.com/pixelrogueart/goap-godot-4) | MIT（Asset 标注，仓库 LICENSE 待核） | Pure GDScript / 零依赖，2026-08 |
| **效用 AI** | ⛔ **自己写** | — | 现成两个都弱（一个 2024 停更、一个仅 24 stars 且是原生扩展） |

> **Beehave vs LimboAI 的抉择**：
> 要**黑板 / HSM / 调试器**，且**能接受引擎版本绑定** → **LimboAI**
> 要**长期升级自由度**，且坚持**纯 GDScript** → **Beehave**
>
> ⚠️ LimboAI **v1.7.0 明确声明 "It's not compatible with previous Godot versions"**
> → **必须先在项目中冻结 Godot 版本，再选对应发行包**。
> 这是**工程风险**（升级引擎必须同步换包），不是授权风险。

**效用 AI 为什么自己写**：本质是"打分取最大"，**几十行 GDScript**，
行为 / 考量项 / 响应曲线**全放 JSON**，完全可 headless 单测——比引依赖划算，也更符合 D-05。

### 4.7 🚨 小队协同 AI：**没有现成库，必须自研**（T-83）

> **诚实结论**：Godot 生态里**没有**成熟的、开源的"战斗小队协同 AI"库。
> 行为树 / 黑板提供的是**承载结构**，**不是战术本身**。这类逻辑在 Godot 社区普遍自研。
> —— 这印证了 `feasibility.md` 把 AI 群体协同列为**最高风险项**的判断。

**可复用的底座**：**LimboAI 的 Blackboard / BlackboardPlan**
（类型化变量、多智能体共享同一棵树、v1.7.0 起支持**运行时黑板检视**）

**战术自己写，推荐结构**：

1. **Squad 层**：持有共享 Blackboard（目标、`alert_level: float`、玩家最后可见位置与时间、已分配包夹位、阵亡成员）
2. **⚠️ 警戒等级扩散走格子 BFS，不走直线** → 直接复用 §4.2 的 **Cost Field 做穿墙衰减**，
   天然正确且**可 headless 单测**
3. **包夹不是路径问题，是位置分配问题**：在玩家周围取角度槽位（±45° / ±90°），
   用"距离 + 是否被玩家视线覆盖 + 是否被队友占用"做**贪心 / 匈牙利匹配**，再各自走位
4. **不要上真正的 MAPF**

### 4.8 感知（T-84 / T-85）

**⚠️ 先纠正一个常见误解**：
> **`LightOccluder2D` / `OccluderPolygon2D` 不能用于 AI 视线查询。**
> `OccluderPolygon2D` 只有 `polygon` / `closed` / `cull_mode` 三个成员，
> 是**纯 2D 光照渲染系统**，**没有任何查询 API**。

| 技术 | 关键事实 |
|---|---|
| **`PhysicsDirectSpaceState2D.intersect_ray()`** | ✅ **视线遮挡首选**。⚠️ **必须在 `_physics_process()` 内调用**（官方原文：空间在外部是 *locked*）。`exclude=[self]` 防自撞；**用 `collision_mask` 比 exceptions 数组高效** |
| **`ShapeCast2D`** | ✅ 可一次查询近似"视野锥"、返回多个碰撞体。⚠️ 官方警告 **"Shape casting is more computationally expensive than ray casting."** → 用 `max_results` 限流 |
| **`RayCast2D`** | ✅ 少量角色可用（每物理帧自动返回结果） |
| **`Area2D`** | ⚠️ 官方明说其短板：**"collision information isn't immediately available to it"** → **不适合瞬时精确判定**，只做粗筛 |
| [Vision Cone 2D](https://godotengine.org/asset-library/asset/1568) | MIT，94 stars。⚠️ **是否自带射线遮挡未核实 → 待确认** |

**听觉（T-85）**：
> **Godot 4 没有游戏逻辑层面的"听觉 / 声音传播" API。**
> `AudioListener2D` 的唯一职责是 "Overrides the location sounds are heard from"
> —— 这是**给音频混音用的听者位置**，**不是游戏查询**。

**推荐方案**：全局信号 `noise_emitted(position, loudness, source_team)` +
**基于格子的声音强度场**（复用 §4.2 的 Cost Field 做 BFS）
→ **穿墙衰减天然正确**，可与流场共用数据结构。

### 4.9 ⭐ 性能：网格地图的最大红利（T-86）

**官方警告（有出处）**：
> "Try to **never** request any information from `RenderingServer`, `PhysicsServer2D`, or `PhysicsServer3D` ...
> These servers will often run **asynchronously** ... calling any function that returns a value will **stall them** ...
> This will **severely decrease performance** if you call them every frame (and it won't be obvious why)."

→ **正对应"30 个敌人每帧查物理空间"这个反模式。**

**四条优化，按性价比排序**：

| # | 手段 | 说明 |
|---|---|---|
| **1** ⭐ | **格子级可见性表** | 关卡生成时**预计算**；判断"两格连线上格子是否全通行"是**纯数据操作、零物理调用**。**这是网格地图架构的最大红利**——比任何射线调优都省，且**完全可 headless 单测** |
| **2** | **分帧错峰** | 30 敌人按 `index % 3` 分 3 组，每物理帧只 1 组做完整检测 → 每帧 10 次，每敌人每 3 帧（50 ms）更新一次。**对枪战手感不可感知**，CPU 峰值削掉 2/3 |
| **3** | **两级粗筛** | 先 `distance² < range²` + `dot(facing, to_target) > cos(half_angle)`（纯数学、零物理）→ 真正需要射线遮挡的往往只剩 3–8 个 |
| **4** | **距离 / 可见性 LOD** | 屏幕外或远处降到每 6–10 帧一次，甚至只做纯数学判定 |

**其他约束**：
- 寻路用**共享流场**，每帧最多 1 次重算，且**只在玩家换格时**
- 听觉走格子场，避免"每敌人对每枪声检测"
- 开 `run_on_separate_thread` 后**不要在非物理帧查空间**（会放大"空间锁定"错误）

> ⚠️ **我没有找到 Godot 官方给出的"每帧安全射线数"数字。** 官方不发布这类预算
> （完全取决于目标设备与形状复杂度）。**以上是工程建议，非文档结论。请以真机 profiler 为准。**

### 4.10 授权红线（本次调研新增）

| 项目 | 问题 | 处置 |
|---|---|---|
| 🚨 [Jhon-Crow/godot-topdown-MVP](https://github.com/Jhon-Crow/godot-topdown-MVP) | **同品类参考**（含 VisionComponent / CoverComponent / GOAP / 听觉），**但仓库内找不到任何 LICENSE 文件（返回 404）** → 按著作权默认规则**保留所有权利** | ❌ **只能读思路，绝对不能复制代码**进 GPL-3.0 项目 |
| ⚠️ [kagenash1/godot-behavior-tree](https://github.com/kagenash1/godot-behavior-tree) | README 声称 MIT，但**根目录没有 LICENSE / LICENSE.md** | ⚠️ **声明与文件不一致，使用前先向作者确认** |
| ⚠️ LimboAI | MIT 且有 Android 预编译包，但**与 Godot 版本强绑定** | ⚠️ **工程风险**（升级引擎须同步换包），非授权风险 |

> ❌ **明确找不到**（不凑数）：
> - 成熟的 Godot 4 开源**战斗小队协同 AI**库
> - 成熟的 Godot 4 开源**声音传播 / 听觉**库（搜索命中的是 AI 提示词文档仓库，**不是游戏库**）
> - `NathanHoad/godot-state-machine` —— **API 返回 404**（不存在或已改名），**勿采信其他资料里的该链接**

---

## 5. 随机地图生成

### 5.1 核心范式：图优先（Graph-based）

> **`feasibility.md` §4.2 的四条硬约束（全连通 / 撤离点 ≥2 / 出生撤离距离 / 宽度 ≥3 格）本质都是图上的约束。**

| 算法 | 评价 |
|---|---|
| **图优先（TinyKeep / Edgar / Gungeon）** | ✅✅ **采纳**。房间类型/连通性/环路/关键路径/预算**全在图阶段可算可校验** |
| **BSP 分割** | ✅ 适合方正室内（军事基地/实验室）；不重叠、无浪费、**天然全连通**、O(n log n) |
| 随机房间 + 走廊 | ⚠️ 最简单但**不保证连通** |
| Drunkard's Walk | ❌ 不保证连通与宽度 |
| **Cellular Automata** | ❌ **不采纳**——天生**切碎走廊宽度**、丢失房间语义 |
| Voronoi / 泊松盘 | ⚠️ 形状不规则、宽度难保证（可用于有机城区分块） |

### 5.2 采纳的生成链路（T-30）

```
seed
 → ① 房间布点（BSP = 方正室内 / 泊松盘 + 分离转向 = 有机城区）
 → ② 房间邻接图（网格邻接 或 Delaunay）
 → ③ Kruskal MST 保证全连通
 → ④ 回加 10%~20% 边造环（TinyKeep 用 15%）
 → ⑤ 固定宽度走廊
 → ⑥ uncarve：只删一部分死路，保留 10%~20% 尽头房
 → ⑦ 按「图距离 + 深度」分配 6 种房间类型
 → ⑧ ★ 图论校验不通过就换 seed 重来（最多 N 次）
 → ⑨ 按类型 + 深度系数，用 rand_weighted 花预算
 → ⑩ terrain set 自动接合铺 tile
```

> ⚠️ **uncarve 只删一部分**：Bob Nystrom 明确警告"跑到底会把整个迷宫擦光"。

### 5.3 ⭐ 最关键工程决策：逻辑格 = 3×3 tile（T-31）

| 项 | 值 |
|---|---|
| 逻辑格尺寸 | **3 × 3 tile**（16 px → **48 px 逻辑格**） |
| 走廊宽度 | **恒为 1 逻辑格** = 3 tile |
| 房间最小 | 2 × 2 逻辑格 |

**这一个决策同时解决三件事**：

1. **「最小可行走宽度 ≥3 格」从"每处都要小心"变成"结构上不可能违反"**
2. **寻路与生成规模缩小 9 倍**（直接利好手机性能）
3. 走廊宽度恒定，**AI 群体协同的包夹槽位计算更简单**

### 5.4 Godot 4 现成实现

> **结论：Godot 4 生态里成熟的 2D 房间-走廊生成插件非常稀缺**——真正可用的只有 3 个。
> Asset Library 检索实证：关键词 `dungeon` **仅 2 条**、`roguelike` **仅 1 条**。

| 方案 | 授权 | Godot | 结论 |
|---|---|---|---|
| **自写生成器（约 600–1200 行 GDScript）** | — | 4.6 | ✅ **首选**。现有插件**没有一个**能同时满足「房间类型表 + 图论硬校验 + 3 格宽走廊」。自写核心更快，GPL-3.0 零授权摩擦 |
| [ProcGen](https://godotengine.org/asset-library/asset/4672) | **MIT** | 4.5 | ⚠️【需改造】取 BSP 分区 + Kruskal 连接，**丢掉末段 CA**（会破坏走廊宽度）。⚠️ **用内部 RNG，`generate_new_seed_on_run` 会覆盖你设的 seed** |
| [Edgar.Godot](https://godotengine.org/asset-library/asset/3770) | MIT（包装层） | 4.5 | ⚠️【需改造，风险中高】唯一现成图优先方案，但需 .NET 版 Godot 或 GDExtension，**安卓导出复杂度 ↑**；上游自陈"最佳 <30 房间"。⚠️ **底层 Edgar-DotNet 授权待确认** |
| [DTL Godot GDExtension](https://godotengine.org/asset-library/asset/3583) | MIT | 4.3 | ⚠️【偏底层】C++ 挖洞器，手机性能最好，但**只给网格、无房间语义**。⚠️ Android 各 ABI `.so` 是否自带**待确认** |
| [Blobsmith Autotile Wirer](https://godotengine.org/asset-library/asset/5343) | MIT | 4.3+ | ✅【可直接使用】**一键生成 47-blob TileSet**，省一天手工配置。仅编辑器工具 |

### 5.5 TileMap / Terrain（**全部内置，不需要插件**）

- ⚠️ **`TileMap` 已废弃 → `TileMapLayer`**（一节点一层）。官方原文：「Unlike the TileMap node, which is deprecated, TileMapLayer has only one layer of tiles.」
- **terrain autotiling 是内置的**：`TileSet` 的 `TERRAIN_MODE_MATCH_CORNERS_AND_SIDES`（= **47-blob**）
- **`set_cells_terrain_connect()`** 自动与邻居接合——**对随机走廊特别有用**
- **把「房间 ID / 房间类型 / 可走」写进 tile 的 Custom Data Layer** 是好做法
- ⚠️ **TileMapLayer 批量写入在帧末批处理**；`update_internals()` 开销大要少用
  → **先写进自建数组，全部校验通过后一次性灌入 TileMapLayer**

### 5.6 调试与调参（决定"好玩度"）

| 手段 | 说明 |
|---|---|
| **图论叠加视图（必须自写）** | 房间画圆点、连接画线、类型配色、出生/撤离标星叠加在 tilemap 上。**这是调"好玩度"唯一能看见结构性问题的办法**（死路扎堆？环路太密？撤离点太近？）。**现成插件里没有这个功能** |
| **seed 显示 + 一键重随 + 手输 seed** | 早做，否则无法复现玩家报的图 |
| Tiled 1.10+ 自带 Godot 4 导出器 | 直接产出 `.tscn`；tile 的 custom property 会导出为 Godot **Custom Data Layers**（**【可直接使用】**） |
| Godot 生成结果 → 可编辑关卡 | 用 `PackedScene.pack()` + `ResourceSaver.save()` 存成 `.tscn`。**属推断，需实测** |

> ❌ **Godot → Tiled 反向导出：未找到任何官方或成熟工具。**

### 5.7 seed 纪律（T-32）

1. **用 `RandomNumberGenerator` 实例，禁止全局 `randi()` / `randf()`**——全局仅一条流，调用者互相污染，无法局部复现
2. ⚠️ **给 `seed` 赋值会重置 `state`**。官方警告原文：「Changing the seed will reset the state, so make sure to set the seed first.」
   → **顺序必须** `new()` → `seed = X` → 记录 `state`
3. **每张图一个 seed 并持久化**（存档 + 日志 + 地图 ID）
4. **子 seed 用 `seed ^ (0x9E3779B9 * id)`**，不要用相邻整数
5. ⚠️ **`RandomNumberGenerator` 在极短时间内连续创建并赋 seed 时可能产生相关的随机流**（godot#119322，**本环境无法核实正文**）→ 稳妥做法是**同一 RNG 顺序消费**
6. ⚠️ **引入任何第三方生成器，第一件事是确认它的 RNG 来源与自播种开关**
7. **加 lint / 自检，禁止生产生成代码里出现全局随机**

> ⚠️ **纠正**：本文件早先草稿写过「`Random` 单例」——**Godot 4 里不存在名为 `Random` 的类或单例**。
> 官方原文是"两种方式"：`@GlobalScope` 全局函数（`randi()` 等，Godot 4 里是**静态方法**）与 `RandomNumberGenerator` 类。

### 5.8 性能预算（T-33）

- **无官方权威数字**，不编造。
- 锚点：**60 FPS ⇒ 16.67 ms/帧**；同步生成超 ~16 ms 即掉帧；>100 ms 感觉"顿一下"；>1 s 被认为卡死
- **建议**：小/中图（80×80 ~ 160×160）「生成 + 铺 tile」**同步目标 < 50 ms**
- **搜打撤通常是进图前 loading → 放 loading 最省心**；必须局内生成则用后台线程或分帧协程
- ⚠️ **GDScript 下"单后台线程"比"多线程并行分区"现实**——ProcGen README 实证多线程"不稳定且更慢"，建议 `automaton_threads = 1`
- 用 `Time.get_ticks_usec()` 对六段（分区/连接/走廊/uncarve/校验/铺 tile）分别计时，在最低配目标机跑 1000 张图看 P50/P95/max

### 5.9 搜打撤针对性两条（T-34）

1. **撤离点不要生成完再随便挑**：在 ⑦ 阶段就用**图 BFS 跳数 + tile 路径长度双阈值**筛选
   （如 `跳数 ≥ 4 且 路径长度 ≥ 图对角线 40%`，且两撤离点互不相邻）。路径长度用 `AStarGrid2D` 算
2. **高价值房应落在"环路末端"而非主干道旁**（Gungeon 的 **"No risk – no reward"** 规则），用**图距离**筛

### 5.10 权威学习资料（**学思路，代码自己写**）

| 资料 | 链接 | 价值 |
|---|---|---|
| **Rooms and Mazes** — Bob Nystrom | [链接](https://journal.stuffwithstuff.com/2014/12/21/rooms-and-mazes/) | 完整流程；uncarve 只删一部分的原话依据 |
| **TinyKeep Dungeon Generation** — Phigames | [链接](https://www.indiedb.com/games/tinykeep/news/dungeon-generation-demo) | 9 步原文；**回加 15% Delaunay 边造环** |
| **Dungeon Generation in Enter The Gungeon** — BorisTheBrave | [链接](https://www.boristhebrave.com/2019/07/28/dungeon-generation-in-enter-the-gungeon/) | flow 图 + room type + node injection；"No risk – no reward" |
| **BFS for dungeon generation** — Red Blob Games | [链接](https://www.redblobgames.com/x/2043-bfs-dungeons/) | 一主路径 + 多短路 + 偶尔环 + 锁与钥匙 |
| **《PCG in Games》**（Springer 2016，作者版 PDF 免费） | [链接](https://www.pcgbook.com/) | 第 3 章构造式地牢生成；第 12 章生成器评估 |
| **Spelunky Generator Lessons** — Darius Kazemi | [链接](https://tinysubversions.com/spelunkyGen/) | 先生成关键路径，再放敌人/宝藏 |

> ⚠️ **归因纠正**：TinyKeep 的方法是开发者 **Phigames** 在 IndieDB 写的，
> **与 Adi Shavit 无任何关联**（搜到的 Adi Shavit 是 C++ 社群讲者）。**请勿归因到他。**

---

## 6. 背包 / 数据驱动 / 存档 / 测试 / 本地化

### 6.1 ⚠️ 背包插件的结论：**不要用任何现成插件**

> **Godot 4 背包插件生态质量普遍不行，尤其是对安卓触屏场景。**

**证据**：

| 事实 | 说明 |
|---|---|
| 17 个 Godot 4 背包插件**全部 MIT** | **授权不是问题，问题在质量** |
| **没有一个**在文档中声明"移动端 / 触屏可用" | — |
| 头部插件 **GLoot 有明确的安卓拖拽失效 issue**（gloot#197） | 标题级证据，正文待确认 |
| **Wyvernbox**（功能最全）的交互范式是 **Shift-Click / Double-Click / Right-Click** | **手机上根本不存在右键** |
| **Grid Inventory Lite** 把堆叠 / 工具提示 / 存档放进**付费 PRO** 版 | Lite 版不满足需求 |
| 我们的组合（格子 + 重量 + 触屏 + 全数据驱动 + headless 单测 + 中文） | **在现成插件里不存在交集** |

**结论（T-60）**：**模拟层自己写，UI 层自己写，不整套引入任何背包插件。**
模拟层核心约 **600–1000 行 GDScript**，**改造成本高于自写成本**，且只有自写才能在 headless 下无痛单测。

**唯一值得抄的是架构思想**：[GLoot](https://github.com/peter-kish/gloot)（MIT）的
**「约束（Constraint）组合」**设计 —— `GridConstraint` / `WeightConstraint` / `ItemCountConstraint` 自由组合。

### 6.2 背包形态选型（T-61）

| 维度 | 槽位 / 列表背包 | 网格占格（Tetris / 塔科夫式） |
|---|---|---|
| 数据结构 | `Array[Slot]`，O(1) | 占据矩阵 + 矩形列表，O(W×H) |
| 需要算法 | 无 | **首次/最优适配装箱 + 旋转** |
| 自动整理 | 一行排序 | **NP-hard 近似问题**，玩家期待"一键整理"却很难做好 |
| **触屏可用性** | ✅ 好（点选→点放即可） | ❌ **差**：手指遮挡目标格、需精确对齐 1~4 格 |
| 拖拽命中 | 单格 | 多格矩形 + 旋转矩形，**触屏上误差被放大** |
| 开发成本 | **1×** | **3~5×** |

**采纳方案**：**装备槽位 + 主背包用宽格**（6×4 大格，每格 1 物品，可堆叠）
—— **有网格视觉但无 Tetris 占格**。

> **Tetris 占格只放在藏身处（stash）界面**——把复杂度放到玩家不急的场景里。

### 6.3 触屏背包交互（T-62）——**手机没有鼠标怎么办**

业界对"触屏拖拽很差"的标准解法是**不依赖拖拽**：

| 方案 | 说明 | 推荐度 |
|---|---|---|
| **点选 → 点放**（Tap-to-pick / Tap-to-place） | 第一次点选中（槽位高亮 + 显示"手中物品"），再点目标格放下。**零精度要求，可撤销** | ★★★★★ **主交互** |
| **长按抬起 → 拖动 → 松手放下** | 长按 ≥300 ms 进入"拿起"状态。**作为可选加速，不是唯一路径** | ★★★★☆ 辅助 |
| **上下文菜单 / 长按菜单** | 长按弹「使用 / 拆分 / 丢弃 / 装备 / 移到藏身处」。**取代鼠标右键** | ★★★★★ 必备 |
| **拆分堆叠用按钮而非拖拽** | "− / +" 或步进器，**绝不让玩家靠拖拽位置表达数量** | ★★★★★ |
| **一键整理 / 一键合并 / 一键堆叠** | 减少手动摆放的全部需求，也就绕开了触屏拖拽难题 | ★★★★★ |
| **快捷栏** | 消耗品 / 枪械放快捷栏，直接点按使用 | ★★★★☆ |
| **点按即用** | 医疗包 / 弹匣单击即用，长按才进菜单 | ★★★★☆ |

**⚠️ 硬性尺寸约束**：触摸目标 **≥ 48 dp（Android Material）/ 44 pt（Apple HIG）**。
**像素风 UI 尤其容易把格子做到 32 px，必须按屏幕 DPI 缩放，否则点不中。**

**拖拽实现（T-63）**：Godot 的 `_get_drag_data` / `_can_drop_data` / `_drop_data` **只做转发**，
所有合法性判断与状态变更调用**模拟层**（纯 GDScript、无 Node 依赖）。
这样 headless 单测才能覆盖"移动 / 交换 / 堆叠 / 拆分"的全部状态机——正是 D-06 要的效果。

⚠️ **触摸模拟鼠标会与虚拟摇杆冲突**（摇杆拖动被当成 UI 拖拽）。
更稳的做法：**自己用 `InputEventScreenTouch` / `InputEventScreenDrag` 实现**，并定义清晰的**手势让渡规则**
（手指落在摇杆区域 → 归摇杆；落在背包面板 → 归背包；面板滑动 → 滚动列表）。

### 6.4 数据格式：JSON 为唯一真源（T-64）

| 维度 | 自定义 `Resource`（.tres/.res） | **JSON** |
|---|---|---|
| 编辑器友好度 | ✅ 极好（Inspector 直接编辑） | ❌ 无内置编辑器 |
| 类型安全 | ✅ 属性一定存在 | ❌ 全靠运行时校验 |
| **版本控制 diff** | ⚠️ 冗长；路径/uid 噪声大；重命名引发大面积 diff | ✅ **极好**：紧凑、稳定、天然按行 diff |
| **AI 生成友好度** | ❌ 差：模型容易写错 `[gd_resource ...]` 头、`ext_resource` id、`uid://` | ✅ **极好**：模型天然擅长吐 JSON |
| **文件数量** | ❌ **每个物品一个文件** = 250+25+120+80 ≈ **475 个 .tres**，FileSystem 面板爆炸 | ✅ 一个 `items.json` / `weapons.json` |
| 加载性能 | ✅ 最佳 | ⚠️ 需解析——但 475 行在手机上是毫秒级 |
| 热重载 | ❌ 要等重新导入 | ✅ 重读一次即可 |

**明确结论**：
> **以 JSON 作为唯一真源 + 启动时严格校验 + 运行时编译成轻量类型化对象。不使用 475 个 .tres。**

**唯一例外**：需要引 `Texture2D` 时，JSON 里存 `"icon": "res://art/items/ak47.png"`，加载时 `load()` 一次并缓存。

**想要编辑器友好时的折中**：写一个 EditorPlugin 从 JSON **生成** `.tres`
（**单向 JSON → Resource，JSON 仍是真源，生成的 .tres 加入 `.gitignore`**）。

> 印证：GLoot 的物品原型也**用 JSON prototree**，而不是为每件物品建 Resource。

### 6.5 数据加载与校验（T-65）

**加载要点**：

| 要点 | 做法 |
|---|---|
| 路径 | 放 `res://data/**`，**不放 `user://`**。JSON 导出时打进 PCK，`FileAccess.open("res://...")` 依然可读 |
| **解析错误必须检查** | `JSON.parse()` 返回值 + `json.get_error_line()` / `get_error_message()` |
| **类型换算** | JSON 只有 float，**没有 int / Vector2 / Color**。约定：整数用 `int(row["damage"])`；向量用 `"Vector2i(2,2)"` 字符串 + `str_to_var()`（GLoot 就这么做） |
| 索引化 | 加载后**立刻建 `Dictionary` 主键索引**，避免运行时线性查找 |
| **交叉引用校验** | 单独一趟验证 `recipe.inputs` / `attachment.fits` 里的 id 都存在 |
| 唯一性 | 校验 id 不重复；不通过就 `assert`/`push_error` 并**在 CI 里当失败处理** |
| 运行时只读 | 玩家改动**只写存档**，不回写真源 |

**Schema 校验工具**：

| 方案 | 授权 | Godot | 更新 | 结论 |
|---|---|---|---|---|
| [**GDSchema**](https://godotengine.org/asset-library/asset/4383) | **MIT** | 4.3 | 2026-08-24 | ✅【可直接使用】**完整 JSON Schema Draft 2020-12**，支持 `$ref`、详细错误报告 |
| [**Zodot**](https://godotengine.org/asset-library/asset/2261) | **Apache-2.0** | 4.2 | 2024-03-11 | ✅【可直接使用】Zod 风格链式 DSL，零依赖 |

> **诚实提示**：对 475 行数据，**自己写 60 行校验器**（必填字段、类型、枚举、范围、交叉引用、id 唯一）
> 通常比引入插件更划算，且能在 headless 测试里直接断言。**先用自写，不够再上 GDSchema。**

**CSV 导入**：Godot 生态**没有**工业级 "CSV → 强类型 Resource" 方案。
CSV 只在"需要拿 Excel 编辑"时引入，且**在构建期转成 JSON**（`godot --headless -s tools/csv2json.gd`），
**不要把 CSV 解析留到运行时**。

### 6.6 ⚠️ 存档：安全漏洞与方案（T-66）

> 🚨 **绝对不要用 `ResourceSaver` 存玩家档案。**
> **`.tres` 可被 `load()`，加载恶意 `.tres` 会执行脚本 / 实例化任意资源** —— 这是经典 Godot 存档漏洞。
> 而搜打撤玩家**一定会去改存档**。

| 方案 | 人类可读 | 体积 | 适合 |
|---|---|---|---|
| **JSON + `FileAccess`** ✅ **采纳** | ✅ | 大 | 背包、状态、藏身处进度、map seed |
| `FileAccess.open_encrypted_with_pass`（AES-256） | ❌ | 大 | 需要加密时叠加 |
| **`ConfigFile`** | ✅ INI | 小 | **设置 / 偏好**（音量、语言、按键）——官方文档明确推荐 |
| 二进制 `store_var` / `get_var` | ❌ | **最小** | 大量状态；但版本迁移更难 |
| ~~`ResourceSaver` (.tres/.res)~~ | — | — | 🚫 **禁止用于玩家存档** |
| SQLite（[godot-sqlite](https://github.com/2shady4u/godot-sqlite)，MIT，4.5） | ❌ | 中 | ❌ **不采纳**：**明确不支持加密**；安卓 `res://` 不可写、必须整库拷到 `user://`；**对单机搜打撤过重** |

**防篡改的正确心态（T-67）**：
> **单机游戏做不到真正的防篡改**——密钥在二进制里，玩家能反编译。
> 目标是**提高成本 + 优雅降级**，不是"防住"。

| 手段 | 强度 |
|---|---|
| **不存派生值**——只存 `{item_id, count}` 与进度标记，伤害/价格/容量全部从数据表读 | ★★★★★ **最有效** |
| **白名单归一化**——`item_id` 必须存在于 `DataRegistry`；`count` 钳制到 `[0, max_stack]`；越界槽位丢弃 | ★★★★☆ |
| **版本字段 + 迁移链**——`"version": 7` + `while v < CURRENT: v = _migrate[v](data)`。**从第一版就加** | ★★★★★ **必做** |
| 完整性校验——`HashingContext` + SHA-256，`payload` 与签名分开存 | ★★★☆☆ |
| 加密——`open_encrypted_with_pass`，密钥混淆进二进制 | ★★☆☆☆ 只提高门槛 |
| **优雅降级**——检测异常 → 打 `"modified": true`，禁用联机/排行榜/成就，但**允许继续玩** | ★★★★★ |

> **搜打撤玩家最恨的是"改了一下存档就被删档"。** 打标记，别删档。

**安卓 `user://`（T-68）**：
- 官方文档只写 "unique to the project and is not accessible by other applications"，
  **绝对路径未给出 → 用 `OS.get_user_data_dir()` 或 `ProjectSettings.globalize_path("user://")` 打印，不要硬编码**
- `user://` **一定可写**；`res://` 运行时**只读**
- ⚠️ **`user://` 默认会纳入 Android Auto Backup**（godot PR #49069）→
  改过的存档可能随 Google 账号**恢复到新设备**（好消息是 `modified` 标记会跟着走）

**存档插件备选**：[Save Vault](https://godotengine.org/asset-library/asset/5478)（**MIT**，v1.1.0，2026-09）——
**加密 + 多存档槽 + 可选 Steam Cloud + 云/本地冲突解决 + JSON/二进制双编码**。
但**版本迁移与白名单校验插件帮不了你，必须自己写**。

> ❌ **授权雷区**：`TemplateSaver`（Asset 2663）是 **GPLv2** → **禁用**（命中 `third-party.md` R-06）。
> ⚠️ `Addonsave` 是 **GPLv3** → 可用但会传染，**非必要不引入**。

### 6.7 测试框架（T-69）

| 维度 | **GUT** | **GdUnit4** |
|---|---|---|
| 授权 | **MIT** | **MIT** |
| 版本 | 9.6.1 → **Godot 4.6**（2026-07） | v6.2.0 → **Godot 4.5+**（2026-07） |
| headless | ✅ `addons/gut/gut_cmdln.gd` | ✅ 官方 Command Line Tool |
| **退出码** | **全通过 0，有失败 1** → 可作 CI gate | 同 |
| 报告 | JUnit XML | JUnit XML + **HTML** |
| CI 生态 | VSCode 扩展 | ✅ **官方 GitHub Action** |
| 独有能力 | 轻量、教程最多 | **Scene Runner：可模拟鼠标/键盘/触屏输入**、Fuzzing、孤儿节点检测 |

**推荐：主力用 GdUnit4** —— 因为 **Scene Runner 支持触屏输入**，
可以直接为"触屏拖拽 / 点选背包 UI"写自动化测试，**这对安卓项目价值很大**；且带官方 CI action。

> ⚠️ **不要在同一项目混用两个框架**（会互相干扰测试发现）。

**headless 命令**：
```bash
godot --headless -d -s --path "$PWD" addons/gut/gut_cmdln.gd \
  -gexit -gdir=res://test/unit -gjunit_xml_file=res://test_results.xml
```

**CI 流程**：`--headless --import` → **数据校验脚本** → 单测 → JUnit XML 上报。

> 💡 **CI 加速技巧**：把**数据校验**也做成 headless 脚本（`godot --headless -s tools/validate_data.gd`），
> 在跑单测前先 gate——**数据错了立刻失败**。
>
> ⚠️ `godot --test` 是跑**引擎自身**的单测，与项目测试无关，**别混淆**。

**模拟层的五条硬约束（直接对应 D-06）**：

1. **纯 `RefCounted`/`Object`，不 `extends Node`，不引用任何 `Control`/`Sprite2D`** —— 测试不需要场景树、不需要渲染器，毫秒级跑完
2. **不读 `res://` 文件** —— 数据由构造函数 / `setup()` 注入，测试完全确定性
3. 外部依赖（**时间、随机、存档 IO**）走**接口注入**，测试里传 fake
4. **`randomize()` 绝不写死在模拟层**，必须注入带 seed 的 `RandomNumberGenerator`（直接对应 map seed）
5. 全部公开 API 可被单测直接调用，无隐藏的树/节点依赖

### 6.8 本地化（T-70）——**两条会毁掉中文版的坑**

**CSV 翻译表**：

```csv
keys,en,zh
ITEM_AK47,AK-47,AK-47
ITEM_MEDKIT,Medkit,医疗包
HINT_EXTRACT,Extract before the timer ends,倒计时结束前撤离
```

| 要点 | 说明 |
|---|---|
| **编码** | 🚨 **必须 UTF-8 无 BOM**。官方警告：**Excel 默认存 ANSI 不是 UTF-8** → 用 **LibreOffice 或 Google Sheets** |
| 列头 | `keys,<lang1>,<lang2>...`；lang 必须是**有效 locale**，或以 `_` 开头（该列作为注释不导入） |
| KEY 大小写 | **敏感**：`KEY1` 与 `Key1` 是不同键 → 约定**全大写** |
| 复数 / 上下文 | **Godot 4.6 起**支持 `?plural` 与 `?context` 列。⚠️ **使用后 Control 的自动翻译失效**，必须手动 `tr()` / `tr_n()` |
| **注册** | CSV 被自动导入，但**不会自动注册**。必须去 **Project Settings → Localization → Translations** 手动添加，否则运行时没翻译 |
| 运行时切换 | `TranslationServer.set_locale("zh")` |
| 自动翻译 | `Button`/`Label` 匹配翻译键会**自动翻译**。展示玩家名等要把节点 **Auto Translate → Mode 设为 Disabled** |
| 占位符 | 用 `String.format()` 具名占位符，让译者能调换顺序 |

**🚨 坑 1：Godot 默认项目字体只支持 Latin-1 子集，无法显示中文。**
→ 必须引入含 CJK 的字体（推荐 **Noto Sans CJK / Noto Sans SC**），
做成 `Theme` 的 Default Font 应用到根 `Control`。**不做就是满屏方块。**

**🚨 坑 2：中文断行需要 ICU 断行规则数据，而该数据默认不导出。**
→ 必须去 **Project Settings → Internationalization → Locale → 勾选 `Include Text Server Data`**，
否则中文换行 / 分词不正确。**代价：约 4 MB。**

> ⚠️ **这两条对包体和 M0 验证都有影响，必须在 M0 就验证一次中文显示与断行。**

**辅助工具**：[LocGuard Lite](https://godotengine.org/asset-library/asset/5378)（**MIT**，2026-09）
—— 检查缺失 / 未翻译的 key，**适合放进 CI**。

---

## 7. 射击战斗与手感

### 7.1 战斗核心架构

> **逻辑层一律 hitscan 射线判定（权威判决），表现层再决定要不要画飞行子弹。**
> —— 与 D-06「模拟层 / 表现层分离 + headless 单测」天然契合。

**官方依据**：Godot 文档说提高 physics ticks 的额外好处是「**让 tunneling 更不容易发生**」
→ **反推默认 60 Hz 物理一定会穿模漏检**。且 `Area2D` 在同一帧内无法采样多个位置，**高速子弹必漏**。

| ID | 决策 |
|---|---|
| **T-50** | 战斗判定 = **hitscan 射线**（`intersect_ray`）；子弹视觉与判定解耦 |
| **T-51** | **提高 physics ticks**（120 / 180 / 240）换取低延迟与低穿模；**不靠 physics interpolation**（见 §7.5） |
| **T-52** | **不做"爆头"**。用**多 `CollisionShape2D` + 射线返回的 `result["shape"]` 索引**映射部位/倍率（`intersect_ray` 原生支持）；或改做俯视专属的「背刺 / 弱点区域」 |
| **T-53** | **弹道下坠在 2D 俯视不做**——画面表现为"莫名偏离准心"，玩家读不出来 → 用**射程衰减**替代 |

### 7.2 对象池（T-54）

**Godot 4 没有内置对象池节点。**
自建 autoload 池（约 60 行：`reset()` + 预热 + `take()` 永不返回 null）**比引入插件划算**。

⚠️ 现成插件 **Godot Projectile Engine** 是 MIT，但**作者自标 `v0.6.0-beta`「不推荐用于生产」** → 【仅参考思路】

**万弹级性能**：官方 demo [`2d/bullet_shower`](https://docs.godotengine.org/)（MIT）示范 `PhysicsServer2D` 路线。

### 7.3 手感（Game Feel）

**反馈性价比排序**（高 → 低）：

| 排序 | 手段 | 说明 |
|---|---|---|
| ★★★★★ | **hitstop 命中停顿** | **上限 60–120 ms**——超了就"卡"而不是"猛" |
| ★★★★★ | **音效** | 与 hitstop 并列 |
| ★★★★ | 受击闪白 | |
| ★★★★ | **相机 trauma 震动** | `Camera2D.offset` + trauma 衰减，**trauma 平方是关键** |
| ★★★ | 命中标记 / 伤害数字 | |
| ★★★ | 血雾粒子 | |
| ★★ | 弹壳、枪口火光 | 锦上添花 |

> ⭐ **比"选哪个效果"更重要的原则：反馈必须分级。**
> 轻击 / 重击 / 暴击 / 击杀走**不同量级**的同一套效果；**全部同量级 = 手感反而变平**。

**⚠️ 不该做 shake 的时候**：

1. **连续随机震动**（机枪每发都抖）→ 不适 + 毁可读性
2. **"自己受伤"与"自己射击"用同幅度**
3. **像素游戏专属坑：亚像素随机偏移会撕裂像素网格** → **量化到整像素**，或改用「一帧式 kick」
4. 务必提供**关闭 / 降低震动的无障碍选项**

**后坐力**：视觉 kick 与准心真实偏移**分成两条独立通道**（主流方案）。**所有数值必须人工调。**

### 7.4 ⚠️ 一条与渲染方案直接相关的官方张力

| 官方说法 | 冲突 |
|---|---|
| 官方**像素游戏推荐 `viewport` 拉伸模式** | 但**同一页**明确警告 `viewport` **不适合需要亚像素移动 / 旋转的对象** |
| 我们的武器要**连续跟随瞄准角旋转**（D-04） | → 因此**不能纯用 `viewport`** |

**结论**：采纳 **`canvas_items` + `stretch scale mode = integer`**（即 T-15），兼顾整数倍缩放与亚像素精度。
**这是官方文档两段话的交叉推论，必须实机 A/B 验证。**

> ✅ **顺带验证**：D-04「枪械 12 角度烘焙」决策**被官方文档证实是对的**——
> Godot 明确 **MSAA 对 nearest-neighbor 像素画纹理内部的锯齿完全无效**，开 MSAA 修不了连续旋转的锯齿。

### 7.5 输入延迟优化（T-55）

**physics interpolation（4.4+）官方明确"会增加依赖物理 tick 的输入延迟"**
→ **射击游戏默认关闭**，先用提高 physics ticks（T-51）换低延迟。

官方文档可直接照做的清单：
关 V-Sync · `Swapchain Image Count = 2`（4.3+）· 提高 physics ticks · `Input.set_use_accumulated_input(false)` · 独占全屏

### 7.6 Godot 4 现成资源

| 项目 | 授权 | Godot | 结论 |
|---|---|---|---|
| [Phantom Camera](https://godotengine.org/asset-library/) | **MIT** | 4.4+ | ✅【可直接使用】Cinemachine 式相机框架 |
| **Saltmire Juice** | **MIT** | **4.6+** | ✅【可直接使用】**单个 autoload、零依赖**：trauma shake / hitstop / flash / 池化伤害数字。**与 T-01（4.6）正好匹配** |
| [godot-demo-projects `2d/bullet_shower`](https://docs.godotengine.org/) | MIT | 4 | ✅【可直接使用】官方万弹级性能 demo |
| Virtual Joystick DX | **MIT** | 4.6+ | ✅【可直接使用】见 T-10 |
| GameFeelFlow | MIT | 4.6+ | ⚠️【需评估】0 评价 |
| Godot Projectile Engine | MIT | 4.4 | ⚠️【仅参考】作者自标 beta |

> ⚠️ **授权地雷**：**Rokojori Action Library** 用的是自定义 **"Rokojori Public Indie License"**，
> **不是 OSI 开源许可** → 对 GPL-3.0 项目**直接排除**。
>
> ⚠️ **EZ Camera Shake 的 Godot 4 版本查不到可信移植** → **待确认，请勿据传闻引入**。
> 另有 `object-pooling-godot-4`、`Trauma - 2D Camera Shake`、`Virtual Joystick(1787)` 三项授权/版本**待确认**。

### 7.7 触屏射击（T-56）——**本条修正 T-13**

> **优先做「子弹磁性」（hitscan 射线加粗），而不是角度吸附。**

| 机制 | 评价 |
|---|---|
| **子弹磁性**（hitscan 射线加粗） | ⭐ **首选**。**不改准心、对输入映射零干扰**；且我们是 hitscan（T-50），**实现成本极低** |
| 磁性减速 | 次选，体感自然 |
| 角度吸附 | 备选，容易让玩家觉得"被抢枪" |
| 目标重力 | 备选 |

**两条硬原则**：

1. **辅助强度必须可被玩家超越**——玩家把摇杆推到底主动转向时，辅助应减弱 / 关闭
2. **搜打撤必须做目标筛选**——**不能自动吸附中立 NPC 或同伴**

**自动开火 vs 手动开火**：搜打撤的核心循环是「搜 → 打 → 撤」，
**开火时机的决策权比操作省力更重要** → **推荐默认手动开火 + 强 aim assist（子弹磁性）**，
把"辅助开火"做成**可选的无障碍项**。

**触屏延迟**：

- 设计侧：**touch down 即开火**；瞄准摇杆用 **STATIC 固定锚点**
  （DYNAMIC 动态跟随每次都要找零位 = 额外延迟）；准心与枪口解耦带 1 帧平滑
- 引擎侧见 T-55
- ⚠️ **触摸屏系统级延迟引擎改不了**；官方要求测延迟必须**高速摄像机拍屏幕 + 手指同框**

### 7.8 ⚠️ 必须人工试玩调参的部分（**AI 替不了**）

hitstop 时长 · 震动 trauma 幅度与衰减 · 后坐力曲线 · spread 数值 ·
**aim assist 容差角度与磁性强度** · 摇杆死区与灵敏度曲线

> **没有任何文档或 AI 能替你定这些数值。**

**建议工作流**：所有手感参数 `@export` → **编辑器 Remote Inspector 运行时热调** →
**一次只改一个参数** → 录屏 → **≥3 名不同水平测试者盲测** → **看 Profiler 的 frame time，不要看 FPS**。

---

## 8. 跨领域待验证清单

> ⚠️ **以下各项在本环境无法确认，**上线前必须实测**。不要跳过。

| # | 待验证项 | 为什么重要 | 来源 |
|---|---|---|---|
| **V-01** | **`aspect=expand` + `scale_mode=integer` 的实际行为** | 官方 issue #92055 记录了异常。异常则退回 `keep` | [#92055](https://github.com/godotengine/godot/issues/92055) |
| **V-02** | **Google Play 当前 targetSdk 要求** | **唯一会导致拒审的合规项**。政策页本环境抓取失败 | [Play 政策页](https://support.google.com/googleplay/android-developer/answer/11926878)（自行打开） |
| **V-03** | **所用 Godot 版本导出预设里 `Min SDK` 的默认值** | 目标 24，但以预设 UI 实际值 + 官方导出文档为准 | — |
| **V-04** | **Compatibility 渲染器下的粒子方案** | 若误用 `GPUParticles2D`，枪口火光会**不显示且不报错** | T-03 |
| **V-05** | **itch.io 素材补做调研** | 本环境 DNS 封锁，**像素素材最大聚集地完全未覆盖**。重点看 Anokolisa / LimeZu / Pixel-Boy 等作者并逐个核对授权 | — |
| **V-06** | **枪声素材来源** | 未找到并核实任何高质量免费枪声包；Kenney 无枪声包 | §3.6 |
| **V-07** | **ETC2/ASTC 是否启用** | 有损压缩会糊像素边。**M2 前必须定案** | §2.6 |
| **V-08** | **release keystore 备份** | **丢失 = 无法再更新同一应用**。必须存两处不同介质 | T-21 |
| **V-09** | ⚠️ **Android `InputEventScreenDrag` 触发间隔过长的 issue**（godot#120322） | **修复状态未能验证。它直接决定瞄准摇杆在真机上是否可用** | §7.7 |
| **V-10** | **逐个亲自打开所有 GitHub 仓库的 LICENSE** | 本环境 GitHub 被拦，所有授权信息**均为二手登记信息** | §0 |
| **V-11** | **EZ Camera Shake 是否有可信的 Godot 4 移植** | 未查到可信来源 → **请勿据传闻引入** | §7.6 |
| **V-12** | **physics ticks 具体值（120 / 180 / 240）** | 与输入延迟、穿模率直接相关，需实机 A/B | T-51 |
| **V-13** | **`canvas_items`+integer vs `viewport` 实机 A/B** | 官方文档两段话互相张力，**必须实测才能定** | §7.4 |
| **V-14** | **明确排除 Rokojori Action Library** | 自定义 "Public Indie License" **非 OSI 开源**，与 GPL-3.0 不兼容 | §7.6 |
| **V-15** | **三项授权待确认**：Edgar-DotNet（地图生成底层）、DTL 是否自带 Android 各 ABI `.so`、Dungeon Forge | 引入前必须核实，否则可能污染 GPL-3.0 | §5.4 |
| **V-16** | 🚨 **中文显示与断行**：换 CJK 字体 + 勾选 `Include Text Server Data` | **不换字体 = 满屏方块；不勾选 = 导出包里中文断行错乱**。后者**增加约 4 MB 包体** | §6.8 |
| **V-16b** | ✅ **已实测（2026-10-11，Godot 4.7.2）：该开关在编辑器/headless 下【恒真】，无法证伪。** | 把 `include_text_server_data` 设为 `false` 后，**断行断言依然全部通过**——因为它只控制数据是否打进**导出包**，编辑器自带这份数据。⇒ **headless 测试只能守门「设置没被误关」，不能证明导出包的行为。真实断行必须导到手机上目视确认。** | 见下方「M0 设备验证」 |
| **V-17** | **`gloot#197` / `godot#84331` / `godot#13235` 的正文与修复状态** | 只有标题级证据。**安卓触屏拖拽是否可用，直接决定背包 UI 方案** | §6.1 |
| **V-18** | **安卓 `user://` 的实际绝对路径** | 官方文档未给出。**必须用 `OS.get_user_data_dir()`，不要硬编码** | T-68 |
| **V-19** | **Android Auto Backup 的默认开关**（`android:allowBackup` / `fullBackupContent`） | 存档可能随 Google 账号恢复到新设备，影响防篡改策略 | T-68 |
| **V-20** | 🚫 **明确排除 `TemplateSaver`（Asset 2663，GPLv2）** | 命中 `third-party.md` R-06。⚠️ `Addonsave`（GPLv3）可用但会传染，**非必要不引入** | §6.6 |
| **V-21** | **三项数据类插件授权未核实**：ResPort (4734)、Gnumaru's Static Data Importer (3048)、Text Database (kobewi) | 引入前必须核实 | §6.5 |
| **V-22** | 🚨 **确认 Godot 4.7.2 稳定版 + 原生 `VirtualJoystick` 是否可用** | **T-01 已更正为 4.7.x**。若原生摇杆可用，则**不引第三方摇杆插件**（少一个版本绑定依赖）。这直接影响 M0 验证清单第 4 项 | T-01 / T-01b / T-10 |
| **V-23** | 🚫 **排除 Jhon-Crow/godot-topdown-MVP 的代码** | **同品类参考（视野/掩体/GOAP/听觉）极具诱惑，但仓库无任何 LICENSE 文件** → 保留所有权利。**只能读思路，绝不能复制代码** | §4.10 |
| **V-24** | ⚠️ **kagenash1/godot-behavior-tree 的授权** | README 称 MIT 但**仓库无 LICENSE 文件**，声明与文件不一致 → **使用前先向作者确认** | §4.10 |
| **V-25** | **`NavigationRegion2D` / `NavigationAgent2D` / `NavigationObstacle2D` 是否仍标 `experimental`** | 4.4 文档确实带该标记（导航系统重构期），**4.7 是否摘掉未核实**。影响是否敢依赖导航网格 | §4.5 |
| **V-26** | **Vision Cone 2D 是否自带射线遮挡** | 未读实现源码。若只做角度+距离锥，仍需自己接 `intersect_ray` | §4.8 |
| **V-27** | **LimboAI vs Beehave 的最终抉择** | **必须先冻结引擎版本再选**：LimboAI v1.8.1 → 4.7.2（功能强但版本强绑定）；Beehave（纯 GDScript、升级自由） | §4.6 |
| **V-28** | **`NathanHoad/godot-state-machine` 已被证伪** | API 返回 404（不存在或已改名）→ **勿采信其他资料里的该链接**。用 Godot State Charts 替代 | §4.10 |

---

## 9. M0 设备验证（真机）

> 有些坑 **headless 测不出来**。已实测确认的有两个，都做进了同一个真机场景。

**运行方式**：

```bash
# 1. 把主场景临时指到这个测试场景
#    Project Settings > Application > Run > Main Scene
#    = res://test/m0_device_check.tscn
# 2. 导出安卓 APK（渲染器走 mobile 覆盖项 = gl_compatibility）
# 3. 装到手机，打开，按屏幕上的 3 项检查单目视确认
# 4. 确认后把主场景改回来
```

| # | 检查项 | 期望 |
|---|---|---|
| 1 | **中文显示与断行** | 长中文段落在限宽框内**正确换行**，无方块、无溢出 |
| 2 | **粒子可见性** | 左侧 `CPUParticles2D` **有火焰**；右侧 `GPUParticles2D` **多半没有** → 证实 T-03 |
| 3 | **渲染器确认** | 手机上实际走 OpenGL/Compatibility 路径 |

### 9.1 ⚠️ 为什么检查 1 不能靠测试

**实测（2026-10-11，Godot 4.7.2）**：把 `include_text_server_data` 设为 `false` 后，
`test/run_tests.gd` 的断行断言**依然全部通过**（换行高度完全相同，都是 72 px）。

**原因**：该开关只控制 ICU 数据是否打进**导出包**，而**编辑器自带这份数据**。

⇒ **结论**：
- headless 测试的作用是**守门**（防止设置被误关、防止字体被删）——这仍然有价值
- 但**它不能证明导出包里的断行是对的**。这一条**只有真机/导出包能验证**

### 9.2 对应的自动化守门

`test/run_tests.gd` 的「CJK 字体与中文断行」套件保留，但断言已加前缀区分：

| 前缀 | 含义 |
|---|---|
| `[守门]` | **真正的失败条件** —— 设置被误关、字体加载不了、字形缺失 |
| `[编辑器]` | 编辑器层健全性检查 —— **恒真，不是导出包的证明** |
