// The device identity the runtime reports to guest code.
















#ifndef KUDROID_DEVICE_PROFILE_H
#define KUDROID_DEVICE_PROFILE_H

// Keep in step with framework/android/os/Build.java, which cannot include this
// header. Build.VERSION.SDK_INT and Build.VERSION.RELEASE are the Java-visible
// copies of these two.
#define KUDROID_SDK_INT 29
#define KUDROID_SDK_INT_STR "29"
#define KUDROID_ANDROID_RELEASE "10"

// One device identity for build.prop, the property service and Build.java alike.
// The ABI list is what an app reads to decide which native library set to load, so
// it has to match what the ELF loader can actually map — arm64 only.
#define KUDROID_DEVICE_MODEL "KuDroid"
#define KUDROID_DEVICE_MANUFACTURER "KuDroid"
#define KUDROID_DEVICE_BRAND "kudroid"
#define KUDROID_DEVICE_NAME "kudroid"
#define KUDROID_DEVICE_BOARD "kudroid_arm64"
#define KUDROID_DEVICE_ABI "arm64-v8a"

#endif  // KUDROID_DEVICE_PROFILE_H
