# 美术管线 —— 实测记录

> 本文件记录**实际跑出来的结论**，不是计划。与 `specs/art-pipeline.md` 冲突时以本文件为准。

## 环境（2026-10-12 实测）

| 项 | 值 |
|---|---|
| 生成器 | ComfyUI @ `D:\comfyui\Comfyui-WF-2026.8.8\ComfyUI` |
| Python | `D:\comfyui\Comfyui-WF-2026.8.8\python\python.exe`（3.12.10, torch 2.10.0+cu130） |
| GPU | RTX 4070 SUPER 12GB |
| 底模 | `sdxl\perfectdeliberate_v10.safetensors` |
| 像素 LoRA | `pixel-art-xl.safetensors`（162MB，从 HF `nerijs/pixel-art-xl` 下载） |
| 速度 | 768×768 / 30 步 / dpmpp_2m+karras ≈ **11 秒/张** |

启动：
```powershell
cd D:\comfyui\Comfyui-WF-2026.8.8\ComfyUI
D:\comfyui\Comfyui-WF-2026.8.8\python\python.exe main.py --port 8188 --listen 127.0.0.1 --disable-auto-launch
```

## ⭐ 核心结论：**AI 不适合生成 tile，适合生成角色/物品/枪械**

### 实测证据

| 资产类型 | AI 生成 | 结论 |
|---|---|---|
| **枪械** | ✅ 一眼认出是突击步枪 | 用 AI |
| **物品图标** | ✅ 医疗包（白盒红十字）、背包清晰可辨 | 用 AI |
| **角色** | ⚠️ 站立持枪士兵，轮廓可辨；48×48 下偏糊 | 用 AI + 人工修 |
| **地形 tile** | ❌ **完全失败** | **改用程序化** |

### tile 为什么失败

写 `seamless concrete floor texture` 时，`pixel-art-xl` 产出的是**"物件轮廓"**（一块石头/一个色块），
不是满幅铺满的纹理。试过三种 LoRA 权重，全部失败：

| LoRA 权重 | 结果 |
|---|---|
| 1.15（默认） | 一只怪物 |
| 0.35 | 一块石头形状的色块 |
| 0.0（不吃 LoRA） | 还是色块 |

**根因**：`pixel-art-xl` 是**角色** LoRA，训练集偏角色/生物/物件。
而 16×16 地砖本质上就是「底色 + 几个深色像素」——AI 在这里是过度工具。

**解法**：`tools/art/gen_tiles.py` 程序化生成。优点：确定、瞬时、严格可平铺、
颜色必然在调色板内。7 类 × 3 变体 = 21 块 tile。

---

## 提示词模板（`tools/art/gen_comfy.py`）

四条硬约束，缺一个就不可用：

```
POSE_CHAR = "flat 2D side profile view, standing upright, facing right,
             full body head to toe, orthographic, no perspective"
```

1. **姿态必须写死**。不写 `side profile / facing right`，模型会画成斜俯视或趴姿。
2. **单主体**。`single subject` + 负向 `multiple subjects, two characters` —— 否则会多画一个小人。
3. **不要 `top-down view`**。写这个模型会画成真正的俯视（只能看见头顶），角色立绘就废了。
4. **背景用浅色**，不要 `plain dark background` —— 深色背景会和角色的暗色装备糊在一起，
   抠图抠不干净。

---

## 后处理（`tools/art/postprocess.py`）

`去背景 -> 去碎片 -> 裁主体 -> 缩放对齐锚点 -> 量化`

### 背景去除：`mode="both"`

```
border  只删与边界连通的背景 —— 安全，但【腿间/腋下】的封闭背景删不掉（实测踩过）
global  全局色键 —— 能删封闭区，但可能吃掉浅色装备
both    先 border 保主体，再 global 补封闭区   ← 推荐
```

两个实测踩过的坑：

1. **四角采样会取错背景色**。有些图下边缘有地板/阴影，某个角拿到的是地板色，
   导致整张图去背失败。改用**外圈 2px 环形众数**（`_sample_bg_color`）后修好。
2. **封闭区域**（两腿之间）泛洪填不到，必须靠 global 阶段补。

### 碎片清理

`keep_largest_component(min_ratio=0.35)` —— AI 偶尔在角落多画一个小人，
只保留最大连通分量即可清掉。

### 锚点

角色用 `ANCHOR_FOOT = (24, 40)`（`art-pipeline.md §2`）：
主体底部中心对齐到该点，保证不同角色的"脚"在同一水平线上。

---

## ⚠️ Godot 导入设置（踩过的大坑）

`project.godot` 里的 `import_etc2_astc=true` 是 **Android 导出的强制能力位**，
但它会让 Godot 把**所有**纹理走 ETC2/ASTC **有损** VRAM 压缩 —— 像素画边缘直接糊掉。
第一次截图时地形全成了色块。

**必须**在每个 `.import` 里设：

```
compress/mode=0          # Lossless
mipmaps/generate=false   # 像素画不要 mipmap
detect_3d/compress_to=0  # 别被 3D 检测改回去
```

批量脚本见本目录提交历史（`art/**/*.import` 共 56 个文件已改）。

---

## 分层原则

```
tile (16x16)     只负责材质纹理      —— 程序化生成
逻辑格 (48x48)   负责结构/轮廓/AO    —— 渲染层烘焙（view/raid_scene.gd::_bake_structure）
```

**为什么**：一个逻辑格要铺 3×3 块砖。如果在每块砖上画"墙的顶边"，
一个格子里就会堆出 3 条横杠（实测踩过）。结构信息属于逻辑格，不属于砖。

## 性能

整张 81×81 的地图**烘焙成一张像素图**，用 nearest 放大 16 倍一次绘完。
一次 draw call，而不是 6561 次 `draw_texture_rect` —— 手机上这是关键差异。

---

## 工具清单

| 脚本 | 作用 |
|---|---|
| `tools/art/artlib.py` | 调色板读写 / 量化 / 硬规格 / 校验 |
| `tools/art/gen_comfy.py` | ComfyUI API 批量生成（+ 下采样 + 量化） |
| `tools/art/gen_tiles.py` | 程序化生成可平铺地形 tile |
| `tools/art/postprocess.py` | 去背景 / 去碎片 / 裁主体 / 锚点对齐 |
| `test/screenshot.gd` | 开窗口渲染并截图（headless 没有渲染器，看不到画面） |

## 用法

```powershell
$py = "C:\Users\xxx\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe"
& $py tools\art\gen_comfy.py --list-models
& $py tools\art\gen_comfy.py --batch b_first          # 12 个资产约 140 秒
& $py tools\art\gen_comfy.py --name char_player_side --n 4 --seed 3001
& $py tools\art\gen_tiles.py                          # 21 块地形
& $py tools\art\postprocess.py raw.png out.png --size 48 48
```

## 调色板

`art/palette.gpl` —— **40 色锁定**，11 个功能组：
背景 3 / 墙 5 / 石材 4 / 泥土 4 / 军绿 5 / 木锈 4 / 金属 4 / 血 3 / 火 3 / 科技青 3 / 警示黄 2

所有素材入库前必须量化到它。改这个文件 = 改全项目美术风格，不要随手改。
