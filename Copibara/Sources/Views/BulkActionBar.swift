import SwiftUI

/// Compact action bar shown when multiple items are selected.
struct BulkActionBar: View {
    let selectedCount: Int
    let onCopyAll: () -> Void
    let onDeleteAll: () -> Void
    let onDeselectAll: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("\(selectedCount) selected")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.appTextPrimary)

                Spacer()

                Button(action: onDeselectAll) {
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

            Spacer()

            // Bulk icon
            VStack(spacing: Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.appPrimary)

                Text("\(selectedCount) items selected")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appTextSecondary)

                Text("Use the actions below\nto manage your selection.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appTextTertiary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Divider()

            // Actions
            VStack(spacing: Spacing.sm) {
                Button(action: onCopyAll) {
                    Label("Copy All", systemImage: "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .foregroundStyle(.white)
                        .background(Color.appPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                }
                .buttonStyle(.plain)

                Button(action: onDeleteAll) {
                    Label("Delete Selected", systemImage: "trash")
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.sm)
                        .foregroundStyle(Color.appTextSecondary)
                        .background(Color.appSurfaceHover)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                }
                .buttonStyle(.plain)
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
