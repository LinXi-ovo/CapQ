#Requires AutoHotkey v2.0
#ErrorStdOut
; 冒烟测试：结果写入文件（每步立即落盘，便于定位卡点）。
; 使用独立临时目录，绝不触碰真实 data。

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

OUT := A_Temp "\CapQ_smoke_out.txt"
try FileDelete OUT

P(line) {
    global OUT
    f := FileOpen(OUT, "a", "UTF-8")
    f.Write(line "`n")
    f.Close()
}
Ok(n, extra := "")  => P("ok   " n (extra != "" ? "  " extra : ""))
Bad(n, m)           => P("FAIL " n " :: " m)

tmp := A_Temp "\CapQ_smoke_" A_TickCount
DirCreate tmp
P("== CapQ 冒烟测试开始 tmp=" tmp " ==")

; ── 1. Config ──
P("[1] Config ...")
try {
    errs := Config.Load(tmp "\config.ini")
    Ok("Config.Load", "Validate=" errs.Length "条 (key为空应为1)")
} catch as e {
    Bad("Config", e.Message " @ " e.Line)
}

; ── 2. Log ──
P("[2] Log ...")
try {
    Log.Init(tmp)
    Log.Info("smoke")
    Ok("Log.Init", FileExist(Log.File()) ? "日志已建" : "日志未建")
} catch as e {
    Bad("Log", e.Message " @ " e.Line)
}

; ── 3. Clip 估算 ──
P("[3] Clip ...")
try {
    Ok("Clip.EstimateTokens", "en=" Round(Clip.EstimateTokens("hello world"), 2)
        " zh=" Round(Clip.EstimateTokens("中文测试"), 2))
} catch as e {
    Bad("Clip", e.Message " @ " e.Line)
}

; ── 4. History ──
P("[4] History ...")
try {
    History.Init(tmp)
    id := History.Add("quick", "", "测试问题")
    Ok("History.Add", "id=" id)
    History.Success(id, "测试回答", 42, 1234)
    r := History.Get(id)
    Ok("History.Success", "status=" r["status"] " tok=" r["tokens"] " ms=" r["ms"])

    id2 := History.Add("chat", "default", "第二问")
    History.Fail(id2, "timeout", "请求超时")
    r2 := History.Get(id2)
    Ok("History.Fail", "status=" r2["status"] " err=" r2["err"])

    Ok("History.Query", "全部=" History.Query("", "", 0).Length
        " quick=" History.Query("quick", "", 0).Length
        " 关键词=" History.Query("", "第二问", 0).Length)

    s := History.Stats()
    Ok("History.Stats", "total=" s["total"] " success=" s["success"] " failed=" s["failed"])

    mdPath := tmp "\out.md"
    e1 := History.Export("md", mdPath)
    Ok("History.Export", "err=[" e1 "] size=" (FileExist(mdPath) ? FileGetSize(mdPath) : 0))

    History.Init(tmp)
    Ok("History 重载", "条数=" History.items.Length)

    Ok("History.Delete", "ok=" History.Delete(id2) " 剩余=" History.items.Length)
} catch as e {
    Bad("History", e.Message " @ " e.Line)
}

; ── 5. Session ──
P("[5] Session ...")
try {
    Session.Init(tmp)
    sid := Session.Active()
    Ok("Session.Active", sid)
    Session.Append(sid, "user", "第一个问题")
    Session.Append(sid, "assistant", "第一个回答")
    Ok("Session 追加", "条数=" Session.Messages(sid).Length)

    msgs := Session.BuildPayloadMessages(sid, "第二个问题")
    Ok("Session.BuildPayloadMessages", "条数=" msgs.Length " 末role=" msgs[-1]["role"])

    Loop 40 {
        Session.Append(sid, "user", "填充问题 " A_Index)
        Session.Append(sid, "assistant", "填充回答 " A_Index)
    }
    Ok("Session.Prepare", "裁剪后=" Session.Prepare(sid).Length
        " (上限 " Session.maxRounds * 2 ")")

    Session.Clear(sid)
    Ok("Session.Clear", "条数=" Session.Messages(sid).Length)
} catch as e {
    Bad("Session", e.Message " @ " e.Line)
}

; ── 6. Ai 纯函数 ──
P("[6] Ai 纯函数 ...")
try {
    body := '{"choices":[{"message":{"content":"你好世界"}}],"usage":{"total_tokens":99}}'
    Ok("Ai.Extract", "=[" Ai.Extract(body) "] tok=" Ai.Tokens(body))
    Ok("Ai.Extract 错误体", "=[" Ai.Extract('{"error":{"message":"bad key"}}') "]")
    Ok("Ai.ErrText", "auth=[" Ai.ErrText("auth", 401) "]")

    bt := Chr(96)
    src := "## 标题" "`n`n" "**粗体** 和 " bt "代码" bt "`n`n" bt bt bt "js`nvar a=1`n" bt bt bt
    md := Ai.StripMarkdown(src)
    P("     原文=[")
    P(src)
    P("     ]")
    P("     结果=[")
    P(md)
    P("     ]")
    Ok("Ai.StripMarkdown", "见上方原文/结果")
} catch as e {
    Bad("Ai", e.Message " @ " e.Line)
}

; ── 7. Http 错误路径（不发真实请求）──
P("[7] Http 无 key 路径 ...")
try {
    done := false
    Http.Post(Map("x", 1), (ok, body, code, kind) => (done := true, 0))
    Ok("Http 无 key 拒绝", "回调触发=" done " inflight=" Http.InflightCount())
} catch as e {
    Bad("Http", e.Message " @ " e.Line)
}

try DirDelete tmp, true
P("== SMOKE_DONE ==")
ExitApp 0
