/************************************************************************
 * CapQ - HTTP 通信系统（curl 子进程 + 定时器轮询，绝不阻塞消息泵）
 *
 * 关键设计：AHK 是伪多线程，同步 COM（WinHttp）会冻结整个程序。
 * 所以一律用 Run() 起 curl 子进程拿到 pid，再用 SetTimer 轮询 ProcessExist。
 ***********************************************************************/

class Http {
    ; id -> {pid, req, res, code, cb, started, timer}
    static pending := Map()
    static seq     := 0

    ; 回调签名：cb(ok, body, httpCode, errKind)
    ; 返回 id；失败时立即以 ok=false 回调
    static Post(payload, cb) {
        if (Trim(Config.key) = "") {
            cb.Call(false, "", "", "auth")
            return ""
        }

        this.seq += 1
        id  := A_TickCount "_" this.seq
        dir := A_Temp "\CapQ\"
        DirCreate dir

        reqFile  := dir id ".req"
        resFile  := dir id ".res"
        hdrFile  := dir id ".hdr"

        try
            bodyText := JSON.stringify(payload)
        catch as e {
            Log.Error("JSON.stringify 失败: " e.Message)
            cb.Call(false, "", "", "encode")
            return ""
        }

        try {
            ; 必须 UTF-8-RAW：带 BOM 的 JSON 请求体会被服务端判为非法
            f := FileOpen(reqFile, "w", "UTF-8-RAW")
            f.Write(bodyText)
            f.Close()
        } catch as e {
            Log.Error("写请求体失败: " e.Message)
            cb.Call(false, "", "", "io")
            return ""
        }

        url := Config.Url()
        ; 直接调 curl.exe，不经 cmd、不用 ">" 重定向：
        ;   1) 经 cmd 时 Run() 拿不到可靠 pid（前面验证过 pid 为空）
        ;   2) cmd 的 "> file" 会吞掉其后的所有参数
        ; 状态码改用 -D 写响应头文件，再从状态行解析。
        cmd := '"' A_WinDir '\System32\curl.exe"'
             . ' -s -S --max-time ' Config.timeout
             . ' -o "' resFile '"'
             . ' -D "' hdrFile '"'
             . ' -H "Content-Type: application/json"'
             . ' -H "Authorization: Bearer ' Config.key '"'
             . ' --data-binary "@' reqFile '"'
             . ' "' url '"'

        try
            pid := Run(cmd, , "Hide", &pidOut)
        catch as e {
            Log.Error("curl 启动失败: " e.Message)
            this.Cleanup(reqFile, resFile, hdrFile)
            cb.Call(false, "", "", "network")
            return ""
        }
        ; Run 的返回值有时为空，&pid 输出参数更可靠；两者取其一
        if (pid = "" || pid = 0)
            pid := pidOut
        pid := "" pid

        ; 注意：SetTimer 不接受 Bind 出来的函数对象（会丢参数，报
        ; "Missing a required parameter: id"）。必须用 ObjBindMethod。
        rec := {pid: pid, req: reqFile, res: resFile, hdr: hdrFile
              , cb: cb, started: A_TickCount, timer: 0}
        rec.timer := ObjBindMethod(Http, "Check", id)
        this.pending[id] := rec
        SetTimer rec.timer, 120
        Log.Info("HTTP 发出 id=" id " pid=" pid)
        return id
    }

    ; 由 SetTimer 反复调用；id 为 pending 键
    static Check(id) {
        if !this.pending.Has(id)
            return
        p := this.pending[id]

        ; 判断 curl 是否仍在运行。注意 Run() 拿到的 pid 可能为空，
        ; 所以不能只靠 ProcessExist；pid 为空时退化为看响应头是否已落盘。
        stuck := false
        if (p.pid != "" && ProcessExist(p.pid)) {
            stuck := true
        } else if (p.pid = "") {
            ; 没有 pid：只要 hdr 文件还没出现，就认为还在跑
            if !FileExist(p.hdr)
                stuck := true
        }

        if (stuck) {
            ; 硬超时保护：curl 自身有 --max-time，这里只防僵死
            if (A_TickCount - p.started <= (Config.timeout + 30) * 1000)
                return
            if (p.pid != "")
                try ProcessClose(p.pid)
            Log.Warn("HTTP 超时强杀 id=" id)
        }

        SetTimer(p.timer, 0)              ; 关掉自己这个定时器
        this.pending.Delete(id)

        ok := false, body := "", code := "", errKind := ""
        try {
            ; 从 -D 写出的响应头里取状态行：HTTP/1.1 200 OK
            hdr := FileRead(p.hdr, "UTF-8")
            if RegExMatch(hdr, "HTTP/\d[\d.]*\s+(\d{3})", &m)
                code := m[1]
            else
                code := "000"
            body := FileRead(p.res, "UTF-8")
        } catch as e {
            Log.Warn("读取 curl 结果失败 id=" id " : " e.Message)
            errKind := "network"
        }

        if (errKind = "") {
            if (code = "200")
                ok := true
            else
                errKind := this.Classify(code)
        }

        if (!ok)
            Log.Warn("HTTP 失败 id=" id " code=" code " kind=" errKind)

        this.Cleanup(p.req, p.res, p.hdr)
        try p.cb.Call(ok, body, code, errKind)
    }

    static Classify(code) {
        if (code = "401" || code = "403")
            return "auth"
        if (code = "429")
            return "rate_limit"
        if (code = "408" || code = "504")
            return "timeout"
        if (code = "000" || code = "")
            return "network"
        if (SubStr(code, 1, 1) = "5")
            return "server"
        return "http_" code
    }

    static Cleanup(req, res, hdr) {
        for f in [req, res, hdr]
            try FileDelete f
    }

    static CancelAll() {
        for id, p in this.pending {
            SetTimer(p.timer, 0)
            try ProcessClose(p.pid)
            this.Cleanup(p.req, p.res, p.hdr)
        }
        this.pending := Map()
    }

    static InflightCount() => this.pending.Count
}
