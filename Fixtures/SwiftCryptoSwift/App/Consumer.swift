import CryptoSwift

public enum RegistryConsumer {
    public static func probe() -> String {
        SHA2(variant: .sha256).calculate(for: Array("PkgLift consumer probe".utf8)).toHexString()
    }
}
