# W-00 报告 —— 让模拟可复现（hitstop 帧计数）

> 执行：DSH-Lead，本会话（起点 HEAD `71a25f8`，工作区 `D:\AAAASDC`）
> 验收命令：`powershell -NoProfile -ExecutionPolicy Bypass -File tools\verify_all.ps1` → **退出码 0**
> 专项验收：`tools\check_determinism.ps1`（新增）

---

## 0. 一句话结论

**W-00 做完了，但根因和 workboard 上写的不一样 —— 而且比它写的更严重。**

1. `feel.gd` 的 hitstop 确实用**墙钟**决定冻结时长（真 bug，已改成帧计数）：
   实测同一个 `hitstop(120ms)` 请求，旧实现冻结 **251104 帧**（紧凑循环）vs **29 帧**（每帧 +3ms）——
   **同一份代码、同一个请求，差 8660 倍，只因为机器快慢不同**。新实现两种节奏都是 **8 帧**。
2. **但 AGENTS.md / session-handoff 里"第 300 帧 2~7% 不一致"的数字，主因不是 hitstop。**
   它是**验收工具自己的两个 bug**：
   - **`--hide-hud` 静默失效** —— HUD 里那行 `FPS %d 平均 %.1f ms` 是**墙钟读数**，被当成"世界像素"在比；
   - **鼠标瞄准泄漏** —— `_mouse_aiming()` 读操作系统的鼠标速度，**验收时有人动鼠标，视野锥就整块变**。
   两条都修掉之后：`verify_all.ps1` 的 ④ 从
   「两次截图不一致（0.43%~5.36%）」变成「**同构建两次截图完全一致**」，
   而且「与基线一致：**逐像素完全一致**」。

> ⚠️ 也就是说：**"这局游戏运行期本质不确定"这个结论是错的**（至少在这里可复现的范围内）。
> 它是"会撒谎的验收工具"造出来的 —— 正是本项目一直在防的那类问题。

---

## 1. 证据：修之前到底差在哪

### 1.1 默认局面：差异全部来自 HUD 的墙钟读数

4 次运行（种子 424242 / 第 300 帧 / `--hide-hud`），6 对比较：

```
run_1 run_2  逐像素完全一致
run_1 run_3  有差异 166 像素 (0.0180%)，区域 x[363..376] y[274..291]
run_2 run_3  有差异 166 像素 (0.0180%)，区域 x[363..376] y[274..291]
（其余 3 对一致）
```

把差异区域放大 8 倍看一眼 —— **是一行文字，不是一个实体**：

- 放大图显示左边是 `8.5`、右边是 `8.7`；
- 对照 `view/raid_hud.gd:136`：`"FPS %d  平均 %.1f ms  最慢 %.1f ms  敌 %d  音频掉 %d"`。

**根因**（`test/screenshot.gd` 与我的探针都中招）：

```gdscript
_scene = ps.instantiate()
root.add_child(_scene)          # <- 这一刻 raid_hud 还是 null
if _hide_hud:
    var hud = _scene.get("raid_hud")
    if hud != null: hud.visible = false     # <- 静默跳过！
```

HUD 是 `raid_scene._ready() -> _setup_view()` 里才 `RaidHud.new()` 的，
`_initialize` 里 `get("raid_hud")` 返回 **null**，那次 hide **什么也没做**。
而 HUD 一直显示到截图帧 —— 于是**墙钟读数进了"世界像素基线"**。

日志原文（探针的 `PROBE_DIAG`）：

```
PROBE_DIAG hud_arg=raid_hud node=null visible=n/a      <- _initialize：还不存在
PROBE_HEAD seed=424242 frames=5 hide_hud=true ...
PROBE_DIAG hud_arg=raid_hud node=@CanvasLayer@39 visible=true   <- 截图帧：一直是可见的
```

改成**每帧都藏**之后，同一实验：

```
run_1 run_2  逐像素完全一致
run_1 run_3  逐像素完全一致
run_1 run_4  逐像素完全一致
run_2 run_3  逐像素完全一致
run_2 run_4  逐像素完全一致
run_3 run_4  逐像素完全一致
✅ 可复现：6 对比较全部逐像素完全一致
```

> 这就是 AGENTS.md 里那句「~0.02% 的帧时序噪声」的真身：
> **它不是噪声，是一条 HUD 文本**。

### 1.2 第二条通道：鼠标瞄准（外部输入进模拟）

修掉 HUD 之后，4 次里仍有 1 次差 **6.66%**：

```
run_1  aim=(1.000,0.000)   sim_time=5.0125
run_2  aim=(-0.256,-0.967) sim_time=5.0125      <- 只有 aim 变了
run_3  aim=(1.000,0.000)   sim_time=5.0125
run_4  aim=(1.000,0.000)   sim_time=5.0125
⚠️ 状态分叉 run_1 vs run_2 -> 第一个不同字段：aim_x: 1.0 vs -0.2558937669
run_1 run_2  有差异 61424 像素 (6.6649%)，区域 x[438..767] y[0..471]
```

`sim_time`、`rng_state`、所有实体位置**完全相同**，只有 `player_aim` 变了。查到：

```gdscript
# view/raid_scene.gd
func _mouse_aiming() -> bool:
	if DisplayServer.is_touchscreen_available(): return false
	return Input.get_last_mouse_velocity().length() > 1.0     # <- 操作系统状态
```

验收跑在**真窗口**里：**只要有人在动鼠标**（或窗口出现时系统给了一次移动事件），
瞄准方向就变 → 视野锥整块变 → 5%~7% 像素差。

**处理**：加了 `allow_mouse_aim`（默认 `true`，正常游玩零变化），
验收探针把它设成 `false` —— **固定输入才能比较两次运行**。

### 1.3 hitstop 本身：墙钟 -> 冻结帧数由机器速度决定

`tools/check_determinism.ps1 -HitstopFrame 150` 让第 150 帧触发一次 hitstop。
但**单位级**才看得清（跑旧的 `feel.gd` 与新的各一遍，同样的 `hitstop(120ms)`）：

```
FRAME_CHECK 单次 hitstop(120ms) 的冻结帧数：
  RESULT 旧(墙钟ms)    紧凑循环 =   251104 帧      每帧+3ms =    29 帧
  RESULT 新(帧计数)     紧凑循环 =        8 帧      每帧+3ms =     8 帧
```

命令（旧文件从 git 取，不用改工作树）：

```powershell
cmd /c "git show HEAD:feel/feel.gd > _install\tmp\det\old_feel.gd"
godot --headless --path . --script res://_install/tmp/det/frame_check.gd
```

**这就是"bug 报告无法从种子复现"的机制**：冻结时长不是常数，是机器速度的函数。
（注：稳态 60fps 下旧实现也是 ~8 帧，所以它不是"每次都差"，而是
**只要有一帧慢/快就漂** —— 而这正是 300 帧尺度上混沌放大的入口。）

---

## 2. 改了什么

| 文件 | 改动 |
|---|---|
| `feel/feel.gd` | hitstop/受伤闪白冷却/频率配额 全部由**墙钟 ms** 改**帧计数**（60fps 基准）；新增 `_end_hitstop()`；`reset()` / 无障碍开关语义保持 |
| `view/raid_scene.gd` | 新增 `allow_mouse_aim`（默认 true），`_mouse_aiming()` 遵它 |
| `test/suites/s06_feel_audio.gd` | 4 处依赖墙钟等时的断言改成**喂帧**；新增 ⑥「冻结帧数与机器快慢无关」 |
| `test/screenshot.gd` | `--hide-hud` 改**每帧**都藏（原来静默失效） |
| `tools/determinism_probe.gd` | **新增**：截图 + 模拟状态指纹（30 个字段，含 RNG 游标 / aim / 相机） |
| `tools/determinism_check.py` | **新增**：N 次两两比对 + **定位第一个分叉字段** |
| `tools/check_determinism.ps1` | **新增**：W-00 验收命令 |

**帧换算**（60fps 基准，`ceil` 是为了对齐旧实现实测观感）：

| 项 | 旧（墙钟） | 新（帧） |
|---|---|---|
| hitstop 60ms | 60ms | 4 帧 |
| hitstop 120ms 上限 | 120ms | 8 帧 |
| hitstop 最小间隔 | 110ms | 7 帧 |
| 受伤闪白冷却 | 180ms | 11 帧 |

`Engine.time_scale = 0` 仍然照压 —— **"冻结期间世界不动"的观感没变**，
变的只是"冻多久"由常数决定。

### ⚠️ 顺手修正了 workboard 里 W-00 的两条判断

1. **"同参数连跑 4 次、第 300 帧 5 对全一致"** 这条验收标准本身**不足以验 W-00** ——
   默认局面 `kills=0 / bullets=0 / hitstop=0`，**它根本不触发 hitstop**。
   所以 `check_determinism.ps1` 加了 `-HitstopFrame`（单次）与 `-HitstopEvery`（顿帧风暴）。
2. 探针必须**每帧**藏 HUD、并在 `RenderingServer.frame_post_draw` 里截图
   （`get_image()` 拿的是上一帧；在 `_process` 里读会差一帧）。

---

## 3. 验收结果（原始输出）

### 3.1 专项：`tools\check_determinism.ps1`（4 次 × 4 个场景，容差 0）

| 场景 | 结果 | 指纹 |
|---|---|---|
| A 默认 | ✅ 6/6 逐像素一致 | `sim_time=5.0125 hitstop=0` |
| B combat（自动瞄准+射击） | ✅ 6/6 一致 | 同上 |
| C 单次 hitstop@150 | ✅ 6/6 一致 | `sim_time=4.9625 hitstop=1` |
| D 顿帧风暴（每 12 帧一次） | ✅ 6/6 一致 | `sim_time=3.7958 hitstop=25 frozen=True frames_left=2` |

D 是最有说服力的一条：**25 次冻结、累积 300 帧后，四次运行的模拟时间仍然一字不差**
（修之前它正是靠这条暴露了鼠标泄漏）。

### 3.2 全量：`tools\verify_all.ps1`

```
── ① 单元测试 ──   ✅ 通过：847 项，0 失败（退出码 0）
── ② 集成验证 ──   ✅ PC 端验证全部通过（51 项）（退出码 0）
── ③ 数据契约 ──   ✅ 通过：0 错误，0 警告
── ④ 像素基线 ──   · 自身复现性：同构建两次截图完全一致（本环境稳定）
                   ✅ 与基线一致：逐像素完全一致
✅ 通过 —— 可以交付。   EXITCODE=0
```

- 847 = 799（原）+ 45（WorkBuddy 的 W-01 套件 `s11_adversarial.gd`）+ 我的 s06 新增断言。
- 隔离复跑手感套件：`通过：58 项，0 失败`。

### 3.3 像素基线被我**有意重设**过（需要解释）

`art/_raw/_baseline.png` 原来是**带 HUD 的**（因为 `--hide-hud` 一直没生效）。
把 HUD 真正藏掉之后，与旧基线差 9.48%（87336 像素），所以跑了
`verify_all.ps1 -UpdateBaseline` 重设，重设后立即复跑 → **逐像素完全一致**。

**理由**：旧基线把"墙钟读数"当成了世界像素，它**天生不可能稳定**；
新基线才是"世界部分"。这不是"把失败当新基线"，是把一个**不可能通过的门**换成能通过的。

---

## 4. 没验证的事（别当成已验证）

| # | 事项 | 状态 |
|---|---|---|
| 1 | **hitstop 观感**（人眼） | ⚠️ **未验证**。帧换算按 `ceil` 对齐旧实现实测的 8 帧，但"手感对不对"必须人来确认（AGENTS.md 把这条列为审美判断） |
| 2 | 安卓真机 | ⚠️ 未验证（无设备）。帧计数在低帧率设备上会让冻结**变长**（30fps 时 4 帧=133ms，超过 spec 的 120ms 上限）——**这是已知取舍，真机确认前不要宣布达标** |
| 3 | 满编 35 敌 / 真机性能 | ⚠️ 未验证（属真机 A/B） |
| 4 | 长时间运行 | 帧计数用了上限 `1<<20`，没做过数小时压力 |
| 5 | 多人/多进程并发跑验收 | 未验证；`check_determinism.ps1` 的输出目录不与 `verify_all.ps1` 冲突，但**像素基线只能一个人重设** |

---

## 5. 建议（给下一个人）

1. **把 W-00 的验收接进 `verify_all.ps1` 当第 ⑤ 项**（本次没动它 —— 它是共享契约，
   而且加 4 次窗口运行会让验收变慢；先让它在 `tools\check_determinism.ps1` 里稳定一段时间）。
2. **`.ps1` 加一条"必须有 UTF-8 BOM"的守卫。** 本次我**两次**被它咬：
   编辑工具保存时把 BOM 去掉 → PS 5.1 按 ANSI 读中文 → 解析器崩在无关的行上
   （报 `Missing expression after ','`，完全指不到 BOM）。现有 `_test_project_hygiene`
   只查 `.gd/.json/.cfg/.godot/.tscn/.tres`，**恰好漏了 `.ps1`**。
3. **重设像素基线只能一个人做**（workboard 已警告 ②）。本次是我做的，已在此声明。
4. **WorkBuddy 的 `s11_adversarial.gd` 是 GBK/UTF-8 双重编码的乱码**（注释全是 `瀵规姉鎬ч獙鏀讹`），
   并且中途留下 `test/_diag_s11.gd`、`test/_diag_s11.log`、`verify_run.log` 三个 scratch 文件在仓库里。
   它现在**能编译、测试也过**，但注释读不了、scratch 文件不该提交 —— 建议让他们清一遍。
