// OAT: the DEX runtime's ahead-of-time cache, on disk beside the app's DEX.





















#ifndef KUDROID_KUART_OATFILE_H
#define KUDROID_KUART_OATFILE_H

#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

namespace kudroid {
namespace kuart {

class OatFile {
public:
    // How a method fared last run.
    enum class MethodState : uint8_t {
        kUnknown = 0,
        kHot = 1,       // ran often enough to be worth compiling on sight
        kRefused = 2,   // the compiler declined; do not retry
    };

    struct Entry {
        // Identifies a method across runs: the DEX it came from plus its method index.
        // A name would be ambiguous (overloads) and a pointer meaningless (a new run
        // allocates different addresses).
        uint32_t dex_checksum = 0;
        uint32_t method_index = 0;
        MethodState state = MethodState::kUnknown;
    };

    OatFile() = default;

    // Read `path`. Returns false when the file is absent, truncated, or written by a
    // different version — all of which are ordinary and mean "no profile", not an error.
    bool Load(const std::string& path);

    // Write the accumulated profile. Writes to a temporary and renames, so a kill
    // during the write leaves the previous file rather than a half-written one — a
    // truncated profile would be rejected on load anyway, but losing the old one costs
    // a slow start.
    bool Save(const std::string& path) const;

    // Record what happened to a method this run.
    void Note(uint32_t dex_checksum, uint32_t method_index, MethodState state);

    // What the previous run recorded, or kUnknown.
    MethodState Lookup(uint32_t dex_checksum, uint32_t method_index) const;

    // Forget everything belonging to a DEX whose checksum no longer matches.
    //
    // Called when a DEX is loaded whose checksum differs from any recorded for the same
    // location: the app was updated, so every method index in those entries now refers
    // to different bytecode.
    void InvalidateChecksum(uint32_t dex_checksum);

    size_t size() const { return entries_.size(); }
    bool empty() const { return entries_.empty(); }

    // Bounded so a long-running app cannot grow the file without limit. Reaching it
    // means dropping new entries, not evicting old ones — the old ones are the ones
    // with proven value.
    static constexpr size_t kMaxEntries = 65536;

    // Bumped whenever the on-disk layout or the meaning of a field changes, so an old
    // file is rejected rather than misread.
    static constexpr uint32_t kMagic = 0x4B554F41;  // "KUOA"
    static constexpr uint32_t kVersion = 1;

private:
    struct Key {
        uint32_t checksum;
        uint32_t index;
        bool operator==(const Key& o) const {
            return checksum == o.checksum && index == o.index;
        }
    };
    struct KeyHash {
        size_t operator()(const Key& k) const {
            return (static_cast<size_t>(k.checksum) << 32) ^ k.index;
        }
    };

    std::unordered_map<Key, MethodState, KeyHash> entries_;
};

}  // namespace
}  // namespace

#endif  // KUDROID_KUART_OATFILE_H
