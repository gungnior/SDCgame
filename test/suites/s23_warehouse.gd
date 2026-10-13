extends TestSuite

## 2026-10-14「优化藏身处仓库」回归：
##   ① 扩容：基础槽位 40 -> 64，升级继续叠加
##   ② 分类：category -> 标签页分组映射
##   ③ 过滤+排序：stash_entries_filtered(group, sort_mode)

func register() -> void:
	_suite("仓库扩容：基础槽位 40->64", _test_capacity)
	_suite("仓库分类映射 group_of", _test_grouping)
	_suite("仓库过滤+排序 stash_entries_filtered", _test_filter_sort)


func _test_capacity() -> void:
	var reg := DataRegistry.new()
	reg.load_all("B")
	var h := Hideout.new(reg.items)
	_check(h.slot_count() >= 64, "仓库基础槽位 >= 64（原 40 扩容）")
	# 升级继续叠加（不回归）
	h.wallet = 999999
	var e := h.buy_upgrade("stash_size")
	_check(e == "", "能买仓库扩建（%s）" % e)
	_check(h.slot_count() > 64, "买仓库扩建后槽位继续增加（%d）" % h.slot_count())


func _test_grouping() -> void:
	_check_eq(Hideout.group_of("weapon"), "武器", "weapon -> 武器")
	_check_eq(Hideout.group_of("armor"), "护甲", "armor -> 护甲")
	_check_eq(Hideout.group_of("helmet"), "护甲", "helmet -> 护甲")
	_check_eq(Hideout.group_of("ammo"), "弹药", "ammo -> 弹药")
	_check_eq(Hideout.group_of("medical"), "医疗", "medical -> 医疗")
	_check_eq(Hideout.group_of("consumable"), "医疗", "consumable -> 医疗")
	_check_eq(Hideout.group_of("valuables"), "贵重", "valuables -> 贵重")
	_check_eq(Hideout.group_of("key"), "贵重", "key -> 贵重")
	_check_eq(Hideout.group_of(""), "杂物", "未知 -> 杂物")
	_check_eq(Hideout.group_of("backpack"), "杂物", "背包 -> 杂物")


func _test_filter_sort() -> void:
	var reg := DataRegistry.new()
	reg.load_all("B")
	var h := Hideout.new(reg.items)
	# 每类放一个代表物（id 来自 data/items.json）
	h.stash.add("weapon_rifle", 1)
	h.stash.add("armor_heavy", 1)
	h.stash.add("ammo_rifle", 30)
	h.stash.add("medical_kit", 2)
	h.stash.add("valuables_gpu", 1)

	# 全部：每类一行
	var all := h.stash_entries_filtered("全部", 0)
	_check_eq(all.size(), 5, "全部：5 类各 1 行")

	# 按武器过滤
	var w := h.stash_entries_filtered("武器", 0)
	_check_eq(w.size(), 1, "武器标签只 1 行")
	_check_eq(Hideout.group_of(h.category_of(str(w[0]["id"]))), "武器", "该行确为武器")

	# 按弹药过滤
	var a := h.stash_entries_filtered("弹药", 0)
	_check_eq(a.size(), 1, "弹药标签只 1 行")
	_check_eq(str(a[0]["id"]), "ammo_rifle", "弹药行是 ammo_rifle")

	# 排序：名称升序（全序）
	var by_name := h.stash_entries_filtered("全部", 1)
	var ok_name := true
	for i in range(1, by_name.size()):
		if str(by_name[i - 1]["name"]) > str(by_name[i]["name"]):
			ok_name = false
	_check(ok_name, "名称升序（全序）")

	# 排序：数量降序（全序）
	var by_cnt := h.stash_entries_filtered("全部", 2)
	var ok_cnt := true
	for i in range(1, by_cnt.size()):
		if int(by_cnt[i - 1]["count"]) < int(by_cnt[i]["count"]):
			ok_cnt = false
	_check(ok_cnt, "数量降序（全序）")
