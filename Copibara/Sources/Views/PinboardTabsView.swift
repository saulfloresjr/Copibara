import SwiftUI
import UniformTypeIdentifiers

struct PinboardTabsView: View {
    @Bindable var store: CopibaraStore
    @Binding var showNewBoardSheet: Bool
    @Binding var boardToDelete: Pinboard?

    @State private var draggedBoard: Pinboard?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                // "All" tab — always first, not draggable
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
                        Button(role: .destructive) {
                            boardToDelete = board
                        } label: {
                            Label("Delete Board", systemImage: "trash")
                        }
                    }
                    .onDrag {
                        draggedBoard = board
                        return NSItemProvider(object: board.id as NSString)
                    }
                    .onDrop(of: [.plainText], delegate: BoardDropDelegate(
                        board: board,
                        boards: $store.pinboards,
                        draggedBoard: $draggedBoard,
                        onReorder: { store.save() }
                    ))
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

// MARK: - Board Drop Delegate

private struct BoardDropDelegate: DropDelegate {
    let board: Pinboard
    @Binding var boards: [Pinboard]
    @Binding var draggedBoard: Pinboard?
    let onReorder: () -> Void

    func performDrop(info: DropInfo) -> Bool {
        draggedBoard = nil
        onReorder()
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedBoard,
              dragged.id != board.id,
              let fromIndex = boards.firstIndex(where: { $0.id == dragged.id }),
              let toIndex = boards.firstIndex(where: { $0.id == board.id })
        else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            boards.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
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
        .help("Drag to reorder · Right-click to delete")
    }
}
