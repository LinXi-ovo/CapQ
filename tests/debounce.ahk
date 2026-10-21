#Requires AutoHotkey v2.0
#ErrorStdOut
; 验证防抖（双闸门）：用真实连发频率 30ms 测
SetWorkingDir A_ScriptDir
#Include ..\lib\Log.ahk
#Include ..\lib\Config.ahk
#Include ..\lib\Clipboard.ahk
#Include ..\lib\Notify.ahk
#Include ..\lib\Url.ahk

OUT := A_Temp "\db2.txt"
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

tmp := A_Temp "\db2cfg"
DirCreate tmp
Config.Load(tmp "\config.ini")
Config.dataDir := tmp
Config.urlActivate := 0
Log.Init(tmp)
Notify.toast := 0

A_Clipboard := "https://github.com/LinXi-ovo/CapQ"
Sleep 200
P("剪贴板 = [" A_Clipboard "]")
P("")

fail := 0
Chk(cond, label) {
    global fail
    if (cond)
        P("  ok  " label)
    else {
        P("  FAIL " label)
        fail += 1
    }
}

; ── 测试 1：30ms 连发 20 次（模拟真实按住热键）──
P("=== 测试1: 30ms 连发 20 次，期望只执行 1 次 ===")
n1 := 0
Loop 20 {
    if (Url.OpenClipboard())
        n1 += 1
    Sleep 30
}
P("执行次数 = " n1 " / 20  期望 1")
Chk(n1 = 1, "连发只执行一次")

; ── 测试 2：等超过窗口后能再执行（同一 URL 但间隔足够）──
P("")
P("=== 测试2: 等 2100ms 后同一链接应可再开 ===")
Sleep 2100
n2 := Url.OpenClipboard() ? 1 : 0
P("执行 = " n2 "  期望 1")
Chk(n2 = 1, "窗口过后可重开")

; ── 测试 3：换一个链接应立刻能开 ──
P("")
P("=== 测试3: 立刻换新链接，应能打开 ===")
A_Clipboard := "https://example.com/other"
Sleep 100
n3 := Url.OpenClipboard() ? 1 : 0
P("执行 = " n3 "  期望 1")
Chk(n3 = 1, "新链接立即可开")

; ── 测试 4：非链接应被拒绝 ──
P("")
P("=== 测试4: 非链接内容应被拒绝 ===")
A_Clipboard := "README.md"
Sleep 100
n4 := Url.OpenClipboard() ? 1 : 0
P("执行 = " n4 "  期望 0（被拒绝）")
Chk(n4 = 0, "非链接被拒绝")

P("")
P(fail = 0 ? "=== DB2_PASS ===" : "=== DB2_FAIL " fail " 项 ===")
ExitApp (fail = 0 ? 0 : 1)
