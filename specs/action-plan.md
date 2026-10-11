# 行动清单（Action Plan）

> 执行入口。**分阶段细节见 `roadmap-bac.md`**，合规细节见 `publishing-cn.md`。
> 关联：`feasibility.md`（D-xx）· `tech-stack.md`（T-xx）· `art-pipeline.md`（A-xx）· `third-party.md`

---

## 0. 已冻结的关键决定

| ID | 决定 |
|---|---|
| **D-01** | 单机 PvE，不做联机 |
| **D-02 / T-01** | **Godot 4.7.x**（当前 4.7.2），GDScript |
| **D-09** | 开源（GPL-3.0）+ Gitee/GitHub 仓库 |
| **D-14 / D-15 / D-16** | ⭐ **国内发行：TapTap 主力 · 不联网 · 零变现** → 只需防沉迷 + 隐私合规 |
| **D-17** | ⭐ **递进路线 B → A → C**，B 按 A/C 架构只填核心内容 |
| **D-18** | 编码走 **DeepSeek**；美术用 **ComfyUI 本地 / LiblibAI**（$0） |

---

## 1. 你需要准备什么

### 1.1 硬件

- [ ] PC（已有）
- [ ] **安卓真机 ×2** —— 中端主力 + **一台低端机**（模拟器替代不了）
- [ ] USB 数据线
- [ ] 硬盘 10–20 GB
- [ ] ⭐ **可选但很值**：NVIDIA 显卡 **GTX 1060 6GB+** —— 有它美术生成成本 $0 且无上限

### 1.2 软件

- [ ] **Godot 4.7.x** 稳定版
- [ ] **JDK 17**（Temurin）—— ⚠️ JDK 21 常致 Gradle 失败
- [ ] **Android SDK**
- [ ] 像素编辑器：**Pixelorama**（免费）或 Aseprite（$20）
- [ ] **ComfyUI**（有 N 卡时）—— 或注册 **LiblibAI**
- [ ] git（已有）

### 1.3 账号

- [ ] **TapTap 开发者账号**（需实名认证；个人可注册）
- [ ] DeepSeek
- [ ] Gitee 或 GitHub（仓库）
- [ ] ⏳ 好游快爆开发者账号（`open.3839.com`，待核实要求）

### 1.4 素材（**全部 $0**）

- [ ] [Kenney **Desert Shooter Pack**](https://kenney.nl/assets/desert-shooter-pack) —— 主基底（**16×16 像素**，CC0）
- [ ] [OGA **knekko** Futuristic Guns](https://opengameart.org/content/futuristic-guns-weapons-and-items) —— 枪械/物品图标（**32×32**，CC0）
- [ ] **Noto Sans CJK 字体** —— 🚨 **必须**，否则中文满屏方块
- [ ] Kenney 音效（CC0）· Freesound（逐条授权）—— ⚠️ 枪声需另找

### 1.5 Godot 插件（均 MIT）

- [ ] **原生 `VirtualJoystick`**（4.7 内置，先试）→ 不行再退 Virtual Joystick DX
- [ ] **PixelPerfectSmoother** —— 像素完美相机
- [ ] **Blobsmith Autotile Wirer** —— 47-blob TileSet 一键生成
- [ ] **GdUnit4** —— 单测（含触屏 Scene Runner）
- [ ] Saltmire Juice（手感）· Phantom Camera（可选）

### 1.6 需要立刻问清的两件事（⚠️ 可能影响方案）

- [ ] **TapTap 工单**：不联网单机游戏的**防沉迷**具体怎么做？
- [ ] **TapTap 工单**：「唤起更新」SDK 是否**强制**、是否引入**网络请求**？
      （若强制联网 → 会直接撞上 D-16，需重新评估平台策略）

---

## 2. 第 0 阶段（本周，3–5 天）

- [ ] 装 **Godot 4.7 + JDK 17 + Android SDK**，跑通"空项目导出到手机"
- [ ] 建仓库：`LICENSE` = GPL-3.0 · `.gitignore` · `README` · spec 目录
- [ ] 下载 Kenney + OGA 素材，**登记 `third-party.md`**，LICENSE 存档 `art/_licenses/`
- [ ] 引入 **Noto Sans CJK**，验证**中文显示与断行**
- [ ] 引入 PixelPerfectSmoother，验证**像素完美与相机无抖动**
- [ ] 提交上面 §1.6 的两个 TapTap 工单

> 后两天的两个验证是本次调研挖出的**高概率翻车点**，很便宜、一周能验完，
> **不先验就会在 A 阶段才爆。**

---

## 3. M0 技术验证（1–1.5 周）—— 过不了别往下走

- [ ] Godot 4.7 导出安卓，真机稳定 60 fps
- [ ] 🚨 **中文显示 + 断行**（CJK 字体 + 勾 `Include Text Server Data`，**+约 4 MB 包体**）
      → **必须真机验证**：`test/m0_device_check.tscn`（⚠️ 编辑器里这个开关恒真，测不出差别）
- [ ] 🚨 **Compatibility 渲染器下 `CPUParticles2D` 可见** —— 用错 `GPUParticles2D` 会**静默消失、不报错**
      → 同一场景里已有 CPU/GPU 左右对照：`test/m0_device_check.tscn`
- [ ] 🚨 **双虚拟摇杆可用**（先试 4.7 原生；验证 `InputEventScreenDrag`）
- [ ] **像素完美 + 相机无抖动**（`canvas_items`+`integer` vs `viewport` 实机 A/B）
- [ ] **流场寻路**：1 个敌人追你；流场为**纯数据数组**，可 headless 单测
- [ ] **随机地图生成 < 50 ms** + **seed 可复现**
- [ ] **hitscan 命中判定**
- [ ] 存档读写 + **版本迁移骨架**
- [ ] 🚨 **确认不申请 `INTERNET` 权限**

---

## 4. 递进路线（详见 `roadmap-bac.md`）

| 阶段 | 内容 | 工期（兼职 15h/周） | 工期（全职） |
|---|---|---|---|
| **B** | 核心循环：进图→搜刮→战斗→撤离 + 死亡掉落 | **3–5 月** | 1.5–2 月 |
| 🚪 **门 1** | **「玩 30 分钟，还想再开一局吗？」** | — | — |
| **A** | + 改装 / 医疗 / 藏身处 / 群体 AI | 再 **2–4 月** | 再 1–1.5 月 |
| 🚪 **门 2** | 能连续玩 3 小时不腻 | — | — |
| **C** | + 制造 / 任务 / 更多枪械敌人地图 | 再 **3–6 月** | 再 1.5–2 月 |
| **累计** | | **8–15 个月** | **3–5 个月** |

> ⚠️ **门 1 不通过时绝不要进入 A。** 回去改 B 的数值与节奏，**而不是加系统**。
> 9 个系统里任何一个都救不了不好玩的核心循环。

---

## 5. 只有你能做的事（**AI 完全替不了**）

- [ ] **竞品拆解** —— 填 `reference-teardown.md` 的 13 张表
- [ ] **手感调参** —— hitstop、trauma、后坐力曲线、spread、aim assist 容差
- [ ] **玩法试玩与决策** —— 门 1 / 门 2
- [ ] **AI 美术的修帧** —— 约 30% 工作量（集中在死亡/换弹动作）
- [ ] **真机测试**
- [ ] **上架合规**（见 `publishing-cn.md`）

**手感调参工作流**：参数全 `@export` → 编辑器 Remote Inspector 运行时热调 →
一次只改一个参数 → 录屏 → **≥3 名不同水平测试者盲测** → **看 Profiler 的 frame time，不要看 FPS**。

---

## 6. 多少钱

| 项 | 金额 |
|---|---|
| **编码（DeepSeek）** | **约 $5 – 40**（全程 12–21 M token） |
| **美术生成** | **$0**（ComfyUI 本地或 LiblibAI 免费额度） |
| 素材采购 | **$0**（全 CC0 / CC-BY） |
| 音效 | **$0 – 50** |
| 像素编辑器 | **$0**（Pixelorama）或 $20 |
| **平台费用** | **$0**（TapTap / 好游快爆 上架免费） |
| **总计** | **约 $5 – 110** |

> **成本已经不是需要讨论的问题。** 唯一真正的投入是你的时间。

---

## 7. 多少时间

| 投入强度 | M0 | B | A | C | **累计** |
|---|---|---|---|---|---|
| 兼职 15 h/周 | 1–1.5 周 | 3–5 月 | 再 2–4 月 | 再 3–6 月 | **8–15 月** |
| 认真 25 h/周 | 1 周 | 2–3 月 | 再 1.5–2.5 月 | 再 2–4 月 | **5–9 月** |
| 全职 45 h/周 | 1 周 | 1.5–2 月 | 再 1–1.5 月 | 再 1.5–2 月 | **3–5 月** |

**两个必须知道的事实**：

1. **AI 不是并行加速器。** 每轮生成都要你 review、测试、决策。
2. **时间的大头不是写代码，是调参和试玩。**
3. **递进路线比"直接做 A"多花约 40–60% token**，但换来早期验证与低白干风险
   —— 累计到 C 时，成本与"直接做 C"相当。**这是近乎免费的风险保险。**

---

## 8. 红线检查表

- [ ] 🚨 **不申请 `INTERNET` 权限**，代码内零网络请求（D-16）
- [ ] 🚨 **零变现**：无内购、无广告、无打赏（D-14）
- [ ] 🚫 **禁止商业游戏提取素材**（D-11）
- [ ] 🚫 **禁止 `Jhon-Crow/godot-topdown-MVP` 的代码**（仓库无 LICENSE 文件）
- [ ] 🚫 **禁止 `TemplateSaver`（GPLv2）**
- [ ] ⚠️ **禁止 `CC-BY-NC-ND` 素材**
- [ ] ⚠️ **付费素材不入公开仓库**（D-13）
- [ ] **每引入外部资源，先登记 `third-party.md`，LICENSE 原文存档**
- [ ] **CC-BY / CC-BY-SA 素材必须署名**（仓库 `CREDITS.md` + 游戏内 Credits）
