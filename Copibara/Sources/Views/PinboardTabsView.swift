import SwiftUI

struct PinboardTabsView: View {
    @Bindable var store: CopibaraStore
    @Binding var showNewBoardSheet: Bool
    @Binding var boardToDelete: Pinboard?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                // "All" tab — shows items from every board
                TabButton(
                    label: "🗂 All",
                    isActive: store.activeBoard == "all"
                ) {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        store.activeBoard = "all"
                    }
                }

                ForEach(store.pinboards) { board in
                    TabButton(
                        label: "\(board.icon) \(board.name)",
                        isActive: store.activeBoard == board.id
                    ) {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            store.activeBoard = board.id
                        }
                    }
                    .contextMenu {
                        if !board.isDefault {
                            Button(role: .destructive) {
                                boardToDelete = board
                            } label: {
                                Label("Delete Board", systemImage: "trash")
                            }
                        }
                    }
                }

                // Add pinboard button
                Button {
                    showNewBoardSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.appTextTertiary)
                        .frame(width: 26, height: 26)
                        .background(Color.appSurface)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.appBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("New Pinboard")
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.sm)
        }
        .background(Color.appSurface)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

// MARK: - Tab Button

private struct TabButton: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? .white : Color.appTextSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(isActive ? Color.appPrimary : (isHovering ? Color.appSurfaceHover : Color.clear))
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Use ← → to switch · Right-click to delete")
    }
}
