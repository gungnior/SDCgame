class_name TestSuite
extends RefCounted

## 测试套件基类。
##
## 每个 `test/suites/*.gd` 继承它，在 `register()` 里登记自己的套件，
## 然后用 `_check` / `_check_eq` 断言。
##
## ⚠️ `_check` / `_check_eq` / `_open_grid` **名字与签名刻意与老的 run_tests.gd 一致** ——
##    这样把测试函数体搬过来时**一个字都不用改**，搬迁风险最低。
##    （`_open_grid` 的实现也是原样抄的：它**会 carve 一个矩形**，
##      不是"全可走" —— 我第一版凭印象写错成全可走，会导致大量断言失效。）

var kit: TestKit = null
## 本文件路径（报错时能定位到文件，而不是只说套件名）
var source_path: String = ""
## 运行器注入的 SceneTree。
##
## ⚠️ 为什么需要：老的 `run_tests.gd` 继承 `SceneTree`，所以测试体里可以
##    直接写 `root.add_child(x)`（有些测试必须把节点挂进树才能触发
##    `_ready` / `_process`）。拆成 `RefCounted` 子类后 `root` 就没了。
##    这里提供**同名访问器**，让搬运过来的函数体一个字都不用改。
var tree: SceneTree = null

var root: Node:
	get:
		return tree.root if tree != null else null


## 子类重写：在这里登记全部套件。
func register() -> void:
	pass


func _suite(name: String, cb: Callable) -> void:
	if kit != null:
		kit.suite(name, cb, source_path)


func _check(cond: bool, label: String) -> void:
	if kit != null:
		kit.check(cond, label)


func _check_eq(actual: Variant, expected: Variant, label: String) -> void:
	if kit != null:
		kit.check_eq(actual, expected, label)


## 造一张"四周是墙、内部可走"的测试网格。
## ⚠️ 原样抄自 run_tests.gd:821 —— 注意它有 carve_rect，
##    所以 (0,0) 等边界格是 SOLID。凭印象写成"全可走"会让边界相关断言全错。
func _open_grid(w: int = 12, h: int = 8) -> LogicalGrid:
	var g := LogicalGrid.new(w, h)
	g.carve_rect(Rect2i(1, 1, w - 2, h - 2))
	return g


# ─────────────────────── 视图层源码读取 ───────────────────────
#
# ⚠️ **为什么需要这个**
# 项目里有一批"源码文本断言"（`_check(src.contains("..."))`）用来防止代码回流 ——
# 它们本身是有价值的，但有一个通病：
# **把「代码在哪」和「代码对不对」绑在了一起。**
#
# 拆分 raid_scene.gd（1676 行）到 5 个文件的过程中，这类断言**失效了 6 次**：
#   HUD  / 地图烘焙 / 世界绘制 / 视野锥 / 键位分派 / 模拟调度
# 每次代码一搬，断言就红 —— 而它想守的其实只是"这段逻辑存在"。
#
# 所以分两类写：
#   · **行为存在**（"自动射击看 visible 不看粘性"）-> 用 `_view_src()` 查整个视图层，
#     代码在层内怎么搬都不会误报
#   · **结构关系**（"场景必须委托、不许自己长回来"）-> 用具体文件名查，
#     这正是防回流要盯的东西
const VIEW_LAYER_FILES := [
	"res://view/raid_scene.gd",
	"res://view/raid_hud.gd",
	"res://view/raid_drawer.gd",
	"res://view/raid_map_baker.gd",
	"res://view/raid_input.gd",
	"res://view/raid_sim_runner.gd",
	"res://view/raid_player_actions.gd",   # 2026-10-13 从 raid_scene 分出的玩家动作
]


## 视图层全部源码拼接。用于"这段逻辑存在于视图层某处"的断言。
func _view_src() -> String:
	var parts: Array[String] = []
	for p in VIEW_LAYER_FILES:
		if ResourceLoader.exists(p) or FileAccess.file_exists(p):
			parts.append(FileAccess.get_file_as_string(p))
	return "\n".join(parts)

