import SwiftUI
import AppKit

struct CopibaraCardView: View {
    let item: CopibaraItem
    let isSelected: Bool
    let isMultiSelect: Bool
    let onSelect: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    var onSaveImage: (() -> Void)? = nil
    var onDoubleClick: (() -> Void)? = nil

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
        .background(Color.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl))
        .shadow(
            color: .black.opacity(0.06),
            radius: 4,
            y: 2
        )
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.xl)
                .stroke(
                    isSelected ? Color.appPrimary
                    : Color.appBorder.opacity(0.5),
                    lineWidth: isSelected ? 2 : 0.5
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: CornerRadius.xl))
        .drawingGroup()
        .onHover { isHovering = $0 }
        .onAppear {
            // Cache image once on appear, not on every render
            if item.type == .image && cachedImage == nil {
                cachedImage = loadItemImage()
            }
        }
        .onTapGesture(count: 2) {
            onDoubleClick?()
        }
        .onTapGesture(count: 1) {
            onSelect()
        }
        .contextMenu {
            Button("Copy to Clipboard") { onCopy() }
            if item.type == .image, let onSaveImage = onSaveImage {
                Button("Save Image") { onSaveImage() }
            }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    /// Load the image from ~/Library/Application Support/CopibaraManager/images/
    private func loadItemImage() -> NSImage? {
        guard let fileName = item.imageFileName else { return nil }
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let imagePath = appSupport
            .appendingPathComponent("CopibaraManager", isDirectory: true)
            .appendingPathComponent("images", isDirectory: true)
            .appendingPathComponent(fileName)
        return NSImage(contentsOf: imagePath)
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
