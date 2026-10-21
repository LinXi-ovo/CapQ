#Requires AutoHotkey v2.0
#ErrorStdOut
; A 链路端到端：用文件传问题，验证 Ai.OnQuickDone 的完整收尾
SetWorkingDir A_ScriptDir
#Include ..\lib\Log.ahk
#Include ..\lib\Config.ahk
#Include ..\lib\JSON.ahk
#Include ..\lib\Clipboard.ahk
#Include ..\lib\Notify.ahk
#Include ..\lib\Http.ahk
#Include ..\lib\History.ahk
#Include ..\lib\Session.ahk
#Include ..\lib\Ai.ahk

OUT := A_Temp "\e2e2.txt"
try FileDelete OUT

P(l) {
    global OUT
    f := FileOpen(OUT, "a", "UTF-8-RAW")
    f.Write(l "`n")
    f.Close()
}

MyErr(e, mode) {
    P("!! ERR line=" e.Line " msg=" e.Message " extra=" e.Extra)
    return 1
}
OnError(MyErr)

errs := Config.Load(A_ScriptDir "\..\config.ini")
Config.dataDir := A_ScriptDir "\..\data"
DirCreate Config.dataDir
Log.Init(Config.dataDir)
History.Init(Config.dataDir)
Session.Init(Config.dataDir)
Notify.toast := 0

P("配置: " Config.model " @" Config.apiBase)
P("开始历史条数=" History.Stats()["total"])

; 直接走 Http + Ai 的回调，绕过剪贴板读取
q := "用一句话解释什么是递归"
id := History.Add("quick", "", q)
P("本地登记 id=" id)

payload := Map(
    "model",       Config.model,
    "messages",    [Map("role", "user", "content", q)],
    "temperature", 0.3,
    "max_tokens",  256,
    "stream",      JSON.false)

Ai.busy := true
t0 := A_TickCount
Http.Post(payload, ObjBindMethod(Ai, "OnQuickDone", id, t0))
P("已发出 inflight=" Http.InflightCount())

Wait() {
    static n := 0
    global OUT
    n += 1
    if (Ai.busy) {
        if (n > 120) {
            P("!! 超时")
            ExitApp 1
        }
        return
    }
    P("完成,轮询 " n " 次")
    P("=== 剪贴板 ===")
    P("[" A_Clipboard "]")
    P("=== 历史记录 ===")
    r := History.Get(id)
    if IsObject(r) {
        P("status=" r["status"] " tokens=" r["tokens"] " ms=" r["ms"])
        P("q=" r["q"])
        P("a=" SubStr(r["a"], 1, 300))
        if (r["err"] != "")
            P("err=" r["err"])
    } else {
        P("<查不到该 id>")
    }
    P("=== E2E2_DONE ===")
    ExitApp 0
}
SetTimer Wait, 500
