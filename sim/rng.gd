class_name SimRng
extends RefCounted

## 注入式随机数发生器。
##
## 为什么必须用它、而不是全局 randi()/randf()（T-32 / specs/tech-stack.md §5.7）：
##   1. 全局作用域只有【一条】随机流，调用者互相推进，无法局部复现
##   2. SimRng 每实例独立流，可用 seed + state 完整复现
##   3. 模拟层依赖注入后，测试可以完全确定性
##
## ⚠️ Godot 官方警告：给 seed 赋值会【重置 state】。
##    顺序必须是 new() -> seed = X -> 再使用。本类在 _init 里保证了这个顺序。

var _rng: RandomNumberGenerator


func _init(seed_value: int = 0) -> void:
	_rng = RandomNumberGenerator.new()
	if seed_value != 0:
		# ⚠️ 必须在任何取数之前赋值（会重置 state）
		_rng.seed = seed_value
	else:
		_rng.randomize()


## 派生一个子随机流。
## ⚠️ 不要用相邻整数做子 seed（可能产生相关的随机流，见 godot#119322）。
static func derive_seed(parent_seed: int, salt_id: int) -> int:
	return parent_seed ^ (0x9E3779B9 * salt_id)


func randi_range(from: int, to: int) -> int:
	if to < from:
		return from
	return _rng.randi_range(from, to)


func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


func randf() -> float:
	return _rng.randf()


## 权重抽样。返回 [0, weights.size()) 的下标。
func weighted_index(weights: Array) -> int:
	if weights.is_empty():
		return -1
	var total := 0
	for w in weights:
		total += int(w)
	if total <= 0:
		return 0
	var pick := _rng.randi_range(0, total - 1)
	var acc := 0
	for i in weights.size():
		acc += int(weights[i])
		if pick < acc:
			return i
	return weights.size() - 1


## 保存 state 以便后续重放同一段序列
func save_state() -> int:
	return _rng.state


func restore_state(s: int) -> void:
	_rng.state = s


func _to_string() -> String:
	return "SimRng(seed=%d)" % _rng.seed
