# AGENTS.md —— 在这个仓库里干活的规则

> **任何 agent（DSH 的 Lead/teammate、WorkBuddy、或人）动手之前先读这一份。**
> 项目背景见 [specs/](specs/)；B→A→C 路线见 [roadmap-bac.md](specs/roadmap-bac.md)。
>
> 🆕 **刚接手这个项目？先读 [specs/session-handoff.md](specs/session-handoff.md)**
> —— 那是「上一轮到哪了、哪些没验证、下一步做什么」的交接。

---

## 0. 一句话

**搜打撤**（2D 像素俯视角撤离射击）· Godot 4.7.2 · GDScript · 安卓 + PC。
非商业、免费发布、**MIT**、代码开源。

### 工作区位置与**可移植性约定**

```
当前工作区：D:\AAAASDC          （原 D:\aaaaadsh 保留为备份，未删除）
工具链：    <项目根>\_install\   （Godot 二进制 + Python + TEMP + 音频素材）
```

⭐ **所有脚本必须相对项目自身定位，不许写死盘符。**

这条不是洁癖 —— 这个工作区是给「人 + DSH + WorkBuddy」共用的。
写死 `D:\AAAASDC\...` 的话，任何人把仓库克隆/移动到别处，验收就全废。

**正确写法**：

```powershell
# PowerShell：脚本在 tools/ 下 -> 项目根是上一级
$Root  = Split-Path -Parent $PSScriptRoot
$Godot = Join-Path $Root "_install\godot\Godot_v4.7.2-stable_win64_console.exe"
```

```python
# Python：脚本在 tools/audio/ 下 -> 项目根是上两级
PROJ = Path(__file__).resolve().parents[2]
SFX  = PROJ / "_install" / "sfx"
```

`tools\verify_all.ps1` 已按这个原则改过 —— 它在任何位置都能跑，
且会自己找 `_install/` 与 Python。**新增脚本照这个写法，不要引入新的绝对路径。**

> 迁移时已核实：在 `D:\AAAASDC` 从零重建 `.godot` 后，
> 验收退出码 0（799 项单测 + 51 项集成 + 数据契约全过），游戏窗口正常启动。

---

## 1. ⭐ 验收：只有一条命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\verify_all.ps1
```

**退出码 0 = 可以交付；非 0 = 不许交付。**

它跑四件事：

| # | 项 | 规模 | 抓什么 | 是门槛吗 |
|---|---|---|---|---|
| ① | 单元测试 | **847 项断言**（会随套件增长） | 逻辑正确性（headless，秒级） | ✅ **是** |
| ② | 集成验证 | **51 项** | 零件装到游戏里还转不转（真的实例化场景） | ✅ **是** |
| ③ | 数据契约 | JSON schema | 数据表与跨表引用 | ✅ **是** |
| ④ | 像素基线 | 固定种子截图 | 画面被明显改动 | ⚠️ **否，仅供参考**（`-Strict` 才当门槛） |

**为什么要固化成一条命令**：多 agent 协作最大的风险不是写不出代码，
是**"done" 的定义不一致** —— A 觉得跑过了、B 觉得没跑，最后谁都不知道能不能交。
把验收变成「一条命令 + 一个退出码」之后，这件事不需要信任，只需要执行。

> ⚠️ **不许只跑其中一项就说"过了"。** 更不许"看起来没问题"就交。

### ⚠️ 为什么 ④ 像素基线**曾经**不是门槛 —— 🔴 **已在 W-00 修好，现在可以用了**

> 🔴 **2026-10-12 更正（W-00）**：下面那段把"运行期不确定"归因于 hitstop 的墙钟，
> **实测证明主因不是它，而是验收工具自己的两个 bug**：
>
> 1. **`--hide-hud` 静默失效** —— HUD 是 `raid_scene._ready()` 里才 new 出来的，
>    `_initialize` 里 `get("raid_hud")` 还是 **null**，那次 hide 什么也没做。
>    于是 HUD 那行 `FPS %d **平均 %.1f ms** 最慢 %.1f ms`（**墙钟读数**）
>    进了"世界像素基线" —— 所谓 0.018% "帧时序噪声"的真身就是它。
> 2. **`_mouse_aiming()` 读操作系统的鼠标速度** —— 验收跑在真窗口里，
>    **只要有人在动鼠标**，视野锥就整块变（差 5%~7%），而模拟状态一字不差。
>
> 两条修掉之后：`verify_all.ps1` 的 ④ 是
> 「自身复现性：**同构建两次截图完全一致**」+「与基线一致：**逐像素完全一致**」。
> **所以 ④ 现在可以当粗粒度回归门用了**（是否 `-Strict` 仍维持现状）。
> ⚠️ 跑验收时**别动鼠标**；需要严格比较用 `tools\check_determinism.ps1`（它把鼠标瞄准钉住）。
>
> hitstop 的墙钟问题**是真的**（单位级实测：同一个 120ms 请求，旧实现紧凑循环冻
> **251104 帧**、每帧 +3ms 冻 **29 帧**；新实现两种都 **8 帧**），已改成帧计数。
> 完整证据 / 未验证项见 [specs/w00-determinism.md](specs/w00-determinism.md)。

**（以下为原文，保留作为"判断 → 被证伪"的记录）**

**这局游戏运行期曾被判定为本质不确定。** 同种子、同参数、同 `--fixed-fps 60` 连跑 4 次：

```
第 30 帧   ✅ 5/5 对完全一致        <- 早期是确定的
第 60 帧   ⚠️ 4/5 对不一致 (0.04%)
第 120 帧  ⚠️ 5/5 对不一致 (0.03~0.06%)
第 300 帧  ⚠️ 3~5/5 对不一致 (2~7%)  <- 混沌放大
```

**根因**：「手感」用了**真实时钟** —— `feel/feel.gd` 的 hitstop 靠
`Time.get_ticks_msec()` 把 `Engine.time_scale` 压到 0。
而 `time_scale = 0` 时 `delta` 也是 0，**游戏没法用模拟时间给自己计时**，
只能用真实时钟 → 停顿帧数随真实耗时浮动 → 模拟推进量不同 → 混沌放大。

**所以：会飘的门比没有门更糟**（它训练人忽略失败）。
④ 保留为**咨询性**，并顺带做「同一构建连跑两次自身比对」——
那比"和基线比"更有意义，它直接测出本环境的随机性有多大。

> 📌 **同时纠正一个早先的说法**：拆分 `raid_scene.gd` 时，我用 1v1 截图对比
> 声称过「逐像素完全一致，零视觉回归」。那些对比**当时确实通过了**，
> 但在这个随机性面前，**单次对比不构成证据**。
> **唯一可靠的那条是地图烘焙** —— 它用的是确定性单测
> （`RaidMapBaker` 输出 vs `WhiteboxPainter.paint()`，3 个种子差异均为 0），
> 完全不依赖运行期时序。

### ✅ 想让像素比对真正可用，需要先修的东西 —— **W-00 已全部修完（2026-10-12）**

原文要求：把 `feel.gd` 的 hitstop 从真实时钟改成帧计数。**已做**，并且顺带查出
上面那两条验收工具 bug（`--hide-hud` 静默失效 / 鼠标瞄准泄漏）。
现在 ④ 的自身复现性是**逐像素完全一致**，可以当粗粒度回归门。

专项验收命令（新增）：`tools\check_determinism.ps1`
（4 场景 × 4 次、容差 0；`-HitstopEvery 12` 是 25 次冻结的"顿帧风暴"用例）

---

## 2. 文件归属：谁能改什么

`raid_scene.gd` 曾是 1676 行的上帝对象、50% 的提交都要碰它。
现已拆成「协调者 + 5 个模块」，**这正是为了让人/agent 能并行开工**。

### ✅ 可并行（互不冲突）

| 范围 | 说明 |
|---|---|
| `data/*.json` | 内容填充（武器/物品/敌人/掉落表）。改完必须跑 ③ |
| `tools/`, `art/` | Python 管线与生成产物，与游戏代码零耦合 |
| **`test/suites/*.gd`** | ⭐ **新增一个文件即可，不需要改任何公共文件**（自动发现） |
| `view/raid_hud.gd` | HUD 文本 / toast / 尸体提示 |
| `view/raid_drawer.gd` | 全部世界绘制 |
| `view/raid_map_baker.gd` | 地图烘焙（纯图像生成，可 headless 单测） |
| `view/raid_input.gd` | 键盘键位分派 |
| `view/raid_sim_runner.gd` | 玩家/敌人 tick、自动瞄准、开火 —— **AI / 战斗手感调参在这里** |
| `ui/*.gd` | 独立面板（彼此不引用） |
| `sim/**/*.gd` | 模拟层模块（注意：`sim/` 内部仍要避免两人改同一文件） |

### ❌ 必须单一作者

| 文件 | 为什么 |
|---|---|
| `view/raid_scene.gd` | 仍是协调者：场景搭建、UI 胶水、面板接线 |
| `test/run_tests.gd` | 框架守卫与调度。**新增测试不需要碰它** —— 碰它说明你在改框架，要特别小心 |
| `test/test_kit.gd`, `test/suite_base.gd` | 所有套件共用，改一处影响全部 |
| 手感参数（hitstop / trauma / 后坐力 / 屏幕震动） | 这是**审美判断**，多人同时调只会互相打架 |

### 写入范围约定

**开始一个任务前，先在 [specs/workboard.md](specs/workboard.md) 上写下"我只会改哪些文件"。**
如果两个任务的范围有重叠 —— **停下来，改成串行，或者重新切分**。
写入范围是**约定**，不是锁（没有机制强制），所以靠的是先声明。

---

## 3. 提交前必须做的事

1. **跑 `tools\verify_all.ps1`**，退出码必须是 0（①②③ 是门槛）
2. 改纯逻辑可以加 `-Fast` 跳过 ④；改画面就全量跑，看清 ④ 的报告
3. ④ 是咨询性的。**如果你有意改了画面**，复核截图后跑 `-UpdateBaseline`，
   并在提交信息里**说明为什么**（"基线被我重设了" 是一句需要解释的话）
4. 在 workboard 上把任务标记完成，附上退出码
5. ⭐ **任务「完成」或「中断」时，都必须写交接**（用户明确要求）：
   更新 [specs/session-handoff.md](specs/session-handoff.md) 顶部，写清
   **① 一句话状态 ② 改了哪些文件（别人别碰） ③ 复跑命令 ④ 没验证的 ⑤ 下一步**。
   中断也要写 —— 半成品比没开工更需要交接。**只写结论，不写思考过程。**
   **deliberate 的例外必须用户明确批准**（见 §4.5），不得静默豁免。
6. ⭐ **声称"某功能在构建里 / 在包里"之前，先打开产物核对一次**（2026-10-13 加的规矩）。
   来历：`git log` 里有 ≠ 你跑的那个产物里有。实测做法 —— 导出 APK 后用 `zipfile` 数 `.gdc`
   （15/15 命中才算数）；改脚本后用 `godot --headless --check-only --script res://<file>` 逐文件解析。
7. ⭐ **`git clang-format` 的精神**：只对你**改动的部分**负责，不许顺手重排整个文件
   （我们的等价物：补丁要小、别把无关段落一起改了）。

> ⚠️ **像素基线现在可以用了，但仍别用它证明"没改坏"。**
> 它抓的是"明显改动"，细粒度回归靠 ①②。另外**跑验收时别动鼠标**
> （`_mouse_aiming()` 读操作系统鼠标速度，会整块改变视野锥）。

### ⚠️ 关于「源码文本断言」

项目里有一批 `_check(src.contains("..."))` 用来防代码回流。
**它们把「代码在哪」和「代码对不对」绑在了一起** ——
拆分上帝对象的过程中，这类断言失效了 **6 次**。

所以写这类断言时分两类：

| 类型 | 例子 | 怎么写 |
|---|---|---|
| **行为存在** | "自动射击看 visible 不看锁定粘性" | 用 `_view_src()` 查整个视图层 —— 层内怎么搬都不误报 |
| **结构关系** | "场景必须委托、不许自己长回来" | 查**具体文件** —— 这正是防回流要盯的 |

`_view_src()` 定义在 [suite_base.gd](test/suite_base.gd)。

---

## 4. 已知的坑（都踩过，别再踩）

### 环境
- **Godot 子进程写不了 `user://`**（沙箱）—— 存档走 `SaveManager._resolve_path()` 的回退
- **Windows PowerShell 5.1 不带 BOM 就按 ANSI 读 `.ps1`** —— 中文会变乱码并让解析器崩。
  ⚠️ **W-00 实测又踩了两次**：**编辑工具保存时会去掉 BOM**，于是
  `tools\check_determinism.ps1` 一保存就"坏"，报的还是完全指不到 BOM 的错
  （`Missing expression after ','` / 字符串没有结束符）。**改完 `.ps1` 必须补 BOM 并自检**：
  ```powershell
  $p='tools\x.ps1'; $b=[System.IO.File]::ReadAllBytes($p)
  if (-not ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) {
      [System.IO.File]::WriteAllBytes($p, ([byte[]](0xEF,0xBB,0xBF)) + $b) }
  $errs=$null; $null=[System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$null,[ref]$errs)
  if($errs.Count){$errs[0].Message}else{'PARSE OK'}
  ```
  现有 `_test_project_hygiene` 只查 `.gd/.json/.cfg/.godot/.tscn/.tres`，**恰好漏了 `.ps1`**。
  另外**加载 `.gd` 时也别用 `Set-Content` 管道**（会把 UTF-8 中文写成乱码，
  WorkBuddy 的 `s11_adversarial.gd` 就这么坏过一次）—— 要原样复制就用 `cmd /c "git show ... > file"`。
- **别在 PowerShell here-string 里嵌 Python** —— 引号会被吃、`$` 会被插值。
  写成独立 `.py` 文件（`tools/compare_images.py` 就是因此拆出来的）
- **Godot 每次启动都往 stderr 写两条无害提示**（`user://logs/godot.log`、根证书库）——
  驱动它要**看退出码**，别用 `$ErrorActionPreference = "Stop"`

### GDScript
- **`Perfomance.TIME_PROCESS` 在安卓上不可靠** —— 用墙钟 `Time.get_ticks_usec()`
  （这个坑踩了两次：先修遥测、漏了 HUD）
- **对带锚点的 `Control` 直接赋 `size`** 会被锚点覆盖并打警告 ——
  用「零锚点 + `_fit_viewport()` 手动钉尺寸 + 监听 `size_changed`」
- **`:=` 类型推断在 Variant 链上会连环失败** —— 访问 duck-typed 的 `scene.xxx` 时用无类型 `var`
- **`get_tree().paused` 会连输入一起门控** —— 用纯逻辑冻结（`Game.paused`）
- **typed array 不能赋普通 Array**（`LootTableDef.entries`）—— 要 `clear()` + `append()`

### 工具
- **`Image.getbbox()` 在 RGBA 图上以 alpha 当掩码** ——
  截图差值图 alpha 恒为 0，它会报「没有差异」。
  **实测把玩家从蓝改红（66926 像素真的变了）仍然报一致** ——
  这是"测试说 OK"最危险的形式。用 `tools/compare_images.py`（numpy 在 RGB 上比）

### 测试框架
- **`run_tests.gd` 会拦住"定义了却没注册"的测试函数**。
  这是有来历的：拆分前发现 **4 个 `_test_*` 从未注册**（89 行静默不执行），
  其中**一个一直是坏的**，只因为从不执行才没暴露

---

## 4.5 2026-10-13 新增的规矩（来自一次引擎调研的对照）

### 本机环境特殊性（换机请重看）

- **`git` 连不上 GitHub（schannel）**：报 `SEC_E_NO_CREDENTIALS (0x8009030e)`。
  加 `-c http.sslBackend=openssl` 可解。另外 **push 必须由拥有者在自己的终端执行** ——
  沙箱内进程不能建命名管道，凭据助手起不来（`couldn't create signal pipe, Win32 error 5`）。
- **`verify_all.ps1` 找 Python 的路径与本机实际差一层**：脚本找 `%LOCALAPPDATA%\dsh\...`，
  实际在 `C:\Users\<用户>\.dsh\dsh-runtimes\...`。用 junction 补：
  `mklink /J _install\python <实际路径>`。
- **`art\_raw\` 必须存在**：它被 `.gitignore` 排除、新克隆里没有，而 `Image.save_png()` **不会自建父目录**
  -> 截图静默失败（err 7）。跑 ④ 前先 `New-Item -ItemType Directory -Force art\_raw`。
- **Android 导出**：模板只需 `android_debug.apk` / `android_release.apk` / `version.txt`；
  **`platform-tools` 必装**（哪怕 `use_gradle_build=false`，Godot 的导出校验仍会去找 adb）。
  完整 recipe 见 [specs/android-export.md](specs/android-export.md)。

### `.godot/` 导入缓存是真实故障模式

新脚本 / 新资源之后仍报古怪的 Parse 或"找不到类"，**先删 `.godot/` 重新扫描，再查代码**。
来历：`art\_raw` 缺失导致截图失败、`.uid` 由引擎生成、`class_name` 靠 `global_script_class_cache.cfg` 解析 ——
这三件事都是**文件系统/缓存状态**，不是代码逻辑。

### 卡住时的五步（排查手册）

1. **先查契约，再猜** —— 先看函数签名与文档，别猜引擎行为。
2. **尽早打开"验证层"** —— Godot 的等价物是 `godot --headless --check-only --script res://<file>`
   （逐文件解析、给出确切行号；这次就是靠它抓出 `_aim_push` 那处）。它慢，只在短跑里用。
3. **先做最小复现** —— 写一个 `test/*_probe.gd`（headless 能跑），绕开场景与全局状态。
4. **先排除上游层** —— 先确认是"我们的脚本"还是"引擎/缓存（`.godot/`）"，再往下挖。
5. **不凭记忆断言** —— 不信"Godot 应该会…"，跑一遍看**退出码与原文**。

### 单一真相源：一个可变事实，只有一个所有者

| 事实 | 唯一所有者 |
|---|---|
| 玩家实际受到的伤害 | `RaidScene._resolve_player_hit` |
| 人物判定身位 | `BodyMetrics`（弹道半宽 / 闪避距离全部由它推导） |
| 存档格式与迁移 | `SaveManager.SAVE_VERSION` + `migrate()` |
| 验收 = 可交付 | `tools/verify_all.ps1` 的退出码 |

新增一处可变事实时，**先指名它的所有者**，再写代码。

### 新的兜底 / TODO 必须写「移除条件」

新的 `TODO` / `HACK` / `FALLBACK` / 豁免清单，都要写清**原因 + 移除条件（或到期）**；
不许为了兼容制造第二个真相源。
**已补（2026-10-13）**：`EnemyAgent._fire_at` 的"无弹道管理器时的兼容结算"、
`PlayerAutopilot._step_dir` 的"流场拿不到方向的直线兜底"——两处都写明了各自的移除条件。
同理，`pre_push_check.ps1` 里那 4 个探针豁免也带着理由（不是静默跳过）。

### 同时开火节流（B 方案）的调参口径

`sim/combat/lane_shot_manager.gd` 的令牌桶（`SPAWN_RATE` 条/秒 + `SPAWN_BURST` 瞬时）决定**入射量**。
它必须与最大闪避频率（`1 / DodgeState.COOLDOWN` ≈ **1.18 次/秒**）同量级 ——
否则"躲得开"又从数学上不成立。改这两个常量请连着真机复核（`specs/feel-tuning.md` 有实测表）。

### 视觉证据三条纪律

1. 截图必须由**引擎自己写文件**（不要拿窗口/系统截图当视觉正确性证据）；
2. **写出后要断言文件存在** —— 目标目录不存在时 `save_png` 会静默失败（err 7），
   而验收脚本会把"没图"读成"首次运行"（2026-10-13 已修：现在判【无效】）；
3. 比对必须在 **RGB** 上做（`tools/compare_images.py`），不要用 `ImageChops...getbbox()`。

### 大文件阈值：超过 ~1000 行 = 单作者文件

`.gd` 超过约 1000 行就该**按既有分节拆成多个文件（纯搬运、不改行为）**，而不是继续往里加方法。
现状（2026-10-13 两刀之后）：`view/raid_scene.gd` **≈1018 行** ——
第一刀把「玩家动作」（闪避 / 自动作战开关 / 冻结判定）切到 `view/raid_player_actions.gd`，
第二刀把「搜刮交互」（开面板 / 容器视图 / 面板动作）切到 `view/raid_loot_actions.gd`，两刀都是纯搬运、行为零改动。
**它仍在阈值之上**，第三刀的自然切法是伤害/护甲结算（`_resolve_player_hit` / `_player_armor` /
`_weapon_wear_factor`）—— ⚠️ 搬它必须同步改 `test/suites/s20_round7_fixes.gd` 的两条源码断言。
其余：`view/raid_sim_runner.gd` ≈ 530、`ui/touch_controls.gd` ≈ 263。

### 例外必须用户批准

交接里若有 **deliberate 的例外**（某个门槛故意没跑、某个规矩故意没守），**必须由用户明确批准**，
agent 不得静默豁免。

## 5. 红线（不可谈判）

- ❌ **不申请 `INTERNET` 权限、零网络调用**（已用 `aapt2 dump permissions` 验证）
- ❌ **零变现**
- ✅ **MIT**，代码开源（2026-10-13 拥有者拍板，取代原 GPL-3.0 红线；远端仓库
  `github.com/gungnior/SDCgame` 建库时选的 MIT。连带影响：MIT 兼容 GPL 代码但
  GPL-2.0-only 仍禁用，见 [specs/third-party.md](specs/third-party.md) R-06）
- ❌ **不使用商业游戏素材**
- ❌ **不使用 `Jhon-Crow/godot-topdown-MVP` 的代码**
- ❌ **不使用 `CC-BY-NC-ND` 素材**

---

## 6. 报告风格

用户明确要求：**不用反馈思考过程，直接汇报结果**。
所以报告里放：**命令原文 + 原始输出 + 结论**，不要放"我考虑了一下…"。

**没跑过的就别写"通过"。** 无法复现的条目直接写「无法复现」。
