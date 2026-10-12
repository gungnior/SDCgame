class_name SaveManager
extends RefCounted

## 存档模块（含版本迁移骨架）
##
## 依据 specs/roadmap-bac.md §2「核心框架（状态机 / 事件总线 / **存档** / 配置）」，
## 这是 M0 清单里唯一未完成的技术项（action-plan.md §3）。
##
## ⚠️ 路径策略（实测踩过才这么写）：
##   `user://` 在**开发环境里写不进去**（Godot 子进程被限制在工作区内），
##   实测：`user://a.txt` -> err 12；`AppData` 下的绝对路径 -> err 7/12；
##   而**可执行文件旁边** -> 成功。
##   但**安卓上必须用 `user://`**（那里只有 user:// 可写）。
##   所以：**`user://` 优先，失败则回退到可执行文件旁边**（可移植模式），
##   并把实际使用的路径暴露出来，别让存档静默丢。
##
## 纯 RefCounted，可 headless 单测。

## 当前存档格式版本。**每次改档结构必须 +1，并补一条迁移规则。**
const SAVE_VERSION := 3
const SAVE_FILE := "soudache_save.json"
## 迁移链：from_version -> 函数(把该版本的数据升到 from_version+1)
## 用字典而不是一串 if，这样"有哪些迁移"一眼看得全。
const MIGRATIONS := {
	1: "_migrate_1_to_2",
	2: "_migrate_2_to_3",
}

var path: String = ""               ## 实际使用的存档路径
var last_error: String = ""
var used_fallback: bool = false     ## 是否用了"可移植"回退路径


func _init() -> void:
	path = _resolve_path()


## 依次尝试 user:// 与可执行文件旁边，返回**第一个真的能写**的路径。
func _resolve_path() -> String:
	# ① user://（安卓唯一可用；桌面正常环境下也可用）
	if _writable("user://"):
		used_fallback = false
		return "user://" + SAVE_FILE
	# ② 可执行文件旁边（本项目的开发环境走这条）
	var exe_dir := OS.get_executable_path().get_base_dir()
	var alt := exe_dir.path_join(SAVE_FILE)
	if _writable(alt.get_base_dir()):
		used_fallback = true
		return alt
	# ③ 都不行：仍返回 user://（让调用方拿到明确报错，而不是静默不存）
	last_error = "找不到可写的存档目录"
	used_fallback = false
	return "user://" + SAVE_FILE


## 往目录里试写一个探针文件来判断可写性
func _writable(dir_path: String) -> bool:
	var probe := dir_path.path_join(".write_probe")
	var f := FileAccess.open(probe, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string("1")
	f.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(probe))
	return true


func exists() -> bool:
	return FileAccess.file_exists(path)


func delete() -> void:
	if exists():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# ─────────────────── 写 ───────────────────

## 保存。返回失败原因（空串 = 成功）。
##
## 先写临时文件再改名 —— 避免"写到一半掉电"把好档写坏。
func save(data: Dictionary) -> String:
	last_error = ""
	var payload := data.duplicate(true)
	payload["version"] = SAVE_VERSION
	payload["saved_at"] = Time.get_datetime_string_from_system()
	var text := JSON.stringify(payload, "  ", false)

	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		last_error = "打不开临时文件 %s（err %d %s）" % [
			tmp, FileAccess.get_open_error(), error_string(FileAccess.get_open_error())]
		return last_error
	f.store_string(text)
	f.close()

	# 改名（先删目标，Godot 的 rename 不覆盖已存在文件）
	if exists():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var err := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(tmp),
		ProjectSettings.globalize_path(path))
	if err != OK:
		last_error = "改名失败（err %d %s）" % [err, error_string(err)]
		return last_error
	return ""


# ─────────────────── 读 ───────────────────

## 读取并迁移到当前版本。
## 返回 {ok: bool, data: Dictionary, error: String, migrated_from: int}
func load_save() -> Dictionary:
	last_error = ""
	if not exists():
		return {"ok": false, "data": {}, "error": "存档不存在", "migrated_from": 0}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "data": {}, "error": "打不开存档：%s" % path,
			"migrated_from": 0}
	var text := f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return {"ok": false, "data": {}, "error": "存档不是合法 JSON",
			"migrated_from": 0}

	var d: Dictionary = parsed
	var from := int(d.get("version", 0))
	if from <= 0:
		return {"ok": false, "data": {}, "error": "存档没有版本号", "migrated_from": 0}
	# ⚠️ 比当前新的档不读 —— 宁可报错，也不要按旧规则解析出乱七八糟的状态
	if from > SAVE_VERSION:
		return {"ok": false, "data": {},
			"error": "存档版本 %d 比程序支持的 %d 新，拒绝读取" % [from, SAVE_VERSION],
			"migrated_from": from}

	var migrated_ok := migrate(d, from)
	if not migrated_ok:
		return {"ok": false, "data": {}, "error": last_error, "migrated_from": from}
	return {"ok": true, "data": d, "error": "", "migrated_from": from}


## 把 d 从 from_version 逐级升到 SAVE_VERSION。
## 返回是否成功；失败时 last_error 有原因。
static func migrate(d: Dictionary, from_version: int) -> bool:
	var v := from_version
	var guard := 0
	while v < SAVE_VERSION:
		guard += 1
		if guard > 64:
			return false
		var fn := str(MIGRATIONS.get(v, ""))
		if fn == "":
			# 缺迁移规则：不能瞎猜，直接拒绝
			return false
		# 用 Callable 调静态函数
		Callable(SaveManager, fn).call(d)
		v += 1
		d["version"] = v
	return true


# ─────────────────── 迁移规则（每加一条都要写清"为什么") ───────────────────
#
# 约定：函数只负责把 d 从 v 改成 v+1 的结构，**不动 version 字段**
#（上面的循环会写）。

## v1 -> v2：早期档只有 wallet，没有 upgrades/stash
static func _migrate_1_to_2(d: Dictionary) -> void:
	if not d.has("upgrades"):
		d["upgrades"] = {}
	if not d.has("stash"):
		d["stash"] = {"slots": [], "max_weight": 999.0}
	if not d.has("wallet"):
		d["wallet"] = 0


## v2 -> v3：加入设置项与统计（早期档把它们散在别处或干脆没有）
static func _migrate_2_to_3(d: Dictionary) -> void:
	if not d.has("settings"):
		d["settings"] = {}
	if not d.has("stats"):
		d["stats"] = {"raids": 0, "extracts": 0, "deaths": 0, "kills": 0}


# ─────────────────── 状态 ───────────────────

func summary() -> String:
	return "存档：%s%s%s" % [
		path,
		"（可移植回退路径）" if used_fallback else "",
		"" if last_error == "" else "  错误：" + last_error]
