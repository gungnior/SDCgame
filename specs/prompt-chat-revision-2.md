# 修订指令 2：APK 登录页键盘失效（阻断性 bug）

> 项目已完成并验收通过（`D:\prompt-chat\README.md`）。
> **本文件只修一个阻断性 bug + 两条同类加固，不是重写。先读现有代码再改。**

---

## 症状（用户真机反馈）

> 「这 apk 在手机上调用键盘老失败，我都输不了密码。」

用户**无法登录**，APK 处于完全不可用状态。

---

## 根因：一个无限重载循环

**服务端**（`server/index.mjs:111-114`）未登录时，用 **HTTP 401 状态码承载登录页 HTML**：

```js
if (!isAuthed(req)) {
  if (pathname.startsWith('/api/')) return sendJson(res, 401, { error: '未登录' });
  res.writeHead(401, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
  return res.end(LOGIN_PAGE);          // ← 401 + 登录页
}
```

**客户端**（`MainActivity.kt:122-126`）看到主框架 401 就重载同一个地址：

```kotlin
override fun onReceivedHttpError(...) {
    if (request.isForMainFrame && errorResponse.statusCode == 401) webView.loadUrl(currentUrl())
}
```

**两者组合成死循环：**

```
GET / ──► 401 + 登录页 HTML
          │
          ├─► WebView 触发 onReceivedHttpError(401)
          │
          └─► loadUrl(currentUrl())  ← 回到第一步
```

登录页每次都被下一次重载打断，永远无法完成渲染并接受点击。
登录页里还带 `autofocus`，键盘刚被唤起、页面就被销毁重建 ——
这就是用户看到的「调用键盘老失败」。

---

## 为什么之前的验收没发现

你在 README 里如实写了两次：**真机安装/点复制未能由我完成**。
之前所有登录测试都是 PowerShell 发 HTTP 请求：

```
未登录 GET /  ->  401        ← 这个断言是对的
```

**401 状态码本身没有问题**，用浏览器打开也会正常渲染登录页。
问题只存在于 Android WebView 的 `onReceivedHttpError` 回调里 ——
**这个缺陷只有真机才能暴露，HTTP 层测试永远测不到。**

这一点请写进 README 的「已知限制」，作为教训记录。

---

## 必修 1：删掉 401 自动重载

`MainActivity.kt` 的 `onReceivedHttpError` 里，**去掉 `loadUrl` 调用**：

```kotlin
override fun onReceivedHttpError(
    view: WebView, request: WebResourceRequest, errorResponse: WebResourceResponse
) {
    // 【不要在这里重载】服务端用 401 状态承载登录页 HTML，
    // 无条件 loadUrl 会导致「401 → 重载 → 401」的无限循环，登录页永远无法交互。
    // 401 的响应体本身就会被 WebView 正常渲染，无需任何客户端干预。
    // 若将来要处理「登录态中途失效」，必须用一次性守卫（见下文「可选」），不得无条件重载。
}
```

**如果那个 `loadUrl` 原本是为了解决某个具体问题**（比如 cookie 过期后白屏），
请在 README 里写明当初的意图，再用下面的「可选」方案实现，别直接丢掉需求。

---

## 必修 2：viewport 加 `interactive-widget=resizes-content`

Android Chrome 108+ 起，软键盘默认是**覆盖**内容而不是**压缩**视口。
你的聊天输入框固定在底部（`index.html` 的 `<form id="f">`），
登录页也用了 `height:100vh` —— 键盘弹出后会盖住输入框。

两处 viewport meta 都改成：

```
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover,interactive-widget=resizes-content">
```

涉及文件：
- `public/index.html`
- `server/index.mjs` 里的 `LOGIN_PAGE` 字符串（第 73 行）

`AndroidManifest.xml` 的 `windowSoftInputMode="adjustResize"` **保留**，两者配合才生效。

---

## 必修 3：登录页去掉 `autofocus`

`server/index.mjs:84` 的登录输入框：

```
<input id="t" type="password" placeholder="访问口令" autocomplete="current-password" autofocus>
```

**删掉 `autofocus`。** 原因：WebView 在页面加载期接受程序化聚焦时，唤起 IME 的行为
在不同 ROM 上不一致；让用户手动点一下，键盘一定会出来。这比自动聚焦可靠。

---

## 可选：如果确实需要「Cookie 失效后自动回登录页」

不要无条件 `loadUrl`。用一个**一次性守卫**：

```kotlin
private var reloadedForAuth = false
private var hadSuccessfulLoad = false   // onPageFinished 里置 true

override fun onReceivedHttpError(...) {
    if (!request.isForMainFrame) return
    if (errorResponse.statusCode != 401) return
    // 只有「曾经成功加载过」才可能是登录态失效；且整次会话只允许重载一次
    if (!hadSuccessfulLoad || reloadedForAuth) return
    reloadedForAuth = true
    webView.loadUrl(currentUrl())
}
```

这样初次未登录时（`hadSuccessfulLoad == false`）绝不会触发重载。

---

## 回归验证（在没有真机的前提下，你能做到什么程度）

**你做不到真机验证**（无 adb、无设备）。所以请**如实标注**，不要写成「已通过」。
你能做的是：

1. **静态断言**：改完后，`MainActivity.kt` 的 `onReceivedHttpError` 函数体内
   **不得出现 `loadUrl`**。请贴出该函数的最终代码作为证据。
2. **服务端行为复核**：`curl -i http://127.0.0.1:8090/` 确认未登录时
   返回 `HTTP/1.1 401` 且响应体是完整登录页 HTML（这是既有行为，确认没被改坏）。
3. **viewpot 复核**：用 `aapt2` 或直接读打包进 APK 的页面源码，
   确认两处 viewport 都含 `interactive-widget=resizes-content`。
4. **重新构建 APK**，覆盖 `D:\prompt-chat\android\app\build\outputs\apk\debug\app-debug.apk`
   和桌面 `提示词助手.apk`，报告新包大小。

在 README 里明确写：

> 本次修复**未经真机验证**（无可用设备）。静态证据：`onReceivedHttpError` 已无 `loadUrl`。
> 待用户在真机上确认能否正常唤起键盘并登录。

**用户会在真机上验证，你不要替他宣称通过。**

---

## 顺带自查（这次真机一暴露，说明同类问题可能还有）

请**逐条检查并回答**，不要只做上面三条：

1. `app.js` 里复制按钮：`http://` 明文下 `navigator.clipboard` 是 `undefined`。
   现在是否优先走 `window.Android.copy`？无桥时是否退回 `document.execCommand('copy')`？
   把相关代码贴出来。
2. `JsBridge` 是否在 `loadUrl` **之前**注入？（`configureWebView` 里必须早于任何加载）
3. `WebChromeClient` 只实现了 `onReceivedTitle`。页面里是否存在
   `alert()` / `confirm()` / `prompt()` 调用？**WebView 默认不实现这些，会静默失效或返回 null。**
   如果有，要么实现对应回调，要么改掉页面调用。
4. `localStorage` 相关：`domStorageEnabled = true` 已设，但确认主题与历史在
   **杀进程重启后**仍存在（这是真机才能验的，请标注）。
5. `shouldOverrideUrlLoading` 里对非 http(s) 的 scheme 调用了 `startActivity`，
   确认打开设置页/返回后不会把 WebView 留在错误状态。

---

## 不要做的事

- 不要重写已验收的部分（两轮 NEED 协议、安全函数、鉴权逻辑、防火墙）
- 不要改动服务端 401 + 登录页的设计（问题在客户端回调，不在服务端）
- 不要动 `C:\Users\xxx\.dsh\` 和 `D:\prism-llama\start_llama.bat`
- 不要把未真机验证的项写成「已通过」

---

## 验收清单

1. `MainActivity.onReceivedHttpError` 函数体内**不含 `loadUrl`**（贴出函数最终代码）
2. `public/index.html` 与 `LOGIN_PAGE` 的 viewport 均含 `interactive-widget=resizes-content`
3. 登录页 `<input>` 已无 `autofocus`
4. `curl -i http://127.0.0.1:8090/` 未登录仍返回 401 + 完整登录页 HTML
5. 上述自查 5 条逐条回答
6. APK 已重建，报告新包大小与桌面副本是否同步
7. README 追加本次修订记录，并**明确标注未经真机验证**
8. **收工前确认 `GET http://127.0.0.1:8081/v1/models` 返回 200** ——
   上次和上上次你都把模型留在停止状态了，别再犯第三次
