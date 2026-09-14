import DeviceKit

public enum RegistryConsumer {
    public static func probe() -> String {
        let device = Device.current
        return "\(device.description):\(device.isSimulator)"
    }
}
