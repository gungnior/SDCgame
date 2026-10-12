#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
build_sfx_bank.py -- 把外部 CC0 音效整理进 art/sfx/，并生成 data/sfx.json

素材来源（均在 specs/third-party.md 登记，全部 CC0）：
  · The Free Firearm Sound Library  —— 枪声（见 tools/audio/extract_gunshots.py 先裁好）
  · Kenney Impact Sounds            —— 脚步 / 命中 / 弹着
  · Kenney Sci-fi Sounds            —— 爆炸 / 金属弹着
  · Kenney Interface Sounds         —— UI / 换弹

本脚本做三件事：
  1. 按逻辑名拷贝到 art/sfx/（文件名用逻辑名，便于代码引用与替换）
  2. 生成 data/sfx.json（数据驱动的音效注册表）
  3. 打印清单供人工核对
"""

import json
import shutil
import sys
from pathlib import Path

# ⭐ 路径相对脚本自身解析，不写死盘符（同 extract_gunshots.py 的理由）。
#    本文件在 tools/audio/ 下，所以项目根是上两级。
PROJ = Path(__file__).resolve().parents[2]
SRC = PROJ / "_install" / "sfx"
OUT = PROJ / "art" / "sfx"

GUNS = OUT / "guns"

# 逻辑名 -> (来源文件, volume_db, pitch_min, pitch_max, max_simul, bus)
#   max_simul 是"同时最多几个"—— 一帧内 5 个敌人开枪不能叠成噪音
BANK = {
    # ── 玩家武器（near distance 录音，紧凑无尾）──
    "gun_pistol_player":  (GUNS / "gun_pistol_player.wav",  -2.0, 0.97, 1.03, 3, "Master"),
    "gun_rifle_player":   (GUNS / "gun_rifle_player.wav",   -2.5, 0.96, 1.02, 3, "Master"),
    "gun_shotgun_player": (GUNS / "gun_shotgun_player.wav", -1.0, 0.98, 1.04, 2, "Master"),

    # ── 敌人武器（mid distance 录音，自带距离感与尾音）──
    "gun_pistol_enemy":   (GUNS / "gun_pistol_enemy.wav",   -6.0, 0.94, 1.04, 4, "Master"),
    "gun_rifle_enemy":    (GUNS / "gun_rifle_enemy.wav",    -6.5, 0.93, 1.03, 4, "Master"),
    "gun_shotgun_enemy":  (GUNS / "gun_shotgun_enemy.wav",  -4.5, 0.95, 1.05, 3, "Master"),

    # ── 命中（分级：轻击 / 重击 / 暴击 / 护甲）──
    "hit_flesh":      (SRC / "kenney_impact-sounds/Audio/impactSoft_medium_000.ogg",   -3.0, 0.88, 1.14, 4, "Master"),
    "hit_crit":       (SRC / "kenney_impact-sounds/Audio/impactPunch_heavy_000.ogg",   -1.5, 0.92, 1.08, 3, "Master"),
    "hit_armor":      (SRC / "kenney_impact-sounds/Audio/impactPlate_heavy_000.ogg",   -3.5, 0.95, 1.10, 3, "Master"),
    "hit_wood":       (SRC / "kenney_impact-sounds/Audio/impactWood_medium_000.ogg",   -5.0, 0.92, 1.12, 3, "Master"),
    "hit_concrete":   (SRC / "kenney_impact-sounds/Audio/impactMining_000.ogg",        -5.5, 0.90, 1.12, 3, "Master"),
    "hit_metal":      (SRC / "kenney_sci-fi-sounds/Audio/impactMetal_000.ogg",         -5.0, 0.92, 1.14, 3, "Master"),

    # ── 自己受伤 / 击杀确认 ──
    "player_hurt":    (SRC / "kenney_impact-sounds/Audio/impactPunch_medium_000.ogg",  -1.0, 0.90, 1.06, 2, "Master"),
    "kill_confirm":   (SRC / "kenney_interface-sounds/Audio/confirmation_001.ogg",     -6.0, 0.98, 1.04, 2, "Master"),

    # ── 换弹 ──
    "reload_start":   (SRC / "kenney_interface-sounds/Audio/click_002.ogg",            -5.0, 0.95, 1.08, 2, "Master"),
    "reload_done":    (SRC / "kenney_interface-sounds/Audio/click_004.ogg",            -3.5, 0.98, 1.06, 2, "Master"),
    "reload_empty":   (SRC / "kenney_interface-sounds/Audio/error_001.ogg",            -6.0, 1.00, 1.00, 1, "Master"),

    # ── 脚步（按地面材质）──
    "step_concrete":  (SRC / "kenney_impact-sounds/Audio/footstep_concrete_000.ogg",   -13.0, 0.90, 1.12, 2, "Master"),
    "step_wood":      (SRC / "kenney_impact-sounds/Audio/footstep_wood_000.ogg",       -13.0, 0.90, 1.12, 2, "Master"),
    "step_dirt":      (SRC / "kenney_impact-sounds/Audio/footstep_grass_000.ogg",      -13.0, 0.90, 1.12, 2, "Master"),
    "step_metal":     (SRC / "kenney_impact-sounds/Audio/footstep_carpet_000.ogg",     -13.0, 0.92, 1.10, 2, "Master"),

    # ── 交互 / UI ──
    "pickup":         (SRC / "kenney_interface-sounds/Audio/select_001.ogg",           -5.0, 0.98, 1.05, 3, "Master"),
    "ui_click":       (SRC / "kenney_interface-sounds/Audio/click_001.ogg",            -7.0, 0.99, 1.02, 2, "Master"),
    "ui_confirm":     (SRC / "kenney_interface-sounds/Audio/confirmation_002.ogg",     -5.0, 1.00, 1.00, 1, "Master"),
    "ui_deny":        (SRC / "kenney_interface-sounds/Audio/error_002.ogg",            -6.0, 1.00, 1.00, 1, "Master"),

    # ── 回合事件 ──
    "extract_tick":   (SRC / "kenney_interface-sounds/Audio/toggle_001.ogg",           -8.0, 0.98, 1.03, 2, "Master"),
    "extract_done":   (SRC / "kenney_interface-sounds/Audio/confirmation_003.ogg",     -2.0, 1.00, 1.00, 1, "Master"),
    "explosion":      (SRC / "kenney_sci-fi-sounds/Audio/explosionCrunch_000.ogg",     -1.0, 0.94, 1.06, 2, "Master"),
    "hurt_heavy":     (SRC / "kenney_sci-fi-sounds/Audio/explosionCrunch_002.ogg",     -2.0, 0.96, 1.04, 1, "Master"),
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    entries = []
    missing = []
    copied = 0

    for name, (src, vol, pmin, pmax, simul, bus) in BANK.items():
        if not src.exists():
            missing.append(f"{name}  <- {src}")
            continue
        ext = src.suffix
        dst = OUT / f"{name}{ext}"
        if src.resolve() != dst.resolve():
            shutil.copy2(src, dst)
            copied += 1
        entries.append({
            "id": name,
            "file": f"res://art/sfx/{name}{ext}",
            "volume_db": vol,
            "pitch_min": pmin,
            "pitch_max": pmax,
            "max_simul": simul,
            "bus": bus,
        })

    out_json = PROJ / "data" / "sfx.json"
    out_json.write_text(
        json.dumps(entries, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8")

    print(f"拷贝 {copied} 个文件 -> {OUT}")
    print(f"写入 {len(entries)} 条 -> {out_json}")
    if missing:
        print(f"\n⚠️ 缺失 {len(missing)} 个：")
        for m in missing:
            print("   ", m)
    print("\n清单：")
    for e in entries:
        print(f"  {e['id']:<20} {e['file'].replace('res://art/sfx/','')}")
    return 0 if not missing else 1


if __name__ == "__main__":
    sys.exit(main())
