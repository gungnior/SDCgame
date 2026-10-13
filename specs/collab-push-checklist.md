# push 前检查清单（两人协作出库门禁）

> 配套脚本：`tools/pre_push_check.ps1`。一条命令跑完 7 项检查，退出码 0 才准 push。
> 写于 2026-10-13 · 本地历史 17 个提交已落地、**remote 待建**（见 [workboard.md](workboard.md) W-07）。

## 一键跑

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\pre_push_check.ps1
```

只改了文档想省 20 秒验收：加 `-SkipVerify`。**改了 `sim/`/`view/`/`data/` 就别加**——
那 20 秒是整个项目"done 定义"的地基。

## 七项检查各防什么

| # | 检查 | 不查会怎样 |
|---|---|---|
| 1 | 工作树干净 | 半成品推上去，队友 pull 到跑不起来的东西 |
| 2 | 无超大文件（>5MB 警告 / >20MB 失败） | 534MB 的 APK、2.2G 的 `_install/` 误入库，clone 变灾难 |
| 3 | `_install/` `build/` `.godot/` `.workbuddy/` 未被跟踪 | 工具链/本地态进库，两人互相覆盖 |
| 4 | 无 `*.keystore`/`*.jks`/`*.p12`/`*.pem`/`.env` | 签名密钥泄露（项目红线：免费开源 ≠ 公开私钥） |
| 5 | 含非 ASCII 的 `*.ps1` 均带 UTF-8 BOM | Win PowerShell 5.1 不带 BOM 按 ANSI 读，中文注释直接崩解析器——这个坑本项目踩过不止一次（纯 ASCII 的脚本豁免，不误报） |
| 6 | `verify_all.ps1 -Fast` 退出码 0 | 把已知会挂的代码推上去，队友第一件事就是踩雷 |
| 7 | remote 已配置 | push 到不存在或打错的地址 |

## 首次建 remote（W-07，需要拥有者账号）

```powershell
# 1. 拥有者在 GitHub / Gitee 建空仓库（国内访问优先 Gitee；项目 GPL-3.0 免费开源，公开推符合红线）
# 2. 回到本地：
git remote add origin <你的仓库地址>
git push -u origin master
```

推之前**两人各自**确认：`_install/` 工具链已在本地放好（引擎 + Python + 音频素材），
clone 到任何盘符都能跑验收——所有脚本都按项目根相对定位，这是硬约定。

## 提交信息规范（本仓库已在用，保持一致）

```
<类型>(<范围>): <中文摘要，<= 50 字>

<正文：为什么这么改、关键决策、踩过的坑、没验证什么>
```

- 类型：`feat` / `fix` / `test` / `docs` / `chore` / `refactor`
- **正文比摘要重要**：写清"为什么"和"没验证什么"——后者是队友最需要的
- 小步提交：`sim/` 共用类攒大改动，合并时痛的是两个人
- 重设像素基线（`-UpdateBaseline`）**只能一个人干**，且在提交信息里说明理由

## 检查挂了怎么办

| 挂的项 | 处理 |
|---|---|
| 1 脏树 | `git status` 看清楚再 commit，别 `add .` 一把梭 |
| 2 超大文件 | 确认是不是 `build/`、`art/_raw/` 的东西被手动 `add` 了；`.gitignore` 已挡，正常不会挂 |
| 3 产物入库 | `git rm -r --cached <目录>`，确认 `.gitignore` 有对应条目再 commit |
| 4 密钥 | **立即停止 push**，删文件、删历史（`git filter-repo`），轮换密钥 |
| 5 缺 BOM | 只在你往脚本里写了中文/注释后出现。用 `AGENTS.md` §4 的 BOM 自检片段补（编辑工具保存时会吃掉 BOM，改完 `.ps1` 必须补）；纯 ASCII 老脚本不会误报 |
| 6 验收非 0 | 不许 push。看 `verify_all.ps1` 输出定位，修好重跑 |
| 7 无 remote | 见上方首次建 remote |
