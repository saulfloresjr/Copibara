import SwiftUI
import AppKit

struct CopibaraCardView: View {
    let item: CopibaraItem
    let isSelected: Bool
    let isMultiSelect: Bool
    var isYapivo: Bool = false
    var isForaged: Bool = false
    var isFavorite: Bool = false
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    var onSaveImage: (() -> Void)? = nil
    var onRemoveBackground: (() -> Void)? = nil
    var onAIUpscale: ((UpscaleMode) -> Void)? = nil
    var onToggleFavorite: (() -> Void)? = nil
    var onDoubleClick: (() -> Void)? = nil

    /// Yapivo energetic orange color
    private let yapivOrange = Color(red: 1.0, green: 0.42, blue: 0.21) // #FF6B35

    /// Cards get a coloured glow saying what they are at a glance: amber for starred,
    /// orange for voice, green for foraged. A star is a choice the user made by hand,
    /// so it outranks where the clip happened to come from.
    private var accent: Color? {
        if isFavorite { return .favoriteAccent }
        if isYapivo { return yapivOrange }
        if isForaged { return .forageAccent }
        return nil
    }

    @State private var isHovering = false
    @State private var cachedImage: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Type Badge Header
            HStack {
                // Checkbox (multi-select mode)
                if isMultiSelect {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? Color.appPrimary : Color.appTextTertiary)
                }

                HStack(spacing: 4) {
                    Circle()
                        .fill(item.type.color)
                        .frame(width: 6, height: 6)

                    Text(item.type.label)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(item.type.color)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(item.type.backgroundColor)
                .clipShape(Capsule())

                Spacer()

                // The star stays visible once set — it's state, not a hover affordance —
                // while copy/delete still appear only on hover.
                if let onToggleFavorite {
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isFavorite ? Color.favoriteAccent : Color.appTextSecondary)
                            .frame(width: 24, height: 24)
                            .background(Color.appSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .opacity(isFavorite || (isHovering && !isMultiSelect) ? 1 : 0)
                    .allowsHitTesting(!isMultiSelect)
                    .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                }

                // Always rendered, visibility controlled by opacity — no layout shift on hover
                HStack(spacing: 4) {
                    SmallIconButton(systemName: "doc.on.doc", action: onCopy)
                    SmallIconButton(systemName: "trash", action: onDelete)
                }
                .opacity(isHovering && !isMultiSelect ? 1 : 0)
                .allowsHitTesting(isHovering && !isMultiSelect)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.sm)

            // Content Preview
            Group {
                switch item.type {
                case .image:
                    // Image thumbnail for screenshots
                    if let nsImage = cachedImage {
                        Image(nsImage: nsImage)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 80)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                            .overlay(
                                RoundedRectangle(cornerRadius: CornerRadius.sm)
                                    .stroke(Color.appBorder, lineWidth: 0.5)
                            )
                            .padding(.horizontal, Spacing.md)
                    } else {
                        // Fallback if image can't be loaded
                        HStack(spacing: 6) {
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.appTextTertiary)
                            Text(item.preview)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.appTextPrimary)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, Spacing.md)
                    }

                case .code:
                    Text(item.preview)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.appTextPrimary)
                        .padding(Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appBackground)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                        .padding(.horizontal, Spacing.md)

                case .link:
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.system(size: 10))
                                .foregroundStyle(item.type.color)
                            Text(item.preview)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(item.type.color)
                                .lineLimit(1)
                        }
                        Text(item.content)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.appTextTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, Spacing.md)

                default:
                    Text(item.preview)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appTextPrimary)
                        .lineLimit(5)
                        .padding(.horizontal, Spacing.md)
                }
            }

            Spacer(minLength: Spacing.sm)

            // Source chip — where this find came from (Forage mode only)
            if let capture = item.capture, capture.hasSource {
                sourceChip(capture)
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.sm)
            }

            // Footer
            HStack {
                Text(item.createdAt.timeAgoDisplay())
                    .font(.system(size: 10))
                    .foregroundStyle(Color.appTextTertiary)

                Spacer()

                Text(formatSize(item.size))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.appTextTertiary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
        }
        .frame(minHeight: 140)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                .fill(Color.appSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous)
                .stroke(
                    isSelected ? Color.appPrimary
                    : accent?.opacity(0.5) ?? Color.appBorder.opacity(0.5),
                    lineWidth: isSelected ? 2 : (accent != nil ? 1.5 : 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
        // Shadow LAST and outside any rasterisation. A .drawingGroup() used to sit at
        // the end of this chain, which rendered the card into a rectangular offscreen
        // buffer and clipped the coloured glow to those bounds — the boxy halo around
        // the rounded corners. Dropping it lets the glow follow the corner radius.
        .shadow(
            color: accent?.opacity(0.35) ?? .black.opacity(0.06),
            radius: accent != nil ? 8 : 4,
            y: accent != nil ? 0 : 2
        )
        .contentShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
        .onHover { isHovering = $0 }
        .onAppear {
            // Decode OFF the main thread (scrolling never blocks), from a shared bounded
            // cache so thumbnails can't pile up into gigabytes.
            guard item.type == .image, cachedImage == nil, let url = imageURL else { return }
            Task { @MainActor in cachedImage = await ImageThumbnail.loadAsync(url, maxPixel: 600) }
        }
        .onDisappear {
            // Release this card's thumbnail when it scrolls off. The shared cache keeps a
            // copy (bounded), so scrolling back is a fast cache hit — but off-screen cards
            // no longer hold gigabytes of decoded images alive.
            cachedImage = nil
        }
        .onTapGesture(count: 2) {
            onDoubleClick?()
        }
        .onTapGesture(count: 1) {
            onSelect()
        }
        .contextMenu {
            Button("Copy to Clipboard") { onCopy() }
            if let onToggleFavorite {
                Button(isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                    onToggleFavorite()
                }
            }
            if item.type == .image, let onSaveImage = onSaveImage {
                Button("Save Image") { onSaveImage() }
            }
            if item.type == .image, let onRemoveBackground = onRemoveBackground {
                Button("Remove Background") { onRemoveBackground() }
            }
            if item.type == .image, let onAIUpscale = onAIUpscale {
                Menu("Upscale (AI)") {
                    Button("Fit for sharing (\(Int(AIUpscaler.defaultTarget))px)") {
                        onAIUpscale(.fit(AIUpscaler.defaultTarget))
                    }
                    Divider()
                    Button("2×") { onAIUpscale(.times2) }
                    Button("4×") { onAIUpscale(.times4) }
                }
            }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    /// Where a foraged clip came from, plus how well it did if we could read a count.
    /// Clicking opens the original page — the point of saving the source is being able
    /// to go back and credit it.
    @ViewBuilder
    private func sourceChip(_ capture: CaptureContext) -> some View {
        HStack(spacing: 4) {
            Text(capture.kind?.glyph ?? "🌐")
                .font(.system(size: 9))

            Text(capture.displaySource ?? "")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.forageAccent)
                .lineLimit(1)
                .truncationMode(.middle)

            if let proof = capture.socialProof {
                Text("↑\(proof)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.appTextTertiary)
            }

            Spacer(minLength: 0)

            if capture.url != nil {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.appTextTertiary)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.forageAccent.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = capture.url { NSWorkspace.shared.open(url) }
        }
        .help(capture.url?.absoluteString ?? capture.windowTitle ?? "")
    }

    /// URL of the stored image in ~/Library/Application Support/CopibaraManager/images/
    private var imageURL: URL? {
        guard let fileName = item.imageFileName else { return nil }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CopibaraManager", isDirectory: true)
            .appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}

// MARK: - Small Icon Button

private struct SmallIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.appTextSecondary)
                .frame(width: 24, height: 24)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Date Extension

extension Date {
    func timeAgoDisplay() -> String {
        let seconds = Int(-timeIntervalSinceNow)
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        if seconds < 604800 { return "\(seconds / 86400)d ago" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: self)
    }
}
