namespace {
std::vector<kudroid::GuestMappedSegment> BuildGuestMappings(
        std::uintptr_t base, const void* headers, unsigned short count) {
    std::vector<kudroid::GuestMappedSegment> result;
    const auto* phdrs = static_cast<const kudroid::Elf64Phdr*>(headers);
    const long pageSize = ::sysconf(_SC_PAGESIZE);
    if (pageSize <= 0) return result;
    const auto page = static_cast<std::uint64_t>(pageSize);
    const auto maximum = std::numeric_limits<std::uintptr_t>::max();
    for (unsigned short i = 0; i < count; ++i) {
        const auto& header = phdrs[i];
        if (header.p_type != 1 || header.p_memsz == 0 || header.p_vaddr > maximum - base) continue;
        const auto start = base + header.p_vaddr;
        if (header.p_memsz > maximum - start) continue;
        const auto end = start + header.p_memsz;
        if (end > maximum - (page - 1)) continue;
        result.push_back({start - start % page, (end + page - 1) / page * page,
                          header.p_offset - header.p_offset % page, {}});
    }
    return result;
}
}

std::vector<GuestMappedSegment> snapshot_guest_mappings() {
    std::lock_guard<std::mutex> lock(g_guestMtx);
    std::vector<GuestMappedSegment> result;
    for (const auto& module : g_guestModules) {
        for (auto segment : module.mappings) {
            segment.path = module.path;
            result.push_back(std::move(segment));
        }
    }
    return result;
}

void forget_guest_mappings(void* base) {
    if (!base) return;
    std::lock_guard<std::mutex> lock(g_guestMtx);
    for (auto& module : g_guestModules) {
        if (module.base == reinterpret_cast<std::uintptr_t>(base)) module.mappings.clear();
    }
}
