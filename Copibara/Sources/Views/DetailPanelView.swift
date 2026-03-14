import SwiftUI

struct DetailPanelView: View {
    let item: CopibaraItem
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void
    var onSaveImage: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Preview")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.appTextPrimary)

                Spacer()

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
                    // Full content preview
                    if item.type == .code {
                        Text(item.content)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color.appTextPrimary)
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.appBackground)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                    } else if item.type == .image {
                        if let nsImage = loadItemImage() {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                        } else {
                            Text(item.content)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.appTextPrimary)
                        }
                    } else {
                        Text(item.content)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.appTextPrimary)
                            .textSelection(.enabled)
                    }

                    Divider()

                    // Metadata
                    VStack(spacing: Spacing.sm) {
                        MetadataRow(label: "Type", value: "\(item.type.emoji) \(item.type.label)")
                        MetadataRow(label: "Size", value: formatSize(item.size))
                        MetadataRow(label: "Copied", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))
                        MetadataRow(label: "Board", value: item.boardId.capitalized)
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
