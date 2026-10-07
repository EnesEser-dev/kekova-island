import AppKit
import Combine
import SwiftUI

enum IslandTab {
    case music
    case timer
    case calendar
    case shelf
    case settings

    /// Tabs shown on the left of the header; settings lives behind the gear on the right.
    static let leading: [IslandTab] = [.music, .timer, .calendar, .shelf]

    init?(urlName: String) {
        switch urlName {
        case "music": self = .music
        case "timer": self = .timer
        case "calendar": self = .calendar
        case "shelf": self = .shelf
        case "settings": self = .settings
        default: return nil
        }
    }

    var symbolName: String {
        switch self {
        case .music: "music.note"
        case .timer: "timer"
        case .calendar: "calendar"
        case .shelf: "tray.full"
        case .settings: "gearshape"
        }
    }
}

/// Short-lived notice that widens the collapsed island for a few seconds.
enum IslandBanner: Equatable {
    case charging(level: Int)
    case headphones(HeadphoneInfo)
    case screenshot
}

struct IslandServices {
    let nowPlaying: NowPlayingService
    let timer: TimerService
    let shelf: ShelfStore
    let calendar: CalendarService
    let launchAtLogin: LaunchAtLogin
    let screenshots: ScreenshotWatcher
}

final class IslandViewModel: ObservableObject {
    @Published var isExpanded = false
    @Published var hasMusic = false
    @Published var hasTimer = false
    @Published var banner: IslandBanner?
    @Published var selectedTab: IslandTab = .music
    @Published var notchSize: CGSize = .zero
    let expandedSize = CGSize(width: 480, height: 170)
    let bannerWingWidth: CGFloat = 110

    var isCompactVisible: Bool { hasMusic || hasTimer }

    /// Width added on each side of the notch for the compact "live activity" view.
    /// Wider while a countdown is shown so "12:34" fits.
    var compactWingWidth: CGFloat { hasTimer ? 58 : notchSize.height + 6 }

    var collapsedSize: CGSize {
        if banner != nil {
            return CGSize(width: notchSize.width + 2 * bannerWingWidth, height: notchSize.height)
        }
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
    private static let bannerDuration: TimeInterval = 3
    private static let timerFinishedDuration: TimeInterval = 10
    private static let meetingReminderDuration: TimeInterval = 30
    private static let openedFromURLDuration: TimeInterval = 10
    private static let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8)
    private static let closeAnimation = Animation.spring(response: 0.35, dampingFraction: 0.9)

    private let model = IslandViewModel()
    private let services: IslandServices
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
    private var pendingBannerHide: DispatchWorkItem?
    private var pendingTimerReset: DispatchWorkItem?

    /// Keeps the island open while the mouse is elsewhere, e.g. for "Time's up". Ends on
    /// timeout or once the mouse comes in, after which the usual hover rules apply.
    private var isPinnedOpen = false
    private var pendingUnpin: DispatchWorkItem?

    private let dragPasteboard = NSPasteboard(name: .drag)
    /// Drag pasteboard changeCount when the mouse went down; nil while the button is up.
    /// A different count during the press means a drag session is carrying something.
    private var dragBaseline: Int?
    private var dragStartedInside = false
    private var isDraggingFiles = false

    init(services: IslandServices) {
        self.services = services
        // @Published emits in willSet; hopping to the next runloop turn lets the value land
        // first. Reacting synchronously made SwiftUI render the old state and then never
        // re-render the timer card (presets "did nothing").
        services.nowPlaying.$info
            .map { $0 != nil }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] hasMusic in
                withAnimation(Self.openAnimation) { self?.model.hasMusic = hasMusic }
            }
            .store(in: &subscriptions)
        services.timer.$state
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

    func showBanner(_ banner: IslandBanner) {
        // While open the user is busy with the island; a banner would only get in the way.
        guard !model.isExpanded else { return }
        pendingBannerHide?.cancel()
        withAnimation(Self.openAnimation) { model.banner = banner }

        let work = DispatchWorkItem { [weak self] in
            withAnimation(Self.closeAnimation) { self?.model.banner = nil }
        }
        pendingBannerHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.bannerDuration, execute: work)
    }

    /// Opened from a URL (Raycast, Shortcuts...) the mouse is usually elsewhere, so keep
    /// the island open until the mouse visits it or the timeout passes.
    func open(tab: IslandTab) {
        pin(tab: tab, for: Self.openedFromURLDuration)
    }

    func close() {
        releasePin()
        collapse()
    }

    func showMeetingReminder() {
        pin(tab: .calendar, for: Self.meetingReminderDuration)
    }

    private func configurePanel() {
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .mainMenu + 3
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.contentView = FirstClickHostingView(rootView: IslandView(model: model, services: services))
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
        updateDragState(at: location)
        guard location != lastMouseLocation else { return }
        lastMouseLocation = location
        handleMouseMove(at: location)
    }

    private func updateDragState(at location: CGPoint) {
        let isMouseDown = NSEvent.pressedMouseButtons & 1 != 0
        if isMouseDown, dragBaseline == nil {
            dragBaseline = dragPasteboard.changeCount
            dragStartedInside = model.isExpanded && hitRect().contains(location)
        } else if isMouseDown, let baseline = dragBaseline, !isDraggingFiles {
            isDraggingFiles = dragPasteboard.changeCount != baseline
                && dragPasteboard.types?.contains(.fileURL) == true
        } else if !isMouseDown, dragBaseline != nil {
            finishDrag(at: location)
        }
    }

    private func finishDrag(at location: CGPoint) {
        let wasDraggingOut = isDraggingFiles && dragStartedInside
        dragBaseline = nil
        dragStartedInside = false
        isDraggingFiles = false
        guard wasDraggingOut else { return }
        // A file dragged out to Finder on the same volume gets moved; give Finder a
        // moment, then drop shelf entries whose files are gone.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.services.shelf.refresh() }
        if !hitRect().contains(location) && !isPinnedOpen { collapse() }
    }

    private func handleMouseMove(at location: CGPoint) {
        let isInside = hitRect().contains(location)
        if model.isExpanded {
            if isInside && isPinnedOpen { releasePin() }
            // Dragging a file out of the shelf: stay open so the drag source stays alive.
            let isDraggingOut = isDraggingFiles && dragStartedInside
            if !isInside && !isPinnedOpen && !isDraggingOut { collapse() }
            return
        }
        if isDraggingFiles && dropZoneRect().contains(location) {
            model.selectedTab = .shelf
            expand()
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

    /// Generous area around the notch so a file dragged roughly toward it opens the shelf.
    private func dropZoneRect() -> CGRect {
        let rect = hitRect()
        return rect.insetBy(dx: -50, dy: -40).offsetBy(dx: 0, dy: 40)
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
        pendingBannerHide?.cancel()
        panel.ignoresMouseEvents = false
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        withAnimation(Self.openAnimation) {
            model.banner = nil
            model.isExpanded = true
        }
    }

    private func collapse() {
        panel.ignoresMouseEvents = true
        withAnimation(Self.closeAnimation) { model.isExpanded = false }
    }

    private func pin(tab: IslandTab, for duration: TimeInterval) {
        model.selectedTab = tab
        isPinnedOpen = true
        expand()
        pendingUnpin?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.unpin() }
        pendingUnpin = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    /// Ends the pin but leaves the island open; hover rules take over from here.
    private func releasePin() {
        isPinnedOpen = false
        pendingUnpin?.cancel()
        pendingUnpin = nil
    }

    private func unpin() {
        guard isPinnedOpen else { return }
        releasePin()
        if !hitRect().contains(NSEvent.mouseLocation) { collapse() }
    }

    private func handleTimerChange(_ state: TimerState) {
        withAnimation(Self.openAnimation) { model.hasTimer = state.isActive }
        let wasFinished = pendingTimerReset != nil
        pendingTimerReset?.cancel()
        pendingTimerReset = nil
        guard state == .finished else {
            // Leaving "Time's up" ends its pin; other timer changes keep the island as is.
            if wasFinished { unpin() }
            return
        }
        pin(tab: .timer, for: Self.timerFinishedDuration)
        let work = DispatchWorkItem { [weak self] in self?.services.timer.reset() }
        pendingTimerReset = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.timerFinishedDuration, execute: work)
    }
}
