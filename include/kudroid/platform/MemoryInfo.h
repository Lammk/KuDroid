// Real system memory figures for the host device.









#ifndef KUDROID_PLATFORM_MEMORYINFO_H
#define KUDROID_PLATFORM_MEMORYINFO_H

#include <cstdint>

namespace kudroid {

struct SystemMemory {
    // Physical RAM installed. Always known.
    uint64_t total_bytes = 0;

    // RAM the system could hand out right now (free + reclaimable). This is the
    // system-wide figure ActivityManager.MemoryInfo.availMem reports.
    uint64_t available_bytes = 0;

    // How much more this process may allocate before the OS kills it.
    //
    // On iOS this is the number that actually matters and it is NOT
    // available_bytes: jetsam enforces a per-process limit well below total RAM,
    // so an app that trusts system-available memory allocates its way into a
    // kill. 0 when the platform cannot report it.
    uint64_t process_available_bytes = 0;

    // Resident size of this process. 0 when unknown.
    uint64_t process_resident_bytes = 0;

    // The system is under memory pressure; mirrors MemoryInfo.lowMemory.
    bool low_memory = false;

    // False when every figure is a fallback guess rather than measured.
    bool measured = false;
};

// Query the host. Cheap enough for a per-call refresh (two syscalls), so callers do
// not have to cache; memory figures go stale immediately anyway.
SystemMemory query_system_memory();

// Per-app heap budget in megabytes, the unit ActivityManager.getMemoryClass uses.




int memory_class_mb();

// The larger budget an app gets with android:largeHeap="true".
int large_memory_class_mb();

}  // namespace

#endif  // KUDROID_PLATFORM_MEMORYINFO_H
