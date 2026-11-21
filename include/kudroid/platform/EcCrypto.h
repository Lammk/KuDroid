#pragma once
#include <cstddef>
#include <cstdint>
#include <vector>

namespace kudroid {
struct EcKeyInfo {
    int bits = 0;
    std::vector<uint8_t> point;
    std::vector<uint8_t> scalar;
    ~EcKeyInfo() {
        volatile uint8_t* bytes = scalar.data();
        for (size_t i = 0; i < scalar.size(); ++i) bytes[i] = 0;
    }
};
bool EcCryptoAvailable();
bool GenerateEcKey(int bits, std::vector<uint8_t>* publicDer, std::vector<uint8_t>* privateDer);
bool InspectEcKey(const uint8_t* der, size_t length, bool privateKey, EcKeyInfo* info);
bool SignEc(const char* hash, const uint8_t* der, size_t length,
            const uint8_t* message, size_t messageLength, std::vector<uint8_t>* signature);
int VerifyEc(const char* hash, const uint8_t* der, size_t length,
             const uint8_t* message, size_t messageLength, const uint8_t* signature, size_t signatureLength);
}
