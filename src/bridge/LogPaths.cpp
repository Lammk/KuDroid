#include "LogPaths.h"

#include <atomic>
#include <filesystem>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace {
struct Paths {
    std::string documents;
    std::string root;
    std::string host;
    std::string current;
};

static_assert(std::atomic<const Paths*>::is_always_lock_free,
              "Signal handlers require lock-free path reads");
std::atomic<const Paths*> selected{nullptr};
std::mutex pathsMutex;

void publish(Paths paths) {
    // Retain immutable snapshots while signal handlers or writers may hold them.
    static auto* snapshots = new std::vector<std::unique_ptr<Paths>>;
    for (const auto& item : *snapshots) {
        if (item->documents == paths.documents && item->root == paths.root &&
            item->host == paths.host && item->current == paths.current) {
            selected.store(item.get(), std::memory_order_release);
            return;
        }
    }
    auto next = std::make_unique<Paths>(std::move(paths));
    const auto* pointer = next.get();
    snapshots->push_back(std::move(next));
    selected.store(pointer, std::memory_order_release);
}

bool prepareDirectory(const std::filesystem::path& path) {
    std::error_code error;
    auto status = std::filesystem::symlink_status(path, error);
    if (std::filesystem::is_symlink(status)) return false;
    error.clear();
    std::filesystem::create_directories(path, error);
    if (error) return false;
    status = std::filesystem::symlink_status(path, error);
    return !error && std::filesystem::is_directory(status);
}

bool validPackage(const char* package) {
    if (!package || !*package) return false;
    if (std::string(package) == "_host") return false;
    bool first = true;
    size_t length = 0;
    for (const char* p = package; *p; ++p) {
        if (++length > 255) return false;
        const bool letter = (*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z');
        const bool digit = *p >= '0' && *p <= '9';
        if (*p == '.') {
            if (first) return false;
            first = true;
        } else {
            if (!letter && *p != '_' && (!digit || first)) return false;
            first = false;
        }
    }
    return !first;
}
}  // namespace

extern "C" const char* kudroid_current_log_dir(void) {
    const auto* paths = selected.load(std::memory_order_acquire);
    return paths ? paths->current.c_str() : "";
}

extern "C" const char* kudroid_host_log_dir(void) {
    const auto* paths = selected.load(std::memory_order_acquire);
    return paths ? paths->host.c_str() : "";
}

const char* bridgeDocumentsDirectory(void) {
    const auto* paths = selected.load(std::memory_order_acquire);
    return paths ? paths->documents.c_str() : "";
}

bool bridgeConfigureLogPaths(const char* documents, const char* root) {
    if (!documents || !*documents || !root || !*root) return false;
    const std::filesystem::path logRoot(root);
    if (!logRoot.is_absolute() || !std::filesystem::path(documents).is_absolute()) return false;
    if (logRoot.string().size() > 700 || std::string(documents).size() > 1000) return false;
    std::lock_guard<std::mutex> lock(pathsMutex);
    const auto* current = selected.load(std::memory_order_acquire);
    if (current && current->documents == documents && current->root == root) return false;
    const auto host = logRoot / "_host";
    if (!prepareDirectory(logRoot) || !prepareDirectory(host)) return false;
    publish({documents, root, host.string(), host.string()});
    return true;
}

bool bridgeSelectAppLogDirectory(const char* package) {
    if (!validPackage(package)) return false;
    std::lock_guard<std::mutex> lock(pathsMutex);
    const auto* current = selected.load(std::memory_order_acquire);
    if (!current || current->root.empty()) return false;
    const auto directory = std::filesystem::path(current->root) / package;
    if (!prepareDirectory(current->root) || !prepareDirectory(directory)) return false;
    publish({current->documents, current->root, current->host, directory.string()});
    return true;
}

void bridgeRememberDocumentsDirectory(const char* documents) {
    if (!documents || !*documents) return;
    std::lock_guard<std::mutex> lock(pathsMutex);
    const auto* current = selected.load(std::memory_order_acquire);
    if (current && !current->documents.empty()) return;
    const Paths previous = current ? *current : Paths{};
    publish({documents, previous.root, previous.host, previous.current});
}

void bridgeClearCurrentLogFiles(void) {
    std::lock_guard<std::mutex> lock(pathsMutex);
    const auto* current = selected.load(std::memory_order_acquire);
    if (!current || current->current.empty()) return;
    std::error_code error;
    const auto status = std::filesystem::symlink_status(current->current, error);
    if (error || !std::filesystem::is_directory(status)) return;
    std::filesystem::directory_iterator iterator(current->current, error), end;
    while (!error && iterator != end) {
        const auto entryStatus = iterator->symlink_status(error);
        if (error) break;
        if (!std::filesystem::is_directory(entryStatus)) {
            std::filesystem::remove(iterator->path(), error);
            if (error) break;
        }
        iterator.increment(error);
    }
}

bool bridgeValidPackageIdentifier(const char* package) { return validPackage(package); }
