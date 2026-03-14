import SwiftUI

struct CopibaraGridView: View {
    @Bindable var store: CopibaraStore
    let searchText: String
    @Binding var selectedItemIds: Set<Int>
    @Binding var lastClickedId: Int?
    var onDoubleClick: ((CopibaraItem) -> Void)? = nil
    var onPasteItem: ((CopibaraItem) -> Void)? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 190, maximum: 280), spacing: Spacing.base)
    ]

    /// Whether multi-select mode is active (more than 1 item selected).
    private var isMultiSelect: Bool {
        selectedItemIds.count > 1
    }

    /// Explicitly compute filtered items so SwiftUI can track the dependency.
    private var displayItems: [CopibaraItem] {
        let board = store.activeBoard
        var result = board == "all"
            ? store.items
            : store.items.filter { $0.boardId == board }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.content.lowercased().contains(query) ||
                $0.type.label.lowercased().contains(query)
            }
        }
        return result
    }

    var body: some View {
        let items = displayItems

        if items.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Spacing.base) {
                    ForEach(items) { item in
                        CopibaraCardView(
                            item: item,
                            isSelected: selectedItemIds.contains(item.id),
                            isMultiSelect: isMultiSelect,
                            onSelect: {
                                handleClick(item: item, items: items)
                            },
                            onCopy: { store.copyToClipboard(id: item.id) },
                            onDelete: {
                                withAnimation {
                                    selectedItemIds.remove(item.id)
                                    store.deleteItem(id: item.id)
                                }
                            },
                            onSaveImage: { store.exportImage(for: item.id) },
                            onDoubleClick: {
                                onDoubleClick?(item)
                            }
                        )
                    }
                }
                .padding(Spacing.xl)
            }
            .id(store.activeBoard)
        }
    }

    // MARK: - Click Handling with Modifier Keys

    private func handleClick(item: CopibaraItem, items: [CopibaraItem]) {
        let modifiers = NSEvent.modifierFlags

        if modifiers.contains(.command) {
            // ⌘+Click: toggle item in/out of selection
            if selectedItemIds.contains(item.id) {
                selectedItemIds.remove(item.id)
            } else {
                selectedItemIds.insert(item.id)
            }
            lastClickedId = item.id
        } else if modifiers.contains(.shift), let lastId = lastClickedId {
            // ⇧+Click: range select from lastClicked to this item
            if let startIdx = items.firstIndex(where: { $0.id == lastId }),
               let endIdx = items.firstIndex(where: { $0.id == item.id }) {
                let range = min(startIdx, endIdx)...max(startIdx, endIdx)
                for i in range {
                    selectedItemIds.insert(items[i].id)
                }
            }
        } else {
            // Plain click: paste the item into the previously focused app
            onPasteItem?(item)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.base) {
            Text("📋")
                .font(.system(size: 48))

            Text(searchText.isEmpty ? "Your clipboard is empty" : "No results found")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.appTextPrimary)

            Text(searchText.isEmpty
                 ? "Copy text, links, or code — everything appears here automatically."
                 : "Try a different search term.")
                .font(.system(size: 13))
                .foregroundStyle(Color.appTextSecondary)
                .multilineTextAlignment(.center)

            if searchText.isEmpty {
                HStack(spacing: 4) {
                    Text("Press")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appTextTertiary)
                    KeyboardKey("⌘")
                    KeyboardKey("V")
                    Text("to paste content")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appTextTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xxl)
    }
}

// MARK: - Keyboard Key Badge

private struct KeyboardKey: View {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.appTextSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.appSurface)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.appBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
    }
}
