#pragma once

#include <cstdint>
#include <cstddef>

namespace kudroid {

// Look up a Vorbis codebook by its CRC32.

const void* kudroid_fmod_vorbis_lookup(uint32_t crc);

// Register the Vorbis codebook trap handler.





bool kudroid_arm_fmod_vorbis_trap(uintptr_t patchAddr, uintptr_t targetFound,
                                  uintptr_t resumeAfter, uint32_t origInst, bool probe);

// Handle a missing Vorbis codebook through the registered breakpoint.
bool bionic_handle_fmod_vorbis_trap(void* ucontext);

} // namespace
