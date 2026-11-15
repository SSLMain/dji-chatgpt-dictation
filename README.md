# DJI Mic Mini dictation companion

## Windows setup

Use 64-bit AutoHotkey v2 and the ChatGPT desktop app. For mouse-free mode, bind Microsoft WinUSB to the DJI Mic Mini receiver’s **button interface only**. In Zadig, verify all three USB ID fields before replacing a driver. The button is **`2CA3 4011 00`** and normally shows **HidUsb**. The audio interface is **`2CA3 4011 01`** and must stay on Microsoft USB Audio. Leave the composite parent and keyboard drivers alone.

After applying the driver, verify that Windows still lists **Microphone (Wireless Mic Rx)** and open the AutoHotkey companion of your choice. Start with a short test in a fresh chat before relying on automatic Send.

To undo the driver change, open the exact `MI_00` device in Device Manager and choose **Roll Back Driver** on the Driver tab. Verify that the device returns to **USB Input Device** with the **HidUsb** service. If Roll Back is unavailable, identify the installed OEM INF on the device’s **Details → Inf name** property. Remove it only after verifying that its hardware match is exactly `USB\VID_2CA3&PID_4011&MI_00` and then reconnect the receiver.

- [AutoHotkey v2](https://www.autohotkey.com/)
- [Zadig project and download](https://zadig.akeo.ie/)

## Mouse-free version with automatic Send

Open `DJI Dictate and Send.ahk` with `ChatGPT UI Automation.ahk` and `DJI WinUSB.ahk` in the same folder. This version uses the existing WinUSB driver binding. It starts in inspection mode if the working `DJI Dictation.ahk` companion is running. Activate ChatGPT and press **Ctrl+Alt+F11** to check which controls are accessible without triggering dictation or sending anything.

To switch, exit the working `DJI Dictation.ahk` companion from its tray menu. Then use **Enable or pause DJI** from the new script's tray menu, or exit and relaunch the new script. Start with an empty ChatGPT composer and no attachments. The first tap invokes Dictate. The second invokes Stop dictation, waits for fresh text and an enabled Send button in the same chat, then invokes Send once. The script uses no screen coordinates, cursor movement, or F9 calibration. **F10** pauses the active companion and cancels a pending send.

Keep the same ChatGPT window in front through transcription. A chat or window change, keyboard activity, unreadable composer, or timeout can leave the result for manual review. The status log records outcomes only. To switch back, exit `DJI Dictate and Send.ahk` and launch `DJI Dictation.ahk`. Your original F8/F9 script may stay running.

## Original companion with editable transcripts

The companion uses AutoHotkey v2 in 64-bit mode. It reads the receiver’s button report and sends F8 to the original dictation script after checking the calibrated point. Keep `DJI WinUSB.ahk` alongside `DJI Dictation.ahk`. With the original Windows HID driver, the DJI button also raises Windows volume. With a working WinUSB binding on the button interface, the companion reads the receiver directly. The keyboard remains on its own driver.

### Run the companion

1. Keep your original `Dictation.ahk` running and open `DJI Dictation.ahk`.
2. Activate ChatGPT. Hover over its **Dictate** microphone and press and release **F9** while holding the pointer still. Both scripts need the same calibration point.
3. Tap the DJI button to start dictation, speak, and tap it again to transcribe. Check that the cursor returns and that editable text appears in the composer.
4. Repeat on the second monitor and check both keyboard volume keys. F8 remains available for the original script’s normal start and stop workflow.
5. Press **F10** or use the tray menu to pause or resume the DJI listener.

### Troubleshooting and rollback

- Keep ChatGPT in the foreground and wait for the composer to finish transcribing before starting another recording. Allow about a second for the companion to check for an enabled Dictation button at the calibrated point.
- Press F9 again if you move or resize ChatGPT, change its layout, or restart either script. The original script uses screen coordinates.
- `DJI Dictation trace.log` records button reports, calibration, and whether the companion sent F8. It contains no audio or dictated text.
- To pause dictation while keeping the current driver, exit the companion from the tray. The original script can keep running. `Dictation.original.ahk` is a verified copy of the original.
