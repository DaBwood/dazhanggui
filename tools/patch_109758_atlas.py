import os

from PIL import Image

TARGET = r"C:\Users\林\Documents\大掌柜_assets\hotupdate\skins\109758\spineSkin"
ATLAS = os.path.join(TARGET, "skeleton.atlas")
REGION = "3qi_22"


def main():
    text = open(ATLAS, encoding="utf-8").read()
    if "\n" + REGION + "\n" in "\n" + text:
        print("already patched:", REGION)
        return
    Image.new("RGBA", (16, 16), (0, 0, 0, 0)).save(os.path.join(TARGET, "patch.png"))
    block = [
        "patch.png",
        "size: 16,16",
        "format: RGBA8888",
        "filter: Linear,Linear",
        "repeat: none",
        REGION,
        "  rotate: false",
        "  xy: 0,0",
        "  size: 16,16",
        "  orig: 16,16",
        "  offset: 0,0",
        "  index: -1",
    ]
    with open(ATLAS, "a", encoding="utf-8") as f:
        f.write("\n" + "\n".join(block) + "\n")
    print("patched", ATLAS, REGION)


if __name__ == "__main__":
    main()
