import Foundation
import IOKit.ps

struct PowerState: Equatable {
    var isOnAC: Bool
    var isCharging: Bool
    var level: Int
}

/// Watches IOKit power source changes and reports when the charger gets plugged in.
final class PowerMonitor {
    var onPluggedIn: ((PowerState) -> Void)?

    private var runLoopSource: CFRunLoopSource?
    private var lastState: PowerState?

    func start() {
        lastState = Self.readState()
        let context = Unmanaged.passUnretained(self).toOpaque()
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue().handleChange()
        }, context)?.takeRetainedValue()
        guard let source else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    private func handleChange() {
        guard let state = Self.readState() else { return }
        defer { lastState = state }
        if state.isOnAC, lastState?.isOnAC == false {
            onPluggedIn?(state)
        }
    }

    static func readState() -> PowerState? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            return PowerState(
                isOnAC: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                level: max > 0 ? current * 100 / max : 0
            )
        }
        return nil
    }
}
