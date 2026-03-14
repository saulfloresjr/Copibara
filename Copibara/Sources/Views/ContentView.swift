import SwiftUI

struct ContentView: View {
    @Bindable var store: CopibaraStore
    var onPasteItem: ((CopibaraItem) -> Void)? = nil

    @State private var searchText = ""
    @State private var selectedItemIds: Set<Int> = []
    @State private var lastClickedId: Int?
    @State private var showNewBoardSheet = false
    @State private var showAddItemSheet = false
    @State private var showClearConfirm = false
    @State private var boardToDelete: Pinboard?

    /// Whether any overlay modal is showing.
    private var isModalOpen: Bool {
        showNewBoardSheet || showAddItemSheet || showClearConfirm || boardToDelete != nil
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header
                header

                // Pinboard Tabs
                PinboardTabsView(store: store, showNewBoardSheet: $showNewBoardSheet, boardToDelete: $boardToDelete)

                // Main Area
                CopibaraGridView(
                    store: store,
                    searchText: searchText,
                    selectedItemIds: $selectedItemIds,
                    lastClickedId: $lastClickedId,
                    onDoubleClick: { item in
                        onPasteItem?(item)
                    },
                    onPasteItem: { item in
                        onPasteItem?(item)
                    }
                )
                .overlay(alignment: .trailing) {
                    // Detail panel overlays the grid instead of resizing it
                    if selectedItemIds.count == 1,
                       let id = selectedItemIds.first,
                       let item = store.item(for: id) {
                        DetailPanelView(
                            item: item,
                            onCopy: {
                                store.copyToClipboard(id: id)
                            },
                            onDelete: {
                                selectedItemIds.removeAll()
                                store.deleteItem(id: id)
                            },
                            onClose: {
                                selectedItemIds.removeAll()
                            },
                            onSaveImage: {
                                store.exportImage(for: id)
                            }
                        )
                    } else if selectedItemIds.count > 1 {
                        BulkActionBar(
                            selectedCount: selectedItemIds.count,
                            onCopyAll: {
                                store.copyItemsToClipboard(ids: selectedItemIds)
                            },
                            onDeleteAll: {
                                store.deleteItems(ids: selectedItemIds)
                                selectedItemIds.removeAll()
                            },
                            onDeselectAll: {
                                selectedItemIds.removeAll()
                                lastClickedId = nil
                            }
                        )
                    }
                }
            }

            // Inline overlay modals (avoids .sheet() crash in MenuBarExtra)
            if showNewBoardSheet {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showNewBoardSheet = false }

                NewPinboardSheet(isPresented: $showNewBoardSheet) { name, icon in
                    store.addPinboard(name: name, icon: icon)
                    store.activeBoard = store.pinboards.last?.id ?? "clipboard"
                }
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 4)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            if showAddItemSheet {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showAddItemSheet = false }

                AddItemSheet(isPresented: $showAddItemSheet) { content in
                    store.addItem(content: content)
                }
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 4)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            if showClearConfirm {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showClearConfirm = false }

                VStack(spacing: Spacing.base) {
                    Text("Clear All Items?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appTextPrimary)

                    Text("This will delete all items in the current board. This can't be undone.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appTextSecondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: Spacing.sm) {
                        Button("Cancel") {
                            showClearConfirm = false
                        }

                        Button("Clear All") {
                            store.clearAll()
                            showClearConfirm = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .padding(Spacing.xl)
                .frame(width: 280)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 4)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            if let board = boardToDelete {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { boardToDelete = nil }

                VStack(spacing: Spacing.base) {
                    Text("Delete \"\(board.name)\"?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appTextPrimary)

                    Text("All items in this board will be permanently deleted.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appTextSecondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: Spacing.sm) {
                        Button("Cancel") {
                            boardToDelete = nil
                        }

                        Button("Delete") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                store.deletePinboard(id: board.id)
                            }
                            boardToDelete = nil
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .padding(Spacing.xl)
                .frame(width: 280)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 4)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showNewBoardSheet)
        .animation(.easeInOut(duration: 0.2), value: showAddItemSheet)
        .animation(.easeInOut(duration: 0.2), value: showClearConfirm)
        .animation(.easeInOut(duration: 0.2), value: boardToDelete?.id)
        .background(Color.appBackground)
        .frame(width: 720, height: 520)
        // MARK: - Keyboard Shortcuts
        .onKeyPress(.escape) {
            if boardToDelete != nil {
                boardToDelete = nil
                return .handled
            }
            if showClearConfirm {
                showClearConfirm = false
                return .handled
            }
            if showNewBoardSheet {
                showNewBoardSheet = false
                return .handled
            }
            if showAddItemSheet {
                showAddItemSheet = false
                return .handled
            }
            if !selectedItemIds.isEmpty {
                withAnimation { selectedItemIds.removeAll(); lastClickedId = nil }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.return) {
            // Enter: paste the single selected item
            guard !isModalOpen else { return .ignored }
            guard selectedItemIds.count == 1,
                  let id = selectedItemIds.first,
                  let item = store.item(for: id) else {
                // If nothing selected, select+paste the first item
                let items = store.filteredItems(search: searchText)
                guard let first = items.first else { return .ignored }
                onPasteItem?(first)
                return .handled
            }
            onPasteItem?(item)
            return .handled
        }
        .onKeyPress(.downArrow) {
            // ↓ move selection to next item
            guard !isModalOpen else { return .ignored }
            let items = store.filteredItems(search: searchText)
            guard !items.isEmpty else { return .ignored }

            if selectedItemIds.isEmpty {
                // Nothing selected → select first item
                let firstId = items[0].id
                withAnimation(.easeInOut(duration: 0.1)) {
                    selectedItemIds = [firstId]
                    lastClickedId = firstId
                }
            } else if selectedItemIds.count == 1,
                      let currentId = selectedItemIds.first,
                      let currentIdx = items.firstIndex(where: { $0.id == currentId }),
                      currentIdx < items.count - 1 {
                // Move to next item
                let nextId = items[currentIdx + 1].id
                withAnimation(.easeInOut(duration: 0.1)) {
                    selectedItemIds = [nextId]
                    lastClickedId = nextId
                }
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            // ↑ move selection to previous item
            guard !isModalOpen else { return .ignored }
            let items = store.filteredItems(search: searchText)
            guard !items.isEmpty else { return .ignored }

            if selectedItemIds.isEmpty {
                // Nothing selected → select last item
                let lastId = items[items.count - 1].id
                withAnimation(.easeInOut(duration: 0.1)) {
                    selectedItemIds = [lastId]
                    lastClickedId = lastId
                }
            } else if selectedItemIds.count == 1,
                      let currentId = selectedItemIds.first,
                      let currentIdx = items.firstIndex(where: { $0.id == currentId }),
                      currentIdx > 0 {
                // Move to previous item
                let prevId = items[currentIdx - 1].id
                withAnimation(.easeInOut(duration: 0.1)) {
                    selectedItemIds = [prevId]
                    lastClickedId = prevId
                }
            }
            return .handled
        }
        .onKeyPress(.tab) {
            // Tab → next board
            guard !isModalOpen else { return .ignored }
            let allTabs = ["all"] + store.pinboards.map(\.id)
            guard let idx = allTabs.firstIndex(of: store.activeBoard) else { return .ignored }
            let nextIdx = (idx + 1) % allTabs.count
            withAnimation(.easeInOut(duration: 0.1)) {
                store.activeBoard = allTabs[nextIdx]
                selectedItemIds.removeAll()
            }
            return .handled
        }
        .onKeyPress(characters: .alphanumerics) { press in
            // ⌘A: select all visible items
            if press.characters == "a" && NSEvent.modifierFlags.contains(.command) {
                guard !isModalOpen else { return .ignored }
                let visibleItems = store.filteredItems(search: searchText)
                withAnimation(.easeInOut(duration: 0.15)) {
                    selectedItemIds = Set(visibleItems.map(\.id))
                }
                return .handled
            }
            return .ignored
        }
        .focusable()
        .onAppear {
            // Force the MenuBarExtra panel to become key window for keyboard events
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let window = NSApp.windows.first(where: { $0.isVisible && $0.level.rawValue > 0 }) {
                    window.makeKey()
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Spacing.base) {
            // Logo
            HStack(spacing: Spacing.sm) {
                Text("C")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        LinearGradient(
                            colors: [Color.appPrimary, Color.appPrimaryHover],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7))

                Text("Copibara")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.appTextPrimary)
            }

            // Search
            SearchBar(text: $searchText)

            // Actions
            HStack(spacing: Spacing.sm) {
                Button {
                    showClearConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appTextSecondary)
                        .frame(width: 32, height: 32)
                        .background(Color.appSurfaceHover)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                }
                .buttonStyle(.plain)
                .help("Clear All")

                Button {
                    showAddItemSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Add")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.appPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                }
                .buttonStyle(.plain)
                .help("Add Item")

                // Quit
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.appTextTertiary)
                        .frame(width: 32, height: 32)
                        .background(Color.appSurfaceHover)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                }
                .buttonStyle(.plain)
                .help("Quit Copibara")
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
        .background(Color.appSurface)
        .overlay(alignment: .bottom) { Divider() }
    }
}
