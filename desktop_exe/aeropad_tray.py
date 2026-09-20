"""AeroPad Windows System Tray Application.

Runs the AeroPad UDP companion server in the background and provides a sleek
system tray menu in the Windows taskbar notification area.
"""

from __future__ import annotations

import os
import subprocess
import sys
import threading
import time
import winreg
from typing import Any

from PIL import Image, ImageDraw
import pystray

from aeropad_server import AeroPadServer, COMMAND_PORT

REG_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"
APP_NAME = "AeroPadServer"


def copy_to_clipboard(text: str) -> None:
    try:
        subprocess.run(
            ["clip"],
            input=text.encode("utf-16"),
            check=True,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    except Exception as error:
        print(f"[AeroPad] Clipboard error: {error}")


def is_autostart_enabled() -> bool:
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, REG_KEY, 0, winreg.KEY_READ) as key:
            winreg.QueryValueEx(key, APP_NAME)
            return True
    except OSError:
        return False


def set_autostart(enable: bool) -> None:
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, REG_KEY, 0, winreg.KEY_ALL_ACCESS) as key:
            if enable:
                exe_path = sys.executable if getattr(sys, "frozen", False) else os.path.abspath(sys.argv[0])
                winreg.SetValueEx(key, APP_NAME, 0, winreg.REG_SZ, f'"{exe_path}"')
            else:
                try:
                    winreg.DeleteValue(key, APP_NAME)
                except FileNotFoundError:
                    pass
    except Exception as error:
        print(f"[AeroPad] Autostart error: {error}")


def get_icon_image() -> Image.Image:
    possible_paths: list[str] = []

    # If PyInstaller bundle
    if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
        possible_paths.append(os.path.join(sys._MEIPASS, "aeropad_icon.ico"))
        possible_paths.append(os.path.join(sys._MEIPASS, "aeropad_icon.png"))

    base_dir = os.path.dirname(os.path.abspath(__file__))
    possible_paths.extend([
        os.path.join(base_dir, "aeropad_icon.ico"),
        os.path.join(base_dir, "aeropad_icon.png"),
        os.path.join(base_dir, "..", "assets", "app icon.png"),
        os.path.join(base_dir, "..", "assets", "app_icon_adaptive_fg.png"),
    ])

    for path in possible_paths:
        if os.path.isfile(path):
            try:
                return Image.open(path).convert("RGBA")
            except Exception:
                continue

    # Clean programmatic fallback icon
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.ellipse((4, 4, 60, 60), fill=(14, 42, 56, 255), outline=(56, 189, 248, 255), width=3)
    draw.rounded_rectangle((22, 16, 42, 48), radius=6, outline=(224, 228, 232, 255), width=2)
    draw.line((32, 16, 32, 28), fill=(56, 189, 248, 255), width=2)
    return img


class AeroPadTrayApp:
    def __init__(self) -> None:
        self.server = AeroPadServer(on_client_activity=self._on_client_activity)
        self.icon: pystray.Icon | None = None
        self._last_notification_time = 0.0

    def _on_client_activity(self, client_ip: str) -> None:
        now = time.time()
        if now - self._last_notification_time > 10.0 and self.icon:
            self._last_notification_time = now
            try:
                self.icon.notify(
                    f"AeroPad mobile app connected from {client_ip}",
                    "AeroPad Connected"
                )
            except Exception:
                pass

    def _make_ip_item(self, address: str) -> pystray.MenuItem:
        def on_copy(icon: pystray.Icon, item: Any) -> None:
            copy_to_clipboard(address)
            try:
                icon.notify(f"Copied {address} to clipboard!", "AeroPad IP Copied")
            except Exception:
                pass

        return pystray.MenuItem(f"{address}:{COMMAND_PORT} (Copy)", on_copy)

    def _build_menu(self) -> pystray.Menu:
        ip_items = [self._make_ip_item(ip) for ip in self.server.ip_addresses]
        status_text = "Status: Running" if not self.server.paused else "Status: Paused"

        def on_toggle_pause(icon: pystray.Icon, item: Any) -> None:
            is_paused = self.server.toggle_pause()
            icon.menu = self._build_menu()
            icon.update_menu()
            try:
                msg = "Server input paused." if is_paused else "Server input resumed."
                icon.notify(msg, "AeroPad")
            except Exception:
                pass

        def on_toggle_autostart(icon: pystray.Icon, item: Any) -> None:
            new_state = not is_autostart_enabled()
            set_autostart(new_state)
            icon.menu = self._build_menu()
            icon.update_menu()

        def on_show_info(icon: pystray.Icon, item: Any) -> None:
            primary_ip = self.server.ip_addresses[0] if self.server.ip_addresses else "127.0.0.1"
            info = (
                f"Server: {self.server.hostname}\n"
                f"Primary IP: {primary_ip}:{COMMAND_PORT}\n"
                f"Active Hotspot: {'Yes' if '192.168.137.1' in self.server.ip_addresses else 'No'}\n"
                f"UDP Port: {COMMAND_PORT}"
            )
            try:
                icon.notify(info, "AeroPad Server Info")
            except Exception:
                pass

        def on_exit(icon: pystray.Icon, item: Any) -> None:
            self.server.stop()
            icon.stop()

        return pystray.Menu(
            pystray.MenuItem(f"AeroPad Server ({self.server.hostname})", None, enabled=False),
            pystray.MenuItem(status_text, None, enabled=False),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Server IP Addresses", pystray.Menu(*ip_items)),
            pystray.MenuItem(
                "Resume Server" if self.server.paused else "Pause Server",
                on_toggle_pause
            ),
            pystray.MenuItem(
                "Start with Windows",
                on_toggle_autostart,
                checked=lambda item: is_autostart_enabled()
            ),
            pystray.MenuItem("Show Server Info", on_show_info),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("Exit AeroPad", on_exit)
        )

    def run(self) -> None:
        self.server.start()
        primary_ip = self.server.ip_addresses[0] if self.server.ip_addresses else "0.0.0.0"
        tooltip = f"AeroPad Server - {primary_ip}:{COMMAND_PORT}"

        self.icon = pystray.Icon(
            name="AeroPadServer",
            icon=get_icon_image(),
            title=tooltip,
            menu=self._build_menu()
        )

        try:
            self.icon.notify(
                f"Server running on {primary_ip}:{COMMAND_PORT}\nRight-click tray icon for options.",
                "AeroPad Server Started"
            )
        except Exception:
            pass

        self.icon.run()


if __name__ == "__main__":
    app = AeroPadTrayApp()
    app.run()
