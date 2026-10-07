import Foundation
import IOBluetooth

struct HeadphoneInfo: Equatable {
    var name: String
    var symbolName: String
    var batteryLevel: Int?
}

/// Reports Bluetooth audio devices (AirPods, headphones) as they connect.
final class HeadphoneMonitor: NSObject {
    var onConnected: ((HeadphoneInfo) -> Void)?

    /// Battery levels arrive a moment after the connection itself.
    private static let batteryReadDelay: TimeInterval = 2
    /// Registering fires once for every device that is already connected; ignore those.
    private static let startupGracePeriod: TimeInterval = 3
    private static let audioMajorClass: BluetoothDeviceClassMajor = 0x04

    private var notification: IOBluetoothUserNotification?
    private var startedAt = Date()

    func start() {
        startedAt = Date()
        notification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    @objc private func deviceConnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard
            Date().timeIntervalSince(startedAt) > Self.startupGracePeriod,
            device.deviceClassMajor == Self.audioMajorClass
        else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.batteryReadDelay) { [weak self] in
            let name = device.name ?? "Headphones"
            self?.onConnected?(HeadphoneInfo(
                name: name,
                symbolName: Self.symbolName(for: name),
                batteryLevel: Self.batteryLevel(of: device)
            ))
        }
    }

    private static func symbolName(for name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("airpods max") { return "airpodsmax" }
        if lowered.contains("airpods pro") { return "airpodspro" }
        if lowered.contains("airpods") { return "airpods" }
        if lowered.contains("beats") { return "beats.headphones" }
        if ["buds", "liberty", "earbuds"].contains(where: lowered.contains) { return "earbuds" }
        return "headphones"
    }

    /// IOBluetoothDevice exposes battery levels only through undocumented properties, so
    /// check each selector exists before asking. Earbuds report left/right, others "single".
    private static func batteryLevel(of device: IOBluetoothDevice) -> Int? {
        let keys = ["batteryPercentSingle", "batteryPercentLeft", "batteryPercentRight"]
        let levels = keys.compactMap { key -> Int? in
            guard device.responds(to: NSSelectorFromString(key)) else { return nil }
            let value = (device.value(forKey: key) as? NSNumber)?.intValue ?? 0
            return value > 0 ? value : nil
        }
        return levels.min()
    }
}
