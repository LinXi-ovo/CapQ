#Requires AutoHotkey v2.0
#ErrorStdOut
; Url 模块单元测试：只验证识别逻辑，不真的打开浏览器
SetWorkingDir A_ScriptDir
#Include ..\lib\Log.ahk
#Include ..\lib\Config.ahk
#Include ..\lib\Clipboard.ahk
#Include ..\lib\Notify.ahk
#Include ..\lib\Url.ahk

OUT := A_Temp "\urltest.txt"
try FileDelete OUT

P(l) {
    global OUT
    f := FileOpen(OUT, "a", "UTF-8-RAW")
    f.Write(l "`n")
    f.Close()
}

MyErr(e, mode) {
    P("!! ERR line=" e.Line " msg=" e.Message " extra=" e.Extra)
    return 1
}
OnError(MyErr)

fail := 0

; expect: 期望结果（"" = 应判为非链接）
T(name, input, expect) {
    global fail
    got := Url.Parse(input)
    ok := (got = expect)
    if (!ok)
        fail += 1
    P((ok ? "ok   " : "FAIL ") name)
    if (!ok) {
        P("     输入=[" input "]")
        P("     期望=[" expect "]")
        P("     实际=[" got "]")
    }
}

P("=== 应该识别 ===")
T("完整 https",        "https://github.com/LinXi-ovo/CapQ", "https://github.com/LinXi-ovo/CapQ")
T("完整 http",         "http://example.com/a?b=1&c=2",       "http://example.com/a?b=1&c=2")
T("裸域名 com",        "example.com",                        "https://example.com")
T("www 开头",          "www.google.com",                     "https://www.google.com")
T("裸域名带路径",      "github.com/foo/bar",                 "https://github.com/foo/bar")
T("带端口",            "localhost.dev:8080/x",               "https://localhost.dev:8080/x")
T("中文句号结尾",      "看这个 https://a.com/x。",            "https://a.com/x")
T("英文句号结尾",      "见 https://a.com/x.",                 "https://a.com/x")
T("包裹引号",          Chr(34) "https://a.com/x" Chr(34),    "https://a.com/x")
T("尖括号",            "<https://a.com/x>",                   "https://a.com/x")
T("Markdown 链接",     "[点我](https://a.com/x)",             "https://a.com/x")
T("句中夹链接",        "去 https://a.com/x 看看",             "https://a.com/x")
T("协议相对",          "//a.com/x",                           "https://a.com/x")
T("换行包围",          "`n https://a.com/x `n",               "https://a.com/x")
T("cn 域名",           "baidu.com",                           "https://baidu.com")
T("io 域名",           "github.io",                           "https://github.io")

P("")
P("=== 必须拒绝（安全）===")
T("空字符串",          "",                                    "")
T("纯空格",            "   ",                                 "")
T("普通句子",          "这是一个普通句子",                     "")
T("README.md",         "README.md",                           "")
T("脚本文件",          "test.ahk",                            "")
T("图片文件",          "photo.png",                           "")
T("file 协议",         "file:///C:/Windows/System32/calc.exe", "")
T("javascript 协议",   "javascript:alert(1)",                 "")
T("data 协议",         "data:text/html,<script>x</script>",   "")
T("ms-settings",       "ms-settings:privacy",                 "")
T("ftp 协议",          "ftp://a.com/x",                       "")
T("vscode 协议",       "vscode://file/C:/x",                  "")
T("无点数字",          "12345",                               "")
T("版本号",            "v1.2.3",                              "")
T("单个词",            "hello",                               "")
T("知识点",            "C++11",                               "")
T("文件名.h",          "stdio.h",                             "")

P("")
P("=== 边界 ===")
T("超长文本",   "https://a.com/" . Repeat("x", 9000), "")
T("只有协议",   "https://",                            "")

Repeat(s, n) {
    r := ""
    Loop n
        r .= s
    return r
}

P("")
P("=== 结果 ===")
P(fail = 0 ? "=== URLTEST_PASS ===" : "=== URLTEST_FAIL 共 " fail " 项 ===")
ExitApp (fail = 0 ? 0 : 1)
