#pragma once
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum KuDroidWebCommand {
    KD_WEB_LOAD = 1, KD_WEB_HTML, KD_WEB_SETTINGS, KD_WEB_FRAME,
    KD_WEB_VISIBLE, KD_WEB_BACK, KD_WEB_FORWARD, KD_WEB_RELOAD,
    KD_WEB_STOP, KD_WEB_DESTROY, KD_WEB_EVALUATE, KD_WEB_DECIDE,
    KD_WEB_COOKIE_SET, KD_WEB_COOKIE_CLEAR, KD_WEB_COOKIE_FLUSH, KD_WEB_COOKIE_POLICY
};
enum KuDroidWebEvent {
    KD_WEB_NAVIGATE = 1, KD_WEB_STARTED, KD_WEB_FINISHED, KD_WEB_ERROR,
    KD_WEB_HISTORY, KD_WEB_TITLE, KD_WEB_HTTP_ERROR, KD_WEB_PROGRESS,
    KD_WEB_CLOSED, KD_WEB_EVALUATED, KD_WEB_COOKIES, KD_WEB_USER_AGENT,
    KD_WEB_CONSOLE
};
typedef struct KuDroidWebViewHost {
    void (*create)(int64_t handle, const char* package_name, const char* data_dir, const char* log_dir);
    void (*command)(int64_t handle, int32_t command, int64_t request,
                    const char* text, const char* detail, double a, double b, double c, double d);
    char* (*cookies)(int64_t handle, const char* url);
    char* (*user_agent)(void);
    void (*reset)(void);
} KuDroidWebViewHost;

void kudroid_set_webview_host(const KuDroidWebViewHost* host);
int64_t kudroid_webview_create(const char* package_name);
int kudroid_webview_active(int64_t handle);
void kudroid_webview_command(int64_t handle, int32_t command, int64_t request,
                            const char* text, const char* detail, double a, double b, double c, double d);
char* kudroid_webview_cookies(int64_t handle, const char* url);
char* kudroid_webview_user_agent(void);
int kudroid_webview_post(int64_t handle, int32_t event, int64_t request,
                        const char* text, const char* detail, int32_t flags);
void kudroid_webview_reset(void);

#ifdef __cplusplus
}
#include <string>
namespace kudroid {
struct WebViewEvent {
    int64_t handle = 0;
    int32_t event = 0;
    int64_t request = 0;
    std::string text;
    std::string detail;
    int32_t flags = 0;
};
bool webview_take(WebViewEvent* event);
}
#endif
