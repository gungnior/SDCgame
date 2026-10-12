#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
extract_gunshots.py -- 从 Free Firearm Sound Library 裁出可用的单发声

素材来源：The Free Firearm Sound Library（CC0，见 specs/third-party.md）
  归档里的 "Prepared SFX Library" 是 **96kHz 立体声、约 15 秒的多 take 录音**，
  不能直接丢进游戏 —— 必须找到瞬态并裁成一击。

元数据 "Prepared Master Sheet.csv" 给了每条录音的语义：
  "near distance ... left, right"  -> 玩家武器（贴近听者）
  "mid distance  ... forward, back" -> 敌人武器（有距离感，天然适合做衰减音）
  "gunshot"（单数）vs "gunshots"（复数/burst）-> 只用单数

所以本脚本不靠猜：先用 CSV 选文件，再用能量包络找瞬态并裁切。
"""

import csv
import re
import sys
import wave
from pathlib import Path

import numpy as np

SRC = Path(r"D:\aaaaadsh\_install\sfx\firearm\Prepared SFX Library")
META = Path(r"D:\aaaaadsh\_install\sfx\meta\Prepared Master Sheet.csv")
# ⚠️ 落到暂存区而不是 art/ —— 否则同一批 WAV 会被 Godot 导入两遍，白白撑大 APK
OUT = Path(r"D:\aaaaadsh\_install\sfx\staged_guns")

TARGET_SR = 44100

# 我们需要的：3 把枪 x 玩家/敌人两版
#   key        -> (CSV 里的枪名, 距离语义, 输出名, 目标时长秒)
WANTED = [
    ("weapon_pistol",   "1911",    "near", "gun_pistol_player",  0.42),
    ("weapon_pistol",   "1911",    "mid",  "gun_pistol_enemy",   0.55),
    ("weapon_rifle",    "AR-15",   "near", "gun_rifle_player",   0.46),
    ("weapon_rifle",    "AR-15",   "mid",  "gun_rifle_enemy",    0.60),
    ("weapon_shotgun",  "Mossberg", "near", "gun_shotgun_player", 0.90),
    ("weapon_shotgun",  "Mossberg", "mid",  "gun_shotgun_enemy",  1.00),
    # 霰弹枪近距备选（Mossberg 只有 2 条，够用；Nova / Model 12 作为备用）
    ("weapon_shotgun",  "Nova",    "near", "gun_shotgun_player_b", 0.90),
]


def read_wav(path):
    with wave.open(str(path)) as f:
        n, ch, sr, sw = f.getnframes(), f.getnchannels(), f.getframerate(), f.getsampwidth()
        raw = f.readframes(n)
    # 素材是 24-bit（Free Firearm Sound Library 的原始规格）
    if sw == 2:
        a = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
    elif sw == 3:
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        v = b[:, 0] | (b[:, 1] << 8) | (b[:, 2] << 16)
        v = np.where(v >= 0x800000, v - 0x1000000, v)
        a = v.astype(np.float32) / 8388608.0
    elif sw == 4:
        a = np.frombuffer(raw, dtype="<i4").astype(np.float32) / 2147483648.0
    else:
        raise SystemExit(f"{path}: 不支持的位深 {sw*8}-bit")
    if ch > 1:
        a = a.reshape(-1, ch).mean(axis=1)
    return a, sr


def resample(a, sr_from, sr_to):
    if sr_from == sr_to:
        return a
    # 先做移动平均抗混叠，再线性重采样（够用；比直接抽样干净得多）
    k = max(1, int(round(sr_from / sr_to)))
    if k > 1:
        kern = np.ones(k, dtype=np.float32) / k
        a = np.convolve(a, kern, mode="same")
    n_out = int(round(len(a) * sr_to / sr_from))
    x_old = np.linspace(0.0, 1.0, len(a), endpoint=False)
    x_new = np.linspace(0.0, 1.0, n_out, endpoint=False)
    return np.interp(x_new, x_old, a).astype(np.float32)


def find_shot(a, sr):
    """
    返回 (onset_idx, peak_idx)。
    做法：短时 RMS 包络 -> 全局最大 -> 从峰值往回找能量跌到 8% 的位置作为起音点。
    """
    win = max(1, int(sr * 0.002))              # 2ms 窗
    n = len(a) // win * win
    env = np.sqrt(np.mean(a[:n].reshape(-1, win) ** 2, axis=1))
    if env.size == 0:
        return 0, int(np.argmax(np.abs(a)))
    peak_w = int(np.argmax(env))
    peak = int(peak_w * win + win // 2)
    thr = max(env.max() * 0.08, 1e-4)
    i = peak_w
    # 往回最多 400ms
    limit = max(0, peak_w - int(0.4 * sr / win))
    while i > limit and env[i] > thr:
        i -= 1
    onset = int(i * win)
    # 再往前留 3ms 的 PRAT（起音前的极短静音，避免听起来"被切掉头"）
    onset = max(0, onset - int(0.003 * sr))
    return onset, peak


def trim_and_norm(a, sr, dur):
    onset, peak = find_shot(a, sr)
    seg = a[onset: onset + int(dur * sr)].copy()
    if len(seg) == 0:
        return None
    # 归一化到 -1 dBFS
    mx = float(np.max(np.abs(seg)))
    if mx > 1e-6:
        seg *= (10 ** (-1.0 / 20.0)) / mx
    # 尾部 50ms 淡出，避免硬切产生的"啪"
    fade = min(int(0.05 * sr), len(seg) // 3)
    if fade > 1:
        seg[-fade:] *= np.linspace(1.0, 0.0, fade, dtype=np.float32)
    # 头部 1ms 淡入，去掉可能的直流台阶
    fi = min(int(0.001 * sr), len(seg) // 4)
    if fi > 1:
        seg[:fi] *= np.linspace(0.0, 1.0, fi, dtype=np.float32)
    return seg


def save_wav(a, sr, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.clip(a * 32767.0, -32768, 32767).astype("<i2")
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(sr)
        f.writeframes(pcm.tobytes())
    return path


def load_metadata():
    rows = []
    with open(META, encoding="utf-8-sig", newline="") as f:
        for r in csv.DictReader(f):
            rows.append(r)
    return rows


def pick_file(rows, gun, distance):
    """按 CSV 语义挑一条单发录音"""
    cands = []
    for r in rows:
        if r["CD"].strip() != gun:
            continue
        desc = (r.get("Description") or "").lower()
        if "gunshot" not in desc:
            continue
        # 单发：出现 "gunshot," 或结尾 "gunshot"；复数 "gunshots" 排除
        if re.search(r"\bgunshots\b", desc):
            continue
        want = "near distance" if distance == "near" else "mid distance"
        if want in desc:
            cands.append(r["Filename"].strip())
    return cands


def main():
    if not META.exists():
        raise SystemExit(f"缺少元数据：{META}")
    rows = load_metadata()
    OUT.mkdir(parents=True, exist_ok=True)

    print(f"元数据 {len(rows)} 条\n")
    ok = 0
    for _weapon, gun, dist, outname, dur in WANTED:
        files = pick_file(rows, gun, dist)
        if not files:
            print(f"  ✗ {outname}: 在 CSV 里找不到 {gun} / {dist} 的单发")
            continue
        src = SRC / gun / files[0]
        if not src.exists():
            print(f"  ✗ {outname}: 文件不存在 {src}")
            continue
        a, sr = read_wav(src)
        seg = trim_and_norm(a, sr, dur)
        if seg is None:
            print(f"  ✗ {outname}: 裁切失败")
            continue
        seg = resample(seg, sr, TARGET_SR)
        dst = OUT / f"{outname}.wav"
        save_wav(seg, TARGET_SR, dst)
        ms = len(seg) / TARGET_SR * 1000.0
        print(f"  ✓ {outname:<24} <- {gun}/{files[0]:<12} {ms:6.0f} ms  {dst.stat().st_size//1024} KB")
        ok += 1

    print(f"\n完成 {ok} 个 -> {OUT}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
