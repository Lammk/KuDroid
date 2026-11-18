#include "kudroid/elf_loader.hpp"
#include "kudroid/platform/ProcessMaps.h"

#include <cstdio>
#include <cstdlib>
#include <elf.h>
#include <fcntl.h>
#include <fstream>
#include <sstream>
#include <string>
#include <sys/mman.h>
#include <unistd.h>

static int failures = 0;
static void check(bool ok, const char* label) {
    std::printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}
static std::string permissions(const std::string& maps, std::uintptr_t address) {
    std::istringstream input(maps);
    for (std::string line; std::getline(input, line);) {
        if (line.find("libfixture.so") == std::string::npos) continue;
        unsigned long long start, end;
        char mode[5]{};
        if (std::sscanf(line.c_str(), "%llx-%llx %4s", &start, &end, mode) == 3 &&
            address >= start && address < end) return mode;
    }
    return {};
}
static std::string read_file(const std::string& path) {
    std::ifstream input(path);
    return {std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
}
static std::string read_fd(int fd) {
    std::string result;
    char buffer[4096];
    for (ssize_t count; (count = ::read(fd, buffer, sizeof(buffer))) > 0;) result.append(buffer, count);
    return result;
}
int main() {
    const auto page = static_cast<std::size_t>(::sysconf(_SC_PAGESIZE));
    void* mapping = ::mmap(nullptr, page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (mapping == MAP_FAILED) return 2;
    const auto address = reinterpret_cast<std::uintptr_t>(mapping);
    kudroid::kudroid_register_guest_module(mapping, page, "/data/app/example/libfixture.so");
    {
        Elf64_Phdr header{};
        header.p_type = PT_LOAD;
        header.p_flags = PF_R | PF_X;
        header.p_memsz = page;
        kudroid::kudroid_register_guest_phdrs(mapping, &header, 1);
    }
    std::string maps = kudroid::build_process_maps();
    check(permissions(maps, address) == "rw-p", "mapped library uses real address and current permissions");
    check(maps.find("/system/bin/app_process64") == std::string::npos, "invented process mappings are absent");
    check(::mprotect(mapping, page, PROT_READ) == 0, "test mapping protection changes");
    check(permissions(kudroid::build_process_maps(), address) == "r--p", "snapshot observes protection changes");

    char directory[] = "/tmp/kudroid-process-maps-XXXXXX";
    if (!::mkdtemp(directory)) return 2;
    const std::string path = std::string(directory) + "/maps";
    check(kudroid::refresh_process_maps_file(path), "process maps snapshot is created");
    const int old = ::open(path.c_str(), O_RDONLY);
    check(old >= 0, "snapshot can be opened");
    ::mprotect(mapping, page, PROT_READ | PROT_WRITE);
    check(kudroid::refresh_process_maps_file(path), "next snapshot atomically replaces the file");
    check(permissions(read_file(path), address) == "rw-p", "new readers see updated permissions");
    check(old >= 0 && permissions(read_fd(old), address) == "r--p", "existing readers retain their complete snapshot");
    if (old >= 0) ::close(old);
    kudroid::forget_guest_mappings(mapping);
    check(permissions(kudroid::build_process_maps(), address).empty(), "released module metadata is no longer reported");
    ::munmap(mapping, page);
    ::unlink(path.c_str());
    ::rmdir(directory);
    return failures ? 1 : 0;
}
