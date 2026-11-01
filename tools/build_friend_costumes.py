"""Pull and render all mapped friend costumes from the emulator."""
import csv
import os
import re
import shutil
import subprocess
import sys
import tarfile

ADB = r"D:\leidian\LDPlayer9\adb.exe"
DEVICE = "emulator-5554"
PACKAGE = "com.sqw.jwdzg.jwdzg_pz"
REPO = r"C:\Users\林\Documents\大掌柜"
ASSETS = r"C:\Users\林\Documents\大掌柜_assets"
ROOT = os.path.join(ASSETS, "clean", "costumes_v3")
INV = os.path.join(ROOT, "friend_costume_inventory.csv")
HOT = os.path.join(ASSETS, "hotupdate", "skins")
RENDER = os.path.join(ASSETS, "clean", "portraits_v3", "rendered", "friends_batch")
OUT = os.path.join(ROOT, "friends_cos")
TOOLS = os.path.dirname(os.path.abspath(__file__))
TEMP = r"C:\Users\林\AppData\Local\Temp\opencode"


def adb(*args):
    return subprocess.run([ADB, "-s", DEVICE] + list(args), capture_output=True,
                          text=True, encoding="utf-8", errors="replace")


def main():
    rows = list(csv.DictReader(open(INV, encoding="utf-8-sig")))
    rows = [r for r in rows if r["skin_id"]]
    out = adb("shell", "find", f"/data/data/{PACKAGE}/files/201/subpackages",
              "-name", "skeleton.json", "-o", "-name", "skeleton.skel")
    dev = set()
    for line in out.stdout.splitlines():
        m = re.search(r"/subpackages/(\d+)/", line)
        if m:
            dev.add(m.group(1))
    rows = [r for r in rows if r["skin_id"] in dev]
    ids = sorted({r["skin_id"] for r in rows}, key=int)
    print("friend costumes", len(rows), "unique skins", len(ids), flush=True)

    remote_tar = "/sdcard/friends_batch.tar.gz"
    local_tar = os.path.join(TEMP, "friends_batch.tar.gz")
    r = adb("shell", f"cd /data/data/{PACKAGE}/files/201/subpackages && tar czf {remote_tar} " + " ".join(ids))
    if r.returncode != 0:
        print("tar failed", r.stderr, flush=True)
        return
    adb("pull", remote_tar, local_tar)
    with tarfile.open(local_tar, "r:gz") as t:
        t.extractall(HOT)
    print("extracted", flush=True)

    # Normalize cn/spineSkin to spineSkin.
    for sid in ids:
        d = os.path.join(HOT, sid)
        src = os.path.join(d, "cn", "spineSkin")
        dst = os.path.join(d, "spineSkin")
        if os.path.isdir(src) and not os.path.isdir(dst):
            shutil.copytree(src, dst)

    os.makedirs(RENDER, exist_ok=True)
    cmd = [sys.executable, "-X", "utf8", os.path.join(TOOLS, "render_skin_spine.py"),
           "--ids"] + ids + ["--out", RENDER]
    subprocess.run(cmd, cwd=REPO, check=False)

    os.makedirs(OUT, exist_ok=True)
    by_skin = {r["skin_id"]: r for r in rows}
    coverage = []
    for skin, r in by_skin.items():
        src = os.path.join(RENDER, skin + ".png")
        dst = os.path.join(OUT, r["costume_id"] + ".png")
        if os.path.exists(src):
            shutil.copy2(src, dst)
            coverage.append([r["costume_id"], r["name"], r["quality"], r["friend_slug"],
                             r["friend_name"], r["beauty_id"], skin, "rendered", dst])
        else:
            coverage.append([r["costume_id"], r["name"], r["quality"], r["friend_slug"],
                             r["friend_name"], r["beauty_id"], skin, "render-missing", ""])
    cov_path = os.path.join(ROOT, "friends_coverage.csv")
    with open(cov_path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["costume_id", "name", "quality", "friend_slug", "friend_name",
                    "beauty_id", "skin_id", "status", "output"])
        w.writerows(coverage)
    print("rendered", sum(1 for c in coverage if c[7] == "rendered"),
          "missing", sum(1 for c in coverage if c[7] != "rendered"), flush=True)
    print(cov_path, flush=True)


if __name__ == "__main__":
    main()
