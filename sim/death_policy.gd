class_name DeathPolicy
extends RefCounted

## 死亡损失策略（3c，2026-10-13）。
##
## 真机反馈："掉了装备不心疼" —— 根因不是"没掉"（搜打撤本来就该掉），
## 而是**没有可调的损失规则**：要么全掉、要么不掉，中间档（保险/找回/损失比例）
## 完全没法表达。本文件把"损失规则"做成一个**纯数据 + 纯函数**的对象，
## 所有数值都可调、默认"全掉"，把具体数值交给【平衡专家】定。
##
## 机制（不关心数值）：
##   · keep_*_ratio 0~1：按【价值】保留前 N 个最值钱的槽（N = floor(ratio × 总槽数)）
##   · insured_slots：无论比例多少，前 N 个最值钱的槽【必留】（"保险"概念）
##   · 最终保留数 = max(insured_slots, floor(ratio × N))
##
## 纯静态、可 headless 单测（plan_keep 不碰任何状态）。

## 身上装备保留比例 0~1（0 = 全掉，1 = 全留）
var keep_equipment_ratio: float = 0.0
## 携带背包保留比例 0~1（同上）
var keep_carry_ratio: float = 0.0
## 保险槽位：最值钱的前 N 个槽无论比例都保留（0 = 无保险）
var insured_slots: int = 0


## 纯函数：给定一组价值，返回【应该保留的索引】。
## [param values] 第 i 个元素是第 i 个槽的价值（任意可比较数）。
## 返回按"价值从高到低"的前 keep_n 个索引；keep_n = max(insured, floor(ratio×N))。
## 不读取、不修改任何外部状态 —— 这样既能单测，也方便接"保险/找回/损失比例"各种策略。
static func plan_keep(values: Array, ratio: float, insured: int) -> Array:
	var n := values.size()
	if n == 0:
		return []
	var keep_n := maxi(insured, int(floor(clampf(ratio, 0.0, 1.0) * float(n))))
	keep_n = mini(keep_n, n)
	if keep_n <= 0:
		return []
	# 索引按价值降序排，取前 keep_n 个
	var idx: Array = range(n)
	idx.sort_custom(func(a, b): return float(values[a]) > float(values[b]))
	return idx.slice(0, keep_n)
