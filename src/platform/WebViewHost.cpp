#include "kudroid/platform/WebViewHost.h"
#include "kudroid/VFSPathRemapper.h"
#include "kudroid/kudroid_bridge.h"
#include <atomic>
#include <deque>
#include <mutex>
#include <unordered_set>

extern "C" void kudroid_looper_wake_main(void);
namespace {
std::mutex hostMutex;
KuDroidWebViewHost host{};
std::atomic<int64_t> nextHandle{1};
std::mutex eventMutex;
std::unordered_set<int64_t> handles;
std::deque<kudroid::WebViewEvent> events;
KuDroidWebViewHost snapshot() {
    std::lock_guard<std::mutex> lock(hostMutex);
    return host;
}
bool contains(int64_t handle) {
    std::lock_guard<std::mutex> lock(eventMutex);
    return handles.count(handle) != 0;
}
}
extern "C" void kudroid_set_webview_host(const KuDroidWebViewHost* value) {
    std::lock_guard<std::mutex> lock(hostMutex);
    host = value ? *value : KuDroidWebViewHost{};
}
extern "C" int64_t kudroid_webview_create(const char* package_name) {
    const auto value = snapshot();
    if (!value.create || !package_name || !*package_name) return 0;
    const std::string package(package_name);
    if (package.front() == '.' || package.back() == '.' || package.find("..") != std::string::npos) return 0;
    for (const unsigned char* p = reinterpret_cast<const unsigned char*>(package_name); *p; ++p) {
        if (!((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
              (*p >= '0' && *p <= '9') || *p == '.' || *p == '_')) return 0;
    }
    const int64_t handle = nextHandle.fetch_add(1, std::memory_order_relaxed);
    if (handle <= 0) return 0;
    const std::string data = kudroid::VFSPathRemapper::getInstance().remap(
        (std::string("/data/data/") + package_name).c_str());
    const std::string logs = kudroid_current_log_dir();
    {
        std::lock_guard<std::mutex> lock(eventMutex);
        handles.insert(handle);
    }
    value.create(handle, package_name, data.c_str(), logs.c_str());
    if (!contains(handle) && value.command) value.command(handle, KD_WEB_DESTROY, 0, nullptr, nullptr, 0, 0, 0, 0);
    return handle;
}
extern "C" int kudroid_webview_active(int64_t handle) { return contains(handle); }
extern "C" void kudroid_webview_command(int64_t handle, int32_t command, int64_t request,
    const char* text, const char* detail, double a, double b, double c, double d) {
    if (!contains(handle)) return;
    const auto value = snapshot();
    if (command == KD_WEB_DESTROY) {
        std::lock_guard<std::mutex> lock(eventMutex);
        handles.erase(handle);
        for (auto it = events.begin(); it != events.end();) {
            if (it->handle == handle) it = events.erase(it); else ++it;
        }
    }
    if (value.command) value.command(handle, command, request, text, detail, a, b, c, d);
}
extern "C" char* kudroid_webview_cookies(int64_t handle, const char* url) {
    const auto value = snapshot();
    return contains(handle) && value.cookies ? value.cookies(handle, url) : nullptr;
}
extern "C" char* kudroid_webview_user_agent(void) {
    const auto value = snapshot();
    return value.user_agent ? value.user_agent() : nullptr;
}
extern "C" int kudroid_webview_post(int64_t handle, int32_t event, int64_t request,
    const char* text, const char* detail, int32_t flags) {
    {
        std::lock_guard<std::mutex> lock(eventMutex);
        if (!handles.count(handle) || events.size() >= 4096) return 0;
        events.push_back({handle, event, request, text ? text : "", detail ? detail : "", flags});
    }
    kudroid_looper_wake_main();
    return 1;
}
bool kudroid::webview_take(WebViewEvent* event) {
    std::lock_guard<std::mutex> lock(eventMutex);
    if (!event || events.empty()) return false;
    *event = std::move(events.front()); events.pop_front();
    return true;
}
extern "C" void kudroid_webview_reset(void) {
    {
        std::lock_guard<std::mutex> lock(eventMutex);
        handles.clear(); events.clear();
    }
    const auto value = snapshot();
    if (value.reset) value.reset();
}
