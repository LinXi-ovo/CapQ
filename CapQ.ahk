/************************************************************************
 * CapQ — 剪贴板 AI 快捷助手
 *
 *   CapsLock + A  → 无历史单轮提问（不碰 messages 数组）
 *   CapsLock + H  → 带历史多轮提问（读写 messages 数组）
 *   CapsLock + O  → 打开历史问答面板
 *
 * 核心约束（见 docs/designs）：
 *   1. 热键回调内绝不做 IO —— 一律投递/异步（curl 子进程 + SetTimer）
 *   2. A 链路绝不读写 Session
 *   3. 所有错误写日志，绝不弹窗（OnError 接管）
 ***********************************************************************/

#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon off
Persistent
SendMode "Input"

; 剪贴板被占用时自动重试 5 秒（解决「刚 Ctrl+C 就按热键」的竞态）
#ClipboardTimeout 5000

SetWorkingDir A_ScriptDir
SetCapsLockState "AlwaysOff"

#Include lib\Log.ahk
#Include lib\Config.ahk
#Include lib\JSON.ahk
#Include lib\Clipboard.ahk
#Include lib\Notify.ahk
#Include lib\Http.ahk
#Include lib\History.ahk
#Include lib\Session.ahk
#Include lib\Ai.ahk
#Include lib\Panel.ahk

; ─────────────────────────────────────────────────────────
; 全局错误处理：只写日志，绝不弹窗
; ─────────────────────────────────────────────────────────
OnError(CapQ_OnError)

CapQ_OnError(err, mode) {
    global BUSY
    try BUSY := false
    try Notify.Error("内部错误，详见日志")
    try Log.Error(Format("未捕获错误 [{1}] 行 {2}: {3} :: {4}"
        , mode, err.Line, err.Message, err.Extra))
    try Ai.Reset()
    return 1                    ; 1 = 抑制默认错误对话框
}

; ─────────────────────────────────────────────────────────
; 启动
; ─────────────────────────────────────────────────────────
global BUSY := false

try {
    Config.Load()
    Log.Init(Config.dataDir)
    Log.Info("==== CapQ 启动 v" A_AhkVersion " ====")

    History.Init(Config.dataDir)
    Session.Init(Config.dataDir)

    pruned := History.Prune()
    if (pruned)
        Log.Info("历史清理 " pruned " 条")

    errs := Config.Validate()
    if (errs.Length) {
        for e in errs
            Log.Warn("配置问题: " e)
        TrayTip "请在 config.ini 填写 api.key`n脚本目录: " A_ScriptDir, "CapQ 需要配置", "Icon!"
    } else {
        TrayTip "A=无历史  H=带历史  O=面板", "CapQ 已就绪", "Iconi Mute"
    }

    InitTray()
} catch as e {
    Log.Error("启动失败: " e.Message " @line " e.Line)
}

; ─────────────────────────────────────────────────────────
; 热键
; ─────────────────────────────────────────────────────────
CapsLock::return                                 ; 单按 CapsLock 无动作
CapsLock & a::Ai.AskQuick()
CapsLock & h::Ai.AskWithHistory()
CapsLock & o::HistoryPanel.Toggle()

; ─────────────────────────────────────────────────────────
; 托盘
; ─────────────────────────────────────────────────────────
InitTray() {
    A_IconTip := "CapQ — 剪贴板 AI 助手"

    m := A_TrayMenu
    m.Delete()
    m.Add("历史面板 (CapsLock+O)", (*) => HistoryPanel.Toggle())
    m.Add("无历史提问 (CapsLock+A)", (*) => Ai.AskQuick())
    m.Add("带历史提问 (CapsLock+H)", (*) => Ai.AskWithHistory())
    m.Add()
    m.Add("打开配置 config.ini", (*) => Run(Config.iniPath))
    m.Add("打开日志目录", (*) => Run(Config.dataDir "\logs"))
    m.Add("重新加载配置", (*) => ReloadConfig())
    m.Add("重载脚本", (*) => Reload())
    m.Add()
    m.Add("退出", (*) => Quit())
    m.Default := "历史面板 (CapsLock+O)"
}

ReloadConfig() {
    errs := Config.Load()
    Notify.Show(errs.Length ? "配置有 " errs.Length " 处问题，见日志" : "配置已重新加载", "CapQ")
}

Quit() {
    try Ai.Reset()
    Log.Info("==== CapQ 退出 ====")
    ExitApp()
}

OnExit((*) => (Ai.Reset(), Log.Info("==== CapQ 退出 ====")))
