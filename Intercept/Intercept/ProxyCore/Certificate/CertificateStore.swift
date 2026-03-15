import Foundation
import Crypto
import X509
import SwiftASN1
import NIOSSL

final class CertificateStore: @unchecked Sendable {

    private let rootCA: Certificate
    private let rootKey: P256.Signing.PrivateKey
    private var cache: [String: (certificate: NIOSSLCertificate, key: NIOSSLPrivateKey)] = [:]
    private let lock = NSLock()

    init(rootCA: Certificate, rootKey: P256.Signing.PrivateKey) {
        self.rootCA = rootCA
        self.rootKey = rootKey
    }

    /// Returns a TLS server configuration with a certificate for the given hostname.
    func tlsConfiguration(forHost host: String) throws -> TLSConfiguration {
        let (cert, key) = try certificateForHost(host)

        var rootSerializer = DER.Serializer()
        try rootSerializer.serialize(rootCA)
        let rootNIOCert = try NIOSSLCertificate(bytes: rootSerializer.serializedBytes, format: .der)

        var config = TLSConfiguration.makeServerConfiguration(
            certificateChain: [.certificate(cert), .certificate(rootNIOCert)],
            privateKey: .privateKey(key)
        )
        config.minimumTLSVersion = .tlsv12
        return config
    }

    // MARK: - Private

    private func certificateForHost(_ host: String) throws -> (certificate: NIOSSLCertificate, key: NIOSSLPrivateKey) {
        try lock.withLock {
            if let cached = cache[host] {
                return cached
            }

            let result = try generateCertificate(for: host)
            cache[host] = result
            return result
        }
    }

    private func generateCertificate(for host: String) throws -> (certificate: NIOSSLCertificate, key: NIOSSLPrivateKey) {
        let leafKey = P256.Signing.PrivateKey()
        let leafCertKey = Certificate.PrivateKey(leafKey)

        let subject = try DistinguishedName {
            CommonName(host)
            OrganizationName("Intercept")
        }

        let certificate = try Certificate(
            version: .v3,
            serialNumber: .init(),
            publicKey: leafCertKey.publicKey,
            notValidBefore: Date().addingTimeInterval(-86400),
            notValidAfter: Date().addingTimeInterval(86400 * 365),
            issuer: rootCA.subject,
            subject: subject,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                KeyUsage(digitalSignature: true)
                SubjectAlternativeNames([.dnsName(host)])
                try ExtendedKeyUsage([.serverAuth])
            },
            issuerPrivateKey: Certificate.PrivateKey(rootKey)
        )

        // Convert to NIOSSL types
        var certSerializer = DER.Serializer()
        try certSerializer.serialize(certificate)
        let niosslCert = try NIOSSLCertificate(bytes: certSerializer.serializedBytes, format: .der)

        let keyPEM = try Certificate.PrivateKey(leafKey).serializeAsPEM()
        let niosslKey = try NIOSSLPrivateKey(bytes: [UInt8](keyPEM.pemString.utf8), format: .pem)

        return (niosslCert, niosslKey)
    }
}
