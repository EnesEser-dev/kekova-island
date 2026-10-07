import AppKit
import Combine
import SwiftUI

enum IslandTab: CaseIterable {
    case music
    case timer

    var symbolName: String {
        switch self {
        case .music: "music.note"
        case .timer: "timer"
        }
    }
}

final class IslandViewModel: ObservableObject {
    @Published var isExpanded = false
    @Published var hasMusic = false
    @Published var hasTimer = false
    @Published var selectedTab: IslandTab = .music
    @Published var notchSize: CGSize = .zero
    let expandedSize = CGSize(width: 480, height: 170)

    var isCompactVisible: Bool { hasMusic || hasTimer }

    /// Width added on each side of the notch for the compact "live activity" view.
    /// Wider while a countdown is shown so "12:34" fits.
    var compactWingWidth: CGFloat { hasTimer ? 58 : notchSize.height + 6 }

    var collapsedSize: CGSize {
        guard isCompactVisible else { return notchSize }
        return CGSize(width: notchSize.width + 2 * compactWingWidth, height: notchSize.height)
    }

    var currentSize: CGSize { isExpanded ? expandedSize : collapsedSize }
}

/// The island never becomes key, so without this the first click on a button would
/// only "activate" the window and a second click would be needed to press it.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class IslandController {
    private static let hoverOpenDelay: TimeInterval = 0.2
    private static let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8)
    private static let closeAnimation = Animation.spring(response: 0.35, dampingFraction: 0.9)

    private let model = IslandViewModel()
    private let nowPlaying: NowPlayingService
    private let timer: TimerService
    private var subscriptions: Set<AnyCancellable> = []
    private let panel = IslandPanel(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private var screen: NSScreen?
    private var monitors: [Any] = []
    private var mouseTimer: Timer?
    private var lastMouseLocation: CGPoint?
    private var pendingOpen: DispatchWorkItem?
    /// Keeps the island open while the mouse is elsewhere, e.g. to show "Time's up".
    private var isPinnedOpen = false
    private var pendingDismiss: DispatchWorkItem?
    private static let finishedDismissDelay: TimeInterval = 10

    init(nowPlaying: NowPlayingService, timer: TimerService) {
        self.nowPlaying = nowPlaying
        self.timer = timer
        // @Published emits in willSet; hopping to the next runloop turn lets the value land
        // first. Reacting synchronously made SwiftUI render the old state and then never
        // re-render the timer card (presets "did nothing").
        nowPlaying.$info
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] hasMusic in
                withAnimation(Self.openAnimation) { self?.model.hasMusic = hasMusic }
            }
            .store(in: &subscriptions)
        timer.$state
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.handleTimerChange(state) }
            .store(in: &subscriptions)

        configurePanel()
        placeOnScreen()
        startTrackingMouse()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.placeOnScreen()
        }
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .mainMenu + 3
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.contentView = FirstClickHostingView(rootView: IslandView(model: model, nowPlaying: nowPlaying, timer: timer))
    }

    private func placeOnScreen() {
        guard let screen = NSScreen.builtInWithNotch ?? NSScreen.main else { return }
        self.screen = screen
        model.notchSize = screen.notchSize

        // The panel always has the expanded size; SwiftUI draws the visible shape inside it.
        let size = CGSize(width: model.expandedSize.width + 2 * IslandShape.earRadius, height: model.expandedSize.height)
        let origin = CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    private func startTrackingMouse() {
        // Polling instead of mouseMoved monitors: macOS only emits mouseMoved when the
        // frontmost app asks for it, so global monitors miss movement over the menu bar.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.pollMouse()
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseTimer = timer

        // While collapsed the panel ignores the mouse, so clicks on the notch reach us only globally.
        let globalClick = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.handleClick()
        }
        monitors = [globalClick].compactMap { $0 }
    }

    private func pollMouse() {
        let location = NSEvent.mouseLocation
        guard location != lastMouseLocation else { return }
        lastMouseLocation = location
        handleMouseMove(at: location)
    }

    private func handleMouseMove(at location: CGPoint) {
        let isInside = hitRect().contains(location)
        if model.isExpanded {
            if !isInside && !isPinnedOpen { collapse() }
            return
        }
        if isInside {
            scheduleOpen()
        } else {
            cancelPendingOpen()
        }
    }

    private func handleClick() {
        guard !model.isExpanded, hitRect().contains(NSEvent.mouseLocation) else { return }
        expand()
    }

    private func hitRect() -> CGRect {
        guard let screen else { return .zero }
        let size = model.currentSize
        // A little slack around the shape so the edge isn't twitchy. The extra point on top
        // matters: with the cursor pinned to the top edge, mouseLocation.y == frame.maxY,
        // which CGRect.contains treats as outside.
        let slack: CGFloat = model.isExpanded ? 16 : 6
        return CGRect(
            x: screen.frame.midX - size.width / 2 - slack,
            y: screen.frame.maxY - size.height - slack,
            width: size.width + 2 * slack,
            height: size.height + slack + 1
        )
    }

    private func scheduleOpen() {
        guard pendingOpen == nil else { return }
        let work = DispatchWorkItem { [weak self] in self?.expand() }
        pendingOpen = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverOpenDelay, execute: work)
    }

    private func cancelPendingOpen() {
        pendingOpen?.cancel()
        pendingOpen = nil
    }

    private func expand() {
        cancelPendingOpen()
        guard !model.isExpanded else { return }
        panel.ignoresMouseEvents = false
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(Self.openAnimation) { model.isExpanded = true }
    }

    private func collapse() {
        panel.ignoresMouseEvents = true
        withAnimation(Self.closeAnimation) { model.isExpanded = false }
    }

    private func handleTimerChange(_ state: TimerState) {
        withAnimation(Self.openAnimation) { model.hasTimer = state.isActive }
        if state == .finished {
            showTimerFinished()
        } else if isPinnedOpen {
            unpin()
        }
    }

    private func showTimerFinished() {
        model.selectedTab = .timer
        isPinnedOpen = true
        expand()
        let work = DispatchWorkItem { [weak self] in self?.timer.reset() }
        pendingDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.finishedDismissDelay, execute: work)
    }

    private func unpin() {
        isPinnedOpen = false
        pendingDismiss?.cancel()
        pendingDismiss = nil
        if !hitRect().contains(NSEvent.mouseLocation) { collapse() }
    }
}
