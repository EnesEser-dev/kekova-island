import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: IslandController?
    private let nowPlaying = NowPlayingService()
    private let timer = TimerService()
    private let shelf = ShelfStore()
    private let calendar = CalendarService()
    private let launchAtLogin = LaunchAtLogin()
    private let power = PowerMonitor()
    private let headphones = HeadphoneMonitor()
    private let screenshots = ScreenshotWatcher()
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Only an installed copy should register; a dev build under build/ gets wiped on rebuild.
        if Bundle.main.bundlePath.contains("/Applications/") {
            launchAtLogin.enableOnFirstLaunch()
        }
        let controller = IslandController(services: IslandServices(
            nowPlaying: nowPlaying,
            timer: timer,
            shelf: shelf,
            calendar: calendar,
            launchAtLogin: launchAtLogin,
            screenshots: screenshots
        ))
        self.controller = controller

        power.onPluggedIn = { [weak controller] state in
            controller?.showBanner(.charging(level: state.level))
        }
        headphones.onConnected = { [weak controller] info in
            controller?.showBanner(.headphones(info))
        }
        calendar.onReminder = { [weak controller] _ in
            controller?.showMeetingReminder()
        }
        screenshots.onScreenshot = { [weak controller, shelf] url in
            shelf.add([url])
            controller?.showBanner(.screenshot)
        }

        handleTerminationSignals()
        nowPlaying.start()
        power.start()
        headphones.start()
        calendar.start()
        screenshots.start()
    }

    /// `kekova://timer?minutes=25` (or `seconds=90`) starts a timer from Raycast,
    /// Shortcuts or `open` in a terminal. `kekova://preview/charging|headphones|screenshot|meeting`
    /// shows a notice without needing the real event, handy for testing and demos.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "kekova" {
            switch (url.host, url.lastPathComponent) {
            case ("timer", _):
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let minutes = query.first { $0.name == "minutes" }?.value.flatMap(Double.init) ?? 0
                let seconds = query.first { $0.name == "seconds" }?.value.flatMap(Double.init) ?? 0
                timer.start(duration: minutes * 60 + seconds)
            case ("preview", "charging"):
                controller?.showBanner(.charging(level: PowerMonitor.readState()?.level ?? 80))
            case ("preview", "headphones"):
                controller?.showBanner(.headphones(HeadphoneInfo(name: "AirPods Pro", symbolName: "airpodspro", batteryLevel: 92)))
            case ("preview", "screenshot"):
                controller?.showBanner(.screenshot)
            case ("preview", "meeting"):
                controller?.showMeetingReminder()
            default:
                break
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        nowPlaying.stop()
    }

    /// `kill`/`pkill` skip applicationWillTerminate, which left the perl stream orphaned.
    private func handleTerminationSignals() {
        for signalNumber in [SIGTERM, SIGINT] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }
}

extension NSScreen {
    static var builtInWithNotch: NSScreen? {
        screens.first { $0.safeAreaInsets.top > 0 }
    }

    var notchSize: CGSize {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else {
            // No notch (external display): fake one the height of the menu bar.
            return CGSize(width: 200, height: frame.maxY - visibleFrame.maxY)
        }
        return CGSize(width: frame.width - left.width - right.width, height: safeAreaInsets.top)
    }
}
