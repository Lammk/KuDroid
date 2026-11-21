#pragma once

#include <string>
#include <string_view>

namespace kudroid {

// GLES 3.1 compatibility for a 3.0 host driver.







enum class ShaderDowngrade {
    NotApplicable,  // not a 3.1/3.2 shader; left as is
    Downgraded,     // rewritten to "#version 300 es"
    Unsupported,    // needs a real 3.1 feature; left as is
};

// Rewrites `source` in place when it is a 3.1/3.2 shader with nothing 3.0 lacks.
ShaderDowngrade gles31_downgrade_shader(std::string& source);

// First token that makes a shader impossible to express in 3.0, or nullptr.
const char* gles31_unsupported_feature(std::string_view source);

// Preserve the actual backend version and its feature limits.
const char* gles31_advertise_version(const char* value, unsigned name);

// True when `pkg` is listed in `listText` (one package per line, '#' starts a comment).
bool gles31_package_listed(std::string_view listText, std::string_view pkg);

}  // namespace
