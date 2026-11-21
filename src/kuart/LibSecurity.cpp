#include "kudroid/kuart/LibCore.h"
#include "kudroid/kuart/DexClass.h"
#include "kudroid/kuart/DexObject.h"
#include "kudroid/kuart/DexString.h"
#include "kudroid/kuart/DexClassLinker.h"
#include "kudroid/kuart/Interpreter.h"
#include "kudroid/platform/RsaSignature.h"
#include "kudroid/platform/SymmetricCrypto.h"
#include "kudroid/platform/EcCrypto.h"
#include "kudroid/kuart/VmLock.h"

#include <cstring>
#include <new>
#include <vector>

namespace kudroid::kuart {
namespace {
struct CryptoBytes : std::vector<uint8_t> {
    using std::vector<uint8_t>::vector;
    CryptoBytes(const std::vector<uint8_t>& bytes) : std::vector<uint8_t>(bytes) {}
    ~CryptoBytes() {
        volatile uint8_t* p = data();
        for (size_t i = 0; i < size(); ++i) p[i] = 0;
    }
};

DexArray* Bytes(const DexValue& v) {
    auto* array = reinterpret_cast<DexArray*>(v.l);
    return array && array->clazz && array->clazz->descriptor &&
           !std::strcmp(array->clazz->descriptor, "[B") ? array : nullptr;
}

bool ReturnBytes(Interpreter* interp, const std::vector<uint8_t>& bytes, DexValue* result) {
    auto* klass = interp->linker()->FindClass("[B");
    auto* array = klass ? interp->linker()->AllocArray(klass, static_cast<int32_t>(bytes.size())) : nullptr;
    if (!array) {
        interp->ThrowException("Ljava/lang/OutOfMemoryError;", "Crypto result allocation failed");
        return true;
    }
    if (!bytes.empty()) std::memcpy(array->Data(), bytes.data(), bytes.size());
    result->l = array;
    return true;
}

bool ReturnByteArrays(Interpreter* interp, const std::vector<CryptoBytes>& rows, DexValue* result) {
    auto* type = interp->linker()->FindClass("[[B");
    auto* array = type ? interp->linker()->AllocArray(type, static_cast<int32_t>(rows.size())) : nullptr;
    if (!array) { interp->ThrowException("Ljava/lang/OutOfMemoryError;", "Key allocation failed"); return true; }
    for (size_t i = 0; i < rows.size(); ++i) {
        DexValue item;
        ReturnBytes(interp, rows[i], &item);
        if (interp->HasPendingException()) return true;
        array->Set<DexObject*>(static_cast<int32_t>(i), item.l);
    }
    result->l = array;
    return true;
}

bool InvokeEc(Interpreter* interp, const char* name, const DexValue* args, size_t count, DexValue* result) {
    if (!std::strcmp(name, "ecAvailable") && count == 0) {
        *result = DexValue::Int(EcCryptoAvailable()); return true;
    }
    if (!std::strcmp(name, "generateEcKeyPair") && count == 1) {
        std::vector<uint8_t> publicKey; CryptoBytes privateKey;
        bool ready;
        { VmLockRelease release; ready = GenerateEcKey(args[0].i, &publicKey, &privateKey); }
        if (!ready) { interp->ThrowException("Ljava/security/ProviderException;", "EC key generation failed"); return true; }
        return ReturnByteArrays(interp, {publicKey, privateKey}, result);
    }
    if (!std::strcmp(name, "inspectEcKey") && count == 2) {
        auto* key = Bytes(args[0]); EcKeyInfo info;
        bool valid = false;
        if (key) { VmLockRelease release; valid = InspectEcKey(key->Data(), key->length, args[1].i != 0, &info); }
        if (!valid) { result->l = nullptr; return true; }
        return ReturnByteArrays(interp, {{static_cast<uint8_t>(info.bits >> 8), static_cast<uint8_t>(info.bits)}, info.point, info.scalar}, result);
    }
    if (!std::strcmp(name, "signEc") && count == 3) {
        auto* hash = reinterpret_cast<DexString*>(args[0].l);
        auto* key = Bytes(args[1]); auto* message = Bytes(args[2]); std::vector<uint8_t> signature;
        bool signedValue = false;
        if (hash && key && message) {
            VmLockRelease release;
            signedValue = SignEc(hash->utf8, key->Data(), key->length, message->Data(), message->length, &signature);
        }
        if (!signedValue) { interp->ThrowException("Ljava/security/SignatureException;", "EC signing failed"); return true; }
        return ReturnBytes(interp, signature, result);
    }
    if (!std::strcmp(name, "verifyEc") && count == 4) {
        auto* hash = reinterpret_cast<DexString*>(args[0].l);
        auto* key = Bytes(args[1]); auto* message = Bytes(args[2]); auto* signature = Bytes(args[3]);
        int verified = -1;
        if (hash && key && message && signature) {
            VmLockRelease release;
            verified = VerifyEc(hash->utf8, key->Data(), key->length, message->Data(), message->length, signature->Data(), signature->length);
        }
        *result = DexValue::Int(verified); return true;
    }
    return false;
}

bool InvokeSymmetric(Interpreter* interp, const char* name, const DexValue* args,
                     size_t num_args, DexValue* result) {
    if (!std::strcmp(name, "symmetricAvailable") && num_args == 0) {
        *result = DexValue::Int(SymmetricCryptoAvailable());
        return true;
    }
    if (!std::strcmp(name, "digest") && num_args == 2) {
        auto* algorithm = reinterpret_cast<DexString*>(args[0].l);
        auto* input = Bytes(args[1]); CryptoBytes bytes;
        bool valid = false;
        if (algorithm && input) {
            VmLockRelease release;
            valid = CryptoDigest(algorithm->utf8, input->Data(), input->length, &bytes);
        }
        if (!valid) { interp->ThrowException("Ljava/security/ProviderException;", "Digest failed"); return true; }
        return ReturnBytes(interp, bytes, result);
    }
    if (!std::strcmp(name, "pkcs12Sha1Key") && num_args == 3) {
        auto* password = reinterpret_cast<DexArray*>(args[0].l);
        DexArray* salt = Bytes(args[1]);
        CryptoBytes bytes;
        if (!password || !password->clazz || !password->clazz->descriptor ||
            std::strcmp(password->clazz->descriptor, "[C") || !salt ||
            !Pkcs12Sha1Key(reinterpret_cast<const uint16_t*>(password->Data()), password->length,
                          salt->Data(), salt->length, args[2].i, &bytes)) {
            interp->ThrowException("Ljava/security/spec/InvalidKeySpecException;", "PBE derivation failed");
            return true;
        }
        return ReturnBytes(interp, bytes, result);
    }
    if (!std::strcmp(name, "aesCbc") && num_args == 4) {
        DexArray* key = Bytes(args[1]);
        DexArray* iv = Bytes(args[2]);
        DexArray* input = Bytes(args[3]);
        CryptoBytes bytes;
        int status = key && iv && input ? AesCbc(args[0].i != 0, key->Data(), key->length,
            iv->Data(), iv->length, input->Data(), input->length, &bytes) : -1;
        if (status) {
            const char* exception = status == -2 ? "Ljavax/crypto/IllegalBlockSizeException;" :
                status == -3 ? "Ljavax/crypto/BadPaddingException;" : "Ljava/security/ProviderException;";
            interp->ThrowException(exception, "AES CBC operation failed");
            return true;
        }
        return ReturnBytes(interp, bytes, result);
    }
    if (!std::strcmp(name, "randomBytes") && num_args == 1) {
        if (args[0].i < 0) {
            interp->ThrowException("Ljava/lang/IllegalArgumentException;", "Negative random byte count");
            return true;
        }
        CryptoBytes bytes(static_cast<size_t>(args[0].i));
        if (!CryptoRandomBytes(bytes.data(), bytes.size())) {
            interp->ThrowException("Ljava/security/ProviderException;", "Random source unavailable");
            return true;
        }
        return ReturnBytes(interp, bytes, result);
    }
    return false;
}
}

bool Invoke_libcore_io_KuCrypto(Interpreter* interp, const char* name, const DexValue* args,
                               size_t num_args, DexValue* result) {
    try {
        if (InvokeEc(interp, name, args, num_args, result)) return true;
    } catch (const std::bad_alloc&) {
        interp->ThrowException("Ljava/lang/OutOfMemoryError;", "Key allocation failed"); return true;
    }
    if (!std::strcmp(name, "rsaAvailable") && num_args == 0) {
        *result = DexValue::Int(RsaAvailable());
        return true;
    }
    if (!std::strcmp(name, "validateRsaSpki") && num_args == 1) {
        DexArray* key = Bytes(args[0]);
        *result = DexValue::Int(key && ValidateRsaSpki(key->Data(), key->length));
        return true;
    }
    if (!std::strcmp(name, "verifyRsaSignature") && num_args == 4) {
        auto* algorithm = reinterpret_cast<DexString*>(args[0].l);
        DexArray* key = Bytes(args[1]);
        DexArray* message = Bytes(args[2]);
        DexArray* signature = Bytes(args[3]);
        *result = DexValue::Int(algorithm && key && message && signature
            ? VerifyRsaSignature(algorithm->utf8, key->Data(), key->length,
                                 message->Data(), message->length, signature->Data(), signature->length) : -1);
        return true;
    }
    try {
        return InvokeSymmetric(interp, name, args, num_args, result);
    } catch (const std::bad_alloc&) {
        interp->ThrowException("Ljava/lang/OutOfMemoryError;", "Crypto allocation failed");
        return true;
    }
}
}  // namespace
