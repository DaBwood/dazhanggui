"""Write the friend costume manifest and sync images into the project."""
import csv
import os
import shutil

ROOT = r"C:\Users\林\Documents\大掌柜_assets\clean\costumes_v3"
COV = os.path.join(ROOT, "friends_coverage.csv")
SRC = os.path.join(ROOT, "friends_cos")
DST = r"C:\Users\林\Documents\大掌柜\assets\portraits\friends_cos"
MAN = os.path.join(ROOT, "friends_cos_manifest.csv")


def main():
    rows = list(csv.DictReader(open(COV, encoding="utf-8-sig")))
    os.makedirs(DST, exist_ok=True)
    manifest = []
    for r in rows:
        path = r["output"]
        ok = r["status"] in ("rendered", "shared-patron", "base-portrait") and os.path.exists(path)
        if ok:
            shutil.copy2(path, os.path.join(DST, r["costume_id"] + ".png"))
        manifest.append([r["costume_id"], r["name"], r["quality"], r["friend_slug"],
                         r["friend_name"], r["beauty_id"], r["skin_id"],
                         r["status"], path if ok else ""])
    with open(MAN, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.writer(f)
        w.writerow(["costume_id", "name", "quality", "friend_slug", "friend_name",
                    "beauty_id", "skin_id", "source", "output"])
        w.writerows(manifest)
    print("manifest", len(manifest), "synced", sum(1 for r in manifest if r[8]))
    print(MAN)
    print(DST)


if __name__ == "__main__":
    main()
