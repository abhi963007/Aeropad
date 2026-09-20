"""Automated PyInstaller compilation script for AeroPad Windows System Tray Executable.

Generates: desktop_exe/dist/AeroPadServer.exe
"""

import os
import shutil
import sys
from PIL import Image
import PyInstaller.__main__


def ensure_icon(base_dir: str) -> str:
    ico_path = os.path.join(base_dir, "aeropad_icon.ico")
    if os.path.exists(ico_path):
        return ico_path

    source_png = os.path.join(base_dir, "..", "assets", "app icon.png")
    if not os.path.exists(source_png):
        source_png = os.path.join(base_dir, "..", "assets", "splash_screen.png")

    if os.path.exists(source_png):
        print(f"Generating icon from {source_png}...")
        img = Image.open(source_png).convert("RGBA")
        img.save(
            ico_path,
            format="ICO",
            sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
        )
    return ico_path


def build() -> None:
    base_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(base_dir)

    ico_path = ensure_icon(base_dir)
    tray_script = os.path.join(base_dir, "aeropad_tray.py")
    dist_dir = os.path.join(base_dir, "dist")
    work_dir = os.path.join(base_dir, "build")

    print(f"Starting AeroPad standalone Windows .exe build...")
    print(f"Entry script: {tray_script}")
    print(f"Target dist: {dist_dir}")

    pyinstaller_args = [
        tray_script,
        "--name=AeroPadServer",
        "--onefile",
        "--noconsole",
        f"--icon={ico_path}",
        f"--add-data={ico_path};.",
        f"--distpath={dist_dir}",
        f"--workpath={work_dir}",
        f"--specpath={base_dir}",
        "--clean",
        "--hidden-import=pystray",
        "--hidden-import=PIL",
        "--hidden-import=pynput",
        "--hidden-import=pynput.keyboard",
        "--hidden-import=pynput.mouse",
        "--noconfirm",
    ]

    PyInstaller.__main__.run(pyinstaller_args)

    exe_path = os.path.join(dist_dir, "AeroPadServer.exe")
    if os.path.exists(exe_path):
        size_mb = os.path.getsize(exe_path) / (1024 * 1024)
        print("\n" + "=" * 60)
        print(" BUILD SUCCESSFUL!")
        print(f" Standalone Windows Executable: {exe_path}")
        print(f" File size: {size_mb:.2f} MB")
        print("=" * 60)
    else:
        print("\nBuild completed, but executable was not found.")
        sys.exit(1)


if __name__ == "__main__":
    build()
