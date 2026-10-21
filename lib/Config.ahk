/************************************************************************
 * CapQ - 配置系统
 * 读写 config.ini，提供带默认值的强类型配置对象。
 ***********************************************************************/

class Config {
    ; ── api ─────────────────────────────────────────────
    ; 注意：属性名不能叫 base —— 那是 AHK 内置的对象基类引用，
    ; 用作属性名会导致 load-time 错误（弹窗且卡住，/validate 查不出来）。
    static apiBase     := "https://api.deepseek.com"
    static path        := "/chat/completions"
    static model       := "deepseek-chat"
    static key         := ""
    static temperature := 0.3
    static maxtok      := 2048
    static timeout     := 120

    ; ── ui ──────────────────────────────────────────────
    static toast       := 1
    static trimmarkdown := 0
    static historyMax  := 2000
    static historyDays := 90
    ; 打开链接后是否把浏览器窗口切到前台（1=切，0=留在后台）
    static urlActivate := 1

    ; ── 运行期 ───────────────────────────────────────────
    static iniPath     := ""
    static dataDir     := ""

    static Load(path := "") {
        this.iniPath := path != "" ? path : A_ScriptDir "\config.ini"
        this.dataDir := A_ScriptDir "\data"
        DirCreate this.dataDir

        if !FileExist(this.iniPath)
            this.WriteDefault()

        this.StripBom()

        this.apiBase     := IniRead(this.iniPath, "api", "base", this.apiBase)
        this.path        := IniRead(this.iniPath, "api", "path", this.path)
        this.model       := IniRead(this.iniPath, "api", "model", this.model)
        this.key         := IniRead(this.iniPath, "api", "key", this.key)
        this.temperature := this.Num(IniRead(this.iniPath, "api", "temperature", this.temperature), 0.3)
        this.maxtok      := Integer(this.Num(IniRead(this.iniPath, "api", "maxtok", this.maxtok), 2048))
        this.timeout     := Integer(this.Num(IniRead(this.iniPath, "api", "timeout", this.timeout), 120))

        this.toast       := Integer(this.Num(IniRead(this.iniPath, "ui", "toast", this.toast), 1))
        this.trimmarkdown := Integer(this.Num(IniRead(this.iniPath, "ui", "trimmarkdown", this.trimmarkdown), 0))
        this.historyMax  := Integer(this.Num(IniRead(this.iniPath, "ui", "historyMax", this.historyMax), 2000))
        this.historyDays := Integer(this.Num(IniRead(this.iniPath, "ui", "historyDays", this.historyDays), 90))
        this.urlActivate := Integer(this.Num(IniRead(this.iniPath, "ui", "urlActivate", this.urlActivate), 1))

        ; 环境变量最后覆盖，优先级高于 ini
        this.ApplyEnv()

        return this.Validate()
    }

    ; ── 环境变量覆盖 ─────────────────────────────────────
    ; myllmurl     → 接口根地址（apiBase）
    ; myllmapi     → API Key
    ; myllmmodelid → 模型名
    ; 用途：密钥不落盘。ini 里留空即可，全部从环境变量取。
    static ApplyEnv() {
        u := this.Env("myllmurl")
        if (u != "")
            this.apiBase := this.NormBase(u)

        k := this.Env("myllmapi")
        if (k != "")
            this.key := k

        ; 模型名：兼容两种写法
        m := this.Env("myllmmodelid")
        if (m = "")
            m := this.Env("myllmmodel")
        if (m != "")
            this.model := m
    }

    ; 读环境变量并去掉首尾空白/引号（用户可能在系统设置里带了引号）
    static Env(name) {
        v := ""
        try v := EnvGet(name)
        catch
            return ""
        if (v = "" || !IsSet(v))
            return ""
        v := Trim(v " ", " `t`r`n")
        ; 去掉可能被一起粘进来的成对引号
        while (StrLen(v) >= 2) {
            f := SubStr(v, 1, 1), l := SubStr(v, -1)
            if ((f = '"' && l = '"') || (f = "'" && l = "'"))
                v := Trim(SubStr(v, 2, StrLen(v) - 2), " `t`r`n")
            else
                break
        }
        return v
    }

    ; 归一化 base：去掉尾部斜杠，避免拼出 "//chat/completions"
    static NormBase(u) {
        u := Trim(u " ", " `t`r`n")
        while (SubStr(u, -1) = "/")
            u := SubStr(u, 1, StrLen(u) - 1)
        return u
    }

    static Num(v, def) {
        v := Trim(v "")
        return (v = "" || !IsNumber(v)) ? def : v + 0
    }

    ; 返回错误数组；空数组表示通过
    static Validate() {
        errs := []
        if (Trim(this.key) = "")
            errs.Push("API Key 未设置：设环境变量 myllmapi，或在 config.ini 的 [api] key= 填")
        if (Trim(this.apiBase) = "")
            errs.Push("接口地址为空：设环境变量 myllmurl，或在 config.ini 的 [api] base= 填")
        if (Trim(this.model) = "")
            errs.Push("api.model 为空")
        if (this.maxtok < 1)
            errs.Push("api.maxtok 必须 >= 1")
        return errs
    }

    static Url() {
        b := RTrim(this.apiBase, "/")
        p := this.path
        if (SubStr(p, 1, 1) != "/")
            p := "/" p
        return b p
    }

    static WriteDefault() {
        txt := "
        (
        [api]
        base=https://api.deepseek.com
        path=/chat/completions
        model=deepseek-chat
        key=
        temperature=0.3
        maxtok=2048
        timeout=120

        [ui]
        toast=1
        trimmarkdown=0
        historyMax=2000
        historyDays=90
        urlActivate=1
        )"
        try FileDelete this.iniPath
        ; 必须用 UTF-8-RAW：带 BOM 会让 IniRead 把首段读成 "\uFEFFapi"，
        ; 导致 [api] 段永远取不到值（key 读成空）。
        FileAppend txt, this.iniPath, "UTF-8-RAW"
    }

    ; 容错：若 ini 带 UTF-8 BOM，IniRead 会把首段名读成 "\uFEFFapi"。
    ; 检测到 BOM 就重写为无 BOM 版本（内容不变）。
    static StripBom() {
        try {
            f := FileOpen(this.iniPath, "r", "UTF-8-RAW")
            head := f.Read(3)
            f.Close()
        } catch {
            return
        }
        if (head = Chr(0xEF) Chr(0xBB) Chr(0xBF)) {
            try {
                content := FileRead(this.iniPath, "UTF-8")   ; 自动吃掉 BOM
                FileDelete this.iniPath
                FileAppend content, this.iniPath, "UTF-8-RAW"
                Log.Warn("config.ini 带 BOM，已自动转为无 BOM")
            }
        }
    }

    static Set(section, key, value) {
        IniWrite value, this.iniPath, section, key
    }
}
