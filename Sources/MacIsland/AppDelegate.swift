import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: IslandController?
    private let nowPlaying = NowPlayingService()
    private let timer = TimerService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        nowPlaying.start()
        controller = IslandController(nowPlaying: nowPlaying, timer: timer)
    }

    /// Handles `macisland://timer?minutes=25` (or `seconds=90`) so Raycast, Shortcuts
    /// or `open` in a terminal can start a timer.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "macisland" && url.host == "timer" {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let minutes = query.first { $0.name == "minutes" }?.value.flatMap(Double.init) ?? 0
            let seconds = query.first { $0.name == "seconds" }?.value.flatMap(Double.init) ?? 0
            timer.start(duration: minutes * 60 + seconds)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        nowPlaying.stop()
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
