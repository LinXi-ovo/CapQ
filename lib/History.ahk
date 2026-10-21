/************************************************************************
 * CapQ - 历史问答系统（query_history）
 * JSONL 追加写 + 内存索引。崩溃最多丢最后一条。
 ***********************************************************************/

class History {
    static file    := ""
    static items   := []          ; 数组，按时间正序
    static byId    := Map()

    static Init(dataDir) {
        this.file := dataDir "\history.jsonl"
        this.Load()
    }

    static Load() {
        this.items := []
        this.byId  := Map()
        if !FileExist(this.file)
            return

        try {
            content := FileRead(this.file, "UTF-8")
        } catch as e {
            Log.Error("读历史失败: " e.Message)
            return
        }

        bad := 0
        Loop Parse content, "`n", "`r" {
            line := Trim(A_LoopField, " `t")
            if (line = "")
                continue
            try {
                rec := JSON.parse(line, false, true)
                this.items.Push(rec)
                this.byId[rec["id"]] := rec
            } catch {
                bad += 1                   ; 跳过损坏行（如崩溃时写了一半）
            }
        }
        if (bad)
            Log.Warn("历史中有 " bad " 条损坏记录已跳过")
        Log.Info("历史载入 " this.items.Length " 条")
    }

    static Append(rec) {
        try {
            f := FileOpen(this.file, "a", "UTF-8")
            ; 必须 expandlevel=0 输出单行：JSONL 一条一行，默认会美化多行导致重载解析失败
            f.Write(JSON.stringify(rec, 0) "`n")
            f.Close()
        } catch as e {
            Log.Error("写历史失败: " e.Message)
        }
    }

    ; 新增一条 pending 记录，返回 id
    static Add(mode, sid, q) {
        rec := Map(
            "id",  this.NewId(),
            "mode", mode,
            "sid", sid,
            "q",   q,
            "a",   "",
            "status", "pending",
            "err", "",
            "model", Config.model,
            "tokens", 0,
            "ms", 0,
            "ts", A_TickCount + 0,
            "time", FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss"),
            "epoch", DateDiff(A_Now, "19700101000000", "Seconds") * 1000
        )
        this.items.Push(rec)
        this.byId[rec["id"]] := rec
        this.Append(rec)
        return rec["id"]
    }

    static Success(id, answer, tokens, ms) {
        this.Update(id, Map("a", answer, "status", "success", "err", ""
                          , "tokens", tokens, "ms", ms))
    }

    static Fail(id, errKind, errMsg := "") {
        this.Update(id, Map("status", "failed", "err", errKind
                          , "a", errMsg))
    }

    static Update(id, fields) {
        if !this.byId.Has(id) {
            Log.Warn("Update 找不到条目 " id)
            return
        }
        rec := this.byId[id]
        for k, v in fields
            rec[k] := v
        this.Rewrite()          ; 简单可靠：整体重写（几千条无压力）
    }

    static Delete(id) {
        if !this.byId.Has(id)
            return false
        this.byId.Delete(id)
        out := []
        for rec in this.items
            if (rec["id"] != id)
                out.Push(rec)
        this.items := out
        this.Rewrite()
        return true
    }

    static Get(id) => this.byId.Has(id) ? this.byId[id] : ""

    ; 过滤：mode 为空则不限；kw 为空则不限
    static Query(mode := "", kw := "", limit := 0) {
        out := []
        kw := Trim(kw "")
        Loop this.items.Length {
            i := this.items.Length - A_Index + 1        ; 倒序遍历（最新在前）
            rec := this.items[i]
            if (mode != "" && rec["mode"] != mode)
                continue
            if (kw != "" && !InStr(rec["q"], kw) && !InStr(rec["a"], kw))
                continue
            out.Push(rec)
            if (limit && out.Length >= limit)
                break
        }
        return out
    }

    static Rewrite() {
        tmp := this.file ".tmp"
        try {
            f := FileOpen(tmp, "w", "UTF-8")
            for rec in this.items
                f.Write(JSON.stringify(rec, 0) "`n")   ; 单行 JSONL
            f.Close()
            ; 目标可能还不存在（首次运行），FileDelete 会抛错，故先判断
            if FileExist(this.file)
                FileDelete this.file
            FileMove tmp, this.file
        } catch as e {
            Log.Error("重写历史失败: " e.Message)
        }
    }

    ; 按条数与天数清理
    static Prune() {
        before := this.items.Length
        if (this.items.Length <= Config.historyMax && Config.historyDays <= 0)
            return 0

        out := []
        nowEpoch := DateDiff(A_Now, "19700101000000", "Seconds") * 1000
        minEpoch := nowEpoch - Config.historyDays * 86400000

        for rec in this.items {
            if (Config.historyDays > 0 && rec["epoch"] < minEpoch)
                continue
            out.Push(rec)
        }
        ; 仍超量则从最旧的砍
        if (out.Length > Config.historyMax)
            out := this.Tail(out, Config.historyMax)

        this.items := out
        this.byId := Map()
        for rec in out
            this.byId[rec["id"]] := rec
        this.Rewrite()
        return before - out.Length
    }

    static Tail(arr, n) {
        if (arr.Length <= n)
            return arr
        out := []
        start := arr.Length - n + 1
        Loop n
            out.Push(arr[start + A_Index - 1])
        return out
    }

    static NewId() {
        return FormatTime(A_Now, "yyyyMMddHHmmss") "_" Format("{:06}", Random(0, 999999))
    }

    static Stats() {
        s := Map("total", this.items.Length, "quick", 0, "chat", 0
               , "success", 0, "failed", 0, "pending", 0)
        for rec in this.items {
            m := rec["mode"]
            if (m = "quick")
                s["quick"] += 1
            else if (m = "chat")
                s["chat"] += 1
            st := rec["status"]
            if s.Has(st)
                s[st] += 1
        }
        return s
    }

    static Export(kind, path) {
        try {
            f := FileOpen(path, "w", "UTF-8")
        } catch as e {
            return "无法写文件: " e.Message
        }

        if (kind = "json") {
            f.Write(JSON.stringify(this.items, 3))
        } else {
            for rec in this.items {
                f.Write("## " rec["time"] " [" rec["mode"] "/" rec["status"] "]`n`n")
                f.Write("**Q**：" rec["q"] "`n`n")
                if (rec["a"] != "")
                    f.Write("**A**：`n`n" rec["a"] "`n`n")
                if (rec["err"] != "")
                    f.Write("*错误*：" rec["err"] "`n`n")
                f.Write("---`n`n")
            }
        }
        f.Close()
        return ""
    }
}
