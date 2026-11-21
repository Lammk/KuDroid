#include "kudroid/kuart/LibCore.h"
#include "kudroid/kuart/DexClassLinker.h"
#include "kudroid/kuart/DexString.h"
#include "kudroid/kuart/Interpreter.h"
#include "kudroid/platform/WebViewHost.h"
#include <cstdlib>
#include <cstring>

namespace kudroid::kuart {
bool Invoke_android_webkit_WebView(Interpreter* interp, const char* name,
    const DexValue* args, size_t count, DexValue* result) {
    const auto string = [](const DexValue& value) -> const char* {
        return value.l ? reinterpret_cast<DexString*>(value.l)->utf8 : nullptr;
    };
    if (!std::strcmp(name, "nativeCreate") && count == 1) {
        *result = DexValue::Long(kudroid_webview_create(string(args[0]))); return true;
    }
    if (!std::strcmp(name, "nativeCommand") && count == 9) {
        kudroid_webview_command(args[0].j, args[1].i, args[2].j, string(args[3]), string(args[4]),
                               args[5].d, args[6].d, args[7].d, args[8].d);
        return true;
    }
    if ((!std::strcmp(name, "nativeCookies") && count == 2) ||
        (!std::strcmp(name, "nativeUserAgent") && count == 0)) {
        char* value = count ? kudroid_webview_cookies(args[0].j, string(args[1])) : kudroid_webview_user_agent();
        result->l = value ? reinterpret_cast<DexObject*>(interp->linker()->NewString(value)) : nullptr;
        std::free(value); return true;
    }
    return false;
}
}
