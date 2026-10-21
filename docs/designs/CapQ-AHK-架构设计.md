# CapQ —— 剪贴板 AI 快捷助手（AutoHotkey v2 方案）

> 一句话定位：选中文本 → `Ctrl+C` → 按快捷键 → AI 回答自动进剪贴板 + Win11 Toast 提醒，全过程不切窗口。
>
> **本版基于 AutoHotkey v2 重写选型结论**；第 9 章保留「何时该换回 Rust」的判断依据。

---

## 0. 结论：这个需求 AHK 确实更合适

CapQ 的本质是「**一个键盘钩子 + 一个剪贴板读写 + 一个 HTTP 调用 + 一个通知**」。这四件事里，前三件在 AHK 里是**内建语法**，在 Rust 里要引库+自研。

| 你担心的点 | Rust 情况 | AHK v2 情况 |
| --- | --- | --- |
| CapsLock 当修饰键 | 无库可依，自研 200–300 行低层钩子 | `CapsLock & a::` **一行** |
| 剪贴板被占用要重试 | 自研退避重试 | `#ClipboardTimeout 5000` **一行** |
| Win11 Toast | 要注册 AUMID + 引 winrt 库 | `TrayTip(...)` **一行，Win10+ 自动是原生 toast** |
| 单实例 | 自研 40 行互斥体 | `#SingleInstance Force` **一行** |
| 托盘图标+菜单 | 引 `tray-icon` + 自建消息循环 | `A_TrayMenu` **内建** |
| 面板窗口 | `eframe` 引一大堆依赖 | `Gui()` + `ListView` **内建** |
| 编译产物 | 10MB、无杀软误报 | 1MB、**有误报风险** |
| 开发总量 | 约 1600–2000 行 | **约 450–650 行** |

**结论：MVP / 自用 / 快速迭代 → AHK v2 完胜。** 唯一真正的短板是 HTTP 与 JSON（见 §5.2），而两者都有干净的解法。

---

## 1. 四级设计树

> 这层与语言无关，保持不变。每个模块的 AHK 落地方式见 §5.1 映射表。

```
CapQ
├── 热键系统
│   ├── 全局热键功能
│   │   ├── 按键捕获模块
│   │   │   ├── API: startHotkeyListener()
│   │   │   ├── API: registerHotkey(id, 组合键)
│   │   │   ├── API: unregisterHotkey(id)
│   │   │   └── API: onHotkeyEvent(callback)
│   │   ├── 组合键匹配模块
│   │   │   ├── API: matchChord(键位状态) -> 动作
│   │   │   ├── API: isCapsLockHeld() -> bool
│   │   │   └── API: suppressCapsLockToggle()   // SetCapsLockState "AlwaysOff"
│   ├── 动作分发功能
│   │   ├── 动作路由模块
│   │   │   ├── API: dispatchAction(A|QUICK_ASK, H|ASK_WITH_HISTORY, O|OPEN_PANEL)
│   │   │   ├── API: bindAction(组合键, 动作枚举)
│   │   │   └── API: debounce(键码, 毫秒)        // 防止长按连发
│   ├── 热键生命周期功能
│   │   ├── 启停模块
│   │   │   ├── API: enableHotkeys() / disableHotkeys()   // Suspend / Pause
│   │   │   └── API: reloadHotkeys(配置)
├── 剪贴板系统
│   ├── 读取功能
│   │   ├── 文本读取模块
│   │   │   ├── API: readClipboardText() -> String      // A_Clipboard
│   │   │   ├── API: hasTextFormat() -> bool
│   │   │   └── API: normalizeText(文本)                 // Trim + 限长
│   │   ├── 快照模块
│   │   │   ├── API: snapshotClipboard() -> 快照         // ClipboardAll()
│   │   │   └── API: waitClipboardSettled(序列号, 超时)  // #ClipboardTimeout 内建
│   ├── 写入功能
│   │   ├── 文本写入模块
│   │   │   ├── API: writeClipboardText(文本)            // A_Clipboard := text
│   │   │   ├── API: writeWithRetry(文本, 重试次数)      // 同上，由 #ClipboardTimeout 兜底
│   │   │   └── API: restoreClipboard(快照)
│   ├── 变更监听功能
│   │   ├── 监听模块
│   │   │   ├── API: watchClipboard(callback)           // OnClipboardChange
│   │   │   └── API: stopWatchClipboard()
├── AI 请求系统
│   ├── 无历史问答功能            // CapsLock + A，单轮、无状态
│   │   ├── 单轮请求模块
│   │   │   ├── API: askOnce(问题文本, 参数) -> 回答
│   │   │   ├── API: buildStatelessPayload(问题, 系统提示词)
│   │   │   └── API: spawnAskOnce(问题) -> 任务句柄      // curl 子进程
│   ├── 带历史问答功能            // CapsLock + H，维护 messages 数组
│   │   ├── 会话管理模块
│   │   │   ├── API: getOrCreateSession(会话ID)
│   │   │   ├── API: appendMessage(会话ID, role, content)
│   │   │   ├── API: getMessages(会话ID, 条数上限) -> Array
│   │   │   └── API: clearSession(会话ID)
│   │   ├── 上下文裁剪模块
│   │   │   ├── API: trimMessages(messages, token预算)
│   │   │   └── API: selectSessionForAsk(模式) -> 会话ID
│   ├── HTTP 通信功能
│   │   ├── 传输模块
│   │   │   ├── API: postChatCompletion(payload) -> Response   // curl.exe 异步
│   │   │   ├── API: streamChatCompletion(payload, onDelta)
│   │   │   └── API: setTimeout(连接超时, 读取超时)             // --max-time
│   │   ├── 重试与取消模块
│   │   │   ├── API: retryWithBackoff(请求, 最大次数)
│   │   │   ├── API: cancelRequest(请求ID)                    // ProcessClose
│   │   │   └── API: isInflight(请求ID) -> bool
│   │   ├── 响应解析模块
│   │   │   ├── API: parseAnswer(响应体) -> 文本
│   │   │   ├── API: parseError(响应体) -> 错误信息
│   │   │   └── API: stripMarkdown(文本)          // 写剪贴板时可选
├── 通知系统
│   ├── Toast 通知功能
│   │   ├── 通知构建模块
│   │   │   ├── API: showToast(标题, 正文, 图标)        // TrayTip
│   │   │   ├── API: showSuccessToast(摘要) / showErrorToast(错误)
│   │   │   └── API: toastWithAction(按钮, 回调)        // TrayTip 无按钮 → 降级托盘菜单
│   │   ├── 注册与降级模块
│   │   │   ├── API: ensureToastRegistered(AppUserModelID)  // AHK 不需要！
│   │   │   └── API: fallbackNotify(文本)
├── 历史问答系统                  // query_history
│   ├── 记录功能
│   │   ├── 写入模块
│   │   │   ├── API: addHistoryEntry(条目)
│   │   │   ├── API: markEntryStatus(条目ID, pending|success|failed)
│   │   │   └── API: upsertEntry(条目)
│   ├── 查询功能
│   │   ├── 检索模块
│   │   │   ├── API: listHistory(分页, 排序)
│   │   │   ├── API: searchHistory(关键词, 模式/时间过滤)
│   │   │   ├── API: getHistoryEntry(条目ID)
│   │   │   └── API: getHistoryStats(时间范围)
│   ├── 维护功能
│   │   ├── 清理与导出模块
│   │   │   ├── API: deleteEntry(条目ID) / deleteAll()
│   │   │   ├── API: exportHistory(格式, 路径)
│   │   │   └── API: pruneHistory(保留天数, 条数)
│   │   ├── 持久化模块
│   │   │   ├── API: initStore(路径) / migrateSchema(版本)
│   │   │   └── API: backupStore(路径)
├── 面板系统
│   ├── 历史条目面板功能          // CapsLock + O
│   │   ├── 面板窗口模块
│   │   │   ├── API: toggleHistoryPanel() / showPanel() / hidePanel()
│   │   │   ├── API: focusPanel()
│   │   │   └── API: setPanelFilter(模式, 时间, 关键词)
│   │   ├── 列表渲染模块
│   │   │   ├── API: loadPanelPage(页码)
│   │   │   ├── API: onPanelItemClick(条目ID) -> 打开编辑面板
│   │   │   └── API: copyEntryToClipboard(条目ID)
│   ├── 编辑面板功能
│   │   ├── 编辑模块
│   │   │   ├── API: openEditor(条目ID)
│   │   │   ├── API: updateEntry(条目ID, 字段变更)
│   │   │   ├── API: saveAndCloseEditor()
│   │   │   └── API: reAskFromEditor(条目ID)
│   │   ├── 窗口交互模块
│   │   │   ├── API: closeOnEscOrBlur()
│   │   │   └── API: openUrlInItem(链接)
├── 配置系统
│   ├── 配置读取功能
│   │   ├── 加载与校验模块
│   │   │   ├── API: loadConfig() -> Config            // IniRead
│   │   │   ├── API: validateConfig(Config) -> Array
│   │   │   └── API: watchConfig(callback)             // 重启生效（AHK 无文件监听内建）
│   ├── 凭据管理功能
│   │   ├── 密钥存储模块
│   │   │   ├── API: setApiKey(provider, key)          // DPAPI DllCall 或 ini 明文
│   │   │   ├── API: getApiKey(provider) -> String
│   │   │   └── API: setModel(provider, 模型名, 温度, 最大token)
├── 运行时系统
│   ├── 托盘与单实例功能
│   │   ├── 托盘模块
│   │   │   ├── API: initTray(菜单项)                  // A_TrayMenu
│   │   │   └── API: onTrayMenu(菜单ID, callback)
│   │   ├── 单实例模块
│   │   │   ├── API: ensureSingleInstance() -> bool    // #SingleInstance Force
│   │   │   └── API: activateExistingInstance()
│   ├── 生命周期功能
│   │   ├── 启动与退出模块
│   │   │   ├── API: bootstrap()
│   │   │   ├── API: setAutostart(bool)                // 启动文件夹快捷方式
│   │   │   └── API: shutdown()
│   │   ├── 日志与错误模块
│   │   │   ├── API: initLogger(级别, 目录)
│   │   │   └── API: reportError(错误, 上下文)
```

---

## 2. 三条关键链路

### 2.1 A 无历史（CapsLock + A）

```
CapsLock & a::                    ← AHK 热键，一行注册
  → QuickAsk()
  → txt := Trim(A_Clipboard)      ← 内建读取，#ClipboardTimeout 自动重试
  → payload := 单条 user message   ← 硬约束：不含任何历史
  → Curl.Post(payload, callback)   ← 异步子进程，不阻塞
  → callback: parseAnswer()
  → A_Clipboard := answer
  → TrayTip(answer, "CapQ")
  → History.Add(mode="quick", session_id="")
```

**硬约束不变**：此链路不得读取、不得写入 `messages` 数组，也不得创建会话。

### 2.2 H 带历史（CapsLock + H）

```
CapsLock & h::
  → AskWithHistory()
  → sid := Sessions.Active
  → msgs := Sessions.Get(sid)      ← Array of Map
  → msgs := Trim(msgs, token预算)
  → msgs.Push(Map("role","user","content",txt))
  → Curl.Post(payload, callback)
  → callback: msgs.Push(Map("role","assistant","content",ans))
  → A_Clipboard := ans ; TrayTip ; History.Add(mode="chat")
```

### 2.3 O 面板（CapsLock + O）

```
CapsLock & o::
  → ToggleHistoryPanel()
  → ListView 填充（内存数组过滤）
  → 双击条目 → OpenEditor(id)
  → 保存 → History.Update(id, 字段)
  → 重问 → 复用 question 走 A 链路
```

---

## 3. 关键设计要点（AHK 版，共 7 条）

### 3.1 CapsLock 必须「吞掉翻转」——两件事一起做

AHK 文档明确：自定义组合键（`X & Y`）中，**前缀键会失去原生功能，除非它是标准修饰键或像 CapsLock 这样的可切换键**。CapsLock 正好是「可切换键」→ 它**保留原生功能**，按下会翻转大写锁定。

所以必须双保险：

```ahk
SetCapsLockState "AlwaysOff"   ; 强制永久关闭（会自动安装键盘钩子）
CapsLock::return               ; 单按 CapsLock 什么也不做
CapsLock & a::QuickAsk()       ; 此时 CapsLock 已是纯前缀键
```

只写 `CapsLock & a::` 而不关状态 → 每次都会把大写锁定弄乱，这是最常见翻车点。

### 3.2 🔴 别在热键线程里同步发 HTTP

AHK 是**伪多线程**：一个线程阻塞时，消息泵被占住，后续热键/timer 都会卡。同步 COM（`WinHttp.WinHttpRequest`）会让整个程序在等 API 时「假死 3–30 秒」。

**采用 curl 子进程 + SetTimer 轮询**，天然异步、可取消：

```ahk
pid := Run(cmd, , "Hide")                      ; 立即返回
SetTimer(CheckDone.Bind(pid, resFile, cb), 100) ; 轮询不阻塞
; 取消：ProcessClose(pid)
```

### 3.3 剪贴板竞态：AHK 原生就解决了

Rust 要自己 `GetClipboardSequenceNumber` 轮询等待，AHK 只要：

```ahk
#ClipboardTimeout 5000   ; 被占用时自动重试 5 秒（默认仅 1000ms）
```

这一行同时解决「刚 Ctrl+C 就按热键」和「写回时目标程序占着剪贴板」两个问题。

### 3.4 Toast：TrayTip 就是 Win11 原生 toast

文档原文：**Windows 10 及以后会把所有气泡通知替换为 toast 通知**，且「靠近托盘图标显示」。

```ahk
TrayTip text, title, "Iconi Mute"   ; 正文≤255字符，标题≤63字符，必须截断
```

约束与坑：
- **必须有托盘图标**（用了 `#NoTrayIcon` 或 `A_IconHidden := true` 就完全无效）；
- 组策略把 `EnableBalloonTips` 设为 0 时失效 → 仍需 `fallbackNotify`（退化为 ToolTip 或托盘菜单提示）；
- 拿不到「点击通知回调」按钮 → 想要「点通知打开面板」只能在 Rust 版实现，AHK 版放弃这个交互。

### 3.5 历史存储：先用 JSONL，别急着上 SQLite

AHK 调 SQLite 要走 `DllCall("sqlite3.dll")` 的完整封装（约 150–250 行），对个人工具是过度工程。

推荐：
- `history.jsonl`，一行一条，追加写 → 崩溃时最多丢最后一条；
- 启动时全量读入内存 Array，搜索/过滤在内存做（几万条毫无压力）；
- 超过 N 条或 M 天时重写文件做 prune。

**只在需要全文检索、多进程并发、十万级数据时才换 SQLite。**

### 3.6 并发保护：一次只允许一个请求

AHK 伪线程下，用户可能连按两次热键。用一个模块级标志挡住，并在 Toast 上提示「上一个请求还在进行」；或者按 §3.2 的 pid 表允许排队但限制上限 3。

### 3.7 键盘钩子的隐形代价

AHK 装键盘钩子后，**全系统按键都会过一次 AHK 的回调**（约 1–3ms 每键）。正常打字无感，但：
- 部分反作弊游戏会拒绝/踢出带全局钩子的进程；
- 部分安全软件会提示「正在记录键盘输入」；
- 极端情况下钩子被系统摘掉 → 热键静默失灵，需要「重载脚本」托盘菜单项兜底。

---

## 4. 数据结构

### 4.1 单条历史（JSONL 一行）

```json
{"id":"1730...-a1b2","mode":"quick","sid":"","q":"原文","a":"回答",
 "status":"success","err":"","model":"deepseek-chat",
 "tin":12,"tout":340,"ms":1840,"ts":1730000000000}
```

| 字段 | 说明 |
| --- | --- |
| `mode` | `quick`（A）/ `chat`（H） |
| `sid` | 仅 `chat` 有值，指向会话 |
| `status` | `pending` / `success` / `failed` / `canceled` |
| `err` | 失败分类：`timeout` / `rate_limit` / `auth` / `network` / `server` |
| `ms` | 端到端耗时，面板里用来排序找「哪个模型快」 |

### 4.2 会话（`sessions.json`）

```json
{"active":"s1","sessions":{"s1":{"name":"默认","msgs":[
  {"role":"user","content":"..."},{"role":"assistant","content":"..."}]}}}
```

裁剪策略：保留首条 system + 最近 N 轮，超出按 token 粗估（中文 1 字≈1 token，英文 4 字符≈1 token）。

### 4.3 配置（`config.ini`，用内建 IniRead/IniWrite）

```ini
[api]
base=https://api.deepseek.com
path=/chat/completions
model=deepseek-chat
key=sk-xxx
temperature=0.3
maxtok=2048

[ui]
toast=1
pasteback=1
trimmarkdown=0

[hotkey]
quick=CapsLock & a
history=CapsLock & h
panel=CapsLock & o
```

> 密钥安全：`key=` 明文存用户目录下的 ini 属权宜之计。要更稳可用 `DllCall("CryptProtectData")` 走 DPAPI（约 40 行），或干脆每次启动问一次、只存内存。

---

## 5. 能力映射：内建 vs 自研 vs Rust 对照

### 5.1 一张表看完所有模块

| 模块 | AHK v2 落地方式 | 工作量 |
| --- | --- | --- |
| 全局热键 | `CapsLock & a::` | 1 行 |
| CapsLock 吞键 | `SetCapsLockState "AlwaysOff"` + `CapsLock::return` | 2 行 |
| debounce | `A_TickCount` 差值判断 | 4 行 |
| 读剪贴板 | `A_Clipboard` | 1 行 |
| 剪贴板重试 | `#ClipboardTimeout 5000` | 1 行 |
| 写剪贴板 | `A_Clipboard := ans` | 1 行 |
| 剪贴板快照 | `ClipboardAll()` | 2 行 |
| 变更监听 | `OnClipboardChange` | 3 行 |
| HTTP | `curl.exe` 子进程 + `Run` | ~60 行 |
| JSON | **需引第三方 include**（cJson / JSON.ahk） | 0 行（vendored） |
| A/H 分流 | `Map` + `Array` 手搓 payload | ~40 行 |
| 上下文裁剪 | Array 切片 + 字数估算 | ~30 行 |
| Toast | `TrayTip` | 1 行 |
| 历史存储 | JSONL 文件 + 内存 Array | ~80 行 |
| 搜索过滤 | `InStr()` 内存过滤 | ~20 行 |
| 面板窗口 | `Gui()` + `ListView` | ~120 行 |
| 编辑窗口 | `Gui()` + `Edit` 控件 | ~80 行 |
| 配置 | `IniRead` / `IniWrite` | ~20 行 |
| 托盘菜单 | `A_TrayMenu` | ~15 行 |
| 单实例 | `#SingleInstance Force` | 1 行 |
| 开机自启 | 启动文件夹放 `.lnk` | ~10 行 |
| 日志 | `FileAppend` + `OutputDebug` | ~15 行 |
| **合计** | | **约 450–650 行** |

对比 Rust 方案 §5.6 的 1600–2000 行，**代码量降到约 1/3**。

### 5.2 两个必须认清的短板

#### ① 没有内建 HTTP —— 用 curl.exe 绕过

`C:\Windows\System32\curl.exe` 在 Win10 1803+ 就自带了，本机已确认存在。要点：

```ahk
; payload 写临时文件，用 --data-binary "@file" 避免任何引号转义地狱
cmd := A_ComSpec ' /c "" ' A_WinDir '\System32\curl.exe" -s -S --max-time 120'
     . ' -o "' resFile '" -w "%{http_code}" > "' codeFile '"'
     . ' -H "Content-Type: application/json"'
     . ' -H "Authorization: Bearer ' key '"'
     . ' --data-binary "@' reqFile '" "' url '"'
pid := Run(cmd, , "Hide")
```

- `-w "%{http_code}"` 拿状态码，判断 200/401/429/5xx；
- `--max-time 120` 是超时；
- `ProcessClose(pid)` 是取消；
- 全程不阻塞，主线程继续响应热键。

> 备选：`ComObject("WinHttp.WinHttpRequest.5.1")` 同步调用 —— **不要用**，会卡死消息泵（见 §3.2）。

#### ② 没有内建 JSON —— 必须 vendor 一个库

AHK v2 不解析 JSON。三条路：

| 方案 | 说明 |
| --- | --- |
| **vendor `cJson.ahk`**（G33kDude） | 约 300 行，`cJson.Dump(obj)` / `cJson.Load(str)`，最常用，**推荐** |
| vendor `JSON.ahk`（thqby） | 性能更好，API 略不同 |
| 手写拼 JSON + 正则抠 content | 请求侧可行（约 15 行转义），响应侧**会因转义引号/换行翻车**，不推荐 |

结论：**老老实实 vendor 一个**，这是 AHK 方案唯一必须引入的外部文件。

### 5.3 Rust vs AHK 决策矩阵

| 维度 | AHK v2 | Rust |
| --- | --- | --- |
| 代码量 | 450–650 行 | 1600–2000 行 |
| 首版到手时间 | **1–2 天** | 1–2 周 |
| 启动速度 | ~50ms（解释执行） | ~5ms |
| 产物大小 | ~1MB（Ahk2Exe 编译） | ~10MB |
| **杀软误报** | ⚠️ **高频，编译版尤甚** | ✅ 几乎没有 |
| 类型安全 | ❌ 动态类型，重构靠人 | ✅ 编译期兜底 |
| 单元测试 | ❌ 基本没有生态 | ✅ `cargo test` |
| UI 观感 | 原生控件，朴素 | `eframe` 可控、好看 |
| 流式输出 | 麻烦（要轮询落盘文件） | 原生支持 |
| 通知按钮/点击回调 | ❌ 拿不到 | ✅ WinRT 可做 |
| 跨平台 | ❌ 仅 Windows | ✅ |
| 环境依赖 | 需装 AHK 或编译成 exe | 无（静态链接） |
| 调试体验 | `MsgBox` / `OutputDebug` 原始 | `rust-gdb` / `dbg!` |

---

## 6. 代码骨架（可直接起步）

```ahk
#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
SetCapsLockState "AlwaysOff"
#ClipboardTimeout 5000
SendMode "Input"

#Include cJson.ahk

global CFG      := LoadConfig()
global HIST     := HistoryStore()
global SESS     := SessionStore()
global BUSY     := false

; ── 热键 ──────────────────────────────────────────────
CapsLock::return
CapsLock & a::AskQuick()
CapsLock & h::AskWithHistory()
CapsLock & o::TogglePanel()

AskQuick() {
    global BUSY
    static last := 0
    if (A_TickCount - last < 300)                    ; debounce
        return
    last := A_TickCount
    if BUSY
        return Notify("上一个请求还在进行中", "CapQ", "Icon!")
    txt := Normalize(A_Clipboard)
    if (txt = "")
        return Notify("剪贴板为空", "CapQ", "Icon!")
    BUSY := true
    payload := Map(
        "model", CFG.model,
        "messages", [Map("role", "user", "content", txt)],
        "temperature", CFG.temperature,
        "max_tokens", CFG.maxtok)
    reqId := Hist.Add("quick", "", txt)              ; 先落 pending
    Http.Post(payload, Done.Bind(reqId, txt, A_TickCount))
}

Done(reqId, question, t0, ok, body, httpCode) {
    global BUSY
    BUSY := false
    if !ok
        return Hist.Fail(reqId, "network"), Notify("请求失败：" body, "CapQ", "Iconx")
    ans := Json(path(body, "choices.1.message.content"))
    A_Clipboard := ans
    Hist.Success(reqId, ans, path(body, "usage.total_tokens"), A_TickCount - t0)
    Notify(SubStr(ans, 1, 250), "CapQ 已复制", "Iconi Mute")
}

Notify(text, title := "CapQ", icon := "Iconi Mute") {
    TrayTip SubStr(text, 1, 250), SubStr(title, 1, 60), icon
}
```

```ahk
; ── Http.ahk（异步 curl 封装）─────────────────────────
Class Http {
    static pending := Map()

    static Post(payload, cb) {
        id  := A_TickCount "_" Random(1000, 9999)
        dir := A_Temp "\CapQ\"
        DirCreate dir
        req := dir id ".req", res := dir id ".res", code := dir id ".code"
        FileOpen(req, "w", "UTF-8").Write(cJson.Dump(payload)).Close()

        url := CFG.base CFG.path
        cmd := A_ComSpec ' /c ""' A_WinDir '\System32\curl.exe"'
             . ' -s -S --max-time ' CFG.timeout
             . ' -o "' res '" -w "%{http_code}" > "' code '"'
             . ' -H "Content-Type: application/json"'
             . ' -H "Authorization: Bearer ' CFG.key '"'
             . ' --data-binary "@' req '" "' url '"'
        pid := Run(cmd, , "Hide")
        Http.pending[id] := {pid: pid, res: res, code: code, cb: cb}
        SetTimer(Http.CheckLate.Bind(id), 120)
    }

    static CheckLate(id) {
        p := Http.pending[id]
        if ProcessExist(p.pid)
            return
        SetTimer(, -1), Http.pending.Delete(id)
        ok := false, body := "", code := ""
        try {
            code := Trim(FileRead(p.code))
            body := FileRead(p.res, "UTF-8")
            ok   := (code = "200")
        }
        FileDelete(p.req), FileDelete(p.res), FileDelete(p.code)
        p.cb.Call(ok, body, code)
    }
}
```

**关键点**：`Run` 立即返回 pid → `SetTimer` 轮询 `ProcessExist` → 期间主线程完全响应热键。这就是 AHK 版异步的正确姿势。

---

## 7. 目录结构

```
CapQ/
├── CapQ.ahk              # 启动 + 热键绑定 + bootstrap
├── lib/
│   ├── cJson.ahk         # vendored JSON（唯一外部依赖）
│   ├── Http.ahk          # curl 异步封装
│   ├── Clipboard.ahk     # 读写 + 快照 + 归一化
│   ├── Ai.ahk            # A/H 分流、payload、裁剪、错误映射
│   ├── History.ahk       # JSONL 存储 + 搜索 + prune
│   ├── Session.ahk       # messages 数组管理
│   ├── Panel.ahk         # 历史面板 + 编辑面板
│   ├── Notify.ahk        # TrayTip + 降级
│   ├── Config.ahk        # ini 读写 + 校验
│   └── Log.ahk           # 文件日志
├── config.ini
└── docs/designs/
```

---

## 8. 实施顺序（每步都可独立验收）

| 步骤 | 内容 | 验收标准 |
| --- | --- | --- |
| 1 | `CapsLock+A` 触发 → 读剪贴板 → 假回答写回 → Toast | 大写锁定不翻转，能弹提醒 |
| 2 | 接 curl + 真 API，A 链路跑通 | 真实回答进剪贴板 |
| 3 | `history.jsonl` 落库（含 pending/failed） | 失败也留痕 |
| 4 | `CapsLock+H` 会话上下文 | 能追问「上面那句再简洁点」 |
| 5 | `CapsLock+O` 面板 + 编辑 | 能改、能复制、能重问 |
| 6 | 托盘菜单、单实例、开机自启、prune | 日常可用 |
| 7 | Ahk2Exe 编译（先不签名，观察误报） | 双击可跑 |

---

## 9. 风险与「何时该换回 Rust」

### 必须接受的三个风险

1. **杀软误报**——AHK 编译产物被 Defender/360 报毒是长期顽疾，尤其「带键盘钩子的 AHK exe」几乎是最典型的误报特征。缓解：加白名单说明、不编译直接用 `.ahk`、或做代码签名（EV 证书才有效）。
2. **键盘钩子的全局开销与冲突**——见 §3.7。
3. **无类型、无测试**——超过 1500 行后改动会开始心虚。

### 触发「换回 Rust」的信号（任一出现就该重写）

- 需要**发布给他人使用**，且无法说服用户加白名单 / 无法取得签名证书；
- 需要**流式输出**（边生成边入剪贴板）或**通知上的交互按钮**；
- 需要**跨平台**（macOS / Linux）；
- 代码突破 **1500 行**，且要多人协作；
- 需要**严格测试**（回归测试套件）。

### 渐进迁移路径（推荐）

不改架构、只换实现，因为 §1 的四级树和 §2 的三条链路是语言无关的：

```
阶段 1（现在）：AHK 全量 → 验证交互手感、快捷键是否符合直觉
阶段 2：把 Http + Ai 抽成独立 helper（Rust 或 PowerShell），AHK 只做 UI/热键
阶段 3：UI 用 eframe 重做，AHK 退场 → 完整的 Rust 版
```

这样每个阶段都能独立发布，且**设计文档一行都不用改**。

---

## 10. 实战踩坑记录（实现阶段验证出的 7 个真 bug）

这些都是**写代码时才暴露、设计阶段无法预见**的问题。全部已修复，记录在此避免重犯。

### 10.1 `base` 是保留字，不能做类属性名

```ahk
class Config {
    static base := "https://api.deepseek.com"   ; ✗ 直接报错
}
```

`base` 是 AHK 内置的对象基类引用，用作类成员名会触发 **load-time 错误**。表现极具迷惑性：进程活着、没有窗口、`/validate` 查不出来、看起来像"卡死"。

**修复**：改名 `apiBase`。**教训**：load-time 错误 `/validate` 未必能查出来，不能只依赖它。

### 10.2 `SetTimer` 不接受 `.Bind()` 的结果

```ahk
timer := Http.Check.Bind(id)
SetTimer timer, 120          ; ✗ 静默失效，定时器根本不触发
```

`.Bind()` 返回 BoundFunc，`SetTimer` 对它的处理会**丢参数**，报 `Missing a required parameter: id`。

**修复**：`SetTimer ObjBindMethod(Http, "Check", id), 120`。

### 10.3 static 方法用 `.Bind()` 会丢失 `this`

```ahk
Http.Post(payload, this.OnQuickDone.Bind(id, t0))   ; ✗ this 丢失
```

回调进入后 `this` 不再是类本身，`this.HandleFail(id, errKind, code)` 参数整体错位，报 `Missing a required parameter: errKind`。

**修复**：一律 `ObjBindMethod(Ai, "OnQuickDone", id, t0)`。**规则**：AHK 里给 static 方法做回调绑定，只用 `ObjBindMethod`。

### 10.4 cmd 的 `>` 重定向会吞掉后续所有参数

```ahk
cmd := A_ComSpec ' /c curl.exe ... -o res -w "%{http_code}" > code.txt -H "..." '
```
`> code.txt` 之后的内容全被当作重定向目标的一部分，curl 只收到半截命令。而且经 `cmd /c` 调用时 `Run()` 拿到的 **pid 是空字符串**。

**修复**：直接 `Run('"C:\Windows\System32\curl.exe" ...')`，不用 cmd；状态码改用 `-D hdrFile` 写响应头，再用正则 `HTTP/\d[\d.]*\s+(\d{3})` 解析。**连带收益**：不再依赖 pid，`Run()` 返回空 pid 时降级为"看响应头文件是否落盘"来判断完成。

### 10.5 `JSON.stringify` 默认输出多行，会毁掉 JSONL

```ahk
f.Write(JSON.stringify(rec) "`n")      ; ✗ 多行，JSONL 被切碎
```

默认是 pretty-print 多行输出，逐行读回时**每一行都解析失败**，表现为"历史写进去了但读不出来、Delete 永远返回 0"。

**修复**：`JSON.stringify(rec, 0)`（第 2 参数 0 = 紧凑单行）。

### 10.6 原生 `false` 被序列化成 `0`，请求体非法

```ahk
"stream", false     ; ✗ 实际发出 {"stream":0}
```

本 JSON 库只认 `JSON.true` / `JSON.false`（ComValue 类型）才输出 `true`/`false`；AHK 原生布尔会被当作数字输出 `0`。对类型敏感的 API 直接返回：

```
400 invalid_request_error: invalid field type or conflicting parameters
```

**修复**：`"stream", JSON.false`。**注意**：这个报错信息完全不提哪个字段错了，只能靠 dump 请求体才发现。

### 10.7 UTF-8 带 BOM 的连锁伤害

`FileOpen(path, "w", "UTF-8")` 和 `FileAppend txt, path, "UTF-8"` 都会**写 BOM**。三个后果：

1. **config.ini**：`IniRead` 把首段读成 `"\uFEFFapi"`，`[api]` 段永远取不到值 → key 读成空 → 报"api.key 未设置"。
2. **请求体**：带 BOM 的 JSON 被服务端判为非法。
3. **JSONL**：首行解析失败。

**修复**：所有数据文件一律 `"UTF-8-RAW"`（写不写 BOM、读不吃 BOM）。`Config.StripBom()` 额外兜底：检测到用户手工创建的文件带 BOM 时自动转为无 BOM。

### 10.8 剪贴板是独占资源，必须重试

剪贴板管理器（本机是 **Ditto**）会持续占用剪贴板，导致：

```
Can't open clipboard for writing.
```

且写入"看似成功、读回却是空"。这不是 bug 而是**真实使用环境**，代码必须容忍。

**修复**：`Clip.Write(txt, retries := 8)` 循环重试（每次间隔 80ms）；`Ai.Finish` 在最终写入失败时不静默，而是提示"回答已生成，但写剪贴板失败，去面板里复制"——回答已入历史，不会丢。

### 10.9 顶层不能写 `global X := ...`

`global` 声明只能在函数体内使用。顶层作用域本来就是全局的，写 `global GPID := Run(...)` 会触发 load-time 错误（同样是"进程活着但什么都不做"）。

**修复**：顶层直接 `GPID := Run(...)`。

### 10.10 热键会连发，每个入口都必须防抖

`CapsLock & k` 这类组合热键在**按住不放时会被系统反复触发**（每 30ms 左右一次）。没有防抖时表现为：

- 连开十几个浏览器标签页
- 反复抢前台，屏幕疯狂闪烁
- `CapsLock+O` 会把面板开开关关，闪成一片

这不是"某个键的 bug"，而是**所有热键入口的共性问题**。

**修复**：按语义选两道闸门。

```ahk
; 动作型（打开链接）：同一个目标 + 时间窗口内只执行一次
static lastUrl   := ""
static lastUrlAt := 0
static sameUrlMs := 1500

now := A_TickCount
if (this.lastUrl != "" && u = this.lastUrl && now - this.lastUrlAt < this.sameUrlMs)
    return false
```

```ahk
; 开关型（面板 Toggle）：纯时间窗口，350ms
static lastToggle := 0
now := A_TickCount
if (this.lastToggle && now - this.lastToggle < 350)
    return
this.lastToggle := now
```

**关键取舍**：时间窗口**只对同一个目标生效**，不要写成"全局窗口内一律不执行"。否则用户换个链接立刻按 `CapsLock+K` 会被吞掉，感觉是"按键失灵"——这比连发更难排查，因为它是静默失败。

### 10.11 调试脚本不要用 `Stop-Process AutoHotkey*`

排查时图省事写 `Get-Process AutoHotkey* | Stop-Process -Force`，会把**用户正在用的 CapQ 实例一起杀掉**。症状就是"按快捷键没反应"，而实际上是自己的调试命令干的。

更糟的是如果同时有后台循环脚本在跑（本机就有一个别的项目目录在做 6 轮重试测试，每轮都先杀光 AHK 再启动），两边互相踩，会表现为"错误弹窗疯狂闪、杀不干净"。

**规则**：
- 精确定位 pid 再杀，或按命令行过滤
- 自己起的进程用 `Run()` 返回的 pid 关，不要用通配
- 遇到"杀不完的弹窗"，查 `Win32_Process` 的 `ParentProcessId` 往上追，找到拉起它的循环脚本

### 教训汇总

| 现象 | 排查手法 |
| --- | --- |
| 进程活着但不干活、无窗口 | 90% 是 load-time 错误。`/validate` 不可靠，改用 `OnError` 捕获 `e.File` / `e.Line` |
| 回调报"缺参数" | 检查是否用了 `.Bind()`，换 `ObjBindMethod` |
| 定时器不触发 | 同上 |
| 网络明明通却报 network | dump 实际命令行 + 实际请求体字节 |
| 配置读了等于没读 | 查 BOM |
| 窗口疯狂闪烁、标签页连开 | 热键连发，入口缺防抖 |
| 快捷键"没反应" | 先确认进程还在——别是自己的调试命令 `Stop-Process` 杀的 |
| 弹窗杀不完 | 往上追 `ParentProcessId`，找拉起它的循环脚本 |

**最重要的排查基建**：所有错误只写日志、绝不弹窗（`OnError` 返回 `1`）；测试脚本一律 `/ErrorStdOut` + 进度写文件，因为进程被 kill 时 stdout 缓冲会丢。
