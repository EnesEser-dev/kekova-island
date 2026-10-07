import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: IslandController?
    private let nowPlaying = NowPlayingService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        nowPlaying.start()
        controller = IslandController(nowPlaying: nowPlaying)
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
