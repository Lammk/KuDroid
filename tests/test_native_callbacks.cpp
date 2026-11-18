#include "kudroid/kuart/DexClassLinker.h"
#include "kudroid/kuart/DexJniEnv.h"
#include "kudroid/kuart/Interpreter.h"
#include "kudroid/kuart/VmLock.h"

#include <chrono>
#include <cstdio>
#include <fstream>
#include <future>
#include <iterator>
#include <thread>
#include <vector>

using namespace kudroid::kuart;
namespace {
bool called = false;
bool argumentsValid = false;
bool released = false;
std::thread worker;
void Callback(JNIEnv*, jclass, jboolean available, jboolean metered, jboolean constrained) {
    called = true;
    argumentsValid = available && !metered && constrained;
    std::promise<void> entered;
    auto completed = entered.get_future();
    worker = std::thread([signal = std::move(entered)]() mutable {
        VmLockGuard guard;
        signal.set_value();
    });
    released = VmLockDepth() == 0 &&
        completed.wait_for(std::chrono::seconds(1)) == std::future_status::ready;
}
}

int main(int argc, char** argv) {
    if (argc != 3) return 2;
    DexClassLinker linker;
    std::vector<std::vector<uint8_t>> files;
    std::string error;
    for (int i = 1; i < argc; ++i) {
        std::ifstream stream(argv[i], std::ios::binary);
        files.emplace_back(std::istreambuf_iterator<char>(stream), std::istreambuf_iterator<char>());
        if (files.back().empty() || !linker.AddDexFile(files.back().data(), files.back().size(), argv[i], &error)) return 2;
    }
    Interpreter interpreter(&linker);
    DexJniEnv jni(&linker, &interpreter);
    interpreter.set_jni_env(&jni);
    JNIEnv* env = jni.env();
    jclass klass = env->FindClass("NativeCallbackTests");
    char name[] = "nativeUpdateNetworkStatus", signature[] = "(ZZZ)V";
    JNINativeMethod method{name, signature, reinterpret_cast<void*>(&Callback)};
    if (!klass || env->RegisterNatives(klass, &method, 1) != JNI_OK) return 2;
    jmethodID callback = env->GetStaticMethodID(klass, name, signature);
    if (!callback) return 2;
    bool restored = false;
    {
        VmLockGuard outer;
        VmLockGuard inner;
        jvalue args[3]{};
        args[0].z = JNI_TRUE;
        args[2].z = JNI_TRUE;
        env->CallStaticVoidMethodA(klass, callback, args);
        restored = VmLockDepth() == 2;
    }
    if (worker.joinable()) worker.join();
    bool clear = !env->ExceptionCheck();
    std::printf("Native callbacks: called=%d arguments=%d released=%d restored=%d clear=%d\n",
                called, argumentsValid, released, restored, clear);
    return called && argumentsValid && released && restored && clear ? 0 : 1;
}
