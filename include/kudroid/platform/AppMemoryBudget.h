#pragma once

#include "kudroid/platform/MemoryInfo.h"

namespace kudroid {

struct AppMemoryBudget {
    uint64_t limit_bytes = 0;
    uint64_t baseline_bytes = 0;
    bool active = false;
};

uint64_t memory_budget_bytes(uint64_t available, int percent);
SystemMemory memory_budget_view(const SystemMemory& host, const AppMemoryBudget& budget);
void configure_app_memory_budget(bool enabled, int percent);
void begin_app_memory_budget();
void end_app_memory_budget();
bool app_memory_budget_active();
uint64_t estimate_app_memory_budget(int percent);
SystemMemory query_android_memory();

}
