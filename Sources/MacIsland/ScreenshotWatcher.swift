import Foundation

/// Spots new screenshots through Spotlight (macOS tags them with kMDItemIsScreenCapture),
/// so it works wherever the user saves them.
final class ScreenshotWatcher: ObservableObject {
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            isEnabled ? start() : stop()
        }
    }

    var onScreenshot: ((URL) -> Void)?

    private static let enabledKey = "addScreenshotsToShelf"
    private var query: NSMetadataQuery?
    private var seenPaths: Set<String> = []
    private var observer: NSObjectProtocol?

    init() {
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func start() {
        guard isEnabled, query == nil else { return }
        requestFolderAccess()
        let query = NSMetadataQuery()
        // Only screenshots taken from now on; older ones are not news.
        query.predicate = NSPredicate(
            format: "kMDItemIsScreenCapture == 1 AND kMDItemFSCreationDate >= %@",
            Date() as NSDate
        )
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] notification in
            self?.handleUpdate(notification)
        }
        query.start()
        self.query = query
    }

    func stop() {
        query?.stop()
        query = nil
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }

    /// Spotlight silently hides results in privacy-protected folders (Desktop, Downloads,
    /// Documents) from apps without access. Listing the folder once makes macOS ask.
    /// Off the main thread: the call blocks until the user answers the prompt.
    private func requestFolderAccess() {
        let folder = Self.screenshotFolder()
        DispatchQueue.global(qos: .utility).async {
            _ = try? FileManager.default.contentsOfDirectory(atPath: folder.path)
        }
    }

    private static func screenshotFolder() -> URL {
        let configured = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        let path = configured.map { NSString(string: $0).expandingTildeInPath }
            ?? NSHomeDirectory() + "/Desktop"
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func handleUpdate(_ notification: Notification) {
        let added = notification.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? []
        for item in added {
            guard
                let path = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                !seenPaths.contains(path)
            else { continue }
            seenPaths.insert(path)
            onScreenshot?(URL(fileURLWithPath: path))
        }
    }
}
