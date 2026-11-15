#Requires AutoHotkey v2.0 64-bit

class ChatGPTControls {
    __New() {
        this.api := ComObject("{FF48DBA4-60EF-4201-AA87-54103EEF594E}",
            "{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}")
        this.documents := this.Condition(30003, 50030)
        this.edits := this.Condition(30003, 50004)
        this.buttons := this.Condition(30003, 50000)
        this.promptId := this.Condition(30011, "prompt-textarea")
        ComCall(16, this.api, "Ptr*", &walker := 0)
        this.walker := ComValue(13, walker, 1)
    }

    Snapshot(hwnd, findComposer := true) {
        ComCall(6, this.api, "Ptr", hwnd, "Ptr*", &root := 0)
        result := {route: "", composer: 0, start: 0, stop: 0, send: 0, attachment: false, documents: 0, edits: 0}
        if !root
            return result
        root := ComValue(13, root, 1)

        candidates := []
        visible := []
        for document in this.Elements(root, this.documents) {
            if this.Prop(document, 30022)
                continue
            visible.Push(document)
            route := this.Prop(document, 30045)
            if !this.IsChatRoute(route)
                route := this.Prop(document, 30093)
            if this.IsChatRoute(route)
                candidates.Push({doc: document, route: route})
        }
        result.documents := visible.Length
        if candidates.Length > 1
            return result
        if candidates.Length = 1 {
            document := candidates[1].doc
            result.route := candidates[1].route
        } else {
            ; The desktop app can expose controls without a web document URL.
            document := visible.Length = 1 ? visible[1] : root
            identity := this.RuntimeId(document)
            if identity = ""
                return result
            result.route := "uia:" identity
        }

        if findComposer {
            prompts := []
            for edit in this.Elements(document, this.promptId) {
                if !this.Prop(edit, 30022)
                    prompts.Push(edit)
            }
            if !prompts.Length {
                visibleEdits := []
                for edit in this.Elements(document, this.edits) {
                    if this.Prop(edit, 30022)
                        continue
                    visibleEdits.Push(edit)
                    if RegExMatch(this.Prop(edit, 30005), "i)^(Message ChatGPT|Ask anything|Prompt|ChatGPT message input)$")
                        prompts.Push(edit)
                }
                result.edits := visibleEdits.Length
                if !prompts.Length && visibleEdits.Length = 1
                    prompts.Push(visibleEdits[1])
            }
            if prompts.Length = 1
                result.composer := prompts[1]
        }

        counts := Map("start", 0, "stop", 0, "send", 0)
        for button in this.Elements(document, this.buttons) {
            name := this.Prop(button, 30005)
            action := ""
            if RegExMatch(name, "i)^(Dictate|Start dictation)$")
                action := "start"
            else if RegExMatch(name, "i)^Stop dictation$")
                action := "stop"
            else if RegExMatch(name, "i)^(Send|Send message|Send prompt)$")
                action := "send"
            else if RegExMatch(name, "i)^(Remove|Delete) (attachment|file|image)(\b|$)") && !this.Prop(button, 30022)
                result.attachment := true
            if action = "" || this.Prop(button, 30022)
                continue
            counts[action] += 1
            result.%action% := counts[action] = 1 && this.Prop(button, 30010) ? button : 0
        }
        if findComposer && !result.composer {
            anchor := result.start || result.stop || result.send
            if anchor
                result.composer := this.EditNearButton(result.start ? result.start : (result.stop ? result.stop : result.send))
        }
        return result
    }

    EditNearButton(button) {
        node := button
        Loop 8 {
            ComCall(3, this.walker, "Ptr", node, "Ptr*", &parent := 0)
            if !parent
                break
            node := ComValue(13, parent, 1)
            matches := []
            for edit in this.Elements(node, this.edits) {
                if !this.Prop(edit, 30022)
                    matches.Push(edit)
            }
            if matches.Length = 1
                return matches[1]
            if matches.Length > 1
                break
        }
        return 0
    }

    RuntimeId(element) {
        ComCall(4, element, "Ptr*", &ids := 0)
        if !ids
            return ""
        try {
            if DllCall("oleaut32\SafeArrayGetLBound", "Ptr", ids, "UInt", 1, "Int*", &first := 0, "Int")
                return ""
            if DllCall("oleaut32\SafeArrayGetUBound", "Ptr", ids, "UInt", 1, "Int*", &last := 0, "Int")
                return ""
            id := ""
            Loop last - first + 1 {
                index := first + A_Index - 1
                if DllCall("oleaut32\SafeArrayGetElement", "Ptr", ids, "Int*", &index, "Int*", &part := 0, "Int")
                    return ""
                id .= "/" part
            }
            return id
        } finally {
            DllCall("oleaut32\SafeArrayDestroy", "Ptr", ids)
        }
    }

    IsChatRoute(value) {
        return RegExMatch(value, "i)^https://(?:chatgpt\.com|chat\.openai\.com)(?:[/?#]|$)")
    }

    Text(edit, &known) {
        known := false
        if !edit
            return ""
        pattern := this.Pattern(edit, 10002) ; ValuePattern
        if pattern {
            value := this.BStr(pattern, 4)
            known := true
            return Trim(value, " `t`n`r" Chr(0x200B) Chr(0xFEFF))
        }
        pattern := this.Pattern(edit, 10014) ; TextPattern
        if pattern {
            ComCall(7, pattern, "Ptr*", &range := 0)
            if range {
                value := this.BStr(ComValue(13, range, 1), 12, -1)
                known := true
                return Trim(value, " `t`n`r" Chr(0x200B) Chr(0xFEFF))
            }
        }
        pattern := this.Pattern(edit, 10018) ; LegacyIAccessiblePattern
        if pattern {
            value := this.BStr(pattern, 8)
            known := true
            return Trim(value, " `t`n`r" Chr(0x200B) Chr(0xFEFF))
        }
        return ""
    }

    Invoke(element) {
        if !element || !this.Prop(element, 30010) || this.Prop(element, 30022)
            return false
        invoke := this.Pattern(element, 10000)
        if !invoke
            return false
        ComCall(3, invoke)
        return true
    }

    CanInvoke(element) {
        return element && this.Pattern(element, 10000) ? true : false
    }

    IsFocused(element) {
        if !element
            return false
        ComCall(8, this.api, "Ptr*", &focused := 0)
        if !focused
            return false
        focused := ComValue(13, focused, 1)
        ComCall(3, this.api, "Ptr", element, "Ptr", focused, "Int*", &same := 0)
        return !!same
    }

    Pattern(element, id) {
        ComCall(16, element, "Int", id, "Ptr*", &ptr := 0)
        return ptr ? ComValue(13, ptr, 1) : 0
    }

    BStr(element, slot, args*) {
        ptr := 0
        try {
            if args.Length
                ComCall(slot, element, "Int", args[1], "Ptr*", &ptr)
            else
                ComCall(slot, element, "Ptr*", &ptr)
            return ptr ? StrGet(ptr, "UTF-16") : ""
        } finally {
            if ptr
                DllCall("oleaut32\SysFreeString", "Ptr", ptr)
        }
    }

    Prop(element, id) {
        value := Buffer(24, 0)
        try {
            ; GetCurrentPropertyValueEx with ignoreDefaultValue=true.
            ComCall(11, element, "Int", id, "Int", 1, "Ptr", value)
            switch NumGet(value, 0, "UShort") {
                case 3: return NumGet(value, 8, "Int")
                case 8:
                    ptr := NumGet(value, 8, "Ptr")
                    return ptr ? StrGet(ptr, "UTF-16") : ""
                case 11: return NumGet(value, 8, "Short") != 0
                default: return ""
            }
        } finally {
            DllCall("oleaut32\VariantClear", "Ptr", value)
        }
    }

    Condition(property, value) {
        variant := Buffer(24, 0)
        if value is Integer
            NumPut("UShort", 3, variant), NumPut("Int", value, variant, 8)
        else {
            str := DllCall("oleaut32\SysAllocString", "WStr", value, "Ptr")
            NumPut("UShort", 8, variant), NumPut("Ptr", str, variant, 8)
        }
        try {
            ; A 24-byte VARIANT passed by value is passed indirectly on Windows x64.
            ComCall(23, this.api, "Int", property, "Ptr", variant, "Ptr*", &condition := 0)
            return ComValue(13, condition, 1)
        } finally {
            DllCall("oleaut32\VariantClear", "Ptr", variant)
        }
    }

    Elements(root, condition) {
        ComCall(6, root, "Int", 4, "Ptr", condition, "Ptr*", &results := 0)
        elements := []
        if !results
            return elements
        results := ComValue(13, results, 1)
        ComCall(3, results, "Int*", &length := 0)
        Loop length {
            ComCall(4, results, "Int", A_Index - 1, "Ptr*", &ptr := 0)
            if ptr
                elements.Push(ComValue(13, ptr, 1))
        }
        return elements
    }
}
