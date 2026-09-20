"""AeroPad UDP mouse receiver and local-network discovery beacon."""

from __future__ import annotations

import json
import socket
import threading
import time
from typing import Any

from pynput.mouse import Button, Controller

COMMAND_PORT = 8989
DISCOVERY_PORT = 8988
DISCOVERY_REQUEST = "AEROPAD_DISCOVERY"
DISCOVERY_RESPONSE = "AEROPAD_DISCOVERY_RESPONSE"


class AeroPadServer:
    def __init__(self) -> None:
        self.mouse = Controller()
        self.running = True
        self.pressed: set[str] = set()
        self.hostname = socket.gethostname()
        self.ip_addresses = self._local_addresses()

    @staticmethod
    def _local_addresses() -> list[str]:
        addresses: set[str] = set()
        try:
            addresses.update(
                info[4][0]
                for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET)
            )
        except socket.gaierror:
            pass
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
                probe.connect(("8.8.8.8", 80))
                addresses.add(probe.getsockname()[0])
        except OSError:
            pass
        return sorted(address for address in addresses if not address.startswith("127.")) or ["127.0.0.1"]

    @staticmethod
    def _button(name: str) -> Button:
        return {"left": Button.left, "right": Button.right, "middle": Button.middle}[name]

    def handle(self, packet: dict[str, Any]) -> None:
        command = packet.get("type")
        if command == "move":
            self.mouse.move(int(packet.get("dx", 0)), int(packet.get("dy", 0)))
        elif command == "scroll":
            self.mouse.scroll(0, int(packet.get("dy", 0)))
        elif command == "click":
            self.mouse.click(self._button(str(packet.get("btn", "left"))))
        elif command == "down":
            button = str(packet.get("btn", "left"))
            if button not in self.pressed:
                self.mouse.press(self._button(button))
                self.pressed.add(button)
        elif command == "up":
            button = str(packet.get("btn", "left"))
            if button in self.pressed:
                self.mouse.release(self._button(button))
                self.pressed.remove(button)

    def response(self) -> bytes:
        return json.dumps({
            "type": DISCOVERY_RESPONSE,
            "name": self.hostname,
            "ip": self.ip_addresses[0],
            "port": COMMAND_PORT,
        }, separators=(",", ":")).encode()

    def receive_loop(self) -> None:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as receiver:
            receiver.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            receiver.bind(("0.0.0.0", COMMAND_PORT))
            receiver.settimeout(1.0)
            while self.running:
                try:
                    raw, _ = receiver.recvfrom(4096)
                    packet = json.loads(raw.decode("utf-8"))
                    if isinstance(packet, dict):
                        self.handle(packet)
                except socket.timeout:
                    continue
                except (OSError, UnicodeDecodeError, json.JSONDecodeError, KeyError, ValueError) as error:
                    print(f"[AeroPad] Ignored packet: {error}")

    def discovery_loop(self) -> None:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as beacon:
            beacon.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            beacon.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            beacon.bind(("0.0.0.0", DISCOVERY_PORT))
            beacon.settimeout(0.1)
            next_beacon = 0.0
            while self.running:
                try:
                    now = time.monotonic()
                    if now >= next_beacon:
                        beacon.sendto(self.response(), ("255.255.255.255", DISCOVERY_PORT))
                        next_beacon = now + 2.0
                    try:
                        raw, address = beacon.recvfrom(2048)
                    except socket.timeout:
                        continue
                    packet = json.loads(raw.decode("utf-8"))
                    if isinstance(packet, dict) and packet.get("type") == DISCOVERY_REQUEST:
                        # Reply to the packet's real source address and port. This
                        # also works across laptop hotspot virtual interfaces.
                        beacon.sendto(self.response(), address)
                except OSError as error:
                    print(f"[AeroPad] Discovery error: {error}")
                except (UnicodeDecodeError, json.JSONDecodeError, ValueError):
                    continue

    def run(self) -> None:
        print(f"AeroPad server: {self.hostname}")
        print(f"Listening for mouse packets on UDP {COMMAND_PORT}")
        if "192.168.137.1" in self.ip_addresses:
            print("WINDOWS MOBILE HOTSPOT READY: 192.168.137.1")
        else:
            print("Windows hotspot gateway: 192.168.137.1 (probe enabled)")
        print("Local Wi-Fi / hotspot addresses:")
        for address in self.ip_addresses:
            print(f"  http://{address}:{COMMAND_PORT} (UDP)")
        print("Waiting for AeroPad discovery and input. Press Ctrl+C to stop.")
        threads = [
            threading.Thread(target=self.receive_loop, daemon=True),
            threading.Thread(target=self.discovery_loop, daemon=True),
        ]
        for thread in threads:
            thread.start()
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            self.running = False
            for button in list(self.pressed):
                self.mouse.release(self._button(button))


if __name__ == "__main__":
    AeroPadServer().run()
