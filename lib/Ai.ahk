/************************************************************************
 * CapQ - AI 请求系统
 *
 * 两条链路严格隔离：
 *   AskQuick()          → A：单轮、不读不写 messages
 *   AskWithHistory()    → H：读写 Session 的 messages 数组
 ***********************************************************************/

class Ai {
    ; 阻止并发：一次只允许一个请求在飞
    static busy     := false
    static lastFire := 0

    ; ─────────────────────────────────────────────────────
    ; A 链路：无历史。硬约束——绝不触碰 Session。
    ; ─────────────────────────────────────────────────────
    static AskQuick() {
        if this.Guard()
            return

        q := Clip.Read()
        if Clip.IsEmpty(q)
            return Notify.Warn("剪贴板为空，先 Ctrl+C 复制内容")

        this.busy := true
        id := History.Add("quick", "", q)
        Log.Info("A 发起 id=" id " qlen=" StrLen(q))

        payload := Map(
            "model",       Config.model,
            "messages",    [Map("role", "user", "content", q)],   ; 唯一一条
            "temperature", Config.temperature + 0,
            "max_tokens",  Config.maxtok + 0,
            ; 必须用 JSON.false：原生 false 会被序列化成 0，
            ; 服务端要求布尔类型，"stream":0 会报 invalid field type。
            "stream",      JSON.false)

        t0 := A_TickCount
        ; 必须用 ObjBindMethod：.Bind() 会丢失 static 方法的 this，
        ; 导致内部的 this.HandleFail 参数错位（Missing a required parameter）。
        Http.Post(payload, ObjBindMethod(Ai, "OnQuickDone", id, t0))
    }

    static OnQuickDone(id, t0, ok, body, httpCode, errKind) {
        this.busy := false
        ms := A_TickCount - t0

        if (!ok)
            return this.HandleFail(id, errKind, httpCode)

        ans := this.Extract(body)
        if (ans = "")
            return this.HandleFail(id, "empty_answer", httpCode)

        this.Finish(id, ans, body, ms)
    }

    ; ─────────────────────────────────────────────────────
    ; H 链路：带历史。读写 messages 数组。
    ; ─────────────────────────────────────────────────────
    static AskWithHistory() {
        if this.Guard()
            return

        q := Clip.Read()
        if Clip.IsEmpty(q)
            return Notify.Warn("剪贴板为空，先 Ctrl+C 复制内容")

        this.busy := true
        sid := Session.Active()
        id  := History.Add("chat", sid, q)
        Log.Info("H 发起 id=" id " sid=" sid " 历史条数=" Session.Messages(sid).Length)

        payload := Map(
            "model",       Config.model,
            "messages",    Session.BuildPayloadMessages(sid, q),
            "temperature", Config.temperature + 0,
            "max_tokens",  Config.maxtok + 0,
            "stream",      JSON.false)   ; 原生 false 会序列化成 0

        t0 := A_TickCount
        Http.Post(payload, ObjBindMethod(Ai, "OnChatDone", id, sid, q, t0))
    }

    static OnChatDone(id, sid, question, t0, ok, body, httpCode, errKind) {
        this.busy := false
        ms := A_TickCount - t0

        if (!ok)
            return this.HandleFail(id, errKind, httpCode)

        ans := this.Extract(body)
        if (ans = "")
            return this.HandleFail(id, "empty_answer", httpCode)

        ; 成功才写回会话上下文
        Session.Append(sid, "user", question)
        Session.Append(sid, "assistant", ans)

        this.Finish(id, ans, body, ms)
    }

    ; ─────────────────────────────────────────────────────
    ; 共用收口：写剪贴板 → Toast → 落库
    ; ─────────────────────────────────────────────────────
    static Finish(id, ans, body, ms) {
        if (Config.trimmarkdown)
            ans := this.StripMarkdown(ans)

        written := Clip.Write(ans)
        tokens  := this.Tokens(body)

        History.Success(id, ans, tokens, ms)

        if (!written)
            return Notify.Error("回答已生成，但写剪贴板失败，去面板里复制")

        summary := SubStr(StrReplace(ans, "`n", " "), 1, 120)
        Notify.Success(summary)
        Log.Info("完成 id=" id " ms=" ms " tok=" tokens)
    }

    static HandleFail(id, errKind, httpCode) {
        msg := this.ErrText(errKind, httpCode)
        History.Fail(id, errKind, msg)
        Notify.Error(msg)
        Log.Warn("失败 id=" id " kind=" errKind " code=" httpCode)
    }

    static ErrText(kind, code) {
        switch kind {
            case "auth":       return "API Key 无效或未设置（改 config.ini）"
            case "rate_limit": return "触发限流，稍后再试"
            case "timeout":    return "请求超时"
            case "network":    return "网络不通（curl 失败）"
            case "server":     return "服务端错误 " code
            case "encode":     return "请求序列化失败"
            case "io":         return "临时文件读写失败"
            case "empty_answer": return "返回内容为空"
            default:           return "请求失败 " code
        }
    }

    ; curl 若因网络错误退出，body 可能是空或错误文本
    static Extract(body) {
        if (Trim(body "") = "")
            return ""
        try {
            obj := JSON.parse(body, false, true)
        } catch as e {
            Log.Warn("响应非 JSON: " SubStr(body, 1, 200))
            return ""
        }
        ; OpenAI 兼容格式
        if (obj.Has("choices") && Type(obj["choices"]) = "Array" && obj["choices"].Length > 0) {
            c := obj["choices"][1]
            if (c.Has("message") && Type(c["message"]) = "Map" && c["message"].Has("content"))
                return c["message"]["content"] ""
        }
        ; 错误体
        if (obj.Has("error")) {
            e := obj["error"]
            Log.Warn("API 错误体: " (Type(e) = "Map" && e.Has("message") ? e["message"] : String(e)))
        }
        return ""
    }

    static Tokens(body) {
        try {
            obj := JSON.parse(body, false, true)
            if (obj.Has("usage") && Type(obj["usage"]) = "Map") {
                u := obj["usage"]
                return u.Has("total_tokens") ? u["total_tokens"] + 0 : 0
            }
        }
        return 0
    }

    ; 简易 markdown 清理：去代码块围栏、去行内 ** 与反引号
    static StripMarkdown(t) {
        bt := Chr(96)                                  ; 反引号，避免转义地狱
        fence := bt bt bt
        t := RegExReplace(t, fence "[a-zA-Z]*\r?\n?", "")
        t := RegExReplace(t, fence, "")
        t := RegExReplace(t, "\*\*(.+?)\*\*", "$1")
        t := RegExReplace(t, "(?m)^#{1,6}\s+", "")
        t := RegExReplace(t, bt "([^" bt "]+)" bt, "$1")
        return Trim(t, " `t`r`n")
    }

    ; 并发 / 防抖保护。返回 true 表示应中止
    static Guard() {
        if this.busy {
            Notify.Warn("上一个请求还在进行中")
            return true
        }
        if (A_TickCount - this.lastFire < 300) {
            return true
        }
        this.lastFire := A_TickCount
        return false
    }

    static Reset() {
        this.busy := false
        Http.CancelAll()
    }
}
