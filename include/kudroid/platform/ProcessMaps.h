#pragma once
#include <string>

namespace kudroid {
std::string build_process_maps();
bool refresh_process_maps_file(const std::string& path);
}
