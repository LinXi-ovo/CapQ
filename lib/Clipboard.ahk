/************************************************************************
 * CapQ - 剪贴板系统
 * 读/写/快照/归一化。重试由 #ClipboardTimeout 在主脚本里全局兜底。
 ***********************************************************************/

class Clip {
    ; 读取剪贴板文本（去除首尾空白，限制最大长度）
    static Read(maxLen := 60000) {
        txt := A_Clipboard
        if (Type(txt) != "String")
            return ""
        txt := Trim(txt, " `t`r`n")
        if (StrLen(txt) > maxLen)
            txt := SubStr(txt, 1, maxLen)
        return txt
    }

    static IsEmpty(txt) {
        return Trim(txt, " `t`r`n") = ""
    }

    ; 写入文本（返回是否成功）
    ; 剪贴板是全局独占资源，常被剪贴板管理器（Ditto、输入法、微信等）
    ; 短暂占用；直接赋值会抛 "Can't open clipboard for writing"。
    ; 所以必须重试，并把最终成功与否如实返回。
    static Write(txt, retries := 8) {
        Loop retries {
            try {
                A_Clipboard := txt
                Sleep 30                  ; 让系统处理 WM_SETTINGCHANGE
                return true
            } catch as e {
                if (A_Index = retries) {
                    Log.Warn("Clip.Write 失败(重试 " retries " 次): " e.Message)
                    return false
                }
                Sleep 80                  ; 等占用方释放
            }
        }
        return false
    }

    ; 只读取，不写入；用于拿到用户复制的内容
    static SafeRead() {
        Loop 5 {
            try
                return this.Read()
            catch
                Sleep 60
        }
        return ""
    }

    ; 保存完整剪贴板（含图片等），用于还原
    static Snapshot() {
        try return ClipboardAll()
        catch
            return ""
    }

    static Restore(snap) {
        if (snap = "" || !IsObject(snap))
            return false
        try {
            A_Clipboard := snap
            return true
        } catch {
            return false
        }
    }

    ; 粗估 token：中文 1 字≈1，英文 4 字符≈1
    static EstimateTokens(txt) {
        n := 0
        Loop Parse txt {
            ch := A_LoopField
            n += (Ord(ch) > 127) ? 1 : 0.25
        }
        return n
    }
}
