# 修订指令 3：给提示词服务加 OpenAI 兼容层（让 Chatbox 安卓能遥控 PC）

> 项目已完成并验收通过（`D:\prompt-chat\README.md`）。
> **本文件是增量新增一个能力，不重写任何已验收部分。**
> 两轮 NEED 协议、安全函数、鉴权、主题、防火墙一行都不要动。

---

## 目标

让 **Chatbox 安卓版**把本服务当成一个「模型」来用，从而在手机上遥控 PC 上的技能与规则：

```
手机 Chatbox → http://172.16.3.239:8090/v1/chat/completions
            → 服务内部：SKILL.md 注入 + 两轮 NEED 读规则 + 本地 27B 生成
            → 提示词回到手机
```

技能和规则**只有一份，在 PC 上**；手机不需要同步任何东西。
切换模型 = 切换技能。

---

## 一、实测抓包：Chatbox 安卓到底发什么（这是实现依据，不要凭猜）

下面是**从真实 Chatbox 安卓 1.23.4 抓到的原始请求**（通过一个 mock OpenAI 端点抓的）。
文件留存在 `C:\Users\xxx\.dsh\logs\chatbox-capture.log`，可直接查看。

### 1) 每个请求前都先发 OPTIONS 预检

```
OPTIONS /v1/chat/completions
host: 172.16.3.239:8091
origin: http://localhost
access-control-request-method: POST
access-control-request-headers: authorization,content-type
x-requested-with: xyz.chatboxapp.chatbox
sec-fetch-mode: cors
```

**Chatbox 安卓的 UI 跑在 WebView 里，origin 是 `http://localhost`，所以所有请求都是 CORS 请求。**
实测：不回 CORS 头 → 预检失败 → **真正的 POST 根本不会发出**。
（llama.cpp 默认发宽松 CORS 头，所以桌面版连它没问题；这个坑只在安卓端暴露。）

### 2) 真正的对话请求

```
POST /v1/chat/completions
authorization: Bearer token-abc123
content-type: application/json

{
  "model": "anima3-prompt-generator",
  "messages": [
    {
      "role": "system",
      "content": "You are a helpful assistant.\n\nAdditional info for this conversation: \n\n## Runtime\nCurrent model: anima3-prompt-generator\nConversation started: 2026-10-11 14:33 (UTC+08:00)\n<system-reminder>...</system-reminder> blocks are out-of-band runtime metadata from Chatbox (e.g. the current date and time), not part of the user's message. Treat their contents as authoritative; do not quote or acknowledge them."
    },
    {
      "role": "user",
      "content": [
        { "type": "text", "text": "hello-chatbox-android" },
        { "type": "text", "text": "capture-please" }
      ]
    }
  ],
  "stream": true
}
```

**要点（每一条都实测确认过）：**

| 事实 | 说明 |
|---|---|
| `model` = 你在 Chatbox 里填的 modelId | 所以**用技能名当 modelId** 成立 |
| `authorization: Bearer <API密钥>` | 口令填在 Chatbox 的「API 密钥」字段 |
| **`content` 可能是数组** | `[{"type":"text","text":"..."}]`，不是字符串。**必须兼容两种形式** |
| **多轮被合并** | 多轮 user 消息被合成**一个 message 的多个 content part** |
| **Chatbox 会发它自己的 system prompt** | `You are a helpful assistant.` + `## Runtime` 元数据。**必须剥离，不要传给流水线** |
| 没有 `tools` 字段 | 因为模型条目**没有勾 capabilities**。保持这样，兼容层就不用实现函数调用 |

### 3) Chatbox 会用同一个端点生成「对话标题」

```
POST /v1/chat/completions
{
  "model": "anima3-prompt-generator",
  "messages": [{ "role": "user", "content": "Based on the chat history, give this conversation a name.\nKeep it short - 10 words max, no quotes.\nUse 简体中文.\n..." }],
  "stream": true
}
```

**如果不识别这个，兼容层会为一条「给对话取名」跑完整的两轮 NEED 流水线** —— 白等十几秒，还可能把生成出来的提示词当成标题。

---

## 二、要实现的东西（新增一个文件 + 少量路由）

建议新增 `server/openai-compat.mjs`，在 `server/index.mjs` 里挂上。
**仍然零第三方依赖。**

### 2.1 CORS（硬阻塞，优先级最高）

- `OPTIONS /v1/*` → 直接返回 **204**，带下列头
- 所有 `/v1/*` 响应都要带这些头

```
Access-Control-Allow-Origin: *
Access-Control-Allow-Methods: POST, GET, OPTIONS
Access-Control-Allow-Headers: authorization, content-type, x-requested-with
Access-Control-Max-Age: 86400
```

### 2.2 `GET /v1/models`

返回技能列表，每个技能一个「模型」：

```json
{ "object": "list", "data": [
  { "id": "anima3-prompt-generator", "object": "model", "created": 1, "owned_by": "prompt-chat" },
  { "id": "h3-nsfw-director",        "object": "model", "created": 1, "owned_by": "prompt-chat" }
] }
```

### 2.3 `POST /v1/chat/completions`

处理顺序（照这个顺序做，能省很多事）：

1. **鉴权**：复用现有 `isAuthed`。**注意：`/v1/*` 未授权时必须返回 JSON 401**（形如
   `{"error":{"message":"unauthorized","type":"invalid_request_error"}}`），
   **不能返回 HTML 登录页** —— 否则 Chatbox 的报错看不懂。
2. **识别标题请求**：任一 message 的文本里含 `give this conversation a name`（大小写不敏感）
   → **不跑流水线**，直接从最后一条 user 消息里取会话内容的前几个词当标题返回。
   这类请求用便宜的一次模型调用或直接截断都行，但**绝对不能跑 SKILL.md + NEED**。
3. **取技能**：`body.model` → 技能名。技能不存在 → 返回 OpenAI 风格错误：
   ```json
   { "error": { "message": "unknown model: xxx", "type": "invalid_request_error", "code": "model_not_found" } }
   ```
4. **提取文本**（写一个 `textOf(content)` 帮助函数）：
   - `content` 是字符串 → 直接用
   - `content` 是数组 → 把每个 `{type:'text'}` 的 `text` 用 `\n` 拼起来
5. **剥离 system 消息**：`role === 'system'` 的全部丢弃（那是 Chatbox 的人设与 Runtime 元数据）。
6. **映射历史**：把剩下的 user/assistant 消息按顺序拼成现有流水线的 `history`，
   最后一条 user 消息作为本次 `message`。
7. **跑现有流水线**（两轮 NEED + 预算守卫，一行都别改）。
8. **输出**：
   - `stream: true` → 按下面的 SSE 格式流式输出
   - `stream: false` → 返回普通 JSON
   - **把「已加载规则」塞进正文开头**（OpenAI 格式没地方放这个信息）：
     ```
     > 已加载规则：04-slot-order.md, 09-pose-solo.md
     ```
     放在最前面，跟一个空行，然后是模型原本的输出。

### 2.4 SSE 格式（照抄这份，已被 Chatbox 安卓实际接受）

我的 mock 实现就是**已验证可用的最小参考**，文件在
`C:\Users\xxx\.dsh\scripts\mock-openai.mjs`，**直接照着它的格式写**。

```
data: {"id":"chatcmpl-x","object":"chat.completion.chunk","created":1,"model":"<model>","choices":[{"index":0,"delta":{"role":"assistant","content":"第一段"},"finish_reason":null}]}

data: {"id":"chatcmpl-x","object":"chat.completion.chunk","created":1,"model":"<model>","choices":[{"index":0,"delta":{"content":"第二段"},"finish_reason":null}]}

data: {"id":"chatcmpl-x","object":"chat.completion.chunk","created":1,"model":"<model>","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]
```

硬性要求：

- 每行必须是 `data: `（**冒号后有一个空格**）+ 一行 JSON，行尾 `\n\n`
- 结尾**必须**是 `data: [DONE]`
- 如果请求带了 `"stream_options": {"include_usage": true}`，在 `[DONE]` 之前补一个：
  ```
  data: {"id":"...","object":"chat.completion.chunk","created":1,"model":"...","choices":[],"usage":{"prompt_tokens":N,"completion_tokens":M,"total_tokens":N+M}}
  ```
  （实测 Chatbox 会把它显示成 `· 15 tokens`）
- **首字延迟是正常的**：两轮协议要先让模型点名规则文件，首字可能 5–15 秒。
  可以先发一个空 delta 的心跳，或者什么都不发让 Chatbox 显示「正在输入」。

---

## 三、环境线索（上次你说"本机没有 adb、也没有设备"，这次是错的）

| 项 | 值 |
|---|---|
| **MuMu 模拟器** | 已启动且常驻，Android 12，机型 SM-S9080 |
| adb 可执行文件 | `C:\Users\xxx\AppData\Local\Android\Sdk\platform-tools\adb.exe` |
| 模拟器 adb 地址 | `127.0.0.1:16384`（`adb connect 127.0.0.1:16384`） |
| MuMu 管理工具 | `D:\Program Files\Netease\MuMuPlayer-12.0\nx_main\MuMuManager.exe` |
| **Chatbox 安卓已装好** | 包名 `xyz.chatboxapp.chatbox`，版本 1.23.4 |
| Chatbox 安卓配置位置 | `/data/data/xyz.chatboxapp.chatbox/databases/chatboxSQLite.db` 的 `key_value` 表（`settings` 行） |
| adb 权限 | **adbd 已经是 root**，可直接读写 `/data/data/...`（无需 su） |
| 27B 模型 | 8081 **正在运行**，`bonsai-27b` |
| 8090 服务 | **未启动**，你自己用 `start.bat` 起 |

**在模拟器里配 Chatbox 的两种方式：**

- **UI 方式**：设置 → 模型提供方 → 添加 → 选「OpenAI API 兼容」→ 填 API 主机和密钥 → 加模型。
- **直接改数据库（更快、更可靠，我就是这么做的）**：改 `settings` 行里的
  `settings.providers['custom-provider-<uuid>']` **和** `settings.customProviders[]`
  两处 —— **只做前者界面上不会显示**（我在这卡了两轮）。
  `customProviders` 条目形如 `{"id":"custom-provider-<uuid>","name":"...","type":"openai","isCustom":true}`。
  改完要 `chown` 回 `u0_a37:u0_a37`、`chmod 600`。

---

## 四、验收清单（逐条跑，把结果贴回来）

1. `curl -i -X OPTIONS http://127.0.0.1:8090/v1/chat/completions` → **204** + 三个 CORS 头
2. 未授权 `POST /v1/chat/completions` → **JSON 401**（不是 HTML）
3. 带 `Authorization: Bearer <口令>`、`model=anima3-prompt-generator`、普通字符串 content
   → 返回 SSE，内容是**一段真实提示词**，开头有「已加载规则：…」
4. `content` 传**数组形式** → 能正确解析（不能因为它是数组就报错）
5. `model` 传不存在的技能 → 返回 OpenAI 风格错误体
6. 发一条含 `give this conversation a name` 的请求 → **日志显示走了标题捷径，没有跑 NEED 流水线**
7. 带 `stream_options.include_usage` → 最后有 usage chunk
8. **在 MuMu 模拟器里端到端实测**：
   - 启动 `start.bat`
   - Chatbox 安卓里配置提供商：API 主机 `http://172.16.3.239:8090`，API 密钥 = 访问口令，
     模型填 `anima3-prompt-generator`（**capabilities 全部留空，不要勾 `tool_use`**）
   - 发一句「性感女性」→ **手机里拿回提示词**
   - 截图或把 Chatbox 里显示的回复贴回来
9. 收工前确认 `GET http://127.0.0.1:8081/v1/models` 返回 200（这已经是第三次要求了）
10. 结果写进 `README.md`，新增一节

---

## 五、不要做的事

- 不要重写两轮 NEED 协议、安全函数（`safeRefFile`/`safeSkillDir`）、鉴权、主题、防火墙
- 不要引入任何 npm 依赖
- 不要实现 tools / function calling（实测 Chatbox 不勾 capabilities 就不会发）
- 不要动 `C:\Users\xxx\.dsh\` 和 `D:\prism-llama\start_llama.bat`
- 不要把 Chatbox 的 system prompt 传进流水线
- 不要为标题请求跑完整流水线
- **不要声称"已通过真机验证"而不实际跑第 8 项** —— 模拟器就在你手边，adb 可用
