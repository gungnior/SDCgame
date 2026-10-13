class_name UITokens

## 设计令牌（Design Tokens）—— 全 UI 的**唯一视觉来源**
##
## 为什么要有这个文件：
##   改 UI 之前，~250 个 `Color(...)` 硬编码散在 20 个文件里，每个面板自己一套色，
##   字号也是 12/13/14/15/18/20/34 随手写。后果：界面之间"看起来像不同的游戏"，
##   想统一调个色调要改 20 处，漏一处就花脸。
##
## 设计定调（简洁不失美观）：
##   · **冷底 + 一点暖**：深蓝灰底（军事/潜行感）+ 琥珀金主强调（撤离/贵重/警示），
##     冷暖对比就是层次，不需要贴图也能有质感。
##   · **强调色纪律**：全局只有 1 个主强调色（ACCENT），其余四色只表达语义
##     （危险/成功/信息/稀有），不允许拿来"好看"。
##   · **三层 elevation**：场景底 < 面板 < 卡片 < 浮层，用不透明度 + 边框亮度区分，
##     不用投影（俯视 2D 加投影会脏）。
##   · **全部数值走 4 的倍数**（间距/圆角），对齐像素栅格，避免半像素模糊。
##
## 用法：`UITokens.ACCENT` / `UITokens.panel_box()` —— 不要在业务代码里再写 Color。

# ─────────────────────────── 底色（三层 elevation）──────────────────────────
## 场景最底层（主菜单/战局背景）
const BG_DEEP := Color(0.055, 0.065, 0.085)
## 面板底（弹窗/侧栏）
const BG_PANEL := Color(0.098, 0.112, 0.138, 0.95)
## 卡片底（列表条目/格子）
const BG_CARD := Color(0.150, 0.168, 0.200, 0.92)
## 抬起层（浮层/弹窗/提示）
const BG_RAISED := Color(0.196, 0.216, 0.252, 0.96)

# ─────────────────────────── 边框 ───────────────────────────
const BORDER := Color(0.32, 0.36, 0.43, 0.55)
const BORDER_HI := Color(0.46, 0.51, 0.60, 0.80)

# ─────────────────────────── 文字（四档，亮度即层级）──────────────────────────
const TEXT_HI := Color(0.965, 0.975, 0.990)     ## 标题 / 关键数值
const TEXT := Color(0.845, 0.875, 0.920)        ## 正文
const TEXT_MID := Color(0.660, 0.700, 0.770)    ## 次要说明
const TEXT_LOW := Color(0.470, 0.510, 0.590)    ## 提示 / 禁用

# ─────────────────────────── 强调与功能色 ───────────────────────────
## 主强调：琥珀金（撤离点/贵重/选中态）
const ACCENT := Color(0.980, 0.720, 0.250)
const ACCENT_DIM := Color(0.980, 0.720, 0.250, 0.35)
const DANGER := Color(0.905, 0.320, 0.300)      ## 危险 / 阵亡 / 开火
const SUCCESS := Color(0.420, 0.800, 0.480)     ## 成功 / 撤离 / 治疗
const INFO := Color(0.400, 0.700, 0.950)        ## 信息 / 换弹 / 选中
const RARE := Color(0.720, 0.520, 0.960)        ## 稀有度专用（不挪作他用）
const STEALTH := Color(0.620, 0.860, 0.820)     ## 静步 / 潜行专用（青，与 INFO 蓝区分）
const NEUTRAL := Color(0.720, 0.760, 0.840)     ## 中性（设置/系统按钮）

# ─────────────────────────── 字号阶梯（640×360 视口专用）──────────────────────────
## 640×360 会被整数倍放大到手机（约 3x），所以这里是"逻辑像素"，不是物理像素。
const FS_DISPLAY := 28   ## 游戏大标题
const FS_TITLE := 20     ## 面板标题
const FS_HEAD := 16      ## 分区小标题
const FS_BODY := 13      ## 正文 / 列表默认
const FS_CAPTION := 11   ## 提示 / 次要说明

# ─────────────────────────── 间距 / 圆角（4 的倍数）──────────────────────────
const SP_1 := 4.0
const SP_2 := 8.0
const SP_3 := 12.0
const SP_4 := 16.0
const SP_6 := 24.0

const R_SM := 4.0    ## 小控件 / 标签底
const R_MD := 8.0    ## 卡片 / 按钮
const R_LG := 12.0   ## 面板 / 弹窗

## 按钮最小点击区（触屏人机工效：逻辑像素下 ≥ 44 才够手指）
const TAP_MIN := 44.0


# ─────────────────────────── StyleBoxFlat 助手 ───────────────────────────
## 面板底：圆角 + 边框 + 不透明底色
static func panel_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BG_PANEL
	s.border_color = BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(int(R_LG))
	s.content_margin_left = int(SP_3)
	s.content_margin_right = int(SP_3)
	s.content_margin_top = int(SP_2)
	s.content_margin_bottom = int(SP_2)
	s.anti_slicing = false
	return s


## 卡片底：用于列表条目 / 格子（无内容边距，由调用方排）
static func card_box(radius: float = R_MD) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BG_CARD
	s.border_color = BORDER
	s.set_border_width_all(1)
	s.set_corner_radius_all(int(radius))
	s.anti_slicing = false
	return s


## 浮层底：数量弹窗 / 提示（最亮一层 + 亮边，视觉上"浮"起来）
static func raised_box() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = BG_RAISED
	s.border_color = BORDER_HI
	s.set_border_width_all(1)
	s.set_corner_radius_all(int(R_LG))
	s.content_margin_left = int(SP_3)
	s.content_margin_right = int(SP_3)
	s.content_margin_top = int(SP_3)
	s.content_margin_bottom = int(SP_3)
	s.anti_slicing = false
	return s


## 选中 / 强调底：主强调色低透明度 + 亮边（用于选中行、当前标签）
static func accent_box(radius: float = R_MD) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.16)
	s.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.65)
	s.set_border_width_all(1)
	s.set_corner_radius_all(int(radius))
	s.anti_slicing = false
	return s


## 把任意颜色按 alpha 淡化（用于"按下/禁用"等派生态，避免各处自己 lerp）
static func fade(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)
