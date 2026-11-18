#include "kudroid/ElfSyscalls.h"
#include <algorithm>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iterator>
#include <vector>

using namespace kudroid;
static int failures = 0;
static void check(bool ok, const char* label) {
    std::printf("%s %s\n", ok ? "PASS" : "FAIL", label);
    failures += !ok;
}
static constexpr std::uint32_t svc = kLinuxSvcInstruction, trap = kLinuxSyscallBreakpoint;
static constexpr std::uint32_t ret = 0xD65F03C0, nop = 0xD503201F;

static void blocks() {
    std::uint32_t straight[]{nop, svc, ret, svc};
    check(rewrite_raw_syscall_block(straight, 4) == 1 && straight[1] == trap && straight[3] == svc,
          "return stops rewriting before literal data");
    std::uint32_t jump[]{0x14000002, svc, svc, ret};
    check(rewrite_raw_syscall_block(jump, 4) == 1 && jump[1] == svc && jump[2] == trap,
          "unconditional branch skips literal data");
    for (auto conditional : {0x54000040u, 0xB4000040u, 0xB5000040u, 0x36000040u, 0x37000040u}) {
        std::uint32_t words[]{conditional, svc, svc, ret};
        check(rewrite_raw_syscall_block(words, 4) == 2 && words[1] == trap && words[2] == trap,
              "conditional branch visits both paths");
    }
    std::uint32_t loop[]{svc, 0x17FFFFFF, svc};
    check(rewrite_raw_syscall_block(loop, 3) == 1 && loop[2] == svc, "backward branch terminates");
    std::uint32_t call[]{0x94000002, ret, svc, ret};
    check(rewrite_raw_syscall_block(call, 4) == 1 && call[2] == trap, "local call target is visited");
    std::uint32_t indirect[]{0xD61F0000, svc};
    check(rewrite_raw_syscall_block(indirect, 2) == 0, "indirect jump stops linear decoding");
    std::uint32_t indirectCall[]{0xD63F0000, svc, ret};
    check(rewrite_raw_syscall_block(indirectCall, 3) == 1, "indirect call preserves fallthrough");
    std::uint32_t foreign[]{0xD4000021, 0xD4200020, svc, ret};
    check(rewrite_raw_syscall_block(foreign, 4) == 1 && foreign[0] == 0xD4000021 && foreign[1] == 0xD4200020,
          "foreign supervisor calls and breakpoints are preserved");
    check(rewrite_raw_syscall_block(foreign, 4) == 0, "rewriting is idempotent");
    check(rewrite_raw_syscall_block(nullptr, 20) == 0, "null code is rejected");
}

template<class T> static void put(std::vector<std::uint8_t>& file, std::size_t p, T value) {
    std::memcpy(file.data() + p, &value, sizeof(value));
}
static std::vector<std::uint8_t> fixture() {
    std::vector<std::uint8_t> file(1024);
    std::memcpy(file.data(), "\177ELF\2\1", 6);
    put<std::uint16_t>(file, 18, 183);
    put<std::uint64_t>(file, 40, 512);
    put<std::uint16_t>(file, 58, 64);
    put<std::uint16_t>(file, 60, 4);
    put<std::uint16_t>(file, 62, 1);
    std::memcpy(file.data()+64, "\0.text\0.eh_frame\0", 17);
    put<std::uint64_t>(file, 576+24, 64);
    put<std::uint64_t>(file, 576+32, 17);
    put<std::uint32_t>(file, 640, 1);
    put<std::uint32_t>(file, 640+4, 1);
    put<std::uint64_t>(file, 640+8, 6);
    put<std::uint64_t>(file, 640+16, 0x1000);
    put<std::uint64_t>(file, 640+24, 128);
    put<std::uint64_t>(file, 640+32, 16);
    put<std::uint32_t>(file, 128, svc);
    put<std::uint32_t>(file, 132, ret);
    put<std::uint32_t>(file, 136, svc);
    put<std::uint32_t>(file, 140, ret);
    put<std::uint32_t>(file, 704, 7);
    put<std::uint32_t>(file, 704+4, 1);
    put<std::uint64_t>(file, 704+16, 0x2000);
    put<std::uint64_t>(file, 704+24, 256);
    put<std::uint64_t>(file, 704+32, 40);
    const std::uint8_t cie[]{12,0,0,0, 0,0,0,0, 1,'z','R',0, 1,0x78,30,1,0x1B,0,0,0};
    // CIE padding must be included in its record length.
    std::memcpy(file.data()+256, cie, sizeof(cie));
    put<std::uint32_t>(file, 256, 16);
    put<std::uint32_t>(file, 276, 16);
    put<std::uint32_t>(file, 280, 24);
    put<std::int32_t>(file, 284, -0x101C);
    put<std::uint32_t>(file, 288, 8);
    return file;
}
static std::size_t rewrite_fixture(std::vector<std::uint8_t>& file, std::uint32_t (&mapped)[4],
                                   std::uint32_t flags = 5, std::uint64_t bytes = 16) {
    std::memcpy(mapped, file.data()+128, 16);
    ElfLoader::Segment segment{};
    segment.vaddr=0x1000; segment.filesz=bytes; segment.memsz=16; segment.flags=flags;
    return elf_raw_syscall_rewrite(mapped, 0x1000, {segment}, file.data(), file.size());
}
static void elf() {
    auto file = fixture();
    std::uint32_t mapped[4];
    check(rewrite_fixture(file,mapped)==1 && mapped[0]==trap && mapped[2]==svc,
          "FDE covers only its declared mapped function");
    check(rewrite_fixture(file,mapped,4)==0, "non-executable mapping is untouched");
    check(rewrite_fixture(file,mapped,5,4)==0, "function beyond file-backed segment is rejected");
    auto bad = file;
    put<std::uint32_t>(bad,256,0xFFFFFFFF);
    check(rewrite_fixture(bad,mapped)==0, "truncated unwind record is rejected");
    bad=file; bad[272]=0;
    check(rewrite_fixture(bad,mapped)==0, "unsupported unwind encoding is skipped");
    bad=file; put<std::uint64_t>(bad,40,UINT64_MAX);
    check(rewrite_fixture(bad,mapped)==0, "overflowing section table is rejected");
    bad=file; bad[0]=0;
    check(rewrite_fixture(bad,mapped)==0, "invalid ELF signature is rejected");
    bad=file; put<std::uint32_t>(bad,704+4,11); put<std::uint64_t>(bad,704+24,256);
    put<std::uint64_t>(bad,704+32,24); put<std::uint64_t>(bad,704+56,24);
    bad[260]=2; put<std::uint16_t>(bad,262,2);
    put<std::uint64_t>(bad,264,0x1008); put<std::uint64_t>(bad,272,8);
    check(rewrite_fixture(bad,mapped)==1 && mapped[0]==svc && mapped[2]==trap,
          "symbol metadata works without unwind data");
    put<std::uint64_t>(bad,272,UINT64_MAX);
    check(rewrite_fixture(bad,mapped)==0, "overflowing symbol range is rejected");
}
static void errors() {
    check(raw_syscall_result(56,8,78,true)==8, "success ignores stale errno");
    check(raw_syscall_result(222,-1,12,true)==-12, "failed mmap returns raw negative errno");
    check(raw_syscall_result(9999,-1,78,true)==-38, "unsupported syscall returns Linux ENOSYS");
    check(raw_syscall_result(203,-1,115,true)==-115, "translated EINPROGRESS is not translated twice");
    check(raw_syscall_result(63,-1,11,true)==-11, "translated read EAGAIN is preserved");
    check(raw_syscall_result(98,-1,110,true)==-110, "translated futex timeout is preserved");
    check(raw_syscall_result(101,-1,4,true)==-4, "interrupted sleep reports EINTR");
    check(raw_syscall_result(56,-1,63,true)==-36, "file errors use Linux numbering");
    check(raw_syscall_result(64,-1,35,true)==-11, "raw write converts Darwin EAGAIN");
    check(raw_syscall_result(64,-1,11,false)==-11, "Linux errno stays unchanged");
}
int main(int argc, char** argv) {
    blocks(); elf(); errors();
    if (argc == 2) {
        std::ifstream stream(argv[1], std::ios::binary);
        std::vector<std::uint8_t> file((std::istreambuf_iterator<char>(stream)), {});
        if (file.size() >= 64) {
            std::uint64_t phoff; std::uint16_t stride,count;
            std::memcpy(&phoff,file.data()+32,8); std::memcpy(&stride,file.data()+54,2);
            std::memcpy(&count,file.data()+56,2);
            std::vector<ElfLoader::Segment> segments;
            std::uint64_t low=UINT64_MAX, high=0;
            for (unsigned i=0;i<count && stride>=56;++i) {
                const auto p=phoff+i*stride;
                if (p>file.size() || file.size()-p<56) break;
                std::uint32_t type; std::memcpy(&type,file.data()+p,4);
                if (type!=1) continue;
                ElfLoader::Segment s{};
                std::memcpy(&s.flags,file.data()+p+4,4); std::memcpy(&s.offset,file.data()+p+8,8);
                std::memcpy(&s.vaddr,file.data()+p+16,8); std::memcpy(&s.filesz,file.data()+p+32,8);
                std::memcpy(&s.memsz,file.data()+p+40,8);
                if (s.offset>file.size() || s.filesz>file.size()-s.offset || s.vaddr>UINT64_MAX-s.memsz) continue;
                low=std::min(low,s.vaddr); high=std::max(high,s.vaddr+s.memsz); segments.push_back(s);
            }
            if (high>low && high-low<64*1024*1024) {
                std::vector<std::uint8_t> image(high-low);
                for (auto s:segments) std::memcpy(image.data()+s.vaddr-low,file.data()+s.offset,s.filesz);
                auto sites=elf_raw_syscall_rewrite(image.data(),low,segments,file.data(),file.size());
                std::printf("AUDIT raw syscall sites: %zu\n",sites);
                check(sites>0,"audit copy contains rewritable syscall instructions");
            }
        }
    }
    return failures ? 1 : 0;
}
