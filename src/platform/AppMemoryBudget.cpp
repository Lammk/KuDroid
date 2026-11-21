#include "kudroid/platform/AppMemoryBudget.h"

#include <algorithm>
#include <cstdio>
#include <mutex>

#if defined(__APPLE__)
#include <TargetConditionals.h>
#include <mach/mach.h>
#if __has_include(<os/proc.h>)
#include <os/proc.h>
#define KUDROID_BUDGET_HAVE_OS_PROC 1
#endif
#endif

namespace kudroid {
namespace {
std::mutex budgetMutex;
bool enabled = false;
int percentage = 70;
AppMemoryBudget currentBudget;

uint64_t AvailableForApp(const SystemMemory& memory) {
#if defined(KUDROID_BUDGET_HAVE_OS_PROC) && TARGET_OS_IPHONE
    if (__builtin_available(iOS 13.0, *))
        return std::min<uint64_t>(os_proc_available_memory(), memory.available_bytes);
#endif
    return memory.process_available_bytes > 0
        ? std::min(memory.process_available_bytes, memory.available_bytes) : memory.available_bytes;
}

SystemMemory FreshBudgetMemory(SystemMemory memory) {
#if defined(__APPLE__)
    task_vm_info_data_t info{};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, reinterpret_cast<task_info_t>(&info),
                  &count) == KERN_SUCCESS) memory.process_resident_bytes = info.phys_footprint;
#endif
    memory.process_available_bytes = AvailableForApp(memory);
    return memory;
}
}

uint64_t memory_budget_bytes(uint64_t available, int percent) {
    if (percent < 0 || percent > 100) return 0;
    const uint64_t value = static_cast<uint64_t>(percent);
    return available / 100 * value + available % 100 * value / 100;
}

SystemMemory memory_budget_view(const SystemMemory& host, const AppMemoryBudget& budget) {
    if (!budget.active) return host;
    SystemMemory view = host;
    const uint64_t growth = host.process_resident_bytes > budget.baseline_bytes
        ? host.process_resident_bytes - budget.baseline_bytes : 0;
    const uint64_t used = std::min(growth, budget.limit_bytes);
    const uint64_t available = std::min(budget.limit_bytes - used, host.process_available_bytes);
    view.total_bytes = budget.limit_bytes;
    view.available_bytes = available;
    view.process_available_bytes = available;
    view.process_resident_bytes = budget.limit_bytes - available;
    view.low_memory = host.low_memory || available <= budget.limit_bytes / 8;
    return view;
}

void configure_app_memory_budget(bool value, int percent) {
    if (percent < 0 || percent > 100) return;
    std::lock_guard<std::mutex> lock(budgetMutex);
    enabled = value && percent > 0 && percent < 100;
    percentage = percent;
}

void begin_app_memory_budget() {
    const SystemMemory memory = FreshBudgetMemory(query_system_memory());
    const uint64_t available = memory.process_available_bytes;
    std::lock_guard<std::mutex> lock(budgetMutex);
    currentBudget = {};
    if (!enabled || !memory.measured) return;
    currentBudget.active = true;
    currentBudget.baseline_bytes = memory.process_resident_bytes;
    currentBudget.limit_bytes = memory_budget_bytes(std::min(available, memory.total_bytes), percentage);
    std::fprintf(stderr, "[KuDroidMemoryBudget] percent=%d available=%llu budget=%llu baseline=%llu\n",
                 percentage, static_cast<unsigned long long>(available),
                 static_cast<unsigned long long>(currentBudget.limit_bytes),
                 static_cast<unsigned long long>(currentBudget.baseline_bytes));
}

void end_app_memory_budget() {
    std::lock_guard<std::mutex> lock(budgetMutex);
    currentBudget = {};
}

bool app_memory_budget_active() {
    std::lock_guard<std::mutex> lock(budgetMutex);
    return currentBudget.active;
}

uint64_t estimate_app_memory_budget(int percent) {
    const SystemMemory memory = query_system_memory();
    if (!memory.measured) return 0;
    return memory_budget_bytes(std::min(AvailableForApp(memory), memory.total_bytes), percent);
}

SystemMemory query_android_memory() {
    SystemMemory memory = query_system_memory();
    AppMemoryBudget budget;
    {
        std::lock_guard<std::mutex> lock(budgetMutex);
        budget = currentBudget;
    }
    if (!budget.active) return memory;
    memory = FreshBudgetMemory(memory);
    return memory_budget_view(memory, budget);
}

}

extern "C" void kudroid_configure_app_memory_budget(int enabled, int percent) {
    kudroid::configure_app_memory_budget(enabled != 0, percent);
}

extern "C" unsigned long long kudroid_app_memory_budget_estimate(int percent) {
    return kudroid::estimate_app_memory_budget(percent);
}

extern "C" unsigned long long kudroid_hardware_memory_bytes() {
    const auto memory = kudroid::query_system_memory();
    return memory.measured ? memory.total_bytes : 0;
}

extern "C" unsigned long long kudroid_available_app_memory_bytes() {
    return kudroid::estimate_app_memory_budget(100);
}
