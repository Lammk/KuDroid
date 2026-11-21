#include "kudroid/platform/EcCrypto.h"
#include <cstdlib>
#include <cstring>
#include <limits>
#include <memory>
#if defined(__APPLE__)
extern "C" int kudroid_ec_crypto(int operation, int bits, const char* hash,
    const uint8_t* key, size_t keyLength, const uint8_t* message, size_t messageLength,
    const uint8_t* signature, size_t signatureLength, void** output, size_t* outputLength) __attribute__((weak));
#elif defined(KUDROID_HAS_OPENSSL)
#include <openssl/ec.h>
#include <openssl/evp.h>
#include <openssl/x509.h>
#endif

namespace kudroid {
namespace {
#if defined(__APPLE__)
struct Output {
    void* bytes = nullptr;
    size_t size = 0;
    ~Output() {
        volatile uint8_t* p = static_cast<uint8_t*>(bytes);
        for (size_t i = 0; i < size; ++i) p[i] = 0;
        std::free(bytes);
    }
};
uint32_t read32(const uint8_t* p) {
    return uint32_t(p[0]) << 24 | uint32_t(p[1]) << 16 | uint32_t(p[2]) << 8 | p[3];
}
#elif defined(KUDROID_HAS_OPENSSL)
using Key = std::unique_ptr<EVP_PKEY, decltype(&EVP_PKEY_free)>;
Key keyFromDer(const uint8_t* bytes, size_t length, bool privateKey) {
    if (!bytes || !length || length > static_cast<size_t>(std::numeric_limits<long>::max())) return {nullptr, EVP_PKEY_free};
    const unsigned char* pointer = bytes;
    EVP_PKEY* key = privateKey ? d2i_AutoPrivateKey(nullptr, &pointer, static_cast<long>(length))
        : d2i_PUBKEY(nullptr, &pointer, static_cast<long>(length));
    Key result(key, EVP_PKEY_free);
    if (!key || pointer != bytes + length || EVP_PKEY_base_id(key) != EVP_PKEY_EC) return {nullptr, EVP_PKEY_free};
    const EC_KEY* ec = EVP_PKEY_get0_EC_KEY(key);
    const int curve = ec ? EC_GROUP_get_curve_name(EC_KEY_get0_group(ec)) : 0;
    if ((curve != NID_X9_62_prime256v1 && curve != NID_secp384r1 && curve != NID_secp521r1) ||
        EC_KEY_check_key(ec) != 1) return {nullptr, EVP_PKEY_free};
    return result;
}
#endif
}

bool EcCryptoAvailable() {
#if defined(__APPLE__)
    return kudroid_ec_crypto != nullptr;
#elif defined(KUDROID_HAS_OPENSSL)
    return true;
#else
    return false;
#endif
}

bool GenerateEcKey(int bits, std::vector<uint8_t>* publicDer, std::vector<uint8_t>* privateDer) {
#if defined(__APPLE__)
    if (!kudroid_ec_crypto) return false;
    Output result;
    if (kudroid_ec_crypto(0, bits, nullptr, nullptr, 0, nullptr, 0, nullptr, 0, &result.bytes, &result.size) != 1 || result.size < 5) return false;
    const auto* bytes = static_cast<const uint8_t*>(result.bytes);
    const auto publicSize = read32(bytes);
    if (!publicSize || publicSize >= result.size - 4) return false;
    publicDer->assign(bytes + 4, bytes + 4 + publicSize);
    privateDer->assign(bytes + 4 + publicSize, bytes + result.size);
    return true;
#elif defined(KUDROID_HAS_OPENSSL)
    const int curve = bits == 256 ? NID_X9_62_prime256v1 : bits == 384 ? NID_secp384r1 : bits == 521 ? NID_secp521r1 : 0;
    if (!curve) return false;
    std::unique_ptr<EVP_PKEY_CTX, decltype(&EVP_PKEY_CTX_free)> context(EVP_PKEY_CTX_new_id(EVP_PKEY_EC, nullptr), EVP_PKEY_CTX_free);
    EVP_PKEY* generated = nullptr;
    if (!context || EVP_PKEY_keygen_init(context.get()) != 1 || EVP_PKEY_CTX_set_ec_paramgen_curve_nid(context.get(), curve) != 1 ||
        EVP_PKEY_keygen(context.get(), &generated) != 1) return false;
    Key key(generated, EVP_PKEY_free);
    const int publicSize = i2d_PUBKEY(key.get(), nullptr);
    std::unique_ptr<PKCS8_PRIV_KEY_INFO, decltype(&PKCS8_PRIV_KEY_INFO_free)> info(EVP_PKEY2PKCS8(key.get()), PKCS8_PRIV_KEY_INFO_free);
    const int privateSize = info ? i2d_PKCS8_PRIV_KEY_INFO(info.get(), nullptr) : 0;
    if (publicSize <= 0 || privateSize <= 0) return false;
    publicDer->resize(publicSize); privateDer->resize(privateSize);
    auto* pub = publicDer->data(); auto* priv = privateDer->data();
    return i2d_PUBKEY(key.get(), &pub) == publicSize && i2d_PKCS8_PRIV_KEY_INFO(info.get(), &priv) == privateSize;
#else
    return false;
#endif
}

bool InspectEcKey(const uint8_t* der, size_t length, bool privateKey, EcKeyInfo* info) {
#if defined(__APPLE__)
    if (!kudroid_ec_crypto) return false;
    Output result;
    if (kudroid_ec_crypto(privateKey ? 2 : 1, 0, nullptr, der, length, nullptr, 0, nullptr, 0, &result.bytes, &result.size) != 1 || result.size < 8) return false;
    const auto* bytes = static_cast<const uint8_t*>(result.bytes);
    const auto pointSize = read32(bytes + 4);
    if (pointSize > result.size - 8) return false;
    info->bits = static_cast<int>(read32(bytes));
    info->point.assign(bytes + 8, bytes + 8 + pointSize);
    info->scalar.assign(bytes + 8 + pointSize, bytes + result.size);
    return (info->bits == 256 || info->bits == 384 || info->bits == 521) &&
        pointSize == 1 + 2 * static_cast<size_t>((info->bits + 7) / 8) && !info->point.empty() && info->point[0] == 4;
#elif defined(KUDROID_HAS_OPENSSL)
    auto key = keyFromDer(der, length, privateKey);
    if (!key) return false;
    const EC_KEY* ec = EVP_PKEY_get0_EC_KEY(key.get());
    const EC_GROUP* group = EC_KEY_get0_group(ec);
    info->bits = EC_GROUP_get_degree(group);
    const size_t size = EC_POINT_point2oct(group, EC_KEY_get0_public_key(ec), POINT_CONVERSION_UNCOMPRESSED, nullptr, 0, nullptr);
    if (!size) return false;
    info->point.resize(size);
    if (EC_POINT_point2oct(group, EC_KEY_get0_public_key(ec), POINT_CONVERSION_UNCOMPRESSED, info->point.data(), size, nullptr) != size) return false;
    info->scalar.clear();
    if (privateKey) {
        info->scalar.resize((info->bits + 7) / 8);
        const auto* scalar = EC_KEY_get0_private_key(ec);
        if (!scalar || BN_bn2binpad(scalar, info->scalar.data(), static_cast<int>(info->scalar.size())) != static_cast<int>(info->scalar.size())) return false;
    }
    return true;
#else
    return false;
#endif
}

bool SignEc(const char* hash, const uint8_t* der, size_t length,
            const uint8_t* message, size_t messageLength, std::vector<uint8_t>* signature) {
#if defined(__APPLE__)
    if (!kudroid_ec_crypto) return false;
    Output result;
    if (kudroid_ec_crypto(3, 0, hash, der, length, message, messageLength, nullptr, 0, &result.bytes, &result.size) != 1) return false;
    const auto* data = static_cast<const uint8_t*>(result.bytes);
    signature->assign(data, data + result.size);
    return true;
#elif defined(KUDROID_HAS_OPENSSL)
    auto key = keyFromDer(der, length, true);
    if (hash && std::strcmp(hash, "NONE") == 0) {
        std::unique_ptr<EVP_PKEY_CTX, decltype(&EVP_PKEY_CTX_free)> raw(key ? EVP_PKEY_CTX_new(key.get(), nullptr) : nullptr, EVP_PKEY_CTX_free);
        size_t size = 0;
        if (!raw || EVP_PKEY_sign_init(raw.get()) != 1 || EVP_PKEY_sign(raw.get(), nullptr, &size, message, messageLength) != 1) return false;
        signature->resize(size);
        if (EVP_PKEY_sign(raw.get(), signature->data(), &size, message, messageLength) != 1) return false;
        signature->resize(size);
        return true;
    }
    const EVP_MD* digest = hash ? EVP_get_digestbyname(hash) : nullptr;
    std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)> context(EVP_MD_CTX_new(), EVP_MD_CTX_free);
    size_t size = 0;
    if (!key || !digest || !context || EVP_DigestSignInit(context.get(), nullptr, digest, nullptr, key.get()) != 1 ||
        EVP_DigestSign(context.get(), nullptr, &size, message, messageLength) != 1) return false;
    signature->resize(size);
    if (EVP_DigestSign(context.get(), signature->data(), &size, message, messageLength) != 1) return false;
    signature->resize(size);
    return true;
#else
    return false;
#endif
}

int VerifyEc(const char* hash, const uint8_t* der, size_t length,
             const uint8_t* message, size_t messageLength, const uint8_t* signature, size_t signatureLength) {
#if defined(__APPLE__)
    return kudroid_ec_crypto ? kudroid_ec_crypto(4, 0, hash, der, length, message, messageLength, signature, signatureLength, nullptr, nullptr) : -1;
#elif defined(KUDROID_HAS_OPENSSL)
    auto key = keyFromDer(der, length, false);
    if (hash && std::strcmp(hash, "NONE") == 0) {
        std::unique_ptr<EVP_PKEY_CTX, decltype(&EVP_PKEY_CTX_free)> raw(key ? EVP_PKEY_CTX_new(key.get(), nullptr) : nullptr, EVP_PKEY_CTX_free);
        if (!raw || EVP_PKEY_verify_init(raw.get()) != 1) return -1;
        return EVP_PKEY_verify(raw.get(), signature, signatureLength, message, messageLength) == 1 ? 1 : 0;
    }
    const EVP_MD* digest = hash ? EVP_get_digestbyname(hash) : nullptr;
    std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)> context(EVP_MD_CTX_new(), EVP_MD_CTX_free);
    if (!key || !digest || !context || EVP_DigestVerifyInit(context.get(), nullptr, digest, nullptr, key.get()) != 1) return -1;
    const int status = EVP_DigestVerify(context.get(), signature, signatureLength, message, messageLength);
    return status == 1 ? 1 : 0;
#else
    return -1;
#endif
}
}
