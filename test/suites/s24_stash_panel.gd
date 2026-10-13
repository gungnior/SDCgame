extends TestSuite

## 2026-10-14「优化藏身处仓库（UI）+ 再次扩大地图」回归：
##   ① StashPanel：分类标签 + 排序 + 全量滚动（消费 s23 的 stash_entries_filtered / group_of）
##   ② 藏身处接线：stash_panel 创建 / 打开入口 / 关闭后存档+刷新
##   ③ 地图扩大到 56/64/72：三主题按新尺寸生成成功、grid 匹配、撤离点达标
##
## 只用显式类型（避开 untyped Array 上的 := 推断陷阱，同 s18）。

func register() -> void:
	_suite("仓库面板：标签/排序/全量列表", _test_stash_panel_ui)
	_suite("仓库面板：藏身处接线（结构）", _test_stash_wiring)
	_suite("地图扩大：三主题 56/64/72 可生成", _test_map_enlarged)


func _reg() -> DataRegistry:
	var reg := DataRegistry.new()
	reg.load_all("C")       # 地图主题是 stage C，必须用 C 才能拿到 maps
	return reg


func _hideout_with_loot(reg: DataRegistry) -> Hideout:
	var h := Hideout.new(reg.items)
	# 每类放一个代表物（id 来自 data/items.json）
	h.stash.add("weapon_rifle", 1)
	h.stash.add("armor_heavy", 1)
	h.stash.add("ammo_rifle", 30)
	h.stash.add("medical_kit", 2)
	h.stash.add("valuables_gpu", 1)
	return h


# ═══════════════ ① StashPanel UI ═══════════════

func _test_stash_panel_ui() -> void:
	var reg := _reg()
	var h := _hideout_with_loot(reg)

	var sp := StashPanel.new()
	sp.call("_ensure_built")
	_check(sp.get_child_count() > 0, "仓库面板 _ensure_built 建出了节点")
	_check(not sp.is_open(), "仓库面板初始是关的")
	sp.open(h)
	_check(sp.is_open() and sp.visible, "仓库面板能打开且可见")
	_check(sp.size.x > 100.0 and sp.size.y > 100.0,
		"面板尺寸被 _fit_viewport 钉住（%s）—— 否则整块塌成 0" % str(sp.size))

	# 标签数 == 分组数（含"全部"），排序按钮 == 3
	_check_eq(sp._tab_buttons.size(), StashPanel.GROUPS.size(), "分类标签数 == GROUPS（含全部）")
	_check_eq(sp._sort_buttons.size(), StashPanel.SORTS.size(), "排序按钮数 == SORTS")

	# 全量列表：默认「全部」= 5 行
	_check_eq(sp._list.get_child_count(), 5, "默认全部：5 行")
	# 切到「弹药」：只剩 1 行
	sp.call("_on_tab", "弹药")
	_check_eq(sp._list.get_child_count(), 1, "切到弹药标签：1 行")
	# 切回全部 + 按名称排序：仍是 5 行（排序不改变数量，只改顺序）
	sp.call("_on_tab", "全部")
	sp.call("_on_sort", 1)
	_check_eq(sp._list.get_child_count(), 5, "排序后仍 5 行")

	# 空分类给提示行、不崩（切到没有"护甲以外"……这里造一个真空的：清空仓库再切）
	var empty_h := Hideout.new(reg.items)
	var sp2 := StashPanel.new()
	sp2.call("_ensure_built")
	sp2.open(empty_h)
	_check(sp2._list.get_child_count() >= 1, "空仓库也有占位提示行（不崩）")

	# 关闭 -> is_open false + closed 信号
	var fired := [false]
	sp.closed.connect(func(): fired[0] = true)
	sp.call("_on_close")
	_check(not sp.is_open(), "仓库面板能关闭")
	_check(fired[0], "关闭时发出 closed 信号")


# ═══════════════ ② 藏身处接线（结构，防回流）═══════════════

func _test_stash_wiring() -> void:
	var hs := FileAccess.get_file_as_string("res://view/hideout_scene.gd")
	var ps := FileAccess.get_file_as_string("res://ui/stash_panel.gd")
	_check(hs.contains("stash_panel = StashPanel.new()"), "藏身处创建 StashPanel")
	_check(hs.contains("func _open_stash"), "藏身处有 _open_stash 入口")
	_check(hs.contains("stash_panel.closed.connect"), "关闭仓库后存档+刷新")
	_check(ps.contains("stash_entries_filtered"), "仓库面板用 stash_entries_filtered 取数据")
	_check(ps.contains("group_of"), "仓库面板用 group_of 分组")
	_check(ps.contains("GROUPS") and ps.contains("SORTS"), "仓库面板定义分类与排序常量")


# ═══════════════ ③ 地图扩大后仍可生成 ═══════════════

func _test_map_enlarged() -> void:
	var reg := _reg()
	var forest: MapThemeDef = reg.get_map("map_forest")
	var urban: MapThemeDef = reg.get_map("map_urban")
	var military: MapThemeDef = reg.get_map("map_military")
	_check(forest != null and urban != null and military != null, "三主题都存在")

	_check_eq(forest.map_w, 56, "森林扩到 56")
	_check_eq(urban.map_w, 64, "城区扩到 64")
	_check_eq(military.map_w, 72, "军事基地扩到 72")
	_check(military.map_w > urban.map_w and urban.map_w > forest.map_w, "尺寸仍严格递增")
	_check(military.map_w <= 128, "最大不超过校验上限 128")

	var themes: Array[MapThemeDef] = [forest, urban, military]
	for t in themes:
		var tname: String = t.name
		var ok_any := false
		for s in [20261013, 20261014, 777, 4242, 99]:
			var gen := MapGenerator.new()
			if gen.generate(s, reg.room_types, t.map_w, t.map_h, t):
				ok_any = true
				_check_eq(gen.grid_w, t.map_w, "%s 生成宽度==主题(%d)" % [tname, t.map_w])
				_check_eq(gen.grid_h, t.map_h, "%s 生成高度==主题(%d)" % [tname, t.map_h])
				_check(gen.graph.rooms.size() >= 8,
					"%s 房间数 >= 8（实际 %d）" % [tname, gen.graph.rooms.size()])
				_check(gen.extract_rooms().size() >= 2,
					"%s 撤离点 >= 2（实际 %d）" % [tname, gen.extract_rooms().size()])
				break
		_check(ok_any, "%s 在扩大后的尺寸能生成地图" % tname)
