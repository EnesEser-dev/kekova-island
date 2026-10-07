import AppKit
import SwiftUI

struct IslandView: View {
    @ObservedObject var model: IslandViewModel
    @ObservedObject var nowPlaying: NowPlayingService

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                IslandShape(bottomRadius: model.isExpanded ? 30 : 10)
                    .fill(.black)

                if model.isExpanded {
                    ExpandedContent(nowPlaying: nowPlaying)
                        .padding(.top, model.notchSize.height + 8)
                        .padding(.horizontal, IslandShape.earRadius + 22)
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
                } else if model.isCompactVisible, let info = nowPlaying.info {
                    CompactNowPlaying(info: info, notchSize: model.notchSize, wingWidth: model.compactWingWidth)
                        .padding(.horizontal, IslandShape.earRadius)
                        .transition(.opacity)
                }
            }
            .frame(width: model.currentSize.width + 2 * IslandShape.earRadius, height: model.currentSize.height)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Black body with rounded bottom corners and small concave "ears" at the top,
/// so it flows out of the menu bar the way the hardware notch does.
struct IslandShape: Shape {
    static let earRadius: CGFloat = 8
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let ear = Self.earRadius
        let radius = min(bottomRadius, (rect.width - 2 * ear) / 2, rect.height - ear)
        let left = rect.minX + ear
        let right = rect.maxX - ear

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.minY + ear), control: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: left + radius, y: rect.maxY), control: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: right - radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.maxY - radius), control: CGPoint(x: right, y: rect.maxY))
        path.addLine(to: CGPoint(x: right, y: rect.minY + ear))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Compact

private struct CompactNowPlaying: View {
    let info: NowPlayingInfo
    let notchSize: CGSize
    let wingWidth: CGFloat

    var body: some View {
        let artSize = notchSize.height - 12
        HStack(spacing: 0) {
            Artwork(image: info.artwork, cornerRadius: 5)
                .frame(width: artSize, height: artSize)
                .frame(width: wingWidth)
            Spacer(minLength: notchSize.width)
            EqualizerBars(color: Color(nsColor: info.accentColor), isAnimating: info.isPlaying)
                .frame(width: artSize * 0.8, height: artSize * 0.6)
                .frame(width: wingWidth)
        }
        .frame(height: notchSize.height)
    }
}

private struct EqualizerBars: View {
    let color: Color
    let isAnimating: Bool

    private static let phases: [Double] = [0, 1.7, 0.9, 2.6]

    var body: some View {
        TimelineView(.animation(paused: !isAnimating)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                HStack(alignment: .center, spacing: proxy.size.width * 0.12) {
                    ForEach(Self.phases.indices, id: \.self) { index in
                        let wave = isAnimating ? (sin(time * 7 + Self.phases[index]) + 1) / 2 : 0
                        Capsule()
                            .fill(color)
                            .frame(height: proxy.size.height * (0.25 + 0.75 * wave))
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Expanded

private struct ExpandedContent: View {
    @ObservedObject var nowPlaying: NowPlayingService

    var body: some View {
        if let info = nowPlaying.info {
            NowPlayingCard(info: info, nowPlaying: nowPlaying)
        } else {
            ClockCard()
        }
    }
}

private struct NowPlayingCard: View {
    let info: NowPlayingInfo
    let nowPlaying: NowPlayingService

    private var accent: Color { Color(nsColor: info.accentColor) }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                Button {
                    nowPlaying.openSourceApp()
                } label: {
                    Artwork(image: info.artwork, cornerRadius: 12)
                        .frame(width: 62, height: 62)
                        .shadow(color: accent.opacity(0.45), radius: 12)
                }
                .buttonStyle(.plain)
                .help("Open player")

                VStack(alignment: .leading, spacing: 3) {
                    Text(info.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Text(info.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    ControlButton(systemName: "backward.fill", size: 15) { nowPlaying.send(.previousTrack) }
                    ControlButton(systemName: info.isPlaying ? "pause.fill" : "play.fill", size: 22) {
                        nowPlaying.send(.togglePlayPause)
                    }
                    ControlButton(systemName: "forward.fill", size: 15) { nowPlaying.send(.nextTrack) }
                }
            }
            ProgressRow(info: info, accent: accent)
        }
        .foregroundStyle(.white)
    }
}

private struct ProgressRow: View {
    let info: NowPlayingInfo
    let accent: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let elapsed = info.elapsed(at: context.date)
            let fraction = info.duration > 0 ? elapsed / info.duration : 0
            HStack(spacing: 10) {
                Text(Self.format(elapsed))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule().fill(accent).frame(width: proxy.size.width * fraction)
                    }
                }
                .frame(height: 5)
                Text(Self.format(info.duration))
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct ControlButton: View {
    let systemName: String
    let size: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size))
                .contentTransition(.symbolEffect(.replace, options: .speed(2)))
                .frame(width: 36, height: 36)
                .background(.white.opacity(isHovered ? 0.12 : 0), in: Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

private struct Artwork: View {
    let image: NSImage?
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.12)
                    Image(systemName: "music.note")
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct ClockCard: View {
    var body: some View {
        HStack(alignment: .center) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                    Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Quit MacIsland")
        }
        .foregroundStyle(.white)
    }
}
