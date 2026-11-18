#include "kudroid/kudroid_bridge.h"
#include "kudroid/KuArtRuntime.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    kudroid_set_documents_dir(argv[1]);
    const char* log = kudroid_run_apk("launch.fixture");
    const bool ready = kuart_is_ready() && log && std::strstr(log, "KuART ready:");
    JNIEnv* env = nullptr;
    JavaVM* vm = kuart_get_javavm();
    if (vm) kuart_get_env(vm, reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
    jclass activity = env ? env->FindClass("launch/fixture/JavaOnlyLaunchActivity") : nullptr;
    jfieldID created = activity ? env->GetStaticFieldID(activity, "created", "Z") : nullptr;
    jfieldID resumed = activity ? env->GetStaticFieldID(activity, "resumed", "Z") : nullptr;
    const bool launched = created && resumed && env->GetStaticBooleanField(activity, created) &&
                          env->GetStaticBooleanField(activity, resumed) && !env->ExceptionCheck();
    std::printf("%s DEX-only application reaches creation and resume\n", ready && launched ? "PASS" : "FAIL");
    if (!ready || !launched) std::fprintf(stderr, "%s\n", log ? log : "no launch log");
    std::free(const_cast<char*>(log));
    return ready && launched ? 0 : 1;
}
