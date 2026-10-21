# CapQ

Copy text → press `CapsLock + A` → get the AI answer back in your clipboard.

AutoHotkey v2 clipboard AI assistant for Windows 11. Three hotkeys, no window, no
chat UI — the answer lands where you can paste it immediately.

## 快捷键

| 快捷键 | 行为 |
| --- | --- |
| `CapsLock + A` | 问当前剪贴板内容。**不带**对话历史，每次都是全新单轮 |
| `CapsLock + H` | 同上，但**带** `messages` 上下文，可以连续追问 |
| `CapsLock + O` | 打开历史面板，可查看 / 复制 / 编辑 / 删除 / 导出 |

所有问答都会自动记入历史面板。

## 三条链路的关键区别

`A` 和 `H` 的区别不是"记不记录历史"——两者**都**记录到本地历史面板。
区别在于**是否把上下文发给模型**：

- `A`：payload 里 `messages` 只有一条当前提问，代码路径不读也不写 `Session`。
- `H`：把 `Session` 里的历史消息一起发过去，成功后把本轮问答追加回 `Session`。

所以 `A` 永远不会因为上下文变长而变慢或跑题，适合查单个概念；`H` 适合连续追问。

## 安装

1. 装 [AutoHotkey v2](https://www.autohotkey.com/)（v2.0+，本项目在 v2.0.30 上验证）

2. 设置三个环境变量（推荐，密钥不落盘）：

   ```powershell
   setx myllmurl     "https://api.deepseek.com"
   setx myllmapi     "sk-your-key-here"
   setx myllmmodelid "deepseek-chat"
   ```

   `setx` 写入的是用户级变量，**新开的进程才读得到**（已开的终端/程序需重启）。

3. 双击 `CapQ.ahk`。程序常驻托盘。

也可以不用环境变量，复制 `config.example.ini` 为 `config.ini` 后直接填。
**环境变量优先级高于 config.ini**，同时存在时以环境变量为准。

| 环境变量 | 对应配置 | 说明 |
| --- | --- | --- |
| `myllmurl` | `[api] base` | 接口根地址，尾部斜杠会自动去掉 |
| `myllmapi` | `[api] key` | API Key |
| `myllmmodelid` | `[api] model` | 模型名（也接受 `myllmmodel`） |

## 配置

见 `config.example.ini`，字段都有注释。默认对接 DeepSeek，任何 OpenAI 兼容接口
都能用——改 `base` / `path` / `model` 即可。

## 数据存放

```
data/
  history.jsonl   问答历史，一行一条 JSON
  logs/YYYYMMDD.log
```

`data/` 不纳入版本控制。

## 结构

```
CapQ.ahk            主脚本：热键注册、托盘、启动、全局错误兜底
lib/
  Config.ahk        config.ini 读写与校验
  Clipboard.ahk     剪贴板读写（带重试）、token 估算
  Http.ahk          curl 子进程 + 定时器轮询（不阻塞消息泵）
  JSON.ahk          JSON 序列化（vendored: thqby/ahk2_lib）
  Ai.ahk            A / H 双链路分流、错误映射、Markdown 清理
  Session.ahk       messages 数组管理与上下文裁剪
  History.ahk       本地问答历史（JSONL）
  Panel.ahk         历史面板 + 编辑面板
  Notify.ahk        系统通知与降级
  Log.ahk           按天切分日志
tests/
  smoke.ahk         冒烟测试（Config/Log/Clip/History/Session/Ai/Http）
  json_roundtrip.ahk
  e2e2.ahk          真实接口端到端测试
```

## 为什么不用同步 HTTP

AHK 是伪多线程：同步调用（WinHttp COM）会冻结整个消息泵，热键在等待期间全部失灵。
所以请求走 `Run()` 起 `curl.exe` 子进程，再用 `SetTimer` 轮询完成状态，主线程始终可响应。

## 已知限制

- **通知无法点击**。`TrayTip` 是原生 toast，但不提供点击回调，"点通知打开面板"做不到。
- **不支持流式输出**：必须等完整回答。
- **Key 明文存盘**。后续可用 DPAPI（`CryptProtectData`）加密。
- **杀软误报**。带全局键盘钩子的 AHK 脚本容易被误判，建议直接用 `.ahk` 不编译。
- **剪贴板管理器干扰**。Ditto 等工具会短时独占剪贴板，已内置重试；若仍失败，
  回答已存入历史面板，可去那里复制。

## 测试

冒烟测试不联网、不需要 key：

```powershell
$ahk = "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey64.exe"   # 装到默认位置时
& $ahk tests\smoke.ahk
```

如果 AHK 装在别处（scoop、便携版），把 `$ahk` 换成实际路径即可。

测试脚本都设了 `OnError` 兜底，出错只写日志不弹窗；结果输出在 `%TEMP%` 下的文本文件里，
跑完看控制台或对应文件。`tests\json_roundtrip.ahk` 验证 JSON 序列化往返，
`tests\e2e2.ahk` 需要有效配置才能真实打接口。

## License

MIT
