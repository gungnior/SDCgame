# 修订指令 1：本地模型提示词助手

> 项目已完成并验收通过（见 `D:\prompt-chat\README.md`）。
> **本文件是增量修订，不是重写。请先读完现有代码再动手，只改下面列出的点。**

---

## 修订 1 · `config.json` 必须是合法 JSON

**现状**：`D:\prompt-chat\config.json` 里有 `//` 注释，因此**不是合法 JSON**。
`config.mjs` 里写了一个容错解析器来剥注释。

**问题**（不是洁癖，是实际影响）：

- 任何标准工具读它都会失败 —— 编辑器不会校验语法、`jq` / `ConvertFrom-Json` / 其他脚本一律报错
- 容错解析器是靠正则剥 `//` 的，**一旦某个字符串值里出现 `//`（比如 URL 写成 `http://`），解析就会错**
- 配置项注释的价值是给人看的，但代价是让这个文件对所有机器不可读

**改为**：

1. `config.json` 里**删除所有注释**，确保 `JSON.parse` 能直接成功
2. 所有键的说明移到一个新的 `config.md`，用表格列出：键名 / 当前值 / 含义 / 改动后是否需重启
3. `config.mjs` 里那个剥注释的容错逻辑**删掉**，改成直接 `JSON.parse`，
   解析失败时就报清晰的错误（指出文件路径和出错位置），不要静默容错
4. **启动时做一次自检**：`JSON.parse` 失败 → 打印明确的错误并退出，不要带着坏配置跑

**验收**：用 `node -e "JSON.parse(require('fs').readFileSync('config.json','utf8'))"` 能成功；
故意把 JSON 改坏，启动时应报错退出而不是静默使用默认值。

---

## 修订 2 · 明文策略：去掉「蒲公英 IP 变了就必须重编 APK」这个地雷

**现状**：`android/app/src/main/res/xml/network_security_config.xml` 里

- `base-config cleartextTrafficPermitted="false"`（默认全拒）
- `domain-config` 只放行写死的三个主机：`172.16.3.239`、`127.0.0.1`、`localhost`

**问题**：Android 的 network security config **只支持主机名，不支持 CIDR**（你已在注释里诚实写明）。
后果是：**蒲公英一旦给这台 PC 换一个 IP，用户在设置里改地址也没用 —— 明文被系统拦掉，必须重新编译 APK。**
这跟「服务器地址运行时可改、以后方便修改」的需求直接冲突。

**改为**：

1. 把 `base-config` 的 `cleartextTrafficPermitted` 改为 **`true`**，
   移除 `domain-config` 里那三个写死的 `<domain>`
2. 真正的门禁交给**应用层**（这是本来就该承担这一职责的地方）：
   - `Config.kt` 的 `ALLOWED_CIDRS`（`172.16.0.0/12` + `192.168.0.0/16`）作为唯一裁决
   - 校验必须覆盖**每一个入口**，不能只在首次加载时查：
     - 首次 `loadUrl` 之前
     - `WebViewClient.shouldOverrideUrlLoading` 里**每一次**导航
     - `SettingsActivity` 保存地址时先校验再落盘
   - 不在允许网段内的地址：拒绝加载 + 明确提示「该地址不在允许的网段内」
3. 在 `config.md` 或 README 里写清这个取舍：
   明文许可是给整个应用放开的，但本应用只会加载用户配置并经网段校验的单一地址，
   不存在第三方页面，因此实际暴露面与逐主机白名单等价。
4. 若将来想彻底不放开明文：改用 HTTPS + 自签证书 + `network_security_config` 的 `<pin>` 固定证书，
   那样连明文开关都不需要。**本次不做，只在 README 里记一笔备选方案。**

**验收**：
把默认地址改成一个**同网段但不同 IP**（如 `http://172.16.3.240:8090`），
不重新编译、直接在设置里改地址 → 应能尝试连接（而不是被系统明文策略瞬间拦掉）；
改成一个**网段外**地址（如 `http://8.8.8.8:8090`）→ 应被应用层拒绝并给出提示。

---

## 修订 3 · 模型别名回归验证（我已在你机器上改过 `start_llama.bat`）

**背景**：你原来的 `llama-server` 命令行带 `--alias bonsai-27b`，但 `D:\prism-llama\start_llama.bat` 里没有。
所以通过 app 的「重启模型」拉起来的实例会丢掉别名，`/v1/models` 会显示 GGUF 路径。

**我已经在 bat 里加上了 `--alias bonsai-27b`**，并已实测：重启后 `data[0].id = bonsai-27b`，
`model: "bonsai-27b"` 的请求返回 200。**不需要你再改 bat。**

**你要做的**：把这个变成一条**回归检查**写进 README 的验收清单：

> 用 app 的「重启模型」重启后，`GET /v1/models` 返回的 `data[0].id` 必须仍然是 `bonsai-27b`。

如果你后续改了 `start_llama.bat` 或换了启动方式，这条能第一时间发现别名又丢了。

---

## 顺带清理（非阻塞）

1. `D:\prompt-chat\server.log`（11 KB）留在项目根目录了。移到 `logs\` 子目录，
   并在 `.gitignore`（如果没有就建一个）里忽略 `*.log`、`.token`、`android\build\`、`android\.gradle\`。
2. README 里 `server.mjs` 的行数（457）已经过时 —— 该文件已被删除，改成模块化结构了。
   核对并订正 README 里的文件清单和行数。
3. README 的「prompt_tokens 实测值」表里，服务端估算值有几轮达到 12,673 ~ 13,397，
   略高于 `budget.targetTokens`（12000）但低于 `maxPromptTokens`（24000）。
   这是正常的（target 是软目标，cap 才是硬限制），但在 README 里加一句说明，免得以后误判成 bug。

---

## 不要做的事

- 不要重写已通过验收的部分（两轮 NEED 协议、安全函数、主题、鉴权、防火墙）
- 不要引入任何依赖
- 不要动 `C:\Users\xxx\.dsh\` 和 `D:\prism-llama\start_llama.bat`
- 不要在 `network_security_config.xml` 里试图用 CIDR（Android 不支持，别再试一遍）

---

## 验收清单

1. `JSON.parse` 能直接读 `config.json`；改坏 JSON 时启动报错退出
2. 同网段不同 IP 的地址能在不重编 APK 的情况下被接受（至少不被系统明文策略拦掉）
3. 网段外地址被应用层拒绝，且 `shouldOverrideUrlLoading` 也拦得住
4. 用 app 重启模型后，`/v1/models` 的 `data[0].id` 仍是 `bonsai-27b`
5. 上述改完后，重跑一次原有的 6 次生成验收，规则注入数仍**全部 ≥1 篇**
6. 结果写进 `D:\prompt-chat\README.md` 并贴回给我
