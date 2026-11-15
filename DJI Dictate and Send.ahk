#Requires AutoHotkey v2.0 64-bit
#SingleInstance Force
#Include DJI WinUSB.ahk
#Include ChatGPT UI Automation.ahk

tracePath := A_ScriptDir "\DJI Dictate and Send.log"
controller := DictationSession(ChatGPTControls())
buttonDown := false
lastPress := 0
reader := 0
enabled := false
A_TrayMenu.Add("Enable or pause DJI", Toggle)
if BackupRunning()
    Status("DJI backup is running. Ctrl+Alt+F11 can check ChatGPT controls without using the receiver.")
else
    Enable()
^!F11::Inspect()
Trace("Companion started.")

#HotIf controller.phase != "idle"
~*LButton::controller.CancelOnInput()
~*RButton::controller.CancelOnInput()
~*MButton::controller.CancelOnInput()
~*XButton1::controller.CancelOnInput()
~*XButton2::controller.CancelOnInput()
#HotIf

BackupRunning() {
    oldSetting := A_DetectHiddenWindows
    DetectHiddenWindows true
    try {
        for hwnd in WinGetList("ahk_class AutoHotkey") {
            if RegExMatch(WinGetTitle("ahk_id " hwnd), "i)\\DJI Dictation\.ahk - AutoHotkey")
                return true
        }
        return false
    } finally {
        DetectHiddenWindows oldSetting
    }
}

HandleReport(state) {
    global buttonDown, lastPress, enabled
    if state = 0 {
        buttonDown := false
        return
    }
    if state != 1 || buttonDown
        return
    buttonDown := true
    now := DllCall("GetTickCount64", "Int64")
    if enabled && now - lastPress >= 250 {
        lastPress := now
        SetTimer Tap, -1
    }
}

Tap() {
    global controller, enabled
    if !enabled
        return
    if BackupRunning() {
        controller.Reset("DJI: exit the backup companion before using Dictate and Send.")
        return
    }
    controller.Tap()
}

Toggle(*) {
    global controller, enabled
    if enabled {
        enabled := false
        controller.Reset("DJI paused. Any pending send was canceled.")
        return
    }
    Enable()
}

Enable() {
    global enabled, reader
    if BackupRunning() {
        Status("DJI: exit DJI Dictation.ahk from the tray before enabling this version.")
        return
    }
    if !reader
        reader := DJIWinUSB(HandleReport, Trace)
    Hotkey "F10", Toggle
    enabled := true
    Status("DJI Dictate and Send enabled.")
}

Inspect() {
    global controller
    hwnd := WinActive("ahk_exe ChatGPT.exe")
    if !hwnd {
        Status("DJI check: bring the ChatGPT desktop app forward and try again.")
        return
    }
    try {
        Loop 6 {
            view := controller.controls.Snapshot(hwnd)
            if view.route != "" && view.composer
                break
            if A_Index < 6
                Sleep 120
        }
        draft := controller.controls.Text(view.composer, &known)
        Status(Format("DJI check: chat={1}, composer readable={2}, Dictate invokable={3}, Stop invokable={4}, Send invokable={5}.",
            view.route != "", known, controller.controls.CanInvoke(view.start),
            controller.controls.CanInvoke(view.stop), controller.controls.CanInvoke(view.send)))
        Trace(Format("Inspection: {1} visible document(s), {2} alternate edit control(s), identity source {3}.",
            view.documents, view.edits, InStr(view.route, "uia:") = 1 ? "UI Automation" : "URL or unavailable"))
        Trace(Format("Message-box check: readable={1}, empty={2}, attachment detected={3}, box focused={4}, placeholder-like text={5}.",
            known, known && draft = "", view.attachment, controller.controls.IsFocused(view.composer),
            RegExMatch(draft, "i)^(Ask anything|Message ChatGPT|Type a message)$") != 0))
    } catch Error as err {
        Status("DJI check: accessibility lookup failed.")
        Trace(Format("UI Automation error: {1} at {2}.", Type(err), err.Line))
    }
}

Trace(message) {
    global tracePath
    try FileAppend(A_Now " " message "`n", tracePath, "UTF-8")
}

Status(message) {
    Trace(message)
    ToolTip message
    SetTimer () => ToolTip(), -2500
}

class DictationSession {
    phase := "idle"
    busy := false
    hwnd := 0
    route := ""
    baseline := ""
    transcript := ""
    stableSince := 0
    deadline := 0
    input := 0
    canceled := false

    __New(controls) {
        this.controls := controls
        this.pollCallback := ObjBindMethod(this, "Check")
    }

    Tap() {
        if this.busy || this.phase = "waiting"
            return
        this.busy := true
        try {
            if this.phase = "recording"
                this.StopRecording()
            else
                this.StartRecording()
        } catch Error as err {
            this.Reset("DJI: could not complete the control action. Review the composer.")
            Trace(Format("UI Automation error: {1} at {2}.", Type(err), err.Line))
        } finally {
            this.busy := false
        }
    }

    StartRecording() {
        hwnd := WinActive("ahk_exe ChatGPT.exe")
        if !hwnd {
            Status("DJI: bring the ChatGPT desktop app forward.")
            return
        }
        Loop 6 {
            view := this.controls.Snapshot(hwnd)
            if view.route != "" && view.start && view.composer
                break
            if !WinActive("ahk_id " hwnd)
                return
            if A_Index < 6
                Sleep 120
        }
        if !view.start || !view.composer || view.route = "" {
            Status("DJI: could not identify Dictate and the composer in this chat.")
            return
        }
        draft := this.controls.Text(view.composer, &known)
        if !known || (draft != "" && view.send) || view.attachment {
            reason := !known ? "could not read the message box." :
                (view.attachment ? "remove attachments before starting." : "clear the message box before starting.")
            Status("DJI: " reason)
            return
        }
        if !WinActive("ahk_id " hwnd)
            return
        this.hwnd := hwnd
        this.route := view.route
        this.baseline := draft
        this.canceled := false
        this.input := InputHook("V")
        this.input.KeyOpt("{All}", "+N")
        this.input.OnKeyDown := (*) => this.CancelOnInput()
        this.input.Start()
        if !this.controls.Invoke(view.start) {
            this.Reset("DJI: Dictate could not be invoked.")
            return
        }
        this.phase := "recording"
        SetTimer this.pollCallback, 200
        Trace("Dictate invoked.")
    }

    StopRecording() {
        if !this.InTarget() {
            this.Reset("DJI: chat changed. Auto-send canceled.")
            return
        }
        Loop 6 {
            view := this.controls.Snapshot(this.hwnd)
            if view.route != "" && view.route != this.route {
                this.Reset("DJI: chat changed. Auto-send canceled.")
                return
            }
            if view.route = this.route && view.stop
                break
            if !this.InTarget()
                return
            if A_Index < 6
                Sleep 120
        }
        if view.route != this.route || !view.stop || !this.InTarget() {
            this.Reset("DJI: Stop dictation was unavailable. Review the composer.")
            return
        }
        current := this.controls.Text(view.composer, &known)
        if this.canceled || (known && view.send && !(current == this.baseline)) || view.attachment
            this.canceled := true
        if !this.controls.Invoke(view.stop) {
            this.Reset("DJI: Stop dictation could not be invoked.")
            return
        }
        Trace("Stop dictation invoked.")
        if this.canceled {
            this.Reset("DJI: composer or input activity detected. Review the draft and send manually.")
            return
        }
        this.phase := "waiting"
        this.deadline := A_TickCount + 30000
        this.transcript := ""
        this.stableSince := 0
    }

    Check() {
        if this.busy || this.phase = "idle"
            return
        this.busy := true
        try {
            if !this.InTarget() || BackupRunning() {
                this.Reset("DJI: chat window changed. Auto-send canceled.")
                return
            }
            if this.phase = "recording"
                return
            if this.canceled || A_TickCount >= this.deadline {
                this.Reset("DJI: auto-send canceled. Review the composer.")
                return
            }
            view := this.controls.Snapshot(this.hwnd)
            if view.route != "" && view.route != this.route {
                this.Reset("DJI: chat changed. Auto-send canceled.")
                return
            }
            text := this.controls.Text(view.composer, &known)
            if view.route != this.route || view.stop || !view.send || !known || text = "" || text == this.baseline || view.attachment {
                this.transcript := ""
                this.stableSince := 0
                return
            }
            if !(text == this.transcript) {
                this.transcript := text
                this.stableSince := A_TickCount
                return
            }
            if A_TickCount - this.stableSince < 500 || !this.InTarget() || this.canceled
                return

            ; Clear the pending action before invoking Send. An ambiguous result is never retried.
            this.Reset()
            if this.controls.Invoke(view.send)
                Trace("Send invoked once after transcription.")
            else
                Status("DJI: Send could not be invoked. Review the composer.")
        } catch Error as err {
            this.Reset("DJI: auto-send canceled. Review the composer.")
            Trace(Format("UI Automation error: {1} at {2}.", Type(err), err.Line))
        } finally {
            this.busy := false
        }
    }

    InTarget() {
        return this.hwnd && WinActive("ahk_id " this.hwnd)
    }

    CancelOnInput() {
        this.canceled := true
    }

    Reset(message := "") {
        this.phase := "idle"
        SetTimer this.pollCallback, 0
        if this.input {
            this.input.Stop()
            this.input := 0
        }
        this.hwnd := 0
        this.route := ""
        this.baseline := ""
        this.transcript := ""
        this.canceled := false
        if message != ""
            Status(message)
    }
}
