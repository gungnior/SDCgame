class_name BodyMetrics
extends RefCounted

## 人物判定身位 —— 「身位」在全局的**唯一**换算来源
##
## 用户规格（本次需求原文）：
##   「敌人的攻击为固定弹道，宽度为两倍人物判定身位，会固定锁定人物为中心，
##     即人物两侧的弹道均为 1 格人物身位。角色可以进行闪避操作，
##     闪避的距离为 1.5 倍人物身位。」
##
## 于是「1 个身位」= 人物判定体的**宽度（直径）**：
##   判定半径沿用 AimAssist.DEFAULT_HIT_RADIUS（0.45 逻辑格）
##   -> 身位 BODY_WIDTH = 0.9 逻辑格
##
## 三处数值全部由它推导，**不许在别处写死**（否则「几倍身位」就没法对账）：
##   · 敌方弹道半宽 = 1 身位（人物两侧各 1 身位 -> 总宽 2 身位）
##   · 闪避位移     = 1.5 身位（> 1 身位 -> 侧移一步就能离开弹道）
##
## 纯常量，无 Node 依赖，可 headless 单测。

## 人物判定半径（逻辑格）—— 与瞄准辅助的实体半径同源
const HIT_RADIUS := AimAssist.DEFAULT_HIT_RADIUS
## 一个「身位」= 判定体的宽度（直径，逻辑格）
const BODY_WIDTH := HIT_RADIUS * 2.0
## 敌方弹道的半宽 = 人物两侧各 1 身位
const LANE_HALF_WIDTH := BODY_WIDTH
## 敌方弹道的总宽 = 2 身位
const LANE_WIDTH := LANE_HALF_WIDTH * 2.0
## 闪避位移 = 1.5 身位
const DODGE_DISTANCE := BODY_WIDTH * 1.5


## 侧移多少格才能离开一条以自己为中心的弹道（= 1 身位）。
## 闪避位移必须大于它，否则「闪避」在数学上就不成立。
static func escape_distance() -> float:
	return LANE_HALF_WIDTH


## 闪避位移 / 脱离距离 —— 测试里断言「闪避一定躲得开」用
static func dodge_clears_lane() -> bool:
	return DODGE_DISTANCE > LANE_HALF_WIDTH
