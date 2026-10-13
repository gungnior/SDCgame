class_name DragGhost
extends Control

## 拖拽浮标（2026-10-13 真机反馈 #4：物品交互要有拖动）
##
## 拖拽时跟着手指画一个小牌子，告诉玩家"手里正拿着哪件东西、有几个"。
## 没有它的话，手指把条目本身盖住了，玩家根本不知道自己在拖什么。
##
## ⚠️ `mouse_filter = IGNORE` 是**硬要求**：
##    浮标画在最上层，一旦吃触摸，就会把"松手落在哪一栏"的判定打断 ——
##    表现为"怎么拖都放不下"。它只能看，不能碰。
##
## 纯绘制，无状态依赖，可单测（只看 `is_live()` / `show_at` 的字段）。

## ⚠️ 这里必须用 `var` 而不是 `const`：GDScript 的 const 只接受**常量表达式**，
##    引用别的类的 const（`UITokens.TEXT_HI`）或调它的静态函数（`UITokens.fade(...)`）
##    都会报 "isn't a constant expression"。文件级 var 在加载时求值，效果相同。
var C_BG := UITokens.fade(UITokens.BG_PANEL, 0.93)
var C_EDGE := UITokens.fade(UITokens.INFO, 0.92)
var C_TEXT := UITokens.TEXT_HI
const FONT_SIZE := 15

var _text := ""
var _at := Vector2.ZERO
var _live := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


func is_live() -> bool:
	return _live


func text_now() -> String:
	return _text


## 在（本控件局部坐标）pos 处显示牌子。
func show_at(txt: String, pos: Vector2) -> void:
	_text = txt
	_at = pos
	_live = true
	visible = true
	queue_redraw()


func move_to(pos: Vector2) -> void:
	if not _live:
		return
	_at = pos
	queue_redraw()


func hide_ghost() -> void:
	_live = false
	_text = ""
	visible = false
	queue_redraw()


func _draw() -> void:
	if not _live:
		return
	var f := ThemeDB.fallback_font
	var sz := Vector2(96.0, 34.0)
	if f != null:
		var m := f.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
		sz = Vector2(maxf(72.0, m.x + 22.0), 34.0)
	var rc := Rect2(_at - sz * 0.5 + Vector2(0.0, -26.0), sz)
	draw_rect(Rect2(rc.position + Vector2(0, 2), rc.size), Color(0, 0, 0, 0.35), true)
	draw_rect(rc, C_BG, true)
	draw_rect(rc, C_EDGE, false, 2.0)
	if f != null:
		draw_string(f, Vector2(rc.position.x + 11.0, rc.position.y + 23.0), _text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, C_TEXT)
