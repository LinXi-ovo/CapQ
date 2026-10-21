/************************************************************************
 * CapQ - 会话管理（messages 数组）
 * 只被 H 链路使用；A 链路绝不触碰本模块。
 ***********************************************************************/

class Session {
    static file     := ""
    static data     := Map("active", "default", "sessions", Map())
    static maxRounds := 12          ; 保留最近 N 轮
    static maxTokens := 12000       ; 粗估 token 上限

    static Init(dataDir) {
        this.file := dataDir "\sessions.json"
        if FileExist(this.file) {
            try {
                this.data := JSON.parse(FileRead(this.file, "UTF-8"), false, true)
                if (Type(this.data) != "Map")
                    this.data := Map("active", "default", "sessions", Map())
            } catch as e {
                Log.Warn("读会话失败，重置: " e.Message)
                this.data := Map("active", "default", "sessions", Map())
            }
        }
        if (!this.data.Has("sessions") || Type(this.data["sessions"]) != "Map")
            this.data["sessions"] := Map()
        if (!this.data.Has("active"))
            this.data["active"] := "default"
        this.Ensure(this.data["active"])
    }

    static Active() => this.data["active"]

    static Ensure(sid) {
        s := this.data["sessions"]
        if !s.Has(sid)
            s[sid] := Map("name", sid, "msgs", [])
        if (!s[sid].Has("msgs") || Type(s[sid]["msgs"]) != "Array")
            s[sid]["msgs"] := []
        return s[sid]
    }

    static Messages(sid := "") {
        if (sid = "")
            sid := this.Active()
        return this.Ensure(sid)["msgs"]
    }

    ; 裁剪：保留最近 maxRounds 轮（每轮 user+assistant），并控制粗估 token
    static Prepare(sid := "") {
        msgs := this.Messages(sid)
        msgs := this.TrimRounds(msgs, this.maxRounds)
        msgs := this.TrimTokens(msgs, this.maxTokens)
        return msgs
    }

    static TrimRounds(msgs, rounds) {
        if (msgs.Length <= rounds * 2)
            return msgs
        out := []
        start := msgs.Length - rounds * 2 + 1
        Loop msgs.Length - start + 1
            out.Push(msgs[start + A_Index - 1])
        return out
    }

    static TrimTokens(msgs, budget) {
        total := 0
        for m in msgs
            total += Clip.EstimateTokens(m["content"] "") + 4
        if (total <= budget)
            return msgs
        ; 从最旧的成对丢弃
        out := msgs.Clone()
        while (out.Length > 2) {
            total := 0
            for m in out
                total += Clip.EstimateTokens(m["content"] "") + 4
            if (total <= budget)
                break
            out.RemoveAt(1)
        }
        return out
    }

    static Append(sid, role, content) {
        s := this.Ensure(sid)
        s["msgs"].Push(Map("role", role, "content", content))
        this.Save()
    }

    static Clear(sid := "") {
        if (sid = "")
            sid := this.Active()
        this.Ensure(sid)["msgs"] := []
        this.Save()
    }

    static Save() {
        try {
            f := FileOpen(this.file, "w", "UTF-8")
            f.Write(JSON.stringify(this.data, 10))
            f.Close()
        } catch as e {
            Log.Error("保存会话失败: " e.Message)
        }
    }

    ; 构造 H 链路的 messages 数组（含本轮新问题，但不写回磁盘）
    static BuildPayloadMessages(sid, question) {
        out := []
        for m in this.Prepare(sid)
            out.Push(Map("role", m["role"], "content", m["content"]))
        out.Push(Map("role", "user", "content", question))
        return out
    }
}
