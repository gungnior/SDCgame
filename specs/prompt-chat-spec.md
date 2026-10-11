# 实现规格：本地模型提示词助手（移动端 Web）

> 本文件是交给 AI 编码 Agent 的施工规格。自包含，不需要额外背景。
> 目标读者：能读写文件、能运行命令的编码 Agent。

---

## 1. 目标

在 Windows PC 上做一个**极简的移动端网页聊天工具**，让用户在手机上（局域网或异地）使用
**PC 本地的 llama.cpp 模型 + 已有的技能(Skill)规则库**，产出图像/视频提示词。

已有一个更复杂但**不适用**的方案（DSH agent）被否决，原因是它的系统提示词基线高达 ~35,700 token，
超过本地模型 32,768 的上下文。**本方案的核心指标就是把提示词压到 ~12K token 以内。**

---

## 2. 硬约束（违反则方案失败）

1. **上下文预算**：单次请求 prompt 必须 ≤ 24,000 token，目标 ~12,000。
2. **零第三方依赖**：Node 只用标准库（`node:http`/`node:fs`/`node:path`/`node:crypto`/`fetch`）。
   不要 npm install 任何东西。
3. **规则按需读取**：**禁止**把 references 目录一次性读进上下文。必须走第 5 节的两轮协议。
4. **不接知识库**：不要向量检索、不要 embedding、不要 Ollama。规则直接读磁盘 `.md` 文件。
5. **不执行 shell**：服务端不得提供任何执行命令的能力。
6. **不碰 DSH**：不要修改 `C:\Users\xxx\.dsh\` 下任何现有文件（只读技能目录）。

---

## 3. 运行环境（已确认存在）

| 项 | 值 |
|---|---|
| 系统 Node | `C:\Program Files\nodejs\node.exe`，v24.21.0 |
| 模型服务 | `http://127.0.0.1:8081/v1`（llama.cpp，OpenAI 兼容） |
| 模型名 | `bonsai-27b` |
| 模型上下文 | 32,768 token（服务端写死，不要假设更大） |
| 技能根目录 | `C:\Users\xxx\.dsh\skills\`（每个子目录含 `SKILL.md`） |
| 实测 token 比 | **0.79 token / 字符**（中文为主的内容，用于预算估算） |

现有两个技能：
- `anima3-prompt-generator`（28 个 references，共 112,555 字符）
- `h3-nsfw-director`（6 个 references）

---

## 4. 交付物

```
D:\prompt-chat\
├── server.mjs        Node 后端，约 300 行
├── index.html        移动端单页，约 300 行（内联 CSS/JS，不引外部资源）
└── start.bat         启动脚本（含 pause）
```

服务监听 `http://0.0.0.0:8090`（8090 要避开已占用的 8081/3080/3443）。

---

## 5. 核心协议：两轮 NEED 读取

**不要依赖模型的 function calling**（该模型 `/v1/models` 只声明 `capabilities:["completion"]`，工具调用无保证）。
用纯文本的确定性协议。

### 第 1 轮

system 消息内容（按此顺序拼接）：

```
<SKILL.md 的完整内容>

===== 可用的规则文件（本技能的 references 目录） =====
00-index.md            6431 字  <首行摘要>
00-quick-start.md      4223 字  <首行摘要>
04-slot-order.md       6490 字  <首行摘要>
...（每篇一行：文件名 + 字符数 + 正文首行，截断到 100 字）
```

> 目录表由服务端生成，**不是**把文件内容读进来。整表应 < 2,000 字符。

user 消息 = 用户的需求（例如「我要一个性感女孩的提示词」）。

并要求模型**只输出一行**：

```
NEED: 04-slot-order.md, 09-pose-solo.md
```
或
```
READY
```

### 第 2 轮

服务端解析第 1 轮的输出：

- 用正则 `([0-9A-Za-z._-]+\.md)` 抓出所有 `.md` 文件名（**宽容匹配**，不要求严格格式）。
- **白名单校验（安全关键）**：
  - 文件名必须完全匹配 `^[0-9A-Za-z._-]+\.md$`
  - 拒绝含 `/`、`\`、`..`、绝对路径、盘符
  - `path.resolve(refDir, name)` 的结果必须以 `refDir + path.sep` 开头
  - 文件必须真实存在且是普通文件
  - 不合法的名字直接丢弃并记录日志
- 最多取 **3 篇**；按需截断：单篇超过 12,000 字符时截断并加 `...[已截断]`。
- 抓不到任何合法文件名 → 兜底注入 `00-index.md`，并要求模型再要一次（允许最多 2 次 NEED 往返）。
- 模型输出 `READY` → 直接进入第 2 轮生成。

第 2 轮 system = 第 1 轮的 system + **本次要到的文件全文**（用 `########## 文件名 ##########` 分隔）。
user = 同样的原始需求，附一句「现在按技能规定的格式输出最终结果，不要再要文件」。

### 预算守卫

拼接完成后估算 `token ≈ 字符数 × 0.79`。超过 24,000 就**从后往前丢弃规则文件**，直到达标。
若只剩 SKILL.md 仍超标，直接返回错误给前端（不要发给模型）。

---

## 6. 模型调用

`POST http://127.0.0.1:8081/v1/chat/completions`

```json
{
  "model": "bonsai-27b",
  "messages": [...],
  "max_tokens": 1200,
  "temperature": 0.7,
  "stream": true,
  "chat_template_kwargs": { "enable_thinking": false }
}
```

要点：
- **必须带 `chat_template_kwargs.enable_thinking = false`**。这是推理模型，不关思考会写满输出预算导致最终答案被截断（实测过）。
- 若服务端返回 400 且提到 `chat_template_kwargs`，**去掉该字段重试一次**。
- 流式（SSE）：逐 `data: ` 行解析，取 `choices[0].delta.content`，转发给前端。
- 服务端若返回 400 且 message 含 `exceeds the available context size`，**原样把这段错误显示给前端**（这是最关键的诊断信息）。
- 超时 300 秒（27B 模型提示词大时首轮较慢）。

---

## 7. 前端要求（移动端优先）

- `<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">`
- 单列布局，输入框吸底，触控目标 ≥ 44px，支持深色模式
- 流式显示回复；请求中显示「正在读取规则…」/「正在生成…」两个阶段
- **一键复制**：把回复里的 ` ```text ` 代码块内容提取出来，在代码块上方渲染一个「复制提示词」按钮（`navigator.clipboard.writeText`）。这是本工具的核心动作。
- 会话历史存 `localStorage`（最多保留 50 条），刷新不丢
- 技能选择器：启动时 `GET /api/skills` 列出 `C:\Users\xxx\.dsh\skills\` 下的技能名，下拉切换
- 出错时把服务端返回的原始错误文本显示在气泡里，不要吞掉

---

## 8. 后端接口

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/` | 返回 index.html |
| GET | `/api/skills` | `[{ name, refCount, totalChars }]`，扫描技能根目录 |
| POST | `/api/chat` | body `{ skill, message, history? }`，返回 `text/event-stream` |
| POST | `/api/auth` | body `{ token }`，校验后下发 httpOnly cookie |

SSE 事件：
```
data: {"type":"stage","value":"reading"}
data: {"type":"stage","value":"generating"}
data: {"type":"files","value":["04-slot-order.md","09-pose-solo.md"]}
data: {"type":"delta","value":"..."}
data: {"type":"error","value":"<原始错误>"}
data: {"type":"done","usage":{"prompt_tokens":12345,"completion_tokens":456}}
```

---

## 9. 安全

异地使用意味着会被公网/别的网络访问，必须做：

1. **鉴权**：环境变量 `PROMPT_CHAT_TOKEN` 读一个口令。未携带有效 cookie 的请求一律 401 并返回登录页。
   cookie 用 `httpOnly`、`SameSite=Lax`、有效期 30 天。
2. **路径白名单**：见第 5 节，防目录穿越。这是唯一接触文件系统的入口。
3. **无 shell**：不实现任何执行命令的接口。
4. **绑定与访问范围**：绑 `0.0.0.0:8090`（这样本机 `localhost` 和虚拟网卡都能访问）。
   **异地访问不需要额外装隧道工具**——这台机器上已经有蒲公英（贝锐 OrayBoxVpnEnt）虚拟局域网在运行，
   地址是 `172.16.3.239`。手机装蒲公英客户端加入同一网络后，直接开 `http://172.16.3.239:8090` 即可。
   因为在虚拟局域网里鉴权是唯一防线，第 1 条的 token 鉴权**必须实现，不可省略**。
5. **防火墙最小化**：`start.bat` 首次运行时，用 `netsh advfirewall firewall add rule` 只放行
   8090 端口来自 `172.16.0.0/12`（蒲公英）和 `192.168.0.0/16`（本机局域网）的入站连接，
   不要放行 0.0.0.0/0。
6. 请求体上限 1 MB。

---

## 10. 验收清单

实现完成后逐条自测并在回复中给出结果：

- [ ] `node server.mjs` 能启动，`http://localhost:8090` 能打开
- [ ] `GET /api/skills` 返回 2 个技能（`anima3-prompt-generator`、`h3-nsfw-director`）
- [ ] 选 `anima3-prompt-generator`，发「我要一个性感女孩的提示词」
- [ ] 服务端日志显示第 1 轮模型输出被解析成文件名，且**文件名通过白名单校验**
- [ ] 第 2 轮返回的内容里有 ` ```text ` 代码块 + `中文对照：` 行
- [ ] 最终 `usage.prompt_tokens` **< 24000**（在浏览器里显示出来）
- [ ] 构造恶意文件名（如 `../../../../windows/win.ini`）时**被拒绝**且不泄露文件
- [ ] 无 cookie 访问 `/api/chat` 返回 401
- [ ] 手机浏览器（同局域网）能正常使用，代码块复制按钮可用
- [ ] 杀进程重启后能正常工作

---

## 11. 不要做的事

- 不要引入 npm 依赖、构建步骤、框架（React/Vue 都不要）
- 不要接入 DSH、知识库、embedding、Ollama
- 不要修改 `C:\Users\xxx\.dsh\` 下任何文件
- 不要把 references 全量读入上下文
- 不要实现 function calling / tool calling
- 不要为了"更完整"加功能：这个工具的范围就是「选技能 → 输需求 → 出提示词 → 复制」

---

## 12. 已知坑（实测踩过，务必遵守）

1. **模型是推理模型**：不关 thinking 会把输出预算烧在思考上，`content` 为空、`finish_reason=length`。
   必须 `chat_template_kwargs.enable_thinking=false`。
2. **上下文只有 32768**：prompt 超了服务端返回 400 且带 `n_prompt_tokens`，这是最有用的诊断信息，别吞。
3. **规则文件里表格很多**：不要用任何"智能分块"，直接整篇读、按需读。
4. **首轮慢是正常的**：27B + ~12K 提示词，首轮可能 30–90 秒。之后 llama.cpp 会命中前缀缓存，明显变快。
