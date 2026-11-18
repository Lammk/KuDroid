namespace kudroid {
long raw_syscall_result(long number, long result, int error, bool darwin) {
    if (result != -1) return result;
    if (!darwin) return -error;
    // These wrappers already return Linux errno values.
    const bool guest = number == 63 || number == 72 || number == 73 || number == 98 ||
        (number >= 198 && number <= 212) || number == 242 || number == 243 || number == 269;
    if (guest && error != 78) return -error;
    switch (error) {
        case 11: return -35;  // EDEADLK
        case 62: return -40;  // ELOOP
        case 63: return -36;  // ENAMETOOLONG
        case 66: return -39;  // ENOTEMPTY
        case 78: return -38;  // ENOSYS
        case 84: return -75;  // EOVERFLOW
        default: return -SocketErrnoToGuest(error);
    }
}

namespace {
using RawFunctionRange = std::pair<std::uint64_t, std::uint64_t>;

// Read the common ELF64 PC-relative unwind encoding; skip unsupported records.
void raw_unwind_ranges(const std::uint8_t* bytes, std::size_t size, std::uint64_t address,
                       std::vector<RawFunctionRange>& ranges) {
    struct Cie { std::size_t offset; unsigned encoding; };
    std::vector<Cie> cies;
    auto u32 = [&](std::size_t p) {
        std::uint32_t n; std::memcpy(&n, bytes + p, 4); return n;
    };
    auto leb = [&](std::size_t& p, std::size_t end, std::uint64_t& value) {
        value = 0;
        for (unsigned shift = 0; shift < 64 && p < end; shift += 7) {
            const unsigned b = bytes[p++];
            if (shift == 63 && (b & 0x7E)) return false;
            value |= std::uint64_t(b & 0x7F) << shift;
            if (!(b & 0x80)) return true;
        }
        return false;
    };
    for (std::size_t p = 0; p <= size && size - p >= 4;) {
        const auto offset = p;
        const auto length = u32(p);
        p += 4;
        if (!length || length > size - p) break;
        const auto end = p + length;
        if (length < 4) { p = end; continue; }
        const auto id = u32(p);
        const auto idOffset = p;
        p += 4;
        if (id == 0) {
            if (p >= end || (bytes[p] != 1 && bytes[p] != 3)) { p = end; continue; }
            ++p;
            const auto augmentation = p;
            while (p < end && bytes[p]) ++p;
            if (p == end) { p = end; continue; }
            const auto augmentationEnd = p++;
            std::uint64_t value;
            if (!leb(p, end, value) || !leb(p, end, value) || !leb(p, end, value)) {
                p = end; continue;
            }
            unsigned encoding = 0;
            bool valid = augmentation < augmentationEnd && bytes[augmentation] == 'z';
            if (valid && leb(p, end, value) && value <= end - p) {
                const auto dataEnd = p + static_cast<std::size_t>(value);
                for (auto a = augmentation + 1; valid && a < augmentationEnd; ++a) {
                    if (p >= dataEnd) { valid = false; break; }
                    switch (bytes[a]) {
                        case 'R': encoding = bytes[p++]; break;
                        case 'L': ++p; break;
                        case 'P': {
                            const unsigned fmt = bytes[p++] & 0x0F;
                            const std::size_t width = fmt == 0 ? 8 : (fmt == 3 || fmt == 11) ? 4 : 0;
                            if (!width || width > dataEnd - p) valid = false;
                            else p += width;
                            break;
                        }
                        default: valid = false; break;
                    }
                }
            } else valid = false;
            if (valid && encoding == 0x1B) cies.push_back({offset, encoding});
        } else if (id <= idOffset && end - p >= 8) {
            const auto cieOffset = idOffset - id;
            bool valid = false;
            for (const auto& cie : cies) valid |= cie.offset == cieOffset;
            if (valid && address <= UINT64_MAX - p) {
                std::int32_t relative; std::memcpy(&relative, bytes + p, 4);
                const auto base = address + p;
                const auto delta = static_cast<std::int64_t>(relative);
                const auto length = u32(p + 4);
                if ((delta >= 0 && std::uint64_t(delta) <= UINT64_MAX - base) ||
                    (delta < 0 && std::uint64_t(-delta) <= base)) {
                    const auto start = delta < 0 ? base - std::uint64_t(-delta) : base + delta;
                    if (length && length <= UINT64_MAX - start) ranges.emplace_back(start, start + length);
                }
            }
        }
        p = end;
    }
}
}

std::size_t rewrite_raw_syscall_block(std::uint32_t* code, std::size_t words) {
    if (!code || words == 0) return 0;
    std::vector<unsigned char> visited(words, 0);
    std::vector<std::size_t> pending{0};
    std::size_t sites = 0;
    auto branch = [&](std::size_t pc, std::uint32_t immediate, unsigned bits) {
        const auto sign = std::int64_t{1} << (bits - 1);
        const auto offset = (static_cast<std::int64_t>(immediate) ^ sign) - sign;
        const auto target = static_cast<std::int64_t>(pc) + offset;
        if (target >= 0 && static_cast<std::uint64_t>(target) < words)
            pending.push_back(static_cast<std::size_t>(target));
    };
    while (!pending.empty()) {
        std::size_t pc = pending.back();
        pending.pop_back();
        while (pc < words && !visited[pc]) {
            visited[pc] = 1;
            const std::uint32_t word = code[pc];
            if (word == kLinuxSvcInstruction) { code[pc] = kLinuxSyscallBreakpoint; ++sites; }
            if ((word & 0x7C000000u) == 0x14000000u) {
                branch(pc, word & 0x03FFFFFFu, 26);
                if (!(word & 0x80000000u)) break;
            } else if ((word & 0xFF000010u) == 0x54000000u ||
                       (word & 0x7E000000u) == 0x34000000u) {
                branch(pc, (word >> 5) & 0x7FFFFu, 19);
            } else if ((word & 0x7E000000u) == 0x36000000u) {
                branch(pc, (word >> 5) & 0x3FFFu, 14);
            } else if ((word & 0xFE000000u) == 0xD6000000u && !(word & 0x00200000u)) {
                break;
            }
            ++pc;
        }
    }
    return sites;
}

std::size_t elf_raw_syscall_rewrite(void* writeBase, std::uint64_t minVaddr,
    const std::vector<ElfLoader::Segment>& segments, const std::uint8_t* fileData,
    std::size_t fileSize) {
    if (!writeBase || !fileData || fileSize < 64 || std::memcmp(fileData, "\177ELF", 4) ||
        fileData[4] != 2 || fileData[5] != 1) return 0;
    auto u16 = [&](std::size_t at) { std::uint16_t n; std::memcpy(&n, fileData + at, 2); return n; };
    auto u32 = [&](std::size_t at) { std::uint32_t n; std::memcpy(&n, fileData + at, 4); return n; };
    auto u64 = [&](std::size_t at) { std::uint64_t n; std::memcpy(&n, fileData + at, 8); return n; };
    if (u16(18) != 183) return 0;
    const auto shoff = u64(40);
    const auto stride = u16(58), count = u16(60), stringsIndex = u16(62);
    if (stride < 64 || count == 0 || stringsIndex >= count || shoff > fileSize ||
        static_cast<std::uint64_t>(count) * stride > fileSize - shoff) return 0;
    const auto stringsHeader = shoff + stringsIndex * stride;
    const auto strings = u64(stringsHeader + 24), stringsSize = u64(stringsHeader + 32);
    if (strings > fileSize || stringsSize > fileSize - strings) return 0;
    std::vector<std::pair<std::uint64_t, std::uint64_t>> executable;
    std::vector<RawFunctionRange> functions;
    std::uint64_t ehAddress = 0, ehOffset = 0, ehSize = 0;
    for (unsigned i = 0; i < count; ++i) {
        const auto header = shoff + i * stride;
        const auto name = u32(header);
        const auto address = u64(header + 16), size = u64(header + 32);
        if (u32(header + 4) == 1 && (u64(header + 8) & 4) && size && address + size >= address)
            executable.emplace_back(address, address + size);
        const auto type = u32(header + 4);
        const auto entrySize = u64(header + 56);
        const auto offset = u64(header + 24);
        if ((type == 2 || type == 11) && entrySize >= 24 && offset <= fileSize && size <= fileSize - offset) {
            for (std::uint64_t entry = 0; entry <= size && size - entry >= entrySize; entry += entrySize) {
                const auto symbol = offset + entry;
                const auto start = u64(symbol + 8), length = u64(symbol + 16);
                if ((fileData[symbol + 4] & 15) == 2 && u16(symbol + 6) && length &&
                    length <= UINT64_MAX - start) functions.emplace_back(start, start + length);
            }
        }
        if (name >= stringsSize) continue;
        const char* text = reinterpret_cast<const char*>(fileData + strings + name);
        if (!std::memchr(text, 0, stringsSize - name) || std::strcmp(text, ".eh_frame") != 0) continue;
        if (offset <= fileSize && size <= fileSize - offset) {
            ehAddress = address; ehOffset = offset; ehSize = size;
        }
    }
    if (ehSize) raw_unwind_ranges(fileData + ehOffset, ehSize, ehAddress, functions);
    std::sort(functions.begin(), functions.end());
    functions.erase(std::unique(functions.begin(), functions.end()), functions.end());
    std::size_t sites = 0;
    for (const auto& function : functions) {
        const auto start = function.first;
        const auto length = function.second - start;
        if (start < minVaddr || start % 4 || length % 4 || length == 0 || start + length < start) continue;
        const auto end = start + length;
        bool code = false, mapped = false;
        for (const auto& span : executable) code |= start >= span.first && end <= span.second;
        for (const auto& segment : segments)
            mapped |= (segment.flags & 1) && start >= segment.vaddr &&
                      end >= segment.vaddr && end - segment.vaddr <= segment.filesz;
        if (!code || !mapped) continue;
        auto* words = reinterpret_cast<std::uint32_t*>(static_cast<std::uint8_t*>(writeBase) + start - minVaddr);
        sites += rewrite_raw_syscall_block(words, length / 4);
    }
    return sites;
}
}
