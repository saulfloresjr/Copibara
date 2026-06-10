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
    @State private var boardToClear: Pinboard?
    @State private var showClearAllBoardsConfirm = false
    @State private var activeTypeFilter: ContentType? = nil
    @State private var keyMonitor: Any?
    @State private var globalKeyMonitor: Any?

    /// Whether any overlay modal is showing.
    private var isModalOpen: Bool {
        showNewBoardSheet || showAddItemSheet || showClearConfirm || boardToDelete != nil || boardToClear != nil || showClearAllBoardsConfirm
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
                    activeTypeFilter: $activeTypeFilter,
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

            // Confirmation: clear a specific board (from All menu)
            if let board = boardToClear {
                let count = store.items.filter { $0.boardId == board.id }.count
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { boardToClear = nil }

                VStack(spacing: Spacing.base) {
                    Text("Clear \"\(board.name)\"?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appTextPrimary)

                    Text("This will delete all \(count) items in \(board.name). This can't be undone.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appTextSecondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: Spacing.sm) {
                        Button("Cancel") {
                            boardToClear = nil
                        }

                        Button("Clear \(board.name)") {
                            store.clearBoard(id: board.id)
                            boardToClear = nil
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .padding(Spacing.xl)
                .frame(width: 300)
                .background(Color.appSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.3), radius: 16, y: 4)
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            // Confirmation: clear EVERYTHING (nuclear option)
            if showClearAllBoardsConfirm {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { showClearAllBoardsConfirm = false }

                VStack(spacing: Spacing.base) {
                    Text("⚠️ Clear Everything?")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.appTextPrimary)

                    Text("This will permanently delete all \(store.items.count) items across every board. This cannot be undone.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appTextSecondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: Spacing.sm) {
                        Button("Cancel") {
                            showClearAllBoardsConfirm = false
                        }

                        Button("Delete Everything") {
                            store.clearAllBoards()
                            showClearAllBoardsConfirm = false
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                .padding(Spacing.xl)
                .frame(width: 320)
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
        .animation(.easeInOut(duration: 0.2), value: boardToClear?.id)
        .animation(.easeInOut(duration: 0.2), value: showClearAllBoardsConfirm)
        .background(Color.appBackground)
        .frame(width: 720, height: 520)
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
            // Aggressively force the MenuBarExtra panel to become key window
            // for keyboard events — run repeatedly to survive focus changes
            for delay in [0.05, 0.15, 0.3] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    if let window = NSApp.windows.first(where: { $0.isVisible && $0.level.rawValue > 0 }) {
                        window.makeKey()
                    }
                }
            }
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Spacing.base) {
            // Logo
            HStack(spacing: Spacing.sm) {
                if let icon = NSImage(named: "AppIcon") {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                } else {
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
                }

                Text("Copibara")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.appTextPrimary)
            }

            // Search
            SearchBar(text: $searchText)

            // Actions
            HStack(spacing: Spacing.sm) {
                if store.activeBoard == "all" {
                    // "All" board: show a menu with per-board clear + nuclear option
                    Menu {
                        Section("Clear Board") {
                            ForEach(store.pinboards, id: \.id) { board in
                                let count = store.items.filter { $0.boardId == board.id }.count
                                Button {
                                    boardToClear = board
                                } label: {
                                    Label("\(board.icon) \(board.name) (\(count))", systemImage: "xmark.circle")
                                }
                                .disabled(count == 0)
                            }
                        }
                        Divider()
                        Button(role: .destructive) {
                            showClearAllBoardsConfirm = true
                        } label: {
                            Label("Clear Everything (\(store.items.count))", systemImage: "trash.fill")
                        }
                        .disabled(store.items.isEmpty)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.appTextSecondary)
                            .frame(width: 32, height: 32)
                            .background(Color.appSurfaceHover)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 32, height: 32)
                    .help("Clear boards…")
                } else {
                    // Specific board: single clear button
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
                }

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

    // MARK: - NSEvent Key Monitor (Escape & Shift+Tab)

    private func installKeyMonitor() {
        removeKeyMonitor() // prevent duplicates

        // Local monitor: fires when this app is active and a window has key status
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch Int(event.keyCode) {
            case 53: // Escape
                return handleEscapeEvent()
            case 48: // Tab
                if mods.contains(.shift) {
                    handleShiftTab()
                    return nil  // consume the event
                }
                // Plain Tab: cycle boards
                handleTab()
                return nil  // consume — prevent focus navigation to search bar
            default:
                return event
            }
        }

        // Global monitor: catches Escape even when the MenuBarExtra panel
        // isn't key (e.g. focus went to another element or a child menu)
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [self] event in
            if Int(event.keyCode) == 53 { // Escape
                DispatchQueue.main.async {
                    _ = self.handleEscapeEvent()
                }
            }
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = globalKeyMonitor {
            NSEvent.removeMonitor(monitor)
            globalKeyMonitor = nil
        }
    }

    /// Handles Escape key with priority: modals → selection → close window.
    /// Returns nil if handled, the event otherwise.
    private func handleEscapeEvent() -> NSEvent? {
        // Force-resign first responder so the SearchBar's @FocusState
        // doesn't eat this Escape before we can act on it.
        // Without this, the user needs a double-tap: once to unfocus
        // the TextField, once to reach our handler.
        if let window = NSApp.keyWindow {
            window.makeFirstResponder(nil)
        }

        if boardToClear != nil {
            boardToClear = nil
            return nil
        }
        if showClearAllBoardsConfirm {
            showClearAllBoardsConfirm = false
            return nil
        }
        if boardToDelete != nil {
            boardToDelete = nil
            return nil
        }
        if showClearConfirm {
            showClearConfirm = false
            return nil
        }
        if showNewBoardSheet {
            showNewBoardSheet = false
            return nil
        }
        if showAddItemSheet {
            showAddItemSheet = false
            return nil
        }
        // Clear search text if present
        if !searchText.isEmpty {
            searchText = ""
            return nil
        }
        if !selectedItemIds.isEmpty {
            withAnimation { selectedItemIds.removeAll(); lastClickedId = nil }
            return nil
        }
        // Clear type filter if active
        if activeTypeFilter != nil {
            activeTypeFilter = nil
            return nil
        }
        // Nothing open — dismiss the MenuBarExtra window
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.className.contains("StatusBarWindow") || ($0.isVisible && $0.level.rawValue > 0) }) {
            window.orderOut(nil)
        }
        NSApp.deactivate()
        return nil
    }

    /// Cycles to the next board: all → board1 → board2 → … → all
    private func handleTab() {
        guard !isModalOpen else { return }
        let allTabs = ["all"] + store.pinboards.map(\.id)
        guard let idx = allTabs.firstIndex(of: store.activeBoard) else { return }
        let nextIdx = (idx + 1) % allTabs.count
        store.activeBoard = allTabs[nextIdx]
        selectedItemIds.removeAll()
    }

    /// Cycles the type filter: nil → .text → .code → .link → .image → nil
    private func handleShiftTab() {
        guard !isModalOpen else { return }
        let allTypes = ContentType.allCases
        if let current = activeTypeFilter,
           let idx = allTypes.firstIndex(of: current) {
            let nextIdx = idx + 1
            activeTypeFilter = nextIdx < allTypes.count ? allTypes[nextIdx] : nil
        } else {
            activeTypeFilter = allTypes.first
        }
        selectedItemIds.removeAll()
    }
}
