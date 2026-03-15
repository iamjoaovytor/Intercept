import Foundation
import Crypto
import X509
import SwiftASN1
import Security

final class RootCAManager: @unchecked Sendable {

    private let storageURL: URL
    private let lock = NSLock()
    private var cachedCA: (certificate: Certificate, privateKey: P256.Signing.PrivateKey)?

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        storageURL = appSupport.appendingPathComponent("Intercept", isDirectory: true)
    }

    /// Returns the root CA, generating and persisting it on first call.
    func rootCA() throws -> (certificate: Certificate, privateKey: P256.Signing.PrivateKey) {
        try lock.withLock {
            if let cached = cachedCA {
                return cached
            }

            if let loaded = try? loadFromDisk() {
                cachedCA = loaded
                return loaded
            }

            let ca = try generateRootCA()
            try saveToDisk(certificate: ca.certificate, privateKey: ca.privateKey)
            cachedCA = ca
            return ca
        }
    }

    /// Installs the root CA in the user Keychain and marks it as trusted.
    /// May prompt for user authentication (password/Touch ID).
    func installInKeychainIfNeeded() throws {
        let ca = try rootCA()

        if isAlreadyTrusted() { return }

        // Serialize certificate to DER
        var serializer = DER.Serializer()
        try serializer.serialize(ca.certificate)
        let certData = Data(serializer.serializedBytes)

        // Add to Keychain (or skip if already there)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueData as String: certData,
            kSecAttrLabel as String: keychainLabel,
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            throw RootCAError.keychainAddFailed(addStatus)
        }

        // Get certificate reference
        let certRef = try keychainCertificateRef()

        // Set trust settings — prompts user for authentication
        let trustSettings: [[String: Any]] = [
            [kSecTrustSettingsResult as String: SecTrustSettingsResult.trustRoot.rawValue]
        ]

        let trustStatus = SecTrustSettingsSetTrustSettings(certRef, .user, trustSettings as CFArray)
        guard trustStatus == errSecSuccess else {
            throw RootCAError.trustSettingsFailed(trustStatus)
        }
    }

    // MARK: - Private

    private let keychainLabel = "Intercept Root CA"

    private func isAlreadyTrusted() -> Bool {
        guard let certRef = try? keychainCertificateRef() else { return false }
        var trustSettings: CFArray?
        return SecTrustSettingsCopyTrustSettings(certRef, .user, &trustSettings) == errSecSuccess
    }

    private func keychainCertificateRef() throws -> SecCertificate {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: keychainLabel,
            kSecReturnRef as String: true,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let ref = item else {
            throw RootCAError.keychainGetFailed(status)
        }
        return ref as! SecCertificate
    }

    private func generateRootCA() throws -> (certificate: Certificate, privateKey: P256.Signing.PrivateKey) {
        let privateKey = P256.Signing.PrivateKey()
        let certKey = Certificate.PrivateKey(privateKey)

        let name = try DistinguishedName {
            CommonName("Intercept Root CA")
            OrganizationName("Intercept")
        }

        let certificate = try Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: certKey.publicKey,
            notValidBefore: Date(),
            notValidAfter: Date().addingTimeInterval(86400 * 365 * 10),
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: Certificate.Extensions {
                Critical(BasicConstraints.isCertificateAuthority(maxPathLength: nil))
                KeyUsage(keyCertSign: true, cRLSign: true)
            },
            issuerPrivateKey: certKey
        )

        return (certificate, privateKey)
    }

    private func saveToDisk(certificate: Certificate, privateKey: P256.Signing.PrivateKey) throws {
        try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)

        let certPEM = try certificate.serializeAsPEM()
        try certPEM.pemString.write(
            to: storageURL.appendingPathComponent("root-ca.pem"),
            atomically: true, encoding: .utf8
        )

        let keyPEM = try Certificate.PrivateKey(privateKey).serializeAsPEM()
        try keyPEM.pemString.write(
            to: storageURL.appendingPathComponent("root-ca-key.pem"),
            atomically: true, encoding: .utf8
        )
    }

    private func loadFromDisk() throws -> (certificate: Certificate, privateKey: P256.Signing.PrivateKey) {
        let certPEM = try String(contentsOf: storageURL.appendingPathComponent("root-ca.pem"), encoding: .utf8)
        let keyPEM = try String(contentsOf: storageURL.appendingPathComponent("root-ca-key.pem"), encoding: .utf8)

        let certificate = try Certificate(pemEncoded: certPEM)
        let p256Key = try P256.Signing.PrivateKey(pemRepresentation: keyPEM)

        return (certificate, p256Key)
    }
}

// MARK: - Errors

enum RootCAError: Error, LocalizedError {
    case keychainAddFailed(OSStatus)
    case keychainGetFailed(OSStatus)
    case trustSettingsFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainAddFailed(let s): "Failed to add certificate to Keychain (status: \(s))"
        case .keychainGetFailed(let s): "Failed to retrieve certificate from Keychain (status: \(s))"
        case .trustSettingsFailed(let s): "Failed to set trust settings (status: \(s))"
        }
    }
}
