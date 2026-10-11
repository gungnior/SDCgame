# 俯视现代军事像素素材调研报告

调研方式：全部结论来自本次实际 web_fetch / web_search 打开的页面。无法核实的一律标注「待确认」或「未核实」，不猜。

---

## A. Kenney 核实结果

### A.1 结论：Kenney 不是像素画素材站，`Top-down Shooter` 不是像素画

**证据链（三重，来自 Kenney 自己的页面）：**

1. Kenney 站内有一个他自己维护的 `pixel` 标签分类页：<https://kenney.nl/assets/tag:pixel>（共 3 页）。`Top-down Shooter` **不在其中**。
2. `Top-down Shooter` 条目页 <https://kenney.nl/assets/top-down-shooter> 的元数据表**没有 `Tile size` 行**；而所有真正的像素包都有（例如 1-Bit Pack、Pixel Shmup、Roguelike/RPG pack 都明确写着 `Tile size 16 × 16`）。
3. **决定性证据**：Kenney 本人在 OpenGameArt 上镜像了同一套包 <https://opengameart.org/content/topdown-shooter>，文件清单原文：

   > Files:
   > - Separate PNG files (580x)
   > - Tilesheet
   > - Spritesheet
   > - **Vector file**

   存在 **Vector file（矢量源文件）**说明它是矢量/平滑风格，不是像素画。标签为 `topdown / building / tiles / zombie / police / soldier / survivor / survival / house / furniture`，授权 **CC0**。

**同理确认非像素**：`Top-down Tanks Remastered`（<https://kenney.nl/assets/top-down-tanks-remastered>，无 pixel 标签、无 Tile size 行）。

> 结论：**Kenney 的招牌俯视素材（Top-down Shooter / Top-down Tanks Remastered）是矢量平滑风格，绝对不能用于像素画项目。** 题材虽然沾边（有 soldier/police/zombie 标签），但风格完全不匹配。

### A.2 Kenney 真正属于像素画的包（完整清单，来自 tag:pixel 三页）

| 包名 | 链接 | tile 尺寸 | 题材 |
|---|---|---|---|
| 1-Bit Pack | [链接](https://kenney.nl/assets/1-bit-pack) | **16×16（页面已标明）** | RPG/室内/都市/平台（1-bit 单色） |
| Roguelike/RPG pack | [链接](https://kenney.nl/assets/roguelike-rpg-pack) | **16×16（已标明）** | 奇幻小屋/家具/UI |
| Roguelike Modern City | [链接](https://kenney.nl/assets/roguelike-modern-city) | 页面未标（待确认） | **现代城市/urban** |
| Roguelike Indoors | [链接](https://kenney.nl/assets/roguelike-indoors) | 页面未标（待确认） | 室内 |
| Roguelike Caves & Dungeons | [链接](https://kenney.nl/assets/roguelike-caves-dungeons) | 页面未标（待确认） | 洞穴地牢 |
| Roguelike Characters | [链接](https://kenney.nl/assets/roguelike-characters) | 未标（待确认） | 角色 |
| Desert Shooter Pack | [链接](https://kenney.nl/assets/desert-shooter-pack) | **16×16（已标明）** | **射击（2025 新包）** |
| Pixel Shmup | [链接](https://kenney.nl/assets/pixel-shmup) | **16×16（已标明）** | 俯视飞机射击 |
| Pixel Platformer（+ Food / Industrial / Farm / Blocks 扩展） | [链接](https://kenney.nl/assets/pixel-platformer) | 未标（待确认） | 平台跳跃 |
| Pixel Line Platformer | [链接](https://kenney.nl/assets/pixel-line-platformer) | 未标 | 平台 |
| Platformer Art Pixel | [链接](https://kenney.nl/assets/platformer-art-pixel) | 未标 | 平台 |
| 1-Bit Platformer Pack | [链接](https://kenney.nl/assets/1-bit-platformer-pack) | 未标 | 1-bit 平台 |
| Micro Roguelike | [链接](https://kenney.nl/assets/micro-roguelike) | 未标 | Roguelike |
| Monochrome RPG / Monochrome Pirates | [链接](https://kenney.nl/assets/monochrome-rpg) | 未标 | 1-bit 风格 |
| Pico-8 Platformer / Pico-8 City | [链接](https://kenney.nl/assets/pico-8-city) | 未标 | Pico-8 风 |
| Tiny 系列：Tiny Dungeon / Tiny Battle / Tiny Town / Tiny Farm / Tiny Factory / Tiny Ski | [链接](https://kenney.nl/assets/tiny-dungeon) | 未标（待确认） | 混合 |
| Pixel Vehicle Pack | [链接](https://kenney.nl/assets/pixel-vehicle-pack) | 未标 | 载具 |
| Input Prompts Pixel / Input Prompts Pixel 1-Bit | [链接](https://kenney.nl/assets/input-prompts-pixel) | 未标 | UI 提示 |
| Pixel UI Pack / UI Pack - Pixel Adventure | [链接](https://kenney.nl/assets/pixel-ui-pack) | 未标 | **UI** |
| Cursor Pixel Pack | [链接](https://kenney.nl/assets/cursor-pixel-pack) | 未标 | 光标 |
| Playing Cards Pack | [链接](https://kenney.nl/assets/playing-cards-pack) | 未标 | 卡牌 |
| Pattern Pack Pixel | [链接](https://kenney.nl/assets/pattern-pack-pixel) | 未标 | 贴图 |
| RPG Urban Pack | [链接](https://kenney.nl/assets/rpg-urban-pack) | 未标 | **都市** |
| Minimap Pack | [链接](https://kenney.nl/assets/minimap-pack) | 未标 | UI |
| Kenney Fonts | [链接](https://kenney.nl/assets/kenney-fonts) | — | 字体 |

> 注：Kenney 全站有数百个包，其中带 pixel 标签的只有上面这约 35 个。**绝大多数（含全部 3D 包和大量 2D 包）不是像素画。**

### A.3 Kenney 授权

**全部 CC0。** 我逐页核实的每个 Kenney 页面（top-down-shooter、1-bit-pack、pixel-shmup、desert-shooter-pack、roguelike-rpg-pack、roguelike-modern-city、top-down-tanks-remastered、impact-sounds）元数据表都写着：

> License: [Creative Commons CC0](https://creativecommons.org/publicdomain/zero/1.0/)

OGA 镜像页也标注 CC0，并注明 "Credit 'Kenney.nl', this is not mandatory"。**CC0 = 零义务，可自由修改、可商用、可放进公开开源仓库，无需署名。这是最适合开源项目的授权。**

---

## B. 其他素材来源

### B.1 已实际打开并核实

| 来源 | 包名 | 链接 | 授权 | tile尺寸 | 风格 | 是像素画? | 俯视? | 现代军事题材匹配 | 价格 |
|---|---|---|---|---|---|---|---|---|---|
| **CraftPix** | **TDS Modern: Pixel Game Kit** | [链接](https://craftpix.net/product/tds-modern-pixel-game-kit/) | CraftPix 自定义授权（非 CC）；商用/修改/出售游戏均允许，无需署名；**禁止再分发源文件** | 未标（32×32 级别，见说明） | **军事俯视像素，全套** | ✅ 是 | ✅ 是 | ⭐⭐⭐⭐⭐ **完全对口** | **付费**（子包各 $4.50–$5.50 / 会员制） |
| CraftPix | Free TDS Modern: GUI Pixel Art | [链接](https://craftpix.net/freebies/free-tds-modern-gui-pixel-art/) | 同上（Freebie 条款 §2） | 未标 | 军事 UI | ✅ | ✅ | ⭐⭐⭐⭐ | **免费** |
| CraftPix | Free Top Down Military Boats Pixel Art | [链接](https://craftpix.net/freebies/free-top-down-military-boats-pixel-art/) | 同上 | 未标 | 军用船只 | ✅ | ✅ | ⭐⭐⭐ | **免费** |
| CraftPix（付费子包） | Top Down Soldier Sprites / Tank Sprites / Buildings and Objects / Trucks and Cars / Fire and Explosion / Smoke | [soldier](https://craftpix.net/product/top-down-soldier-sprites-pixel-art/) 等 | 同上 | 未标 | 军事 | ✅ | ✅ | ⭐⭐⭐⭐⭐ | 各 $5.50 |
| **OpenGameArt** | Post-apocalyptic 16x16 tileset [update1] | [链接](https://opengameart.org/content/post-apocalyptic-16x16-tileset-update1) | **CC-BY-SA 3.0** | **16×16** | 废土 tileset | ✅ | ✅ | ⭐⭐⭐⭐ 废土 | 免费 |
| **OpenGameArt** | Futuristic Guns, Weapons and Items (knekko) | [链接](https://opengameart.org/content/futuristic-guns-weapons-and-items) | **CC0** | **32×32 网格** | 手枪/霰弹/机枪/狙击/护甲/物品 | ✅ | ✅（物品图标） | ⭐⭐⭐⭐⭐ 枪械图标 | 免费 |
| OpenGameArt | Topdown Shooter (Kenney 镜像) | [链接](https://opengameart.org/content/topdown-shooter) | CC0 | 无（矢量） | 平滑矢量 | ❌ **不是** | ✅ | 题材沾边但风格错 | 免费 |
| OpenGameArt | Sci Fi Soldier and Guns (DasBilligeAlien) | [链接](https://opengameart.org/content/sci-fi-soldier-and-guns) | CC0 | 无 | 概念画/photoshop | ❌ **不是像素画** | ❌ | 军事但不可用 | 免费 |
| **GameDev Market** | 全站统一 "Pro Licence" | [授权页](https://www.gamedevmarket.net/about/licences) | Pro Licence：非独占，可用于任意定价/变现的游戏 | — | 以付费为主 | 混合 | 混合 | 未找到对口免费军事像素包 | 以付费为主 |
| GameDev Market | Free Pixel UI pack 2 | [链接](https://www.gamedevmarket.net/asset/free-pixel-ui-pack-2) | Pro Licence | 待确认 | UI | 待确认 | — | UI 可用 | 免费 |
| **ぴぽや pipoya（日本）** | 免费素材（マップチップ 16×16 / 32×32～、キャラクターチップ、エフェクト、アイコン） | [利用規約](https://pipoya.net/sozai/terms-of-use/) · [16×16 地图chip](https://pipoya.net/sozai/?p=879) · [32×32～](https://pipoya.net/sozai/assets/map-chip_tileset32/) | 自定义（**已逐条核实**）：个人+法人可商用、允许改変、**无需署名**、允许无偿再分发；**禁止转售素材本身** | **16×16 与 32×32～ 皆有** | JRPG/奇幻 dott 绘 | ✅ 是 | ✅ 是 | ❌ **无现代军事内容** | 免费（另有付费素材，付费版**禁止再分发**） |
| **Freesound** | （音效，见 C 节） | [FAQ](https://freesound.org/help/faq/) | 逐条授权 CC0 / CC-BY / CC-BY-NC | — | — | — | — | — | 免费 |
| **Sonniss** | #GameAudioGDC Bundle | [授权页](https://sonniss.com/gdc-bundle-license/) | **待确认**（页面被 Cloudflare 拦截，返回 403，未能读到条款原文） | — | — | — | — | — | 免费 |

### B.2 未能核实（诚实标注）

| 来源 | 状态 | 说明 |
|---|---|---|
| **itch.io** | ❌ **本次环境无法打开** | 多次尝试 `https://itch.io/game-assets/free/tag-pixel-art/...`、`https://limezu.itch.io/moderninteriors` 等，全部返回 `TypeError: fetch failed` / `getaddrinfo EAI_AGAIN`（DNS 解析失败）。**因此本次无法核实任何 itch.io 素材包的授权、尺寸与风格。** 搜索引擎确实返回了大量 itch.io 结果页（如 [free × pixel-art × tileset × top-down](https://itch.io/game-assets/free/tag-pixel-art/tag-tileset/tag-top-down)、[Anokolisa 作者页](https://itch.io/profile/anokolisa)、[top-down-shooter × weapons](https://itch.io/game-assets/top-seller/free/tag-top-down-shooter/tag-weapons)），但这些只是 URL，**内容与授权我一律没有验证，全部标为「待确认」**。 |
| **Humble Bundle** | 未核实 | 本次未打开任何 Humble 素材包页面，不猜测其授权。 |
| **中文素材站**（爱给网、indienova、66rpg 等） | ❌ 未核实 | 本次没有成功打开并核实任何一个中文素材站的授权条款。**特别提醒：中文聚合站大量存在抓取他人素材、伪造「免费商用」标注的情况，在未逐条核实前不可用于开源项目。** |
| **LPC（Liberated Pixel Cup）** | 待确认 | 仅通过 GitHub 镜像（[nathantgray/LPC](https://github.com/nathantgray/LPC)）间接看到，未打开原始授权页。常见说法是 CC-BY-SA 3.0 / GPL、32×32，但**未经本轮核实，不做断言**。 |
| Kenney 未标尺寸的像素包（Tiny 系列、Roguelike Indoors 等） | 待确认 | 页面未列 `Tile size` 字段，未下载素材包实测。 |

---

## C. 音效

### C.1 授权对比

| 来源 | 授权模型 | 商用 | 署名 | 关键坑 |
|---|---|---|---|---|
| **Freesound** | **逐条授权**：CC0 / CC-BY / CC-BY-NC（+ 遗留 Sampling+） | CC0/CC-BY 可；**CC-BY-NC 不可商用** | CC-BY 必须署名；官方给了逐条列出、或链接到 credits 页的做法；Minecraft 的 [attribution 页](https://www.minecraft.net/en-us/attribution/sound) 是官方举例 | **每个文件授权不同，必须逐个查**；下载需登录账号；Sampling+ 已 retired 但仍存在 |
| **Kenney Audio** | **CC0**（已核实 [Impact Sounds](https://kenney.nl/assets/impact-sounds)：License CC0，130 个文件） | ✅ 可 | ❌ 不需要 | 音效偏「卡通/通用 foley」，不是军事写实枪声 |
| **Sonniss GDC Bundle** | **待确认**（Cloudflare 403，未读到原文） | 未知 | 未知 | 体积巨大（多 GB）；业界普遍认为可免费用于游戏但**不可再分发原始文件**——**此点我未能核实，请勿据此行动** |
| **OpenGameArt** | 与美术一样：逐个条目授权（CC0 / CC-BY / CC-BY-SA / GPL） | 视条目而定 | 视条目而定 | 与美术同样的逐条目核实负担 |

**已核实的 Kenney 音频包清单**（[分类页](https://kenney.nl/assets/category:Audio)）：Casino Audio、Sci-fi Sounds、Interface Sounds、**Impact Sounds（CC0 已核实）**、Voiceover Pack (Fighter)、Voiceover Pack、Music Jingles、RPG Audio、Digital Audio、UI Audio。
> ⚠️ **Kenney 没有专门的枪声/射击音效包**——页面上找不到 shootout/weapon/gun 类包。这意味着枪声必须另找来源。

### C.2 枪声素材

- **结论：本次没有找到并核实任何一个高质量免费枪声包。** Kenney 无枪声包；itch.io 无法打开；Sonniss 条款无法读到。
- Freesound 是理论上最可行的路径（可搜 gunshot/rifle/handgun 并筛 CC0），但我**没有在本轮实际下载或试听任何枪声文件**，因此不给具体推荐。
- 重要实务提醒：**top-down 射击游戏需要的不是"写实录音"，而是"短促、有冲击力、game-ready"的枪声**。Freesound 上大量 raw field recording 直接丢进游戏会显得糊、拖尾长、动态范围过大。通常需要自己做包络裁剪（cut tail）、加层（低频 thump + 高频 crack + 尾音 reverb）、随机化 pitch/volume。

### C.3 授权注意点

1. **Freesound 逐条授权**：一个项目混用 CC0 + CC-BY-NC 在"非商用"前提下合法，但 **NC 条款会永久锁死商业化路径**。若将来想上 Steam 卖，所有 CC-BY-NC 音效必须替换。
2. **署名叠加**：CC-BY 要求逐个署名。官方给的做法是可以写 "uses many sounds from freesound, for the full list see here: <URL>"——即在游戏内 credits 页放一个链接/列表即可，不需要在 UI 里逐条弹署名。
3. **CC0 vs "royalty-free"**：CC0 才是零义务。任何写着 "royalty-free for commercial use" 的素材仍然受**自定义 EULA** 约束（常见限制：不得再分发源文件、不得用于 AI 训练）。对**公开开源仓库**而言这是致命区别——把素材 commit 进 GitHub 就等于再分发源文件。
4. **YouTube「免费音效」频道基本不可用**——授权无法追溯，不要用。

---

## D. 关键问题回答

### D.1 有真正合适的「俯视现代军事像素素材包」吗？——**几乎不存在免费版**

**必须直说：这套组合（俯视 + 现代军事 + 像素画 + 16×16 + 角色动画 + 枪械 + tileset + UI 全套）在免费/CC0 世界里基本是空白。**

本轮实际找到的对口素材只有 **3 类碎片**：

1. **CraftPix TDS Modern 系列** —— 唯一真正"全套对口"的包（士兵含狙击手/机枪手/榴弹手、坦克/装甲车/直升机、兵营/瞭望塔、GUI、爆炸烟雾、含现代枪械的主角）。**但它是付费的，且授权禁止再分发源文件、禁止用于 AI 训练。**
2. **OGA 的零星 CC0/CC-BY-SA 单品** —— [Futuristic Guns（CC0，32×32 枪械图标）](https://opengameart.org/content/futuristic-guns-weapons-and-items)、[Post-apocalyptic 16×16 tileset（CC-BY-SA 3.0）](https://opengameart.org/content/post-apocalyptic-16x16-tileset-update1)。是碎片，不是包。
3. **Kenney 的军事沾边包全是矢量** —— 风格直接出局。

**为什么稀缺（结构性原因）：** 军事题材的商业价值高，作者更倾向放到 CraftPix / GameDev Market 卖钱；而 CC0 生态的作者主流兴趣是奇幻 RPG / 平台跳跃 / 可爱风（对比 OGA 上奇幻包的数量）。这个供需缺口是真实的、长期的。

**这意味着什么：** 这块**不能靠"找包"解决**，必须靠"造素材"。这是本项目最大的美术风险，应当在排期里按"自研美术"而不是"找现成素材"来规划。

### D.2 实际可行的替代路径（按推荐度排序）

1. **混合基底 + 自绘军事件（最推荐）**
   - 环境 tileset / 建筑结构：用 [Kenney 1-Bit Pack（CC0, 16×16）](https://kenney.nl/assets/1-bit-pack) 或 [Roguelike/RPG pack（CC0, 16×16）](https://kenney.nl/assets/roguelike-rpg-pack) 打底，统一重上色到你的战术调色板。
   - 枪械/物品图标：直接吃 [OGA knekko 的 CC0 枪械包（32×32）](https://opengameart.org/content/futuristic-guns-weapons-and-items)。
   - 废土地表：吃 [OGA CobraLad 的 CC-BY-SA 16×16 废土 tileset](https://opengameart.org/content/post-apocalyptic-16x16-tileset-update1)（注意 SA 的传染性）。
   - **士兵角色动画自己画**——这是唯一无法回避的部分，也是最需要美术投入的部分。
   - 好处：CC0 部分可安全进公开仓库，零法律负担。

2. **CraftPix TDS Modern 付费购买（若预算允许，且能接受授权约束）**
   - 单个子包 $5.50 级别，全套几十美元，性价比其实很高，风格完全对口、省下大量工时。
   - **但必须处理授权冲突**：条款写「Distribution of source files is NOT permitted」「You can NOT resell the art source files or slightly modified version」。
   - **应对**：**不要把素材 commit 进公开仓库**。做法是——仓库只放代码 + 一份 `assets/` 的下载说明/获取脚本，素材由开发者各自购买后放入本地目录（`.gitignore` 排除）。这样代码开源、素材私有授权，合规。这也顺便避免了 CC-BY-SA 的传染问题。

3. **AI 生成**
   - 可行但**有真实法律不确定性**：AI 输出在多数司法辖区**不受版权保护**（你有不了版权，但别人也能用）；Freesound 2026 年已加 Gen AI 偏好面板；**CraftPix 明确禁止把其素材用于 AI 训练**；把 CC0 素材喂给模型是灰色地带。
   - 适合当作**草稿/概念图**产出，再由人手工修成规范的 16×16 像素（AI 直接产出的"像素画"通常像素网格不干净、有半透明抗锯齿边缘，需要重画）。

4. **委托画师定制**（最干净、质量最高，成本最高）。对于 16×16 军事角色 + tileset，这是最可靠的路线。

### D.3 Kenney 适合作为「主基底包」吗？——**不适合做美术主基底，适合做补充**

**明确判断：不能当主基底。**

理由：
- ❌ **招牌俯视包是矢量**。`Top-down Shooter` 是项目最该用的那种包（俯视 + 士兵 + 建筑 + 室内家具 + 僵尸），但它是矢量平滑风，**风格完全不匹配像素画项目**，且无法"像素化改造"（矢量包自带抗锯齿和渐变，改不出干净的像素网格）。
- ❌ **像素包占比极小且题材偏**。约 35 个像素包中，题材集中在奇幻地牢、平台跳跃、Tiny 可爱风、Pico-8 风，**没有一个现代军事题材的完整像素包**。最接近的 `Roguelike Modern City` 只覆盖都市环境，没有军事装备/枪械。
- ❌ **美术风格辨识度太低**。Kenney 的像素包是"通用教学向"，调色板平淡、无描边或轻描边，放进游戏很容易被认出是 Kenney 素材，与 Zero Sievert / Hotline Miami 那种有强烈美术个性的目标差距大。

**但作为"补充包"很有价值：**
- ✅ **CC0 是公开开源仓库的唯一无痛授权**——可以直接 commit，无需署名，无再分发限制，无 NC 锁死。
- ✅ 现成可用：**UI**（Pixel UI Pack / UI Pack - Pixel Adventure）、**输入提示图标**（Input Prompts Pixel，做 Android 触屏按钮很实用）、**光标**、**字体**、**全部音频（CC0）**、**1-Bit Pack（16×16）** 作为环境打底。
- ✅ 原型期极快：先拿 Kenney 1-Bit 把玩法跑通，美术后置。

**一句话：Kenney 当「UI / 音频 / 原型占位 / 环境打底」的来源，不当「主视觉基底」。**

### D.4 混用不同来源素材的风格统一难点

| 难点 | 具体冲突 | 处理办法 |
|---|---|---|
| **调色板** | Kenney 明亮饱和；CraftPix 军事风低饱和土黄/军绿；OGA 废土包偏脏暗；pipoya 是 JRPG 高饱和 | 定一个统一调色板（推荐 **Lospec** 上的受限调色板，如 32–48 色战术色系），把所有外来素材**索引化重映射**到该调色板。这一步是统一观感性价比最高的操作。 |
| **描边（outline）** | Kenney 1-Bit 无描边/硬边；CraftPix 有深色外描边；OGA 包描边粗细不一 | 选定一种规则（俯视射击通常用 1px 深色 selective outline）并**逐素材补/删描边**。 |
| **光照方向与阴影** | 各素材包默认光源方向不同（左上/正上/无），阴影偏移方向不一致 | 俯视游戏必须先**固定一个光源方向**，然后统一所有角色/物件的阴影偏移。CraftPix 的 TDS Modern 明确把 shadows 放在单独 PSD 层，正是为此。 |
| **像素密度（最致命）** | 16×16 与 32×32 混用；Kenney 像素包多数 16×16，CraftPix/枪械包是 32×32，矢量包任意尺寸 | 只能**整数倍 nearest-neighbor 缩放**（32 = 16×2）。非整数缩放会破坏像素网格，产生不均匀像素块。混合 16 与 32 会让同屏角色大小比例失真，必须先在美术规范里敲定基准尺寸（建议 16×16 tile + 32×32 角色）。 |
| **抗锯齿 / 半透明** | 矢量包（Kenney Top-down Shooter）和 AI 生成图带 AA 边缘与半透明像素 | **无解，只能弃用或彻底重画**。这也是为什么矢量包不能"改造成像素画"。 |
| **动画帧数 / 骨架比例** | 各包行走循环帧数（4/6/8 帧）与角色头身比（chibi 1:1 vs 1:2.5）不同 | 锁定一个帧数与头身比规范，改动成本高，**最好在建项目初期就定死**。 |

---

## 结论与推荐

1. **Kenney 不是像素画素材站。** 招牌俯视包 `Top-down Shooter` 是矢量风（Kenney 自己在 OGA 的镜像列出 "Vector file" 为证），**不能用于本项目的像素画风格**。Kenney 全站只有约 35 个包带 pixel 标签。授权确认为 **全部 CC0**。

2. **「俯视现代军事像素素材包」在免费/CC0 世界里确实稀缺——这是本次调研最重要的结论。** 唯一完整对口的是 **CraftPix TDS Modern 系列（付费 + 禁止再分发源文件）**；OGA 只有零星 CC0 碎片（knekko 的枪械图标包最值得拿）。

3. **推荐架构：**
   - **基底/占位/UI/音频**：Kenney（CC0，可入库）——1-Bit Pack、Pixel UI Pack、Input Prompts Pixel、全部音频
   - **枪械/物品图标**：[OGA knekko Futuristic Guns（CC0, 32×32）](https://opengameart.org/content/futuristic-guns-weapons-and-items)
   - **废土地表**：[OGA CobraLad Post-apocalyptic 16×16（CC-BY-SA 3.0）](https://opengameart.org/content/post-apocalyptic-16x16-tileset-update1)（注意 SA 传染性）
   - **军事角色 / 现代军事 tileset**：**自绘，或购买 CraftPix TDS Modern**（素材不入公开仓库，走 `.gitignore` + 获取脚本）
   - **首选配色统一手段**：限定调色板 + 索引重映射

4. **本报告的两个明确限制（不隐瞒）：**
   - **itch.io 在本环境完全无法访问**（DNS 解析失败），因此**没有核实任何 itch.io 素材包**。itch.io 是像素素材最大的聚集地，这一块必须补做——建议在能正常访问 itch.io 的环境里重新调研，重点看 Anokolisa、LimeZu、Pixel-Boy (Ninja Adventure) 等作者，并逐个核对授权。
   - **Sonniss 授权页被 Cloudflare 拦截（403）**，条款原文未读到，**标为待确认**；中文素材站本轮也未核实。
