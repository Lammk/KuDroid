#pragma once

#include <string>
#include <cstdint>
#include <vector>

namespace kudroid {
void configure_shared_packages(bool enabled);
bool shared_packages_enabled();
uint32_t shared_packages_generation();
std::vector<std::string> shared_package_directories();
std::string installed_package_record(const std::string& package, bool currentPackage);
std::string shared_package_records();
}
