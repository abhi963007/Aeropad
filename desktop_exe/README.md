# AeroPad Desktop Server (.EXE & System Tray)

A zero-dependency standalone Windows application for the AeroPad Companion Server.

---

## 🚀 How to Run

1. Open the `dist/` folder.
2. Double-click **`AeroPadServer.exe`**.
3. That's it! No command prompt or terminal window will appear. The server starts immediately in the background.

---

## 🖥️ System Tray Controls

When running, AeroPad sits in your Windows **Notification Area / System Tray** (click the little **`^`** arrow on the bottom-right corner of your taskbar).

### Right-Click Context Menu Features:
* **Server Status**: Shows whether the server is active or paused.
* **Server IP Addresses**: Lists all network interfaces (Wi-Fi, Hotspot `192.168.137.1`, Ethernet). Click any IP address to **automatically copy it to your clipboard**!
* **Pause / Resume Server**: Temporarily stop accepting input without closing the app.
* **Start with Windows**: Toggle automatic startup on Windows boot.
* **Show Server Info**: Displays a desktop notification with current connection details.
* **Exit AeroPad**: Safely releases any mouse buttons, shuts down UDP listeners, and exits cleanly.

---

## 🛠️ How to Re-Build `AeroPadServer.exe`

If you modify `aeropad_server.py` or `aeropad_tray.py`:

```bash
# 1. Install dependencies
pip install -r requirements.txt

# 2. Run the automated compiler
python build_exe.py
```

The compiled standalone executable will be generated in `dist/AeroPadServer.exe`.
