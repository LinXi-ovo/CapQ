/************************************************************************
 * CapQ - 日志系统
 * 按天写入 data\logs\YYYYMMDD.log，同时输出到调试器。
 ***********************************************************************/

class Log {
    static dir     := ""
    static enabled := true

    static Init(dataDir) {
        this.dir := dataDir "\logs"
        DirCreate this.dir
    }

    static File() {
        return this.dir "\" FormatTime(A_Now, "yyyyMMdd") ".log"
    }

    static Write(level, msg) {
        if (!this.enabled)
            return
        line := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") " [" level "] " msg
        try OutputDebug line
        try FileAppend line "`n", this.File(), "UTF-8"
    }

    static Info(msg)  => this.Write("INFO", msg)
    static Warn(msg)  => this.Write("WARN", msg)
    static Error(msg) => this.Write("ERROR", msg)
    static Debug(msg) => this.Write("DEBUG", msg)
}
