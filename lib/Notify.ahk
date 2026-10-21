/************************************************************************
 * CapQ - 通知系统
 * Win10+ 下 TrayTip 即为原生 toast。附降级方案。
 ***********************************************************************/

class Notify {
    static Show(text, title := "CapQ", icon := "Iconi Mute") {
        if (!Config.toast)
            return
        text  := SubStr(StrReplace(text, "`r", ""), 1, 250)   ; 正文上限 255
        title := SubStr(title, 1, 60)                          ; 标题上限 63
        try {
            TrayTip text, title, icon
        } catch as e {
            Log.Warn("TrayTip 失败，降级: " e.Message)
            this.Fallback(text, title)
        }
        ; TrayTip 在托盘图标隐藏 / 组策略禁用时静默失效，做个兜底提示
        if (A_IconHidden)
            this.Fallback(text, title)
    }

    static Success(summary) {
        this.Show(summary, "CapQ 已复制", "Iconi Mute")
    }

    static Error(msg) {
        this.Show(msg, "CapQ 出错", "Iconx")
    }

    static Warn(msg) {
        this.Show(msg, "CapQ 提示", "Icon!")
    }

    ; 降到 ToolTip：贴在鼠标旁，2 秒后消失
    static Fallback(text, title) {
        try {
            ToolTip "[" title "] " text
            SetTimer () => ToolTip(), -2000
        }
    }
}
