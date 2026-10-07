import AppKit
import SwiftUI

struct IslandView: View {
    @ObservedObject var model: IslandViewModel
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var timer: TimerService
    @ObservedObject var shelf: ShelfStore

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                IslandShape(bottomRadius: model.isExpanded ? 30 : 10)
                    .fill(.black)

                if model.isExpanded {
                    ExpandedContent(model: model, nowPlaying: nowPlaying, timer: timer, shelf: shelf)
                        .padding(.horizontal, IslandShape.earRadius + 22)
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
                } else if model.isCompactVisible {
                    CompactContent(model: model, nowPlaying: nowPlaying, timer: timer)
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

private struct CompactContent: View {
    @ObservedObject var model: IslandViewModel
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var timer: TimerService

    var body: some View {
        let artSize = model.notchSize.height - 12
        HStack(spacing: 0) {
            Group {
                if let info = nowPlaying.info {
                    Artwork(image: info.artwork, cornerRadius: 5)
                        .frame(width: artSize, height: artSize)
                } else {
                    Image(systemName: "timer")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TimerCard.accent)
                }
            }
            .frame(width: model.compactWingWidth)

            Spacer(minLength: model.notchSize.width)

            Group {
                if timer.state.isActive {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(formatDuration(timer.remaining(at: context.date).rounded(.up)))
                            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(TimerCard.accent)
                            .opacity(isPaused ? 0.5 : 1)
                    }
                } else if let info = nowPlaying.info {
                    EqualizerBars(color: Color(nsColor: info.accentColor), isAnimating: info.isPlaying)
                        .frame(width: artSize * 0.8, height: artSize * 0.6)
                }
            }
            .frame(width: model.compactWingWidth)
        }
        .frame(height: model.notchSize.height)
    }

    private var isPaused: Bool {
        if case .paused = timer.state { return true }
        return false
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
    @ObservedObject var model: IslandViewModel
    @ObservedObject var nowPlaying: NowPlayingService
    @ObservedObject var timer: TimerService
    @ObservedObject var shelf: ShelfStore

    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            Header(model: model)
                .frame(height: model.notchSize.height)
            Group {
                switch model.selectedTab {
                case .music:
                    if let info = nowPlaying.info {
                        NowPlayingCard(info: info, nowPlaying: nowPlaying)
                    } else {
                        ClockCard()
                    }
                case .timer:
                    TimerCard(timer: timer)
                case .shelf:
                    ShelfCard(shelf: shelf, isDropTargeted: isDropTargeted)
                }
            }
            .frame(maxHeight: .infinity)
        }
        // The whole island accepts drops, whichever tab is showing.
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            model.selectedTab = .shelf
            loadFileURLs(from: providers) { shelf.add($0) }
            return true
        }
        .onChange(of: isDropTargeted) { _, isTargeted in
            if isTargeted { model.selectedTab = .shelf }
        }
    }
}

/// Sits in the band beside the hardware notch: tabs on the left, quit on the right.
private struct Header: View {
    @ObservedObject var model: IslandViewModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(IslandTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { model.selectedTab = tab }
                } label: {
                    Image(systemName: tab.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 22)
                        .background(
                            .white.opacity(model.selectedTab == tab ? 0.16 : 0),
                            in: Capsule()
                        )
                        .foregroundStyle(.white.opacity(model.selectedTab == tab ? 1 : 0.5))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: model.notchSize.width + 16)
            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Quit MacIsland")
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
                Text(formatDuration(elapsed))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule().fill(accent).frame(width: proxy.size.width * fraction)
                    }
                }
                .frame(height: 5)
                Text(formatDuration(info.duration))
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
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
        // Color.clear takes the size the caller gives us; the image fills it and gets
        // clipped, so wide video thumbnails show their center instead of overflowing.
        Color.clear
            .overlay {
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
        }
        .foregroundStyle(.white)
    }
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded(.down))
    let hours = total / 3600
    let minutes = total / 60 % 60
    let secs = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}
