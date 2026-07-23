import SwiftUI
import UniformTypeIdentifiers

struct CopibaraGridView: View {
    @Bindable var store: CopibaraStore
    let searchText: String
    @Binding var selectedItemIds: Set<Int>
    @Binding var lastClickedId: Int?
    @Binding var activeTypeFilter: ContentType?
    var onDoubleClick: ((CopibaraItem) -> Void)? = nil
    var onPasteItem: ((CopibaraItem) -> Void)? = nil

    @State private var collapsedSections: Set<String> = []
    @State private var typeOrder: [ContentType] = ContentType.allCases
    @State private var draggedType: ContentType? = nil

    // Gap sized so a card's coloured glow (8pt radius) has clearance on every side
    // instead of bleeding into its neighbour.
    private let columns = [
        GridItem(.adaptive(minimum: 190, maximum: 280), spacing: Spacing.lg)
    ]

    /// Whether multi-select mode is active (more than 1 item selected).
    private var isMultiSelect: Bool {
        selectedItemIds.count > 1
    }

    /// Items filtered by board, search, and content type.
    private var displayItems: [CopibaraItem] {
        let board = store.activeBoard
        var result = board == "all"
            ? store.items
            : store.items.filter { $0.boardId == board }
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { $0.matches(query) }
        }
        if let typeFilter = activeTypeFilter {
            result = result.filter { $0.type == typeFilter }
        }
        return result
    }

    var body: some View {
        let items = displayItems

        if items.isEmpty && searchText.isEmpty && activeTypeFilter == nil {
            emptyState
        } else {
            VStack(spacing: 0) {
                // Type filter pills
                typeFilterBar

                if items.isEmpty {
                    // Filtered empty state
                    filteredEmptyState
                } else {
                    let sections = DateGrouping.group(items)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(sections) { section in
                                sectionHeader(section)

                                if !collapsedSections.contains(section.id) {
                                    LazyVGrid(columns: columns, spacing: Spacing.lg) {
                                        ForEach(section.items) { item in
                                            CopibaraCardView(
                                                item: item,
                                                isSelected: selectedItemIds.contains(item.id),
                                                isMultiSelect: isMultiSelect,
                                                isYapivo: item.boardId == "yapivo",
                                                isForaged: item.capture != nil,
                                                onSelect: {
                                                    handleClick(item: item, items: items)
                                                },
                                                onCopy: { store.copyToClipboard(id: item.id) },
                                                onDelete: {
                                                    withAnimation(.easeInOut(duration: 0.2)) {
                                                        selectedItemIds.remove(item.id)
                                                        store.deleteItem(id: item.id)
                                                    }
                                                },
                                                onSaveImage: { store.exportImage(for: item.id) },
                                                onRemoveBackground: { store.removeBackground(id: item.id) },
                                                onAIUpscale: { mode in store.aiUpscale(id: item.id, mode: mode) },
                                                onDoubleClick: {
                                                    onDoubleClick?(item)
                                                }
                                            )
                                        }
                                    }
                                    .padding(.horizontal, Spacing.xl)
                                    .padding(.bottom, Spacing.lg)
                                }
                            }
                        }
                        .padding(.vertical, Spacing.xl)
                        .animation(.easeInOut(duration: 0.2), value: collapsedSections)
                    }
                    .scrollClipDisabled(false)
                }
            }
            .id(store.activeBoard)
        }
    }

    // MARK: - Type Filter Bar

    private var typeFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                TypePill(label: "All", icon: "square.grid.2x2", isActive: activeTypeFilter == nil) {
                    withAnimation(.easeInOut(duration: 0.15)) { activeTypeFilter = nil }
                }

                ForEach(typeOrder, id: \.self) { type in
                    TypePill(
                        label: type.label.capitalized,
                        icon: iconName(for: type),
                        isActive: activeTypeFilter == type
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            activeTypeFilter = activeTypeFilter == type ? nil : type
                        }
                    }
                    .opacity(draggedType == type ? 0.4 : 1.0)
                    .onDrag {
                        draggedType = type
                        return NSItemProvider(object: type.rawValue as NSString)
                    }
                    .onDrop(of: [.plainText], delegate: TypePillDropDelegate(
                        item: type,
                        items: $typeOrder,
                        draggedItem: $draggedType
                    ))
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.sm)
        }
        .background(Color.appBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.appBorder.opacity(0.5))
                .frame(height: 0.5)
        }
    }

    private func iconName(for type: ContentType) -> String {
        switch type {
        case .text:  return "doc.text"
        case .code:  return "chevron.left.forwardslash.chevron.right"
        case .link:  return "link"
        case .image: return "photo"
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ section: DateSection) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if collapsedSections.contains(section.id) {
                    collapsedSections.remove(section.id)
                } else {
                    collapsedSections.insert(section.id)
                }
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.appTextTertiary)
                    .rotationEffect(.degrees(
                        collapsedSections.contains(section.id) ? 0 : 90
                    ))
                    .animation(.easeInOut(duration: 0.2), value: collapsedSections.contains(section.id))

                Text(section.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appTextSecondary)

                Text("\(section.items.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.appTextTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.appSurface)
                    .clipShape(Capsule())

                Spacer()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Click Handling with Modifier Keys

    private func handleClick(item: CopibaraItem, items: [CopibaraItem]) {
        let modifiers = NSEvent.modifierFlags

        if modifiers.contains(.command) {
            if selectedItemIds.contains(item.id) {
                selectedItemIds.remove(item.id)
            } else {
                selectedItemIds.insert(item.id)
            }
            lastClickedId = item.id
        } else if modifiers.contains(.shift), let lastId = lastClickedId {
            if let startIdx = items.firstIndex(where: { $0.id == lastId }),
               let endIdx = items.firstIndex(where: { $0.id == item.id }) {
                let range = min(startIdx, endIdx)...max(startIdx, endIdx)
                for i in range {
                    selectedItemIds.insert(items[i].id)
                }
            }
        } else {
            onPasteItem?(item)
        }
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: Spacing.base) {
            Text("📋")
                .font(.system(size: 48))

            Text("Your clipboard is empty")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.appTextPrimary)

            Text("Copy text, links, or code — everything appears here automatically.")
                .font(.system(size: 13))
                .foregroundStyle(Color.appTextSecondary)
                .multilineTextAlignment(.center)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xxl)
    }

    private var filteredEmptyState: some View {
        VStack(spacing: Spacing.base) {
            Text("🔍")
                .font(.system(size: 40))

            Text("No results found")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.appTextPrimary)

            Text(activeTypeFilter != nil
                 ? "No \(activeTypeFilter!.label.lowercased()) items match your search."
                 : "Try a different search term.")
                .font(.system(size: 13))
                .foregroundStyle(Color.appTextSecondary)
                .multilineTextAlignment(.center)

            if activeTypeFilter != nil {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { activeTypeFilter = nil }
                } label: {
                    Text("Clear Filter")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.appPrimary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.xxl)
    }
}

// MARK: - Type Pill

private struct TypePill: View {
    let label: String
    let icon: String
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(label)
                    .font(.system(size: 11, weight: isActive ? .semibold : .medium))
            }
            .foregroundStyle(isActive ? .white : Color.appTextSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(isActive ? Color.appPrimary : (isHovering ? Color.appSurfaceHover : Color.appSurface))
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? Color.clear : Color.appBorder.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
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

// MARK: - Drag & Drop Delegate for Type Pills

private struct TypePillDropDelegate: DropDelegate {
    let item: ContentType
    @Binding var items: [ContentType]
    @Binding var draggedItem: ContentType?

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedItem, dragged != item else { return }
        guard let fromIndex = items.firstIndex(of: dragged),
              let toIndex = items.firstIndex(of: item) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            items.move(fromOffsets: IndexSet(integer: fromIndex),
                       toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
