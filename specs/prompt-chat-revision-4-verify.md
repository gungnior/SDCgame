# 修订 4 独立复验指令（对抗性）· 块级向量检索

> ⚠️ **这次的实现者是规格作者本人（我），不是 WorkBuddy。**
> 所以你的任务**不是**"确认它能用"，而是**尝试证明它不能用**。
> 报告里我给出的每一个数字，你都要用**自己的命令**重新跑一遍。**不要采信我的数字。**

---

## 〇、我改了什么（核对范围用）

| 文件 | 状态 | 行数 |
|---|---|---|
| `server/retrieval.mjs` | **新增** | 330 |
| `server/pipeline.mjs` | 重写（检索路径 + 保留旧 NEED 兜底） | 306 |
| `server/index.mjs` | 改（2 个接口 + 启动建索引） | 252 |
| `server/openai-compat.mjs` | 改（规则行） | 272 |
| `server/config.mjs` | 改（加 `retrieval` 段） | 110 |
| `config.json` | 改（加 `retrieval` 段） | 59 |
| `public/app.js` | 改（状态行显示块数） | 371 |
| `README.md` | 加第十五节 | 614 |

`auth.mjs` / `skills.mjs` / `model.mjs` **应当一行未动** —— 请用 diff 确认。

---

## 一、★ 对抗性核心验收（最重要，优先做）

**上一轮我只用「性感女性」测了 10 次。这不够 —— 那是个不会诱导禁止标签的需求。**

真正的测试是用**故意诱导**的需求。以下每一条都会引诱模型输出 `§13.6` 明令禁止的标签：

| # | 需求（直接用这个字符串） | 诱导的禁止标签 |
|---|---|---|
| 1 | `夜晚霓虹灯下的都市女性` | `neon lights`, `streetlights` |
| 2 | `月光下的沙滩` | `moonlight` |
| 3 | `烛光晚餐` | `candlelight` |
| 4 | `逆光剪影` | `backlighting`, `rim light` |
| 5 | `夕阳金色时刻` | `golden hour glow` |
| 6 | `发光的天使` | `glowing`, `illuminated`, `backlit` |
| 7 | `昏暗灯光下的房间` | `dim light` |
| 8 | `赛博朋克霓虹招牌` | `neon lights` |

**每条跑 3 次 = 24 次。任何一次出现禁止标签，这一项即判失败，并给出完整 prompt 作为证据。**

### 检查表必须以规则为准

权威清单在 `C:\Users\xxx\.dsh\skills\anima3-prompt-generator\references\13-detail-mood.md`
的 **§ 13.6 禁止输出清单**（第 75-87 行），共五类：

- 光线描述：`sunlight, moonlight, dim light, candlelight, neon light, neon lights, streetlights`
- 光影技术：`backlighting, rim light, warm lighting, cool lighting, golden hour glow, soft lighting`
- 色调描述：`warm tone, cool tone, sepia, blue tone, amber tone`
- 光学现象：`god rays, light rays, light particles, volumetric light beams, tyndall effect`
- 发光描述：`glowing, illuminated, lit, backlit, spotlight, flash`

**逐条抄成你的检查表，不要自己总结。**

我写了个脚本 `C:\Users\xxx\.dsh\scripts\test-retrieval.mjs`（33 条正则）。
**你要先核对它是否真的覆盖了上面每一条 —— 我可能漏。** 我只用「性感女性」跑过它，没用上面的诱导需求跑过。

---

## 二、我完全没测的部分（重点找问题）

### 2.1 `h3-nsfw-director` 技能 —— **检索路径从没跑过**

- 它的索引有 46 块，但 `pinnedFiles` / `pinnedHeadingPattern` 是**为 anima3 调的词**，
  对 h3 是否命中固定约束**完全未知**
- 请检查 h3 有哪些块被标为 `pinned`，并判断**够不够用**（h3 自己的硬约束在哪几个文件里）
- 用 h3 跑 3 次生成，按**它自己的规则**检查输出
- **注意**：`references/official/README.md` 在子目录里，而 `skills.mjs` 的 `NAME_RE` 只认顶层文件名，
  所以它**没进索引**。确认这是否符合预期，以及 h3 是否因此缺了关键规则

### 2.2 网页版 / APK 的界面 —— **我改完没有目视验证过**

- `public/app.js` 的状态行改成显示 `规则 N 块 / M 文件（固定约束 K 块）`
- **截图确认**：跑一次生成，看状态行是不是这个格式，数字对不对
- 确认原来那个**假的「上限」标签**（第十二节提到的显示 bug）确实没了
- `app.js` 是打进 APK 的，所以**APK 需要重新构建**才能看到新状态行；构建后装进 MuMu 验一次

---

## 三、边界与破坏性测试

1. **索引重建一致性**：把 `index/embeddings.json` 删掉 → 重启 → 块数是否仍为 282？块内容是否一致？
2. **索引损坏**：用坏 JSON 覆盖索引文件 → 服务能起来吗？会退回兜底吗？还是直接崩？
3. **Ollama 中途挂**：请求进行中把 Ollama 停掉 → 请求会挂多久？有没有超时生效？
4. **空消息 / 超长消息**：`message` 传 `""` 和传 5000 字符（注意 `slice(0,4000)`）→ 行为是否符合预期
5. **并发**：同时发 2–3 个请求 → 索引文件会不会被写坏？日志有没有交错？
6. **切块质量抽查**：随机抽 5 个块打印出来，看有没有把 Markdown 表格切碎、把标题和正文分离、产生只有几个字符的碎片
7. **固定约束真的"最后才丢"吗**：临时把 `budget.maxPromptTokens` 调到 3000 → 观察日志里丢弃顺序，
   确认**先丢检索块、后丢固定约束块**
8. **安全函数未被改动**：diff 确认 `safeRefFile` / `safeSkillDir` / `NAME_RE` 一行没动

---

## 四、要补的两件小事

1. **`.gitignore` 加 `index/`** —— 索引是我生成的缓存，不该进版本库
2. **「可选调整」里的违禁建议**：模型建议过「改为夜晚月光下」，而 `moonlight` 正是 `§13.6` 禁止的光线描述。
   实际 prompt 是干净的，但**建议文本里的措辞违规**。评估是否该在 `SKILL.md` 加一条约束。
   （**先评估再改，不要直接动技能文件** —— 那是内容决策）

---

## 五、不要做的事

- ❌ 不要因为"看起来能跑"就跳过第一节的诱导测试
- ❌ **不要只跑我的脚本就下结论** —— 那是我写的，可能有盲区
- ❌ 不要重写 `retrieval.mjs`。**找到缺陷先报告**，不要边查边改（改完我就分不清是复验还是新实现了）
- ❌ 不要动鉴权 / 主题 / 防火墙 / 安全函数
- ❌ 不要引入任何 npm 依赖
- ❌ **不要把 Ollama 暴露到网络**（保持 `127.0.0.1`）

---

## 六、报告要求

- 逐条给出**你自己的命令和原始输出**，不要引用我的数字（我给的数字只用来对照）
- 任何一条无法复现，直接写「无法复现」，不要含糊
- 找到缺陷 → 给出**最小复现步骤**
- 结尾一句结论：**修订 4 是否可接受**

---

## 七、环境

| 项 | 值 |
|---|---|
| 服务 | `8090` 正在运行（口令见 `D:\prompt-chat` 的 `查看口令.bat`，或直接用 `Authorization: Bearer <口令>`） |
| 模型 | `127.0.0.1:8081`，`bonsai-27b`，在线 |
| Ollama | `127.0.0.1:11434`，已设 `OLLAMA_KEEP_ALIVE=60s` / `OLLAMA_MAX_LOADED_MODELS=1` |
| MuMu 模拟器 | **正在运行**，Chatbox 安卓已配好指向 `http://172.16.3.239:8090` |
| adb | `C:\Users\xxx\AppData\Local\Android\Sdk\platform-tools\adb.exe`，`adb connect 127.0.0.1:16384`，**adbd 是 root** |
| 我的脚本 | `C:\Users\xxx\.dsh\scripts\`（`test-retrieval.mjs`、`chatbox-*.mjs`、`ui.ps1` 等） |

### ⚠️ 两个已知陷阱

1. **启动 Electron 应用前必须清掉 `ELECTRON_RUN_AS_NODE`**：
   ```powershell
   Remove-Item Env:\ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
   ```
   不清的话 Chatbox 会被当成纯 Node 执行，**立刻退出、无窗口、无日志、退出码 0**，看起来像"启动坏了"。
   我在这上面浪费了三轮。

2. **Chatbox 安卓的 UI 是整个 WebView**，`uiautomator` 看不到内部控件，只能靠**截图估坐标**。
   要读回复原文，直接拉它的数据库：
   `/data/data/xyz.chatboxapp.chatbox/databases/chatboxSQLite.db` 的 `key_value` 表，
   session 内容在 `contentParts[].text`（注意 `content` 字段是空串，用 `??` 不会穿透，要用 `||`）。
   参考 `C:\Users\xxx\.dsh\scripts\chatbox-last-reply.mjs`。
