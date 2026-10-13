# -*- coding: utf-8 -*-
"""W-00 判定器：把 N 次探针运行的结果两两比对，并定位**第一个分叉的字段**。

被 tools/check_determinism.ps1 调用，也可以手测：

    python tools/determinism_check.py --dir _install/tmp/det --runs 4 --shots run_1.png run_2.png ...

退出码：0 = 全部两两逐像素完全一致 **且** 状态指纹一致
        1 = 有分叉（打印第一处差异的字段与坐标）
        2 = 用法错误 / 缺文件

─── 为什么单独一个 .py ───
AGENTS.md §4：别在 PowerShell here-string 里嵌 Python。而且这一层要在
RGB 上比（见 tools/compare_images.py 头部的坑 1：getbbox() 会在 RGBA 上撒谎）。

─── 为什么要比"状态指纹"，不只比像素 ───
像素只告诉你"分叉了"。要修根因，必须先知道**哪个量先分叉**：
是模拟时间？是 hitstop 次数？还是敌人位置？探针每帧打印一行 PROBE_STATE，
这里按字段逐层比较并报出**最早分叉**的那一个。
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from compare_images import compare  # noqa: E402

# ⚠️ Windows 上子进程 Python 的 stdout 默认是 GBK ——
#    打印 "❌" 这类非 GBK 字符会直接 UnicodeEncodeError 崩掉（实测踩过）。
#    强制 UTF-8，避免"判定器自己崩了"被误读成"验收失败"。
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# 按"最可能解释分叉"的顺序排列，便于先看根因字段
STATE_KEYS = [
    "frames", "sim_time", "time_scale", "frozen", "hitstop_count",
    "hitstop_suppressed", "hitstop_frames", "feel_time", "trauma", "flash",
    "hp", "dead", "kills", "player_x", "player_y", "aim_x", "aim_y",
    "cam_x", "cam_y", "cam_off_x", "cam_off_y",
    "agents_alive", "agents_pos", "agents_detail", "bullets", "muzzle",
    "rng_state", "nodes",
]


def _read_lines(path):
    """读文本日志，自动识别编码。

    ⚠️ 必须容错：Windows PowerShell 5.1 的 `*>` / Out-File 默认写 **UTF-16LE**，
    而 Godot 自己写的是 UTF-8。一个判定器因为读错编码而报"没有 PROBE_STATE"
    会把人引到完全错误的方向（实测踩过）。
    """
    raw = open(path, "rb").read()
    for enc in ("utf-8-sig", "utf-16", "cp1252"):
        try:
            return raw.decode(enc).splitlines()
        except (UnicodeDecodeError, UnicodeError):
            continue
    return raw.decode("utf-8", errors="replace").splitlines()


def read_state(log_path):
    """从 godot 的 stdout 日志里取最后一行 PROBE_STATE。"""
    if not os.path.isfile(log_path):
        return None, "缺日志 %s" % log_path
    state = None
    for line in _read_lines(log_path):
        line = line.strip()
        if line.startswith("PROBE_STATE "):
            try:
                state = json.loads(line[len("PROBE_STATE "):])
            except ValueError as exc:
                return None, "PROBE_STATE 不是合法 JSON：%s" % exc
    if state is None:
        return None, "日志里没有 PROBE_STATE 行"
    return state, ""


def compare_states(a, b):
    """返回第一个分叉的字段描述；全同返回空串。"""
    for key in STATE_KEYS:
        if key not in a or key not in b:
            continue
        if a[key] != b[key]:
            return "%s: %s vs %s" % (key, a[key], b[key])
    # 键集合本身不同也算分叉
    if set(a) != set(b):
        return "字段集合不同"
    return ""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True, help="运行输出目录")
    ap.add_argument("--runs", type=int, required=True)
    ap.add_argument("--prefix", default="run")
    ap.add_argument("--tolerance", type=float, default=0.0,
                    help="像素容差%%（W-00 的验收标准是 0）")
    args = ap.parse_args()

    shots, logs, names = [], [], []
    for i in range(1, args.runs + 1):
        png = os.path.join(args.dir, "%s_%d.png" % (args.prefix, i))
        log = os.path.join(args.dir, "%s_%d.log" % (args.prefix, i))
        if not os.path.isfile(png):
            print("❌ 缺少截图：%s" % png)
            return 2
        shots.append(png)
        logs.append(log)
        names.append("%s_%d" % (args.prefix, i))

    states = []
    for name, log in zip(names, logs):
        st, err = read_state(log)
        if st is None:
            print("❌ %s：%s" % (name, err))
            return 2
        states.append(st)

    print("── 状态指纹（第 %d 帧） ──" % states[0].get("frames", -1))
    for name, st in zip(names, states):
        print("  %-9s sim_time=%.4f hitstop=%d/%d frames_left=%d frozen=%s "
              "time_scale=%.2f hp=%d kills=%d player=(%.3f,%.3f) aim=(%.3f,%.3f) "
              "cam=(%.2f,%.2f) agents=%d bullets=%d"
              % (name, st["sim_time"], st["hitstop_count"], st["hitstop_suppressed"],
                 st.get("hitstop_frames", -1), st["frozen"], st["time_scale"],
                 st["hp"], st["kills"], st["player_x"], st["player_y"],
                 st["aim_x"], st["aim_y"], st["cam_x"], st["cam_y"],
                 st["agents_alive"], st["bullets"]))

    state_bad = False
    for i in range(len(states)):
        for j in range(i + 1, len(states)):
            d = compare_states(states[i], states[j])
            if d:
                state_bad = True
                print("  ⚠️ 状态分叉 %s vs %s -> 第一个不同字段：%s"
                      % (names[i], names[j], d))

    print("── 像素两两比对（容差 %.2f%%） ──" % args.tolerance)
    pix_bad = False
    pairs = 0
    for i in range(len(shots)):
        for j in range(i + 1, len(shots)):
            pairs += 1
            n, desc, ok = compare(shots[i], shots[j], args.tolerance)
            ok = ok and n == 0
            if not ok:
                pix_bad = True
            print("  %-6s %-6s %s" % (names[i], names[j], desc))

    print("")
    if pix_bad or state_bad:
        print("❌ 不可复现：%d 对比较中有分叉（状态分叉=%s，像素分叉=%s）"
              % (pairs, state_bad, pix_bad))
        return 1
    print("✅ 可复现：%d 对比较全部逐像素完全一致，且状态指纹一致（%d 次运行）"
          % (pairs, len(shots)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
