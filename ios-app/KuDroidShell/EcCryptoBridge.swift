import CryptoKit
import Foundation
import Security

private protocol ECDerSignature { var derRepresentation: Data { get } }
private protocol ECPublicSigningKey {
    associatedtype Signature: ECDerSignature
    init(der: Data) throws
    var derRepresentation: Data { get }
    var x963Representation: Data { get }
    static func signature(der: Data) throws -> Signature
    func isValidSignature<D: Digest>(_ signature: Signature, for digest: D) -> Bool
}
private protocol ECPrivateSigningKey {
    associatedtype Public: ECPublicSigningKey
    associatedtype Signature: ECDerSignature
    init(der: Data) throws
    static func generate() -> Self
    var publicKey: Public { get }
    var derRepresentation: Data { get }
    var rawRepresentation: Data { get }
    func signature<D: Digest>(for digest: D) throws -> Signature
}

extension P256.Signing.ECDSASignature: ECDerSignature {}
extension P384.Signing.ECDSASignature: ECDerSignature {}
extension P521.Signing.ECDSASignature: ECDerSignature {}
extension P256.Signing.PrivateKey: ECPrivateSigningKey {
    fileprivate init(der: Data) throws { try self.init(derRepresentation: der) }
    fileprivate static func generate() -> Self { Self(compactRepresentable: false) }
}
extension P384.Signing.PrivateKey: ECPrivateSigningKey {
    fileprivate init(der: Data) throws { try self.init(derRepresentation: der) }
    fileprivate static func generate() -> Self { Self(compactRepresentable: false) }
}
extension P521.Signing.PrivateKey: ECPrivateSigningKey {
    fileprivate init(der: Data) throws { try self.init(derRepresentation: der) }
    fileprivate static func generate() -> Self { Self(compactRepresentable: false) }
}
extension P256.Signing.PublicKey: ECPublicSigningKey {
    fileprivate init(der: Data) throws { try self.init(derRepresentation: der) }
    fileprivate static func signature(der: Data) throws -> P256.Signing.ECDSASignature {
        try P256.Signing.ECDSASignature(derRepresentation: der)
    }
}
extension P384.Signing.PublicKey: ECPublicSigningKey {
    fileprivate init(der: Data) throws { try self.init(derRepresentation: der) }
    fileprivate static func signature(der: Data) throws -> P384.Signing.ECDSASignature {
        try P384.Signing.ECDSASignature(derRepresentation: der)
    }
}
extension P521.Signing.PublicKey: ECPublicSigningKey {
    fileprivate init(der: Data) throws { try self.init(derRepresentation: der) }
    fileprivate static func signature(der: Data) throws -> P521.Signing.ECDSASignature {
        try P521.Signing.ECDSASignature(derRepresentation: der)
    }
}

private enum ECBridgeError: Error { case unsupported }
private func ecSecurityKey(_ bytes: Data, bits: Int, privateKey: Bool) throws -> SecKey {
    let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeyClass: privateKey ? kSecAttrKeyClassPrivate : kSecAttrKeyClassPublic,
        kSecAttrKeySizeInBits: bits]
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateWithData(bytes as CFData, attributes as CFDictionary, &error) else {
        if let error { throw error.takeRetainedValue() }
        throw ECBridgeError.unsupported
    }
    return key
}
private func ecHeader(_ value: Int) -> Data {
    Data([UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
          UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)])
}
private func ecSign<K: ECPrivateSigningKey>(_ key: K, bits: Int, hash: String, message: Data) throws -> Data {
    switch hash {
    case "NONE":
        let nativeKey = try ecSecurityKey(key.publicKey.x963Representation + key.rawRepresentation, bits: bits, privateKey: true)
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(nativeKey, .ecdsaSignatureDigestX962, message as CFData, &error) else {
            if let error { throw error.takeRetainedValue() }
            throw ECBridgeError.unsupported
        }
        return signature as Data
    case "SHA1": return try key.signature(for: Insecure.SHA1.hash(data: message)).derRepresentation
    case "SHA256": return try key.signature(for: SHA256.hash(data: message)).derRepresentation
    case "SHA384": return try key.signature(for: SHA384.hash(data: message)).derRepresentation
    case "SHA512": return try key.signature(for: SHA512.hash(data: message)).derRepresentation
    default: throw ECBridgeError.unsupported
    }
}
private func ecVerify<K: ECPublicSigningKey>(_ key: K, bits: Int, hash: String, message: Data, encoded: Data) throws -> Bool {
    guard let signature = try? K.signature(der: encoded) else { return false }
    switch hash {
    case "NONE":
        let nativeKey = try ecSecurityKey(key.x963Representation, bits: bits, privateKey: false)
        return SecKeyVerifySignature(nativeKey, .ecdsaSignatureDigestX962, message as CFData, encoded as CFData, nil)
    case "SHA1": return key.isValidSignature(signature, for: Insecure.SHA1.hash(data: message))
    case "SHA256": return key.isValidSignature(signature, for: SHA256.hash(data: message))
    case "SHA384": return key.isValidSignature(signature, for: SHA384.hash(data: message))
    case "SHA512": return key.isValidSignature(signature, for: SHA512.hash(data: message))
    default: throw ECBridgeError.unsupported
    }
}
private func ecOperation<K: ECPrivateSigningKey>(_ type: K.Type, bits: Int, operation: Int32,
    hash: String, key: Data, message: Data, signature: Data) throws -> (Int32, Data) {
    switch operation {
    case 0:
        let pair = K.generate()
        let publicKey = pair.publicKey.derRepresentation
        return (1, ecHeader(publicKey.count) + publicKey + pair.derRepresentation)
    case 1:
        let publicKey = try K.Public(der: key)
        let point = publicKey.x963Representation
        return (1, ecHeader(bits) + ecHeader(point.count) + point)
    case 2:
        let privateKey = try K(der: key)
        let point = privateKey.publicKey.x963Representation
        return (1, ecHeader(bits) + ecHeader(point.count) + point + privateKey.rawRepresentation)
    case 3: return (1, try ecSign(K(der: key), bits: bits, hash: hash, message: message))
    case 4: return (try ecVerify(K.Public(der: key), bits: bits, hash: hash, message: message, encoded: signature) ? 1 : 0, Data())
    default: throw ECBridgeError.unsupported
    }
}

@_cdecl("kudroid_ec_crypto")
public func kudroid_ec_crypto(_ operation: Int32, _ bits: Int32, _ hash: UnsafePointer<CChar>?,
    _ key: UnsafePointer<UInt8>?, _ keyLength: Int, _ message: UnsafePointer<UInt8>?, _ messageLength: Int,
    _ signature: UnsafePointer<UInt8>?, _ signatureLength: Int,
    _ output: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, _ outputLength: UnsafeMutablePointer<Int>?) -> Int32 {
    output?.pointee = nil; outputLength?.pointee = 0
    guard keyLength >= 0, messageLength >= 0, signatureLength >= 0,
          keyLength == 0 || key != nil, messageLength == 0 || message != nil,
          signatureLength == 0 || signature != nil else { return -1 }
    let keyData = key.map { Data(bytes: $0, count: keyLength) } ?? Data()
    let messageData = message.map { Data(bytes: $0, count: messageLength) } ?? Data()
    let signatureData = signature.map { Data(bytes: $0, count: signatureLength) } ?? Data()
    let hashName = hash.map { String(cString: $0) } ?? ""
    let result: (Int32, Data)
    do {
        if operation == 0 {
            switch bits {
            case 256: result = try ecOperation(P256.Signing.PrivateKey.self, bits: 256, operation: operation, hash: hashName, key: keyData, message: messageData, signature: signatureData)
            case 384: result = try ecOperation(P384.Signing.PrivateKey.self, bits: 384, operation: operation, hash: hashName, key: keyData, message: messageData, signature: signatureData)
            case 521: result = try ecOperation(P521.Signing.PrivateKey.self, bits: 521, operation: operation, hash: hashName, key: keyData, message: messageData, signature: signatureData)
            default: return -1
            }
        } else if let value = try? ecOperation(P256.Signing.PrivateKey.self, bits: 256, operation: operation, hash: hashName, key: keyData, message: messageData, signature: signatureData) {
            result = value
        } else if let value = try? ecOperation(P384.Signing.PrivateKey.self, bits: 384, operation: operation, hash: hashName, key: keyData, message: messageData, signature: signatureData) {
            result = value
        } else {
            result = try ecOperation(P521.Signing.PrivateKey.self, bits: 521, operation: operation, hash: hashName, key: keyData, message: messageData, signature: signatureData)
        }
    } catch { return -1 }
    if !result.1.isEmpty {
        guard let output, let outputLength, let allocated = malloc(result.1.count) else { return -1 }
        result.1.copyBytes(to: allocated.assumingMemoryBound(to: UInt8.self), count: result.1.count)
        output.pointee = allocated; outputLength.pointee = result.1.count
    }
    return result.0
}
