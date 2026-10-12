extends SceneTree

## Headless 测试运行器（**拆分后只剩下调度**）
##
## 运行方式：
##   godot --headless --path . --script res://test/run_tests.gd
##
## 退出码 = 失败数（0 = 全部通过），可直接作为 CI gate。
##
## ─────────────────────────────────────────────────────────────
## 为什么拆
## ─────────────────────────────────────────────────────────────
## 这个文件曾长到 **3439 行 / 59 个套件**，而统计 36 次提交里有 **67% 都要改它**。
## 它和 `view/raid_scene.gd`（50%）一起构成本项目的两个单点 ——
## 任何"多人并行开工"的尝试都会先撞在这两个文件上。
##
## 现在：框架在 `test/test_kit.gd`，基类在 `test/suite_base.gd`，
## 套件在 `test/suites/*.gd`，本文件只负责**发现 + 调度 + 守卫**。
##
## ─────────────────────────────────────────────────────────────
## ⚠️ 新增的结构性守卫（这条本身就是一个 bug 的产物）
## ─────────────────────────────────────────────────────────────
## 拆分前发现：**4 个 `_test_*` 函数定义了却从未注册**（合计 89 行）——
## `_test_corpse_interaction_visible` / `_test_settings_menu_layout` /
## `_test_whitebox_is_default` / `_test_save_roundtrip_hideout`。
## 根因是补丁脚本往文件里追加了函数、却只登记了其中一个，
## 于是它们**静默地从不执行** —— "746 项通过"里根本不含这些测试。
##
## 靠人眼扫 `_suite(...)` 列表发现不了，所以这里加机器守卫：
## **任何 `test/suites/*.gd` 里定义了却没登记的 `_test_*` 一律判失败。**
## 这才让"拆成多文件"真正安全 —— 否则文件越多，漏注册越难发现。

const SUITES_DIR := "res://test/suites"


func _initialize() -> void:
	print("")
	print("=== 项目测试  (Godot %s) ===" % Engine.get_version_info().string)
	print("")

	var kit := TestKit.new()
	var loaded: Array = []          # [{path, script, instance}]
	var load_failures: Array[String] = []

	# ── ① 发现并注册（按文件名排序 -> 顺序稳定，输出可对比）──
	for path in _discover():
		var sc: GDScript = load(path)
		if sc == null:
			# ⚠️ 不能让"套件文件载入失败"变成静默降级 ——
			#    那等于覆盖率悄悄变少，而运行器还报"全部通过"。
			#    （和"定义了但没注册"是同一类问题：失败必须显式可见。）
			load_failures.append(path)
			continue
		var inst: Object = sc.new()
		if not (inst is TestSuite):
			load_failures.append("%s（没有 extends TestSuite）" % path)
			continue
		inst.kit = kit
		inst.source_path = path
		inst.tree = self          # 部分测试需要 root 才能挂节点进树
		inst.register()
		loaded.append({"path": path, "script": sc, "inst": inst})

	if kit.suite_count() == 0:
		print("❌ 一个套件都没发现，检查 %s" % SUITES_DIR)
		quit(1)
		return

	# ── ② ⭐ 结构性守卫：定义了但没登记的测试 ──
	var orphans: Array[String] = []
	for e in loaded:
		for m in kit.defined_but_unregistered(e["script"]):
			orphans.append("%s :: %s" % [str(e["path"]).get_file(), m])

	# ── ③ 跑 ──
	kit.run_all()

	# ── ④ 守卫结果计入失败（不能被"其他都过了"掩盖）──
	if not load_failures.is_empty():
		kit.failed += 1
		print("[结构守卫：套件文件必须能载入]")
		for f in load_failures:
			print("  FAIL  载入失败 -> %s" % f)
		print("        载入不了的套件等于**覆盖率悄悄变少**，必须显式失败。")

	if not orphans.is_empty():
		kit.failed += 1
		print("[结构守卫：测试函数必须被登记]")
		for o in orphans:
			print("  FAIL  定义了但从未注册 -> %s" % o)
		print("        这些测试**永远不会执行**，等于没写。请在本文件的 register() 里补上。")

	kit.report()
	print("套件文件 %d 个，套件 %d 个" % [loaded.size(), kit.suite_count()])
	print("")
	quit(kit.failed)


## 列出 test/suites/ 下的全部 .gd（排序保证顺序稳定）
func _discover() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(SUITES_DIR)
	if d == null:
		push_error("[测试] 打不开 %s" % SUITES_DIR)
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(SUITES_DIR.path_join(f))
	out.sort()
	return out
