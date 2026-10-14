# 《搜打撤》验收日志

> 2026-10-13 · 工作区 `E:\AAAASDC` · 引擎 Godot 4.7.2-stable · 执行：DSH Lead
> 工程自带验收命令：`powershell -NoProfile -ExecutionPolicy Bypass -File tools\verify_all.ps1`

---

## 0. 结论

**退出码 0 —— 「可以交付」**（①②③ 是门槛，全过；④ 像素基线在本环境无法成像，属咨询项）。
过程中抓出并修正了 **2 处本人引入的真实缺陷**（都不是"看起来没问题"，是验收脚本当场抓出来的）。

## 1. 环境落地（本机原先既无工程也无引擎）

| 步骤 | 命令 | 原始结果 |
|---|---|---|
| 建工作区 | `New-Item -ItemType Directory E:\AAAASDC` | 需越界许可（沙箱默认只允许写会话工作区） |
| 克隆工程 | `git -c http.sslBackend=openssl -c core.autocrlf=false clone --depth 1 https://github.com/gungnior/SDCgame E:\AAAASDC` | 449 个文件 / 19.4 MB / HEAD `b3641e7` / 纯 LF |
| 取引擎 | `python _get_engine.py`（GitHub Releases） | `Godot_v4.7.2-stable_win64.exe.zip` 86,013,866 字节，解出 `..._win64.exe` 172.5 MB 与 `..._win64_console.exe` |
| 补 Python | `mklink /J E:\AAAASDC\_install\python C:\Users\zhangxuwen\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python` | 脚本找的是 `AppData\Local\dsh\...`，实际在 `C:\Users\<用户>\.dsh\...`，差一层，故用 junction 补上 |
| 应用改动 | `git -C E:\AAAASDC apply <workspace>\sdc-changes.patch` | 退出码 0，9 改 + 6 新 |

> 网络说明：本机 `git` 默认的 schannel 后端报 `SEC_E_NO_CREDENTIALS`，
> 换 `-c http.sslBackend=openssl` 后正常；`Invoke-WebRequest` 亦不通，
> 故引擎改用 **Python 的 OpenSSL** 通道下载。

## 2. 最终验收（完整跑，含 ④）

```
powershell -NoProfile -ExecutionPolicy Bypass -File tools\verify_all.ps1
```

```
  ── ① 单元测试（799 项断言） ───────────────────────────────────────────────
    ✅      通过：1619 项，0 失败（退出码 0）

  ── ② 集成验证（真的实例化游戏场景） ───────────────────────────────────────────────
    ✅      ✅ PC 端验证全部通过（105 项）（退出码 0）

  ── ③ 数据契约（JSON schema + 跨表引用） ────────────────────────────────────
    ✅      通过：0 错误，0 警告

  ── ④ 像素基线（咨询性 —— 见脚本开头的说明） ───────────────────────────────────────
    · 自身复现性：两次截图不一致 -> FileNotFoundError: art\_raw\_verify_now.png
    ✅      首次运行，已建立基线 -> art\_raw\_baseline.png

  ✅ 通过（①②③ 是门槛；④ 像素基线仅供参考）—— 可以交付。
```

**退出码 0   耗时 16.7 秒**（原始输出见 `sdc-raw-verify_log_full.txt`）

## 3. 过程中抓到的 2 处真实缺陷（已修）

### 3.1 集成验证失败：`raid_scene.gd` 加载不了

第一次验收的原始输出：

```
  ── ② 集成验证（真的实例化游戏场景） ───────────────────────────────────────────────
    ❌      （退出码 1）
       ERROR: Failed to load script "res://view/raid_scene.gd" with error "Parse error".
       FAIL  突袭场景按 Game.map_id 建图（实际 null）
```

根因（`--check-only --script` 逐文件体检得到原话）：

```
SCRIPT ERROR: Parse Error: Could not parse global class "RaidInput" from "res://view/raid_input.gd".
SCRIPT ERROR: Parse Error: Expected end of statement after expression, found ":" instead.
   at: GDScript::reload (res://view/raid_input.gd:58)
```

**是我引入的**：新加的 `KEY_G:` / `KEY_SHIFT:` 两个 `match` 分支缩进错位
（落进了 `KEY_C:` 的体内）。修正后 `KEY_G:`/`KEY_SHIFT:` 与既有 `KEY_K:` 同为 2 个 tab、
其体内语句 3 个 tab。

### 3.2 `raid_sim_runner.gd` 三处类型推断失败

```
SCRIPT ERROR: Parse Error: Cannot infer the type of "lane_damage" variable because the value does not have a set type.
SCRIPT ERROR: Parse Error: Cannot infer the type of "applied" variable because the value does not have a set type.
SCRIPT ERROR: Parse Error: Cannot infer the type of "heavy" variable because the value does not have a set type.
```

**也是我引入的**：`var x := scene.xxx()` 在 duck-typed 的 `scene.` 链上无法推断类型。
这正是 `AGENTS.md`「已知的坑 · GDScript」里点名过的那一条（我读到过，仍然踩了）。
改成无类型的 `var x = scene.xxx()` 后通过。

## 4. 未能验证的部分

- **④ 像素基线在本环境无法成像**：截图脚本没有产出 `art\_raw\_verify_now.png`
  （此环境没有可用的交互式绘图会话），脚本随后把"找不到基线"理解为"首次运行"，
  因此这一项**没有给出有效结论**。工程自己把它标为**咨询性、非门槛**，
  并在脚本开头写明「像素基线不能当回归门」。
- 真机手感（弹速 / 闪避窗口 / 自动作战走位）仍未验证 —— 需要一台安卓真机。

## 5. 复现步骤（一条不多、一条不少）

```powershell
# 1) 工程
git -c http.sslBackend=openssl clone --depth 1 https://github.com/gungnior/SDCgame E:\AAAASDC
# 2) 引擎：把 Godot_v4.7.2-stable_win64.exe.zip 解到 E:\AAAASDC\_install\godot\
#    （脚本要的是 ..._win64_console.exe）
# 3) Python：junction 到 DSH 运行时（或把 python 放进 _install\python\）
# 4) 改动
git -C E:\AAAASDC apply <本补丁路径>\sdc-changes.patch
# 5) 验收
cd E:\AAAASDC
powershell -NoProfile -ExecutionPolicy Bypass -File tools\verify_all.ps1
```
