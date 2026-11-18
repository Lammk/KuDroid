#include <cstdio>
#include <cstdint>

extern "C" {
int64_t kudroid_surface_set_frame(int64_t, int, int, int, int);
int bionic_ANativeWindow_setBuffersGeometry(void*, int, int, int);
int bionic_ANativeWindow_getWidth(void*);
int bionic_ANativeWindow_getHeight(void*);
void bionic_ANativeWindow_release(void*);
void* bionic_ANativeWindow_fromSurface(void*, void*);
void kudroid_gpu_rebind_native_windows(void*, int, int);
void kudroid_gpu_resize_native_windows(void*, int, int, int, int);
}
extern void* g_metalLayer;
extern int g_metalLayerWidth;
extern int g_metalLayerHeight;

int main() {
    int failures = 0;
    auto check = [&](bool value, const char* message) {
        std::printf("%s %s\n", value ? "OK" : "FAIL", message);
        failures += !value;
    };
    int64_t handle = kudroid_surface_set_frame(0, 10, 20, 640, 360);
    void* window = reinterpret_cast<void*>(handle);
    check(bionic_ANativeWindow_setBuffersGeometry(window, 1280, 720, 0) == 0,
          "explicit buffer dimensions are accepted");
    kudroid_surface_set_frame(handle, 30, 40, 800, 600);
    check(bionic_ANativeWindow_getWidth(window) == 1280 && bionic_ANativeWindow_getHeight(window) == 720,
          "layout changes preserve explicit buffer dimensions");
    check(bionic_ANativeWindow_setBuffersGeometry(window, 0, 0, 0) == 0 &&
          bionic_ANativeWindow_getWidth(window) == 800 && bionic_ANativeWindow_getHeight(window) == 600,
          "zero dimensions restore the current layout size");
    kudroid_surface_set_frame(handle, 0, 0, 1024, 768);
    check(bionic_ANativeWindow_getWidth(window) == 1024 && bionic_ANativeWindow_getHeight(window) == 768,
          "default buffers follow later layout changes");
    check(bionic_ANativeWindow_setBuffersGeometry(window, 256, 0, 0) < 0 &&
          bionic_ANativeWindow_getWidth(window) == 1024,
          "a partial size is rejected without changing geometry");
    check(bionic_ANativeWindow_setBuffersGeometry(window, -1, 200, 0) < 0,
          "negative dimensions are rejected");
    bionic_ANativeWindow_release(window);

    g_metalLayer = reinterpret_cast<void*>(1);
    g_metalLayerWidth = 640;
    g_metalLayerHeight = 360;
    window = bionic_ANativeWindow_fromSurface(nullptr, nullptr);
    bionic_ANativeWindow_setBuffersGeometry(window, 640, 360, 0);
    kudroid_gpu_resize_native_windows(g_metalLayer, 640, 360, 800, 600);
    check(bionic_ANativeWindow_getWidth(window) == 640 && bionic_ANativeWindow_getHeight(window) == 360,
          "an explicit size equal to the old layout survives rotation");
    kudroid_gpu_rebind_native_windows(reinterpret_cast<void*>(2), 1024, 768);
    check(bionic_ANativeWindow_getWidth(window) == 640 && bionic_ANativeWindow_getHeight(window) == 360,
          "layer replacement preserves explicit buffer dimensions");
    bionic_ANativeWindow_setBuffersGeometry(window, 0, 0, 0);
    kudroid_gpu_resize_native_windows(reinterpret_cast<void*>(2), 640, 360, 1280, 720);
    check(bionic_ANativeWindow_getWidth(window) == 1280 && bionic_ANativeWindow_getHeight(window) == 720,
          "default buffers follow host rotation after a reset");
    std::printf("Native window geometry: %d failures\n", failures);
    return failures ? 1 : 0;
}
