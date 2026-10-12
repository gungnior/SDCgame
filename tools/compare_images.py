# -*- coding: utf-8 -*-
"""逐像素比较两张截图，带容差。退出码 0 = 可接受，1 = 有实质差异。

用法：
    python tools/compare_images.py <基线.png> <当前.png> [--tolerance 0.05]

─── 为什么单独一个文件，而不是塞进 ps1 里 ───
在 PowerShell 的 here-string 里嵌 Python，本会话反复踩坑
（引号被吃掉、`$` 被插值、编码问题…）。独立成文件之后可以直接手测，
两边 agent 都能用（不依赖 PowerShell），逻辑也能被单测。

─── ⚠️⚠️ 坑 1：绝不能用 ImageChops.difference(...).getbbox() ───
PIL 的 `getbbox()` 在 **RGBA** 图上以 **alpha 通道**作为"非零"的掩码；
而截图都是完全不透明的，差值图的 alpha 恒为 0 ——
于是它返回 None，也就是"没有差异"。

实测踩到过：把玩家颜色从蓝改成红（**66926 个差分像素**），
基线仍然报「逐像素完全一致」。这是"测试说 OK"最危险的形式 ——
守卫看起来在工作，实际什么都没验。
正确做法：直接在 RGB 上比，用 numpy 数非零。

─── ⚠️ 坑 2：这局游戏有 ~0.02% 的帧时序噪声，所以必须有容差 ───
同参数连跑 3 次实测：
    run1 vs run2   完全一致
    run2 vs run3   188 像素 (0.0204%)
    run1 vs run3   188 像素 (0.0204%)
即 `--fixed-fps 60` + 固定种子仍不能做到 100% 逐位可复现
（差值集中在一个 ~15x18 的小区域，是锥体/轮廓边缘的 1 帧级抖动）。

所以默认容差取 **0.05%**：
  · 噪声           ~0.02%  -> 通过
  · 玩家改色        0.17%  -> 失败（是噪声的 8 倍）
这是一个**粗粒度**守卫 —— 它的职责是"画面/模拟被明显改动了"，
细粒度的正确性交给 799 项单测 + 51 项集成验证。
"""
import sys

import numpy as np
from PIL import Image

DEFAULT_TOLERANCE_PCT = 0.05


def compare(baseline_path: str, current_path: str,
            tolerance_pct: float = DEFAULT_TOLERANCE_PCT) -> tuple[int, str, bool]:
    """返回 (不同像素数, 描述, 是否可接受)。"""
    a = np.asarray(Image.open(baseline_path).convert("RGB")).astype(np.int16)
    b = np.asarray(Image.open(current_path).convert("RGB")).astype(np.int16)

    if a.shape != b.shape:
        return -1, "尺寸不同 %s vs %s" % (a.shape, b.shape), False

    mask = (a != b).any(axis=2)
    n = int(mask.sum())
    total = int(mask.size)
    if n == 0:
        return 0, "逐像素完全一致", True

    pct = n * 100.0 / total
    ys, xs = np.nonzero(mask)
    desc = ("有差异 %d 像素 (%.4f%%)，区域 x[%d..%d] y[%d..%d]"
            % (n, pct, xs.min(), xs.max(), ys.min(), ys.max()))
    ok = pct <= tolerance_pct
    if ok:
        desc += "  <= 容差 %.2f%%（属于帧时序噪声）" % tolerance_pct
    return n, desc, ok


def main() -> int:
    args = sys.argv[1:]
    tolerance = DEFAULT_TOLERANCE_PCT
    if "--tolerance" in args:
        i = args.index("--tolerance")
        tolerance = float(args[i + 1])
        del args[i:i + 2]
    if len(args) < 2:
        print("用法: compare_images.py <基线.png> <当前.png> [--tolerance 0.05]")
        return 2

    n, desc, ok = compare(args[0], args[1], tolerance)
    print(desc)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
