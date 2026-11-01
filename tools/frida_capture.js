// Capture plaintext HTTP requests before TLS encryption.
// Run with tools/frida_capture.py (spawns the game).
//
// We hook SSL_write/SSL_read wherever they are exported or present in the
// symbol table.  Cocos often statically links BoringSSL, so module symbols are
// checked too.

const PACKAGE = "com.sqw.jwdzg.jwdzg_pz";
const MAX_LOG = 4096;

function log(obj) {
    send(obj);
}

function printable(buf, max) {
    try {
        const bytes = new Uint8Array(buf);
        let out = "";
        let run = "";
        const lim = Math.min(bytes.length, max || MAX_LOG);
        for (let i = 0; i < lim; i++) {
            const c = bytes[i];
            if (c >= 32 && c < 127) {
                run += String.fromCharCode(c);
            } else {
                if (run.length >= 4) out += run + "\n";
                run = "";
            }
        }
        if (run.length >= 4) out += run + "\n";
        return out;
    } catch (e) {
        return "";
    }
}

function interesting(text) {
    return /(^|\n)(GET|POST|PUT|HEAD|CONNECT) |Host:|cdn|ngty|\.png|\.webp|\.jpg|\.jpeg|Content-Type:\s*image|HTTP\/1\.[01] /i.test(text);
}

function hookAddr(addr, name, kind) {
    if (!addr || addr.isNull()) return;
    try {
        Interceptor.attach(addr, {
            onEnter: function (args) {
                try {
                    if (kind === "write") {
                        const n = args[2].toInt32();
                        if (n <= 0 || n > 1024 * 1024) return;
                        const text = printable(args[1].readByteArray(n), MAX_LOG);
                        if (text && interesting(text)) {
                            log({ type: "ssl_write", fn: name, text: text });
                        }
                    } else {
                        const n = args[2].toInt32();
                        if (n <= 0 || n > 1024 * 1024) return;
                        const text = printable(args[1].readByteArray(n), MAX_LOG);
                        if (text && interesting(text)) {
                            log({ type: "ssl_read", fn: name, text: text });
                        }
                    }
                } catch (e) {}
            },
        });
        log({ type: "hook", fn: name, addr: addr.toString() });
    } catch (e) {
        log({ type: "hook_error", fn: name, error: String(e) });
    }
}

const seen = {};

function hookModule(mod) {
    let syms = [];
    try {
        syms = mod.enumerateSymbols();
    } catch (e) {
        return;
    }
    for (const s of syms) {
        if (s.name === "SSL_write" || s.name.indexOf("SSL_write") >= 0) {
            const key = s.address.toString();
            if (!seen[key]) {
                seen[key] = true;
                hookAddr(s.address, mod.name + "!" + s.name, "write");
            }
        }
        if (s.name === "SSL_read" || s.name.indexOf("SSL_read") >= 0) {
            const key = s.address.toString();
            if (!seen[key]) {
                seen[key] = true;
                hookAddr(s.address, mod.name + "!" + s.name, "read");
            }
        }
    }
}

// Exported symbols first (libssl, libcrypto, libcocos2djs).
for (const name of ["SSL_write", "SSL_read", "SSL_write_ex", "SSL_read_ex"]) {
    const addr = Module.findExportByName(null, name);
    if (addr) {
        const key = addr.toString();
        if (!seen[key]) {
            seen[key] = true;
            hookAddr(addr, name, name.indexOf("write") >= 0 ? "write" : "read");
        }
    }
}

// Statically linked BoringSSL: scan relevant modules' symbol tables.
for (const mod of Process.enumerateModules()) {
    if (/cocos|ssl|crypto|curl|http|network|net|quic|mbed/i.test(mod.name)) {
        hookModule(mod);
    }
}

// DNS is useful even if TLS symbols are stripped.
try {
    const gai = Module.findExportByName(null, "getaddrinfo");
    if (gai) {
        Interceptor.attach(gai, {
            onEnter: function (args) {
                try {
                    this.host = args[0].isNull() ? "" : args[0].readUtf8String();
                } catch (e) {
                    this.host = "";
                }
            },
            onLeave: function () {
                if (this.host && /cdn|ngty|dzg|sqw|37|2ed5/i.test(this.host)) {
                    log({ type: "dns", host: this.host });
                }
            },
        });
        log({ type: "hook", fn: "getaddrinfo", addr: gai.toString() });
    }
} catch (e) {}

log({ type: "ready", pid: Process.id, arch: Process.arch, modules: Process.enumerateModules().length });
