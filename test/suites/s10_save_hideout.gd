extends TestSuite

## 存档与藏身处经济
##
## 由 test/run_tests.gd 拆分而来（测试函数体原样搬运，未改一字）。


func register() -> void:
	_suite("存档：读写与版本迁移", _test_save_manager)
	_suite("藏身处：升级效果接进局内", _test_hideout_effects_reach_raid)
	_suite("藏身处：商人买卖", _test_merchant)
	# ⚠️ 原先【定义了但从未注册】—— 补上（见 test_kit.gd 的说明）
	_suite("补注册：save roundtrip hideout", _test_save_roundtrip_hideout)


func _test_save_manager() -> void:
	# 关联：roadmap-bac.md §2「核心框架（…存档…）」——
	# 这是 M0 清单（action-plan §3）里唯一未完成的技术项。
	#
	# ⚠️ 路径策略是实测出来的：
	#   `user://` 在开发环境写不进去（Godot 子进程被限制在工作区内），
	#   而安卓上必须用 user://。所以 user:// 优先、失败回退到可执行文件旁边。
	var sm := SaveManager.new()
	_check(not sm.path.is_empty(), "解析出了存档路径：%s" % sm.path)
	_check(sm.path.ends_with(SaveManager.SAVE_FILE),
		"路径以 %s 结尾" % SaveManager.SAVE_FILE)

	# 清掉可能存在的旧档，保证从干净状态开始
	sm.delete()
	_check(not sm.exists(), "删除后存档不存在")

	# 从"没有存档"读 -> 明确报告而不是崩
	var r0 := sm.load_save()
	_check(not bool(r0["ok"]), "没有存档时 ok=false")
	_check(not str(r0["error"]).is_empty(), "有明确的原因：%s" % str(r0["error"]))

	# ── 写读往返 ──
	var payload := {
		"hideout": {"wallet": 12345, "upgrades": {"stash_size": 2},
			"stash": {"slots": [], "max_weight": 999.0}},
		"settings": {"auto_fire": true, "auto_aim": false},
		"stats": {"raids": 7, "extracts": 5, "deaths": 2, "kills": 31},
	}
	var err := sm.save(payload)
	_check_eq(err, "", "保存成功（%s）" % err)
	_check(sm.exists(), "存档文件已生成")

	var r1 := sm.load_save()
	_check(bool(r1["ok"]), "读档成功")
	_check_eq(int(r1["data"].get("version", 0)), SaveManager.SAVE_VERSION,
		"写入的版本号是当前版本")
	_check_eq(int((r1["data"]["hideout"] as Dictionary)["wallet"]), 12345, "钱数往返一致")
	_check_eq(int((r1["data"]["stats"] as Dictionary)["kills"]), 31, "统计往返一致")

	# ── 版本迁移 ──
	# v1 的档只有 wallet，缺 upgrades/stash
	var v1 := {"version": 1, "wallet": 999}
	var ok1 := SaveManager.migrate(v1, 1)
	_check(ok1, "v1 能迁移到当前版本")
	_check_eq(int(v1["version"]), SaveManager.SAVE_VERSION, "迁移后版本号被更新")
	_check(v1.has("upgrades") and v1.has("stash"), "v1->v2 补上了 upgrades/stash")
	_check(v1.has("settings") and v1.has("stats"), "v2->v3 补上了 settings/stats")

	# v2
	var v2 := {"version": 2, "wallet": 500, "upgrades": {}, "stash": {}}
	_check(SaveManager.migrate(v2, 2), "v2 能迁移")
	_check_eq(int(v2["version"]), SaveManager.SAVE_VERSION, "v2 迁移后版本正确")

	# 已经是当前版本：迁移应当是空操作
	var v3 := {"version": SaveManager.SAVE_VERSION, "wallet": 1}
	_check(SaveManager.migrate(v3, SaveManager.SAVE_VERSION), "当前版本迁移为空操作")
	_check_eq(int(v3["wallet"]), 1, "空操作不改数据")

	# ── 拒绝比程序更新的档 ──
	# ⚠️ 这条很重要：按旧规则解析新档会得到乱七八糟的状态，
	#    宁可报错也不要把玩家的档读坏。
	# ⚠️ 不能走 sm.save() —— 它总是把 version 覆写成当前版本，
	#    那样根本造不出"未来版本"的档（测试第一版就写错了）。
	#    直接写文件绕过它。
	var ff := FileAccess.open(sm.path, FileAccess.WRITE)
	_check(ff != null, "能直接打开存档文件写入")
	if ff != null:
		ff.store_string(JSON.stringify({
			"version": SaveManager.SAVE_VERSION + 5, "wallet": 1}))
		ff.close()
	var r2 := sm.load_save()
	_check(not bool(r2["ok"]), "拒绝读取比程序新的存档")
	_check(str(r2["error"]).contains("新"), "错误信息说明了版本过新：%s" % str(r2["error"]))

	# ── 坏档不能崩 ──
	var bad := FileAccess.open(sm.path, FileAccess.WRITE)
	if bad != null:
		bad.store_string("这不是 JSON {{{")
		bad.close()
	var r3 := sm.load_save()
	_check(not bool(r3["ok"]), "坏档返回 ok=false")
	_check(not str(r3["error"]).is_empty(), "坏档有明确原因")

	# ── 清理 ──
	sm.delete()
	_check(not sm.exists(), "测试后清理干净")


func _test_hideout_effects_reach_raid() -> void:
	# 真机/设计缺口：`Hideout.raid_modifiers()` / `heal_speed_multiplier()` /
	# `carry_weight_limit()` **全都实现了，但一个都没被调用** ——
	# 也就是玩家花钱买「负重训练」「战地急救」完全没效果。
	var reg := DataRegistry.new()
	reg.load_all("A")
	var gen := MapGenerator.new()
	gen.generate(1234, reg.room_types)

	# ── 无升级：用默认值 ──
	var h0 := Hideout.new(reg.items, 0)
	var r0 := RaidSession.new(reg.items, SimRng.new(1), h0.stash, h0.raid_modifiers())
	_check_eq(r0.carry.slot_count(), RaidSession.DEFAULT_CARRY_SLOTS,
		"无升级时背包格数是默认值")
	_check(absf(r0.carry.max_weight - RaidSession.DEFAULT_CARRY_WEIGHT) < 0.01,
		"无升级时负重上限是默认值 %.1f" % r0.carry.max_weight)
	_check(absf(r0.heal_speed - 1.0) < 0.001, "无升级时治疗速度是 1.0")

	# ── 买升级：必须真的进到局内 ──
	var h1 := Hideout.new(reg.items, 999999)
	h1.buy_upgrade("carry_size")       # +3 kg
	h1.buy_upgrade("carry_size")       # +3 kg
	h1.buy_upgrade("heal_speed")       # +12%
	var mods := h1.raid_modifiers()
	_check(absf(float(mods["carry_weight_limit"]) - h1.carry_weight_limit()) < 0.001,
		"raid_modifiers 里的负重上限与 Hideout 一致")
	var r1 := RaidSession.new(reg.items, SimRng.new(2), h1.stash, mods)
	_check(absf(r1.carry.max_weight - h1.carry_weight_limit()) < 0.001,
		"局内负重上限真的用了升级值（%.1f kg）" % r1.carry.max_weight)
	_check(r1.carry.max_weight > r0.carry.max_weight + 5.0,
		"升了两级后确实更宽（%.1f > %.1f）" % [r1.carry.max_weight, r0.carry.max_weight])
	_check(absf(r1.heal_speed - h1.heal_speed_multiplier()) < 0.001,
		"局内治疗速度用了升级值（%.2f）" % r1.heal_speed)
	_check(r1.heal_speed > 1.0, "治疗速度确实变快了")

	# ── 治疗速度真的缩短耗时 ──
	var bandage: ItemDef = reg.get_item("medical_bandage")
	var md := MedicalSystem.new()
	var vit := Vitals.new()
	vit.reset(100, 40)
	vit.hp = 10
	_check_eq(md.start(bandage, vit), "", "无加成时能开始治疗")
	var base_dur := md.duration
	md.cancel()
	md.set_speed_multiplier(r1.heal_speed)
	vit.hp = 10
	_check_eq(md.start(bandage, vit), "", "有加成时能开始治疗")
	_check(md.duration < base_dur,
		"升级后治疗耗时更短（%.2fs < %.2fs）" % [md.duration, base_dur])
	# 倍率夹取：极端值不能变成 0 秒或无穷
	md.cancel()
	md.set_speed_multiplier(999.0)
	_check(md.speed_multiplier <= 5.0, "倍率有上限（%.1f）" % md.speed_multiplier)
	md.set_speed_multiplier(-5.0)
	_check(md.speed_multiplier >= 0.2, "倍率有下限（%.1f）" % md.speed_multiplier)

	# ── 商人回收比例也受升级影响 ──
	var h2 := Hideout.new(reg.items, 999999)
	var before := h2.sell_ratio()
	h2.buy_upgrade("merchant_rep")
	_check(h2.sell_ratio() > before,
		"「商人关系」升级提升回收比例（%.2f -> %.2f）" % [before, h2.sell_ratio()])


func _test_merchant() -> void:
	# `Hideout.buy/sell/stock_price` 早就实现了，缺的是 UI 入口（已补 MerchantPanel）。
	# 这里测交易逻辑本身。
	var reg := DataRegistry.new()
	reg.load_all("A")
	var h := Hideout.new(reg.items, 1000)

	# 买入：钱够
	var price := h.stock_price("ammo_rifle")
	_check(price > 0, "步枪弹有售价 %d" % price)
	_check_eq(h.buy("ammo_rifle", 10), "", "买 10 发成功")
	_check_eq(h.stash.count_of("ammo_rifle"), 10, "仓库收到 10 发")
	_check_eq(h.wallet, 1000 - price * 10, "钱扣对了（%d）" % h.wallet)

	# 买入：钱不够要有明确原因、且不能扣钱
	var w0 := h.wallet
	var e1 := h.buy("valuables_gpu", 1)
	_check(not e1.is_empty(), "钱不够时返回原因：%s" % e1)
	_check_eq(h.wallet, w0, "失败时不能扣钱")

	# 买入不存在的物品
	_check(not h.buy("no_such_item", 1).is_empty(), "买不存在的物品有原因")

	# 卖出：按回收比例
	var ratio := h.sell_ratio()
	var def: ItemDef = reg.get_item("ammo_rifle")
	var expect_unit := int(round(float(def.value) * ratio))
	var got := h.sell("ammo_rifle", 4)
	_check_eq(got, expect_unit * 4, "卖出到账 %d（单价 %d x4）" % [got, expect_unit])
	_check_eq(h.stash.count_of("ammo_rifle"), 6, "仓库剩下 6 发")

	# 卖不存在的
	_check_eq(h.sell("no_such_item", 1), 0, "卖不存在的物品返回 0")
	_check_eq(h.sell("ammo_rifle", 0), 0, "卖 0 个返回 0")

	# 卖超量：只卖仓库里有的
	var have := h.stash.count_of("ammo_rifle")
	var got2 := h.sell("ammo_rifle", 999)
	_check_eq(got2, expect_unit * have, "卖超量只卖实际持有的（%d 发）" % have)
	_check_eq(h.stash.count_of("ammo_rifle"), 0, "卖光了")

	# 仓库满时买入要报错而不是吞钱
	var tiny := Hideout.new(reg.items, 999999)
	tiny.stash.set_slot_capacity(1)
	var e2 := tiny.buy("armor_heavy", 3)
	_check(not e2.is_empty(), "仓库放不下时返回原因：%s" % e2)


func _test_save_roundtrip_hideout() -> void:
	# 藏身处状态【真的】能存下来并读回去 —— 不只是 JSON 往返，
	# 而是 Hideout 这个对象本身。
	var reg := DataRegistry.new()
	reg.load_all("A")
	var sm := SaveManager.new()
	sm.delete()

	# 造一个有状态变化的藏身处
	#
	# ⚠️ 这个测试原本【定义了却从未注册】，所以**一直是坏的也没人发现**。
	#    第一次真跑就失败：给 4321 元不够 —— 升级会涨价
	#    （stash_size 1500 -> 2700），买两次后只剩 121，carry_size 根本买不起。
	#    现在给足钱，并**断言每一次 buy_upgrade 都成功**，
	#    这样以后价格表改了会在这里立刻报错，而不是让后续断言莫名其妙地失败。
	var h1 := Hideout.new(reg.items, 50000)
	_check_eq(h1.buy_upgrade("stash_size"), "", "第 1 次仓库扩建成功")
	_check_eq(h1.buy_upgrade("stash_size"), "", "第 2 次仓库扩建成功")
	_check_eq(h1.buy_upgrade("carry_size"), "", "负重训练成功")
	h1.stash.add("medical_bandage", 3)
	h1.stash.add("ammo_rifle", 60)
	var wallet_before := h1.wallet

	_check_eq(sm.save({"hideout": h1.to_dict()}), "", "保存藏身处")
	var r := sm.load_save()
	_check(bool(r["ok"]), "读回藏身处")

	var h2 := Hideout.new(reg.items, 0)
	h2.from_dict(r["data"]["hideout"])
	_check_eq(h2.level_of("stash_size"), 2, "升级等级往返一致")
	_check_eq(h2.level_of("carry_size"), 1, "第二个升级也一致")
	_check_eq(h2.wallet, wallet_before, "资金往返一致（%d）" % wallet_before)
	_check_eq(h2.stash.count_of("medical_bandage"), 3, "仓库物品往返一致")
	_check_eq(h2.stash.count_of("ammo_rifle"), 60, "第二件也一致")

	# ⚠️ 关键：读回来之后**效果函数必须跟着新等级走**。
	#    只恢复等级数字、不重新应用，就会出现"升级了但仓库没变大"。
	_check_eq(h2.slot_count(), h1.slot_count(), "仓库槽位效果一致（%d）" % h2.slot_count())
	_check(absf(h2.carry_weight_limit() - h1.carry_weight_limit()) < 0.001,
		"负重上限效果一致（%.1f kg）" % h2.carry_weight_limit())
	_check(absf(h2.sell_ratio() - h1.sell_ratio()) < 0.001, "商人回收比例一致")
	_check(h2.slot_count() > SaveManager.SAVE_VERSION * 0 + 40,
		"升级后仓库确实比基础多（%d > 40）" % h2.slot_count())

	sm.delete()


# ─────────────────── ③ 群体 AI ───────────────────
