#Include F:\Cores\project\inbox-vscode-wk\CapQ\lib\JSON.ahk

obj := Map(
    "model", "deepseek-chat",
    "messages", [Map("role", "user", "content", "你好，测试 `"引号`" 和换行`n第二行")],
    "temperature", 0.3,
    "max_tokens", 2048)

s := JSON.stringify(obj)
FileAppend "STRINGIFY OK:`n" s "`n`n", "*"

back := JSON.parse(s, false, true)
FileAppend "PARSE model=" back["model"] "`n", "*"
FileAppend "PARSE content=" back["messages"][1]["content"] "`n", "*"
FileAppend "PARSE max_tokens=" back["max_tokens"] "`n", "*"

; 空数组 / 空 Map / 中文
s2 := JSON.stringify(Map("a", [], "b", Map(), "c", "中文"))
FileAppend "EDGE=" s2 "`n", "*"

FileAppend "ALL_OK`n", "*"
