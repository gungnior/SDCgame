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
