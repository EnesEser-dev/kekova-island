import AppKit
import SwiftUI

struct SettingsCard: View {
    @ObservedObject var launchAtLogin: LaunchAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at login")
                        .font(.system(size: 14, weight: .semibold))
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { launchAtLogin.isEnabled || launchAtLogin.needsApproval },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(.green)
            }

            if launchAtLogin.needsApproval {
                Button("Open Login Items settings") { launchAtLogin.openLoginItemsSettings() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: 0)

            HStack {
                Text("MacIsland \(Bundle.main.shortVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .padding(.top, 6)
        .onAppear { launchAtLogin.refresh() }
    }

    private var statusText: String {
        if let error = launchAtLogin.lastError { return error }
        switch launchAtLogin.status {
        case .enabled: return "Starts automatically when you log in"
        case .requiresApproval: return "Waiting for approval in System Settings"
        default: return "Off"
        }
    }
}

private extension Bundle {
    var shortVersion: String {
        object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
