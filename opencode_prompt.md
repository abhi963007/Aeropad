# AeroPad Master Implementation Prompt for OpenCode

You are an expert Mobile Software Engineer and Systems Architect. Your objective is to build the complete, production-ready Android mobile application for **AeroPad** inside this repository.

---

### 📁 Project Context & Existing Assets
- **Design Reference:** Examine `assets/ui.png` in this directory. The app's user interface must match `assets/ui.png` pixel-for-pixel.
- **Specification:** Review `README.md` and `Project_Abstract.docx` for full architecture and protocol details.
- **Core Principle:** **Zero host/PC software.** The phone emulates a genuine hardware Bluetooth mouse using Android's native `BluetoothHidDevice` API (Android 9.0+ / API 28+). Any PC, Mac, Linux, or Smart TV will detect the phone as a plug-and-play Bluetooth mouse without any companion app or server on the computer.

---

### 🎨 1. UI & Visual Requirements (Matching `assets/ui.png`)
Build an ultra-minimalist, sleek dark-mode interface:

1. **Top App Bar:**
   - Left: **AeroPad** brand title in clean, modern bold sans-serif typography.
   - Right: Live connection badge with a glowing green dot: `"Connected: Windows PC"` (dynamically updates to `"Pairing / Discoverable"` or `"Disconnected"` based on state) and a minimalist settings gear icon.

2. **Main Touchpad Deck (Center ~85% of Viewport):**
   - A large, prominent rounded container (`rounded-3xl`) with a deep matte slate/black finish (`#121316`).
   - Subtle dot-matrix pattern across the touch surface.
   - Centered micro-guide text: `"1-finger move • Tap to click • 2-finger scroll"`.
   - Smooth gesture recognition and touch response with subtle glowing ripple or trace under active touch coordinates.

3. **Bottom Click Bar:**
   - Separated from the pad by clean padding, with a 1px vertical hairline dividing left and right zones.
   - **Left Zone:** Tactile mouse icon with left half highlighted + `"Left Click"` label.
   - **Right Zone:** Tactile mouse icon with right half highlighted + `"Right Click"` label.
   - Haptic vibration feedback on tap/press.

---

### 📡 2. Bluetooth HID Architecture & Native Protocol

#### USB-IF Standard 4-Byte Mouse HID Report Descriptor:
The app must broadcast and register the following standard HID descriptor:
- **Byte 0:** Button bitmask (`Bit 0`: Left Click, `Bit 1`: Right Click, `Bit 2`: Middle Click).
- **Byte 1:** Delta X (`-127` to `+127` signed 8-bit integer, relative horizontal displacement).
- **Byte 2:** Delta Y (`-127` to `+127` signed 8-bit integer, relative vertical displacement).
- **Byte 3:** Scroll Wheel (`-127` to `+127` signed 8-bit integer, vertical scroll delta).

#### Bluetooth Implementation:
- Access Android's `BluetoothProfile.HID_DEVICE` via `BluetoothAdapter.getProfileProxy()`.
- Implement `BluetoothHidDevice.Callback` (`onAppStatusChanged`, `onConnectionStateChanged`, `onGetReport`, `onSetReport`).
- Register the HID Device SDP record with `BluetoothHidDeviceAppSdpSettings`.
- Dispatches real-time pointer reports via `BluetoothHidDevice.sendReport(device, reportId, data)`.
- If using **Flutter**: Implement this via a robust Kotlin `MethodChannel` (`com.aeropad/hid`) in `android/app/src/main/kotlin/...` to bridge the native Android Bluetooth HID Device API to the Flutter UI.
- If using **Kotlin + Jetpack Compose**: Implement native `HidDeviceManager.kt`, `HidReportDescriptor.kt`, and Compose touch canvas.

---

### 🖐️ 3. Touch Gesture Engine

Implement precise multi-touch mathematics:
1. **Single-Finger Drag:** Calculates relative `(dx, dy)` between consecutive touch events, applies a smooth non-linear acceleration curve, and transmits `[0x00, dx, dy, 0x00]`.
2. **Single Tap:** Transmits Left Button Down `[0x01, 0, 0, 0]`, waits 30ms, then sends Button Up `[0x00, 0, 0, 0]` with a subtle haptic vibration.
3. **Two-Finger Tap:** Transmits Right Button Down `[0x02, 0, 0, 0]`, waits 30ms, then sends Button Up `[0x00, 0, 0, 0]`.
4. **Two-Finger Vertical Scroll:** Accumulates vertical displacement between touch samples and sends `[0x00, 0, 0, wheelDelta]`.
5. **Double-Tap & Hold (Drag & Drop):** If a second tap is held down, keeps `[0x01, dx, dy, 0]` active while moving, and releases on finger lift.
6. **Bottom Buttons:** Direct trigger for Left Click and Right Click packets.

---

### ⚙️ 4. Android Permissions & Configuration
Include all required Android permissions in `AndroidManifest.xml`:
- `android.permission.BLUETOOTH`
- `android.permission.BLUETOOTH_ADMIN`
- `android.permission.BLUETOOTH_CONNECT` (Android 12+)
- `android.permission.BLUETOOTH_ADVERTISE` (Android 12+)
- `android.permission.BLUETOOTH_SCAN` (Android 12+)
- `android.permission.VIBRATE`

---

### 🚀 Deliverable Instructions
1. Initialize and generate the full project structure (all Gradle/configuration files, Android manifest, source code, and assets).
2. Ensure there are **no placeholders or TODO comments**; write complete, production-grade, compile-ready code.
3. Match `assets/ui.png` styling accurately.
