import AppKit
import CoreImage
import Foundation

struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String
    var isPlaying: Bool
    var duration: TimeInterval
    var elapsedTime: TimeInterval
    var timestamp: Date
    var playbackRate: Double
    var bundleIdentifier: String?
    var artwork: NSImage?
    var accentColor: NSColor

    func elapsed(at date: Date) -> TimeInterval {
        guard isPlaying else { return elapsedTime }
        let elapsed = elapsedTime + date.timeIntervalSince(timestamp) * playbackRate
        return min(max(elapsed, 0), duration)
    }
}

enum MediaCommand: Int {
    case togglePlayPause = 2
    case nextTrack = 4
    case previousTrack = 5
}

/// Reads the system-wide "Now Playing" info. Since macOS 15.4 apps can't call MediaRemote
/// directly, so we go through mediaremote-adapter, which runs inside the entitled /usr/bin/perl.
final class NowPlayingService: ObservableObject {
    @Published private(set) var info: NowPlayingInfo?

    private static let perlPath = "/usr/bin/perl"
    private static let restartDelay: TimeInterval = 2

    private let scriptPath: String?
    private let frameworkPath: String?
    private var streamProcess: Process?
    private var lineBuffer = Data()
    // Touched only on the pipe's background queue.
    private var lastArtworkBase64: String?
    private var lastArtwork: NSImage?
    private var lastAccentColor: NSColor = .white
    private var isStopping = false

    init() {
        scriptPath = Bundle.main.path(forResource: "mediaremote-adapter", ofType: "pl")
        frameworkPath = Bundle.main.privateFrameworksPath.map { "\($0)/MediaRemoteAdapter.framework" }
    }

    func start() {
        guard let scriptPath, let frameworkPath else {
            NSLog("MacIsland: mediaremote-adapter is missing from the app bundle")
            return
        }
        isStopping = false
        lineBuffer = Data()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.perlPath)
        process.arguments = [scriptPath, frameworkPath, "stream", "--no-diff", "--debounce=100"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.consume(handle.availableData)
        }
        process.terminationHandler = { [weak self] _ in
            output.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.restartDelay) {
                guard let self, !self.isStopping else { return }
                self.start()
            }
        }

        do {
            try process.run()
        } catch {
            NSLog("MacIsland: failed to start now playing stream: \(error)")
            return
        }
        streamProcess = process
    }

    func stop() {
        isStopping = true
        streamProcess?.terminate()
        streamProcess = nil
    }

    func send(_ command: MediaCommand) {
        guard let scriptPath, let frameworkPath else { return }
        if command == .togglePlayPause {
            togglePlayingOptimistically()
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.perlPath)
        process.arguments = [scriptPath, frameworkPath, "send", String(command.rawValue)]
        try? process.run()
    }

    /// Flips the play state right away instead of waiting ~0.5s for the player to echo it
    /// back through the stream; the next stream update overwrites it with the real state.
    private func togglePlayingOptimistically() {
        guard var updated = info else { return }
        let now = Date()
        updated.elapsedTime = updated.elapsed(at: now)
        updated.timestamp = now
        updated.isPlaying.toggle()
        info = updated
    }

    func openSourceApp() {
        guard
            let bundleIdentifier = info?.bundleIdentifier,
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // Runs on the pipe's background queue.
    private func consume(_ data: Data) {
        lineBuffer.append(data)
        while let newline = lineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = lineBuffer[lineBuffer.startIndex..<newline]
            lineBuffer.removeSubrange(lineBuffer.startIndex...newline)
            handle(line: Data(line))
        }
    }

    private func handle(line: Data) {
        guard
            let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
            message["type"] as? String == "data",
            let payload = message["payload"] as? [String: Any]
        else { return }

        let info = parse(payload)
        DispatchQueue.main.async {
            guard info != self.info else { return }
            self.info = info
        }
    }

    private func parse(_ payload: [String: Any]) -> NowPlayingInfo? {
        guard let title = payload["title"] as? String, !title.isEmpty else { return nil }

        // Artwork is several hundred KB of base64 and arrives on every update, so only
        // decode it (and recompute the accent color) when it actually changes.
        let artworkBase64 = payload["artworkData"] as? String
        if artworkBase64 != lastArtworkBase64 {
            lastArtworkBase64 = artworkBase64
            lastArtwork = artworkBase64
                .flatMap { Data(base64Encoded: $0) }
                .flatMap { NSImage(data: $0) }
            lastAccentColor = lastArtwork.flatMap(Self.averageColor(of:)) ?? .white
        }

        return NowPlayingInfo(
            title: title,
            artist: payload["artist"] as? String ?? "",
            isPlaying: payload["playing"] as? Bool ?? false,
            duration: payload["duration"] as? Double ?? 0,
            elapsedTime: payload["elapsedTime"] as? Double ?? 0,
            timestamp: (payload["timestamp"] as? String).flatMap(Self.parseDate) ?? Date(),
            playbackRate: payload["playbackRate"] as? Double ?? 1,
            bundleIdentifier: payload["bundleIdentifier"] as? String,
            artwork: lastArtwork,
            accentColor: lastAccentColor
        )
    }

    private static func parseDate(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }

    private static func averageColor(of image: NSImage) -> NSColor? {
        guard
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let filter = CIFilter(name: "CIAreaAverage")
        else { return nil }
        let input = CIImage(cgImage: cgImage)
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: input.extent), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext().render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let color = NSColor(
            red: CGFloat(pixel[0]) / 255,
            green: CGFloat(pixel[1]) / 255,
            blue: CGFloat(pixel[2]) / 255,
            alpha: 1
        )
        // Dark covers would give a muddy accent on a black island, so lift the brightness.
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        color.usingColorSpace(.deviceRGB)?.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: min(saturation * 1.2, 1), brightness: max(brightness, 0.75), alpha: 1)
    }
}
