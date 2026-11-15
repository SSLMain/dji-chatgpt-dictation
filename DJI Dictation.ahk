#Requires AutoHotkey v2.0 64-bit
#SingleInstance Force
#Include DJI WinUSB.ahk

; Run alongside the original Dictation.ahk, which owns F8 and F9.
DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
CoordMode "Mouse", "Screen"

djiEnabled := true
djiDown := false
lastDjiPress := -1000
djiDevice := 0
djiPath := "\\?\HID#VID_2CA3&PID_4011&MI_00&Col01#"
targetWindow := 0
targetX := 0
targetY := 0
tracePath := A_ScriptDir "\DJI Dictation trace.log"
FileAppend("`n" A_Now " Companion started.`n", tracePath, "UTF-8")

A_TrayMenu.Add("Enable or pause DJI button", ToggleDJI)
OnMessage(0xFF, ReadDJI)
OnMessage(0xFE, ResetDJIDevice)
registration := Buffer(8 + A_PtrSize, 0)
NumPut("UShort", 0x0C, "UShort", 1, "UInt", 0x2100, "Ptr", A_ScriptHwnd, registration)
djiAvailable := DllCall("RegisterRawInputDevices", "Ptr", registration, "UInt", 1, "UInt", registration.Size)
winUsbReader := DJIWinUSB(state => HandleDJIReport(state, "WinUSB"), Trace)
ShowStatus(djiAvailable ? "DJI companion ready. Calibrate in ChatGPT with F9." : "DJI input registration failed.")

; Observe F9 release without competing with the original script's F9 press.
~F9 Up:: {
    global targetWindow, targetX, targetY
    targetWindow := 0
    hwnd := WinActive("A")
    if !hwnd
        return
    window := "ahk_id " hwnd
    if WinGetProcessName(window) != "ChatGPT.exe" && !InStr(WinGetTitle(window), "ChatGPT") {
        ShowStatus("DJI: activate ChatGPT before calibrating.")
        return
    }
    MouseGetPos &x, &y
    if WindowAt(x, y) != hwnd {
        ShowStatus("DJI: keep the pointer over the ChatGPT Dictate button through F9 release.")
        return
    }
    targetX := x
    targetY := y
    targetWindow := hwnd
    Trace("F9 calibration accepted.")
    ShowStatus("DJI companion calibrated.")
}

F10:: ToggleDJI()

ToggleDJI(*) {
    global djiEnabled, djiAvailable, winUsbReader
    if !djiAvailable && !winUsbReader.usb
        return
    djiEnabled := !djiEnabled
    ShowStatus(djiEnabled ? "DJI dictation enabled." : "DJI dictation paused.")
}

TriggerOriginalF8() {
    global djiEnabled, targetWindow, targetX, targetY
    static busy := false
    if busy
        return
    busy := true
    try DispatchF8()
    finally busy := false
}

DispatchF8() {
    global djiEnabled, targetWindow, targetX, targetY
    if !djiEnabled
        return
    if !targetWindow {
        Trace("F8 skipped: calibration missing.")
        ShowStatus("DJI: hover over ChatGPT's Dictate button and press F9.")
        return
    }
    if !WinActive("ahk_id " targetWindow) {
        Trace("F8 skipped: calibrated window is in the background.")
        return
    }
    if WindowAt(targetX, targetY) != targetWindow {
        Trace("F8 skipped: saved point is over another window.")
        ShowStatus("DJI: ChatGPT moved. Calibrate again with F9.")
        return
    }
    hwnd := targetWindow
    x := targetX
    y := targetY
    ; Electron can expose the button only after the first point lookup warms UI Automation.
    Loop 10 {
        if !djiEnabled || targetWindow != hwnd || targetX != x || targetY != y
            return
        if !WinActive("ahk_id " hwnd) || WindowAt(x, y) != hwnd
            return
        if DictationButtonAt(x, y, &detail) {
            if WinActive("ahk_id " hwnd) && WindowAt(x, y) = hwnd {
                Trace("F8 sent after " A_Index " lookup(s): " detail)
                SendEvent "{F8}"
            }
            return
        }
        if detail != "no accessible button at the saved point." || A_Index = 10
            break
        Sleep 100
    }
    Trace("F8 skipped: " detail)
    ShowStatus("DJI: " detail)
}

WindowAt(x, y) {
    point := (y << 32) | (x & 0xFFFFFFFF)
    hwnd := DllCall("WindowFromPoint", "Int64", point, "Ptr")
    return DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
}

DictationButtonAt(x, y, &detail) {
    static automation := 0
    static walker := 0
    element := 0
    detail := "no accessible button at the saved point."
    try {
        if !automation {
            automation := ComObject("{FF48DBA4-60EF-4201-AA87-54103EEF594E}",
                "{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}")
        }
        if !walker {
            ComCall(16, automation, "Ptr*", &rawWalker := 0) ; RawViewWalker
            walker := ComValue(13, rawWalker, 1)
        }
        ; ElementFromPoint takes a POINT by value on x64.
        point := (y << 32) | (x & 0xFFFFFFFF)
        ComCall(7, automation, "Int64", point, "Ptr*", &element)
        Loop 6 {
            if !element
                return false
            ComCall(21, element, "Int*", &controlType := 0)
            if controlType = 50000 {
                ComCall(28, element, "Int*", &enabled := 0)
                ComCall(23, element, "Ptr*", &namePointer := 0)
                name := namePointer ? Trim(StrGet(namePointer, "UTF-16")) : ""
                if namePointer
                    DllCall("OleAut32\SysFreeString", "Ptr", namePointer)
                detail := (enabled ? "enabled" : "disabled") " button: " (name != "" ? name : "(unnamed)")
                return enabled && RegExMatch(name, "i)^(Dictate|Dictation|Start dictation|Stop dictation|Confirm dictation|Submit dictation|Stop recording)$")
            }
            ComCall(3, walker, "Ptr", element, "Ptr*", &parent := 0)
            ObjRelease element
            element := parent
        }
        return false
    } catch Error as err {
        detail := "accessibility lookup failed: " err.Message
        return false
    } finally {
        if element
            ObjRelease element
    }
}

ReadDJI(wParam, lParam, *) {
    global djiDevice, djiPath, djiDown
    headerSize := 8 + 2 * A_PtrSize
    size := 0
    DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003, "Ptr", 0, "UInt*", &size, "UInt", headerSize)
    if size < headerSize + 11
        return
    data := Buffer(size)
    if DllCall("GetRawInputData", "Ptr", lParam, "UInt", 0x10000003, "Ptr", data, "UInt*", &size, "UInt", headerSize, "UInt") != size
        return
    if NumGet(data, 0, "UInt") != 2 || NumGet(data, headerSize, "UInt") != 3
        return
    handle := NumGet(data, 8, "Ptr")
    if handle != djiDevice {
        chars := 0
        DllCall("GetRawInputDeviceInfoW", "Ptr", handle, "UInt", 0x20000007, "Ptr", 0, "UInt*", &chars)
        if !chars
            return
        path := Buffer((chars + 1) * 2, 0)
        if DllCall("GetRawInputDeviceInfoW", "Ptr", handle, "UInt", 0x20000007, "Ptr", path, "UInt*", &chars, "Int") <= 0
            return
        if InStr(StrGet(path, "UTF-16"), djiPath) != 1
            return
        djiDevice := handle
        djiDown := false
    }
    count := NumGet(data, headerSize + 4, "UInt")
    if count > (size - headerSize - 8) // 3
        return
    Loop count {
        offset := headerSize + 8 + (A_Index - 1) * 3
        if NumGet(data, offset, "UChar") != 6 || NumGet(data, offset + 2, "UChar") != 0
            continue
        HandleDJIReport(NumGet(data, offset + 1, "UChar"), "HID")
    }
}

HandleDJIReport(state, source) {
    global djiDown, djiEnabled, lastDjiPress
    if state = 0 {
        Trace(source " DJI release report.")
        djiDown := false
    } else if state = 1 && !djiDown {
        Trace(source " DJI press report.")
        djiDown := true
        now := DllCall("GetTickCount64", "Int64")
        if djiEnabled && now - lastDjiPress >= 250 {
            lastDjiPress := now
            SetTimer TriggerOriginalF8, -1
        }
    }
}

ResetDJIDevice(wParam, lParam, *) {
    global djiDevice, djiDown
    if wParam = 2 && lParam = djiDevice {
        djiDevice := 0
        djiDown := false
    }
}

Trace(message) {
    global tracePath
    try FileAppend(A_TickCount " " message "`n", tracePath, "UTF-8")
}

ShowStatus(message) {
    ToolTip message
    SetTimer () => ToolTip(), -2500
}



