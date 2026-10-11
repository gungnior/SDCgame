# Godot 4 安卓 2D 像素俯视射击 —— 移动端技术调研

> 调研方式：全部结论基于实际 `web_search` / `web_fetch` 结果，优先 Godot 官方文档与官方 Asset Library / 官方博客。
> 标注约定：**【可直接使用】** / **【需改造】** / **【仅参考思路，自己实现】**
> 诚实声明：Godot 官方文档站（docs.godotengine.org）的 HTML 页面由 Sphinx 生成，导航树极长，`web_fetch` 的正文抓取会在导航部分被截断（多次尝试均如此，含 zh-cn / pl / es 镜像）。因此**官方页面我给出的是"可访问 URL + 章节锚点"**，凡是没能直接读到正文的设置项，我都明确标为 **待确认**，不凭记忆编造 API 名。

---

## A. 触屏输入与虚拟摇杆

### A.1 `TouchScreenButton` vs `Control` 自绘摇杆

| 方案 | 基类 | 锚点/自适应 | 多点触控 | 动态摇杆 | 适用场景 | 结论 |
|---|---|---|---|---|---|---|
| `TouchScreenButton` | `Node2D` | **不支持 anchors**（这是官方 PR reviewer 明确指出的硬伤） | 单按钮级，靠 `action` 触发；**没有模拟量输出** | 不可能（原点固定在场景坐标） | 固定位置的离散按钮（开火、换弹、开镜） | **【仅参考思路】** |
| `Control` 自绘（推荐） | `Control` | 支持 anchors / `size_flags` / theme | 自己按 `index` 管理触点，可同时多摇杆 | 原生支持 | 双摇杆、动态摇杆、可换皮 UI | **【可直接使用】** |
| 引擎内置 `VirtualJoystick`（4.7+） | `Control` | 支持 anchors | 由引擎接管，直接写 InputMap | 原生三种模式 | 想省事、且能接受 4.7 的团队 | **【可直接使用】**（版本受限，见 A.2） |

关键证据：
- Godot 4.7 dev 1 官方博客明确说明内置 `VirtualJoystick` 存在，并列出三种模式：`JOYSTICK_FIXED` / `JOYSTICK_DYNAMIC` / `JOYSTICK_FOLLOWING`：<https://godotengine.org/article/dev-snapshot-godot-4-7-dev-1/>
- 其实现 PR（GH-110933）与 reviewer 对 `TouchScreenButton` 继承 `Node2D`、无法用 anchors 的评价，见第三方整理：<https://dev.to/ziva/virtualjoystick-in-godot-47-endlich-ein-nativer-touchscreen-stick-1enb>
- `TouchScreenButton` 类文档（stable）：<https://docs.godotengine.org/en/stable/classes/class_touchscreenbutton.html>
  - 该类有 `passby_press`、`action`、`visibility_mode`、`texture_pressed` 等属性。**具体属性语义我未能读到正文，标为待确认**；但"Node2D 基类 → 无 anchors"这一条已被官方 PR 讨论证实。

**结论**：射击游戏用 `Control` 自绘（或 4.7 内置 `VirtualJoystick`）。`TouchScreenButton` 只适合"固定位置的离散按钮"，不要拿它做摇杆。

### A.2 Godot 4 虚拟摇杆插件核查（授权 / 最后更新 / 兼容性 / 双摇杆 / 动态）

全部数据取自官方 Asset Library（Godot 官方站点，权威），非二手博客：

| 插件 | Asset Library | 授权 | Godot 版本下限 | 最后更新 | 双摇杆 | 动态/浮动摇杆 | 结论 |
|---|---|---|---|---|---|---|---|
| **Virtual Joystick DX** 1.1c | [asset/5256](https://www.godotengine.org/asset-library/asset/5256) | **MIT** | 4.6+（作者称 4.7 已测） | 2026-08-05 | ✅ 有 Active Region、可多节点 | ✅ `STATIC` / `DYNAMIC` / `FOLLOWING` 三种 | **【可直接使用】** 功能最全 |
| **Virtual Joystick CF** 2.0.0 | [asset/4891](https://godotengine.org/asset-library/asset/4891) | **MIT** | 4.5+ | 2026-06-21 | ✅ 支持多实例 | ✅ 插件自称可配置（描述较短） | **【可直接使用】**；注意它已改名以避免与 4.7 原生 `VirtualJoystick` 冲突 |
| **Virtual Joystick Plus** 2.0.0 | [asset/4458](https://godotengine.org/asset-library/asset/4458) | **MIT** | 描述写 "4.5+"，Asset Library 标 4.4 | 2026-02-02 | ✅ | ✅ `NORMAL` / `DYNAMIC` / `FOLLOW` | **【可直接使用】** |
| **Virtual Joystick**（MarcoFazioRandom）1.6 | [asset/1787](https://godotengine.org/asset-library/asset/1787) | **MIT** | 4.2 | 2024-08-29 | ✅（经典双摇杆参考实现） | ✅ 有 "dynamic" 选项（作者项目 README 里常被用作教程） | **【需改造】**：最后一次更新停在 2024-08，未针对 4.6/4.7 验证 |
| Mobile Touchscreen Joystick 1.0.0 | [asset/5155](https://godotengine.org/asset-library/asset/5155) | **MIT** | 4.6 | 2026-05-14 | 待确认 | 待确认 | 备选 |
| Virtual Joystick（mcunha-br）3.0.1 | [asset/1718](https://godotengine.org/asset-library/asset/1718) | **MIT** | 4.0 | 2025-03-01 | 待确认 | 待确认 | 备选 |

⚠️ **Godot 3 插件不可用于 Godot 4**：同一个 Asset Library 列表里混着 `Godot_multidirectional_joystick`（3.5）、`Virtual Joystick for Godot 3`（3.4）等 3.x 资产，安装前务必确认版本列。列表页：<https://godotengine.org/asset-library/asset?filter=joystick>

> 补充：4.7 官方博客提到的一个社区实现 `MarcoFazioRandom/Virtual-Joystick-Godot`，已被官方当作"目前大家不得不用社区方案"的例子引用（<https://godotengine.org/article/dev-snapshot-godot-4-7-dev-1/>）。

### A.3 动态/浮动摇杆（触点即摇杆原点）实现要点

引擎原生模式定义（官方原文，可直接照抄语义）：
- `JOYSTICK_FIXED`：摇杆不移动。
- `JOYSTICK_DYNAMIC`：只要触点落在摇杆 bounds 内，摇杆移到触点位置；松开回原位。
- `JOYSTICK_FOLLOWING`：同上，但手指超出原 bounds 后摇杆继续跟随；松开回原位（**Twin-stick 射击首选**）。

来源：<https://godotengine.org/article/dev-snapshot-godot-4-7-dev-1/>

自研要点（**【仅参考思路，自己实现】**，因为这一层没有官方 API 文档可引用）：
1. **不要用 `Control` 的 `rect_position` 做原点**：动态模式下原点应是"按下瞬间的触摸点"，与控件矩形解耦；控件矩形只作为"激活区域 / Active Region"。
2. **归一化输出**：`output = (touch_pos - origin).limit_length(radius) / radius`，用 `Vector2.limit_length()` 避免手动归一化时除零。
3. **死区要放在 InputMap 一侧还是控件一侧要统一**：4.7 原生 `VirtualJoystick` 明确把 deadzone 交给 InputMap，不在节点上重复配置（官方博客/文章明确说明这是设计决策）。自研时建议同样只保留一处。
4. **松开回原点必须用"该触点 index 的抬起"**，不能用"任意触点抬起"（多指场景必炸）。
5. 浮动摇杆的视觉透明度建议按下瞬间才显示（避免四个幽灵摇杆糊满屏幕）。

### A.4 辅助瞄准（aim assist）

**公开成熟做法盘点**：Godot 官方文档里**没有** aim assist 章节（这是引擎层不提供的能力），目前可复用的公开实现主要有两类。

| 方案 | 来源 | 思路 | 结论 |
|---|---|---|---|
| 角度门限 + 最近敌人 + lerp 转向（即"磁性吸附/减速吸附"的简化版） | Godot 官方论坛答案：[forum.godotengine.org/t/.../121083](https://forum.godotengine.org/t/how-to-create-a-aim-assist-auto-aim-in-godot-4-4/121083) | 取 `MAX_DIST` 内最近敌人 → 若最近敌人方向与摇杆方向夹角 > `FOV_ANGLE/2` 则用摇杆方向 → 否则用敌人方向 → `lerp` 旋转 | **【可直接使用】**（代码完整可跑）；用 `distance_squared_to` 省 sqrt 的细节对移动端有实际意义 |
| 软锁定 aim assist 脚本 | 第三方技能库 `thedivergentai/GD-Agentic-Skills`（GitHub，本次因环境 DNS 限制无法直读，仅作线索） | soft-lock 类吸附 | **【仅参考思路】**，授权与质量未核验 |
| 黏性锁定（sticky lock-on）设计模式 | `raduacg/game-mechanics-optimizations` 的 `104_sticky_lockon.md`（GitHub，同上未能直读） | 设计模式而非 Godot 代码 | **【仅参考思路】** |

**放在你们项目里的推荐组合（射击游戏常用三件套）**：
1. **磁吸（magnetism）**：在摇杆方向上开一个 ±X° 的锥形，锥内有敌人时把摇杆方向"拉"向最近敌人，权重按夹角衰减。
2. **减速（slowdown / friction）**：准星接近目标角度时降低转动灵敏度（鼠标 FPS 里的经典做法，触屏同样有效且体感比硬吸附自然）。
3. **子弹磁吸/辅助弹道**：出膛瞬间或飞行中轻微向最近敌人偏转——**这是唯一能让手感"必中"但玩家不觉得被抢控制权的手段**，比强行转向更不冒犯。

**必须做的约束（否则手感崩）**：
- 吸附只在"玩家在瞄准摇杆"时生效；摇杆回中立刻失效。
- FOV 门限要按屏幕尺寸换算（手机视口比桌面小，固定 90° 会显得吸附过强）。
- 加**视线/遮挡检查**（`RayCast2D` 或 `World2D` 直接空间状态），避免隔着墙吸附。
- 加一个"玩家主动反向拨杆即脱锁"的判定，这是玩家信任感的来源。

> 注意：上面论坛答案是社区回答，不是官方参考实现。Godot **没有官方 aim assist 参考实现**，这点必须直说。

### A.5 多点触控 + `InputEventScreenTouch` / `InputEventScreenDrag` 常见 bug

标准做法是 `_input()` / `_unhandled_input()` 里按**触点的 `index`（finger id）**分发，而不是"当前触摸位置"：

| 常见 bug | 根因 | 修法 |
|---|---|---|
| 移动摇杆和瞄准摇杆互相干扰 | 用单一 `touch_position` 变量存"当前触点" | 用 `Dictionary[int, Vector2]` 按 `index` 存每个手指的起点/当前位置 |
| 松开左手导致右手摇杆归零 | 抬起事件里无脑清空状态 | `InputEventScreenTouch.pressed == false` 时**只清该 index** |
| 拖拽抖动 / 摇杆跳变 | 用了 `event.position`（屏幕坐标）却没算控件坐标 | 统一到同一坐标系（`Control` 内用 `get_local_mouse_position()` 的等价物，或显式做 `canvas_transform` 逆变换） |
| 刘海/圆角区域点不到 | UI 贴着屏幕边缘 | 用 `DisplayServer.get_display_safe_area()` 做安全区偏移（**4.7 dev1 起还新增了设备方向变化信号，见官方博客**） |
| 触点被其他 `Control` 吃掉 | `mouse_filter` 默认值 | 摇杆容器设 `MOUSE_FILTER_STOP`，全屏背景设 `IGNORE`/`PASS` |
| 输入延迟感 | 引擎把一帧内的触摸合并处理 | 可考虑 `Input.set_use_accumulated_input(false)` 逐事件处理（来源：[gtstu.com 移动优化文](https://gtstu.com/godot-4-optimize-android-ios/)，非官方，标**待确认**） |

> 4.7 起另一个实际加分项：`Platforms: Add device orientation change signal to DisplayServer`（GH-115434），来源同上官方 4.7 dev1 博客。

---

## B. 安卓导出工程

> ⚠️ **诚实说明**：`docs.godotengine.org/en/*/tutorials/export/exporting_for_android.html` 我只拿到了"页面存在 + 章节标题"级别的信息，正文被导航截断。因此本节的**工具链精确版本号（JDK/NDK/build-tools/Gradle）我标注为"待你按官方页面核对"**，不编造数字。

### B.1 完整前置要求

| 组件 | 结论 | 依据 / 状态 |
|---|---|---|
| Godot 导出模板 | 必须与编辑器**完全同版本**（如 4.5.1 编辑器 → 4.5.1 模板）；测试版需手动 `Install from File` | 第三方实测指南：[summerengine.com](https://www.summerengine.com/blog/export-game-android-godot)（非官方） |
| JDK | **JDK 17**（Temurin/Adoptium 是常见免费发行版）。JDK 21 常导致 Gradle 失败 | 同上，非官方，**待确认**（官方页面会写明确版本） |
| Android SDK | 通过 Android Studio 或 **command-line tools** 安装；在 **Editor Settings → Export → Android** 里填 `Java SDK Path` 与 `Android SDK Path` | 官方页面章节标题确认存在 "Download the Android SDK"（见 es/it/pl 镜像锚点 `#download-the-android-sdk`） |
| NDK | 仅**自定义 Android 构建模板 / GDExtension** 才需要 | **待确认** |
| Build Template | 导出预设里点 **Install Android Build Template**，会在项目里生成 `android/build` Gradle 工程；**AAB 必需** | 同上 |
| 签名 keystore | debug 用 Godot 自动生成（debug 用户名 `androiddebugkey`，调试凭据是公开常识）；release 用 `keytool -genkey -v -keystore release.keystore -alias <alias> -keyalg RSA -keysize 2048 -validity 10000` | 同上 |
| 官方页面 | <https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html>（锚点：`#exporting-for-google-play-store`、`#create-a-debug-keystore`、`#download-the-android-sdk`） | ✅ |

**最大的坑（按第三方指南与实际社区反馈排序）**：
1. **编辑器 / 导出模板 / JDK 三者版本不一致** —— 绝大多数"第一次导出就失败"的根因（预设红点、Gradle 报错、"App not installed"）。
2. **改了 SDK/NDK 路径只重启编辑器不够**，Gradle 缓存会导致旧配置继续生效。
3. **包名必须是反向域名的全小写**，含空格/连字符/大写都会让 Gradle 崩。
4. **Android SDK 35 (API 35) 与旧版 Godot 的 Gradle/AGP 不兼容**：社区维护了补丁版 Godot 4.x 发行版（`shipth-is/godot-android-sdk-upgrade`，链接见下），这是 **【需改造】** 项。若你们用 4.6/4.7 通常已内含较新 AGP，仍需实测。
5. **release keystore 丢失 = 永久无法更新同一应用**（Google Play 的应用签名机制允许 Play 侧代管，但如果你们自己持有并丢了上传密钥，就只能走 Play 的密钥重置流程）。**这个文件必须备份**。
6. **换签名后的旧包覆盖安装会失败**，必须先卸载。

### B.2 推荐的目标 SDK / minSdk（Google Play 政策）

- **minSdk 24**：你们的目标（Android 7.0）。这是 Godot 4 安卓导出的常见下限；**Godot 4.4/4.5/4.6 各版本默认 minSdk 是否为 24 请以导出预设实际显示为准（待确认）**。
- **targetSdk**：必须跟随 Google Play 的年度要求。**Google Play 官方政策页**：<https://support.google.com/googleplay/android-developer/answer/11926878>
  - 该页面本次抓取失败（`fetch failed`），**因此具体 API 级别数字与生效日期请以该页面为准，我不给未经核实的数字**。
  - 已知方向：近两年政策要求新应用/更新针对"最新发布的 Android 大版本或前一版"（历史上从 API 33 → 34 → 35 逐年抬升）。**请在提审前 30 天再核一次该页**，这是唯一能保证不被拒审的做法。
- **发布前必查**：Google Play Console → "政策与计划" → 目标 API 级别提醒，会直接告诉你当前 App 是否达标。

### B.3 64 位 AAB 打包要点

| 项 | 结论 |
|---|---|
| 架构 | 保留 **arm64-v8a**（现代设备全覆盖）；`armeabi-v7a` 只有明确要覆盖极老机型时才勾。Play 的 64 位要求指的是**必须提供 64 位版本**，arm64-v8a 即满足。 |
| 格式 | 新应用 Play **只接受 AAB**；APK 用于自测/itch.io/侧载。 |
| 导出方式 | 导出预设 → `Export Project`，文件名后缀写 `.aab`。 |
| 一键部署 | 手机开 USB 调试，编辑器右上角出现 Android 图标 → 一键构建+安装+启动，并挂远程调试器。 |
| 符号上传 | **Godot 4.5 起支持 Android 原生调试符号**，可上传到 Play Console 让崩溃栈可读（来源：[gtstu.com](https://gtstu.com/godot-4-optimize-android-ios/)，非官方，**待确认**）。 |
| SDK 35 补丁版 | <https://github.com/shipth-is/godot-android-sdk-upgrade>（社区维护的 "Android SDK 35 Patched Releases of Godot 4.x"）**【需改造】** |

### B.4 常见坑（汇总）

- 红点提示三件套：模板没装 / JDK-SDK 路径错 / 没设 keystore。**悬停红点会直接告诉你缺哪个**。
- 启用 ETC2/ASTC 后**必须重新导入**纹理，否则设置等于没开（见 D.2）。
- 导出后**黑屏**：渲染器选错（桌面 Forward+ 在部分手机上直接黑屏）。
- **Compatibility 渲染器没有 compute shader**，`GPUParticles2D` 会**静默消失**（无报错）——2D 射击的枪口火光/血迹几乎一定会踩到。
- 大纹理（>2048）在低端 GPU 上易 OOM。

### B.5 真机调试

| 手段 | 用途 |
|---|---|
| `adb logcat` | 最底层、最可靠。Godot 的 `print()`/报错都会进 logcat |
| Godot 编辑器 **Debugger → Profiler / Remote Tree** | 经 USB 直接看帧时间、脚本耗时、实时改属性 |
| 一键部署（右上角 Android 图标） | 自动 build+install+launch+attach |
| Perfetto | **Godot 4.6+ 有集成**，系统级 trace（来源 [gtstu.com](https://gtstu.com/godot-4-optimize-android-ios/)，非官方，**待确认**） |
| Android GPU Inspector | 逐 draw call 的 GPU 耗时 |
| Play Console 崩溃符号 | 4.5+ 上传原生符号后栈可读 |

---

## C. 像素完美渲染

### C.1 `stretch_mode` / `stretch_aspect` / `scale_mode` 组合

官方章节页（含 `stretch_mode`、`stretch_aspect`、`scale_mode` 的说明与示例）：<https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html>

**推荐组合（2D 像素游戏 + 手机多分辨率）**：

| 设置 | 推荐值 | 理由 |
|---|---|---|
| `display/window/stretch/mode` | `canvas_items` | UI 与游戏一起缩放；`viewport` 模式会把 UI 也按低分辨率光栅化（像素游戏常用但 UI 会粗） |
| `display/window/stretch/aspect` | `keep` 或 `expand`（见 C.4） | `keep` → 黑边但绝不露出设计外区域；`expand` → 填充但会看到更多世界（对"搜打撤"这类有边界的关卡是可接受的，且能避开黑边观感） |
| `display/window/stretch/scale_mode` | **`integer`** | 像素完美的前提。`fractional` 会在非整数倍时产生像素大小不一致/抖动 |
| 视口基准分辨率 | 选一个能被常见手机宽高比整除的像素值（如 `640x360`） | 让整数倍缩放落到 `x2/x3` |

⚠️ **已知问题**：`aspect = expand` + `scale_mode = integer` 的组合存在官方 issue 记录的行为异常：<https://github.com/godotengine/godot/issues/92055>。**上线前必须实测这一组合**，若异常则退到 `keep` + `integer`（黑边方案）。

### C.2 Texture Filter = Nearest 的正确设置位置

- **项目级（必做）**：项目设置 → 渲染 → 纹理 → **Canvas 纹理默认过滤**（`rendering/textures/canvas_textures/default_texture_filter`）设为 **Nearest**。这是"全局默认"，导入的纹理继承它。
- **导入级**：每张纹理的 `.import` 文件里也可以覆盖（`Filter` 选项）；**画集内的像素图必须与项目级一致**。
- **节点级**：`CanvasItem.texture_filter` 可逐节点覆盖（`Sprite2D`、`TileMapLayer` 都有）。
- **优先级**：节点 > 纹理导入 > 项目默认。
- **同时要关掉亚像素抗锯齿**：`Line2D` / `Polygon2D` 等的 antialiasing 会破坏像素纯度（官方 2D 抗锯齿章节：`tutorials/2d/2d_antialiasing.html`）。
- 相关的一个老问题：4.6 起 2D 的 pixel snap 相关项目设置**被移除/改由 `CanvasItem` 的 `texture_filter` + `texture_repeat` 承担**（本次未直读官方迁移页，**标为待确认**；请以 `migrating/upgrading_to_godot_4.6.html` 为准）。

### C.3 相机跟随的像素抖动 vs `position_smoothing`

**根因（社区一致结论）**：`Camera2D.position_smoothing` 先做浮点插值，然后在绘制阶段取整到整像素，**每帧丢弃亚像素余量**——于是"平滑"变成了"整数跳变"，表现为相机 snap + 精灵边缘爬行。

证据：
- 官方 docs issue #7758「Camera2D avoid Jitter in pixel perfect games should be documented」：<https://github.com/godotengine/godot-docs/issues/7758>
- 引擎 issue #93048「Camera2D pixel position all over the place (jittery) in scaled subviewport with pixel snapping」：<https://github.com/godotengine/godot/issues/93048>
- 引擎 issue #95571「camera smoothing tilemap jitter」：<https://github.com/godotengine/godot/issues/95571>

**三种解法（按推荐度）**：

| 方案 | 做法 | 结论 |
|---|---|---|
| 自持高精度平滑位置 | 相机脚本里自己维护 `float` 累积位置，做 `lerp`/指数平滑，**只在最后一个渲染步骤**取整写入 `Camera2D.global_position` | **【可直接使用】** 最稳 |
| 用现成资产 `PixelPerfectSmoother` | MIT，脚本直接挂在 `Camera2D` 上，设置 `follow_target` 即可；它就是实现上面那件事 | **【可直接使用】** → [asset/4846](https://godotengine.org/asset-library/asset/4846) |
| `physics_interpolation` | 若相机/玩家在 `_physics_process` 更新，开 Project Settings → Physics → Common → Physics Interpolation | **【需改造】**，与像素吸附的交互需实测（[bugnet.io 指南](https://bugnet.io/blog/fix-camera2d-jittering-following-player-godot)） |
| 简单粗暴 `global_position = global_position.round()` | 每帧取整 | **【仅参考思路】**，会**加剧**低速度下的抖动（把余量直接丢光），只适合高倍缩放或快速移动 |

> **最容易被忽略的一点**：抖动往往不是相机的问题，而是**玩家/相机在不同 `_process` 频率里更新**。统一"物理更新 + 渲染插值"或"全部在 `_process`"比调平滑参数更有效。

### C.4 不同分辨率/宽高比下保持像素完美

| 策略 | 优点 | 缺点 | 结论 |
|---|---|---|---|
| **整数缩放 + 黑边**（`keep` + `integer`） | 绝对像素完美，无亚像素 | 宽屏机有黑边 | **【可直接使用】** 保守但正确 |
| **整数缩放 + `expand`** | 无黑边，超大宽高比时看到更多世界 | 存在官方 issue（#92055），需实测 | **【需改造】** |
| **动态视口**（按设备宽高比重算基准分辨率） | 无黑边且像素完美 | 实现复杂；不同设备"可视范围"不同，直接改变玩法平衡 | **【仅参考思路】** 对"搜打撤"要慎重（视野=战术优势） |
| **分数缩放** | 填满屏幕 | **必然破坏像素完美** | ❌ 不要用 |

**刘海屏 / 超宽比 / 圆角**：
- 用 `DisplayServer.get_display_safe_area()` 给 UI 留安全边距（摇杆、按钮不要贴死边缘）。
- 竖屏/横屏：不要锁死单一方向；**4.7 dev1 新增了 `DisplayServer` 设备方向变化信号**（官方博客），可以用来在旋转时重算安全区与摇杆布局。
- 超宽比（如 21:9）优先 `expand` + 把"关键 UI"锚定到安全区，而不是拉伸。

### C.5 现成像素完美相机插件

| 项目 | 授权 | 版本 | 结论 |
|---|---|---|---|
| **PixelPerfectSmoother** | **MIT** | Godot 4.x only（GDScript 2.0），更新 2026-03-02 | **【可直接使用】** <https://godotengine.org/asset-library/asset/4846> |
| `apples/godot-smooth-pixel-subviewport-container` | **待确认** | Godot 4 | 线索：<https://github.com/apples/godot-smooth-pixel-subviewport-container>（本次环境 DNS 限制无法直读核验授权） |
| `voithos/godot-smooth-pixel-camera-demo` | **待确认** | 待确认 | 线索（demo 性质） |

> Asset Library 按 "pixel perfect" 搜索目前**返回 0 条**（<https://godotengine.org/asset-library/asset?filter=pixel+perfect>），说明这类资产没被规范命名——搜索时用 "smooth camera" / "pixel" 更有效。**Godot 官方没有内置的"像素完美相机"节点**，必须自己处理或装插件。

---

## D. 移动端性能

### D.1 2D 渲染性能基线与优化手段

| 手段 | 说明 | 结论 |
|---|---|---|
| **合批（batching）** | 同一纹理、同一材质、同一混合状态的 `CanvasItem` 才能合批；每打断一次 = 一个 draw call | **【必做】** |
| **TextureAtlas** | 把大量小图打进一张图，是手机上最有效的 draw call 削减手段 | **【必做】** |
| **MultiMeshInstance2D** | 大量同款对象（子弹、粒子、弹壳、草）→ 一次调用 | **【必做】** |
| **TileMapLayer 分层** | 背景层/装饰层/碰撞层分开，减少无效重绘；TileSet 本身走一次绘制 | **【可直接使用】** |
| **避免每帧创建 Node** | `instantiate()` 峰值 = 帧率尖刺 | 见 D.3 |
| **可见性裁剪** | 屏幕外的 `CanvasItem` 用 `visible=false` 或 `VisibleOnScreenNotifier2D` 关掉逻辑 | **【必做】** |
| **draw call 数量监控** | `RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)` 显示在调试 HUD | **【可直接使用】** |
| **`Line2D` / 大量 `draw_*`** | 每次重绘都是独立绘制批次，慎用 | 【需改造】 |

手机 CPU 在"派发大量小 draw call"上比桌面弱得多，所以 **2D 游戏的瓶颈几乎总在 CPU/draw call，而不是填充率**（除非你们做全屏光照/shader）。

### D.2 图集（AtlasTexture）对移动端的重要性

- **为什么重要**：一次纹理切换 = 一次状态切换 = 可能打断合批。移动端 CPU 单核性能弱，draw call 是首要瓶颈。
- **Godot 4 的打包方式**：
  1. `TextureAtlas` 资源（编辑器内置的 Atlas 纹理工具）手工/程序化打图；
  2. 对 `SpriteFrames`，可在导入时基于一张 sprite sheet 切成 `AtlasTexture`；
  3. **TexturePacker 类外部工具**（第三方，非 Godot 官方）；
  4. 大型项目常自己写 `EditorScript` 做自动打图。
- ⚠️ **关键陷阱**：**同一张图集内所有图片必须有相同的压缩/导入设置**。混用会让 Godot 拆批，反而抵消图集收益（来源：[gtstu.com](https://gtstu.com/godot-4-optimize-android-ios/)，非官方但机制合理）。
- ⚠️ **VRAM 压缩**：项目设置 → Rendering → Textures → VRAM Compression → Import ETC2 ASTC 打开后，**必须重新导入**（删 `.godot/imported` 或 Export 对话框里 Fix Imports）。**像素游戏要注意**：ETC2/ASTC 对像素画是有损的，会糊边；像素游戏常选择**不压缩**（PNG 直出）以保锐利，代价是包体和显存。**这是像素项目必须做的取舍决策。**

### D.3 GDScript 性能注意事项

| 该避免 | 原因 | 替代 |
|---|---|---|
| 每帧 `get_node("...")` / `$Path` | 路径查找 + 字符串比较，纯浪费 | `@onready var x = $Path`，或在 `_ready()` 缓存引用 |
| 每帧 `instantiate()` | 分配 + `_ready` + 树插入，帧尖刺 | **对象池**（子弹、伤害数字、粒子） |
| 在 `_process` 做物理查询（`get_overlapping_bodies`、每帧 `RayCast` 强制更新） | 物理服务器开销大 | 降频（每 2~3 帧）、用 `Area2D` 信号驱动、用物理帧 |
| 大量信号连接/断开、`Array` 里频繁 `remove()` | 分配与搬移 | 用 `Dictionary` 或 swap-remove |
| 字符串拼接地做比较 | 每次比较都是 O(n) | `StringName` / 常量 / enum |
| 每帧 `array.sort()` | O(n log n) × 60fps | 增量维护有序结构 |
| `Vector2.distance_to()` 用于比较 | 多一次 sqrt | `distance_squared_to()`（论坛答案里就用到了） |
| 每帧 `new` 临时对象（`Vector2`/`Array`） | 移动端 GC/分配压力 | 复用变量 |

**何时需要 C# / GDExtension**：
- 只有当你**profile 证明瓶颈在 GDScript 执行时间**（Debugger → Profiler 里 script 时间占比高）时才需要。
- 高密度弹幕的逐帧弹道积分、大规模寻路、复杂程序化生成，是能真正吃满脚本层的三类场景。
- **GDExtension 的移动端代价**：必须为每个目标 ABI 交叉编译 `.so`（arm64-v8a / armeabi-v7a），并在导出预设里打包；**这会显著增加构建复杂度**。而 **C# 需要 `.NET` 版 Godot 导出**，包体和启动时间都会变差，在安卓上通常是**最后手段**。
- **先做数据导向的 GDScript 优化**（缓存、池化、降频）通常能解决 80% 的问题。

### D.4 Mobile 渲染器 vs Forward+（2D 场景）

| 渲染器 | 2D 场景适用性 | 关键取舍 |
|---|---|---|
| **Compatibility（`gl_compatibility`，OpenGL ES）** | **2D 游戏的推荐默认**。兼容设备最广（含低端机），OpenGL ES 在 2D 上通常比 Vulkan 更省电、驱动问题更少 | ❌ **无 compute shader** → `GPUParticles2D` **静默失效**（无报错！）。2D 射击的火光/血雾必须改用 `CPUParticles2D` 或自绘 |
| **Mobile（`mobile`，Vulkan / Metal）** | 想用 `GPUParticles2D`、或未来上 3D 时选 | 覆盖"2018 年后"的设备；老机驱动兼容性风险更高 |
| **Forward+（`forward_plus`）** | ❌ **不要用于移动导出**。它的设计目标是桌面，在移动 GPU 上未做优化 | — |

**关键技巧：按平台覆盖渲染器**
在 `project.godot` 里有第二个键：
```ini
[rendering]
renderer/rendering_method = "forward_plus"          # 桌面开发时用
renderer/rendering_method.mobile = "gl_compatibility" # Android/iOS 导出时自动切
```
来源：[gtstu.com](https://gtstu.com/godot-4-optimize-android-ios/)（第三方，但该键名与官方渲染器文档的写法一致；官方渲染器文档在 `tutorials/rendering/renderers.html`，**请以官方为准**）。

> 对你们的项目（纯 2D 像素俯视射击）：**Compatibility 优先**，除非必须 GPU 粒子。

### D.5 移动端常见性能陷阱

1. **每帧 `get_node`** → 缓存。
2. **`instantiate` 峰值**（弹幕爆发、尸体堆积）→ 对象池。
3. **物理查询开销** → 降频 / 事件驱动 / 用 `Area2D` 而不是全场景扫描。
4. **不做 frame rate 上限**：不锁帧会让手机跑满刷新率 → 发热 → 系统降频 → 反而掉帧。设 `Engine.max_fps = 60`；低端机档位设 30。
5. **编辑器性能 = 桌面 Forward+**，**绝不能用编辑器帧率推断手机表现**；必须在真机上 Profile。
6. **忘记重新导入纹理**导致 VRAM 压缩没生效。
7. **图集内混用导入设置**导致拆批。
8. **屏外对象仍跑逻辑**（AI/碰撞/动画）。
9. **`processing` 全开**：确认不需要 `_process` 的节点 `set_process(false)`。
10. **Godot 2D 的已知短板（直说）**：
    - 没有内置的像素完美相机、没有内置 aim assist、没有内置"移动端输入最佳实践"模板——这三件事都要自己写或找社区方案。
    - **4.7 之前连虚拟摇杆都要装插件**；4.7 才内置 `VirtualJoystick`（且 4.7 目前是 dev snapshot，稳定版发布日期见官方 release policy）。
    - Android 生态的 Gradle/AGP/SDK 版本跟随是持续负担（社区存在维护补丁发行版的仓库本身就说明了这点）。
    - `GPUParticles2D` 在 Compatibility 渲染器下静默失效 —— 这是会让开发者浪费半天排查的"无声坑"。

---

## 结论与推荐

### 技术选型（针对"安卓 2D 像素俯视射击 + 双摇杆"）

| 领域 | 推荐方案 | 状态 |
|---|---|---|
| **引擎版本** | **4.6.x 稳定版**（保守）/ 评估 **4.7**（原生 `VirtualJoystick`） | 决策点：是否愿为原生摇杆上 dev/beta |
| **摇杆** | 4.7 → 用内置 `VirtualJoystick`（`FOLLOWING` 模式给右摇杆）；4.6 → **Virtual Joystick DX**（MIT，功能最全，含 `DYNAMIC`/`FOLLOWING` + Active Region 天然支持双摇杆） | 【可直接使用】 |
| **按钮** | `Control` + 自绘（不要 `TouchScreenButton`） | 【可直接使用】 |
| **辅助瞄准** | 自己实现三件套：磁吸（角度锥 + 距离衰减）+ 减速 + 子弹轻微偏转；论坛脚本可作起点 | 【可直接使用】首版 |
| **像素完美** | `canvas_items` + `integer` + `keep`；相机用 **PixelPerfectSmoother**（MIT）或自写高精度平滑 | 【可直接使用】 |
| **渲染器** | Compatibility（2D 首选），用 `rendering_method.mobile` 覆盖；**若用 GPUParticles2D 则切 Mobile** | 【可直接使用】 |
| **纹理** | 全局 Nearest；图集统一导入设置；像素画**评估是否真的要开 ETC2/ASTC**（有损） | 需取舍 |
| **导出** | JDK 17 + Android SDK + `Install Android Build Template` + arm64-v8a AAB；**立刻备份 release keystore** | 【可直接使用】 |
| **性能** | `Engine.max_fps = 60`（低端 30）；对象池；`@onready` 缓存；`distance_squared_to` | 【可直接使用】 |
| **真机调试** | 一键部署 + adb logcat + Debugger Profiler；4.6+ 可上 Perfetto | 【可直接使用】 |

### 需要立刻验证的 4 件事（我无法在本次调研中确认，请勿跳过）

1. **`aspect=expand` + `scale_mode=integer` 的实际行为** —— 有官方 issue [#92055](https://github.com/godotengine/godot/issues/92055)，必须实机验证后再决定用 `keep` 还是 `expand`。
2. **Google Play 当前 targetSdk 要求** —— 抓取失败，请直接打开 <https://support.google.com/googleplay/android-developer/answer/11926878> 核对；这是唯一会导致拒审的合规项。
3. **你所用 Godot 版本导出预设里 `Min SDK` 的默认值** —— 目标写 24，但请以预设 UI 实际值 + 官方导出文档为准。
4. **Compatibility 渲染器下你们的粒子方案** —— 若依赖 `GPUParticles2D`，必须切 Mobile 或换 `CPUParticles2D`，否则"枪口火光不显示且不报错"。

### 一句话总结

Godot 4 做安卓 2D 像素射击**完全可行**，但"移动端必须的那几块"（虚拟摇杆、像素完美相机、aim assist、多分辨率策略）**绝大部分得自己搭或依赖社区资产**——官方只在 4.7 才补上摇杆这一块。真正会让项目卡住的是**安卓工具链版本地狱**和**像素完美的相机抖动**，不是引擎的 2D 能力上限。

---

## 附：本次调研实际访问到的关键 URL

**官方（Godot Engine / Godot Foundation）**
- Android 导出文档：<https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html>
- 多分辨率与 stretch 设置：<https://docs.godotengine.org/en/stable/tutorials/rendering/multiple_resolutions.html>
- 渲染器对比：<https://docs.godotengine.org/en/stable/tutorials/rendering/renderers.html>
- `TouchScreenButton` 类参考：<https://docs.godotengine.org/en/stable/classes/class_touchscreenbutton.html>
- `VirtualJoystick` 类参考（4.7+）：<https://docs.godotengine.org/en/stable/classes/class_virtualjoystick.html> ／ <https://docs.godotengine.org/zh-cn/4.x/classes/class_virtualjoystick.html>
- `Camera2D` 类参考：<https://docs.godotengine.org/en/4.4/classes/class_camera2d.html>
- 2D 抗锯齿：<https://docs.godotengine.org/en/stable/tutorials/2d/2d_antialiasing.html>
- **Godot 4.7 dev 1 发布说明（`VirtualJoystick` 三模式原始定义）**：<https://godotengine.org/article/dev-snapshot-godot-4-7-dev-1/>
- 官方 Asset Library 摇杆检索：<https://godotengine.org/asset-library/asset?filter=joystick>
- Asset Library 资产页：[Virtual Joystick DX](https://www.godotengine.org/asset-library/asset/5256)、[Virtual Joystick CF](https://godotengine.org/asset-library/asset/4891)、[Virtual Joystick Plus](https://godotengine.org/asset-library/asset/4458)、[Virtual Joystick (MarcoFazio)](https://godotengine.org/asset-library/asset/1787)、[PixelPerfectSmoother](https://godotengine.org/asset-library/asset/4846)

**官方 issue / 提案（GitHub）**
- [#92055 expand + integer 异常](https://github.com/godotengine/godot/issues/92055)
- [#93048 缩放子视口 + 像素吸附下 Camera2D 抖动](https://github.com/godotengine/godot/issues/93048)
- [#95571 相机平滑导致 TileMap 抖动](https://github.com/godotengine/godot/issues/95571)
- [godot-docs#7758 Camera2D 像素完美抖动应写入文档](https://github.com/godotengine/godot-docs/issues/7758)
- [#110933 `VirtualJoystick` PR](https://github.com/godotengine/godot/pull/110933)｜[提案 #11192](https://github.com/godotengine/godot-proposals/issues/11192)

**社区（非官方，已标注）**
- Godot 论坛 aim assist 实现：<https://forum.godotengine.org/t/how-to-create-a-aim-assist-auto-aim-in-godot-4-4/121083>
- Camera2D 抖动修复指南：<https://bugnet.io/blog/fix-camera2d-jittering-following-player-godot>
- Godot 4 安卓导出实测指南：<https://www.summerengine.com/blog/export-game-android-godot>
- Godot 4 移动优化指南：<https://gtstu.com/godot-4-optimize-android-ios/>
- `VirtualJoystick` 4.7 中文/德文介绍：<https://dev.to/ziva/virtualjoystick-in-godot-47-endlich-ein-nativer-touchscreen-stick-1enb>
- Android SDK 35 补丁版 Godot：<https://github.com/shipth-is/godot-android-sdk-upgrade>

**Google Play 政策（本次抓取失败，务必自行打开）**
- <https://support.google.com/googleplay/android-developer/answer/11926878>
