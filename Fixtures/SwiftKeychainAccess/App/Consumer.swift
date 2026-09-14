import KeychainAccess

public enum RegistryConsumer {
    public static func probe() throws -> String? {
        let keychain = Keychain(service: "dev.pkglift.SwiftKeychainAccess")
        try keychain.set("fixture", key: "probe")
        return try keychain.get("probe")
    }
}
