#include "kudroid/platform/ProcessMaps.h"
#include "kudroid/elf_loader.hpp"

#include <algorithm>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <fcntl.h>
#include <fstream>
#include <limits>
#include <sstream>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>
#if defined(__APPLE__)
#include "kudroid/MachVmDecls.h"
#endif

namespace kudroid {
namespace {
struct NativeMapping {
    std::uintptr_t start, end;
    std::uint64_t offset;
    std::string permissions, device, inode, path;
};

void append_mapping(std::string& output, const NativeMapping& region,
                    const std::vector<GuestMappedSegment>& guests) {
    std::vector<std::uintptr_t> boundaries{region.start, region.end};
    for (const auto& guest : guests) {
        if (guest.start >= region.end || guest.end <= region.start) continue;
        boundaries.push_back(std::max(region.start, guest.start));
        boundaries.push_back(std::min(region.end, guest.end));
    }
    std::sort(boundaries.begin(), boundaries.end());
    boundaries.erase(std::unique(boundaries.begin(), boundaries.end()), boundaries.end());
    for (std::size_t i = 1; i < boundaries.size(); ++i) {
        const auto start = boundaries[i - 1], end = boundaries[i];
        auto offset = region.offset + start - region.start;
        std::string path = region.path;
        for (const auto& guest : guests) {
            if (start >= guest.start && start < guest.end && !guest.path.empty()) {
                offset = guest.offset + start - guest.start;
                path = guest.path;
                break;
            }
        }
        char prefix[160];
        std::snprintf(prefix, sizeof(prefix), "%llx-%llx %s %08llx %s %s",
            static_cast<unsigned long long>(start), static_cast<unsigned long long>(end),
            region.permissions.c_str(), static_cast<unsigned long long>(offset),
            region.device.c_str(), region.inode.c_str());
        output += prefix;
        if (!path.empty()) output += " " + path;
        output += '\n';
    }
}
}

std::string build_process_maps() {
    const auto guests = snapshot_guest_mappings();
    std::string output;
#if defined(__APPLE__)
    mach_vm_address_t cursor = 0;
    for (;;) {
        mach_vm_address_t address = cursor;
        mach_vm_size_t size = 0;
        kudroid_vm_region_basic_info_64_t info{};
        mach_msg_type_number_t count = KUDROID_VM_REGION_BASIC_INFO_64_COUNT;
        mach_port_t object = MACH_PORT_NULL;
        const auto result = mach_vm_region(mach_task_self(), &address, &size,
            KUDROID_VM_REGION_BASIC_INFO_64_FLAVOR,
            reinterpret_cast<vm_region_info_t>(&info), &count, &object);
        if (object != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), object);
        if (result != KERN_SUCCESS || size == 0 || address < cursor ||
            size > std::numeric_limits<mach_vm_address_t>::max() - address) break;
        std::string permissions = "---p";
        if (info.protection & VM_PROT_READ) permissions[0] = 'r';
        if (info.protection & VM_PROT_WRITE) permissions[1] = 'w';
        if (info.protection & VM_PROT_EXECUTE) permissions[2] = 'x';
        if (info.shared) permissions[3] = 's';
        append_mapping(output, {address, address + size, info.offset, permissions, "00:00", "0", {}}, guests);
        cursor = address + size;
    }
#else
    std::ifstream maps("/proc/self/maps");
    for (std::string line; std::getline(maps, line);) {
        NativeMapping region{};
        std::string addresses, offset;
        std::istringstream fields(line);
        if (!(fields >> addresses >> region.permissions >> offset >> region.device >> region.inode)) continue;
        const auto dash = addresses.find('-');
        if (dash == std::string::npos) continue;
        region.start = std::stoull(addresses.substr(0, dash), nullptr, 16);
        region.end = std::stoull(addresses.substr(dash + 1), nullptr, 16);
        region.offset = std::stoull(offset, nullptr, 16);
        std::getline(fields >> std::ws, region.path);
        append_mapping(output, region, guests);
    }
#endif
    return output;
}

bool refresh_process_maps_file(const std::string& path) {
    const std::string contents = build_process_maps();
    if (contents.empty()) { errno = EIO; return false; }
    std::string temporary = path + ".XXXXXX";
    const int fd = ::mkstemp(temporary.data());
    if (fd < 0) return false;
    std::size_t written = 0;
    while (written < contents.size()) {
        const auto count = ::write(fd, contents.data() + written, contents.size() - written);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) break;
        written += static_cast<std::size_t>(count);
    }
    const bool complete = written == contents.size() && ::fchmod(fd, 0444) == 0;
    const int saved = errno;
    const int closed = ::close(fd);
    if (complete && closed == 0 && ::rename(temporary.c_str(), path.c_str()) == 0) return true;
    const int error = complete ? errno : saved;
    ::unlink(temporary.c_str());
    errno = error;
    return false;
}
}
