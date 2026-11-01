"""Collect newly downloaded spineSkin packages from the emulator and render them.

Use after clicking costume cards in 绫罗宝鉴.  It only reads the device; it does
not tap the UI.

Usage:
  python tools/collect_new_spines.py
"""
import os
import re
import subprocess
import sys
import tarfile
import tempfile

ADB = r"D:\leidian\LDPlayer9\adb.exe"
DEVICE = "emulator-5554"
PACKAGE = "com.sqw.jwdzg.jwdzg_pz"
ASSETS = r"C:\Users\林\Documents\大掌柜_assets"
HOT = os.path.join(ASSETS, "hotupdate", "skins")
OUT = os.path.join(ASSETS, "clean", "portraits_v3", "rendered", "costumes_auto")
TOOLS = os.path.dirname(os.path.abspath(__file__))
TEMP = r"C:\Users\林\AppData\Local\Temp\opencode"


def adb(*args, check=False):
    cmd = [ADB, "-s", DEVICE] + list(args)
    return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                          errors="replace", check=check)


def device_spine_ids():
    r = adb("shell", "find",
            f"/data/data/{PACKAGE}/files/201/subpackages",
            "-name", "skeleton.json")
    ids = set()
    for line in r.stdout.splitlines():
        m = re.search(r"/subpackages/(\d+)/(?:cn/)?spineSkin/skeleton\.json$", line.strip())
        if m:
            ids.add(m.group(1))
    return ids


def local_spine_ids():
    ids = set()
    if not os.path.isdir(HOT):
        return ids
    for name in os.listdir(HOT):
        if name.isdigit() and os.path.exists(os.path.join(HOT, name, "spineSkin", "skeleton.json")):
            ids.add(name)
    return ids


def main():
    dev = device_spine_ids()
    loc = local_spine_ids()
    new = sorted(dev - loc, key=int)
    print("device", len(dev), "local", len(loc), "new", len(new))
    if not new:
        return
    print("new ids:", " ".join(new))

    tar_path = os.path.join(TEMP, "new_spines.tar.gz")
    remote_tar = "/sdcard/new_spines.tar.gz"
    quoted = " ".join(new)
    r = adb("shell", f"cd /data/data/{PACKAGE}/files/201/subpackages && tar czf {remote_tar} {quoted}")
    if r.returncode != 0:
        print("tar failed:", r.stderr)
        return
    adb("pull", remote_tar, tar_path)
    os.makedirs(HOT, exist_ok=True)
    with tarfile.open(tar_path, "r:gz") as t:
        t.extractall(HOT)
    print("extracted to", HOT)

    os.makedirs(OUT, exist_ok=True)
    cmd = [sys.executable, "-X", "utf8", os.path.join(TOOLS, "render_skin_spine.py"),
           "--ids"] + new + ["--out", OUT]
    subprocess.run(cmd, cwd=os.path.dirname(TOOLS), check=False)
    print("rendered to", OUT)


if __name__ == "__main__":
    main()
