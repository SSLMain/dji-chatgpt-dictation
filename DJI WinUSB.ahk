#Requires AutoHotkey v2.0 64-bit

class DJIWinUSB {
    hardwareId := "USB\VID_2CA3&PID_4011&MI_00"
    file := 0
    usb := 0
    pipe := 0
    event := 0
    pending := false
    nextConnect := 0

    __New(onReport, trace) {
        this.onReport := onReport
        this.trace := trace
        this.overlapped := Buffer(32, 0)
        OnExit((*) => this.Close())
        SetTimer(ObjBindMethod(this, "Poll"), 15)
    }

    Connect() {
        base := "HKLM\SYSTEM\CurrentControlSet\Enum\" this.hardwareId
        matches := []
        Loop Reg base, "K" {
            if RegRead(base "\" A_LoopRegName, "Service", "") = "WinUSB"
                matches.Push(this.hardwareId "\" A_LoopRegName)
        }
        for instance in matches {
            if this.ConnectInstance(instance)
                return true
        }
        return false
    }

    ConnectInstance(instance) {
        deviceKey := "HKLM\SYSTEM\CurrentControlSet\Enum\" instance
        if RegRead(deviceKey, "Service", "") != "WinUSB"
            return false
        key := deviceKey "\Device Parameters"
        guids := RegRead(key, "DeviceInterfaceGUIDs", "")
        if !guids
            guids := RegRead(key, "DeviceInterfaceGUID", "")
        for guidText in StrSplit(guids, "`n", "`r") {
            guid := Buffer(16)
            if DllCall("ole32\CLSIDFromString", "WStr", guidText, "Ptr", guid, "Int") != 0
                continue
            ; Limit enumeration to the exact DJI button interface.
            if DllCall("cfgmgr32\CM_Get_Device_Interface_List_SizeW", "UInt*", &chars := 0,
                "Ptr", guid, "WStr", instance, "UInt", 0) != 0 || chars <= 1
                continue
            paths := Buffer(chars * 2, 0)
            if DllCall("cfgmgr32\CM_Get_Device_Interface_ListW", "Ptr", guid, "WStr", instance,
                "Ptr", paths, "UInt", chars, "UInt", 0) != 0
                continue
            path := StrGet(paths, "UTF-16")
            if !InStr(path, "vid_2ca3&pid_4011&mi_00#")
                continue
            file := DllCall("CreateFileW", "WStr", path, "UInt", 0xC0000000, "UInt", 3, "Ptr", 0,
                "UInt", 3, "UInt", 0x40000000, "Ptr", 0, "Ptr")
            if file = -1
                continue
            this.file := file
            if this.OpenPipe() {
                this.trace.Call(Format("WinUSB connected to DJI MI_00, interrupt IN 0x{:02X}.", this.pipe))
                return true
            }
            this.Close()
        }
        return false
    }

    OpenPipe() {
        if !DllCall("winusb\WinUsb_Initialize", "Ptr", this.file, "Ptr*", &usb := 0)
            return false
        this.usb := usb
        descriptor := Buffer(9)
        if !DllCall("winusb\WinUsb_QueryInterfaceSettings", "Ptr", usb, "UChar", 0, "Ptr", descriptor)
            return false
        info := Buffer(12)
        Loop NumGet(descriptor, 4, "UChar") {
            if !DllCall("winusb\WinUsb_QueryPipe", "Ptr", usb, "UChar", 0, "UChar", A_Index - 1, "Ptr", info)
                continue
            pipe := NumGet(info, 4, "UChar")
            if NumGet(info, 0, "UInt") != 3 || !(pipe & 0x80)
                continue
            this.pipe := pipe
            this.report := Buffer(NumGet(info, 6, "UShort"))
            this.event := DllCall("CreateEventW", "Ptr", 0, "Int", 1, "Int", 0, "Ptr", 0, "Ptr")
            return !!this.event
        }
        return false
    }

    Poll() {
        if !this.usb {
            if A_TickCount < this.nextConnect
                return
            this.nextConnect := A_TickCount + 1500
            if !this.Connect()
                return
        }
        if this.pending {
            if DllCall("WaitForSingleObject", "Ptr", this.event, "UInt", 0, "UInt") != 0
                return
            this.pending := false
            if !DllCall("winusb\WinUsb_GetOverlappedResult", "Ptr", this.usb, "Ptr", this.overlapped,
                "UInt*", &bytes := 0, "Int", 0) {
                this.Close()
                return
            }
            this.HandleReport(bytes)
        }

        DllCall("ResetEvent", "Ptr", this.event)
        NumPut("Int64", 0, "Int64", 0, "Int64", 0, "Ptr", this.event, this.overlapped)
        if DllCall("winusb\WinUsb_ReadPipe", "Ptr", this.usb, "UChar", this.pipe,
            "Ptr", this.report, "UInt", this.report.Size, "UInt*", &bytes := 0, "Ptr", this.overlapped) {
            this.HandleReport(bytes)
        } else if A_LastError = 997 {
            this.pending := true
        } else {
            this.Close()
        }
    }

    HandleReport(bytes) {
        if bytes >= 3 && NumGet(this.report, 0, "UChar") = 6 && NumGet(this.report, 2, "UChar") = 0
            this.onReport.Call(NumGet(this.report, 1, "UChar"))
    }

    Close() {
        if this.pending {
            DllCall("CancelIoEx", "Ptr", this.file, "Ptr", this.overlapped)
            DllCall("winusb\WinUsb_GetOverlappedResult", "Ptr", this.usb, "Ptr", this.overlapped,
                "UInt*", &ignored := 0, "Int", 1)
            this.pending := false
        }
        if this.usb {
            DllCall("winusb\WinUsb_Free", "Ptr", this.usb)
            this.usb := 0
        }
        if this.file {
            DllCall("CloseHandle", "Ptr", this.file)
            this.file := 0
        }
        if this.event {
            DllCall("CloseHandle", "Ptr", this.event)
            this.event := 0
        }
    }
}
