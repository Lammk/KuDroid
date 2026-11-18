#pragma once
#include "kudroid/elf_loader.hpp"

namespace kudroid {
constexpr std::uint32_t kLinuxSvcInstruction = 0xD4000001u;
constexpr std::uint32_t kLinuxSyscallBreakpoint = 0xD4200000u | (0x5359u << 5);
long raw_syscall_result(long number, long result, int error, bool darwin);
std::size_t rewrite_raw_syscall_block(std::uint32_t* code, std::size_t words);
std::size_t elf_raw_syscall_rewrite(void* writeBase, std::uint64_t minVaddr,
    const std::vector<ElfLoader::Segment>& segments, const std::uint8_t* fileData,
    std::size_t fileSize);
}
