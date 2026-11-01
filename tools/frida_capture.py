"""Spawn the game with frida_capture.js and print plaintext HTTP traffic.

Usage:
    python tools/frida_capture.py

Keep this window open while opening the costume gallery in the emulator.
Press Ctrl+C to stop.
"""
import json
import os
import sys
import time

import frida

PACKAGE = "com.sqw.jwdzg.jwdzg_pz"
HERE = os.path.dirname(os.path.abspath(__file__))


def on_message(message, data):
    if message.get("type") == "send":
        payload = message.get("payload", {})
        kind = payload.get("type")
        if kind == "ssl_write":
            print("\n=== SSL_WRITE %s ===" % payload.get("fn"))
            print(payload.get("text", ""))
        elif kind == "ssl_read":
            text = payload.get("text", "")
            if "Content-Type: image" in text or "HTTP/1." in text:
                print("\n=== SSL_READ %s ===" % payload.get("fn"))
                print(text)
        elif kind == "dns":
            print("[dns] %s" % payload.get("host"))
        else:
            print("[frida] %s" % json.dumps(payload, ensure_ascii=False))
    else:
        print("[frida:%s] %s" % (message.get("type"), message))


def main():
    device = frida.get_usb_device(timeout=10)
    try:
        device.kill(PACKAGE)
        time.sleep(1)
    except Exception as e:
        print("[runner] kill skipped: %s" % e)

    pid = device.spawn([PACKAGE])
    print("[runner] spawned pid %s" % pid)
    session = device.attach(pid)
    script_path = os.path.join(HERE, "frida_capture.js")
    with open(script_path, encoding="utf-8") as f:
        source = f.read()
    script = session.create_script(source)
    script.on("message", on_message)
    script.load()
    device.resume(pid)
    print("[runner] resumed; open 门客换装 → 金雷 in the game now")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[runner] stopping")
        try:
            session.detach()
        except Exception:
            pass


if __name__ == "__main__":
    main()
