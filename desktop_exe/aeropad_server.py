"""AeroPad UDP mouse receiver and local-network discovery beacon.

Designed to be run standalone or managed by the AeroPad System Tray controller.
"""

from __future__ import annotations

import json
import socket
import threading
import time
from typing import Any, Callable

from pynput.mouse import Button, Controller

COMMAND_PORT = 8989
DISCOVERY_PORT = 8988
DISCOVERY_REQUEST = "AEROPAD_DISCOVERY"
DISCOVERY_RESPONSE = "AEROPAD_DISCOVERY_RESPONSE"


class AeroPadServer:
    def __init__(self, on_client_activity: Callable[[str], None] | None = None) -> None:
        self.mouse = Controller()
        self.running = False
        self.paused = False
        self.pressed: set[str] = set()
        self.hostname = socket.gethostname()
        self.ip_addresses = self._local_addresses()
        self.last_client: str = ""
        self.last_activity_time: float = 0.0
        self.on_client_activity = on_client_activity
        self._threads: list[threading.Thread] = []
        self._command_socket: socket.socket | None = None
        self._discovery_socket: socket.socket | None = None

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
        return {"left": Button.left, "right": Button.right, "middle": Button.middle}.get(name, Button.left)

    def handle(self, packet: dict[str, Any], client_addr: str) -> None:
        if self.paused:
            return

        command = packet.get("type")
        self.last_client = client_addr
        self.last_activity_time = time.time()
        if self.on_client_activity:
            self.on_client_activity(client_addr)

        if command == "move":
            self.mouse.move(int(packet.get("dx", 0)), int(packet.get("dy", 0)))
        elif command == "scroll":
            dx = int(packet.get("dx", 0))
            dy = int(packet.get("dy", 0))
            self.mouse.scroll(dx, dy)
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
                self.pressed.discard(button)

    def response(self) -> bytes:
        return json.dumps({
            "type": DISCOVERY_RESPONSE,
            "name": self.hostname,
            "ip": self.ip_addresses[0],
            "port": COMMAND_PORT,
        }, separators=(",", ":")).encode()

    def _broadcast_targets(self) -> list[str]:
        targets = {"255.255.255.255"}
        for ip in self.ip_addresses:
            parts = ip.split(".")
            if len(parts) == 4:
                targets.add(f"{parts[0]}.{parts[1]}.{parts[2]}.255")
        return sorted(targets)

    def receive_loop(self) -> None:
        try:
            receiver = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            receiver.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            receiver.bind(("0.0.0.0", COMMAND_PORT))
            receiver.settimeout(0.5)
            self._command_socket = receiver
        except OSError as e:
            print(f"[AeroPad] Cannot bind command port {COMMAND_PORT}: {e}")
            return

        while self.running:
            try:
                raw, (client_ip, _) = receiver.recvfrom(4096)
                packet = json.loads(raw.decode("utf-8"))
                if isinstance(packet, dict):
                    self.handle(packet, client_ip)
            except socket.timeout:
                continue
            except (OSError, UnicodeDecodeError, json.JSONDecodeError, KeyError, ValueError):
                continue

        try:
            receiver.close()
        except Exception:
            pass

    def discovery_loop(self) -> None:
        try:
            beacon = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            beacon.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            beacon.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            beacon.bind(("0.0.0.0", DISCOVERY_PORT))
            beacon.settimeout(0.2)
            self._discovery_socket = beacon
        except OSError as e:
            print(f"[AeroPad] Cannot bind discovery port {DISCOVERY_PORT}: {e}")
            return

        next_beacon = 0.0
        while self.running:
            try:
                now = time.monotonic()
                if now >= next_beacon:
                    targets = self._broadcast_targets()
                    for target in targets:
                        try:
                            beacon.sendto(self.response(), (target, DISCOVERY_PORT))
                        except OSError:
                            pass
                    next_beacon = now + 1.5

                try:
                    raw, address = beacon.recvfrom(2048)
                except socket.timeout:
                    continue

                packet = json.loads(raw.decode("utf-8"))
                if isinstance(packet, dict) and packet.get("type") == DISCOVERY_REQUEST:
                    beacon.sendto(self.response(), address)
                    if self.on_client_activity:
                        self.on_client_activity(address[0])
            except (OSError, UnicodeDecodeError, json.JSONDecodeError, ValueError):
                continue

        try:
            beacon.close()
        except Exception:
            pass

    def start(self) -> None:
        if self.running:
            return
        self.running = True
        self.paused = False
        t1 = threading.Thread(target=self.receive_loop, daemon=True, name="AeroPad-Receiver")
        t2 = threading.Thread(target=self.discovery_loop, daemon=True, name="AeroPad-Discovery")
        self._threads = [t1, t2]
        for t in self._threads:
            t.start()

    def stop(self) -> None:
        self.running = False
        for button in list(self.pressed):
            try:
                self.mouse.release(self._button(button))
            except Exception:
                pass
        self.pressed.clear()

        # Close sockets to wake loops if blocked
        for sock in [self._command_socket, self._discovery_socket]:
            if sock:
                try:
                    sock.close()
                except Exception:
                    pass

    def toggle_pause(self) -> bool:
        self.paused = not self.paused
        return self.paused


if __name__ == "__main__":
    server = AeroPadServer()
    server.start()
    print(f"AeroPad server running on {server.hostname}")
    for addr in server.ip_addresses:
        print(f"  -> {addr}:{COMMAND_PORT}")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        server.stop()
        print("Server stopped.")
