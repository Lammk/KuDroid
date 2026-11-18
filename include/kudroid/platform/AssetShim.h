#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace kudroid {

struct SymbolEntry;

// Serve native asset APIs from extracted APK assets.




const SymbolEntry* get_asset_symbols(size_t* count);

// Thread-safe copy of the assets dir; prefer over the C accessor below.
std::string kudroid_get_assets_dir_cpp(void);

} // namespace

#ifdef __cplusplus
extern "C" {
#endif

// Set the directory containing extracted assets (called from kudroid_run_apk / kudroid_load_apk).
void kudroid_set_assets_dir(const char* dir);

// Resolve an exact package entry. The caller owns the malloc-allocated path;
// offset and length bound its bytes in the backing file.
int kudroid_package_resolve_bytes(const char* entry, char** outPath,
                                  int64_t* outOffset, int64_t* outLength);

// Get the directory containing extracted assets (or nullptr if not set).
// Legacy: valid only until the next set; C++ callers use the copy above.
const char* kudroid_get_assets_dir(void);

#ifdef __cplusplus
}
#endif
