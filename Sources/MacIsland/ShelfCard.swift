import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct ShelfCard: View {
    @ObservedObject var shelf: ShelfStore
    let isDropTargeted: Bool

    var body: some View {
        Group {
            if shelf.items.isEmpty || isDropTargeted {
                dropZone
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(shelf.items) { item in
                                ShelfItemView(item: item, shelf: shelf)
                            }
                        }
                    }
                    Button("Clear") { shelf.removeAll() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear { shelf.refresh() }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(
                .white.opacity(isDropTargeted ? 0.8 : 0.25),
                style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
            )
            .background(
                .white.opacity(isDropTargeted ? 0.08 : 0),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                        .font(.system(size: 22))
                    Text("Drop files here")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white.opacity(isDropTargeted ? 1 : 0.5))
            }
            .animation(.snappy(duration: 0.2), value: isDropTargeted)
    }
}

private struct ShelfItemView: View {
    let item: ShelfItem
    let shelf: ShelfStore

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 4) {
            FileThumbnail(url: item.url)
                .frame(width: 48, height: 48)
            Text(item.url.lastPathComponent)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 66)
        }
        .padding(6)
        .background(.white.opacity(isHovered ? 0.1 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button {
                    shelf.remove(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .gray)
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { shelf.open(item) }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .help(item.url.path)
    }
}

private struct FileThumbnail: View {
    let url: URL

    @State private var thumbnail: NSImage?

    var body: some View {
        Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .task(id: url) { thumbnail = await Self.makeThumbnail(for: url) }
    }

    private static func makeThumbnail(for url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 96, height: 96),
            scale: 2,
            representationTypes: .thumbnail
        )
        let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        return representation?.nsImage
    }
}

/// Pulls file URLs out of drop providers and hands them over on the main queue.
func loadFileURLs(from providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    let group = DispatchGroup()
    var urls: [URL] = []
    let lock = NSLock()
    for provider in providers where provider.canLoadObject(ofClass: URL.self) {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url, url.isFileURL {
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
            group.leave()
        }
    }
    group.notify(queue: .main) { completion(urls) }
}
