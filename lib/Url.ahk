/************************************************************************
 * CapQ - 链接识别与打开
 *
 * 只做两件事：判断剪贴板文本是不是链接、是就交给默认浏览器打开。
 *
 * 安全底线：只放行 http / https。
 *   剪贴板是不可信输入，绝对不能把 file:// javascript: data: ms-settings:
 *   之类的东西丢给 ShellExecute —— 那等于给攻击者一个启动任意程序的入口。
 ***********************************************************************/

class Url {
    ; 常见 TLD 白名单，用于判断「裸域名」（不带协议）算不算链接。
    ; 故意不收 md / txt / sh / py / js 这类既是 TLD 又是常见文件后缀的，
    ; 否则复制一个 "README.md" 按热键就去开网站了。
    static Tlds := ["com", "net", "org", "io", "dev", "ai", "co", "me", "app"
                  , "cn", "xyz", "info", "top", "site", "online", "tech", "cloud"
                  , "gov", "edu", "cc", "tv", "link", "pro", "wiki", "blog"
                  , "uk", "jp", "us", "de", "fr", "ru", "kr", "tw", "hk", "sg"
                  , "in", "au", "ca", "br", "nl", "se", "no", "fi", "dk", "pl"
                  , "it", "es", "ch", "at", "be", "pt", "gr", "cz", "ie", "il"
                  , "mx", "ar", "cl", "nz", "za", "tr", "ua", "vn", "th", "my"
                  , "id", "ph", "pk", "eg", "ae", "sa"]

    ; ── 从一段剪贴板文本里取出要打开的 URL；不像链接则返回 "" ──
    static Parse(text) {
        t := Trim(text "", " `t`r`n")
        if (t = "")
            return ""
        if (StrLen(t) > 8000)          ; 超长基本不是链接，别让浏览器去猜
            return ""

        ; 1) 整段就是一个链接（最常见）
        if (u := this.AsUrl(t))
            return u

        ; 2) Markdown 链接：[文字](https://...)
        q := Chr(34)
        if RegExMatch(t, "\[[^\]]*\]\(\s*((?i)https?://[^)\s]+)\s*\)", &m)
            if (u := this.AsUrl(m[1]))
                return u

        ; 3) 文本里夹着 http(s) 链接：取第一个
        pattern := "(?i)https?://[^\s<>" q "']+"
        if RegExMatch(t, pattern, &m2)
            if (u := this.AsUrl(m2[0]))
                return u

        return ""
    }

    ; ── 归一化：能确定的返回可打开 URL，否则 "" ──
    static AsUrl(t) {
        t := Trim(t "", " `t`r`n")
        t := this.Strip(t, "`"'")                  ; 去掉包裹的引号
        t := this.Strip(t, "<>")                   ; 去掉邮件/Markdown 的尖括号
        t := this.Strip(t, "`"'<>")

        if (t = "")
            return ""

        ; 有协议：只认 http / https
        if RegExMatch(t, "i)^[a-z][a-z0-9+.\-]*://")
            return RegExMatch(t, "i)^https?://\S+$") ? this.Finish(t) : ""

        ; 协议相对写法 //example.com/xxx
        if (SubStr(t, 1, 2) = "//")
            return RegExMatch(t, "i)^//\S+$") ? this.Finish("https:" t) : ""

        ; 裸域名：example.com  /  www.example.com  /  example.com/a?b=1
        pat := "i)^(?:www\.)?([a-z0-9](?:[a-z0-9\-]*[a-z0-9])?"
             . "(?:\.[a-z0-9](?:[a-z0-9\-]*[a-z0-9])?)+)"
             . "(?::\d{1,5})?(?:[/?#]\S*)?$"
        if RegExMatch(t, pat, &m) {
            parts := StrSplit(m[1], ".")
            tld := StrLower(parts[parts.Length])
            if this.IsTld(tld)
                return this.Finish("https://" t)
        }

        return ""
    }

    static IsTld(s) {
        for t in this.Tlds
            if (t = s)
                return true
        return false
    }

    ; ── 去掉首尾指定字符（反复剥，处理 " <x> " 这种嵌套） ──
    static Strip(s, chars) {
        Loop 4 {
            s := Trim(s, chars)
            if (s = "")
                return s
        }
        return s
    }

    ; ── 收尾清理：去掉粘连的尾部标点，做最终安全校验 ──
    static Finish(t) {
        ; 中文/英文句末标点常被一起复制进来
        Loop
            if (t != "" && InStr(".,;:!?。，、；：！？、）】》”’'", SubStr(t, -1)))
                t := SubStr(t, 1, -1)
            else
                break

        if (t = "")
            return ""

        ; 最终校验：必须 http(s)，且不含引号、空格、控制字符
        if !RegExMatch(t, "i)^https?://\S+$")
            return ""
        for bad in ["`"", "'", " ", "`t", "`r", "`n", "<", ">"]
            if InStr(t, bad)
                return ""

        ; 必须有一个像样的主机名
        if !RegExMatch(t, "i)^https?://[a-z0-9](?:[a-z0-9\-\.]*[a-z0-9])?(?::\d{1,5})?")
            return ""

        return t
    }

    ; ── 打开剪贴板里的链接；返回 true/false ──
    static OpenClipboard() {
        txt := Clip.SafeRead()
        if (Clip.IsEmpty(txt))
            return Notify.Warn("剪贴板是空的，先复制一个链接")

        u := this.Parse(txt)
        if (u = "")
            return Notify.Warn("剪贴板内容不是链接")

        if this.Open(u)
            Notify.Show(SubStr(u, 1, 200), "CapQ 已打开链接")
        return true
    }

    ; ── 真正打开 ──
    static Open(u) {
        ; 防御性二次校验：任何非 http(s) 一律拒绝
        if !RegExMatch(u, "i)^https?://")
            return false
        try {
            Run u
            Log.Info("打开链接 " SubStr(u, 1, 300))
            return true
        } catch as e {
            Log.Warn("打开链接失败: " e.Message " url=" SubStr(u, 1, 200))
            ; 退化用 ShellExecute 再试一次
            try {
                DllCall("ShellExecuteW", "Ptr", 0, "Str", "open"
                    , "Str", u, "Ptr", 0, "Ptr", 0, "Int", 1)
                return true
            } catch {
                Notify.Error("打不开这个链接")
                return false
            }
        }
    }
}
