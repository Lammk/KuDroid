// Loading the frameworks the runtime ships in its own bundle.














#ifndef KUDROID_PLATFORM_BUNDLEDFRAMEWORK_H
#define KUDROID_PLATFORM_BUNDLEDFRAMEWORK_H

namespace kudroid {

// Dlopen a framework from the runtime's own bundle.









void* dlopen_bundled_framework(const char* relativePath, int flags);

}  // namespace

#endif  // KUDROID_PLATFORM_BUNDLEDFRAMEWORK_H
