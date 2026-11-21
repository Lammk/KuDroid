#include "kudroid/ApkSigning.h"

#include <cstring>
#include <algorithm>
#include <fstream>
#include <limits>
#include <zlib.h>

namespace kudroid {
namespace {
using Bytes = std::vector<uint8_t>;
uint16_t U16(const uint8_t* p) { return p[0] | (uint16_t(p[1]) << 8); }
uint32_t U32(const uint8_t* p) { return U16(p) | (uint32_t(U16(p + 2)) << 16); }
uint64_t U64(const uint8_t* p) { return U32(p) | (uint64_t(U32(p + 4)) << 32); }

bool Read(std::ifstream& file, uint64_t offset, size_t size, Bytes& out) {
    if (offset > uint64_t(std::numeric_limits<std::streamoff>::max())) return false;
    out.resize(size);
    file.clear(); file.seekg(static_cast<std::streamoff>(offset));
    return bool(file.read(reinterpret_cast<char*>(out.data()), size));
}

struct Slice {
    const uint8_t* data = nullptr;
    size_t size = 0;
    bool Next(Slice& result) {
        if (size < 4) return false;
        const uint32_t length = U32(data);
        if (length > size - 4) return false;
        result = {data + 4, length}; data += length + 4; size -= length + 4;
        return true;
    }
};

std::vector<Bytes> BlockCertificates(Slice value) {
    std::vector<Bytes> result;
    Slice signers;
    if (!value.Next(signers) || value.size != 0) return {};
    while (signers.size) {
        Slice signer, signedData, digests, certificates, certificate;
        if (!signers.Next(signer) || !signer.Next(signedData) ||
            !signedData.Next(digests) || !signedData.Next(certificates) ||
            !certificates.Next(certificate) || certificate.size == 0) return {};
        result.emplace_back(certificate.data, certificate.data + certificate.size);
    }
    return result;
}

struct Der {
    const uint8_t* data = nullptr;
    size_t size = 0;
    uint8_t tag = 0;
    const uint8_t* encoded = nullptr;
    size_t encodedSize = 0;
    bool Next(Der& node) {
        if (size < 2) return false;
        size_t header = 2, length = data[1];
        if (length & 128) {
            const size_t count = length & 127;
            if (!count || count > sizeof(size_t) || size < 2 + count) return false;
            length = 0; header += count;
            for (size_t i = 0; i < count; ++i) length = (length << 8) | data[2 + i];
        }
        if (header > size || length > size - header) return false;
        node = {data + header, length, data[0], data, header + length};
        data += header + length; size -= header + length;
        return true;
    }
};

bool Same(Der a, Der b) {
    return a.encodedSize == b.encodedSize && a.encoded && b.encoded &&
        std::memcmp(a.encoded, b.encoded, a.encodedSize) == 0;
}

std::vector<Bytes> Pkcs7Certificates(const Bytes& bytes) {
    Der input{bytes.data(), bytes.size()}, top, oid, wrapper, signedData;
    if (!input.Next(top) || top.tag != 0x30 || !top.Next(oid) ||
        !top.Next(wrapper) || wrapper.tag != 0xa0 || !wrapper.Next(signedData)) return {};
    Der version, digests, content, certificates, signers;
    if (!signedData.Next(version) || !signedData.Next(digests) ||
        !signedData.Next(content) || !signedData.Next(certificates) || certificates.tag != 0xa0) return {};
    while (signedData.Next(signers) && signers.tag != 0x31) {}
    if (signers.tag != 0x31) return {};
    std::vector<Der> available;
    Der certificate;
    while (certificates.Next(certificate)) available.push_back(certificate);
    std::vector<Bytes> result;
    Der signer;
    while (signers.Next(signer)) {
        Der signerVersion, identifier, issuer, serial;
        if (!signer.Next(signerVersion) || !signer.Next(identifier) || identifier.tag != 0x30 ||
            !identifier.Next(issuer) || !identifier.Next(serial)) return {};
        for (Der candidate : available) {
            Der body, candidateSerial, algorithm, candidateIssuer;
            if (!candidate.Next(body) || !body.Next(candidateSerial)) continue;
            if (candidateSerial.tag == 0xa0 && !body.Next(candidateSerial)) continue;
            if (!body.Next(algorithm) || !body.Next(candidateIssuer)) continue;
            if (Same(candidateSerial, serial) && Same(candidateIssuer, issuer)) {
                result.emplace_back(candidate.encoded, candidate.encoded + candidate.encodedSize);
                break;
            }
        }
    }
    return result;
}

std::vector<Bytes> JarCertificates(std::ifstream& file, uint64_t offset, uint64_t limit, uint16_t entries) {
    std::vector<Bytes> result;
    for (unsigned i = 0; i < entries; ++i) {
        Bytes header, name;
        if (offset > limit || limit - offset < 46) return {};
        if (!Read(file, offset, 46, header) || U32(header.data()) != 0x02014b50) return {};
        const uint16_t nameSize = U16(header.data() + 28);
        const size_t entrySize = 46u + nameSize + U16(header.data() + 30) + U16(header.data() + 32);
        if (entrySize > limit - offset) return {};
        if (!Read(file, offset + 46, nameSize, name)) return {};
        const std::string path(name.begin(), name.end());
        offset += entrySize;
        if (path.rfind("META-INF/", 0) != 0 || path.size() < 4 ||
            (path.substr(path.size() - 4) != ".RSA" && path.substr(path.size() - 4) != ".DSA" &&
             path.substr(path.size() - 3) != ".EC")) continue;
        const size_t compressed = U32(header.data() + 20), raw = U32(header.data() + 24);
        if (!raw || raw > (2u << 20) || compressed > (2u << 20)) return {};
        Bytes local, data;
        const uint64_t localOffset = U32(header.data() + 42);
        if (!Read(file, localOffset, 30, local) || U32(local.data()) != 0x04034b50 ||
            !Read(file, localOffset + 30 + U16(local.data() + 26) + U16(local.data() + 28), compressed, data)) return {};
        Bytes decoded(raw);
        if (U16(header.data() + 10) == 0) {
            if (compressed != raw) return {};
            decoded = std::move(data);
        } else if (U16(header.data() + 10) == 8) {
            z_stream stream{}; stream.next_in = data.data(); stream.avail_in = data.size();
            stream.next_out = decoded.data(); stream.avail_out = decoded.size();
            if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) return {};
            const int status = inflate(&stream, Z_FINISH);
            const bool complete = status == Z_STREAM_END && stream.total_out == raw;
            inflateEnd(&stream);
            if (!complete) return {};
        } else return {};
        auto certificates = Pkcs7Certificates(decoded);
        for (auto& certificate : certificates)
            if (std::find(result.begin(), result.end(), certificate) == result.end()) result.push_back(std::move(certificate));
    }
    return result;
}
}

std::vector<std::vector<uint8_t>> read_apk_signing_certificates(const std::string& path) {
    std::ifstream file(path, std::ios::binary | std::ios::ate);
    const auto end = file.tellg();
    if (end < 22) return {};
    const uint64_t size = static_cast<uint64_t>(end);
    const size_t tailSize = size < 65557 ? static_cast<size_t>(size) : 65557;
    Bytes tail;
    if (!Read(file, size - tailSize, tailSize, tail)) return {};
    size_t eocd = tail.size() - 22;
    for (;;) {
        if (U32(tail.data() + eocd) == 0x06054b50 &&
            eocd + 22 + U16(tail.data() + eocd + 20) == tail.size()) break;
        if (!eocd--) return {};
    }
    const uint64_t central = U32(tail.data() + eocd + 16);
    const uint64_t centralSize = U32(tail.data() + eocd + 12);
    const uint64_t endOffset = size - tailSize + eocd;
    if (central > endOffset || centralSize != endOffset - central || central < 24 ||
        U16(tail.data() + eocd + 4) != 0 || U16(tail.data() + eocd + 6) != 0 ||
        U16(tail.data() + eocd + 8) != U16(tail.data() + eocd + 10)) return {};
    Bytes footer;
    if (!Read(file, central - 24, 24, footer)) return {};
    if (std::memcmp(footer.data() + 8, "APK Sig Block 42", 16) != 0)
        return JarCertificates(file, central, endOffset, U16(tail.data() + eocd + 10));
    const uint64_t blockSize = U64(footer.data());
    if (blockSize < 24 || blockSize > (16u << 20) || blockSize + 8 > central) return {};
    Bytes block;
    if (!Read(file, central - blockSize - 8, blockSize + 8, block) || U64(block.data()) != blockSize) return {};
    Slice selected{}; int selectedVersion = 0;
    for (size_t cursor = 8; cursor < block.size() - 24;) {
        if (block.size() - 24 - cursor < 12) return {};
        const uint64_t length = U64(block.data() + cursor); cursor += 8;
        if (length < 4 || length > block.size() - 24 - cursor) return {};
        const uint32_t id = U32(block.data() + cursor);
        const int version = id == 0x7109871a ? 2 : id == 0xf05368c0 ? 3 : id == 0x1b93ad61 ? 4 : 0;
        if (version > selectedVersion) {
            selected = {block.data() + cursor + 4, size_t(length - 4)};
            selectedVersion = version;
        }
        cursor += length;
    }
    return selectedVersion ? BlockCertificates(selected) : std::vector<Bytes>{};
}
}
