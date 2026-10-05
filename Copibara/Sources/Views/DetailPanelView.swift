import SwiftUI

struct DetailPanelView: View {
    let item: CopibaraItem
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void
    var onSaveImage: (() -> Void)? = nil
    var isFavorite: Bool = false
    var onToggleFavorite: (() -> Void)? = nil

    @State private var image: NSImage?
    /// The load for this item finished (with or without an image), so the
    /// placeholder can give way to the text fallback.
    @State private var imageLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Preview")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.appTextPrimary)

                Spacer()

                if let onToggleFavorite {
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(isFavorite ? Color.favoriteAccent : Color.appTextTertiary)
                            .frame(width: 24, height: 24)
                            .background(isFavorite ? Color.favoriteAccent.opacity(0.15) : Color.appSurfaceHover)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(isFavorite ? "Remove from Favorites (⌘D)" : "Add to Favorites (⌘D)")
                }

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.appTextTertiary)
                        .frame(width: 24, height: 24)
                        .background(Color.appSurfaceHover)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.base)
            .overlay(alignment: .bottom) { Divider() }

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.base) {
                    // Content preview
                    if item.type == .code {
                        textBody(font: .system(size: 11, design: .monospaced), selectable: false)
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.appBackground)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                    } else if item.type == .image {
                        if let nsImage = image {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                        } else if imageLoaded {
                            Text(item.content)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.appTextPrimary)
                        } else {
                            RoundedRectangle(cornerRadius: CornerRadius.sm)
                                .fill(Color.appSurfaceHover)
                                .aspectRatio(4 / 3, contentMode: .fit)
                                .overlay(ProgressView().controlSize(.small))
                        }
                    } else {
                        textBody(font: .system(size: 13), selectable: true)
                    }

                    if isPartial {
                        Text("Showing the first \(formatSize(shownText.utf8.count)) of \(formatSize(item.size)). Copy and paste use the full text.")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.appTextTertiary)
                    }

                    Divider()

                    // Metadata
                    VStack(spacing: Spacing.sm) {
                        MetadataRow(label: "Type", value: "\(item.type.emoji) \(item.type.label)")
                        MetadataRow(label: "Size", value: formatSize(item.size))
                        MetadataRow(label: "Copied", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        MetadataRow(label: "Board", value: item.boardId.capitalized)
                        if isFavorite {
                            MetadataRow(label: "Saved", value: "⭐️ Favorite — kept through clears")
                        }
                    }
                }
                .padding(Spacing.xl)
            }

            Divider()

            // Actions
            VStack(spacing: Spacing.sm) {
                if item.type == .image, let onSaveImage = onSaveImage {
                    Button(action: onSaveImage) {
                        Label("Save Image", systemImage: "square.and.arrow.down")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(DetailButtonStyle(isPrimary: false))
                }

                HStack(spacing: Spacing.sm) {
                    Button(action: onDelete) {
                        Label("Delete", systemImage: "trash")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(DetailButtonStyle(isPrimary: false))

                    Button(action: onCopy) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(DetailButtonStyle(isPrimary: true))
                }
            }
            .padding(Spacing.base)
        }
        .frame(width: 260)
        .background(Color.appSurface)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.appBorder)
                .frame(width: 1)
        }
        // Decode off the main thread. This used to run synchronously in `body`, so
        // arrowing onto a large screenshot froze the window for up to ~200 ms.
        .task(id: item.id) {
            image = nil
            imageLoaded = false
            guard item.type == .image, let url = imageURL else { imageLoaded = true; return }
            image = await ImageThumbnail.loadAsync(url, maxPixel: 1200)
            imageLoaded = true
        }
    }

    // MARK: - Text

    /// Short clips render as one `Text`, as always (whole-clip selection works).
    /// Above this, the text is split into chunks in a lazy stack so only what's on
    /// screen gets laid out. A single `Text` for a multi-megabyte clip took 140 ms
    /// for 2.6 MB just to size, and scaled up from there.
    private static let singleTextLimit = 8 * 1024
    private static let chunkSize = 4 * 1024

    /// What the panel shows: never more than the inline limit.
    private var shownText: String { item.content.utf8Prefix(CopibaraItem.inlineTextLimit) }

    /// True when the panel isn't showing the whole clip.
    private var isPartial: Bool {
        item.isTextTruncated || shownText.utf8.count < item.content.utf8.count
    }

    @ViewBuilder
    private func textBody(font: Font, selectable: Bool) -> some View {
        let text = shownText
        if text.utf8.count <= Self.singleTextLimit {
            if selectable {
                Text(text).font(font).foregroundStyle(Color.appTextPrimary).textSelection(.enabled)
            } else {
                Text(text).font(font).foregroundStyle(Color.appTextPrimary)
            }
        } else {
            let chunks = Self.chunks(of: text)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(chunks.indices, id: \.self) { index in
                    Text(chunks[index])
                        .font(font)
                        .foregroundStyle(Color.appTextPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Split at line breaks into pieces of roughly `chunkSize` bytes, so no chunk
    /// boundary falls mid-line (unless a single line is itself that long).
    private static func chunks(of text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if !current.isEmpty { current += "\n" }
            current += line
            if current.utf8.count >= chunkSize {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

// MARK: - Metadata Row

private struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color.appTextTertiary)
                .frame(width: 50, alignment: .leading)

            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.appTextPrimary)

            Spacer()
        }
    }
}

// MARK: - Detail Button Style

private struct DetailButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .foregroundStyle(isPrimary ? .white : Color.appTextSecondary)
            .background(isPrimary ? Color.appPrimary : Color.appSurfaceHover)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

extension DetailPanelView {
    /// The stored image in ~/Library/Application Support/CopibaraManager/images/.
    /// Previewed at 1200 px (larger than the grid, still capped so a huge capture
    /// doesn't decode full-res just for the detail pane).
    private var imageURL: URL? {
        guard let fileName = item.imageFileName else { return nil }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CopibaraManager", isDirectory: true)
            .appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
