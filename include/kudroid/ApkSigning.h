#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace kudroid {
std::vector<std::vector<uint8_t>> read_apk_signing_certificates(const std::string& path);
}
