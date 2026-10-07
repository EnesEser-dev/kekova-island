import SwiftUI

/// Content for the widened collapsed island: a label on the left wing, a value on the right.
struct BannerContent: View {
    let banner: IslandBanner
    let notchWidth: CGFloat
    let wingWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                leading
            }
            .frame(width: wingWidth, alignment: .leading)
            .padding(.leading, 14)

            Spacer(minLength: notchWidth - 28)

            HStack(spacing: 6) {
                trailing
            }
            .frame(width: wingWidth, alignment: .trailing)
            .padding(.trailing, 14)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
    }

    @ViewBuilder
    private var leading: some View {
        switch banner {
        case .charging:
            Image(systemName: "bolt.fill")
                .foregroundStyle(.green)
            Text("Charging")
        case .headphones(let info):
            Image(systemName: info.symbolName)
                .font(.system(size: 14))
            Text(info.name)
                .truncationMode(.tail)
        case .screenshot:
            Image(systemName: "camera.viewfinder")
            Text("Screenshot")
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch banner {
        case .charging(let level):
            Text("\(level)%")
                .foregroundStyle(.green)
                .monospacedDigit()
            BatteryGlyph(level: level, color: .green)
        case .headphones(let info):
            if let level = info.batteryLevel {
                Text("\(level)%")
                    .monospacedDigit()
                BatteryGlyph(level: level, color: level <= 20 ? .red : .white)
            } else {
                Text("Connected")
                    .foregroundStyle(.white.opacity(0.6))
            }
        case .screenshot:
            Text("On shelf")
                .foregroundStyle(.white.opacity(0.6))
            Image(systemName: "tray.full.fill")
        }
    }
}

/// Battery outline whose fill sweeps up to the level when it appears.
private struct BatteryGlyph: View {
    let level: Int
    let color: Color

    @State private var shownLevel = 0

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .stroke(.white.opacity(0.4), lineWidth: 1)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: max(CGFloat(shownLevel) / 100 * 19, 2))
                    .padding(1.5)
            }
            .frame(width: 24, height: 12)
            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.4))
                .frame(width: 1.5, height: 4)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.15)) { shownLevel = level }
        }
    }
}
