class_name TestKit
extends RefCounted

## 迷你测试框架（从 run_tests.gd 抽出来，**行为与输出格式逐字节保留**）
##
## 为什么抽出来：`run_tests.gd` 曾长到 **3439 行 / 59 个套件**，
## 而 **67% 的功能提交都要改它** —— 它和 `raid_scene.gd` 一起构成两个单点。
## 拆开之后：框架在这里，套件在 `test/suites/*.gd`，各自独立可改。
##
## ⚠️ 输出格式**刻意与原实现一致**（`  ok    xxx` / `  FAIL  xxx   <-- [套件]`）。

var passed := 0
var failed := 0
var current := ""

## 待跑队列：[{name, cb, method, source}]
var _pending: Array = []


## 登记一个套件。由各 TestSuite.register() 调用。
func suite(name: String, cb: Callable, source: String = "") -> void:
	_pending.append({
		"name": name, "cb": cb,
		"method": cb.get_method() if cb.is_valid() else "",
		"source": source,
	})


func suite_count() -> int:
	return _pending.size()


## 本 kit 已登记的方法名集合（结构性守卫用）
func registered_methods() -> Dictionary:
	var d := {}
	for e in _pending:
		var m := str(e["method"])
		if m != "":
			d[m] = true
	return d


## 依次跑完全部已登记套件。返回失败数。
func run_all() -> int:
	for e in _pending:
		current = str(e["name"])
		print("[%s]" % current)
		var cb: Callable = e["cb"]
		if cb.is_valid():
			cb.call()
		else:
			failed += 1
			print("  FAIL  套件回调无效（目标已释放？）   <-- [%s]" % current)
	return failed


func check(cond: bool, label: String) -> void:
	if cond:
		passed += 1
		print("  ok    %s" % label)
	else:
		failed += 1
		print("  FAIL  %s   <-- [%s]" % [label, current])


func check_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		passed += 1
		print("  ok    %s" % label)
	else:
		failed += 1
		print("  FAIL  %s  (期望 %s，实际 %s)   <-- [%s]" % [
			label, str(expected), str(actual), current])


## 汇总报告（格式与原实现一致）
func report() -> void:
	print("")
	if failed == 0:
		print("通过：%d 项，0 失败" % passed)
	else:
		print("失败：%d 项通过，%d 项失败" % [passed, failed])
	print("")


## ⭐ 结构性守卫：找出"定义了但没登记"的 `_test_*` 方法名。
##
## ⚠️ 这条守卫是有来历的。拆分前发现 **4 个 `_test_*` 函数从未被注册**
##    （合计 89 行）：
##      _test_corpse_interaction_visible / _test_settings_menu_layout /
##      _test_whitebox_is_default / _test_save_roundtrip_hideout
##    根因是**补丁脚本往文件里追加了函数，却只登记了其中一个** ——
##    那些测试于是**静默地从不执行**，"746 项通过"里根本不含它们。
##    靠人眼看 `_suite(...)` 列表发现不了，必须机器守。
func defined_but_unregistered(script: GDScript) -> Array[String]:
	var out: Array[String] = []
	if script == null:
		return out
	var reg := registered_methods()
	var seen := {}
	for m in script.get_script_method_list():
		var n := str(m.get("name", ""))
		if not n.begins_with("_test_"):
			continue
		if seen.has(n):
			continue
		seen[n] = true
		if not reg.has(n):
			out.append(n)
	return out
