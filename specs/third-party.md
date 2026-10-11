# 第三方资源登记与署名清单

> **本文件是保命文档。** 任何外部代码、素材、字体、音效在**落地到项目之前**必须先登记在此。
> 自包含。关联文件：`specs/feasibility.md`（决策 D-09 / D-11 / D-12）、`specs/art-pipeline.md`（§8.5 / §11）。

---

## 1. 硬规则

| ID | 规则 |
|---|---|
| **R-01** | **引入即登记**。不允许"先用了再说"。未登记的第三方资源视为违规 |
| **R-02** | 引入前**必看 LICENSE 原文**，不看 README 里的"free to use"（那不算授权） |
| **R-03** | **LICENSE 原文必须留档**至 `art/_licenses/{source}/{filename}`，或 `third_party/code/{repo}/LICENSE`。防止上游删库后无法举证 |
| **R-04** | **禁止 CC-BY-NC-ND**——游戏必然要修改素材（缩放、调色板、裁剪），ND 直接冲突 |
| **R-05** | **禁止任何商业游戏的提取素材**（D-11）。仓库公开 = 一被举报即 DMCA 下架 + 账号风险 |
| **R-06** | **禁止 GPL-2.0 / LGPL-2.1**——与本项目的 GPL-3.0 **不兼容**（GPL-2.0-only 尤甚） |
| **R-07** | `CREDITS.md` **由 `gen_credits.py` 从本文件自动生成**，禁止手工维护 |
| **R-08** | `audit_licenses.py` 纳入提交前检查，发现违规立即阻断 |

---

## 2. 授权速查表

| 授权 | 可用 | 义务 | 优先级 |
|---|---|---|---|
| CC0 / Unlicense / MIT / BSD / Apache-2.0 | ✅ | 无（建议仍登记） | ⭐⭐⭐⭐⭐ |
| CC-BY | ✅ | **必须署名** | ⭐⭐⭐⭐ |
| CC-BY-SA | ✅ | 署名 + 衍生素材同协议**开源**（不传染代码） | ⭐⭐⭐ |
| CC-BY-NC / NC-SA | ✅ | 署名 + 禁止商用 | ⭐⭐ |
| CC-BY-NC-ND | 🚫 | — | — |
| GPL-3.0 / AGPL-3.0 | ✅ | 项目整体以 GPL-3.0 发布 | ⭐⭐ |
| LGPL-3.0 | ✅ | 动态链接 + 可替换 | ⭐ |
| GPL-2.0 / LGPL-2.1 | 🚫 | 与 GPL-3.0 冲突 | — |
| 商业游戏提取素材 | 🚫 | — | — |

---

## 3. 登记表

### 3.1 代码

| # | 仓库 / 来源 | 授权 | 用途 | 是否合入代码 | LICENSE 存档 | 状态 |
|---|---|---|---|---|---|---|
| C-001 | *(示例)* `MerekiDor/mapsweepers` | 待确认 | NPC 战斗逻辑思路参考 | 否（仅学思路后重写） | — | 待确认 |
| C-002 | ~~`nathanfranke-archive/gdmapf`~~ | MIT（已核实） | 多智能体寻路 | **否** | — | 🚫 **不可用** |
| C-003 | Godot 引擎内置（`AStarGrid2D` 等） | MIT | 网格寻路 | 是（引擎内置） | 引擎自带 | ✅ 可用 |
| C-004 | [Griiimon/Manymies](https://github.com/Griiimon/Manymies) | **MIT**（已核实） | **流场寻路起点**（Godot 4.3，纯 GDScript） | 否（**改造后重写**） | — | ⚠️ 可用但**必须修 O(n²) 缺陷** |
| C-005 | [bitbrain/beehave](https://github.com/bitbrain/beehave) | **MIT**（已核实） | 行为树（纯 GDScript） | 待定 | — | ✅ 可用 |
| C-006 | [limbonaut/limboai](https://github.com/limbonaut/limboai) | **MIT**（已核实） | 行为树 + 黑板 + HSM + 调试器（**有 Android 预编译包**） | 待定 | — | ⚠️ 可用，但**与 Godot 版本强绑定** |
| C-007 | [derkork/godot-statecharts](https://github.com/derkork/godot-statecharts) | MIT（Asset 标注，仓库 LICENSE 待核） | 层级状态机 | 待定 | — | ✅ 可用 |
| C-008 | [pixelrogueart/goap-godot-4](https://github.com/pixelrogueart/goap-godot-4) | MIT（Asset 标注，仓库 LICENSE 待核） | GOAP 规划器（纯 GDScript） | 待定 | — | ✅ 可用 |
| C-009 | [kagenash1/godot-behavior-tree](https://github.com/kagenash1/godot-behavior-tree) | ⚠️ **声明 MIT 但仓库无 LICENSE 文件** | 行为树 + 黑板 | **否** | — | ⚠️ **需先向作者确认** |
| C-010 | 🚫 [Jhon-Crow/godot-topdown-MVP](https://github.com/Jhon-Crow/godot-topdown-MVP) | ❌ **无任何 LICENSE 文件（404）** | 同品类参考（视野/掩体/GOAP/听觉） | **否** | — | 🚫 **保留所有权利——只能读思路，绝不能复制代码** |

> **C-002 否决理由**（已实测核实）：仅 3D（`register_types.cpp` 只注册 3D 类）·
> `.gdextension` 无 Android 库 · **已 archive 归档** · README 自述**存在对向智能体卡死的重大 bug**。

### 3.2 美术素材

| # | 来源 | 授权 | 用途 | LICENSE 存档 | 状态 |
|---|---|---|---|---|---|
| A-001 | [Kenney **Desert Shooter Pack**](https://kenney.nl/assets/desert-shooter-pack) | **CC0** | **起步基底**：tile、角色、枪械、UI 通用件（**16×16 像素画**，2025） | `art/_licenses/kenney/` | ✅ 可用 |
| A-002 | [Kenney **1-Bit Pack**](https://kenney.nl/assets/1-bit-pack) | **CC0** | 环境打底（**16×16**） | `art/_licenses/kenney/` | ✅ 可用 |
| A-003 | [Kenney **UI Pack - Pixel Adventure**](https://kenney.nl/assets/ui-pack-pixel-adventure) | **CC0** | UI 元素 | `art/_licenses/kenney/` | ✅ 可用 |
| A-004 | [Kenney **Input Prompts Pixel**](https://kenney.nl/assets/tag:pixel) | **CC0** | **安卓触屏按钮图标**（很实用） | `art/_licenses/kenney/` | ✅ 可用 |
| A-005 | [Kenney **Minimap Pack**](https://kenney.nl/assets/minimap-pack) | **CC0** | 小地图图标 | `art/_licenses/kenney/` | ✅ 可用 |
| A-006 | [OGA **Futuristic Guns, Weapons and Items**（knekko）](https://opengameart.org/content/futuristic-guns-weapons-and-items) | **CC0** | **枪械/物品图标（32×32，正合我们的图标规格）** | `art/_licenses/oga_knekko/` | ✅ 可用 |
| A-007 | [OGA **Post-apocalyptic 16x16 tileset**（CobraLad）](https://opengameart.org/content/post-apocalyptic-16x16-tileset-update1) | **CC-BY-SA 3.0** | 废土风格地表 | `art/_licenses/oga_cobralad/` | ⚠️ 可用，**有传染性**（见 §4.2） |
| A-008 | [CraftPix **TDS Modern: Pixel Game Kit**](https://craftpix.net/product/tds-modern-pixel-game-kit/) | 自定义，**非 CC**；禁再分发源文件 | 现代军事全套（士兵/载具/建筑/GUI/爆炸/枪械） | 不入库，见 §4.5 | ⚠️ **付费**，**不得入公开仓库** |

> ⚠️ **A-000（已否决）**：[Kenney **Top-down Shooter**](https://kenney.nl/assets/top-down-shooter) 虽为 CC0，
> 但**不是像素画**（矢量/平滑风格），与项目像素风格不匹配，**不得作为基底包**。
> **三重证据**：① 不在 Kenney 的 [`tag:pixel`](https://kenney.nl/assets/tag:pixel) 筛选中；
> ② 元数据表**无 `Tile size` 行**（真像素包都标 `16 × 16`）；
> ③ **决定性**——Kenney 在 OGA 的镜像 <https://opengameart.org/content/topdown-shooter> 文件清单原文含 **`Vector file`**。
> `Top-down Tanks Remastered` 同理，一并否决。

### 3.3 音效

| # | 来源 | 授权 | 用途 | LICENSE 存档 | 状态 |
|---|---|---|---|---|---|
| S-001 | *(示例)* [Freesound](https://freesound.org) | 逐条确认（CC0 / CC-BY） | 枪声、环境音 | `art/_licenses/freesound/` | 待确认 |
| S-002 | *(示例)* Kenney Audio | CC0 | UI 音效、脚步 | `art/_licenses/kenney_audio/` | ✅ 可用 |

### 3.4 字体

| # | 字体名 | 授权 | 用途 | LICENSE 存档 | 状态 |
|---|---|---|---|---|---|
| F-001 | **Noto Sans SC**（可变字重，`NotoSansSC[wght].ttf`） | **OFL-1.1** | M0 验证用 CJK 字体；UI 正文 | `art/fonts/OFL.txt` | ✅ 已入库（16.9 MB） |

**来源**：[google/fonts](https://github.com/google/fonts/tree/main/ofl/notosanssc) ·
经 jsDelivr 获取：`https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/notosanssc/NotoSansSC[wght].ttf`

> ⚠️ **生产前需要处理两件事**：
> 1. **换成像素中文字体** —— Noto Sans SC 是衬线/黑体风格，与像素画不搭。
>    推荐 **[缝合像素字体 Fusion Pixel Font](https://github.com/TakWolf/fusion-pixel-font)**（OFL，8/10/12px 像素字号）。
>    ⚠️ 注意：该仓库**只放字形源 PNG，编译好的字体在 GitHub Releases 里**，jsDelivr 取不到，需要从 Releases 下载。
> 2. **子集化（subset）** —— 16.9 MB 太大。用 `fonttools` 按实际用字裁剪，
>    预计可压到 **200–500 KB**。**这直接影响包体预算（V-07）。**

---

## 4. 候选资源池（**授权状态需自行确认**）

> ⚠️ 下表的授权标注来自社区通用信息，**引入前必须自行核对官方页面**（R-02）。

### 4.1 美术

| 来源 | 说明 | 备注 |
|---|---|---|
| **[Kenney Desert Shooter Pack](https://kenney.nl/assets/desert-shooter-pack)** ⭐ **首选主基底** | **16×16 像素画**，标签 shooter / roguelike / pixel / ui，500 文件，2025 年发布 | CC0，零限制、无需署名。题材为沙漠/军事，与搜打撤契合 |
| [Kenney `tag:pixel` 全部像素包](https://kenney.nl/assets/tag:pixel) | Kenney 的像素包全集（3 页） | **选包时从这里进**，不要从全部素材里挑 |
| [Kenney Minimap Pack](https://kenney.nl/assets/minimap-pack) | 小地图图标 | CC0 |
| [Kenney UI Pack - Pixel Adventure](https://kenney.nl/assets/ui-pack-pixel-adventure) | 像素 UI | CC0 |
| [Kenney Roguelike Characters](https://kenney.nl/assets/roguelike-characters) | 450 个像素角色 | CC0 |
| [itch.io CC0 素材](https://itch.io/game-assets/assets-cc0/free/tag-asset-pack/tag-no-ai/tag-retro/tag-tileset) | 可按 CC0 + tileset + top-down 筛选 | 只用来补缺口 |
| [itch.io 免费素材总入口](https://itch.io/game-assets/new-and-popular/tag-2d/tag-no-ai/tag-pixel-art/tag-retro/tag-top-down) | 量大 | 授权混杂，逐个确认 |
| OpenGameArt.org | 老牌，量大 | 授权混杂，注意 GPL 素材 |

#### ⚠️ 教训：如何判断素材是否为像素画

本次调研踩过一个坑——`Top-down Shooter` 名字里带 "top-down"、题材也对，但**是矢量风格，不是像素画**。
入库前必须用以下任一条核实：

1. **看 tag**——素材站通常有独立的 `pixel` 标签。Kenney 从 [`tag:pixel`](https://kenney.nl/assets/tag:pixel) 进，不要在全部素材里按名字猜
2. **看 Tile size**——明确标注 `16×16` / `8×8` / `32×32` 的基本是像素画；矢量包通常不标尺寸
3. **看预览图**——像素画能看出清晰的方形色块与硬边；矢量图边缘平滑、有抗锯齿
4. **看文件格式**——批量是 PNG-8（≤256 色）或带明确调色板的，多半是像素画

**判据**：如果一张素材图放大后边缘是模糊渐变而不是硬色块，**它就不是像素画**，风格必然撕裂。

### 4.2 音效

| 来源 | 说明 |
|---|---|
| [Freesound.org](https://freesound.org) | CC0 / CC-BY，音效首选 |
| Kenney Audio | CC0，UI 与通用音效 |

### 4.3 代码 / 插件

| 来源 | 说明 |
|---|---|
| [Godot Asset Library](https://godotengine.org/asset-library/asset?max_results=500&page=0&filter=inventory&sort=updated) | 多为 MIT |
| [godotengine/awesome-godot](https://github.com/godotengine/awesome-godot) | 官方维护索引 |
| [SakuyaCN/TowDownGame](https://github.com/SakuyaCN/TowDownGame) | Godot 俯视 2D 射击，结构参考 |
| ~~[nathanfranke-archive/gdmapf](https://github.com/nathanfranke-archive/gdmapf)~~ | 🚫 **不可用**：仅 3D · 无 Android 库 · 已归档 · 有对撞卡死 bug（见 §3.1 C-002） |
| [Griiimon/Manymies](https://github.com/Griiimon/Manymies) | **流场寻路起点**（MIT、Godot 4.3、纯 GDScript）。⚠️ 必须修掉 `remove_at(0)` 的 **O(n²) 退化** |
| [bitbrain/beehave](https://github.com/bitbrain/beehave) | 行为树（MIT、纯 GDScript、活跃） |
| [derkork/godot-statecharts](https://github.com/derkork/godot-statecharts) | 层级状态机（MIT、1619 stars） |
| 🚫 [Jhon-Crow/godot-topdown-MVP](https://github.com/Jhon-Crow/godot-topdown-MVP) | **无 LICENSE 文件 → 保留所有权利。只能读思路，绝不能复制代码** |
| [GitHub topic: extraction-shooter](https://github.com/topics/extraction-shooter) | 类型相关开源项目 |

### 4.4 ⚠️ 合入外部代码的决策原则

**默认不直接合入，而是"读思路 → 写进 spec → 让 AI 重写"**，理由：

1. **授权最干净**——重写后不产生衍生作品争议
2. **风格统一**——外来代码和 AI 生成的代码混在一起会导致后期维护地狱
3. **AI 改得动**——你的核心工作流是让 AI 持续迭代，外来复杂实现 AI 理解成本极高（会烧掉大量 token，正踩 `feasibility.md` §10.5 的爆炸点）

**例外**：Godot 引擎内置能力（MIT，直接用）与 Godot 官方 demo。

---

## 5. CREDITS 生成规则

`gen_credits.py` 从本文件自动生成 `CREDITS.md`，规则：

```
遍历 §3 所有状态为「✅ 可用」或「已合入」的条目
  → 过滤出需要署名的授权（CC-BY / CC-BY-SA / CC-BY-NC / GPL 等）
  → 按来源分组输出：作品名 — 作者 — 链接 — 授权名
  → CC0 / MIT 类归入「特别鸣谢（无署名义务）」段落
```

**署名必须同时出现在两个地方**：

1. 仓库根目录 `CREDITS.md`
2. **游戏内 Credits 界面**（玩家可见）

> ⚠️ CC-BY 的署名义务**不因"游戏免费"而免除**。这是发布后最容易被追责的点。

---

## 6. 提交前检查清单

- [ ] 本次新增的第三方资源已登记到 §3 对应表格
- [ ] LICENSE 原文已存入 `art/_licenses/` 或 `third_party/`
- [ ] 无 CC-BY-NC-ND 素材（`audit_licenses.py`）
- [ ] 无 GPL-2.0 / LGPL-2.1 代码（`audit_licenses.py`）
- [ ] 无商业游戏提取素材（人工确认）
- [ ] 外部素材已过 `import_external.py` 统一化（`art-pipeline.md` §8.5）
- [ ] `CREDITS.md` 已重新生成（`gen_credits.py`）
