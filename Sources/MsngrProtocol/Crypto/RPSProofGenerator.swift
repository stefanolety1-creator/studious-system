import Foundation
#if canImport(CommonCrypto)
import CommonCrypto
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Protocol for generating the MSNP18 USR SSO S RPS cryptographic challenge proof.
public protocol RPSProofGeneratorProtocol: Sendable {
    func generateProof(binarySecretBase64: String, nonce: String, iv: Data?) throws -> String
}

/// Generates the minimal cryptographic proof strictly required by the MSNP18 / Passport RST2 login handshake.
///
/// Format: 28-byte little-endian header + 8-byte IV + 20-byte HMAC-SHA1 + 3DES-CBC encrypted nonce.
public final class RPSProofGenerator: RPSProofGeneratorProtocol, @unchecked Sendable {
    public init() {}

    public func generateProof(binarySecretBase64: String, nonce: String, iv: Data? = nil) throws -> String {
        guard let secret = Data(base64Encoded: binarySecretBase64), !secret.isEmpty else {
            throw PassportError.invalidCredentials
        }
        guard !nonce.isEmpty else {
            throw PassportError.invalidCredentials
        }

        // Derive hash key (24 bytes) and encryption key (24 bytes) via WS-SecureConversation HMAC-SHA1
        let hashKey = deriveKey(secret: secret, dataString: "SESSION KEY HASH")
        let encKey = deriveKey(secret: secret, dataString: "SESSION KEY ENCRYPTION")

        guard let nonceData = nonce.data(using: .utf8) else {
            throw PassportError.invalidCredentials
        }

        // Standard PKCS#7 padding to 8-byte boundary
        let blockSize = 8
        let padLen = blockSize - (nonceData.count % blockSize)
        var paddedNonce = nonceData
        paddedNonce.append(contentsOf: [UInt8](repeating: UInt8(padLen), count: padLen))

        // 8-byte IV: use supplied IV or generate random bytes
        let ivData: Data
        if let suppliedIv = iv, suppliedIv.count == 8 {
            ivData = suppliedIv
        } else {
            ivData = Data((0..<8).map { _ in UInt8.random(in: 0...255) })
        }

        // HMAC-SHA1 over unpadded nonce data using derived hashKey
        let hmac = computeHmacSha1(data: nonceData, key: hashKey)

        // 3DES-CBC encryption over PKCS#7 padded nonce using derived encKey
        let cipherText = try encrypt3DesCbc(data: paddedNonce, key: encKey, iv: ivData)

        // 28-byte little-endian header:
        // headerSize=28, structVersion=1, cipherAlg=0x6603 (3DES), hashAlg=0x8004 (SHA1), ivLen=8, hashLen=20, cipherLen
        var header = Data()
        header.append(uint32LE: 28)
        header.append(uint32LE: 1)
        header.append(uint32LE: 0x6603)
        header.append(uint32LE: 0x8004)
        header.append(uint32LE: UInt32(ivData.count))
        header.append(uint32LE: UInt32(hmac.count))
        header.append(uint32LE: UInt32(cipherText.count))

        // Final payload assembly: header + iv + hmac + cipherText
        var finalPacket = header
        finalPacket.append(ivData)
        finalPacket.append(hmac)
        finalPacket.append(cipherText)

        return finalPacket.base64EncodedString()
    }

    /// Derives session keys per WS-SecureConversation specification using iterative HMAC-SHA1.
    public func deriveKey(secret: Data, dataString: String) -> Data {
        guard let magic = "WS-SecureConversation".data(using: .utf8),
              let value = dataString.data(using: .utf8) else {
            return Data()
        }
        let p1 = magic + value
        let hash1 = computeHmacSha1(data: p1, key: secret)
        let hash2 = computeHmacSha1(data: hash1 + magic + value, key: secret)
        let hash3 = computeHmacSha1(data: hash1, key: secret)
        let hash4 = computeHmacSha1(data: hash3 + magic + value, key: secret)
        return hash2 + hash4.prefix(4)
    }

    private func computeHmacSha1(data: Data, key: Data) -> Data {
        #if canImport(CommonCrypto)
        var hmac = Data(count: Int(CC_SHA1_DIGEST_LENGTH))
        hmac.withUnsafeMutableBytes { hmacBytes in
            key.withUnsafeBytes { keyBytes in
                data.withUnsafeBytes { dataBytes in
                    CCHmac(
                        CCHmacAlgorithm(kCCHmacAlgSHA1),
                        keyBytes.baseAddress,
                        key.count,
                        dataBytes.baseAddress,
                        data.count,
                        hmacBytes.baseAddress
                    )
                }
            }
        }
        return hmac
        #elseif canImport(CryptoKit)
        let symKey = SymmetricKey(data: key)
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: data, using: symKey)
        return Data(mac)
        #else
        fatalError("CommonCrypto or CryptoKit is required for HMAC-SHA1")
        #endif
    }

    private func encrypt3DesCbc(data: Data, key: Data, iv: Data) throws -> Data {
        #if canImport(CommonCrypto)
        let keyBytesCount = 24
        let keyData: Data
        if key.count < keyBytesCount {
            var paddedKey = key
            paddedKey.append(contentsOf: [UInt8](repeating: 0, count: keyBytesCount - key.count))
            keyData = paddedKey
        } else {
            keyData = key.prefix(keyBytesCount)
        }

        var cipherData = Data(count: data.count + kCCBlockSize3DES)
        var numBytesEncrypted: size_t = 0

        let cryptStatus = keyData.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                data.withUnsafeBytes { dataBytes in
                    cipherData.withUnsafeMutableBytes { outBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithm3DES),
                            CCOptions(0),
                            keyBytes.baseAddress,
                            keyBytesCount,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress,
                            data.count,
                            outBytes.baseAddress,
                            outBytes.count,
                            &numBytesEncrypted
                        )
                    }
                }
            }
        }

        guard cryptStatus == kCCSuccess else {
            throw PassportError.cryptoFailed
        }
        cipherData.count = numBytesEncrypted
        return cipherData
        #else
        fatalError("CommonCrypto is required for 3DES-CBC encryption")
        #endif
    }
}

private extension Data {
    mutating func append(uint32LE val: UInt32) {
        var v = val.littleEndian
        withUnsafeBytes(of: &v) { self.append(contentsOf: $0) }
    }
}
