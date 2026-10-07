import AppKit
import Foundation

enum TimerState: Equatable {
    case idle
    case running(endDate: Date, total: TimeInterval)
    case paused(remaining: TimeInterval, total: TimeInterval)
    case finished

    var isActive: Bool {
        switch self {
        case .running, .paused: true
        case .idle, .finished: false
        }
    }
}

final class TimerService: ObservableObject {
    @Published private(set) var state: TimerState = .idle

    private var completion: Timer?

    func remaining(at date: Date) -> TimeInterval {
        switch state {
        case .running(let endDate, _): max(endDate.timeIntervalSince(date), 0)
        case .paused(let remaining, _): remaining
        case .idle, .finished: 0
        }
    }

    func progress(at date: Date) -> Double {
        switch state {
        case .running(_, let total), .paused(_, let total):
            total > 0 ? 1 - remaining(at: date) / total : 0
        case .idle: 0
        case .finished: 1
        }
    }

    func start(duration: TimeInterval) {
        guard duration > 0 else { return }
        run(remaining: duration, total: duration)
    }

    func pause() {
        guard case .running(_, let total) = state else { return }
        completion?.invalidate()
        state = .paused(remaining: remaining(at: Date()), total: total)
    }

    func resume() {
        guard case .paused(let remaining, let total) = state else { return }
        run(remaining: remaining, total: total)
    }

    func addTime(_ seconds: TimeInterval) {
        switch state {
        case .running(let endDate, let total):
            run(remaining: endDate.timeIntervalSinceNow + seconds, total: total + seconds)
        case .paused(let remaining, let total):
            state = .paused(remaining: remaining + seconds, total: total + seconds)
        case .idle, .finished:
            start(duration: seconds)
        }
    }

    func reset() {
        completion?.invalidate()
        state = .idle
    }

    private func run(remaining: TimeInterval, total: TimeInterval) {
        completion?.invalidate()
        let endDate = Date().addingTimeInterval(remaining)
        state = .running(endDate: endDate, total: total)

        // A one-shot timer at the end date instead of ticking every second; the UI
        // computes the countdown itself from endDate.
        let timer = Timer(fire: endDate, interval: 0, repeats: false) { [weak self] _ in
            self?.finish()
        }
        RunLoop.main.add(timer, forMode: .common)
        completion = timer
    }

    private func finish() {
        state = .finished
        NSSound(named: "Glass")?.play()
    }
}
