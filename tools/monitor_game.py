#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
monitor_game.py -- 通过 adb 实时监听手机上的游戏遥测

配套 telemetry/telemetry.gd（游戏侧）。游戏把结构化 JSON 打到 logcat，
本脚本解析成实时仪表盘 + 落盘日志 + 退出时的诊断摘要。

⚠️ 与项目「不联网」约束不冲突：走 USB 调试通道，不需 INTERNET 权限。

用法：
    python tools/monitor_game.py                    # 实时看 + 结束时摘要
    python tools/monitor_game.py --launch           # 顺便启动游戏
    python tools/monitor_game.py --shots art/_raw/device --shot-every 5
    python tools/monitor_game.py --duration 120     # 跑 120 秒后自动汇总
    python tools/monitor_game.py --adb D:\\adb.exe   # 指定 adb 路径
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
from collections import Counter, defaultdict
from pathlib import Path

PREFIX = "DSHTEL|"
PKG = "com.aaaaadsh.soudache"
ACTIVITY = "org.godotengine.godot.GodotActivity"

DEFAULT_ADB_CANDIDATES = [
    os.path.expandvars(r"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"),
    r"C:\Android\Sdk\platform-tools\adb.exe",
    "adb",
]


def find_adb(explicit=None):
    if explicit:
        return explicit
    for c in DEFAULT_ADB_CANDIDATES:
        if c == "adb" or Path(c).exists():
            return c
    return "adb"


def sh(adb, *args, binary=False, timeout=30):
    try:
        r = subprocess.run([adb, *args], capture_output=True, timeout=timeout)
        return r.stdout if binary else r.stdout.decode("utf-8", "replace")
    except Exception as e:
        return b"" if binary else f"[adb 失败] {e}"


def pick_device(adb, want=None):
    out = sh(adb, "devices")
    devs = []
    for line in out.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            devs.append(parts[0])
    if not devs:
        return None
    if want and want in devs:
        return want
    return devs[0]


# ─────────── 解析 ───────────

JSON_RE = re.compile(re.escape(PREFIX) + r"(\{.*\})\s*$")


def parse_line(line):
    i = line.find(PREFIX)
    if i < 0:
        return None
    raw = line[i + len(PREFIX):].strip()
    # logcat 有时会截断长行；尽力而为
    try:
        return json.loads(raw)
    except Exception:
        # 尝试截到最后一个 }
        j = raw.rfind("}")
        if j > 0:
            try:
                return json.loads(raw[:j + 1])
            except Exception:
                return None
    return None


class Report:
    def __init__(self):
        self.boot = None
        self.stats = []
        self.spikes = []
        self.events = []
        self.spike_ctx = Counter()
        self.event_kinds = Counter()
        self.started = time.time()

    def add(self, d):
        k = d.get("k", "spike" if "ms" in d and "avg_ms" not in d else "?")
        if k == "boot":
            self.boot = d
        elif k == "stats":
            self.stats.append(d)
        elif k == "spike":
            self.spikes.append(d)
            self.spike_ctx[d.get("ctx", "?")] += 1
        elif k == "spike_dump":
            for it in d.get("items", []):
                self.spikes.append(it)
                self.spike_ctx[it.get("ctx", "?")] += 1
        else:
            self.events.append(d)
            self.event_kinds[k] += 1

    def summary(self):
        L = []
        L.append("")
        L.append("=" * 68)
        L.append("  诊断摘要")
        L.append("=" * 68)
        if self.boot:
            b = self.boot
            L.append(f"  设备渲染  {b.get('renderer','?')}  ({b.get('api','?')})")
            L.append(f"  屏幕      {b.get('screen','?')}  dpi={b.get('dpi','?')}  触屏={b.get('touch')}")
            L.append(f"  引擎      {b.get('engine','?')}  {b.get('platform','?')}")
        L.append(f"  时长      {time.time()-self.started:.0f} 秒   采样 {len(self.stats)} 次")

        if self.stats:
            fps = [s.get("fps", 0) for s in self.stats]
            avg = [s.get("avg_ms", 0.0) for s in self.stats]
            worst = [s.get("worst_ms", 0.0) for s in self.stats]
            L.append("")
            L.append("  ── 帧率 ──")
            L.append(f"  FPS       最低 {min(fps)}  中位 {sorted(fps)[len(fps)//2]}  最高 {max(fps)}")
            L.append(f"  平均帧    最差窗口 {max(avg):.1f} ms   典型 {sorted(avg)[len(avg)//2]:.1f} ms")
            L.append(f"  最差单帧  {max(worst):.1f} ms")
            mem = [s.get("mem_mb", 0.0) for s in self.stats]
            nodes = [s.get("nodes", 0) for s in self.stats]
            draws = [s.get("draws", 0) for s in self.stats]
            orph = [s.get("orphans", 0) for s in self.stats]
            L.append(f"  内存      {mem[0]:.0f} -> {mem[-1]:.0f} MB")
            L.append(f"  节点      {nodes[0]} -> {nodes[-1]}")
            L.append(f"  绘制调用  {sorted(draws)[len(draws)//2]}")
            if max(orph) > 50:
                L.append(f"  ⚠️ 孤儿节点 峰值 {max(orph)} —— 可能存在未释放的对象")
            # 帧率下降趋势
            if len(self.stats) >= 6:
                h = len(self.stats) // 2
                f1 = sum(s.get("fps", 0) for s in self.stats[:h]) / h
                f2 = sum(s.get("fps", 0) for s in self.stats[h:]) / (len(self.stats) - h)
                trend = f2 - f1
                L.append(f"  趋势      前半 {f1:.0f} -> 后半 {f2:.0f} fps  "
                         f"({'下降 ⚠️' if trend < -5 else '平稳' if abs(trend) <= 5 else '上升'})")

        L.append("")
        L.append("  ── 卡顿帧 (>33ms) ──")
        if not self.spikes:
            L.append("  无")
        else:
            L.append(f"  共 {len(self.spikes)} 次")
            L.append("  按触发场景分类：")
            for ctx, n in self.spike_ctx.most_common(12):
                L.append(f"    {n:4d}  {ctx}")
            worst = sorted(self.spikes, key=lambda x: -x.get("ms", 0))[:10]
            L.append("  最严重的 10 帧：")
            for s in worst:
                L.append("    %6.1f ms  t=%-6.1f  ctx=%-18s age=%-5sms  nodes=%s draws=%s"
                         % (s.get("ms", 0), s.get("t", 0), s.get("ctx", "?"),
                            s.get("ctx_age_ms", "?"), s.get("nodes", "?"), s.get("draws", "?")))

        L.append("")
        L.append("  ── 事件 ──")
        if not self.events:
            L.append("  无")
        else:
            for k, n in self.event_kinds.most_common():
                L.append(f"    {n:4d}  {k}")
        L.append("=" * 68)
        return "\n".join(L)

    def dump(self, path):
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            for s in self.stats:
                f.write(json.dumps(s, ensure_ascii=False) + "\n")
            for s in self.spikes:
                f.write(json.dumps(s, ensure_ascii=False) + "\n")
            for e in self.events:
                f.write(json.dumps(e, ensure_ascii=False) + "\n")


# ─────────── 主流程 ───────────

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--adb", default=None)
    ap.add_argument("--device", default=None)
    ap.add_argument("--launch", action="store_true", help="顺便启动游戏")
    ap.add_argument("--duration", type=float, default=0, help="跑 N 秒后自动汇总（0=手动 Ctrl+C）")
    ap.add_argument("--out", default="_nightrun/device_telemetry.jsonl")
    ap.add_argument("--shots", default=None, help="每隔 N 秒抓一张设备截图存到这里")
    ap.add_argument("--shot-every", type=float, default=6.0)
    ap.add_argument("--quiet", action="store_true", help="只记日志，不刷实时状态")
    ap.add_argument("--replay", default=None,
                    help="离线分析：读已保存的日志文件（含 logcat 原文或本脚本 --out 的产物），不连设备")
    a = ap.parse_args()

    # ── 离线分析模式：一份日志可以反复分析，不用一直连着设备 ──
    if a.replay:
        rep = Report()
        n = 0
        with open(a.replay, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.rstrip()
                if not line:
                    continue
                # 既支持 logcat 原文，也支持本脚本 --out 产出的纯 JSONL
                if PREFIX in line:
                    d = parse_line(line)
                else:
                    try:
                        d = json.loads(line)
                    except Exception:
                        continue
                if d:
                    rep.add(d)
                    n += 1
        print(f"回放 {a.replay}：解析 {n} 条")
        print(rep.summary())
        return 0

    adb = find_adb(a.adb)
    dev = pick_device(adb, a.device)
    if not dev:
        print("❌ 没有已连接且已授权的设备。")
        print("   请：① 手机开启【开发者选项 → USB 调试】")
        print("        ② USB 连接电脑，手机上点【允许 USB 调试】")
        print("        ③ 再跑一次本脚本（或先跑 adb devices 确认）")
        return 2

    print(f"✅ 设备 {dev}")
    print(f"   adb  {adb}")
    info = sh(adb, "-s", dev, "shell", "getprop", "ro.product.model").strip()
    print(f"   机型 {info}")

    if a.launch:
        sh(adb, "-s", dev, "shell", "am", "force-stop", PKG)
        r = sh(adb, "-s", dev, "shell", "am", "start", "-n", f"{PKG}/{ACTIVITY}")
        print(f"   启动 {PKG} -> {r.strip()[:80]}")
        time.sleep(1.5)

    sh(adb, "-s", dev, "logcat", "-c")

    proc = subprocess.Popen(
        [adb, "-s", dev, "logcat", "-v", "brief"],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

    rep = Report()
    last_shot = 0.0
    last_line = ""
    shot_dir = Path(a.shots) if a.shots else None
    if shot_dir:
        shot_dir.mkdir(parents=True, exist_ok=True)

    print("   ── 开始监听（Ctrl+C 结束并汇总）──\n")
    t0 = time.time()
    try:
        for raw in iter(proc.stdout.readline, b""):
            line = raw.decode("utf-8", "replace").rstrip()
            d = parse_line(line)
            if d is None:
                continue
            rep.add(d)

            now = time.time()
            if a.duration and now - t0 >= a.duration:
                break

            if shot_dir and now - last_shot >= a.shot_every:
                last_shot = now
                png = sh(adb, "-s", dev, "exec-out", "screencap", "-p",
                         binary=True, timeout=20)
                if png and len(png) > 1000:
                    p = shot_dir / f"dev_{int(now - t0):04d}s.png"
                    p.write_bytes(png)

            if a.quiet:
                continue
            k = d.get("k", "?")
            if k == "stats":
                last_line = ("  t=%(t)-7s FPS=%(fps)-3s avg=%(avg_ms)-6s worst=%(worst_ms)-7s "
                             "nodes=%(nodes)-5s draws=%(draws)-4s mem=%(mem_mb)sMB ctx=%(ctx)s"
                             % {kk: d.get(kk, "?") for kk in
                                ("t", "fps", "avg_ms", "worst_ms", "nodes", "draws", "mem_mb", "ctx")})
                sys.stdout.write("\r" + last_line[:150].ljust(150))
                sys.stdout.flush()
            elif k == "spike":
                sys.stdout.write("\r" + " " * 150 + "\r")
                print("  ⚠️ 卡顿 %6.1fms  ctx=%s  t=%s"
                      % (d.get("ms", 0), d.get("ctx", "?"), d.get("t", "?")))
            else:
                sys.stdout.write("\r" + " " * 150 + "\r")
                extra = {kk: vv for kk, vv in d.items() if kk not in ("k", "t", "ctx")}
                print(f"  ● {k}  t={d.get('t')}  {extra}")
    except KeyboardInterrupt:
        print("\n  （手动结束）")
    finally:
        try:
            proc.terminate()
        except Exception:
            pass

    print(rep.summary())
    rep.dump(a.out)
    print(f"\n  原始日志 -> {a.out}")
    if shot_dir:
        print(f"  设备截图 -> {shot_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
