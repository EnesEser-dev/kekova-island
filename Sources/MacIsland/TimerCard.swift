import SwiftUI

struct TimerCard: View {
    static let accent = Color.orange
    private static let presetMinutes = [1, 5, 10, 25]

    @ObservedObject var timer: TimerService
    @State private var customMinutes = 15

    var body: some View {
        Group {
            switch timer.state {
            case .idle:
                picker
            case .running, .paused:
                countdown
            case .finished:
                finished
            }
        }
        .foregroundStyle(.white)
    }

    private var picker: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(Self.presetMinutes, id: \.self) { minutes in
                    PillButton(title: "\(minutes) min") { timer.start(duration: TimeInterval(minutes * 60)) }
                }
            }
            HStack(spacing: 10) {
                CircleButton(systemName: "minus") { customMinutes = max(customMinutes - 1, 1) }
                Text("\(customMinutes) min")
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    .frame(minWidth: 60)
                CircleButton(systemName: "plus") { customMinutes = min(customMinutes + 1, 180) }
                Spacer()
                PillButton(title: "Start", isProminent: true) {
                    timer.start(duration: TimeInterval(customMinutes * 60))
                }
            }
        }
    }

    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 16) {
                ProgressRing(progress: timer.progress(at: context.date))
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text(formatDuration(timer.remaining(at: context.date).rounded(.up)))
                        .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: Int(timer.remaining(at: context.date)))
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()

                HStack(spacing: 6) {
                    CircleButton(systemName: "plus.forwardslash.minus", label: "+1") { timer.addTime(60) }
                        .help("Add 1 minute")
                    CircleButton(systemName: isPaused ? "play.fill" : "pause.fill") {
                        isPaused ? timer.resume() : timer.pause()
                    }
                    CircleButton(systemName: "xmark") { timer.reset() }
                        .help("Cancel")
                }
            }
        }
    }

    private var finished: some View {
        HStack(spacing: 16) {
            Image(systemName: "bell.fill")
                .font(.system(size: 30))
                .foregroundStyle(Self.accent)
                .symbolEffect(.bounce, options: .repeating)
            Text("Time's up")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            Spacer()
            PillButton(title: "+1 min") { timer.start(duration: 60) }
            PillButton(title: "Done", isProminent: true) { timer.reset() }
        }
    }

    private var isPaused: Bool {
        if case .paused = timer.state { return true }
        return false
    }

    private var subtitle: String {
        guard case .running(let endDate, _) = timer.state else { return "Paused" }
        return "Ends at " + endDate.formatted(date: .omitted, time: .shortened)
    }
}

private struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: 5)
            Circle()
                .trim(from: 0, to: 1 - progress)
                .stroke(TimerCard.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
            Image(systemName: "timer")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TimerCard.accent)
        }
    }
}

private struct PillButton: View {
    let title: String
    var isProminent = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .frame(height: 30)
                .foregroundStyle(isProminent ? .black : .white)
                .background(background, in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var background: Color {
        if isProminent { return TimerCard.accent.opacity(isHovered ? 0.85 : 1) }
        return .white.opacity(isHovered ? 0.2 : 0.12)
    }
}

private struct CircleButton: View {
    let systemName: String
    var label: String?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if let label {
                    Text(label).font(.system(size: 13, weight: .bold, design: .rounded))
                } else {
                    Image(systemName: systemName).font(.system(size: 13, weight: .bold))
                }
            }
            .frame(width: 32, height: 32)
            .background(.white.opacity(isHovered ? 0.2 : 0.12), in: Circle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
