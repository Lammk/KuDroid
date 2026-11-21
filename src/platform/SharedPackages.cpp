#include "kudroid/platform/SharedPackages.h"
#include "kudroid/APKExtractor.h"
#include "kudroid/ApkSigning.h"
#include "kudroid/ResourceTable.h"
#include "kudroid/VFSPathRemapper.h"
#include "kudroid/platform/AssetShim.h"

#include <atomic>
#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <sstream>

namespace kudroid {
namespace {
std::atomic<bool> enabled{false};
std::atomic<uint32_t> generation{0};
std::string Quote(const std::string& value) {
    const char* digits = "0123456789abcdef";
    std::string result = "\"";
    for (unsigned char c : value) {
        if (c == '"' || c == '\\') { result += '\\'; result += c; }
        else if (c < 32) { result += "\\u00"; result += digits[c >> 4]; result += digits[c & 15]; }
        else result += c;
    }
    return result + '"';
}
bool Valid(const std::string& name) {
    if (name.empty() || name.size() > 255) return false;
    for (unsigned char c : name) if (!(c == '.' || c == '_' ||
        (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))) return false;
    return name != "." && name != "..";
}
bool Shared(const std::filesystem::path& path) {
    std::ifstream marker(path / ".kudroid-shared-service");
    std::string kind; std::getline(marker, kind);
    return kind == "microg";
}
std::vector<uint8_t> Read(const std::filesystem::path& path, size_t maximum) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    const auto size = file.tellg();
    if (size < 0 || static_cast<uint64_t>(size) > maximum) return {};
    std::vector<uint8_t> bytes(static_cast<size_t>(size));
    file.seekg(0);
    if (!file.read(reinterpret_cast<char*>(bytes.data()), bytes.size())) return {};
    return bytes;
}
std::string Hex(const std::vector<uint8_t>& bytes) {
    const char* digits = "0123456789abcdef";
    std::string value; value.reserve(bytes.size() * 2);
    for (uint8_t c : bytes) { value += digits[c >> 4]; value += digits[c & 15]; }
    return value;
}
std::string Strings(const std::vector<std::string>& values) {
    std::string result = "[";
    for (size_t i = 0; i < values.size(); ++i) { if (i) result += ','; result += Quote(values[i]); }
    return result + ']';
}
std::string Metadata(const std::vector<MetaDataEntry>& values) {
    std::string result = "[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i) result += ',';
        result += "{\"name\":" + Quote(values[i].name) + ",\"value\":" + Quote(values[i].value) +
            ",\"type\":" + std::to_string(values[i].valueType) +
            ",\"resource\":" + (values[i].isResource ? "true" : "false") + '}';
    }
    return result + ']';
}
std::string FakeSignature(const ManifestInfo& manifest, const std::filesystem::path& directory) {
    for (const auto& metadata : manifest.applicationMetaData) {
        if (metadata.name != "fake-signature") continue;
        if (!metadata.isResource && metadata.valueType != 1) return metadata.value;
        const ScopedAssetDirectory assets((directory / "assets").string());
        char* path = nullptr; int64_t offset = 0, length = 0;
        if (kudroid_package_resolve_bytes("resources.arsc", &path, &offset, &length) <= 0 ||
            !path || length <= 0 || length > (32u << 20)) { std::free(path); return {}; }
        std::ifstream file(path, std::ios::binary); std::free(path);
        std::vector<uint8_t> bytes(length); file.seekg(offset);
        if (!file.read(reinterpret_cast<char*>(bytes.data()), bytes.size())) return {};
        std::vector<std::string> values;
        if (!resource_resolve_strings(bytes, {metadata.value}, "", &values)) return {};
        return values.empty() ? std::string() : values.front();
    }
    return {};
}
}

void configure_shared_packages(bool value) {
    enabled.store(value, std::memory_order_release);
    generation.fetch_add(1, std::memory_order_release);
}
bool shared_packages_enabled() { return enabled.load(std::memory_order_acquire); }
uint32_t shared_packages_generation() { return generation.load(std::memory_order_acquire); }

std::vector<std::string> shared_package_directories() {
    std::vector<std::string> result;
    if (!shared_packages_enabled()) return result;
    const auto root = std::filesystem::path(VFSPathRemapper::getInstance().androidRoot()) / "data/app";
    std::error_code error;
    for (const auto& entry : std::filesystem::directory_iterator(root, error)) {
        if (entry.is_directory(error) && !entry.is_symlink(error) && Valid(entry.path().filename().string()) &&
            Shared(entry.path())) result.push_back(entry.path().string());
    }
    std::sort(result.begin(), result.end());
    return result;
}

std::string installed_package_record(const std::string& package, bool currentPackage) {
    if (!Valid(package)) return {};
    const auto directory = std::filesystem::path(VFSPathRemapper::getInstance().androidRoot()) / "data/app" / package;
    std::error_code error;
    if (std::filesystem::is_symlink(directory, error)) return {};
    const bool shared = Shared(directory);
    if (shared && !shared_packages_enabled() && !currentPackage) return {};
    const auto bytes = Read(directory / "AndroidManifest.xml", 16u << 20);
    if (bytes.empty()) return {};
    auto manifest = bytes.size() >= 4 && bytes[0] == 3 && bytes[1] == 0 && bytes[2] == 8 && bytes[3] == 0
        ? APKExtractor::parse_manifest(bytes.data(), bytes.size())
        : APKExtractor::parse_manifest_text(reinterpret_cast<const char*>(bytes.data()), bytes.size());
    if (manifest.packageName != package) return {};
    const auto certificates = read_apk_signing_certificates((directory / "base.apk").string());
    std::vector<std::string> signatures;
    for (const auto& certificate : certificates) signatures.push_back(Hex(certificate));
    const std::string fakeSignature = shared ? FakeSignature(manifest, directory) : "";
    const bool spoof = shared && shared_packages_enabled() && !fakeSignature.empty() &&
        std::find(manifest.requestedPermissions.begin(), manifest.requestedPermissions.end(),
                  "android.permission.FAKE_PACKAGE_SIGNATURE") != manifest.requestedPermissions.end();
    std::string json = "{\"package\":" + Quote(package) + ",\"versionName\":" + Quote(manifest.versionName) +
        ",\"versionCode\":" + Quote(manifest.versionCode) + ",\"application\":" + Quote(manifest.appClass) +
        ",\"componentFactory\":" + Quote(manifest.appComponentFactory) + ",\"shared\":" + (shared ? "true" : "false") +
        ",\"signatures\":" + Strings(signatures) + ",\"fakeSignature\":" + Quote(fakeSignature) +
        ",\"spoofGranted\":" + (spoof ? "true" : "false") +
        ",\"targetSdk\":" + std::to_string(manifest.targetSdkVersion) +
        ",\"enabled\":" + (manifest.applicationEnabled ? "true" : "false") +
        ",\"process\":" + Quote(manifest.applicationProcess) +
        ",\"metadata\":" + Metadata(manifest.applicationMetaData) +
        ",\"permissions\":" + Strings(manifest.requestedPermissions) + ",\"services\":[";
    for (size_t i = 0; i < manifest.services.size(); ++i) {
        const auto& service = manifest.services[i]; if (i) json += ',';
        json += "{\"name\":" + Quote(service.name) + ",\"enabled\":" + (service.enabled ? "true" : "false") +
            ",\"exported\":" + (service.exported ? "true" : "false") + ",\"permission\":" + Quote(service.permission) +
            ",\"metadata\":" + Metadata(service.metaData) + ",\"filters\":[";
        for (size_t f = 0; f < service.intentFilters.size(); ++f) {
            const auto& filter = service.intentFilters[f]; if (f) json += ',';
            json += "{\"actions\":" + Strings(filter.actions) + ",\"categories\":" + Strings(filter.categories) +
                ",\"priority\":" + std::to_string(filter.priority) + ",\"hasData\":" + (filter.hasData ? "true" : "false") + '}';
        }
        json += "]}";
    }
    json += "],\"providers\":[";
    for (size_t i = 0; i < manifest.providers.size(); ++i) {
        const auto& provider = manifest.providers[i]; if (i) json += ',';
        json += "{\"name\":" + Quote(provider.name) + ",\"authority\":" + Quote(provider.authorities) +
            ",\"enabled\":" + (provider.enabled ? "true" : "false") + ",\"exported\":" + (provider.exported ? "true" : "false") +
            ",\"process\":" + Quote(provider.processName) + ",\"initOrder\":" + std::to_string(provider.initOrder) +
            ",\"readPermission\":" + Quote(provider.readPermission) + ",\"writePermission\":" + Quote(provider.writePermission) +
            ",\"grantUriPermissions\":" + (provider.grantUriPermissions ? "true" : "false") +
            ",\"metadata\":" + Metadata(provider.metaData) +
            ",\"directBootAware\":" + (provider.directBootAware ? "true" : "false") + '}';
    }
    return json + "]}";
}

std::string shared_package_records() {
    std::string result = "["; bool first = true;
    for (const auto& path : shared_package_directories()) {
        const auto record = installed_package_record(std::filesystem::path(path).filename().string(), false);
        if (record.empty()) continue;
        if (!first) result += ',';
        first = false;
        result += record;
    }
    return result + ']';
}
}

extern "C" void kudroid_configure_shared_packages(int enabled) {
    kudroid::configure_shared_packages(enabled != 0);
}

extern "C" const char* kudroid_android_root_path() {
    return strdup(kudroid::VFSPathRemapper::getInstance(false).androidRoot().c_str());
}
