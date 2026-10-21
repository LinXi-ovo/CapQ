/************************************************************************
 * CapQ - 面板系统
 *   HistoryPanel : 历史列表（CapsLock+O）
 *   EditorPanel  : 单条编辑
 ***********************************************************************/

class HistoryPanel {
    static gui      := ""
    static lv       := ""
    static edit     := ""
    static stStatus := ""
    static filterMode := ""
    static keyword  := ""
    static rows     := []          ; ListView 行 -> 记录

    static Toggle() {
        if (IsObject(this.gui) && this.gui.Hwnd && DllCall("IsWindowVisible", "Ptr", this.gui.Hwnd)) {
            this.Hide()
            return
        }
        this.Show()
    }

    static Show() {
        this.Build()
        this.Refresh()
        this.gui.Show("w900 h600 Center")
        WinActivate "ahk_id " this.gui.Hwnd
    }

    static Hide() {
        if IsObject(this.gui)
            this.gui.Hide()
    }

    static Build() {
        if IsObject(this.gui)
            return

        g := Gui("+Resize", "CapQ · 历史问答")
        g.SetFont("s10", "Microsoft YaHei UI")
        g.MarginX := 10, g.MarginY := 8

        ; 顶部工具条
        g.Add("Text", "xm y+4", "模式:")
        this.ddlMode := g.Add("DropDownList", "x+6 w110", ["全部", "无历史(A)", "带历史(H)"])
        this.ddlMode.Value := 1
        this.ddlMode.OnEvent("Change", (*) => this.Refresh())

        g.Add("Text", "x+14", "搜索:")
        this.edKw := g.Add("Edit", "x+6 w220")
        this.edKw.OnEvent("Change", (*) => this.Refresh())

        btnRefresh := g.Add("Button", "x+10 w70", "刷新")
        btnRefresh.OnEvent("Click", (*) => (History.Load(), this.Refresh()))

        btnCopy := g.Add("Button", "x+6 w90", "复制回答")
        btnCopy.OnEvent("Click", (*) => this.CopySelected())

        btnDel := g.Add("Button", "x+6 w70", "删除")
        btnDel.OnEvent("Click", (*) => this.DeleteSelected())

        btnExport := g.Add("Button", "x+6 w70", "导出")
        btnExport.OnEvent("Click", (*) => this.Export())

        ; 列表
        lv := g.Add("ListView", "xm w880 h440 -Multi Grid"
            , ["时间", "模式", "状态", "问题", "回答摘要", "耗时", "Tok"])
        lv.ModifyCol(1, 130)
        lv.ModifyCol(2, 70)
        lv.ModifyCol(3, 70)
        lv.ModifyCol(4, 260)
        lv.ModifyCol(5, 240)
        lv.ModifyCol(6, 60)
        lv.ModifyCol(7, 50)
        lv.OnEvent("DoubleClick", (*) => this.OpenEditor())
        this.lv := lv

        ; 预览框
        g.Add("Text", "xm y+6", "详情（双击条目可编辑）：")
        this.preview := g.Add("Edit", "xm w880 h80 ReadOnly VScroll")

        this.stStatus := g.Add("StatusBar", , "就绪")
        g.OnEvent("Close", (*) => g.Hide())
        g.OnEvent("Escape", (*) => g.Hide())
        g.OnEvent("Size", ObjBindMethod(HistoryPanel, "OnSize"))

        this.gui := g
    }

    static OnSize(g, minMax, w, h) {
        if (minMax = -1)
            return
        try {
            this.lv.Move(, , w - 20, h - 200)
            this.preview.Move(, , w - 20, 80)
        }
    }

    static Refresh() {
        if !IsObject(this.lv)
            return

        mode := this.ddlMode.Value
        kw   := this.edKw.Value

        m := mode = 1 ? "" : mode = 2 ? "quick" : "chat"
        recs := History.Query(m, kw, 500)

        this.lv.Delete()
        this.rows := []

        for rec in recs {
            st := rec["status"]
            stText := st = "success" ? "成功" : st = "failed" ? "失败" : "进行中"
            modeText := rec["mode"] = "quick" ? "A" : "H"
            q  := SubStr(StrReplace(rec["q"], "`n", " "), 1, 90)
            a  := SubStr(StrReplace(rec["a"], "`n", " "), 1, 80)
            ms := rec["ms"] != "" ? rec["ms"] : ""
            this.rows.Push(rec)
            this.lv.Add(, rec["time"], modeText, stText, q, a, ms, rec["tokens"])
        }

        this.stStatus.SetText("共 " recs.Length " 条"
            . (kw != "" ? "（关键词：" kw "）" : ""))
    }

    static SelectedRec() {
        row := this.lv.GetNext()
        if (!row || row > this.rows.Length)
            return ""
        return this.rows[row]
    }

    static CopySelected() {
        rec := this.SelectedRec()
        if (rec = "")
            return Notify.Warn("先选中一条")
        if (rec["a"] = "")
            return Notify.Warn("这条没有回答可复制")
        Clip.Write(rec["a"])
        Notify.Show("已复制到剪贴板", "CapQ")
    }

    static DeleteSelected() {
        rec := this.SelectedRec()
        if (rec = "")
            return Notify.Warn("先选中一条")
        if (MsgBox("确定删除该条记录？", "CapQ", "YesNo Icon?") != "Yes")
            return
        History.Delete(rec["id"])
        this.Refresh()
    }

    static OpenEditor() {
        rec := this.SelectedRec()
        if (rec = "")
            return
        EditorPanel.Open(rec, ObjBindMethod(HistoryPanel, "Refresh"))
    }

    static Export() {
        path := FileSelect("S16", "capq-history-" FormatTime(A_Now, "yyyyMMdd-HHmm") ".md"
            , "导出历史", "Markdown (*.md; *.txt)|JSON (*.json)")
        if (path = "")
            return
        kind := (SubStr(StrLower(path), -4) = ".json") ? "json" : "md"
        err := History.Export(kind, path)
        if (err = "")
            Notify.Show("已导出到`n" path, "CapQ")
        else
            Notify.Error(err)
    }
}

; ─────────────────────────────────────────────────────────
class EditorPanel {
    static gui := ""

    static Open(rec, onSaved) {
        if (IsObject(this.gui))
            this.gui.Destroy()

        g := Gui("+Resize", "CapQ · 编辑条目")
        g.SetFont("s10", "Microsoft YaHei UI")
        g.MarginX := 12, g.MarginY := 10

        g.Add("Text", "xm", "时间：" rec["time"] "    模式：" (rec["mode"] = "quick" ? "A 无历史" : "H 带历史")
            . "    模型：" rec["model"])

        g.Add("Text", "xm y+8", "问题：")
        edQ := g.Add("Edit", "xm w760 r5 VScroll")

        g.Add("Text", "xm y+8", "回答：")
        edA := g.Add("Edit", "xm w760 r18 VScroll")

        edQ.Value := rec["q"]
        edA.Value := rec["a"]

        btnSave := g.Add("Button", "xm y+10 w100 Default", "保存")
        btnCopy := g.Add("Button", "x+8 w100", "复制回答")
        btnRe   := g.Add("Button", "x+8 w120", "用这问题重问")
        btnClose := g.Add("Button", "x+8 w100", "关闭")

        doSave := (*) => (
            rec["q"] := edQ.Value,
            rec["a"] := edA.Value,
            History.Update(rec["id"], Map("q", edQ.Value, "a", edA.Value)),
            Notify.Show("已保存", "CapQ"),
            onSaved.Call())

        btnSave.OnEvent("Click", doSave)
        btnCopy.OnEvent("Click", (*) => (
            Clip.Write(edA.Value),
            Notify.Show("已复制", "CapQ")))
        btnRe.OnEvent("Click", (*) => (
            Clip.Write(edQ.Value),
            g.Hide(),
            Ai.AskQuick()))
        btnClose.OnEvent("Click", (*) => g.Hide())

        g.OnEvent("Close", (*) => g.Hide())
        g.OnEvent("Escape", (*) => g.Hide())
        g.Show("w784 h640 Center")
        this.gui := g
    }
}
