extends SceneTree

## 定位 user:// 写入失败的原因：是不是路径里的中文（项目名"搜打撤"）导致的。

func _try(path_: String, label: String) -> void:
	var f := FileAccess.open(path_, FileAccess.WRITE)
	if f == null:
		var e := FileAccess.get_open_error()
		print("  ❌ %-28s %s  (err %d %s)" % [label, path_, e, error_string(e)])
	else:
		f.store_string("ok")
		f.close()
		print("  ✅ %-28s %s" % [label, path_])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path_))


func _init() -> void:
	print("项目名: %s" % ProjectSettings.get_setting("application/config/name"))
	print("user:// -> %s" % ProjectSettings.globalize_path("user://"))
	print("OS.get_user_data_dir() -> %s" % OS.get_user_data_dir())
	print()
	print("=== 各种路径写入测试 ===")
	_try("user://a.txt", "user:// 根")
	_try("user://logs/b.txt", "user://logs/")
	_try("user://saves/c.txt", "user://saves/")

	var ascii_dir := "C:/Users/xxx/AppData/Roaming/Godot/app_userdata/_asciitest"
	DirAccess.make_dir_recursive_absolute(ascii_dir)
	_try(ascii_dir + "/d.txt", "纯 ASCII 绝对路径")

	var cjk_dir := "C:/Users/xxx/AppData/Roaming/Godot/app_userdata/搜打撤"
	DirAccess.make_dir_recursive_absolute(cjk_dir)
	_try(cjk_dir + "/e.txt", "含中文的绝对路径")

	# 可执行文件旁边（便携模式常用回退）
	var exe_dir := OS.get_executable_path().get_base_dir()
	_try(exe_dir + "/portable_f.txt", "可执行文件旁边")

	quit(0)
