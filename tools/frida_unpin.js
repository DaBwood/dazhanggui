// Frida SSL unpinning for 《叫我大掌柜》 (Cocos BoringSSL + Java SDKs).
// Run:
//   frida -U -f com.sqw.jwdzg.jwdzg_pz -l tools/frida_unpin.js --no-pause

function log(msg) {
    console.log("[unpin] " + msg);
}

function hookVerify(moduleName) {
    var names = ["SSL_get_verify_result", "X509_verify_cert", "SSL_CTX_set_verify", "SSL_CTX_set_custom_verify"];
    names.forEach(function (name) {
        var addr = Module.findExportByName(moduleName, name);
        if (!addr) {
            log("no " + name + " in " + (moduleName || "global"));
            return;
        }
        if (name === "SSL_get_verify_result") {
            Interceptor.attach(addr, { onLeave: function (ret) { ret.replace(0); } });
        } else if (name === "X509_verify_cert") {
            Interceptor.attach(addr, { onLeave: function (ret) { ret.replace(1); } });
        } else if (name === "SSL_CTX_set_verify") {
            Interceptor.attach(addr, { onEnter: function (args) { args[1] = ptr(0); } });
        } else {
            // BoringSSL custom verify callback: return 0 == ssl_verify_ok.
            Interceptor.attach(addr, {
                onEnter: function (args) {
                    var ok = new NativeCallback(function () { return 0; }, "int", ["pointer", "pointer"]);
                    args[2] = ok;
                },
            });
        }
        log("hooked " + name + " in " + (moduleName || "global"));
    });
}

hookVerify(null);
hookVerify("libcocos2djs.so");

Java.perform(function () {
    try {
        var X509TrustManager = Java.use("javax.net.ssl.X509TrustManager");
        var TrustManager = Java.registerClass({
            name: "com.dzg.UnpinTrustManager",
            implements: [X509TrustManager],
            methods: {
                checkClientTrusted: function (chain, authType) {},
                checkServerTrusted: function (chain, authType) {},
                getAcceptedIssuers: function () { return []; },
            },
        });
        log("registered Java trust manager");
    } catch (e) {
        log("java trust manager: " + e);
    }

    try {
        var HostnameVerifier = Java.use("javax.net.ssl.HostnameVerifier");
        var Verifier = Java.registerClass({
            name: "com.dzg.UnpinHostnameVerifier",
            implements: [HostnameVerifier],
            methods: {
                verify: function (hostname, session) { return true; },
            },
        });
        log("registered Java hostname verifier");
    } catch (e) {
        log("java hostname verifier: " + e);
    }
});

log("ready");
