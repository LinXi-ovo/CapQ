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

        return this.Validate()
    }

    static Num(v, def) {
        v := Trim(v "")
        return (v = "" || !IsNumber(v)) ? def : v + 0
    }

    ; 返回错误数组；空数组表示通过
    static Validate() {
        errs := []
        if (Trim(this.key) = "")
            errs.Push("api.key 未设置（config.ini）")
        if (Trim(this.apiBase) = "")
            errs.Push("api.base 为空")
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
