
#Requires AutoHotkey v2.0
#SingleInstance Force

; Make script DPI-aware for multiple monitors
DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")

CoordMode "Mouse", "Screen"

; Calibration position
micX := 0
micY := 0
calibrated := false

; F9: Calibrate microphone position
F9:: {
    global micX, micY, calibrated

    MouseGetPos &micX, &micY
    calibrated := true

    ToolTip "Saved: X=" micX " Y=" micY
    SetTimer () => ToolTip(), -2000
}

; F8: Click the calibrated position
F8:: {
    global micX, micY, calibrated

    if !calibrated {
        MsgBox "Please hover over the microphone and press F9 first."
        return
    }

    ; Save current cursor location
    MouseGetPos &oldX, &oldY

    ; Move to microphone
    MouseMove micX, micY, 0

    Sleep 100

    ; Click current cursor location
    Click

    ; Restore cursor
    MouseMove oldX, oldY, 0
}
